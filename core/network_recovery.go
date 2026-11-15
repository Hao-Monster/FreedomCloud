package main

import (
	"fmt"
	"net"
	"net/netip"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	networkRecoveryMu           sync.Mutex
	lastTunRecoveredNetworkKey  string
	lastTunDefaultInterfaceID   string
	lastTunRecoveredAt          time.Time
	networkHealthCheckTimer     *time.Timer
	networkHealthCheckWG        sync.WaitGroup
	networkHealthCheckEpoch     uint64
	networkHealthCheckDebounce  = 250 * time.Millisecond
	tunRecoveryDedupGraceWindow = 15 * time.Second
)

func stopNetworkHealthCheckTimerLocked() {
	if networkHealthCheckTimer != nil {
		if networkHealthCheckTimer.Stop() {
			networkHealthCheckWG.Done()
		}
		networkHealthCheckTimer = nil
	}
}

func init() {
	sing_tun.SetFCXDefaultInterfaceObserver(onTunDefaultInterfaceChanged)
}

func resetNetworkCachesAndResolvers() {
	iface.FlushCache()
	if dr := resolver.DefaultResolver; dr != nil {
		dr.ResetConnection()
		dr.ClearCache()
	}
	if sr := resolver.SystemResolver; sr != nil {
		sr.ResetConnection()
		sr.ClearCache()
	}
}

func resetOutboundAdapterPools() {
	proxyStateMu.RLock()
	proxies := proxiesWithProviders()
	proxyStateMu.RUnlock()
	for _, proxy := range proxies {
		adapterProxy, ok := proxy.(*adapter.Proxy)
		if !ok || adapterProxy == nil {
			continue
		}
		outbound.ResetAdapterConnectionsFCX(adapterProxy.ProxyAdapter)
	}
}

func resetURLTestGroupCachesLocked() {
	for _, proxy := range tunnel.Proxies() {
		adapterProxy, ok := proxy.(*adapter.Proxy)
		if !ok || adapterProxy == nil {
			continue
		}
		if urlTest, ok := adapterProxy.ProxyAdapter.(*outboundgroup.URLTest); ok {
			urlTest.ResetFastCacheFCX()
		}
	}
}

func resetURLTestGroupCaches() {
	proxyStateMu.RLock()
	resetURLTestGroupCachesLocked()
	proxyStateMu.RUnlock()
}

// formatRoutingIdentityPrefixes normalizes usable IP prefixes so IPv4 host
// changes remain distinct while RFC 4941/8981 IPv6 SLAAC temporary addresses
// collapse onto their /64 network prefix.
func formatRoutingIdentityPrefixes(prefixes []netip.Prefix) []string {
	var out []string
	for _, p := range prefixes {
		if !p.IsValid() {
			continue
		}
		rawAddr := p.Addr()
		bits := p.Bits()
		if rawAddr.Is4In6() && bits >= 96 {
			bits -= 96
		}
		addr := rawAddr.Unmap()
		if !addr.IsValid() || addr.IsLoopback() || addr.IsLinkLocalUnicast() || addr.IsUnspecified() {
			continue
		}
		if addr.Is4() {
			out = append(out, netip.PrefixFrom(addr, bits).String())
			continue
		}
		if bits > 64 {
			bits = 64
		}
		out = append(out, netip.PrefixFrom(addr, bits).Masked().String())
	}
	sort.Strings(out)
	return slices.Compact(out)
}

func formatDefaultInterfaceID(name string, index int) string {
	if name == "" {
		return ""
	}
	return fmt.Sprintf("%s#%d", name, index)
}

func isEstablishedNetworkRecoveryKey(k string) bool {
	return k != "" && k != "lost" && !strings.HasPrefix(k, "tentative:")
}

func seedNetworkRecoveryBaseline() {
	iface.FlushCache()
	key := computeActivePhysicalInterfacesKey()
	if key == "" {
		return
	}
	networkRecoveryMu.Lock()
	if !isEstablishedNetworkRecoveryKey(lastTunRecoveredNetworkKey) {
		lastTunRecoveredNetworkKey = key
		lastTunRecoveredAt = time.Now()
	}
	networkRecoveryMu.Unlock()
}

