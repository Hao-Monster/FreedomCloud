package main

import (
	"net"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type gracefulStopTestTracker struct {
	statistic.Tracker
	id     string
	info   *statistic.TrackerInfo
	closed atomic.Bool
}

func (t *gracefulStopTestTracker) ID() string {
	return t.id
}

func (t *gracefulStopTestTracker) Info() *statistic.TrackerInfo {
	return t.info
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

func allocateFreeLoopbackPort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("allocateFreeLoopbackPort failed: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()
	return port
}

func TestHandleStopAndStartListenerRestoresCustomInboundsAndHealthChecks(t *testing.T) {
	isolateHealthCheckForwarder(t)
	oldController := recreateRuntimeController
	recreateRuntimeController = func(*config.Config) error { return nil }
	runLock.Lock()
	previousRunning := isRunning
	previousConfig := currentConfig
	previousRaw := appliedRawConfig
	previousPending := pendingTunEnable
	isRunning = true
	runLock.Unlock()
	t.Cleanup(func() {
		stopHealthCheckForwarder()
		stopRequestForwarder()
		recreateRuntimeController = oldController
		runLock.Lock()
		isRunning = previousRunning
		currentConfig = previousConfig
		appliedRawConfig = previousRaw
		pendingTunEnable = previousPending
		stopListeners()
		runLock.Unlock()
	})

	customPort := allocateFreeLoopbackPort(t)
	params := defaultSetupParams()
	params.Config.Tun.Enable = false
	params.Config.MixedPort = 0
	params.Config.Listeners = []map[string]any{
		{
			"name":   "fcx-roundtrip-socks",
			"type":   "socks",
			"listen": "127.0.0.1",
			"port":   customPort,
			"udp":    false,
		},
	}
	if err := setupConfig(params); err != nil {
		t.Fatalf("setupConfig failed: %v", err)
	}

	targetAddr := net.JoinHostPort("127.0.0.1", itoaPort(customPort))
	conn1, err := net.DialTimeout("tcp", targetAddr, time.Second)
	if err != nil {
		t.Fatalf("expected custom inbound %s to accept TCP after initial setup: %v", targetAddr, err)
	}
	_ = conn1.Close()

	if !handleStopListener() {
		t.Fatal("handleStopListener returned false")
	}
	if c, err := net.DialTimeout("tcp", targetAddr, 150*time.Millisecond); err == nil {
		_ = c.Close()
		t.Fatalf("expected custom inbound %s to be closed after handleStopListener", targetAddr)
	}

	if !handleStartListener() {
		t.Fatal("handleStartListener returned false")
	}
	conn2, err := net.DialTimeout("tcp", targetAddr, time.Second)
	if err != nil {
		t.Fatalf("expected custom inbound %s to accept TCP after handleStartListener: %v", targetAddr, err)
	}
	_ = conn2.Close()

	runLock.Lock()
	rebuilt := currentConfig.Listeners["fcx-roundtrip-socks"]
	runLock.Unlock()
	if rebuilt == nil {
		t.Fatal("expected fcx-roundtrip-socks in currentConfig.Listeners")
	}
	if gotAddr := rebuilt.Address(); gotAddr != targetAddr {
		t.Fatalf("expected rebuilt InboundListener single clean address %q without closed stale handle, got %q", targetAddr, gotAddr)
	}

	deadline := time.Now().Add(2 * time.Second)
	forwarderRestarted := false
	for time.Now().Before(deadline) {
		healthCheckChMu.Lock()
		forwarderRestarted = healthCheckStopCh != nil
		healthCheckChMu.Unlock()
		if forwarderRestarted {
			break
		}
		time.Sleep(15 * time.Millisecond)
	}
	if !forwarderRestarted {
		t.Fatal("expected handleStartListener to restart healthCheckForwarder")
	}
}

func TestStoppedSetupConfigSuppressesPortBindsAndUiActiveSkipsProviderTouch(t *testing.T) {
	isolateHealthCheckForwarder(t)
	oldController := recreateRuntimeController
	recreateRuntimeController = func(*config.Config) error { return nil }
	oldTunUp := tunUp.Swap(false)
	oldUiActive := uiActive.Swap(true)
	runLock.Lock()
	previousRunning := isRunning
	previousConfig := currentConfig
	previousRaw := appliedRawConfig
	previousPending := pendingTunEnable
	isRunning = false
	stopListeners()
	runLock.Unlock()
	t.Cleanup(func() {
		stopHealthCheckForwarder()
		stopRequestForwarder()
		recreateRuntimeController = oldController
		tunUp.Store(oldTunUp)
		uiActive.Store(oldUiActive)
		runLock.Lock()
		isRunning = previousRunning
		currentConfig = previousConfig
		appliedRawConfig = previousRaw
		pendingTunEnable = previousPending
		stopListeners()
		runLock.Unlock()
	})

	mixedPort := allocateFreeLoopbackPort(t)
	customPort := allocateFreeLoopbackPort(t)
	params := defaultSetupParams()
	params.Config.Tun.Enable = false
	params.Config.MixedPort = mixedPort
	params.Config.Listeners = []map[string]any{
		{
			"name":   "fcx-stopped-setup-socks",
			"type":   "socks",
			"listen": "127.0.0.1",
			"port":   customPort,
			"udp":    false,
		},
	}
	if err := setupConfig(params); err != nil {
		t.Fatalf("setupConfig while stopped failed: %v", err)
	}

	mixedAddr := net.JoinHostPort("127.0.0.1", itoaPort(mixedPort))
	customAddr := net.JoinHostPort("127.0.0.1", itoaPort(customPort))
	if gotPort := listener.GetPorts().MixedPort; gotPort != 0 {
		t.Fatalf("expected stopped setupConfig NOT to bind MixedPort, got bound port %d", gotPort)
	}
	if c, err := net.DialTimeout("tcp", mixedAddr, 150*time.Millisecond); err == nil {
		_ = c.Close()
		t.Fatalf("expected MixedPort %s to remain closed while !isRunning", mixedAddr)
	}
	if c, err := net.DialTimeout("tcp", customAddr, 150*time.Millisecond); err == nil {
		_ = c.Close()
		t.Fatalf("expected custom listener %s to remain closed while !isRunning", customAddr)
	}

	healthCheckChMu.Lock()
	forwarderRunningWhileStopped := healthCheckStopCh != nil
	healthCheckChMu.Unlock()
	if forwarderRunningWhileStopped {
		t.Fatal("expected setupConfig while !isRunning && !tunUp NOT to start healthCheckForwarder")
	}

	testProvider := &healthCheckTestProvider{
		proxies: []C.Proxy{healthCheckProxy("stopped-cached-node")},
	}
	runLock.Lock()
	tunnel.UpdateProxies(map[string]C.Proxy{}, map[string]P.ProxyProvider{"stopped-prov": testProvider})
	runLock.Unlock()

	handleSetUiActive(true)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && healthCheckCacheSize() == 0 {
		time.Sleep(15 * time.Millisecond)
	}
	if got := healthCheckCacheSize(); got != 1 {
		t.Fatalf("expected handleSetUiActive(true) while stopped to still flush cached delay history (want 1, got %d)", got)
	}
	if touches := testProvider.touches.Load(); touches != 0 {
		t.Fatalf("expected handleSetUiActive(true) while stopped (!isRunning && !tunUp) NOT to touch providers, got touches=%d", touches)
	}

	// Starting listeners afterward must bind both MixedPort and custom listener cleanly.
	if !handleStartListener() {
		t.Fatal("handleStartListener failed after stopped setupConfig")
	}
	if gotPort := listener.GetPorts().MixedPort; gotPort != mixedPort {
		t.Fatalf("expected handleStartListener to bind MixedPort %d, got %d", mixedPort, gotPort)
	}
	conn, err := net.DialTimeout("tcp", customAddr, time.Second)
	if err != nil {
		t.Fatalf("expected handleStartListener to bind custom listener %s: %v", customAddr, err)
	}
	_ = conn.Close()
}

func itoaPort(port int) string {
	return strconv.Itoa(port)
}
