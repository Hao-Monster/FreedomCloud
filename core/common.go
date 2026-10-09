package main

import (
	b "bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/log"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"golang.org/x/sync/semaphore"
)

var (
	currentConfig          *config.Config
	version                atomic.Int32
	isRunning              = false
	runLock                contextMutex
	testDelaySem           = semaphore.NewWeighted(50)
	proxyDescMu            sync.RWMutex
	proxyDescriptions      = map[string]string{}
	pendingTunEnable       = false
	currentTestURL         = "https://www.gstatic.com/generate_204"
	minHealthCheckInterval = 5 * time.Second
)

type ExternalProviders []ExternalProvider

func (a ExternalProviders) Len() int           { return len(a) }
func (a ExternalProviders) Less(i, j int) bool { return a[i].Name < a[j].Name }
func (a ExternalProviders) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }

// proxiesWithProviders merges proxies from tunnel and all proxy providers
func proxiesWithProviders() map[string]constant.Proxy {
	allProxies := make(map[string]constant.Proxy)
	for name, proxy := range tunnel.Proxies() {
		if _, internal := proxy.(*strictProxyRoute); internal {
			continue
		}
		allProxies[name] = proxy
	}
	for _, p := range tunnel.Providers() {
		for _, proxy := range p.Proxies() {
			name := proxy.Name()
			allProxies[name] = proxy
		}
	}
	return allProxies
}

func computeMinHealthCheckInterval(rawConfig *config.RawConfig) {
	min := 300
	for _, g := range rawConfig.ProxyGroup {
		var iv int
		switch v := g["interval"].(type) {
		case int:
			iv = v
		case float64:
			iv = int(v)
		case json.Number:
			iv64, _ := v.Int64()
			iv = int(iv64)
		}
		if iv > 0 && iv < min {
			min = iv
		}
	}
	d := time.Duration(min) * time.Second
	// Floor at 30s (was 5s): a tiny/misconfigured group interval would otherwise url-test
	// every proxy as often as every 5s while foreground — bursts of TLS handshakes
	// (CPU + radio + data) for marginally fresher latency numbers.
	if d < 30*time.Second {
		d = 30 * time.Second
	}
	log.Infoln("[HealthCheck] computed min interval from %d groups: %s", len(rawConfig.ProxyGroup), d)
	minHealthCheckInterval = d
}

// extractProxyDescriptionsFromRaw caches custom server descriptions by proxy name.
func extractProxyDescriptionsFromRaw(rawConfig *config.RawConfig) {
	descriptions := make(map[string]string, len(rawConfig.Proxy))
	for _, proxy := range rawConfig.Proxy {
		nameValue, ok := proxy["name"]
		if !ok {
			continue
		}
		name, ok := nameValue.(string)
		if !ok || name == "" {
			continue
		}
		description := ""
		if value, ok := proxy["serverDescription"]; ok {
			if text, ok := value.(string); ok {
				description = text
			}
		}
		if description == "" {
			if value, ok := proxy["server-description"]; ok {
				if text, ok := value.(string); ok {
					description = text
				}
			}
		}
		if description == "" {
			continue
		}
		descriptions[name] = description
	}
	proxyDescMu.Lock()
	proxyDescriptions = descriptions
	proxyDescMu.Unlock()
}

// proxiesWithDescriptions injects serverDescription for each proxy in API response.
func proxiesWithDescriptions() map[string]interface{} {
	result := make(map[string]interface{})
	for name, proxy := range proxiesWithProviders() {
		data, err := json.Marshal(proxy)
		if err != nil {
			continue
		}
		item := make(map[string]interface{})
		if err := json.Unmarshal(data, &item); err != nil {
			continue
		}
		proxyDescMu.RLock()
		desc, hasDesc := proxyDescriptions[name]
		proxyDescMu.RUnlock()
		if hasDesc && desc != "" {
			item["serverDescription"] = desc
		}
		result[name] = item
	}
	return result
}

func getExternalProvidersRaw() map[string]cp.Provider {
	eps := make(map[string]cp.Provider)
	for n, p := range tunnel.Providers() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	for n, p := range tunnel.RuleProviders() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	return eps
}

