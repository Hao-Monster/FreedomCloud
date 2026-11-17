package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type agentStabilityTracker struct {
	C.Connection
	id         string
	chains     C.Chain
	infoChains C.Chain
	closed     atomic.Bool
	closeCount atomic.Int32
	manager    *statistic.Manager
}

func (t *agentStabilityTracker) ID() string {
	return t.id
}

func (t *agentStabilityTracker) Close() error {
	t.closed.Store(true)
	t.closeCount.Add(1)
	if t.manager != nil {
		t.manager.Leave(t)
	}
	return nil
}

func (t *agentStabilityTracker) Info() *statistic.TrackerInfo {
	chain := t.infoChains
	if len(chain) == 0 {
		chain = t.chains
	}
	return &statistic.TrackerInfo{
		Chain: chain,
	}
}

func (t *agentStabilityTracker) Chains() C.Chain {
	return t.chains
}

func (t *agentStabilityTracker) ProviderChains() C.Chain {
	return nil
}

func (t *agentStabilityTracker) AppendToChains(adapter C.ProxyAdapter) {}

func (t *agentStabilityTracker) RemoteDestination() string {
	return ""
}

type agentStabilityLeafAdapter struct {
	*outbound.Base
}

func newAgentStabilityLeafProxy(name string, adapterType C.AdapterType) C.Proxy {
	return adapter.NewProxy(&agentStabilityLeafAdapter{
		Base: outbound.NewBase(outbound.BaseOption{
			Name: name,
			Type: adapterType,
		}),
	})
}

func (a *agentStabilityLeafAdapter) DialContext(ctx context.Context, metadata *C.Metadata) (C.Conn, error) {
	return nil, C.ErrNotSupport
}

func (a *agentStabilityLeafAdapter) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	return nil, C.ErrNotSupport
}

func (a *agentStabilityLeafAdapter) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]string{
		"type": a.Type().String(),
	})
}

type agentStabilitySelectGroupAdapter struct {
	*outbound.Base
	mu       sync.Mutex
	selected string
	all      []string
	setErr   error
}

func newAgentStabilitySelectGroupProxy(name string, all []string, selected string) (*agentStabilitySelectGroupAdapter, C.Proxy) {
	g := &agentStabilitySelectGroupAdapter{
		Base: outbound.NewBase(outbound.BaseOption{
			Name: name,
			Type: C.Selector,
		}),
		selected: selected,
		all:      append([]string(nil), all...),
	}
	return g, adapter.NewProxy(g)
}

func (g *agentStabilitySelectGroupAdapter) DialContext(ctx context.Context, metadata *C.Metadata) (C.Conn, error) {
	return nil, C.ErrNotSupport
}

func (g *agentStabilitySelectGroupAdapter) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	return nil, C.ErrNotSupport
}

func (g *agentStabilitySelectGroupAdapter) MarshalJSON() ([]byte, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	return json.Marshal(map[string]any{
		"type": g.Type().String(),
		"now":  g.selected,
		"all":  g.all,
	})
}

func (g *agentStabilitySelectGroupAdapter) Now() string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.selected
}

func (g *agentStabilitySelectGroupAdapter) All() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return append([]string(nil), g.all...)
}

func (g *agentStabilitySelectGroupAdapter) Set(name string) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.setErr != nil {
		return g.setErr
	}
	if !slices.Contains(g.all, name) {
		return errors.New("proxy not exist")
	}
	g.selected = name
	return nil
}

func (g *agentStabilitySelectGroupAdapter) ForceSet(name string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.selected = name
}

func TestAgentFormatRoutingIdentityPrefixes(t *testing.T) {
	prefixes := []netip.Prefix{
		{},
		netip.MustParsePrefix("127.0.0.1/8"),
		netip.MustParsePrefix("169.254.1.2/16"),
		netip.MustParsePrefix("0.0.0.0/0"),
		netip.MustParsePrefix("::1/128"),
		netip.MustParsePrefix("fe80::1/64"),
		netip.MustParsePrefix("::/128"),
		netip.MustParsePrefix("192.168.1.50/24"),
		netip.MustParsePrefix("192.168.1.88/24"),
		netip.MustParsePrefix("::ffff:10.0.0.5/120"),
		netip.MustParsePrefix("2001:db8:1:2::10/64"),
		netip.MustParsePrefix("2001:db8:1:2:aaaa:bbbb:cccc:dddd/128"),
		netip.MustParsePrefix("2001:db8:1:2:1111:2222:3333:4444/128"),
		netip.MustParsePrefix("2001:db8:9::1/48"),
		netip.MustParsePrefix("fd12:3456:789a:1::5/64"),
		netip.MustParsePrefix("fd12:3456:789a:1:9999::1/128"),
	}

	got := formatRoutingIdentityPrefixes(prefixes)
	want := []string{
		"10.0.0.5/24",
		"192.168.1.50/24",
		"192.168.1.88/24",
		"2001:db8:1:2::/64",
		"2001:db8:9::/48",
		"fd12:3456:789a:1::/64",
	}
	if !slices.Equal(got, want) {
		t.Fatalf("formatRoutingIdentityPrefixes mismatch:\ngot:  %v\nwant: %v", got, want)
	}

	if gotID := formatDefaultInterfaceID("WLAN", 30); gotID != "WLAN#30" {
		t.Fatalf("formatDefaultInterfaceID(\"WLAN\", 30) = %q, want \"WLAN#30\"", gotID)
	}
	if gotID := formatDefaultInterfaceID("", 30); gotID != "" {
		t.Fatalf("formatDefaultInterfaceID(\"\", 30) = %q, want \"\"", gotID)
	}

	establishedCases := []struct {
		key  string
		want bool
	}{
		{key: "", want: false},
		{key: "lost", want: false},
		{key: "tentative:", want: false},
		{key: "tentative:WLAN", want: false},
		{key: "WLAN=[192.168.1.50/24]", want: true},
	}
	for _, tc := range establishedCases {
		if got := isEstablishedNetworkRecoveryKey(tc.key); got != tc.want {
			t.Fatalf("isEstablishedNetworkRecoveryKey(%q) = %v, want %v", tc.key, got, tc.want)
		}
	}
}

