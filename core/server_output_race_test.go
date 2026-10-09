//go:build !cgo

package main

import (
	"net"
	"sync"
	"testing"
	"time"
)

// This file and server_output.go can also be passed explicitly to go test
// -race: desktop Core normally excludes cgo, which the race runtime requires.
func TestCoreOutputConcurrentSendAndCloseReleasesByteBudget(t *testing.T) {
	for generation := 0; generation < 20; generation++ {
		left, right := net.Pipe()
		output := newCoreOutput(left, 20*time.Millisecond, 20*time.Millisecond)
		go output.writeLoop()
		var workers sync.WaitGroup
		for i := 0; i < 16; i++ {
			workers.Add(1)
			go func() {
				defer workers.Done()
				for n := 0; n < 100; n++ {
					output.sendStream([]byte("sample"))
				}
				_ = output.sendReliable([]byte("reply"))
			}()
		}
		output.close()
		workers.Wait()
		right.Close()
		select {
		case <-output.writerDone:
		case <-time.After(time.Second):
			t.Fatal("writer did not converge")
		}
		if output.bytes.Load() != 0 {
			t.Fatal("closed generation retained bytes")
		}
	}
}
