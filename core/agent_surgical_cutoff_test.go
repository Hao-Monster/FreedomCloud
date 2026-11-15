package main

import (
	"net"
	"net/netip"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestSurgicalCloseConnectionsBeforeCutoffSemantics(t *testing.T) {
	cutoff := time.Now()
	staleBefore := &gracefulStopTestTracker{
		id:   "surgical-stale-before",
		info: &statistic.TrackerInfo{Start: cutoff.Add(-time.Second)},
	}
	exactAtCutoff := &gracefulStopTestTracker{
		id:   "surgical-exact-cutoff",
		info: &statistic.TrackerInfo{Start: cutoff},
	}
	zeroStart := &gracefulStopTestTracker{
		id:   "surgical-zero-start",
		info: &statistic.TrackerInfo{Start: time.Time{}},
	}
	nilInfo := &gracefulStopTestTracker{
		id:   "surgical-nil-info",
		info: nil,
	}
	freshAfter := &gracefulStopTestTracker{
		id:   "surgical-fresh-after",
		info: &statistic.TrackerInfo{Start: cutoff.Add(10 * time.Millisecond)},
	}

	for _, tr := range []*gracefulStopTestTracker{staleBefore, exactAtCutoff, zeroStart, nilInfo, freshAfter} {
		statistic.DefaultManager.Join(tr)
		t.Cleanup(func() { statistic.DefaultManager.Leave(tr) })
	}

	closed := closeConnectionsBefore(cutoff, false, "surgical:cutoff")
	if closed != 4 {
		t.Fatalf("expected 4 closed connections before/at cutoff, got %d", closed)
	}
	if !staleBefore.closed.Load() || !exactAtCutoff.closed.Load() || !zeroStart.closed.Load() || !nilInfo.closed.Load() {
		t.Fatalf("expected stale/exact/zero-start/nil-info connections to be closed (stale=%v exact=%v zero=%v nil=%v)",
			staleBefore.closed.Load(), exactAtCutoff.closed.Load(), zeroStart.closed.Load(), nilInfo.closed.Load())
	}
	if freshAfter.closed.Load() {
		t.Fatal("fresh connection started after cutoff must be preserved")
	}

	// Zero cutoff must close remaining fresh connections too (closeConnectionsWithReason delegation).
	closedZero := closeConnectionsWithReason("surgical:all")
	if closedZero != 1 || !freshAfter.closed.Load() {
		t.Fatalf("expected closeConnectionsWithReason to close remaining fresh connection (closed=%d freshClosed=%v)",
			closedZero, freshAfter.closed.Load())
	}
}

func TestSurgicalObservedAtWaterlinePreservesPostSwitchConnections(t *testing.T) {
	_, _, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1a-observedat")

	wlanPrefix := netip.MustParsePrefix("192.168.50.10/24")
	ethPrefix := netip.MustParsePrefix("10.10.0.10/24")

	restoreWLAN := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{wlanPrefix},
		},
	})
	defer restoreWLAN()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:       "WLAN",
		Index:      30,
		Addresses:  []netip.Prefix{wlanPrefix},
		ObservedAt: time.Now(),
	})
	waitForHealthCheckAtLeast(t, fakeProv, 1)

	now := time.Now()
	// Pretend the OS event was observed 600ms ago (before GetAdaptersAddresses stall),
	// and a new connection started 100ms ago AFTER ObservedAt while GetAdaptersAddresses stalled.
	observedAt := now.Add(-600 * time.Millisecond)
	preSwitchConn := &gracefulStopTestTracker{
		id:   "surgical-1a-old",
		info: &statistic.TrackerInfo{Start: now.Add(-2 * time.Second)},
	}
	postSwitchConn := &gracefulStopTestTracker{
		id:   "surgical-1a-post-observed",
		info: &statistic.TrackerInfo{Start: now.Add(-100 * time.Millisecond)},
	}
	statistic.DefaultManager.Join(preSwitchConn)
	statistic.DefaultManager.Join(postSwitchConn)
	defer statistic.DefaultManager.Leave(preSwitchConn)
	defer statistic.DefaultManager.Leave(postSwitchConn)

	restoreEth := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     12,
			MTU:       1500,
			Name:      "Ethernet",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{ethPrefix},
		},
	})
	defer restoreEth()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:       "Ethernet",
		Index:      12,
		Addresses:  []netip.Prefix{ethPrefix},
		ObservedAt: observedAt,
	})

	if !preSwitchConn.closed.Load() {
		t.Fatal("stale connection started before ObservedAt must be closed")
	}
	if postSwitchConn.closed.Load() {
		t.Fatal("new connection started after ObservedAt must NOT be killed by lagged default interface callback")
	}
}
