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
	lastTunBaselineSeeded       bool
	lastRecoveryFromTun         bool
	lastTunRecoveredAt          time.Time
	networkHealthCheckTimer     *time.Timer
	networkHealthCheckWG        sync.WaitGroup
	networkHealthCheckEpoch     uint64
	networkHealthCheckDebounce  = 250 * time.Millisecond
	tunRecoveryDedupGraceWindow = 30 * time.Second
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
		lastTunDefaultInterfaceID = ""
		lastTunBaselineSeeded = true
		lastRecoveryFromTun = true
		lastTunRecoveredAt = time.Now()
	}
	networkRecoveryMu.Unlock()
}

var fcxBenchmarkTunPrefix = netip.MustParsePrefix("198.18.0.0/15")

var virtualOrTunKeywords = []string{
	"wintun",
	"flclash",
	"vethernet",
	"wsl",
	"hyper-v",
	"vmware",
	"vmnet",
	"vboxnet",
	"virtualbox",
	"tailscale",
	"zerotier",
	"wireguard",
	"tap-windows",
	"loopback",
	"docker",
	"podman",
}

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
	if strings.HasPrefix(lower, "utun") {
		return true
	}
	for _, kw := range virtualOrTunKeywords {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	for _, prefix := range item.Addresses {
		addr := prefix.Addr().Unmap()
		if addr.Is4() && fcxBenchmarkTunPrefix.Contains(addr) {
			return true
		}
	}
	return false
}

func defaultInterfaceHasUsablePrefix(event sing_tun.FCXDefaultInterfaceEvent) bool {
	if len(formatRoutingIdentityPrefixes(event.Addresses)) > 0 {
		return true
	}
	if event.Name == "" && event.Index <= 0 {
		return false
	}
	ifaces, err := iface.Interfaces()
	if err != nil || len(ifaces) == 0 {
		return false
	}
	tunDevice := listener.GetTunLifecycleStatus().Device
	for _, item := range ifaces {
		if item == nil || item.Flags&net.FlagUp == 0 || isTunLikeInterface(item, tunDevice) {
			continue
		}
		matches := false
		if event.Name != "" {
			matches = strings.EqualFold(item.Name, event.Name)
		} else {
			matches = item.Index == event.Index
		}
		if matches && len(formatRoutingIdentityPrefixes(item.Addresses)) > 0 {
			return true
		}
	}
	return false
}

func parseNetworkRecoveryKey(key string) (map[string]map[string]struct{}, bool) {
	if !isEstablishedNetworkRecoveryKey(key) {
		return nil, false
	}
	entries := strings.Split(key, ";")
	result := make(map[string]map[string]struct{}, len(entries))
	for _, entry := range entries {
		idx := strings.Index(entry, "=[")
		if idx <= 0 || !strings.HasSuffix(entry, "]") {
			return nil, false
		}
		ifName := entry[:idx]
		addrsRaw := entry[idx+2 : len(entry)-1]
		if addrsRaw == "" {
			return nil, false
		}
		prefixSet := result[ifName]
		if prefixSet == nil {
			prefixSet = make(map[string]struct{})
			result[ifName] = prefixSet
		}
		for _, p := range strings.Split(addrsRaw, ",") {
			if p == "" {
				return nil, false
			}
			prefixSet[p] = struct{}{}
		}
	}
	return result, len(result) > 0
}