func toExternalProvider(p cp.Provider) (*ExternalProvider, error) {
	switch pp := p.(type) {
	case *provider.ProxySetProvider:
		// Get SubscriptionInfo via JSON marshal (field is unexported in original mihomo)
		var subInfo *provider.SubscriptionInfo
		data, err := json.Marshal(pp)
		if err == nil {
			var apiData struct {
				SubscriptionInfo *provider.SubscriptionInfo `json:"subscriptionInfo"`
			}
			_ = json.Unmarshal(data, &apiData)
			subInfo = apiData.SubscriptionInfo
		}
		return &ExternalProvider{
			Name:             pp.Name(),
			Type:             pp.Type().String(),
			VehicleType:      pp.VehicleType().String(),
			Count:            pp.Count(),
			UpdateAt:         pp.UpdatedAt(),
			Path:             pp.Vehicle().Path(),
			SubscriptionInfo: subInfo,
		}, nil
	case *rp.RuleSetProvider:
		return &ExternalProvider{
			Name:        pp.Name(),
			Type:        pp.Type().String(),
			VehicleType: pp.VehicleType().String(),
			Count:       pp.Count(),
			UpdateAt:    pp.UpdatedAt(),
			Path:        pp.Vehicle().Path(),
		}, nil
	default:
		return nil, errors.New("not external provider")
	}
}

func sideUpdateExternalProvider(p cp.Provider, bytes []byte) error {
	switch pp := p.(type) {
	case *provider.ProxySetProvider:
		_, _, err := pp.SideUpdate(bytes)
		if err != nil {
			return err
		}
		return nil
	case *rp.RuleSetProvider:
		_, _, err := pp.SideUpdate(bytes)
		if err != nil {
			return err
		}
		return nil
	default:
		return errors.New("not external provider")
	}
}

// updateListeners recreates all listeners from current config
func updateListeners() {
	if !isRunning {
		return
	}
	if currentConfig == nil {
		return
	}
	listeners := inboundListenersWithStrictLocked()
	general := currentConfig.General
	listener.PatchInboundListeners(listeners, tunnel.Tunnel, true)
	listener.SetAllowLan(general.AllowLan)
	inbound.SetSkipAuthPrefixes(general.SkipAuthPrefixes)
	inbound.SetAllowedIPs(general.LanAllowedIPs)
	inbound.SetDisAllowedIPs(general.LanDisAllowedIPs)
	listener.SetBindAddress(general.BindAddress)
	listener.ReCreateHTTP(general.Port, tunnel.Tunnel)
	listener.ReCreateSocks(general.SocksPort, tunnel.Tunnel)
	listener.ReCreateRedir(general.RedirPort, tunnel.Tunnel)
	listener.ReCreateTProxy(general.TProxyPort, tunnel.Tunnel)
	listener.ReCreateMixed(general.MixedPort, tunnel.Tunnel)
	listener.ReCreateShadowSocks(general.ShadowSocksConfig, tunnel.Tunnel)
	listener.ReCreateVmess(general.VmessConfig, tunnel.Tunnel)
	listener.ReCreateTuic(general.TuicServer, tunnel.Tunnel)
	// Desktop builds may include the `cmfa` tag, so gate TUN only on Android.
	if runtime.GOOS != "android" {
		listener.ReCreateTun(general.Tun, tunnel.Tunnel)
	}
}

// stopListeners stops all active listeners
func stopListeners() {
	clearStrictIngressForConfigChangeLocked()
	listener.ReCreateHTTP(0, tunnel.Tunnel)
	listener.ReCreateSocks(0, tunnel.Tunnel)
	listener.ReCreateRedir(0, tunnel.Tunnel)
	listener.ReCreateTProxy(0, tunnel.Tunnel)
	listener.ReCreateMixed(0, tunnel.Tunnel)
	listener.ReCreateShadowSocks("", tunnel.Tunnel)
	listener.ReCreateVmess("", tunnel.Tunnel)
	listener.ReCreateTuic(LC.TuicServer{}, tunnel.Tunnel)
	if runtime.GOOS != "android" {
		listener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
	}
	listener.Cleanup()
}

