package main

import (
	b "bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/dialer"
	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/resource"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/log"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/sirupsen/logrus"
	"golang.org/x/sync/semaphore"
)

var (
	currentConfig               *config.Config
	version                     atomic.Int32
	isRunning                   = false
	runLock                     contextMutex
	// Lock hierarchy: runLock -> proxyStateMu. Never acquire runLock while holding proxyStateMu.
	proxyStateMu                sync.RWMutex
	// Leaf lock guarding mmdb.IPInstance() reload/close independently of proxyStateMu.
	mmdbMu                      sync.RWMutex
	configuredFindProcessMode   atomic.Int32
	externalControllerListening atomic.Bool
	testDelaySem                = semaphore.NewWeighted(50)
	proxyDescMu                 sync.RWMutex
	proxyDescriptions           = map[string]string{}
	pendingTunEnable            = false
	skipListenerTunRecreate     = false
	currentRawListeners         []map[string]any
	currentListenersClosed      = false
	currentTestURL              = "https://www.gstatic.com/generate_204"
	minHealthCheckInterval      = 5 * time.Second
	emitLoadedProviderMessage   = func(name string) {
		sendMessage(Message{
			Type: LoadedMessage,
			Data: name,
		})
	}
)

func init() {
	configureCoreStdoutLogLevel()
	resource.SetFCXProviderUpdatedCallback(func(name string) {
		if !isInit.Load() {
			return
		}
		emitLoadedProviderMessage(name)
	})
}

// configureCoreStdoutLogLevel keeps mihomo's stdout logrus sink at InfoLevel by
// default even when the profile or UI sets `log-level: debug`. UI log
// subscribers (`log.Subscribe()`) continue to receive every debug event via
// `mihomo/log`, while Helper/Agent disk log files are protected from
// per-packet debug log floods (`XTLS Vision padding`, `[DNS] cache hit`, etc.).
func configureCoreStdoutLogLevel() {
	if os.Getenv("FCX_CORE_STDOUT_DEBUG") == "1" {
		logrus.SetLevel(logrus.DebugLevel)
		return
	}
	logrus.SetLevel(logrus.InfoLevel)
}

func refreshRuntimeListenersWithoutTun() {
	previousSkip := skipListenerTunRecreate
	skipListenerTunRecreate = true
	defer func() {
		skipListenerTunRecreate = previousSkip
	}()
	refreshRuntimeListeners()
}

func applyRuntimeConfigLocked(cfg *config.Config, force bool) {
	proxyStateMu.Lock()
	defer proxyStateMu.Unlock()
	applyRuntimeConfig(cfg, force)
	configureCoreStdoutLogLevel()
}

func applyConfigForRuntimeStateLocked(cfg *config.Config) {
	if cfg == nil || cfg.General == nil {
		applyRuntimeConfigLocked(cfg, true)
		return
	}
	effective := *cfg
	general := *cfg.General
	if runtime.GOOS == "android" || !isRunning {
		general.Tun.Enable = false
	}
	if general.FindProcessMode == P.FindProcessAlways &&
		!uiActive.Load() &&
		!externalControllerListening.Load() {
		general.FindProcessMode = P.FindProcessStrict
	}
	if runtime.GOOS != "android" && !isRunning {
		general.Port = 0
		general.SocksPort = 0
		general.RedirPort = 0
		general.TProxyPort = 0
		general.MixedPort = 0
		general.ShadowSocksConfig = ""
		general.VmessConfig = ""
		general.TuicServer = LC.TuicServer{}
		effective.Listeners = map[string]constant.InboundListener{}
		effective.Tunnels = nil
	}
	effective.General = &general
	applyRuntimeConfigLocked(&effective, true)
}

func controllerHasActiveEndpoint(cfg *config.Config, enabled bool) bool {
	if !enabled || cfg == nil || cfg.Controller == nil {
		return false
	}
	c := cfg.Controller
	return c.ExternalController != "" ||
		c.ExternalControllerTLS != "" ||
		c.ExternalControllerUnix != "" ||
		c.ExternalControllerPipe != ""
}

func syncEffectiveFindProcessMode() {
	configured := P.FindProcessMode(configuredFindProcessMode.Load())
	effective := configured
	if configured == P.FindProcessAlways &&
		!uiActive.Load() &&
		!externalControllerListening.Load() {
		effective = P.FindProcessStrict
	}
	tunnel.SetFindProcessMode(effective)
}

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