// isPurelyAdditiveInterfaceUpdate reports whether switching from prevKey to newKey
// on the same default interface preserves all previously established prefixes across
// all physical NICs while adding only prefixes from previously absent address families
// on defaultIfName (such as IPv6 RA arriving shortly after DHCPv4).
func isPurelyAdditiveInterfaceUpdate(prevKey, newKey, defaultIfName string) bool {
	if defaultIfName == "" || prevKey == newKey {
		return false
	}
	prevMap, okPrev := parseNetworkRecoveryKey(prevKey)
	newMap, okNew := parseNetworkRecoveryKey(newKey)
	if !okPrev || !okNew {
		return false
	}

	for ifName, prevAddrs := range prevMap {
		if ifName == defaultIfName {
			continue
		}
		newAddrs := newMap[ifName]
		if len(newAddrs) == 0 {
			return false
		}
		for p := range prevAddrs {
			if _, ok := newAddrs[p]; !ok {
				return false
			}
		}
	}

	prevDefault := prevMap[defaultIfName]
	newDefault := newMap[defaultIfName]
	if len(prevDefault) == 0 || len(newDefault) == 0 {
		return false
	}

	var prevHasV4, prevHasV6 bool
	for p := range prevDefault {
		if _, ok := newDefault[p]; !ok {
			return false
		}
		parsed, err := netip.ParsePrefix(p)
		if err != nil {
			return false
		}
		addr := parsed.Addr().Unmap()
		if addr.Is4() {
			prevHasV4 = true
		} else if addr.Is6() {
			prevHasV6 = true
		}
	}

	for p := range newDefault {
		if _, existed := prevDefault[p]; existed {
			continue
		}
		parsed, err := netip.ParsePrefix(p)
		if err != nil {
			return false
		}
		addr := parsed.Addr().Unmap()
		if addr.Is4() && prevHasV4 {
			return false
		}
		if addr.Is6() && prevHasV6 {
			return false
		}
		if !addr.Is4() && !addr.Is6() {
			return false
		}
	}
	return true
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
	observedAt := event.ObservedAt
	if observedAt.IsZero() {
		observedAt = time.Now()
	}

	if event.Lost {
		resetNetworkCachesAndResolvers()
		closeConnectionsBefore(observedAt, true, "network:lost")
		networkRecoveryMu.Lock()
		lastTunRecoveredNetworkKey = "lost"
		lastTunDefaultInterfaceID = ""
		lastTunBaselineSeeded = false
		lastRecoveryFromTun = false
		lastTunRecoveredAt = time.Time{}
		networkHealthCheckEpoch++
		stopNetworkHealthCheckTimerLocked()
		networkRecoveryMu.Unlock()
		log.Infoln("[Network] default interface lost; flushed caches and closed stale connections")
		return
	}

	iface.FlushCache()
	key := computeActivePhysicalInterfacesKey()
	defaultID := formatDefaultInterfaceID(event.Name, event.Index)

	if !defaultInterfaceHasUsablePrefix(event) {
		networkRecoveryMu.Lock()
		prevKey := lastTunRecoveredNetworkKey
		lastTunRecoveredNetworkKey = "tentative:" + event.Name
		lastTunDefaultInterfaceID = defaultID
		lastTunBaselineSeeded = false
		lastRecoveryFromTun = false
		lastTunRecoveredAt = time.Time{}
		networkHealthCheckEpoch++
		stopNetworkHealthCheckTimerLocked()
		networkRecoveryMu.Unlock()

		if !strings.HasPrefix(prevKey, "tentative:") {
			resetNetworkCachesAndResolvers()
			closeConnectionsBefore(observedAt, true, "network:tentative:"+event.Name)
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
	prevSeeded := lastTunBaselineSeeded
	samePhysicalKey := isEstablishedNetworkRecoveryKey(prevKey) && key == prevKey
	sameDefaultIf := (defaultID != "" && prevDefaultID == defaultID) || (prevDefaultID == "" && prevSeeded)
	if samePhysicalKey && sameDefaultIf {
		lastTunBaselineSeeded = false
		if prevDefaultID == "" && defaultID != "" {
			lastTunDefaultInterfaceID = defaultID
		}
		networkRecoveryMu.Unlock()
		log.Debugln("[Network] default interface %s unchanged (%s); preserved active connections", event.Name, key)
		return
	}
	if prevDefaultID != "" && defaultID == prevDefaultID && isPurelyAdditiveInterfaceUpdate(prevKey, key, event.Name) {
		lastTunRecoveredNetworkKey = key
		lastTunBaselineSeeded = false
		networkRecoveryMu.Unlock()
		log.Debugln("[Network] default interface %s additive update (%s); preserved active connections and DNS pools", event.Name, key)
		return
	}
	lastTunRecoveredNetworkKey = key
	lastTunDefaultInterfaceID = defaultID
	lastTunBaselineSeeded = false
	lastRecoveryFromTun = true
	lastTunRecoveredAt = now
	networkRecoveryMu.Unlock()

	resetNetworkCachesAndResolvers()
	closeConnectionsBefore(observedAt, true, "network:changed:"+event.Name)
	resetURLTestGroupCaches()
	scheduleNetworkRecoveryHealthChecks()
	log.Infoln("[Network] default interface switched to %s; reset DNS, closed stale connections, scheduled health checks", event.Name)
}

func recoverFromIPCNetworkReset() {
	ipcStartedAt := time.Now()
	iface.FlushCache()

	key := computeActivePhysicalInterfacesKey()
	networkRecoveryMu.Lock()
	alreadyRecoveredByTun := key != "" &&
		lastRecoveryFromTun &&
		isEstablishedNetworkRecoveryKey(lastTunRecoveredNetworkKey) &&
		key == lastTunRecoveredNetworkKey &&
		!lastTunRecoveredAt.IsZero() &&
		ipcStartedAt.Sub(lastTunRecoveredAt) < tunRecoveryDedupGraceWindow
	if alreadyRecoveredByTun {
		networkRecoveryMu.Unlock()
		log.Debugln("[Network] resetConnections deduplicated within %v after TUN recovery (%s)", tunRecoveryDedupGraceWindow, key)
		return
	}
	if key != "" {
		if lastTunRecoveredNetworkKey != key {
			lastTunDefaultInterfaceID = ""
		}
		lastTunRecoveredNetworkKey = key
	} else {
		lastTunDefaultInterfaceID = ""
	}
	lastTunBaselineSeeded = false
	lastRecoveryFromTun = false
	lastTunRecoveredAt = time.Time{}
	networkRecoveryMu.Unlock()

	resetNetworkCachesAndResolvers()
	closeConnectionsBefore(ipcStartedAt, true, "ipc:resetConnections")
	resetURLTestGroupCaches()
	scheduleNetworkRecoveryHealthChecks()
	log.Infoln("[Network] resetConnections completed (closedConnections=true)")
}

func cancelPendingNetworkRecoveryHealthChecks() {
	networkRecoveryMu.Lock()
	networkHealthCheckEpoch++
	stopNetworkHealthCheckTimerLocked()
	lastTunRecoveredNetworkKey = ""
	lastTunDefaultInterfaceID = ""
	lastTunBaselineSeeded = false
	lastRecoveryFromTun = false
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