func patchSelectGroup(mapping map[string]string) {
	for name, proxy := range proxiesWithProviders() {
		outbound, ok := proxy.(*adapter.Proxy)
		if !ok {
			continue
		}

		selector, ok := outbound.ProxyAdapter.(outboundgroup.SelectAble)
		if !ok {
			continue
		}

		selected, exist := mapping[name]
		if !exist {
			continue
		}

		selector.ForceSet(selected)
	}
}

// Dependency upgrades must not silently change the stack for an absent option
// or a rejected configuration. Explicit user stack choices remain untouched.
func defaultCoreRawConfig() *config.RawConfig {
	defaults := config.DefaultRawConfig()
	defaults.Tun.Stack = constant.TunGvisor
	return defaults
}

func defaultSetupParams() *SetupParams {
	return &SetupParams{
		Config:      defaultCoreRawConfig(),
		TestURL:     "https://www.gstatic.com/generate_204",
		SelectedMap: map[string]string{},
	}
}

func readFile(path string) ([]byte, error) {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	return data, err
}

func updateConfig(params *UpdateParams) error {
	runLock.Lock()
	defer runLock.Unlock()
	if currentConfig == nil {
		return nil
	}
	if params == nil {
		return errors.New("update parameters are required")
	}
	// Bind the authenticated controller before mutating other live settings.
	if params.ExternalController != nil || params.ControllerEnabled != nil {
		candidate := *currentConfig
		controller := *currentConfig.Controller
		if params.ExternalController != nil {
			controller.ExternalController = *params.ExternalController
		}
		candidate.Controller = &controller
		enabled := runtimeControllerEnabled
		if params.ControllerEnabled != nil {
			enabled = *params.ControllerEnabled
		}
		if err := recreateRuntimeController(effectiveControllerConfig(&candidate, enabled)); err != nil {
			return err
		}
		currentConfig.Controller = &controller
		runtimeControllerEnabled = enabled
	}
	general := currentConfig.General
	if params.MixedPort != nil {
		general.MixedPort = *params.MixedPort
	}
	if params.Sniffing != nil {
		general.Sniffing = *params.Sniffing
		tunnel.SetSniffing(general.Sniffing)
	}
	if params.FindProcessMode != nil {
		general.FindProcessMode = *params.FindProcessMode
		tunnel.SetFindProcessMode(general.FindProcessMode)
	}
	if params.TCPConcurrent != nil {
		general.TCPConcurrent = *params.TCPConcurrent
		dialer.SetTcpConcurrent(general.TCPConcurrent)
	}
	if params.Interface != nil {
		general.Interface = *params.Interface
		dialer.DefaultInterface.Store(general.Interface)
	}
	if params.UnifiedDelay != nil {
		general.UnifiedDelay = *params.UnifiedDelay
		adapter.UnifiedDelay.Store(general.UnifiedDelay)
	}
	if params.Mode != nil {
		general.Mode = *params.Mode
		tunnel.SetMode(general.Mode)
	}
	if params.LogLevel != nil {
		general.LogLevel = *params.LogLevel
		log.SetLevel(general.LogLevel)
	}
	if params.IPv6 != nil {
		general.IPv6 = *params.IPv6
		resolver.DisableIPv6 = !general.IPv6
	}
	if params.Tun != nil {
		general.Tun.Enable = params.Tun.Enable
		pendingTunEnable = params.Tun.Enable
		if params.Tun.AutoRoute != nil {
			general.Tun.AutoRoute = *params.Tun.AutoRoute
		}
		if params.Tun.Device != nil {
			general.Tun.Device = *params.Tun.Device
		}
		if params.Tun.RouteAddress != nil {
			general.Tun.RouteAddress = *params.Tun.RouteAddress
		}
		if params.Tun.DNSHijack != nil {
			general.Tun.DNSHijack = *params.Tun.DNSHijack
		}
		if params.Tun.Stack != nil {
			general.Tun.Stack = *params.Tun.Stack
		}
	}

	refreshRuntimeListeners()
	if err := restoreRuntimeStrictIngress(); err != nil {
		return errors.New("macOS strict ingress could not be restored after configuration update")
	}
	return nil
}

