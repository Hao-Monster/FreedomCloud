package main

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
)

func TestRetiredResourceLateLeaseReclaimsAfterDrainTimeout(t *testing.T) {
	baseline := pendingRetiredResources()
	var freed atomic.Int64
	r := newRetiredResource(func() { freed.Add(1) })
	lease, ok := r.Acquire()
	if !ok {
		t.Fatal("live resource rejected a lease")
	}
	r.Retire()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := r.Wait(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("drain must be bounded: %v", err)
	}
	if freed.Load() != 0 || pendingRetiredResources() != baseline+1 {
		t.Fatal("timeout released an in-use resource or lost the retired record")
	}
	if _, ok := r.Acquire(); ok {
		t.Fatal("retired resource accepted a new lease")
	}
	r.Retire()
	lease()
	lease()
	if err := r.Wait(context.Background()); err != nil {
		t.Fatal(err)
	}
	if freed.Load() != 1 || pendingRetiredResources() != baseline {
		t.Fatal("late completion did not reclaim exactly once")
	}
}

func TestRetiredResourceConcurrentCompletionAndRetirement(t *testing.T) {
	baseline := pendingRetiredResources()
	for generation := 0; generation < 100; generation++ {
		var freed atomic.Int64
		r := newRetiredResource(func() { freed.Add(1) })
		leases := make([]func(), 32)
		for i := range leases {
			var ok bool
			leases[i], ok = r.Acquire()
			if !ok {
				t.Fatal("new resource was retired")
			}
		}
		var workers sync.WaitGroup
		for _, lease := range leases {
			workers.Add(1)
			go func(release func()) {
				defer workers.Done()
				release()
				release()
			}(lease)
		}
		for i := 0; i < 8; i++ {
			workers.Add(1)
			go func() { defer workers.Done(); r.Retire() }()
		}
		workers.Wait()
		if err := r.Wait(context.Background()); err != nil {
			t.Fatal(err)
		}
		if freed.Load() != 1 {
			t.Fatalf("freed %d times", freed.Load())
		}
	}
	if pendingRetiredResources() != baseline {
		t.Fatal("retired count did not recover")
	}
}

func TestRetiredResourceGenerationsStayIndependent(t *testing.T) {
	var oldFreed, newFreed atomic.Int64
	old := newRetiredResource(func() { oldFreed.Add(1) })
	lease, _ := old.Acquire()
	old.Retire()
	current := newRetiredResource(func() { newFreed.Add(1) })
	currentLease, ok := current.Acquire()
	if !ok {
		t.Fatal("old retirement blocked the next generation")
	}
	lease()
	if oldFreed.Load() != 1 || newFreed.Load() != 0 {
		t.Fatal("cross-generation release")
	}
	current.Retire()
	if newFreed.Load() != 0 {
		t.Fatal("current resource released while in use")
	}
	currentLease()
	if newFreed.Load() != 1 {
		t.Fatal("current resource was not released")
	}
}

func TestRetiredResourceWaitIncludesCleanup(t *testing.T) {
	baseline := pendingRetiredResources()
	started, finish := make(chan struct{}), make(chan struct{})
	r := newRetiredResource(func() { close(started); <-finish })
	go r.Retire()
	<-started
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := r.Wait(ctx); err == nil {
		t.Fatal("wait returned before cleanup finished")
	}
	if pendingRetiredResources() != baseline+1 {
		t.Fatal("cleanup no longer counted")
	}
	close(finish)
	if err := r.Wait(context.Background()); err != nil {
		t.Fatal(err)
	}
	if pendingRetiredResources() != baseline {
		t.Fatal("completed cleanup still counted")
	}
}

func TestRetiredResourceEmptyRetirementIsIdempotent(t *testing.T) {
	var freed int
	r := newRetiredResource(func() { freed++ })
	r.Retire()
	r.Retire()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := r.Wait(ctx); err != nil {
		t.Fatalf("completed drain: %v", err)
	}
	if freed != 1 {
		t.Fatalf("freed %d times", freed)
	}
}
