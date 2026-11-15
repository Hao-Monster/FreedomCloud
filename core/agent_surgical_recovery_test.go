package main

import (
	"net"
	"net/netip"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func setupSurgicalRecoveryEnv(t *testing.T, providerName string) (*networkRecoveryFakeResolver, *networkRecoveryFakeResolver, *networkRecoveryFakeProvider) {
	t.Helper()
	isolateHealthCheckForwarder(t)
	prevDebounce := networkHealthCheckDebounce
	networkHealthCheckDebounce = 25 * time.Millisecond
	t.Cleanup(func() {
		networkHealthCheckDebounce = prevDebounce
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
	})

	prevDefault := resolver.DefaultResolver
	prevSystem := resolver.SystemResolver
	fakeDefault := &networkRecoveryFakeResolver{}
	fakeSystem := &networkRecoveryFakeResolver{}
	resolver.DefaultResolver = fakeDefault
	resolver.SystemResolver = fakeSystem
	t.Cleanup(func() {
		resolver.DefaultResolver = prevDefault
		resolver.SystemResolver = prevSystem
	})

	proxyStateMu.Lock()
	prevProxies := tunnel.Proxies()
	prevProviders := tunnel.Providers()
	fakeProv := &networkRecoveryFakeProvider{name: providerName}
	tunnel.UpdateProxies(map[string]C.Proxy{}, map[string]cp.ProxyProvider{
		fakeProv.name: fakeProv,
	})
	proxyStateMu.Unlock()
	t.Cleanup(func() {
		proxyStateMu.Lock()
		tunnel.UpdateProxies(prevProxies, prevProviders)
		proxyStateMu.Unlock()
	})

	runLock.Lock()
	prevRunning := isRunning
	prevConfig := currentConfig
	isRunning = true
	currentConfig = &config.Config{General: &config.General{}}
	runLock.Unlock()
	t.Cleanup(func() {
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
		runLock.Lock()
		isRunning = prevRunning
		currentConfig = prevConfig
		runLock.Unlock()
	})

	cancelPendingNetworkRecoveryHealthChecks()
	return fakeDefault, fakeSystem, fakeProv
}

func waitForHealthCheckAtLeast(t *testing.T, prov *networkRecoveryFakeProvider, minCount int32) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) && prov.healthCheckCount.Load() < minCount {
		time.Sleep(15 * time.Millisecond)
	}
	if prov.healthCheckCount.Load() < minCount {
		t.Fatalf("expected HealthCheck count >= %d, got %d", minCount, prov.healthCheckCount.Load())
	}
}

func TestSurgicalAdditiveIPv6RAOnSameDefaultInterfaceDoesNotDropConnections(t *testing.T) {
	fakeDefault, fakeSystem, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1b-provider")

	v4Prefix := netip.MustParsePrefix("192.168.10.20/24")
	v6Prefix := netip.MustParsePrefix("240e:390:100::1234/64")

	// 1. Initial IPv4 recovery on WLAN#30.
	restoreV4 := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{v4Prefix},
		},
	})
	defer restoreV4()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{v4Prefix},
	})
	waitForHealthCheckAtLeast(t, fakeProv, 1)

	tracker := &gracefulStopTestTracker{id: "surgical-1b-active"}
	statistic.DefaultManager.Join(tracker)
	defer statistic.DefaultManager.Leave(tracker)

	fakeDefault.resetCount.Store(0)
	fakeDefault.clearCount.Store(0)
	fakeSystem.resetCount.Store(0)
	fakeSystem.clearCount.Store(0)
	fakeProv.healthCheckCount.Store(0)

	// 2. IPv6 RA arrives additively while IPv4 remains intact on same WLAN#30.
	restoreDual := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{v4Prefix, v6Prefix},
		},
	})
	defer restoreDual()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{v4Prefix, v6Prefix},
	})

	time.Sleep(80 * time.Millisecond)
	if tracker.closed.Load() {
		t.Fatal("purely additive IPv6 RA on same default interface must NOT close active connections")
	}
	if fakeDefault.resetCount.Load() != 0 || fakeSystem.resetCount.Load() != 0 {
		t.Fatalf("purely additive IPv6 RA must NOT reset DNS/DoH connection pools (default=%d system=%d)",
			fakeDefault.resetCount.Load(), fakeSystem.resetCount.Load())
	}
	if fakeProv.healthCheckCount.Load() != 0 {
		t.Fatalf("purely additive IPv6 RA must NOT trigger health check storm, got %d", fakeProv.healthCheckCount.Load())
	}

	// 3. Replacing an established IPv4 prefix on WLAN#30 must trigger full connection closure + DNS reset.
	newV4Prefix := netip.MustParsePrefix("192.168.99.20/24")
	restoreReplaced := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{newV4Prefix, v6Prefix},
		},
	})
	defer restoreReplaced()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{newV4Prefix, v6Prefix},
	})
	if !tracker.closed.Load() {
		t.Fatal("replaced IPv4 prefix on same default interface must close stale connections")
	}
	if fakeDefault.resetCount.Load() == 0 {
		t.Fatal("replaced IPv4 prefix must reset DNS connections")
	}
	waitForHealthCheckAtLeast(t, fakeProv, 1)
}