func TestTunDefaultInterfaceSeededBaselineProtectsFirstSLAACRotation(t *testing.T) {
	isolateHealthCheckForwarder(t)
	prevDebounce := networkHealthCheckDebounce
	networkHealthCheckDebounce = 25 * time.Millisecond
	t.Cleanup(func() {
		networkHealthCheckDebounce = prevDebounce
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
	})
	cancelPendingNetworkRecoveryHealthChecks()

	restoreInit := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index: 30,
			MTU:   1500,
			Name:  "WLAN",
			Flags: net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("172.23.104.177/24"),
				netip.MustParsePrefix("2001:db8:1:2::10/64"),
				netip.MustParsePrefix("2001:db8:1:2:1111:2222:3333:4444/128"),
				netip.MustParsePrefix("fe80::abcd/64"),
			},
		},
	})
	defer restoreInit()

	prevDefaultRes := resolver.DefaultResolver
	prevSystemRes := resolver.SystemResolver
	fakeDefaultRes := &networkRecoveryFakeResolver{}
	fakeSystemRes := &networkRecoveryFakeResolver{}
	resolver.DefaultResolver = fakeDefaultRes
	resolver.SystemResolver = fakeSystemRes
	t.Cleanup(func() {
		resolver.DefaultResolver = prevDefaultRes
		resolver.SystemResolver = prevSystemRes
	})

	carrier := &fakeCarrierAdapter{
		Base: outbound.NewBase(outbound.BaseOption{
			Name: "baseline-carrier",
			Type: C.Trojan,
		}),
	}
	smuxAdapter, err := outbound.NewSingMux(outbound.SingMuxOption{
		Enabled:  true,
		Protocol: "smux",
	}, carrier)
	if err != nil {
		t.Fatalf("NewSingMux failed: %v", err)
	}
	muxProxy := adapter.NewProxy(smuxAdapter)
	t.Cleanup(func() { _ = muxProxy.Close() })

	proxyStateMu.Lock()
	prevProxies := tunnel.Proxies()
	prevProviders := tunnel.Providers()
	fakeProv := &networkRecoveryFakeProvider{name: "baseline-provider"}
	tunnel.UpdateProxies(map[string]C.Proxy{
		"baseline-carrier": muxProxy,
	}, map[string]cp.ProxyProvider{
		fakeProv.name: fakeProv,
	})
	proxyStateMu.Unlock()
	t.Cleanup(func() {
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
		proxyStateMu.Lock()
		tunnel.UpdateProxies(prevProxies, prevProviders)
		proxyStateMu.Unlock()
	})

	stream, err := muxProxy.DialContext(context.Background(), &C.Metadata{Host: "example.com", DstPort: 443})
	if err != nil {
		t.Fatalf("SingMux DialContext failed: %v", err)
	}
	_ = stream.Close()

	prevRecreate := recreateRuntimeTun
	var recreateCalls atomic.Int32
	recreateRuntimeTun = func(tunConf LC.Tun, t C.Tunnel) {
		recreateCalls.Add(1)
	}
	t.Cleanup(func() {
		recreateRuntimeTun = prevRecreate
	})

	runLock.Lock()
	prevRunning := isRunning
	prevConfig := currentConfig
	prevSkip := skipListenerTunRecreate
	isRunning = true
	skipListenerTunRecreate = false
	currentConfig = &config.Config{
		General: &config.General{
			Inbound: config.Inbound{
				Tun: LC.Tun{Enable: false},
			},
		},
		Listeners: map[string]C.InboundListener{},
	}
	runLock.Unlock()
	t.Cleanup(func() {
		runLock.Lock()
		isRunning = prevRunning
		currentConfig = prevConfig
		skipListenerTunRecreate = prevSkip
		runLock.Unlock()
	})

	// Tun disabled must NOT seed baseline.
	updateListeners()
	networkRecoveryMu.Lock()
	keyAfterDisabled := lastTunRecoveredNetworkKey
	networkRecoveryMu.Unlock()
	if keyAfterDisabled != "" {
		t.Fatalf("expected empty baseline when Tun.Enable=false, got %q", keyAfterDisabled)
	}

	// Tun enabled MUST seed baseline.
	runLock.Lock()
	currentConfig.General.Tun.Enable = true
	runLock.Unlock()
	updateListeners()

	if recreateCalls.Load() != 2 {
		t.Fatalf("expected recreateRuntimeTun called twice, got %d", recreateCalls.Load())
	}

	expectedKey := computeActivePhysicalInterfacesKey()
	networkRecoveryMu.Lock()
	seededKey := lastTunRecoveredNetworkKey
	seededDefaultID := lastTunDefaultInterfaceID
	networkRecoveryMu.Unlock()
	if !isEstablishedNetworkRecoveryKey(seededKey) || seededKey != expectedKey {
		t.Fatalf("expected seeded key %q to be established physical key, got %q", expectedKey, seededKey)
	}
	if seededDefaultID != "" {
		t.Fatalf("expected initial seeded lastTunDefaultInterfaceID to be empty, got %q", seededDefaultID)
	}

	agentTracker := &gracefulStopTestTracker{id: "first-slaac-agent-stream"}
	statistic.DefaultManager.Join(agentTracker)
	t.Cleanup(func() { statistic.DefaultManager.Leave(agentTracker) })

	// First SLAAC temporary IPv6 rotation right after startup baseline.
	restoreRotated := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index: 30,
			MTU:   1500,
			Name:  "WLAN",
			Flags: net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("172.23.104.177/24"),
				netip.MustParsePrefix("2001:db8:1:2::10/64"),
				netip.MustParsePrefix("2001:db8:1:2:aaaa:bbbb:cccc:dddd/128"),
				netip.MustParsePrefix("fe80::abcd/64"),
			},
		},
	})
	defer restoreRotated()

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:  "WLAN",
		Index: 30,
		Addresses: []netip.Prefix{
			netip.MustParsePrefix("172.23.104.177/24"),
			netip.MustParsePrefix("2001:db8:1:2::10/64"),
			netip.MustParsePrefix("2001:db8:1:2:aaaa:bbbb:cccc:dddd/128"),
			netip.MustParsePrefix("fe80::abcd/64"),
		},
	})
	time.Sleep(60 * time.Millisecond)

	if agentTracker.closed.Load() {
		t.Fatal("expected first SLAAC rotation after seeded startup baseline NOT to close active Agent connection")
	}
	if carrier.closed.Load() != 0 {
		t.Fatalf("expected SingMux carrier NOT to close after seeded baseline, got %d", carrier.closed.Load())
	}
	if fakeDefaultRes.resetCount.Load() != 0 || fakeDefaultRes.clearCount.Load() != 0 ||
		fakeSystemRes.resetCount.Load() != 0 || fakeSystemRes.clearCount.Load() != 0 {
		t.Fatalf("expected 0 resolver clears/resets, got default=(%d,%d) system=(%d,%d)",
			fakeDefaultRes.resetCount.Load(), fakeDefaultRes.clearCount.Load(),
			fakeSystemRes.resetCount.Load(), fakeSystemRes.clearCount.Load())
	}
	if fakeProv.healthCheckCount.Load() != 0 {
		t.Fatalf("expected 0 healthchecks on seeded first SLAAC rotation, got %d", fakeProv.healthCheckCount.Load())
	}

	networkRecoveryMu.Lock()
	afterEventDefaultID := lastTunDefaultInterfaceID
	afterEventKey := lastTunRecoveredNetworkKey
	networkRecoveryMu.Unlock()
	if afterEventDefaultID != "WLAN#30" {
		t.Fatalf("expected lastTunDefaultInterfaceID to populate to \"WLAN#30\", got %q", afterEventDefaultID)
	}
	if afterEventKey != expectedKey {
		t.Fatalf("expected lastTunRecoveredNetworkKey to stay index-free (%q), got %q", expectedKey, afterEventKey)
	}

	// Lagging IPC resetConnections within grace window must still deduplicate against index-free key.
	recoverFromIPCNetworkReset()
	if agentTracker.closed.Load() {
		t.Fatal("expected recoverFromIPCNetworkReset within grace window to deduplicate against seeded/refreshed key")
	}
}

