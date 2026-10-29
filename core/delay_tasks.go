package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
)

const maxDelayTasks = 150 // 50 executing plus at most 100 waiting

type delayTask struct {
	cancel           context.CancelFunc
	reason           string // protected by delayTasksMu
	historyCommitted bool   // commit is the completion point for explicit UI tests
	owner            *catalogOwner
	catalog          *catalogEntry
}

func (task *delayTask) beginHistoryCommit(ctx context.Context) (func(), bool) {
	delayTasksMu.Lock()
	if task.reason != "" || ctx.Err() != nil {
		delayTasksMu.Unlock()
		return nil, false
	}
	return func() { task.historyCommitted = true; delayTasksMu.Unlock() }, true
}

var (
	delayTaskSlots   = make(chan struct{}, maxDelayTasks)
	delayTasksMu     sync.Mutex
	delayTasks       = map[string]*delayTask{}
	delaySequence    atomic.Uint64
	lookupDelayProxy = func(name string) constant.Proxy { return proxiesWithProviders()[name] }
)

func cancelDelayTask(id, reason string) bool {
	return cancelDelayTaskOwned(nil, id, reason)
}

func delayTaskKey(owner *catalogOwner, id string) string {
	if owner == nil {
		return id
	}
	return fmt.Sprintf("owner-%d/%s", owner.id, id)
}

func cancelDelayTaskOwned(owner *catalogOwner, id, reason string) bool {
	delayTasksMu.Lock()
	defer delayTasksMu.Unlock()
	task := delayTasks[delayTaskKey(owner, id)]
	if task == nil || task.historyCommitted {
		return false
	}
	if task.reason == "" {
		task.reason = reason
	}
	task.cancel()
	return true
}

func cancelAllDelayTasks(reason string) {
	cancelMatchingDelayTasks(reason, func(*delayTask) bool { return true })
}

func cancelOwnedDelayTasks(owner *catalogOwner, reason string) {
	cancelMatchingDelayTasks(reason, func(task *delayTask) bool { return task.owner == owner })
}

// Lock ordering is catalogMu -> delayTasksMu; the runner never holds the
// history/cancellation mutex while acquiring or returning a catalog reference.
func cancelCatalogDelayTasksLocked(entry *catalogEntry, reason string) {
	cancelMatchingDelayTasks(reason, func(task *delayTask) bool { return task.catalog == entry })
}

func cancelMatchingDelayTasks(reason string, matches func(*delayTask) bool) {
	delayTasksMu.Lock()
	defer delayTasksMu.Unlock()
	for _, task := range delayTasks {
		if task.historyCommitted || !matches(task) {
			continue
		}
		if task.reason == "" {
			task.reason = reason
		}
		task.cancel()
	}
}

func handleAsyncTestDelay(paramsString string, fn func(string)) {
	handleAsyncTestDelayOwned(paramsString, nil, fn)
}

func handleAsyncTestDelayOwned(paramsString string, owner *catalogOwner, fn func(string)) {
	var params TestDelayParams
	if err := json.Unmarshal([]byte(paramsString), &params); err != nil || params.ProxyName == "" {
		data, _ := json.Marshal(Delay{Value: -1, Reason: "invalidParameters"})
		fn(string(data))
		return
	}
	runDelayTask(params, func(ctx context.Context) (constant.Proxy, string, func()) {
		if runLock.LockContext(ctx) != nil {
			return nil, "deadlineExceeded", nil
		}
		proxy := lookupDelayProxy(params.ProxyName)
		runLock.Unlock()
		if proxy == nil {
			return nil, "notFound", nil
		}
		return proxy, "", nil
	}, fn, params.RequestID == "", owner, nil)
}

func runDelayTask(params TestDelayParams, lookup func(context.Context) (constant.Proxy, string, func()), fn func(string), broadcast bool, owner *catalogOwner, entry *catalogEntry) {
	started := time.Now()
	result := Delay{Value: -1}
	respond := func() { data, _ := json.Marshal(result); fn(string(data)) }
	result.Name, result.Url = params.ProxyName, params.TestUrl
	if result.Url == "" {
		result.Url = "https://www.gstatic.com/generate_204"
	}
	if params.Timeout <= 0 {
		params.Timeout = 1
	}
	if params.Timeout > 60000 {
		params.Timeout = 60000
	}
	// Admission happens before creating a goroutine. A semaphore alone only
	// bounds execution and still retains one goroutine per waiting request.
	select {
	case delayTaskSlots <- struct{}{}:
	default:
		result.Reason = "overloaded"
		respond()
		return
	}
	id := params.RequestID
	if id == "" {
		id = fmt.Sprintf("legacy-%d", delaySequence.Add(1))
	}
	id = delayTaskKey(owner, id)
	ctx, cancel := context.WithDeadline(context.Background(), started.Add(time.Duration(params.Timeout)*time.Millisecond))
	task := &delayTask{cancel: cancel, owner: owner, catalog: entry}
	// Linearize registration with disconnect/release, including a request whose
	// action goroutine did not begin until its old connection was already closed.
	catalogMu.RLock()
	if owner != nil && owner.closed || entry != nil && (entry.retired || catalogStopped) {
		catalogMu.RUnlock()
		cancel()
		<-delayTaskSlots
		result.Reason = "sessionClosed"
		if entry != nil {
			result.Reason = "catalogNotFound"
		}
		respond()
		return
	}
	delayTasksMu.Lock()
	if delayTasks[id] != nil {
		delayTasksMu.Unlock()
		catalogMu.RUnlock()
		cancel()
		<-delayTaskSlots
		result.Reason = "duplicateRequest"
		respond()
		return
	}
	delayTasks[id] = task
	delayTasksMu.Unlock()
	catalogMu.RUnlock()
	if params.RequestID != "" {
		ctx = adapter.WithURLTestHistoryGuard(ctx, func() (func(), bool) { return task.beginHistoryCommit(ctx) })
	}
	go func() {
		err := testDelaySem.Acquire(ctx, 1)
		if err == nil {
			func() {
				defer testDelaySem.Release(1)
				if ctx.Err() != nil {
					return
				}
				proxy, reason, release := lookup(ctx)
				if release != nil {
					defer release()
				}
				if proxy == nil {
					result.Reason = reason
					return
				}
				expected, _ := utils.NewUnsignedRanges[uint16]("")
				delay, testErr := proxy.URLTest(ctx, result.Url, expected)
				if testErr == nil && delay != 0 {
					result.Value = int32(delay)
				} else {
					result.Reason = "testFailed"
				}
			}()
		}
		// Decide completion under the same lock as cancellation; one request
		// has exactly one completion and no retained cancel function afterwards.
		delayTasksMu.Lock()
		if task.reason != "" {
			result.Value, result.Reason = -1, task.reason
		} else if ctx.Err() != nil && !task.historyCommitted {
			result.Value, result.Reason = -1, "deadlineExceeded"
		}
		delete(delayTasks, id)
		delayTasksMu.Unlock()
		cancel()
		<-delayTaskSlots
		// Request-id callers own their result generation. Emitting a second,
		// uncorrelated stream update could resurrect a cancelled Dart batch.
		if result.Value > 0 && broadcast {
			sendMessage(Message{Type: DelayMessage, Data: &result})
		}
		respond()
	}()
}