func TestSurgicalVirtualInterfacesIgnoredAndDefaultNicTentative(t *testing.T) {
	_, _, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1c-provider")

	virtualNames := []string{
		"vEthernet (WSL)",
		"WSL",
		"Hyper-V Virtual Ethernet Adapter",
		"VMware Network Adapter VMnet8",
		"vmnet1",
		"vboxnet0",
		"VirtualBox Host-Only Ethernet Adapter",
		"Tailscale",
		"ZeroTier One",
		"WireGuard Tunnel",
		"TAP-Windows Adapter V9",
		"Loopback Pseudo-Interface 1",
		"docker0",
		"podman0",
	}
	for _, name := range virtualNames {
		item := &iface.Interface{
			Index:     99,
			MTU:       1500,
			Name:      name,
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("172.25.192.1/20")},
		}
		if !isTunLikeInterface(item, "FlClashX") {
			t.Fatalf("expected virtual/VPN/container interface %q to be filtered by isTunLikeInterface", name)
		}
	}

	physicalNames := []string{
		"Ethernet",
		"WLAN",
		"Intel(R) Wi-Fi 6E AX211 160MHz",
		"Realtek PCIe GbE Family Controller",
	}
	for _, name := range physicalNames {
		item := &iface.Interface{
			Index:     12,
			MTU:       1500,
			Name:      name,
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("192.168.1.10/24")},
		}
		if isTunLikeInterface(item, "FlClashX") {
			t.Fatalf("physical interface %q must NOT be filtered by isTunLikeInterface", name)
		}
	}

	// Default interface WLAN has only link-local IP while vEthernet (WSL) and secondary Ethernet have IPs.
	// WLAN must still enter Tentative deferral and NOT trigger HealthCheck prematurely.
	restoreTentative := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("fe80::1234/64")},
		},
		{
			Index:     50,
			MTU:       1500,
			Name:      "vEthernet (WSL)",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("172.25.192.1/20")},
		},
		{
			Index:     12,
			MTU:       1500,
			Name:      "Ethernet",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("10.0.0.5/24")},
		},
	})
	defer restoreTentative()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{netip.MustParsePrefix("fe80::1234/64")},
	})

	time.Sleep(80 * time.Millisecond)
	if fakeProv.healthCheckCount.Load() != 0 {
		t.Fatalf("expected HealthCheck to be deferred while default NIC WLAN lacks usable IP even though vEthernet/Ethernet have IPs, got %d",
			fakeProv.healthCheckCount.Load())
	}

	// Now WLAN acquires a preferred IPv4 address -> recovery fires once.
	restoreReady := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index: 30,
			MTU:   1500,
			Name:  "WLAN",
			Flags: net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("192.168.1.50/24"),
				netip.MustParsePrefix("fe80::1234/64"),
			},
		},
		{
			Index:     50,
			MTU:       1500,
			Name:      "vEthernet (WSL)",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("172.25.192.1/20")},
		},
	})
	defer restoreReady()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{netip.MustParsePrefix("192.168.1.50/24")},
	})
	waitForHealthCheckAtLeast(t, fakeProv, 1)
}

