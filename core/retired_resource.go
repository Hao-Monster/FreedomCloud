package main

import (
	"context"
	"sync"
	"sync/atomic"
)

var retiredResourceCount atomic.Int64

// retiredResource lets an owner stop accepting calls without freeing a resource
// still used by an earlier generation. A drain timeout never revokes a lease.
type retiredResource struct {
	mu      sync.Mutex
	active  int
	retired bool
	release func()
	done    chan struct{}
}

func newRetiredResource(release func()) *retiredResource {
	return &retiredResource{release: release, done: make(chan struct{})}
}

func (r *retiredResource) Acquire() (func(), bool) {
	r.mu.Lock()
	if r.retired {
		r.mu.Unlock()
		return nil, false
	}
	r.active++
	r.mu.Unlock()
	var once sync.Once
	return func() {
		once.Do(func() {
			r.mu.Lock()
			r.active--
			finish := r.retired && r.active == 0
			r.mu.Unlock()
			if finish {
				r.finish()
			}
		})
	}, true
}

func (r *retiredResource) Retire() {
	r.mu.Lock()
	if r.retired {
		r.mu.Unlock()
		return
	}
	r.retired = true
	retiredResourceCount.Add(1)
	finish := r.active == 0
	r.mu.Unlock()
	if finish {
		r.finish()
	}
}

func (r *retiredResource) finish() {
	// Only the transition to retired with no leases, or the last lease after
	// retirement, reaches here. Release outside mu so the callback can observe
	// the retired state without deadlocking. Wait completes after cleanup.
	defer func() {
		retiredResourceCount.Add(-1)
		close(r.done)
	}()
	if r.release != nil {
		r.release()
		r.release = nil
	}
}

func (r *retiredResource) Wait(ctx context.Context) error {
	select {
	case <-r.done:
		return nil
	default:
	}
	select {
	case <-r.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func pendingRetiredResources() int64 { return retiredResourceCount.Load() }