func setupConfig(params *SetupParams) error {
	runLock.Lock()
	defer runLock.Unlock()
	if params == nil || params.Config == nil {
		return errors.New("configuration is required")
	}
	raw, err := json.Marshal(params.Config)
	if err != nil {
		return fmt.Errorf("serialize candidate configuration: %w", err)
	}
	parseStart := time.Now()
	candidate, err := config.ParseRawConfig(params.Config)
	if err != nil {
		return err
	}
	log.Infoln("[Setup] ParseRawConfig took %s", time.Since(parseStart))
	if activeStrictIngress != nil {
		if _, _, err := buildStrictIngressListeners(&activeStrictIngress.request, candidate); err != nil {
			return err
		}
	}
	if macStrictIngressIntent != nil {
		if _, _, err := buildStrictIngressListeners(macStrictIngressIntent, candidate); err != nil {
			return err
		}
	}
	controllerEnabled := true // setup preserves the complete profile controller configuration
	if err := recreateRuntimeController(effectiveControllerConfig(candidate, controllerEnabled)); err != nil {
		return err
	}
	previous, previousPending, previousControllerEnabled := currentConfig, pendingTunEnable, runtimeControllerEnabled
	clearRuntimeStrictIngress()
	currentConfig = candidate
	candidatePending := candidate.General.Tun.Enable
	if runtime.GOOS == "android" || !isRunning {
		candidate.General.Tun.Enable = false
	}
	applyStart := time.Now()
	applyRuntimeConfig(candidate, true)
	log.Infoln("[Setup] executor.ApplyConfig took %s", time.Since(applyStart))
	candidate.General.Tun.Enable = candidatePending
	pendingTunEnable = candidatePending
	selectRuntimeGroups(params.SelectedMap)
	refreshRuntimeListeners()
	if restoreErr := restoreRuntimeStrictIngress(); restoreErr != nil {
		clearRuntimeStrictIngress()
		currentConfig, pendingTunEnable = previous, previousPending
		if previous == nil {
			// This is rollback after an apply failure, never an invalid-input
			// fallback. A dormant config releases candidate DNS/NTP/providers and
			// proxy listeners even though there is no previous generation.
			dormant, cleanupErr := config.ParseRawConfig(defaultCoreRawConfig())
			if cleanupErr == nil {
				applyRuntimeConfig(dormant, true)
				cleanupErr = recreateRuntimeController(effectiveControllerConfig(dormant, false))
			}
			return errors.Join(fmt.Errorf("initial configuration strict ingress failed: %w", restoreErr), cleanupErr)
		}
		previousTun := previous.General.Tun.Enable
		if runtime.GOOS == "android" || !isRunning {
			previous.General.Tun.Enable = false
		}
		applyRuntimeConfig(previous, true)
		previous.General.Tun.Enable = previousTun
		controllerErr := recreateRuntimeController(effectiveControllerConfig(previous, previousControllerEnabled))
		refreshRuntimeListeners()
		strictErr := restoreRuntimeStrictIngress()
		return errors.Join(fmt.Errorf("configuration strict ingress failed: %w", restoreErr), controllerErr, strictErr)
	}
	appliedRawConfig = raw
	runtimeControllerEnabled = controllerEnabled
	extractProxyDescriptionsFromRaw(params.Config)
	computeMinHealthCheckInterval(params.Config)
	resetHealthCheckForwarderState()
	if params.TestURL != "" {
		currentTestURL = params.TestURL
	}
	cancelAllDelayTasks("configChanged")

	// Kick off pings immediately so the UI shows latencies as soon as the
	// profile loads, without waiting for the user to start TUN or for each
	// provider's own healthcheck-interval to elapse. The forwarder is started
	// here (not only on Start) and keeps running until shutdown.
	startRuntimeHealthChecks()

	// Notify Flutter that all providers are loaded
	sendMessage(Message{
		Type: LoadedMessage,
		Data: "all",
	})

	return nil
}

func UnmarshalJson(data []byte, v any) error {
	decoder := json.NewDecoder(b.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(v); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return errors.New("configuration has trailing JSON data")
	}
	return nil
}