func TestSurgicalIPCReset30sDedupAndCacheFlushSkipsDuplicateResetAndHealthCheck(t *testing.T) {
	fakeDefault, fakeSystem, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1d-dedup")

	wlanPrefix := netip.MustParsePrefix("192.168.1.10/24")
	ethPrefix := netip.MustParsePrefix("10.0.0.5/24")

	// 1. Recover on WLAN#30.
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
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{wlanPrefix},
	})
	waitForHealthCheckAtLeast(t, fakeProv, 1)
	if fakeProv.healthCheckCount.Load() != 1 {
		t.Fatalf("expected 1 initial health check, got %d", fakeProv.healthCheckCount.Load())
	}

	// Simulate stale iface cache holding Ethernet while active override is WLAN again,
	// AND age lastTunRecoveredAt to 20s ago (inside 30s grace window, outside old 15s window).
	restoreEth := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     12,
			MTU:       1500,
			Name:      "Ethernet",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{ethPrefix},
		},
	})
	iface.FlushCache()
	_, _ = iface.Interfaces()
	restoreEth()

	networkRecoveryMu.Lock()
	lastTunRecoveredAt = time.Now().Add(-20 * time.Second)
	networkRecoveryMu.Unlock()

	tracker := &gracefulStopTestTracker{id: "surgical-1d-keep"}
	statistic.DefaultManager.Join(tracker)
	defer statistic.DefaultManager.Leave(tracker)

	fakeDefault.resetCount.Store(0)
	fakeDefault.clearCount.Store(0)
	fakeSystem.resetCount.Store(0)
	fakeSystem.clearCount.Store(0)
	fakeProv.healthCheckCount.Store(0)

	recoverFromIPCNetworkReset()
	time.Sleep(80 * time.Millisecond)

	if tracker.closed.Load() {
		t.Fatal("recoverFromIPCNetworkReset within 30s of matching TUN recovery must NOT close connections")
	}
	if fakeDefault.resetCount.Load() != 0 || fakeDefault.clearCount.Load() != 0 ||
		fakeSystem.resetCount.Load() != 0 || fakeSystem.clearCount.Load() != 0 {
		t.Fatalf("deduped recoverFromIPCNetworkReset must NOT reset resolvers/caches (def=%d/%d sys=%d/%d)",
			fakeDefault.resetCount.Load(), fakeDefault.clearCount.Load(),
			fakeSystem.resetCount.Load(), fakeSystem.clearCount.Load())
	}
	if fakeProv.healthCheckCount.Load() != 0 {
		t.Fatalf("deduped recoverFromIPCNetworkReset must NOT trigger duplicate health check, got %d",
			fakeProv.healthCheckCount.Load())
	}
}

func TestSurgicalIPCResetDoesNotSwallowSubsequentDefaultInterfaceSwitch(t *testing.T) {
	fakeDefault, _, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1d-noswallow")

	restoreDual := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     12,
			MTU:       1500,
			Name:      "Ethernet",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("10.0.0.5/24")},
		},
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{netip.MustParsePrefix("192.168.1.10/24")},
		},
	})
	defer restoreDual()

	// Case A: recoverFromIPCNetworkReset runs without a seeded TUN baseline.
	// It leaves lastTunDefaultInterfaceID empty, so the next real TUN default interface
	// notification must NOT be swallowed as "unchanged".
	recoverFromIPCNetworkReset()
	waitForHealthCheckAtLeast(t, fakeProv, 1)

	tracker := &gracefulStopTestTracker{id: "surgical-1d-switch"}
	statistic.DefaultManager.Join(tracker)
	defer statistic.DefaultManager.Leave(tracker)

	fakeDefault.resetCount.Store(0)
	fakeProv.healthCheckCount.Store(0)

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{netip.MustParsePrefix("192.168.1.10/24")},
	})

	if !tracker.closed.Load() {
		t.Fatal("onTunDefaultInterfaceChanged after non-seeded recoverFromIPCNetworkReset must NOT be swallowed")
	}
	if fakeDefault.resetCount.Load() == 0 {
		t.Fatal("expected DNS reset when real default interface arrives after IPC reset")
	}
	waitForHealthCheckAtLeast(t, fakeProv, 1)

	// Case B: seedNetworkRecoveryBaseline DOES mark startup baseline as seeded,
	// so initial onTunDefaultInterfaceChanged on matching network preserves connections.
	cancelPendingNetworkRecoveryHealthChecks()
	seedNetworkRecoveryBaseline()

	seededTracker := &gracefulStopTestTracker{id: "surgical-1d-seeded"}
	statistic.DefaultManager.Join(seededTracker)
	defer statistic.DefaultManager.Leave(seededTracker)
	fakeDefault.resetCount.Store(0)
	fakeProv.healthCheckCount.Store(0)

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{netip.MustParsePrefix("192.168.1.10/24")},
	})
	time.Sleep(80 * time.Millisecond)

	if seededTracker.closed.Load() {
		t.Fatal("initial monitor event matching seeded baseline must preserve active connections")
	}
	if fakeDefault.resetCount.Load() != 0 {
		t.Fatalf("expected 0 DNS resets for initial seeded match, got %d", fakeDefault.resetCount.Load())
	}
}

