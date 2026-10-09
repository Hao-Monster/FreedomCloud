package main

import (
	"context"
	"sync"
)

// Most callers have synchronous configuration work. Optional observers such
// as queued delay tests must also be able to leave when their deadline expires.
type contextMutex struct {
	once   sync.Once
	permit chan struct{}
}

func (m *contextMutex) initialize() {
	m.once.Do(func() { m.permit = make(chan struct{}, 1); m.permit <- struct{}{} })
}
func (m *contextMutex) Lock() { _ = m.LockContext(context.Background()) }
func (m *contextMutex) LockContext(ctx context.Context) error {
	m.initialize()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-m.permit:
		if err := ctx.Err(); err != nil {
			m.Unlock()
			return err
		}
		return nil
	}
}
func (m *contextMutex) Unlock() { m.permit <- struct{}{} }