// buildProxyDescriptionsFromRaw constructs an immutable map of custom server descriptions by proxy name.
func buildProxyDescriptionsFromRaw(rawConfig *config.RawConfig) map[string]string {
	if rawConfig == nil || len(rawConfig.Proxy) == 0 {
		return map[string]string{}
	}
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
	return descriptions
}

func currentProxyDescriptions() map[string]string {
	proxyDescMu.RLock()
	descriptions := proxyDescriptions
	proxyDescMu.RUnlock()
	return descriptions
}

func setProxyDescriptions(descriptions map[string]string) {
	if descriptions == nil {
		descriptions = map[string]string{}
	}
	proxyDescMu.Lock()
	proxyDescriptions = descriptions
	proxyDescMu.Unlock()
}

// extractProxyDescriptionsFromRaw caches custom server descriptions by proxy name.
func extractProxyDescriptionsFromRaw(rawConfig *config.RawConfig) {
	setProxyDescriptions(buildProxyDescriptionsFromRaw(rawConfig))
}

// injectJSONStringField splices `"<key>":"<escapedValue>"` into a serialized JSON
// object without unmarshaling it into a dynamic map[string]any.
func injectJSONStringField(rawObject []byte, key string, value string) ([]byte, bool) {
	trimmed := b.TrimSpace(rawObject)
	if len(trimmed) < 2 || trimmed[0] != '{' || trimmed[len(trimmed)-1] != '}' {
		return nil, false
	}
	encodedKey, err := json.Marshal(key)
	if err != nil {
		return nil, false
	}
	encodedValue, err := json.Marshal(value)
	if err != nil {
		return nil, false
	}
	body := b.TrimSpace(trimmed[1 : len(trimmed)-1])
	extra := len(encodedKey) + 1 + len(encodedValue) + 2
	out := make([]byte, 0, len(trimmed)+extra)
	out = append(out, trimmed[:len(trimmed)-1]...)
	if len(body) > 0 {
		out = append(out, ',')
	}
	out = append(out, encodedKey...)
	out = append(out, ':')
	out = append(out, encodedValue...)
	out = append(out, '}')
	return out, true
}