var fcxBenchmarkTunPrefix = netip.MustParsePrefix("198.18.0.0/15")

func isTunLikeInterface(item *iface.Interface, configuredTunDevice string) bool {
	if item == nil {
		return true
	}
	if configuredTunDevice != "" && strings.EqualFold(item.Name, configuredTunDevice) {
		return true
	}
	if item.Flags&net.FlagLoopback != 0 || item.Flags&net.FlagPointToPoint != 0 {
		return true
	}
	lower := strings.ToLower(item.Name)
	if strings.Contains(lower, "wintun") || strings.Contains(lower, "flclash") || strings.HasPrefix(lower, "utun") {
		return true
	}
	for _, prefix := range item.Addresses {
		addr := prefix.Addr().Unmap()
		if addr.Is4() && fcxBenchmarkTunPrefix.Contains(addr) {
			return true
		}
	}
	return false
}

func computeActivePhysicalInterfacesKey() string {
	ifaces, err := iface.Interfaces()
	if err != nil || len(ifaces) == 0 {
		return ""
	}
	tunDevice := listener.GetTunLifecycleStatus().Device
	var parts []string
	for _, item := range ifaces {
		if item == nil || item.Flags&net.FlagUp == 0 {
			continue
		}
		if isTunLikeInterface(item, tunDevice) {
			continue
		}
		addrs := formatRoutingIdentityPrefixes(item.Addresses)
		if len(addrs) == 0 {
			continue
		}
		parts = append(parts, item.Name+"=["+strings.Join(addrs, ",")+"]")
	}
	sort.Strings(parts)
	return strings.Join(parts, ";")
}

func buildSingleInterfaceKey(name string, prefixes []netip.Prefix) string {
	if name == "" {
		return ""
	}
	addrs := formatRoutingIdentityPrefixes(prefixes)
	if len(addrs) == 0 {
		return name
	}
	return name + "=[" + strings.Join(addrs, ",") + "]"
}

func onTunDefaultInterfaceChanged(event sing_tun.FCXDefaultInterfaceEvent) {
	if event.Lost {
		resetNetworkCachesAndResolvers()
		closeConnectionsWithReason("network:lost")
		networkRecoveryMu.Lock()
		lastTunRecoveredNetworkKey = "lost"
		lastTunDefaultInterfaceID = ""
		lastTunRecoveredAt = time.Now()
		networkHealthCheckEpoch++
		stopNetworkHealthCheckTimerLocked()
		networkRecoveryMu.Unlock()
		log.Infoln("[Network] default interface lost; flushed caches and closed stale connections")
		return
	}

	iface.FlushCache()
	key := computeActivePhysicalInterfacesKey()
	usableEventAddrs := formatRoutingIdentityPrefixes(event.Addresses)
	defaultID := formatDefaultInterfaceID(event.Name, event.Index)

	if key == "" && len(usableEventAddrs) == 0 {
		networkRecoveryMu.Lock()
		prevKey := lastTunRecoveredNetworkKey
		lastTunRecoveredNetworkKey = "tentative:" + event.Name
		lastTunDefaultInterfaceID = defaultID
		lastTunRecoveredAt = time.Time{}
		networkHealthCheckEpoch++
		stopNetworkHealthCheckTimerLocked()
		networkRecoveryMu.Unlock()

		if !strings.HasPrefix(prevKey, "tentative:") {
			resetNetworkCachesAndResolvers()
			closeConnectionsWithReason("network:tentative:" + event.Name)
			resetURLTestGroupCaches()
		}
		log.Infoln("[Network] default interface %s acquiring usable address (DAD/DHCP in progress); deferred health checks", event.Name)
		return
	}
	if key == "" {
		key = buildSingleInterfaceKey(event.Name, event.Addresses)
	}

	now := time.Now()
	networkRecoveryMu.Lock()
	prevKey := lastTunRecoveredNetworkKey
	prevDefaultID := lastTunDefaultInterfaceID
	samePhysicalKey := isEstablishedNetworkRecoveryKey(prevKey) && key == prevKey
	sameDefaultIf := prevDefaultID == "" || defaultID == "" || defaultID == prevDefaultID
	if samePhysicalKey && sameDefaultIf {
		lastTunRecoveredAt = now
		if prevDefaultID == "" && defaultID != "" {
			lastTunDefaultInterfaceID = defaultID
		}
		networkRecoveryMu.Unlock()
		log.Debugln("[Network] default interface %s unchanged (%s); preserved active connections", event.Name, key)
		return
	}
	lastTunRecoveredNetworkKey = key
	lastTunDefaultInterfaceID = defaultID
	lastTunRecoveredAt = now
	networkRecoveryMu.Unlock()

	resetNetworkCachesAndResolvers()
	closeConnectionsWithReason("network:changed:" + event.Name)
	resetURLTestGroupCaches()
	scheduleNetworkRecoveryHealthChecks()
	log.Infoln("[Network] default interface switched to %s; reset DNS, closed stale connections, scheduled health checks", event.Name)
}