func TestTunDefaultInterfaceRealIPv4OrIPv6PrefixOrInterfaceSwitchStillClosesConnections(t *testing.T) {
	isolateHealthCheckForwarder(t)
	prevDebounce := networkHealthCheckDebounce
	networkHealthCheckDebounce = 25 * time.Millisecond
	t.Cleanup(func() {
		networkHealthCheckDebounce = prevDebounce
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
	})

	prevDefaultRes := resolver.DefaultResolver
	fakeDefaultRes := &networkRecoveryFakeResolver{}
	resolver.DefaultResolver = fakeDefaultRes
	t.Cleanup(func() { resolver.DefaultResolver = prevDefaultRes })

	proxyStateMu.Lock()
	prevProxies := tunnel.Proxies()
	prevProviders := tunnel.Providers()
	fakeProv := &networkRecoveryFakeProvider{name: "real-change-provider"}
	tunnel.UpdateProxies(tunnel.Proxies(), map[string]cp.ProxyProvider{
		fakeProv.name: fakeProv,
	})
	proxyStateMu.Unlock()
	t.Cleanup(func() {
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
		proxyStateMu.Lock()
		tunnel.UpdateProxies(prevProxies, prevProviders)
		proxyStateMu.Unlock()
	})

	runLock.Lock()
	prevRunning := isRunning
	prevConfig := currentConfig
	isRunning = true
	currentConfig = &config.Config{}
	runLock.Unlock()
	t.Cleanup(func() {
		runLock.Lock()
		isRunning = prevRunning
		currentConfig = prevConfig
		runLock.Unlock()
	})

	establishInitial := func(t *testing.T) {
		t.Helper()
		cancelPendingNetworkRecoveryHealthChecks()
		networkHealthCheckWG.Wait()
		restore := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
			{
				Index: 30,
				MTU:   1500,
				Name:  "WLAN",
				Flags: net.FlagUp | net.FlagBroadcast,
				Addresses: []netip.Prefix{
					netip.MustParsePrefix("172.23.104.177/24"),
					netip.MustParsePrefix("2001:db8:1:2::10/64"),
				},
			},
		})
		t.Cleanup(restore)
		onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
			Name:  "WLAN",
			Index: 30,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("172.23.104.177/24"),
				netip.MustParsePrefix("2001:db8:1:2::10/64"),
			},
		})
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) && fakeProv.healthCheckCount.Load() == 0 {
			time.Sleep(15 * time.Millisecond)
		}
		fakeDefaultRes.resetCount.Store(0)
		fakeDefaultRes.clearCount.Store(0)
		fakeProv.healthCheckCount.Store(0)
	}

	t.Run("ipv4_host_change_in_same_slash24", func(t *testing.T) {
		establishInitial(t)
		tracker := &gracefulStopTestTracker{id: "ipv4-change-tracker"}
		statistic.DefaultManager.Join(tracker)
		t.Cleanup(func() { statistic.DefaultManager.Leave(tracker) })

		restore := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
			{
				Index: 30,
				MTU:   1500,
				Name:  "WLAN",
				Flags: net.FlagUp | net.FlagBroadcast,
				Addresses: []netip.Prefix{
					netip.MustParsePrefix("172.23.104.205/24"),
					netip.MustParsePrefix("2001:db8:1:2::10/64"),
				},
			},
		})
		defer restore()

		onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
			Name:  "WLAN",
			Index: 30,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("172.23.104.205/24"),
				netip.MustParsePrefix("2001:db8:1:2::10/64"),
			},
		})
		if !tracker.closed.Load() {
			t.Fatal("expected IPv4 address change within /24 to close active connections")
		}
		if fakeDefaultRes.resetCount.Load() == 0 || fakeDefaultRes.clearCount.Load() == 0 {
			t.Fatal("expected resolvers reset/cleared on IPv4 address change")
		}
	})

	t.Run("ipv6_slash64_prefix_change", func(t *testing.T) {
		establishInitial(t)
		tracker := &gracefulStopTestTracker{id: "ipv6-prefix-change-tracker"}
		statistic.DefaultManager.Join(tracker)
		t.Cleanup(func() { statistic.DefaultManager.Leave(tracker) })

		restore := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
			{
				Index: 30,
				MTU:   1500,
				Name:  "WLAN",
				Flags: net.FlagUp | net.FlagBroadcast,
				Addresses: []netip.Prefix{
					netip.MustParsePrefix("172.23.104.177/24"),
					netip.MustParsePrefix("2001:db8:1:99::10/64"),
				},
			},
		})
		defer restore()

		onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
			Name:  "WLAN",
			Index: 30,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("172.23.104.177/24"),
				netip.MustParsePrefix("2001:db8:1:99::10/64"),
			},
		})
		if !tracker.closed.Load() {
			t.Fatal("expected IPv6 /64 prefix change to close active connections")
		}
	})

	t.Run("default_interface_id_change_even_if_physical_set_overlap", func(t *testing.T) {
		establishInitial(t)
		tracker := &gracefulStopTestTracker{id: "default-if-switch-tracker"}
		statistic.DefaultManager.Join(tracker)
		t.Cleanup(func() { statistic.DefaultManager.Leave(tracker) })

		// Simulated switch to Ethernet#12 (physical key unchanged for any reason or updated).
		onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
			Name:  "Ethernet",
			Index: 12,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("10.10.0.15/24"),
			},
		})
		if !tracker.closed.Load() {
			t.Fatal("expected default interface switch WLAN#30 -> Ethernet#12 to close active connections")
		}
		networkRecoveryMu.Lock()
		gotID := lastTunDefaultInterfaceID
		networkRecoveryMu.Unlock()
		if gotID != "Ethernet#12" {
			t.Fatalf("expected lastTunDefaultInterfaceID = \"Ethernet#12\", got %q", gotID)
		}
	})

	t.Run("event_lost_clears_default_id_and_stops_healthchecks", func(t *testing.T) {
		establishInitial(t)
		tracker := &gracefulStopTestTracker{id: "lost-tracker"}
		statistic.DefaultManager.Join(tracker)
		t.Cleanup(func() { statistic.DefaultManager.Leave(tracker) })

		onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{Lost: true})
		if !tracker.closed.Load() {
			t.Fatal("expected Lost event to close connections")
		}
		networkRecoveryMu.Lock()
		gotKey := lastTunRecoveredNetworkKey
		gotID := lastTunDefaultInterfaceID
		networkRecoveryMu.Unlock()
		if gotKey != "lost" {
			t.Fatalf("expected lastTunRecoveredNetworkKey=\"lost\", got %q", gotKey)
		}
		if gotID != "" {
			t.Fatalf("expected lastTunDefaultInterfaceID cleared on Lost, got %q", gotID)
		}
	})
}

