package main

import (
	"context"
	"net"
	"net/netip"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	D "github.com/miekg/dns"
)

type networkRecoveryFakeResolver struct {
	resetCount atomic.Int32
	clearCount atomic.Int32
}

func (r *networkRecoveryFakeResolver) LookupIP(ctx context.Context, host string) ([]netip.Addr, error) {
	return nil, nil
}
func (r *networkRecoveryFakeResolver) LookupIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	return nil, nil
}
func (r *networkRecoveryFakeResolver) LookupIPv6(ctx context.Context, host string) ([]netip.Addr, error) {
	return nil, nil
}
func (r *networkRecoveryFakeResolver) ResolveECH(ctx context.Context, host string) ([]byte, error) {
	return nil, nil
}
func (r *networkRecoveryFakeResolver) ExchangeContext(ctx context.Context, m *D.Msg) (*D.Msg, error) {
	return nil, nil
}
func (r *networkRecoveryFakeResolver) Invalid() bool { return true }
func (r *networkRecoveryFakeResolver) ClearCache()   { r.clearCount.Add(1) }
func (r *networkRecoveryFakeResolver) ResetConnection() {
	r.resetCount.Add(1)
}

type networkRecoveryFakeProvider struct {
	name             string
	healthCheckCount atomic.Int32
	touchCount       atomic.Int32
}

func (p *networkRecoveryFakeProvider) Name() string                      { return p.name }
func (p *networkRecoveryFakeProvider) VehicleType() cp.VehicleType       { return cp.Compatible }
func (p *networkRecoveryFakeProvider) Type() cp.ProviderType             { return cp.Proxy }
func (p *networkRecoveryFakeProvider) Initial() error                    { return nil }
func (p *networkRecoveryFakeProvider) Update() error                     { return nil }
func (p *networkRecoveryFakeProvider) Proxies() []C.Proxy                { return nil }
func (p *networkRecoveryFakeProvider) Count() int                        { return 0 }
func (p *networkRecoveryFakeProvider) Touch()                            { p.touchCount.Add(1) }
func (p *networkRecoveryFakeProvider) HealthCheck()                      { p.healthCheckCount.Add(1) }
func (p *networkRecoveryFakeProvider) HealthCheckURL() string            { return "https://cp.cloudflare.com/generate_204" }
func (p *networkRecoveryFakeProvider) RegisterHealthCheckTask(url string, expectedStatus utils.IntRanges[uint16], filter string, interval uint) {
}
func (p *networkRecoveryFakeProvider) Version() uint32       { return 1 }
func (p *networkRecoveryFakeProvider) Close() error          { return nil }
func (p *networkRecoveryFakeProvider) SubscriptionInfo() any { return nil }