func recoverFromIPCNetworkReset() {
	resetNetworkCachesAndResolvers()

	key := computeActivePhysicalInterfacesKey()
	now := time.Now()
	networkRecoveryMu.Lock()
	alreadyRecoveredByTun := key != "" &&
		isEstablishedNetworkRecoveryKey(lastTunRecoveredNetworkKey) &&
		key == lastTunRecoveredNetworkKey &&
		now.Sub(lastTunRecoveredAt) < tunRecoveryDedupGraceWindow
	if !alreadyRecoveredByTun && key != "" {
		if lastTunRecoveredNetworkKey != key {
			lastTunDefaultInterfaceID = ""
		}
		lastTunRecoveredNetworkKey = key
		lastTunRecoveredAt = now
	}
	networkRecoveryMu.Unlock()

	if !alreadyRecoveredByTun {
		closeConnectionsWithReason("ipc:resetConnections")
	}
	resetURLTestGroupCaches()
	scheduleNetworkRecoveryHealthChecks()
	log.Infoln("[Network] resetConnections completed (closedConnections=%v)", !alreadyRecoveredByTun)
}

func cancelPendingNetworkRecoveryHealthChecks() {
	networkRecoveryMu.Lock()
	networkHealthCheckEpoch++
	stopNetworkHealthCheckTimerLocked()
	lastTunRecoveredNetworkKey = ""
	lastTunDefaultInterfaceID = ""
	lastTunRecoveredAt = time.Time{}
	networkRecoveryMu.Unlock()
}

func scheduleNetworkRecoveryHealthChecks() {
	networkRecoveryMu.Lock()
	networkHealthCheckEpoch++
	epoch := networkHealthCheckEpoch
	delay := networkHealthCheckDebounce
	stopNetworkHealthCheckTimerLocked()
	networkHealthCheckWG.Add(1)
	networkHealthCheckTimer = time.AfterFunc(delay, func() {
		defer networkHealthCheckWG.Done()
		runNetworkRecoveryHealthChecks(epoch)
	})
	networkRecoveryMu.Unlock()
}

func runNetworkRecoveryHealthChecks(epoch uint64) {
	networkRecoveryMu.Lock()
	current := epoch == networkHealthCheckEpoch
	networkRecoveryMu.Unlock()
	if !current {
		return
	}

	runLock.Lock()
	if currentConfig == nil || (!isRunning && !tunUp.Load()) {
		runLock.Unlock()
		return
	}
	touchProviders()
	proxyStateMu.RLock()
	resetURLTestGroupCachesLocked()
	providerMap := tunnel.Providers()
	providers := make([]cp.ProxyProvider, 0, len(providerMap))
	for _, p := range providerMap {
		if p != nil {
			providers = append(providers, p)
		}
	}
	proxyStateMu.RUnlock()
	runLock.Unlock()

	if len(providers) == 0 {
		return
	}

	var wg sync.WaitGroup
	for _, p := range providers {
		p := p
		wg.Add(1)
		go func() {
			defer wg.Done()
			p.HealthCheck()
		}()
	}
	wg.Wait()

	networkRecoveryMu.Lock()
	stillCurrent := epoch == networkHealthCheckEpoch
	networkRecoveryMu.Unlock()
	if !stillCurrent {
		return
	}

	resetURLTestGroupCaches()
	if uiActive.Load() {
		resetHealthCheckForwarderState()
		forwardHealthCheckDelaysWithTouch(nil, false)
	}
}
