package main

import (
	"runtime/debug"
	"testing"
)

func TestConfigureRuntimeMemory(t *testing.T) {
	oldGC := debug.SetGCPercent(-1)
	oldLimit := debug.SetMemoryLimit(-1)
	t.Cleanup(func() {
		debug.SetGCPercent(oldGC)
		debug.SetMemoryLimit(oldLimit)
	})

	configureRuntimeMemory()
	if current := debug.SetGCPercent(runtimeGCPercent); current != runtimeGCPercent {
		t.Fatalf("unexpected GC percent: got %d want %d", current, runtimeGCPercent)
	}
	if current := debug.SetMemoryLimit(runtimeMemoryLimitByte); current != runtimeMemoryLimitByte {
		t.Fatalf(
			"unexpected memory limit: got %d want %d",
			current,
			runtimeMemoryLimitByte,
		)
	}
}