func TestChangeSelectorProxyPreservesSameLeafAndEvictsOnlyStaleGroupLeafConnections(t *testing.T) {
	boolPtr := func(v bool) *bool { return &v }
	strPtr := func(v string) *string { return &v }

	t.Run("resolveLeafProxyName_hops_cycles_and_limit", func(t *testing.T) {
		_, smartGroup := newAgentStabilitySelectGroupProxy("SmartGroup", []string{"NodeA", "NodeB"}, "NodeA")
		_, topGroup := newAgentStabilitySelectGroupProxy("Proxy", []string{"SmartGroup", "NodeB"}, "SmartGroup")
		nodeA := newAgentStabilityLeafProxy("NodeA", C.Trojan)
		nodeB := newAgentStabilityLeafProxy("NodeB", C.Trojan)

		_, cycle1 := newAgentStabilitySelectGroupProxy("Cycle1", []string{"Cycle2"}, "Cycle2")
		_, cycle2 := newAgentStabilitySelectGroupProxy("Cycle2", []string{"Cycle1"}, "Cycle1")

		proxies := map[string]C.Proxy{
			"Proxy":      topGroup,
			"SmartGroup": smartGroup,
			"NodeA":      nodeA,
			"NodeB":      nodeB,
			"Cycle1":     cycle1,
			"Cycle2":     cycle2,
		}
		for i := 0; i < 18; i++ {
			name := fmt.Sprintf("Chain%02d", i)
			next := fmt.Sprintf("Chain%02d", i+1)
			_, g := newAgentStabilitySelectGroupProxy(name, []string{next}, next)
			proxies[name] = g
		}
		proxies["Chain18"] = newAgentStabilityLeafProxy("Chain18", C.Trojan)

		if got := resolveLeafProxyName("Proxy", proxies); got != "NodeA" {
			t.Fatalf("resolveLeafProxyName(\"Proxy\") = %q, want \"NodeA\"", got)
		}
		if got := resolveLeafProxyName("NodeB", proxies); got != "NodeB" {
			t.Fatalf("resolveLeafProxyName(\"NodeB\") = %q, want \"NodeB\"", got)
		}
		// Must terminate safely on cycle without hanging.
		gotCycle := resolveLeafProxyName("Cycle1", proxies)
		if gotCycle != "Cycle1" && gotCycle != "Cycle2" {
			t.Fatalf("unexpected cycle resolution: %q", gotCycle)
		}
		// Must respect max 16-step cap and not walk all 18 hops to Chain18.
		gotLong := resolveLeafProxyName("Chain00", proxies)
		if gotLong == "Chain18" {
			t.Fatalf("expected 16-step cap to stop before Chain18, got %q", gotLong)
		}
	})

	t.Run("same_leaf_switch_to_smart_group_preserves_connections", func(t *testing.T) {
		mgr := &statistic.Manager{}
		_, smartGroup := newAgentStabilitySelectGroupProxy("SmartGroup", []string{"NodeA", "NodeB"}, "NodeA")
		_, proxyGroup := newAgentStabilitySelectGroupProxy("Proxy", []string{"NodeA", "SmartGroup", "NodeB"}, "NodeA")
		proxies := map[string]C.Proxy{
			"Proxy":      proxyGroup,
			"SmartGroup": smartGroup,
			"NodeA":      newAgentStabilityLeafProxy("NodeA", C.Trojan),
			"NodeB":      newAgentStabilityLeafProxy("NodeB", C.Trojan),
		}

		tr := &agentStabilityTracker{
			id:      "same-leaf-stream",
			chains:  C.Chain{"NodeA", "Proxy"},
			manager: mgr,
		}
		mgr.Join(tr)

		errMsg := changeSelectorProxy(proxies, mgr, ChangeProxyParams{
			GroupName:        strPtr("Proxy"),
			ProxyName:        strPtr("SmartGroup"),
			CloseConnections: boolPtr(true),
		})
		if errMsg != "" {
			t.Fatalf("unexpected error: %s", errMsg)
		}
		if tr.closed.Load() {
			t.Fatal("expected switching from manual NodeA to SmartGroup (currently also on NodeA) to close 0 connections")
		}

		// Re-selecting the exact same target also keeps connections.
		errMsg = changeSelectorProxy(proxies, mgr, ChangeProxyParams{
			GroupName:        strPtr("Proxy"),
			ProxyName:        strPtr("SmartGroup"),
			CloseConnections: boolPtr(true),
		})
		if errMsg != "" {
			t.Fatalf("unexpected error on repeat select: %s", errMsg)
		}
		if tr.closed.Load() {
			t.Fatal("expected repeat select of same group/leaf to close 0 connections")
		}
	})

	t.Run("cross_leaf_evicts_only_stale_group_connections_not_direct_other_or_pools", func(t *testing.T) {
		mgr := &statistic.Manager{}
		_, smartGroup := newAgentStabilitySelectGroupProxy("SmartGroup", []string{"NodeA", "NodeB"}, "NodeA")
		_, proxyGroup := newAgentStabilitySelectGroupProxy("Proxy", []string{"SmartGroup", "NodeB"}, "SmartGroup")
		_, otherGroup := newAgentStabilitySelectGroupProxy("OtherGroup", []string{"NodeX"}, "NodeX")

		carrier := &fakeCarrierAdapter{
			Base: outbound.NewBase(outbound.BaseOption{
				Name: "switch-carrier",
				Type: C.Trojan,
			}),
		}
		smuxAdapter, err := outbound.NewSingMux(outbound.SingMuxOption{
			Enabled:  true,
			Protocol: "smux",
		}, carrier)
		if err != nil {
			t.Fatalf("NewSingMux failed: %v", err)
		}
		muxProxy := adapter.NewProxy(smuxAdapter)
		t.Cleanup(func() { _ = muxProxy.Close() })

		stream, err := muxProxy.DialContext(context.Background(), &C.Metadata{Host: "example.com", DstPort: 443})
		if err != nil {
			t.Fatalf("SingMux DialContext failed: %v", err)
		}
		_ = stream.Close()

		proxyStateMu.Lock()
		prevProxies := tunnel.Proxies()
		prevProviders := tunnel.Providers()
		tunnel.UpdateProxies(map[string]C.Proxy{
			"switch-carrier": muxProxy,
		}, prevProviders)
		proxyStateMu.Unlock()
		t.Cleanup(func() {
			proxyStateMu.Lock()
			tunnel.UpdateProxies(prevProxies, prevProviders)
			proxyStateMu.Unlock()
		})

		proxies := map[string]C.Proxy{
			"Proxy":      proxyGroup,
			"SmartGroup": smartGroup,
			"OtherGroup": otherGroup,
			"NodeA":      newAgentStabilityLeafProxy("NodeA", C.Trojan),
			"NodeB":      newAgentStabilityLeafProxy("NodeB", C.Trojan),
			"NodeX":      newAgentStabilityLeafProxy("NodeX", C.Trojan),
			"DIRECT":     adapter.NewProxy(outbound.NewDirect()),
		}

		tStale := &agentStabilityTracker{
			id:      "stale-group-leaf",
			chains:  C.Chain{"NodeA", "SmartGroup", "Proxy"},
			manager: mgr,
		}
		tFallback := &agentStabilityTracker{
			id:         "stale-fallback-info-chain",
			chains:     nil,
			infoChains: C.Chain{"NodeA", "Proxy"},
			manager:    mgr,
		}
		tAlreadyNewLeaf := &agentStabilityTracker{
			id:      "already-new-leaf",
			chains:  C.Chain{"NodeB", "Proxy"},
			manager: mgr,
		}
		tDirect := &agentStabilityTracker{
			id:      "direct-stream",
			chains:  C.Chain{"DIRECT"},
			manager: mgr,
		}
		tOtherGroup := &agentStabilityTracker{
			id:      "other-group-stream",
			chains:  C.Chain{"NodeA", "OtherGroup"},
			manager: mgr,
		}
		for _, tr := range []*agentStabilityTracker{tStale, tFallback, tAlreadyNewLeaf, tDirect, tOtherGroup} {
			mgr.Join(tr)
		}

		errMsg := changeSelectorProxy(proxies, mgr, ChangeProxyParams{
			GroupName:        strPtr("Proxy"),
			ProxyName:        strPtr("NodeB"),
			CloseConnections: boolPtr(true),
		})
		if errMsg != "" {
			t.Fatalf("unexpected error: %s", errMsg)
		}
		if !tStale.closed.Load() {
			t.Fatal("expected stale NodeA connection through Proxy to be closed")
		}
		if !tFallback.closed.Load() {
			t.Fatal("expected stale NodeA connection using Info().Chain fallback to be closed")
		}
		if tAlreadyNewLeaf.closed.Load() {
			t.Fatal("expected connection already on nextLeaf NodeB NOT to be closed")
		}
		if tDirect.closed.Load() {
			t.Fatal("expected DIRECT connection NOT to be closed")
		}
		if tOtherGroup.closed.Load() {
			t.Fatal("expected OtherGroup connection NOT to be closed")
		}
		if carrier.closed.Load() != 0 {
			t.Fatalf("expected proxy switch NOT to reset global SingMux outbound pool, got closed=%d", carrier.closed.Load())
		}
	})

	t.Run("close_connections_false_or_nil_or_set_error_preserves_all", func(t *testing.T) {
		mgr := &statistic.Manager{}
		proxyAdapter, proxyGroup := newAgentStabilitySelectGroupProxy("Proxy", []string{"NodeA", "NodeB", "NodeC"}, "NodeA")
		proxies := map[string]C.Proxy{
			"Proxy": proxyGroup,
			"NodeA": newAgentStabilityLeafProxy("NodeA", C.Trojan),
			"NodeB": newAgentStabilityLeafProxy("NodeB", C.Trojan),
			"NodeC": newAgentStabilityLeafProxy("NodeC", C.Trojan),
		}
		tr := &agentStabilityTracker{
			id:      "preserve-stream",
			chains:  C.Chain{"NodeA", "Proxy"},
			manager: mgr,
		}
		mgr.Join(tr)

		// CloseConnections = nil
		if errMsg := changeSelectorProxy(proxies, mgr, ChangeProxyParams{
			GroupName: strPtr("Proxy"),
			ProxyName: strPtr("NodeB"),
		}); errMsg != "" {
			t.Fatalf("unexpected error with nil CloseConnections: %s", errMsg)
		}
		if tr.closed.Load() {
			t.Fatal("expected CloseConnections=nil NOT to close connections")
		}

		// CloseConnections = false
		if errMsg := changeSelectorProxy(proxies, mgr, ChangeProxyParams{
			GroupName:        strPtr("Proxy"),
			ProxyName:        strPtr("NodeC"),
			CloseConnections: boolPtr(false),
		}); errMsg != "" {
			t.Fatalf("unexpected error with CloseConnections=false: %s", errMsg)
		}
		if tr.closed.Load() {
			t.Fatal("expected CloseConnections=false NOT to close connections")
		}

		// Set returns error -> error message returned and 0 connections closed.
		proxyAdapter.mu.Lock()
		proxyAdapter.setErr = errors.New("simulated set failure")
		proxyAdapter.mu.Unlock()
		errMsg := changeSelectorProxy(proxies, mgr, ChangeProxyParams{
			GroupName:        strPtr("Proxy"),
			ProxyName:        strPtr("NodeA"),
			CloseConnections: boolPtr(true),
		})
		if errMsg == "" {
			t.Fatal("expected error message when Set fails")
		}
		if tr.closed.Load() {
			t.Fatal("expected Set failure NOT to close any connection")
		}
	})

	t.Run("handleChangeProxy_wire_json_close_connections", func(t *testing.T) {
		_, proxyGroup := newAgentStabilitySelectGroupProxy("Proxy", []string{"NodeA", "NodeB"}, "NodeA")
		proxyStateMu.Lock()
		prevProxies := tunnel.Proxies()
		prevProviders := tunnel.Providers()
		tunnel.UpdateProxies(map[string]C.Proxy{
			"Proxy": proxyGroup,
			"NodeA": newAgentStabilityLeafProxy("NodeA", C.Trojan),
			"NodeB": newAgentStabilityLeafProxy("NodeB", C.Trojan),
		}, prevProviders)
		proxyStateMu.Unlock()
		t.Cleanup(func() {
			proxyStateMu.Lock()
			tunnel.UpdateProxies(prevProxies, prevProviders)
			proxyStateMu.Unlock()
		})

		tStale := &agentStabilityTracker{
			id:      "wire-stale-stream",
			chains:  C.Chain{"NodeA", "Proxy"},
			manager: statistic.DefaultManager,
		}
		tDirect := &agentStabilityTracker{
			id:      "wire-direct-stream",
			chains:  C.Chain{"DIRECT"},
			manager: statistic.DefaultManager,
		}
		statistic.DefaultManager.Join(tStale)
		statistic.DefaultManager.Join(tDirect)
		t.Cleanup(func() {
			statistic.DefaultManager.Leave(tStale)
			statistic.DefaultManager.Leave(tDirect)
		})

		payload, err := json.Marshal(map[string]any{
			"group-name":        "Proxy",
			"proxy-name":        "NodeB",
			"close-connections": true,
		})
		if err != nil {
			t.Fatalf("json.Marshal failed: %v", err)
		}

		resCh := make(chan string, 1)
		handleChangeProxy(string(payload), func(res string) {
			resCh <- res
		})
		select {
		case res := <-resCh:
			if res != "" {
				t.Fatalf("handleChangeProxy returned error: %s", res)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("timed out waiting for handleChangeProxy callback")
		}

		if !tStale.closed.Load() {
			t.Fatal("expected handleChangeProxy with close-connections=true to close stale NodeA stream")
		}
		if tDirect.closed.Load() {
			t.Fatal("expected handleChangeProxy NOT to close DIRECT stream")
		}
	})
}

func TestAgentCloseConnectionsWithReasonLogsAndResetsPools(t *testing.T) {
	carrier := &fakeCarrierAdapter{
		Base: outbound.NewBase(outbound.BaseOption{
			Name: "reason-carrier",
			Type: C.Trojan,
		}),
	}
	smuxAdapter, err := outbound.NewSingMux(outbound.SingMuxOption{
		Enabled:  true,
		Protocol: "smux",
	}, carrier)
	if err != nil {
		t.Fatalf("NewSingMux failed: %v", err)
	}
	muxProxy := adapter.NewProxy(smuxAdapter)
	t.Cleanup(func() { _ = muxProxy.Close() })

	stream, err := muxProxy.DialContext(context.Background(), &C.Metadata{Host: "example.com", DstPort: 443})
	if err != nil {
		t.Fatalf("SingMux DialContext failed: %v", err)
	}
	_ = stream.Close()

	proxyStateMu.Lock()
	prevProxies := tunnel.Proxies()
	prevProviders := tunnel.Providers()
	tunnel.UpdateProxies(map[string]C.Proxy{
		"reason-carrier": muxProxy,
	}, prevProviders)
	proxyStateMu.Unlock()
	t.Cleanup(func() {
		proxyStateMu.Lock()
		tunnel.UpdateProxies(prevProxies, prevProviders)
		proxyStateMu.Unlock()
	})

	tr := &gracefulStopTestTracker{id: "close-reason-tracker"}
	statistic.DefaultManager.Join(tr)
	t.Cleanup(func() { statistic.DefaultManager.Leave(tr) })

	closed := closeConnectionsWithReason("ipc:closeConnections")
	if closed < 1 {
		t.Fatalf("expected at least 1 closed connection, got %d", closed)
	}
	if !tr.closed.Load() {
		t.Fatal("expected tracker to be closed by closeConnectionsWithReason")
	}
	if carrier.closed.Load() == 0 {
		t.Fatal("expected SingMux carrier pool to reset on closeConnectionsWithReason")
	}
}

func TestPatchSelectGroupDynamicTrafficBadgeAlignment(t *testing.T) {
	t.Run("stripDynamicTrafficBadge_positive_and_negative_boundaries", func(t *testing.T) {
		positive := []struct {
			in   string
			stem string
		}{
			{in: "443-新加坡01|📊227.33GB", stem: "443-新加坡01"},
			{in: "香港01 | 剩余 128.4 GB", stem: "香港01"},
			{in: "日本01 [99.5GiB]", stem: "日本01"},
			{in: "美国01 (流量 50MB)", stem: "美国01"},
			{in: "台湾01/可用 1.2TB", stem: "台湾01"},
			{in: "新加坡02、余量 512MiB", stem: "新加坡02"},
			{in: "韩国01 | left 10gb", stem: "韩国01"},
			{in: "德国01 | remaining 200.5 KiB", stem: "德国01"},
			{in: "节点A (100B)", stem: "节点A"},
			{in: "节点B | 📊 0.5 PB", stem: "节点B"},
			{in: "节点C [剩余 3TiB]", stem: "节点C"},
			{in: "节点D (1.5PiB)", stem: "节点D"},
			{in: "香港01 | 10/100GB", stem: "香港01"},
			{in: "香港01 | 10.5GB/200GB", stem: "香港01"},
			{in: "德国01 - 📊 900B", stem: "德国01"},
			{in: "香港01 | 剩余流量 128.4 GB", stem: "香港01"},
			{in: "香港01 | 剩余：128.4 GB", stem: "香港01"},
			{in: "狮城01 / remaining traffic 12.5 TB", stem: "狮城01"},
			{in: "美国01 | 📊 剩余=512 MiB", stem: "美国01"},
			{in: "节点X | 📈 10.5GiB / 🔋 20GiB", stem: "节点X"},
			{in: "日本01 : 可用流量 50GB", stem: "日本01"},
			{in: "韩国01 — 已用流量 10GB / 流量剩余 90GB", stem: "韩国01"},
			{in: "台湾01 · 📉 88GiB", stem: "台湾01"},
			{in: "节点Z | 💾 1.5TB", stem: "节点Z"},
			{in: "节点W (剩余流量: 200MB)", stem: "节点W"},
			{in: "节点V【可用：64GiB】", stem: "节点V"},
			{in: "节点U - [10/100GB]", stem: "节点U"},
		}
		for _, tc := range positive {
			gotStem, stripped := stripDynamicTrafficBadge(tc.in)
			if !stripped || gotStem != tc.stem {
				t.Fatalf("stripDynamicTrafficBadge(%q) = (%q, %v), want (%q, true)", tc.in, gotStem, stripped, tc.stem)
			}
		}

		negative := []string{
			"香港 01",
			"香港01 2x",
			"香港01 | 倍率 2x",
			"香港01 [IEPL]",
			"|📊227.33GB",
			"香港01 | 延迟 200ms",
			"香港01 | 剩余",
			"新加坡01 100GB",
			"443-新加坡01",
			"HK-10GB",
			"节点-100GB",
			"香港01-剩余10GB",
			"节点A (10GB]",
			"",
		}
		for _, raw := range negative {
			gotStem, stripped := stripDynamicTrafficBadge(raw)
			if stripped || gotStem != raw {
				t.Fatalf("stripDynamicTrafficBadge(%q) = (%q, %v), want (%q, false)", raw, gotStem, stripped, raw)
			}
		}
	})

	t.Run("resolveUpdatedProxySelection_exact_unique_and_ambiguous", func(t *testing.T) {
		// Exact match beats stem match.
		if got := resolveUpdatedProxySelection("香港01 | 10GB", []string{"香港01 | 10GB", "香港01 | 20GB"}); got != "香港01 | 10GB" {
			t.Fatalf("expected exact match, got %q", got)
		}

		// Old badge -> new badge.
		if got := resolveUpdatedProxySelection("443-新加坡01|📊227.33GB", []string{"香港01|📊100GB", "443-新加坡01|📊198.12GB"}); got != "443-新加坡01|📊198.12GB" {
			t.Fatalf("expected old->new badge alignment, got %q", got)
		}

		// Old badge -> bare stem.
		if got := resolveUpdatedProxySelection("443-新加坡01|📊227.33GB", []string{"香港01", "443-新加坡01"}); got != "443-新加坡01" {
			t.Fatalf("expected old->bare alignment, got %q", got)
		}

		// Bare stem -> new badge.
		if got := resolveUpdatedProxySelection("443-新加坡01", []string{"香港01|📊100GB", "443-新加坡01|📊198.12GB"}); got != "443-新加坡01|📊198.12GB" {
			t.Fatalf("expected bare->new alignment, got %q", got)
		}

		// Ambiguous candidates sharing same stem -> keep original.
		if got := resolveUpdatedProxySelection("香港01 | 5GB", []string{"香港01 | 10GB", "香港01 | 20GB"}); got != "香港01 | 5GB" {
			t.Fatalf("expected ambiguous candidates to return original, got %q", got)
		}

		// Ambiguous bare + badged sharing same stem -> keep original.
		if got := resolveUpdatedProxySelection("香港01 | 5GB", []string{"香港01", "香港01 | 20GB"}); got != "香港01 | 5GB" {
			t.Fatalf("expected ambiguous bare+badged candidates to return original, got %q", got)
		}

		// Duplicate identical candidates deduplicate instead of triggering ambiguity.
		if got := resolveUpdatedProxySelection("443-新加坡01|📊227.33GB", []string{"443-新加坡01|📊198.12GB", "443-新加坡01|📊198.12GB"}); got != "443-新加坡01|📊198.12GB" {
			t.Fatalf("expected duplicate identical candidate to deduplicate and align, got %q", got)
		}

		// Neither stripped -> must NOT replace solely due to TrimSpace differences.
		if got := resolveUpdatedProxySelection(" 香港01 ", []string{"香港01"}); got != " 香港01 " {
			t.Fatalf("expected unstripped whitespace difference NOT to replace, got %q", got)
		}

		// No match -> keep original.
		if got := resolveUpdatedProxySelection("日本01 | 5GB", []string{"香港01 | 10GB"}); got != "日本01 | 5GB" {
			t.Fatalf("expected unmatched stem to return original, got %q", got)
		}
	})

	t.Run("patchSelectGroupOnProxies_supports_All_and_real_outboundgroup_Selector", func(t *testing.T) {
		// 1) Custom All() []string selector double.
		doubleAdapter, doubleProxy := newAgentStabilitySelectGroupProxy(
			"ProxyAll",
			[]string{"香港01|📊100GB", "443-新加坡01|📊180.00GB"},
			"香港01|📊100GB",
		)
		patchSelectGroupOnProxies(
			map[string]C.Proxy{"ProxyAll": doubleProxy},
			map[string]string{"ProxyAll": "443-新加坡01|📊227.33GB"},
		)
		if got := doubleAdapter.Now(); got != "443-新加坡01|📊180.00GB" {
			t.Fatalf("expected All() selector aligned to \"443-新加坡01|📊180.00GB\", got %q", got)
		}

		// 2) Real mihomo *outboundgroup.Selector (uses Proxies() []C.Proxy).
		leafHK := newAgentStabilityLeafProxy("香港01|📊100GB", C.Trojan)
		leafSG := newAgentStabilityLeafProxy("443-新加坡01|📊180.00GB", C.Trojan)
		leafDup1 := newAgentStabilityLeafProxy("美国01 | 10GB", C.Trojan)
		leafDup2 := newAgentStabilityLeafProxy("美国01 | 20GB", C.Trojan)
		groupProxies := []C.Proxy{leafHK, leafSG, leafDup1, leafDup2}
		hc := provider.NewHealthCheck(groupProxies, C.DefaultTestURL, 5000, 0, true, nil)
		prov, err := provider.NewCompatibleProvider("patch-select-provider", groupProxies, hc)
		if err != nil {
			t.Fatalf("NewCompatibleProvider failed: %v", err)
		}
		t.Cleanup(func() { _ = prov.Close() })

		emptyFallback := adapter.NewProxy(outbound.NewCompatible())
		realSelector, err := outboundgroup.NewSelector(
			outboundgroup.GroupCommonOption{Name: "Proxy"},
			outboundgroup.SelectorOption{},
			emptyFallback,
			[]cp.ProxyProvider{prov},
		)
		if err != nil {
			t.Fatalf("NewSelector failed: %v", err)
		}
		realProxy := adapter.NewProxy(realSelector)

		patchSelectGroupOnProxies(
			map[string]C.Proxy{"Proxy": realProxy},
			map[string]string{"Proxy": "443-新加坡01|📊227.33GB"},
		)
		if got := realSelector.Now(); got != "443-新加坡01|📊180.00GB" {
			t.Fatalf("expected real *outboundgroup.Selector aligned to \"443-新加坡01|📊180.00GB\", got %q", got)
		}

		// Ambiguous target on real selector keeps fallback/previous rather than mis-aligning.
		realSelector.ForceSet("香港01|📊100GB")
		patchSelectGroupOnProxies(
			map[string]C.Proxy{"Proxy": realProxy},
			map[string]string{"Proxy": "美国01 | 5GB"},
		)
		if got := realSelector.Now(); got != "香港01|📊100GB" {
			t.Fatalf("expected ambiguous ForceSet not to match wrong 美国01 node (Now=%q)", got)
		}
	})
}
