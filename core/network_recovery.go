package main

import (
	"net"
	"net/netip"
	"sort"
	"strings"
	"sync"
	"time"

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
	lastTunRecoveredAt          time.Time
	networkHealthCheckTimer     *time.Timer
	networkHealthCheckEpoch     uint64
	networkHealthCheckDebounce  = 250 * time.Millisecond
	tunRecoveryDedupGraceWindow = 15 * time.Second
)

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

func resetURLTestGroupCachesLocked() {
	for _, proxy := range tunnel.Proxies() {
		if proxy == nil {
			continue
		}
		if urlTest, ok := proxy.Adapter().(*outboundgroup.URLTest); ok {
			urlTest.ResetFastCacheFCX()
		}
	}
}

func resetURLTestGroupCaches() {
	runLock.Lock()
	resetURLTestGroupCachesLocked()
	runLock.Unlock()
}

func formatUsablePrefixes(prefixes []netip.Prefix) []string {
	var out []string
	for _, p := range prefixes {
		addr := p.Addr().Unmap()
		if !addr.IsValid() || addr.IsLoopback() || addr.IsLinkLocalUnicast() || addr.IsUnspecified() {
			continue
		}
		out = append(out, netip.PrefixFrom(addr, p.Bits()).String())
	}
	sort.Strings(out)
	return out
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
	tunDevice := listener.GetTunConf().Device
	var parts []string
	for _, item := range ifaces {
		if item == nil || item.Flags&net.FlagUp == 0 {
			continue
		}
		if isTunLikeInterface(item, tunDevice) {
			continue
		}
		addrs := formatUsablePrefixes(item.Addresses)
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
	addrs := formatUsablePrefixes(prefixes)
	if len(addrs) == 0 {
		return name
	}
	return name + "=[" + strings.Join(addrs, ",") + "]"
}

func onTunDefaultInterfaceChanged(event sing_tun.FCXDefaultInterfaceEvent) {
	resetNetworkCachesAndResolvers()
	closeConnections()

	if event.Lost {
		networkRecoveryMu.Lock()
		lastTunRecoveredNetworkKey = "lost"
		lastTunRecoveredAt = time.Now()
		networkHealthCheckEpoch++
		if networkHealthCheckTimer != nil {
			networkHealthCheckTimer.Stop()
		}
		networkRecoveryMu.Unlock()
		log.Infoln("[Network] default interface lost; flushed caches and closed stale connections")
		return
	}

	key := computeActivePhysicalInterfacesKey()
	if key == "" {
		key = buildSingleInterfaceKey(event.Name, event.Addresses)
	}
	networkRecoveryMu.Lock()
	lastTunRecoveredNetworkKey = key
	lastTunRecoveredAt = time.Now()
	networkRecoveryMu.Unlock()

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
		lastTunRecoveredNetworkKey != "" &&
		lastTunRecoveredNetworkKey != "lost" &&
		key == lastTunRecoveredNetworkKey &&
		now.Sub(lastTunRecoveredAt) < tunRecoveryDedupGraceWindow
	if !alreadyRecoveredByTun && key != "" {
		lastTunRecoveredNetworkKey = key
		lastTunRecoveredAt = now
	}
	networkRecoveryMu.Unlock()

	if !alreadyRecoveredByTun {
		closeConnections()
	}
	resetURLTestGroupCaches()
	scheduleNetworkRecoveryHealthChecks()
	log.Infoln("[Network] resetConnections completed (closedConnections=%v)", !alreadyRecoveredByTun)
}

func cancelPendingNetworkRecoveryHealthChecks() {
	networkRecoveryMu.Lock()
	networkHealthCheckEpoch++
	if networkHealthCheckTimer != nil {
		networkHealthCheckTimer.Stop()
		networkHealthCheckTimer = nil
	}
	lastTunRecoveredNetworkKey = ""
	lastTunRecoveredAt = time.Time{}
	networkRecoveryMu.Unlock()
}

func scheduleNetworkRecoveryHealthChecks() {
	networkRecoveryMu.Lock()
	networkHealthCheckEpoch++
	epoch := networkHealthCheckEpoch
	delay := networkHealthCheckDebounce
	if networkHealthCheckTimer != nil {
		networkHealthCheckTimer.Stop()
	}
	networkHealthCheckTimer = time.AfterFunc(delay, func() {
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
	resetURLTestGroupCachesLocked()
	providerMap := tunnel.Providers()
	providers := make([]cp.ProxyProvider, 0, len(providerMap))
	for _, p := range providerMap {
		if p != nil {
			providers = append(providers, p)
		}
	}
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