func TestSurgicalIsPurelyAdditiveInterfaceUpdateMatrix(t *testing.T) {
	cases := []struct {
		name      string
		prevKey   string
		newKey    string
		defaultIf string
		want      bool
	}{
		{
			name:      "ipv4_adds_ipv6_ra_on_default",
			prevKey:   "WLAN=[192.168.10.0/24]",
			newKey:    "WLAN=[192.168.10.0/24,240e:390:100::/64]",
			defaultIf: "WLAN",
			want:      true,
		},
		{
			name:      "ipv6_adds_dhcpv4_on_default",
			prevKey:   "WLAN=[240e:390:100::/64]",
			newKey:    "WLAN=[192.168.10.0/24,240e:390:100::/64]",
			defaultIf: "WLAN",
			want:      true,
		},
		{
			name:      "secondary_nic_plug_in_preserves_default_and_existing",
			prevKey:   "WLAN=[192.168.10.0/24]",
			newKey:    "Ethernet=[10.0.0.0/24];WLAN=[192.168.10.0/24]",
			defaultIf: "WLAN",
			want:      true,
		},
		{
			name:      "non_default_nic_loses_address",
			prevKey:   "Ethernet=[10.0.0.0/24];WLAN=[192.168.10.0/24]",
			newKey:    "WLAN=[192.168.10.0/24,240e:390:100::/64]",
			defaultIf: "WLAN",
			want:      false,
		},
		{
			name:      "default_nic_replaces_ipv4_prefix",
			prevKey:   "WLAN=[192.168.10.0/24]",
			newKey:    "WLAN=[192.168.20.0/24,240e:390:100::/64]",
			defaultIf: "WLAN",
			want:      false,
		},
		{
			name:      "default_nic_adds_second_same_family_ipv4",
			prevKey:   "WLAN=[192.168.10.0/24]",
			newKey:    "WLAN=[192.168.10.0/24,192.168.20.0/24]",
			defaultIf: "WLAN",
			want:      false,
		},
		{
			name:      "default_nic_adds_second_same_family_ipv6",
			prevKey:   "WLAN=[240e:390:100::/64]",
			newKey:    "WLAN=[240e:390:100::/64,240e:390:200::/64]",
			defaultIf: "WLAN",
			want:      false,
		},
		{
			name:      "tentative_prev_key_rejected",
			prevKey:   "tentative:WLAN",
			newKey:    "WLAN=[192.168.10.0/24]",
			defaultIf: "WLAN",
			want:      false,
		},
		{
			name:      "empty_default_if_rejected",
			prevKey:   "WLAN=[192.168.10.0/24]",
			newKey:    "WLAN=[192.168.10.0/24,240e:390:100::/64]",
			defaultIf: "",
			want:      false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isPurelyAdditiveInterfaceUpdate(tc.prevKey, tc.newKey, tc.defaultIf); got != tc.want {
				t.Fatalf("isPurelyAdditiveInterfaceUpdate(%q, %q, %q) = %v, want %v",
					tc.prevKey, tc.newKey, tc.defaultIf, got, tc.want)
			}
		})
	}
}

