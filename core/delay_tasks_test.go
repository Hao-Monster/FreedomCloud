package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
	"runtime"
	"sync/atomic"
	"testing"
	"time"
)

func TestDelayAdmissionAndQueueDeadlineAreBounded(t *testing.T) {
	if err := testDelaySem.Acquire(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	const requests = 1000
	done := make(chan string, requests)
	before := runtime.NumGoroutine()
	t.Cleanup(func() {
		testDelaySem.Release(50)
		deadline := time.NewTimer(2 * time.Second)
		defer deadline.Stop()
		for len(done) < requests {
			select {
			case <-deadline.C:
				return
			case <-time.After(time.Millisecond):
			}
		}
	})
	for i := 0; i < requests; i++ {
		handleAsyncTestDelay(`{"proxy-name":"__missing__","timeout":30}`, func(value string) { done <- value })
	}
	if retained := runtime.NumGoroutine() - before; retained > 160 {
		t.Errorf("admission retained %d goroutines for a 150 task budget", retained)
	}
	deadline := time.NewTimer(time.Second)
	defer deadline.Stop()
	for len(done) != requests {
		select {
		case <-deadline.C:
			t.Fatalf("queue timeout did not complete all requests: %d/%d", len(done), requests)
		case <-time.After(time.Millisecond):
		}
	}
}

type blockingDelayProxy struct {
	constant.Proxy
	started chan struct{}
	active  *atomic.Int64
}

func (p *blockingDelayProxy) URLTest(ctx context.Context, _ string, _ utils.IntRanges[uint16]) (uint16, error) {
	p.active.Add(1)
	defer p.active.Add(-1)
	// Queued work may start while cancellation walks the registered tasks.
	// A full notification channel must not prevent the fake from cancelling.
	select {
	case p.started <- struct{}{}:
	case <-ctx.Done():
		return 0, ctx.Err()
	}
	<-ctx.Done()
	return 0, ctx.Err()
}

func TestDelayRunningAndQueuedCancellationReleasesAllResources(t *testing.T) {
	started := make(chan struct{}, 50)
	var active atomic.Int64
	original := lookupDelayProxy
	lookupDelayProxy = func(string) constant.Proxy { return &blockingDelayProxy{started: started, active: &active} }
	done := make(chan Delay, 150)
	allDone := make(chan struct{})
	var remaining atomic.Int32
	remaining.Store(150)
	t.Cleanup(func() {
		cancelAllDelayTasks("cancelled")
		select {
		case <-allDone:
		case <-time.After(2 * time.Second):
			t.Error("cancelled task cleanup did not finish")
		}
		lookupDelayProxy = original
	})
	for i := 0; i < 150; i++ {
		handleAsyncTestDelay(fmt.Sprintf(`{"request-id":"running-%d","proxy-name":"synthetic","timeout":5000}`, i), func(value string) {
			var d Delay
			_ = json.Unmarshal([]byte(value), &d)
			done <- d
			if remaining.Add(-1) == 0 {
				close(allDone)
			}
		})
	}
	for i := 0; i < 50; i++ {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("execution slots did not fill")
		}
	}
	if active.Load() != 50 {
		t.Fatal("execution budget was not enforced")
	}
	cancelAllDelayTasks("configChanged")
	for i := 0; i < 150; i++ {
		select {
		case result := <-done:
			if result.Reason != "configChanged" {
				t.Fatal(result.Reason)
			}
		case <-time.After(time.Second):
			t.Fatal("running or queued task retained")
		}
	}
	if active.Load() != 0 || len(delayTaskSlots) != 0 {
		t.Fatal("cancelled tasks retained execution resources")
	}
}

func TestDelayHistoryCommitLinearizesCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	task := &delayTask{cancel: cancel}
	delayTasksMu.Lock()
	delayTasks["committing"] = task
	delayTasksMu.Unlock()
	t.Cleanup(func() { delayTasksMu.Lock(); delete(delayTasks, "committing"); delayTasksMu.Unlock() })
	release, allowed := task.beginHistoryCommit(ctx)
	if !allowed {
		t.Fatal("valid history commit rejected")
	}
	done := make(chan bool, 1)
	go func() { done <- cancelDelayTask("committing", "cancelled") }()
	release()
	if <-done {
		t.Fatal("completed history was later classified as cancelled")
	}
	if ctx.Err() != nil {
		t.Fatal("completed history context was cancelled")
	}
	other := &delayTask{cancel: cancel, reason: "cancelled"}
	if _, allowed := other.beginHistoryCommit(ctx); allowed {
		t.Fatal("cancelled task could commit history")
	}
}

func TestDelayCancellationAndDuplicateRequest(t *testing.T) {
	if err := testDelaySem.Acquire(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	defer testDelaySem.Release(50)
	done := make(chan Delay, 3)
	callback := func(value string) { var result Delay; _ = json.Unmarshal([]byte(value), &result); done <- result }
	params := `{"request-id":"cancel-audit","proxy-name":"__missing__","timeout":5000}`
	handleAsyncTestDelay(params, callback)
	handleAsyncTestDelay(params, callback)
	if !cancelDelayTask("cancel-audit", "cancelled") {
		t.Fatal("request not registered")
	}
	seen := map[string]bool{}
	for i := 0; i < 2; i++ {
		select {
		case result := <-done:
			seen[result.Reason] = true
		case <-time.After(time.Second):
			t.Fatal("cancellation did not complete")
		}
	}
	if !seen["cancelled"] || !seen["duplicateRequest"] {
		t.Fatalf("unexpected results: %v", seen)
	}
	if cancelDelayTask("cancel-audit", "cancelled") {
		t.Fatal("completed request retained")
	}
}

func TestDelayDeadlineIncludesConfigurationLock(t *testing.T) {
	runLock.Lock()
	defer runLock.Unlock()
	done := make(chan string, 1)
	handleAsyncTestDelay(`{"proxy-name":"__missing__","timeout":20}`, func(value string) { done <- value })
	select {
	case value := <-done:
		var result Delay
		_ = json.Unmarshal([]byte(value), &result)
		if result.Reason != "deadlineExceeded" {
			t.Fatal(value)
		}
	case <-time.After(time.Second):
		t.Fatal("configuration lock escaped overall deadline")
	}
}

func TestDelayGenerationCancellationAndLegacyCompletion(t *testing.T) {
	if err := testDelaySem.Acquire(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	done := make(chan string, 1)
	handleAsyncTestDelay(`{"proxy-name":"__missing__","timeout":5000}`, func(value string) { done <- value })
	cancelAllDelayTasks("configChanged")
	select {
	case value := <-done:
		var result Delay
		_ = json.Unmarshal([]byte(value), &result)
		if result.Reason != "configChanged" {
			t.Fatal(value)
		}
	case <-time.After(time.Second):
		t.Fatal("generation cancellation did not release queued work")
	}
	testDelaySem.Release(50)
	handleAsyncTestDelay(`{"proxy-name":"__missing__","timeout":100}`, func(value string) { done <- value })
	select {
	case value := <-done:
		var result Delay
		_ = json.Unmarshal([]byte(value), &result)
		if result.Reason != "notFound" {
			t.Fatal(value)
		}
	case <-time.After(time.Second):
		t.Fatal("legacy request did not complete")
	}
}
