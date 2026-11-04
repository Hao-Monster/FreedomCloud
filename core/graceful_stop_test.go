package main

import (
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type gracefulStopTestTracker struct {
	statistic.Tracker
	id     string
	closed atomic.Bool
}

func (t *gracefulStopTestTracker) ID() string {
	return t.id
}

func (t *gracefulStopTestTracker) Close() error {
	t.closed.Store(true)
	statistic.DefaultManager.Leave(t)
	return nil
}

func TestHandleStopListenerDrainsConnectionsClosesCustomInboundsStopsHealthCheckAndSingleClosesTun(t *testing.T) {
	isolateHealthCheckForwarder(t)
	t.Cleanup(func() {
		stopHealthCheckForwarder()
		stopRequestForwarder()
		listener.PatchInboundListeners(map[string]C.InboundListener{}, tunnel.Tunnel, true)
		listener.Cleanup()
	})

	inboundListener, err := listener.ParseListener(map[string]any{
		"name":   "fcx-graceful-stop-test-socks",
		"type":   "socks",
		"listen": "127.0.0.1",
		"port":   "0",
		"udp":    false,
	})
	if err != nil {
		t.Fatalf("ParseListener failed: %v", err)
	}
	listener.PatchInboundListeners(map[string]C.InboundListener{
		"fcx-graceful-stop-test-socks": inboundListener,
	}, tunnel.Tunnel, true)
	boundAddr := inboundListener.Address()
	if boundAddr == "" {
		t.Fatal("expected custom inbound listener to bind a loopback TCP port")
	}
	probeConn, err := net.DialTimeout("tcp", boundAddr, time.Second)
	if err != nil {
		t.Fatalf("expected custom inbound %s to accept TCP before stop: %v", boundAddr, err)
	}
	_ = probeConn.Close()

	tracker := &gracefulStopTestTracker{id: "graceful-stop-tracker-1"}
	statistic.DefaultManager.Join(tracker)
	t.Cleanup(func() {
		statistic.DefaultManager.Leave(tracker)
	})

	runLock.Lock()
	previousRunning := isRunning
	isRunning = true
	currentConfig = &config.Config{}
	startHealthCheckForwarder()
	runLock.Unlock()
	t.Cleanup(func() {
		runLock.Lock()
		isRunning = previousRunning
		runLock.Unlock()
	})

	healthCheckChMu.Lock()
	forwarderRunningBefore := healthCheckStopCh != nil
	healthCheckChMu.Unlock()
	if !forwarderRunningBefore {
		t.Fatal("expected healthCheckForwarder to be running before handleStopListener")
	}

	beforeTunRevision := listener.GetTunLifecycleStatus().Revision

	if ok := handleStopListener(); !ok {
		t.Fatal("handleStopListener must return true to satisfy Agent ReplayJournal contract")
	}

	if !tracker.closed.Load() {
		t.Fatal("expected handleStopListener to close active statistic.DefaultManager connections")
	}

	healthCheckChMu.Lock()
	forwarderRunningAfter := healthCheckStopCh != nil
	healthCheckChMu.Unlock()
	if forwarderRunningAfter {
		t.Fatal("expected handleStopListener to stop healthCheckForwarder so stopped Core does not dial background URLTests")
	}

	afterConn, dialErr := net.DialTimeout("tcp", boundAddr, 150*time.Millisecond)
	if dialErr == nil {
		_ = afterConn.Close()
		t.Fatalf("expected custom inbound listener %s to be closed by handleStopListener", boundAddr)
	}

	afterTunRevision := listener.GetTunLifecycleStatus().Revision
	revisionDelta := afterTunRevision - beforeTunRevision
	if revisionDelta != 1 {
		t.Fatalf("expected single-pass TUN Cleanup (revision delta == 1), got delta=%d (before=%d after=%d)",
			revisionDelta, beforeTunRevision, afterTunRevision)
	}
}