// proxiesWithDescriptions injects serverDescription for each proxy in API response.
func proxiesWithDescriptions() map[string]interface{} {
	all := proxiesWithProviders()
	descMap := currentProxyDescriptions()
	result := make(map[string]interface{}, len(all))
	for name, proxy := range all {
		data, err := json.Marshal(proxy)
		if err != nil {
			continue
		}
		if len(descMap) == 0 {
			result[name] = json.RawMessage(data)
			continue
		}
		desc, hasDesc := descMap[name]
		if !hasDesc || desc == "" {
			result[name] = json.RawMessage(data)
			continue
		}
		if injected, ok := injectJSONStringField(data, "serverDescription", desc); ok {
			result[name] = json.RawMessage(injected)
			continue
		}
		item := make(map[string]interface{})
		if err := json.Unmarshal(data, &item); err != nil {
			continue
		}
		item["serverDescription"] = desc
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
		return &ExternalProvider{
			Name:             pp.Name(),
			Type:             pp.Type().String(),
			VehicleType:      pp.VehicleType().String(),
			Count:            pp.Count(),
			UpdateAt:         pp.UpdatedAt(),
			Path:             pp.Vehicle().Path(),
			SubscriptionInfo: pp.SubscriptionInfoFCX(),
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

func rebuildCurrentListenersFromRawLocked() {
	if currentConfig == nil || len(currentRawListeners) == 0 {
		return
	}
	rebuilt := make(map[string]constant.InboundListener, len(currentRawListeners))
	for _, mapping := range currentRawListeners {
		inboundListener, err := listener.ParseListener(mapping)
		if err != nil {
			return
		}
		rebuilt[inboundListener.Name()] = inboundListener
	}
	currentConfig.Listeners = rebuilt
	currentListenersClosed = false
}

// updateListeners recreates all listeners from current config
func updateListeners() {
	if !isRunning {
		return
	}
	if currentConfig == nil {
		return
	}
	if currentListenersClosed && len(currentRawListeners) > 0 {
		rebuildCurrentListenersFromRawLocked()
	}
	listeners := inboundListenersWithStrictLocked()
	general := currentConfig.General
	listener.PatchInboundListeners(listeners, tunnel.Tunnel, true)
	listener.PatchTunnel(currentConfig.Tunnels, tunnel.Tunnel)
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
	if runtime.GOOS != "android" && !skipListenerTunRecreate {
		recreateRuntimeTun(general.Tun, tunnel.Tunnel)
	}
}

// stopListeners stops all active listeners, drains tracked active connections
// while the TUN stack is still alive so local sockets receive clean FIN/RST
// instead of hanging, and tears down TUN in a single deterministic pass.
func stopListeners() {
	clearStrictIngressForConfigChangeLocked()
	listener.PatchInboundListeners(map[string]constant.InboundListener{}, tunnel.Tunnel, true)
	if currentConfig != nil && len(currentConfig.Listeners) > 0 {
		currentListenersClosed = true
	}
	listener.PatchTunnel(nil, tunnel.Tunnel)
	listener.ReCreateHTTP(0, tunnel.Tunnel)
	listener.ReCreateSocks(0, tunnel.Tunnel)
	listener.ReCreateRedir(0, tunnel.Tunnel)
	listener.ReCreateTProxy(0, tunnel.Tunnel)
	listener.ReCreateMixed(0, tunnel.Tunnel)
	listener.ReCreateShadowSocks("", tunnel.Tunnel)
	listener.ReCreateVmess("", tunnel.Tunnel)
	listener.ReCreateTuic(LC.TuicServer{}, tunnel.Tunnel)
	// Drain tracked TCP/UDP connections and upstream DNS pools BEFORE closing
	// Wintun/gVisor so active packet pumps release cleanly without closeFailed.
	closeConnections()
	resolver.ResetConnection()
	listener.Cleanup()
	closeConnections()
	resolver.StoreFakePoolState()
}

func patchSelectGroupOnProxies(proxies map[string]constant.Proxy, mapping map[string]string) {
	if len(proxies) == 0 || len(mapping) == 0 {
		return
	}
	for name, proxy := range proxies {
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

func patchSelectGroup(mapping map[string]string) {
	proxyStateMu.Lock()
	defer proxyStateMu.Unlock()
	patchSelectGroupOnProxies(proxiesWithProviders(), mapping)
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
		externalControllerListening.Store(controllerHasActiveEndpoint(currentConfig, enabled))
		syncEffectiveFindProcessMode()
	}
	general := currentConfig.General
	listenersChanged := activeStrictIngress != nil || macStrictIngressIntent != nil
	if params.AllowLan != nil && general.AllowLan != *params.AllowLan {
		general.AllowLan = *params.AllowLan
		listenersChanged = true
	}
	if params.MixedPort != nil && general.MixedPort != *params.MixedPort {
		general.MixedPort = *params.MixedPort
		listenersChanged = true
	}
	if params.Sniffing != nil {
		general.Sniffing = *params.Sniffing
		tunnel.SetSniffing(general.Sniffing)
	}
	if params.FindProcessMode != nil {
		general.FindProcessMode = *params.FindProcessMode
		configuredFindProcessMode.Store(int32(general.FindProcessMode))
		syncEffectiveFindProcessMode()
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
	modeChanged := false
	if params.Mode != nil {
		if general.Mode != *params.Mode {
			modeChanged = true
		}
		general.Mode = *params.Mode
		tunnel.SetMode(general.Mode)
	}
	if params.LogLevel != nil {
		general.LogLevel = *params.LogLevel
		log.SetLevel(general.LogLevel)
		configureCoreStdoutLogLevel()
	}
	if params.IPv6 != nil {
		general.IPv6 = *params.IPv6
		resolver.DisableIPv6 = !general.IPv6
	}
	tunChanged := false
	if params.Tun != nil {
		if general.Tun.Enable != params.Tun.Enable || pendingTunEnable != params.Tun.Enable {
			listenersChanged = true
			tunChanged = true
		}
		general.Tun.Enable = params.Tun.Enable
		pendingTunEnable = params.Tun.Enable
		if params.Tun.AutoRoute != nil && general.Tun.AutoRoute != *params.Tun.AutoRoute {
			general.Tun.AutoRoute = *params.Tun.AutoRoute
			listenersChanged = true
			tunChanged = true
		}
		if params.Tun.Device != nil && general.Tun.Device != *params.Tun.Device {
			general.Tun.Device = *params.Tun.Device
			listenersChanged = true
			tunChanged = true
		}
		if params.Tun.RouteAddress != nil && !slices.Equal(general.Tun.RouteAddress, *params.Tun.RouteAddress) {
			general.Tun.RouteAddress = *params.Tun.RouteAddress
			listenersChanged = true
			tunChanged = true
		}
		if params.Tun.DNSHijack != nil && !slices.Equal(general.Tun.DNSHijack, *params.Tun.DNSHijack) {
			general.Tun.DNSHijack = *params.Tun.DNSHijack
			listenersChanged = true
			tunChanged = true
		}
		if params.Tun.Stack != nil && general.Tun.Stack != *params.Tun.Stack {
			general.Tun.Stack = *params.Tun.Stack
			listenersChanged = true
			tunChanged = true
		}
	}

	if listenersChanged {
		if tunChanged {
			refreshRuntimeListeners()
		} else {
			refreshRuntimeListenersWithoutTun()
		}
	}
	if err := restoreRuntimeStrictIngress(); err != nil {
		return errors.New("macOS strict ingress could not be restored after configuration update")
	}
	if modeChanged {
		reconcileActiveConnectionsLocked(nil, currentConfig)
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
	previousRawListeners, previousListenersClosed := currentRawListeners, currentListenersClosed
	previousDescriptions := currentProxyDescriptions()
	candidateDescriptions := buildProxyDescriptionsFromRaw(params.Config)
	clearRuntimeStrictIngress()
	currentConfig = candidate
	currentRawListeners = slices.Clone(params.Config.Listeners)
	currentListenersClosed = false
	candidatePending := candidate.General.Tun.Enable
	setProxyDescriptions(candidateDescriptions)
	configuredFindProcessMode.Store(int32(candidate.General.FindProcessMode))
	externalControllerListening.Store(controllerHasActiveEndpoint(candidate, controllerEnabled))
	syncEffectiveFindProcessMode()
	patchSelectGroupOnProxies(candidate.Proxies, params.SelectedMap)
	applyStart := time.Now()
	applyConfigForRuntimeStateLocked(candidate)
	externalProviders = getExternalProvidersRaw()
	log.Infoln("[Setup] executor.ApplyConfig took %s", time.Since(applyStart))
	pendingTunEnable = candidatePending
	syncEffectiveFindProcessMode()
	selectRuntimeGroups(params.SelectedMap)
	refreshRuntimeListenersWithoutTun()
	if restoreErr := restoreRuntimeStrictIngress(); restoreErr != nil {
		clearRuntimeStrictIngress()
		currentConfig, pendingTunEnable = previous, previousPending
		currentRawListeners, currentListenersClosed = previousRawListeners, previousListenersClosed
		if previous == nil {
			// This is rollback after an apply failure, never an invalid-input
			// fallback. A dormant config releases candidate DNS/NTP/providers and
			// proxy listeners even though there is no previous generation.
			dormant, cleanupErr := config.ParseRawConfig(defaultCoreRawConfig())
			if cleanupErr == nil {
				applyRuntimeConfigLocked(dormant, true)
				cleanupErr = recreateRuntimeController(effectiveControllerConfig(dormant, false))
			}
			externalProviders = getExternalProvidersRaw()
			setProxyDescriptions(map[string]string{})
			configuredFindProcessMode.Store(int32(P.FindProcessStrict))
			externalControllerListening.Store(false)
			syncEffectiveFindProcessMode()
			return errors.Join(fmt.Errorf("initial configuration strict ingress failed: %w", restoreErr), cleanupErr)
		}
		setProxyDescriptions(previousDescriptions)
		configuredFindProcessMode.Store(int32(previous.General.FindProcessMode))
		externalControllerListening.Store(controllerHasActiveEndpoint(previous, previousControllerEnabled))
		syncEffectiveFindProcessMode()
		if (isRunning || currentListenersClosed) && len(currentRawListeners) > 0 {
			rebuildCurrentListenersFromRawLocked()
		}
		applyConfigForRuntimeStateLocked(previous)
		externalProviders = getExternalProvidersRaw()
		controllerErr := recreateRuntimeController(effectiveControllerConfig(previous, previousControllerEnabled))
		syncEffectiveFindProcessMode()
		refreshRuntimeListenersWithoutTun()
		strictErr := restoreRuntimeStrictIngress()
		return errors.Join(fmt.Errorf("configuration strict ingress failed: %w", restoreErr), controllerErr, strictErr)
	}
	appliedRawConfig = raw
	runtimeControllerEnabled = controllerEnabled
	if previous != nil {
		reconcileActiveConnectionsLocked(previous, candidate)
	}
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

	// Notify Flutter that synchronous providers are loaded; uncached remote
	// providers continue emitting LoadedMessage(name) as background pulls finish.
	emitLoadedProviderMessage("all")

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