func TestHandleResetConnectionsFlushesIfaceClearsDNSCacheAndTriggersProviderHealthCheck(t *testing.T) {
	isolateHealthCheckForwarder(t)

	prevResolver := resolver.DefaultResolver
	fakeRes := &networkRecoveryFakeResolver{}
	resolver.DefaultResolver = fakeRes
	t.Cleanup(func() {
		resolver.DefaultResolver = prevResolver
	})

	prevProviders := tunnel.Providers()
	fakeProv := &networkRecoveryFakeProvider{name: "auto-group-provider"}
	tunnel.UpdateProxies(tunnel.Proxies(), map[string]cp.ProxyProvider{
		fakeProv.name: fakeProv,
	})
	t.Cleanup(func() {
		tunnel.UpdateProxies(tunnel.Proxies(), prevProviders)
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

	// Prime iface cache before resetConnections.
	_, _ = iface.Interfaces()

	if ok := handleResetConnections(); !ok {
		t.Fatal("expected handleResetConnections to return true")
	}

	if fakeRes.resetCount.Load() < 1 {
		t.Fatalf("expected DefaultResolver.ResetConnection() to run synchronously, got %d", fakeRes.resetCount.Load())
	}
	if fakeRes.clearCount.Load() < 1 {
		t.Fatalf("expected DefaultResolver.ClearCache() to run on resetConnections, got %d", fakeRes.clearCount.Load())
	}

	deadline := time.Now().Add(1500 * time.Millisecond)
	for time.Now().Before(deadline) && fakeProv.healthCheckCount.Load() == 0 {
		time.Sleep(25 * time.Millisecond)
	}
	if fakeProv.healthCheckCount.Load() < 1 {
		t.Fatalf("expected provider HealthCheck() to be triggered after network reset, got %d", fakeProv.healthCheckCount.Load())
	}
}

func TestTunDefaultInterfaceChangeClosesStaleConnectionsAndDeduplicatesLaggingIPCReset(t *testing.T) {
	isolateHealthCheckForwarder(t)
	prevDebounce := networkHealthCheckDebounce
	networkHealthCheckDebounce = 30 * time.Millisecond
	t.Cleanup(func() {
		networkHealthCheckDebounce = prevDebounce
		cancelPendingNetworkRecoveryHealthChecks()
	})

	restoreIface := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index: 30,
			MTU:   1500,
			Name:  "WLAN",
			Flags: net.FlagUp | net.FlagBroadcast,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("172.23.104.177/24"),
			},
		},
		{
			Index: 68,
			MTU:   9000,
			Name:  "FlClashX",
			Flags: net.FlagUp | net.FlagPointToPoint,
			Addresses: []netip.Prefix{
				netip.MustParsePrefix("198.18.0.1/16"),
			},
		},
	})
	defer restoreIface()

	prevResolver := resolver.DefaultResolver
	fakeRes := &networkRecoveryFakeResolver{}
	resolver.DefaultResolver = fakeRes
	t.Cleanup(func() {
		resolver.DefaultResolver = prevResolver
	})

	prevProviders := tunnel.Providers()
	fakeProv := &networkRecoveryFakeProvider{name: "tun-switch-provider"}
	tunnel.UpdateProxies(tunnel.Proxies(), map[string]cp.ProxyProvider{
		fakeProv.name: fakeProv,
	})
	t.Cleanup(func() {
		tunnel.UpdateProxies(tunnel.Proxies(), prevProviders)
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

	// 1. Default interface lost: closes active connections immediately, clears DNS cache, does NOT run remote HealthCheck.
	lostTracker := &gracefulStopTestTracker{id: "wifi-lost-tracker-1"}
	statistic.DefaultManager.Join(lostTracker)
	t.Cleanup(func() { statistic.DefaultManager.Leave(lostTracker) })

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{Lost: true})
	if !lostTracker.closed.Load() {
		t.Fatal("expected lost default interface to close stale tracked connections")
	}
	time.Sleep(80 * time.Millisecond)
	if fakeProv.healthCheckCount.Load() != 0 {
		t.Fatalf("expected 0 provider HealthChecks while default route is lost, got %d", fakeProv.healthCheckCount.Load())
	}

	// 2. Default interface switched to new hotspot IP: closes half-open connections and triggers HealthCheck.
	switchTracker := &gracefulStopTestTracker{id: "wifi-switch-tracker-2"}
	statistic.DefaultManager.Join(switchTracker)
	t.Cleanup(func() { statistic.DefaultManager.Leave(switchTracker) })

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "WLAN",
		Index:     30,
		Addresses: []netip.Prefix{netip.MustParsePrefix("172.23.104.177/24")},
	})
	if !switchTracker.closed.Load() {
		t.Fatal("expected default interface switch to close stale connections")
	}

	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) && fakeProv.healthCheckCount.Load() == 0 {
		time.Sleep(15 * time.Millisecond)
	}
	if fakeProv.healthCheckCount.Load() < 1 {
		t.Fatal("expected provider HealthCheck() after default interface restored")
	}

	// 3. A brand-new healthy connection opened on the new WiFi must NOT be killed
	// when Windows NCSI fires a lagging resetConnections IPC a few seconds later
	// with the exact same physical interface IP.
	freshTracker := &gracefulStopTestTracker{id: "fresh-new-wifi-conn-3"}
	statistic.DefaultManager.Join(freshTracker)
	t.Cleanup(func() { statistic.DefaultManager.Leave(freshTracker) })

	if ok := handleResetConnections(); !ok {
		t.Fatal("expected handleResetConnections to succeed")
	}
	if freshTracker.closed.Load() {
		t.Fatal("lagging IPC resetConnections on already-recovered physical IP killed newly established connection")
	}
}