func TestSurgicalSystemProxyConsecutiveIPCResetsWithin30sBothRecover(t *testing.T) {
	fakeDefault, _, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1d-sysproxy")
	func() {
		runLock.Lock()
		defer runLock.Unlock()
		currentConfig.General.Tun.Enable = false
	}()

	wlanPrefix := netip.MustParsePrefix("192.168.88.10/24")
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

	// 1. First offline->online recovery in System Proxy mode (no TUN monitor active).
	conn1 := &gracefulStopTestTracker{id: "sysproxy-conn-1"}
	statistic.DefaultManager.Join(conn1)
	defer statistic.DefaultManager.Leave(conn1)

	recoverFromIPCNetworkReset()
	if !conn1.closed.Load() {
		t.Fatal("first System Proxy IPC reset must close active connection")
	}
	if fakeDefault.resetCount.Load() == 0 {
		t.Fatal("first System Proxy IPC reset must reset DNS")
	}
	waitForHealthCheckAtLeast(t, fakeProv, 1)

	networkRecoveryMu.Lock()
	recoveredByTunAfterFirst := lastRecoveryFromTun
	tunAtAfterFirst := lastTunRecoveredAt
	networkRecoveryMu.Unlock()
	if recoveredByTunAfterFirst || !tunAtAfterFirst.IsZero() {
		t.Fatalf("IPC reset must never record TUN recovery timestamp (lastRecoveryFromTun=%v lastTunRecoveredAt=%v)",
			recoveredByTunAfterFirst, tunAtAfterFirst)
	}

	// 2. Disconnect & reconnect to the exact same IP within < 30s in System Proxy mode:
	// second recoverFromIPCNetworkReset must execute full recovery, NOT silently dedup.
	conn2 := &gracefulStopTestTracker{id: "sysproxy-conn-2"}
	statistic.DefaultManager.Join(conn2)
	defer statistic.DefaultManager.Leave(conn2)
	fakeDefault.resetCount.Store(0)
	fakeProv.healthCheckCount.Store(0)

	recoverFromIPCNetworkReset()
	if !conn2.closed.Load() {
		t.Fatal("second System Proxy IPC reset within 30s on same IP must NOT be skipped")
	}
	if fakeDefault.resetCount.Load() == 0 {
		t.Fatal("second System Proxy IPC reset must reset DNS connection pool")
	}
	waitForHealthCheckAtLeast(t, fakeProv, 1)
}

func TestSurgicalSLAACAndAdditiveUpdatesDoNotExtendGraceWindow(t *testing.T) {
	_, _, fakeProv := setupSurgicalRecoveryEnv(t, "surgical-1d-no-extend")

	v4Prefix := netip.MustParsePrefix("192.168.70.10/24")
	v6Prefix := netip.MustParsePrefix("240e:390:700::1234/64")

	restoreV4 := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{v4Prefix},
		},
	})
	defer restoreV4()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{v4Prefix},
	})
	waitForHealthCheckAtLeast(t, fakeProv, 1)

	anchoredAt := time.Now().Add(-20 * time.Second)
	networkRecoveryMu.Lock()
	lastTunRecoveredAt = anchoredAt
	networkRecoveryMu.Unlock()

	// No-op callback must NOT push lastTunRecoveredAt forward.
	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{v4Prefix},
	})
	networkRecoveryMu.Lock()
	afterNoop := lastTunRecoveredAt
	networkRecoveryMu.Unlock()
	if !afterNoop.Equal(anchoredAt) {
		t.Fatalf("no-op interface update extended lastTunRecoveredAt: got %v want %v", afterNoop, anchoredAt)
	}

	// Purely additive IPv6 RA must update key for lagging IPC dedup without sliding lastTunRecoveredAt.
	restoreDual := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     30,
			MTU:       1500,
			Name:      "WLAN",
			Flags:     net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{v4Prefix, v6Prefix},
		},
	})
	defer restoreDual()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{v4Prefix, v6Prefix},
	})
	networkRecoveryMu.Lock()
	afterAdditive := lastTunRecoveredAt
	networkRecoveryMu.Unlock()
	if !afterAdditive.Equal(anchoredAt) {
		t.Fatalf("purely additive update extended lastTunRecoveredAt: got %v want %v", afterAdditive, anchoredAt)
	}

	// Once original recovery timestamp ages past 30s, IPC reset executes full recovery and clears TUN state.
	networkRecoveryMu.Lock()
	lastTunRecoveredAt = time.Now().Add(-31 * time.Second)
	networkRecoveryMu.Unlock()
	conn := &gracefulStopTestTracker{id: "expired-grace-conn"}
	statistic.DefaultManager.Join(conn)
	defer statistic.DefaultManager.Leave(conn)

	recoverFromIPCNetworkReset()
	if !conn.closed.Load() {
		t.Fatal("expected expired 30s grace window to run full IPC recovery")
	}
	networkRecoveryMu.Lock()
	stillFromTun := lastRecoveryFromTun
	stillAt := lastTunRecoveredAt
	networkRecoveryMu.Unlock()
	if stillFromTun || !stillAt.IsZero() {
		t.Fatalf("expected non-deduped IPC recovery to clear TUN dedup state (fromTun=%v at=%v)", stillFromTun, stillAt)
	}
}

