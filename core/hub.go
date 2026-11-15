package main

import (
	"context"
	"core/state"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"sort"
	"strconv"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	coreLifecycleMu       sync.Mutex
	isInit                atomic.Bool
	externalProviders     = map[string]cp.Provider{}
	logSubscriber         observable.Subscription[log.Event]
	healthCheckStopCh     chan struct{}
	healthCheckChMu       sync.Mutex
	healthCheckSweepMu    sync.Mutex
	healthCheckMu         sync.Mutex
	healthCheckGeneration uint64
	healthCheckSeen       = map[healthCheckKey]healthCheckSignature{}
	requestStopCh         chan struct{}
	requestChMu           sync.Mutex
	requestMu             sync.Mutex
	requestEpoch          uint64
	requestSeen           = map[string]uint64{}
	requestsActive        atomic.Bool
	// uiActive reflects whether the Flutter UI is in the foreground. When false
	// (app backgrounded) the request forwarder is paused and the health-check
	// forwarder slows to backgroundHealthCheckInterval, so the core stops pinging
	// every proxy and waking Flutter for a UI nobody is looking at.
	uiActive atomic.Bool
	// tunUp is true while the VpnService TUN is up (set in handleStartTun, cleared in
	// handleStopTun/handleShutdown). A headless tile/boot start brings the TUN up via
	// Core.startTun WITHOUT calling startListener, so isRunning stays false — yet the
	// connections "Journal" (request forwarder) must still run when the UI is
	// foregrounded. Gating the forwarder on (isRunning || tunUp) covers that path too,
	// while it stays uiActive-gated so it never polls during standby.
	tunUp atomic.Bool
	// screenActive mirrors the device screen state (pushed by the Android
	// SuspendModule; defaults to true so desktop and pre-signal starts keep the
	// previous behaviour). Unlike uiActive it stays true while the app is merely
	// backgrounded — it gates provider touching, not UI emits: lazy provider/group
	// health checks must keep running at their config interval while the user is
	// on the device (fallback groups go stale otherwise), and stop only when the
	// screen is dark.
	screenActive atomic.Bool
	// lastProviderTouchNs is the unix-nano time of the last touchProviders() run,
	// used by the screen-on catch-up to decide whether checks went dormant.
	lastProviderTouchNs atomic.Int64
)

// While the UI is backgrounded, keep proxy providers warm at this slow cadence
// (instead of minHealthCheckInterval) so url-test/fallback groups don't go stale,
// without spamming pings/UI updates.
const backgroundHealthCheckInterval = 5 * time.Minute

type healthCheckKey struct {
	proxyName string
	testURL   string
}

type healthCheckSignature struct {
	timestamp int64
	delay     uint16
}

const (
	runtimeGCPercent              = 100
	androidRuntimeMemoryLimitByte = 96 * 1024 * 1024
	desktopRuntimeMemoryLimitByte = 512 * 1024 * 1024
)

func runtimeMemoryLimitForGOOS(goos string) int64 {
	if goos == "android" {
		return androidRuntimeMemoryLimitByte
	}
	return desktopRuntimeMemoryLimitByte
}

func configureRuntimeMemory() {
	// GOGC=off retained every allocation until the soft limit, so the core sat
	// close to its cap even while idle. Go's default proportional collector is a
	// better throughput/RSS balance; Android keeps a 96 MiB bound against OEM
	// background killers, whereas desktop uses 512 MiB so GeoSite/GeoIP + Wintun
	// (~100-140 MiB steady RSS) never triggers continuous soft-limit GC thrashing.
	debug.SetGCPercent(runtimeGCPercent)
	debug.SetMemoryLimit(runtimeMemoryLimitForGOOS(runtime.GOOS))
}

func handleInitClash(paramsString string) bool {
	coreLifecycleMu.Lock()
	defer coreLifecycleMu.Unlock()
	var params = InitParams{}
	err := json.Unmarshal([]byte(paramsString), &params)
	if err != nil {
		return false
	}
	// A desktop core started by the privileged helper receives its only allowed
	// data root through SAFE_PATHS. Do not let an IPC peer replace that root
	// after launch; otherwise a local process could turn the SYSTEM core into an
	// arbitrary file reader/writer. Android does not set SAFE_PATHS and keeps its
	// existing in-process initialization path.
	if safePaths := os.Getenv("SAFE_PATHS"); safePaths != "" &&
		!configuredHomeAllowed(params.HomeDir, safePaths) {
		return false
	}
	configureRuntimeMemory()
	version.Store(int32(params.Version))
	catalogPathMu.Lock()
	constant.SetHomeDir(params.HomeDir)
	catalogPathMu.Unlock()
	// Default to "foreground": the main process drives setUiActive(false) when it
	// backgrounds. A headless cold-start has no UI but keeping the foreground
	// cadence here preserves the previous behaviour (no regression).
	uiActive.Store(true)
	requestsActive.Store(false)
	syncEffectiveFindProcessMode()
	// Screen assumed on until the SuspendModule pushes the real state.
	screenActive.Store(true)
	isInit.Store(true)
	resumeCatalogs()
	return true
}

func configuredHomeAllowed(requested string, safePaths string) bool {
	requestedPath, err := filepath.Abs(requested)
	if err != nil {
		return false
	}
	requestedPath = filepath.Clean(requestedPath)
	if resolved, resolveErr := filepath.EvalSymlinks(requestedPath); resolveErr == nil {
		requestedPath = resolved
	}
	requestedPath = normalizeComparablePath(requestedPath)

	for _, allowed := range filepath.SplitList(safePaths) {
		allowedPath, absErr := filepath.Abs(allowed)
		if absErr != nil {
			continue
		}
		allowedPath = filepath.Clean(allowedPath)
		if resolved, resolveErr := filepath.EvalSymlinks(allowedPath); resolveErr == nil {
			allowedPath = resolved
		}
		allowedPath = normalizeComparablePath(allowedPath)
		if requestedPath == allowedPath ||
			(runtime.GOOS == "windows" && strings.EqualFold(requestedPath, allowedPath)) {
			return true
		}
	}
	return false
}

func normalizeComparablePath(path string) string {
	path = filepath.Clean(path)
	if runtime.GOOS != "windows" {
		return path
	}
	const extendedPrefix = `\\?\`
	const extendedUNCPrefix = `\\?\UNC\`
	if strings.HasPrefix(strings.ToUpper(path), strings.ToUpper(extendedUNCPrefix)) {
		return `\\` + path[len(extendedUNCPrefix):]
	}
	if strings.HasPrefix(path, extendedPrefix) {
		return path[len(extendedPrefix):]
	}
	return path
}

func handleStartListener() bool {
	runLock.Lock()
	if isRunning {
		runLock.Unlock()
		return true
	}
	isRunning = true
	if currentConfig != nil {
		// On Android TUN is driven by a file descriptor from VpnService in
		// handleStartTun, not by mihomo's internal TUN — keep cfg flag off.
		// On desktop, updateListeners() below will (re)create the TUN device.
		if runtime.GOOS == "android" {
			currentConfig.General.Tun.Enable = false
		} else {
			currentConfig.General.Tun.Enable = pendingTunEnable
		}
	}
	// setupConfig already ran executor.ApplyConfig when the profile was loaded,
	// so proxies/rules/DNS/providers are live. Starting only needs to (re)bind
	// listeners and (re)create the TUN device — calling ApplyConfig again would
	// re-run updateProxies, loadProvider(wg.Wait()), updateDNS and runtime.GC()
	// for no reason and was the main source of the long "start" delay.
	updateListeners()
	if err := restoreMacStrictIngressLocked(); err != nil {
		isRunning = false
		stopListeners()
		runLock.Unlock()
		return false
	}
	runLock.Unlock()

	go func() {
		resolver.ResetConnection()
		// handleShutdown/handleStopListener can win runLock in the window between
		// releasing it above and this goroutine running. Re-check under runLock
		// before (re)starting the forwarders so a lagging start can't revive them
		// after teardown (a leaked goroutine outliving shutdown). runLock is held
		// across startHealthCheckForwarder because that snapshots minHealthCheckInterval.
		runLock.Lock()
		if !isRunning || currentConfig == nil {
			runLock.Unlock()
			return
		}
		runInitialProviderHealthChecks()
		startHealthCheckForwarder()
		runLock.Unlock()
		// The request forwarder only feeds the connections UI; skip it while the
		// app is backgrounded (setUiActive(true) starts it when the UI returns).
		// startRequestForwarder re-checks isRunning under runLock itself.
		if uiActive.Load() {
			startRequestForwarder()
		}
	}()
	return true
}

func handleStopListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	isRunning = false
	cancelPendingNetworkRecoveryHealthChecks()
	cancelAllDelayTasks("cancelled")
	// Stop both background forwarders while proxy listeners are stopped so the
	// Core does not wake providers to dial remote URLTests behind a stopped UI;
	// handleStartListener restarts them when the user starts the proxy again.
	stopHealthCheckForwarder()
	stopRequestForwarder()
	stopListeners()
	return true
}

func handleGetIsInit() bool {
	return isInit.Load()
}

func handleForceGc() {
	go func() {
		log.Infoln("[APP] request force GC")
		runtime.GC()
	}()
}

func handleShutdown() bool {
	coreLifecycleMu.Lock()
	defer coreLifecycleMu.Unlock()
	clearCatalogsForShutdown(true)
	runLock.Lock()
	defer runLock.Unlock()
	cancelPendingNetworkRecoveryHealthChecks()
	cancelAllDelayTasks("sessionClosed")
	stopHealthCheckForwarder()
	stopRequestForwarder()
	// Tear down the log subscription too: handleStartLog's subscription and pump
	// goroutine would otherwise leak across shutdown. handleStopLog is idempotent
	// and guarded by its own logMu (never takes runLock), so calling it here is safe.
	handleStopLog()
	stopListeners()
	proxyStateMu.Lock()
	executor.Shutdown()
	proxyStateMu.Unlock()
	setProxyDescriptions(map[string]string{})
	configuredFindProcessMode.Store(int32(P.FindProcessStrict))
	externalControllerListening.Store(false)
	syncEffectiveFindProcessMode()
	runtime.GC()
	isInit.Store(false)
	mmdbReady.Store(false)
	requestsActive.Store(false)
	isRunning = false
	tunUp.Store(false)
	currentConfig = nil
	currentRawListeners = nil
	currentListenersClosed = false
	return true
}

func startHealthCheckForwarder() {
	// Reset the emit-dedup so the immediate warm-up emit below actually re-sends
	// the currently-known histories; otherwise a surviving signature (e.g. a
	// desktop stop->start where the executor lives on) is deduped and the UI shows
	// nothing until a value next changes.
	resetHealthCheckForwarderState()
	// setupConfig just ran runInitialProviderHealthChecks; stamp "fresh" so a
	// screen-on edge right after start doesn't fire a redundant catch-up sweep.
	lastProviderTouchNs.Store(time.Now().UnixNano())
	// Stop+recreate atomically under one lock hold. Two starts can overlap
	// (setupConfig and handleStartListener's goroutine, neither serialised by
	// runLock here); a separate stop()-then-create would let the second overwrite
	// healthCheckStopCh while the first goroutine keeps running on an unreferenced
	// channel that nothing can ever close — a leaked forwarder goroutine.
	healthCheckChMu.Lock()
	if healthCheckStopCh != nil {
		close(healthCheckStopCh)
	}
	healthCheckStopCh = make(chan struct{})
	stopCh := healthCheckStopCh
	healthCheckChMu.Unlock()
	// Snapshot minHealthCheckInterval here, where both callers (setupConfig and
	// handleStartListener's start goroutine) hold runLock, and pass it into the
	// goroutine. The global is written under runLock by computeMinHealthCheckInterval,
	// and a config change recomputes it then restarts this forwarder, so the snapshot
	// stays current — and the goroutine never reads the global without the lock.
	minInterval := minHealthCheckInterval
	go func(stopCh chan struct{}, minInterval time.Duration) {
		log.Infoln("[HealthCheck] forwarder fg interval: %s, bg interval: %s", minInterval, backgroundHealthCheckInterval)
		// Warm-up: surface pings the moment the tunnel comes up instead of after a
		// full interval. Emit immediately (re-sends surviving histories), then a few
		// quick follow-ups to catch the fresh url-tests setupConfig kicks off as they
		// complete. Offsets are cumulative (~0, 0.7s, 1.5s, 3s). Dedup keeps repeat
		// ticks cheap and emits are foreground-only.
		for _, d := range []time.Duration{0, 700 * time.Millisecond, 800 * time.Millisecond, 1500 * time.Millisecond} {
			select {
			case <-time.After(d):
				if uiActive.Load() {
					forwardHealthCheckDelaysForRun(stopCh)
				}
			case <-stopCh:
				return
			}
		}
		for {
			// Recompute each cycle so foreground/background/screen transitions take
			// effect on the next tick without restarting the goroutine. Steady-state
			// cadence is the min group/provider interval from the config (minInterval);
			// only a dark screen (or an idle app with no tunnel) drops to the slow tick.
			interval := minInterval
			if !uiActive.Load() && !touchGateOpen() &&
				backgroundHealthCheckInterval > interval {
				interval = backgroundHealthCheckInterval
			}
			select {
			case <-time.After(interval):
				if uiActive.Load() {
					forwardHealthCheckDelaysForRun(stopCh)
				} else if touchGateOpen() {
					// App backgrounded/killed but the screen is on and the tunnel is
					// up: keep touching so lazy provider/group health checks run at
					// their config interval — fallback/url-test groups must not go
					// stale (they keep routing into dead nodes otherwise). UI emits
					// stay foreground-only.
					touchProvidersSafelyForRun(stopCh)
				}
				// Dark screen / no tunnel: do nothing. Real traffic re-warms
				// providers on demand (URLTest dial -> Touch); the screen-on edge
				// resweeps via handleSetScreenActive, and foreground return emits
				// immediately via handleSetUiActive.
			case <-stopCh:
				return
			}
		}
	}(stopCh, minInterval)
}

func stopHealthCheckForwarder() {
	healthCheckChMu.Lock()
	defer healthCheckChMu.Unlock()
	if healthCheckStopCh != nil {
		close(healthCheckStopCh)
		healthCheckStopCh = nil
	}
	// A foreground flush may still be reading histories even without a worker.
	// Retire that snapshot too, so it cannot repopulate state after shutdown.
	resetHealthCheckForwarderState()
}

func resetHealthCheckForwarderState() {
	healthCheckMu.Lock()
	healthCheckGeneration++
	healthCheckSeen = map[healthCheckKey]healthCheckSignature{}
	healthCheckMu.Unlock()
}

func forwardHealthCheckDelays() {
	forwardHealthCheckDelaysForRun(nil)
}

func forwardHealthCheckDelaysForRun(stopCh <-chan struct{}) {
	forwardHealthCheckDelaysWithTouch(stopCh, true)
}

func forwardHealthCheckDelaysWithTouch(stopCh <-chan struct{}, shouldTouch bool) {
	// Foreground flushes and timer ticks must not overtake one another: an old
	// provider snapshot must never prune a newer one. Lock order is sweep -> run
	// -> state; reset/start/stop take state but never sweep. No run/state lock is
	// held while reading histories or dispatching events to native consumers.
	healthCheckSweepMu.Lock()
	defer healthCheckSweepMu.Unlock()
	runLock.Lock()
	if currentConfig == nil {
		runLock.Unlock()
		return
	}
	healthCheckMu.Lock()
	select {
	case <-stopCh:
		healthCheckMu.Unlock()
		runLock.Unlock()
		return
	default:
	}
	generation := healthCheckGeneration
	healthCheckMu.Unlock()
	if shouldTouch {
		touchProviders()
	}
	proxies := proxiesWithProviders()
	runLock.Unlock()

	live := make(map[healthCheckKey]healthCheckSignature, len(proxies))
	for name, proxy := range proxies {
		collectLatestDelay(live, name, "", proxy.DelayHistory())
		for url, state := range proxy.ExtraDelayHistories() {
			collectLatestDelay(live, name, url, state.History)
		}
	}
	healthCheckMu.Lock()
	if generation != healthCheckGeneration {
		healthCheckMu.Unlock()
		return
	}
	var delays []Delay
	for key, signature := range live {
		if previous, seen := healthCheckSeen[key]; seen && previous == signature {
			continue
		}
		value := int32(signature.delay)
		if value == 0 {
			value = -1
		}
		delays = append(delays, Delay{Name: key.proxyName, Url: key.testURL, Value: value})
	}
	// Replace instead of deleting keys: removed nodes/URLs and the old map's
	// high-water bucket allocation can be collected when a provider shrinks.
	// Capacity follows the current directory, without evicting valid dedup state.
	healthCheckSeen = live
	healthCheckMu.Unlock()
	for i := range delays {
		sendMessage(Message{Type: DelayMessage, Data: &delays[i]})
	}
}

// runInitialProviderHealthChecks kicks off one HealthCheck per proxy provider
// in background goroutines, so the UI has pings right after profile load
// without waiting for the provider's own healthcheck-interval to elapse.
// HealthCheck blocks until every URL test finishes, so each provider gets
// its own goroutine to avoid serialising them.
func runInitialProviderHealthChecks() {
	for _, p := range tunnel.Providers() {
		pp, ok := p.(*provider.ProxySetProvider)
		if !ok {
			continue
		}
		go pp.HealthCheck()
	}
}

// touchProviders marks all proxy providers as recently used so that their
// internal lazy health-check goroutines actually execute on the next tick.
// Unlike the previous triggerProviderHealthChecks which called HealthCheck()
// (blocking until every URL test finishes), Touch() returns immediately and
// lets the provider's own background goroutine perform the checks without
// holding runLock for seconds.
//
// Deliberately unfiltered: tunnel.Providers() also contains the per-group
// CompatibleProviders that host url-test/fallback groups' own health checks
// (their url/interval from the config) — the old *ProxySetProvider filter left
// those untouched, so lazy group checks only ran when real traffic dialed
// through the group and fallback aliveness went stale on an idle tunnel.
func touchProviders() {
	for _, p := range tunnel.Providers() {
		p.Touch()
	}
	lastProviderTouchNs.Store(time.Now().UnixNano())
}

// touchGateOpen reports whether providers should be kept warm even though the
// UI is not foregrounded: the user is on the device (screen on) and the tunnel
// is up, so fallback/url-test aliveness must stay current for real traffic.
func touchGateOpen() bool {
	return screenActive.Load() && tunUp.Load()
}

// touchProvidersSafely is forwardHealthCheckDelays' touch step under runLock,
// without emitting delays — used to keep providers warm while the UI is hidden.
func touchProvidersSafely() {
	touchProvidersSafelyForRun(nil)
}

func touchProvidersSafelyForRun(stopCh <-chan struct{}) {
	runLock.Lock()
	defer runLock.Unlock()
	select {
	case <-stopCh:
		return
	default:
	}
	if currentConfig != nil {
		touchProviders()
	}
}

// handleSetUiActive toggles the foreground flag. On the active->inactive edge it
// pauses the request forwarder; on inactive->active it restarts it (when a
// listener is running) and flushes current delays so the UI repopulates at once.
func handleSetUiActive(active bool) {
	// Don't early-return on an unchanged value: a headless-started tunnel can reach the
	// foreground with uiActive already true (no setUiActive(false) edge happened), and
	// we must still idempotently (re)arm the request forwarder and flush current delays.
	// startRequestForwarder/stopRequestForwarder are both no-ops when already in the
	// target state, so re-running on a redundant call is cheap.
	wasActive := uiActive.Swap(active)
	syncEffectiveFindProcessMode()
	if active {
		runLock.Lock()
		running := isRunning
		runLock.Unlock()
		activeTunnel := running || tunUp.Load()
		if activeTunnel {
			startRequestForwarder()
		}
		// Clear the health-check de-dup before flushing. While the tunnel ran headless
		// (tile/boot start, no UI listener attached) the forwarder's delay emits were
		// dropped by emitEvent (listener==nil) yet their signatures were still recorded
		// in healthCheckSeen — so a plain flush here would be fully de-duped and deliver
		// NOTHING to the just-attached UI (the "no pings after a tile start" bug). Reset
		// so the current delay histories re-emit on foreground.
		resetHealthCheckForwarderState()
		go forwardHealthCheckDelaysWithTouch(nil, activeTunnel)
	} else {
		if wasActive {
			cancelAllDelayTasks("uiInactive")
		}
		stopRequestForwarder()
	}
}

// handleSetScreenActive tracks the device screen state (pushed by the Android
// SuspendModule). While the screen is on and the tunnel is up the forwarder
// keeps touching providers so lazy health checks run at their config interval
// even with the UI backgrounded or killed. On the off->on edge, if checks went
// dormant for at least one interval, force an immediate full sweep so
// fallback/url-test groups realign before the user starts browsing.
func handleSetScreenActive(active bool) {
	wasActive := screenActive.Swap(active)
	if !active || wasActive {
		return
	}
	if !tunUp.Load() && !uiActive.Load() {
		return
	}
	runLock.Lock()
	running := isRunning
	hasConfig := currentConfig != nil
	minInterval := minHealthCheckInterval
	runLock.Unlock()
	if !hasConfig || (!running && !tunUp.Load()) {
		return
	}
	if time.Since(time.Unix(0, lastProviderTouchNs.Load())) < minInterval {
		return
	}
	log.Infoln("[HealthCheck] screen-on catch-up: forcing provider health checks")
	touchProvidersSafely()
	for _, p := range tunnel.Providers() {
		go p.HealthCheck()
	}
}

func handleSetRequestsActive(active bool) {
	requestsActive.Store(active)
	if active {
		if uiActive.Load() {
			startRequestForwarder()
			go forwardNewRequests()
		}
	} else {
		stopRequestForwarder()
	}
}

// startRequestForwarder polls the statistic manager for newly opened trackers
// and pushes each one to Flutter via a RequestMessage. Upstream mihomo does
// not expose the statistic.DefaultRequestNotify hook our old Clash.Meta fork
// relied on, so we emulate it with a short-interval poll.
func startRequestForwarder() {
	// Hold runLock across the start decision so a concurrent handleStopListener
	// (which clears isRunning and stops the forwarder under the same lock) can't
	// race us: either we start before the stop, or we observe the cleared flag and
	// don't revive a forwarder for a listener that's no longer running. Callers
	// (handleStartListener's goroutine, handleSetUiActive) never hold runLock here.
	runLock.Lock()
	defer runLock.Unlock()
	// isRunning covers an app-driven start (startListener); tunUp covers a headless
	// tile/boot start (Core.startTun without startListener). Either means the tunnel is
	// up and the connections it carries should feed the Journal once RequestLogView is open.
	if (!isRunning && !tunUp.Load()) || !uiActive.Load() || !requestsActive.Load() {
		return
	}
	requestChMu.Lock()
	if requestStopCh != nil {
		requestChMu.Unlock()
		return
	}
	requestMu.Lock()
	requestEpoch = 0
	requestSeen = map[string]uint64{}
	requestMu.Unlock()
	requestStopCh = make(chan struct{})
	stopCh := requestStopCh
	requestChMu.Unlock()
	go func(stopCh chan struct{}) {
		ticker := time.NewTicker(4 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				forwardNewRequests()
			case <-stopCh:
				return
			}
		}
	}(stopCh)
}

func stopRequestForwarder() {
	requestChMu.Lock()
	defer requestChMu.Unlock()
	if requestStopCh == nil {
		return
	}
	close(requestStopCh)
	requestStopCh = nil
	requestMu.Lock()
	requestEpoch = 0
	requestSeen = map[string]uint64{}
	requestMu.Unlock()
}

func forwardNewRequests() {
	if !requestsActive.Load() || !uiActive.Load() {
		return
	}
	requestMu.Lock()
	defer requestMu.Unlock()
	requestEpoch++
	epoch := requestEpoch
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		id := c.ID()
		_, seen := requestSeen[id]
		requestSeen[id] = epoch
		if seen {
			return true
		}
		sendMessage(Message{
			Type: RequestMessage,
			Data: c.Info(),
		})
		return true
	})
	for id, seenEpoch := range requestSeen {
		if seenEpoch != epoch {
			delete(requestSeen, id)
		}
	}
}

func collectLatestDelay(live map[healthCheckKey]healthCheckSignature, proxyName string, testURL string, history []constant.DelayHistory) {
	if len(history) == 0 {
		return
	}
	latest := history[len(history)-1]
	live[healthCheckKey{proxyName: proxyName, testURL: testURL}] = healthCheckSignature{
		timestamp: latest.Time.UnixNano(),
		delay:     latest.Delay,
	}
}

func handleValidateConfig(bytes []byte) string {
	_, err := config.UnmarshalRawConfig(bytes)
	if err != nil {
		return err.Error()
	}
	return ""
}

func handleGetProxies() interface{} {
	proxyStateMu.RLock()
	defer proxyStateMu.RUnlock()
	return proxiesWithDescriptions()
}

func resolveLeafProxyName(name string, proxies map[string]constant.Proxy) string {
	if name == "" || len(proxies) == 0 {
		return name
	}
	type nowProvider interface {
		Now() string
	}
	curr := name
	visited := make(map[string]struct{}, 4)
	for step := 0; step < 16; step++ {
		if _, seen := visited[curr]; seen {
			return curr
		}
		visited[curr] = struct{}{}
		proxy, ok := proxies[curr]
		if !ok || proxy == nil {
			return curr
		}
		var next string
		if np, ok := proxy.(nowProvider); ok {
			next = np.Now()
		} else if ap := proxy.Adapter(); ap != nil {
			if np, ok := ap.(nowProvider); ok {
				next = np.Now()
			}
		}
		if next == "" || next == curr {
			return curr
		}
		curr = next
	}
	return curr
}

func applySelectorChange(proxies map[string]constant.Proxy, groupName, proxyName string) (prevLeaf, nextLeaf, errMsg string) {
	group, ok := proxies[groupName]
	if !ok {
		return "", "", "Not found group"
	}
	adapterProxy, ok := group.(*adapter.Proxy)
	if !ok {
		return "", "", "Group is not a proxy adapter"
	}
	selector, ok := adapterProxy.ProxyAdapter.(outboundgroup.SelectAble)
	if !ok {
		return "", "", "Group is not selectable"
	}

	prevLeaf = resolveLeafProxyName(groupName, proxies)
	var err error
	if proxyName == "" {
		selector.ForceSet(proxyName)
	} else {
		err = selector.Set(proxyName)
	}
	if err != nil {
		return "", "", err.Error()
	}
	nextLeaf = resolveLeafProxyName(groupName, proxies)
	return prevLeaf, nextLeaf, ""
}

func closeConnectionsForProxySwitch(manager *statistic.Manager, groupName, targetName, prevLeaf, nextLeaf string) {
	if manager == nil {
		return
	}
	if prevLeaf != "" && prevLeaf == nextLeaf {
		log.Debugln("[ProxySwitch] group=%s target=%s leaf=%s unchanged; preserved active connections", groupName, targetName, nextLeaf)
		return
	}

	var toClose []statistic.Tracker
	manager.Range(func(c statistic.Tracker) bool {
		chains := c.Chains()
		if len(chains) == 0 {
			if info := c.Info(); info != nil {
				chains = info.Chain
			}
		}
		if len(chains) == 0 || !slices.Contains(chains, groupName) {
			return true
		}
		if nextLeaf != "" && chains[0] == nextLeaf {
			return true
		}
		toClose = append(toClose, c)
		return true
	})
	for _, c := range toClose {
		_ = c.Close()
	}
	log.Infoln("[ProxySwitch] group=%s target=%s leaf=%s->%s closed=%d", groupName, targetName, prevLeaf, nextLeaf, len(toClose))
}

func changeSelectorProxy(proxies map[string]constant.Proxy, manager *statistic.Manager, params ChangeProxyParams) string {
	if params.GroupName == nil || params.ProxyName == nil {
		return "missing group-name or proxy-name"
	}
	groupName := *params.GroupName
	proxyName := *params.ProxyName
	prevLeaf, nextLeaf, errMsg := applySelectorChange(proxies, groupName, proxyName)
	if errMsg != "" {
		return errMsg
	}
	if params.CloseConnections != nil && *params.CloseConnections {
		closeConnectionsForProxySwitch(manager, groupName, proxyName, prevLeaf, nextLeaf)
	}
	return ""
}

func handleChangeProxy(data string, fn func(string string)) {
	go func() {
		var params = &ChangeProxyParams{}
		err := json.Unmarshal([]byte(data), params)
		if err != nil {
			fn(err.Error())
			return
		}
		if params.GroupName == nil || params.ProxyName == nil {
			fn("missing group-name or proxy-name")
			return
		}

		// Hold proxyStateMu.RLock only across the proxy lookup + selector mutation
		// and leaf resolution, so proxy queries/switches do not stall behind a
		// multi-second listener/Wintun bring-up on runLock while remaining race-free
		// against ApplyConfig/Shutdown, then release before evicting connections.
		proxyStateMu.RLock()
		proxies := proxiesWithProviders()
		prevLeaf, nextLeaf, errMsg := applySelectorChange(proxies, *params.GroupName, *params.ProxyName)
		proxyStateMu.RUnlock()
		if errMsg != "" {
			fn(errMsg)
			return
		}

		if params.CloseConnections != nil && *params.CloseConnections {
			closeConnectionsForProxySwitch(statistic.DefaultManager, *params.GroupName, *params.ProxyName, prevLeaf, nextLeaf)
		}

		fn("")
	}()
}

type trafficSnapshot struct {
	Up   int64 `json:"up"`
	Down int64 `json:"down"`
}

func handleGetTrafficPayload() trafficSnapshot {
	up, down := statistic.DefaultManager.Now()
	return trafficSnapshot{Up: up, Down: down}
}

func handleGetTraffic() string {
	data, err := json.Marshal(handleGetTrafficPayload())
	if err != nil {
		log.Errorln("Error: %v", err)
		return ""
	}
	return string(data)
}

func handleGetTotalTrafficPayload() trafficSnapshot {
	up, down := statistic.DefaultManager.Total()
	return trafficSnapshot{Up: up, Down: down}
}

func handleGetTotalTraffic() string {
	data, err := json.Marshal(handleGetTotalTrafficPayload())
	if err != nil {
		log.Errorln("Error: %v", err)
		return ""
	}
	return string(data)
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

func handleGetConnectionsRaw() json.RawMessage {
	snapshot := statistic.DefaultManager.Snapshot()
	data, err := json.Marshal(snapshot)
	if err != nil {
		log.Errorln("Error: %v", err)
		return json.RawMessage(`{"downloadTotal":0,"uploadTotal":0,"connections":[],"memory":0}`)
	}
	return json.RawMessage(data)
}

func handleGetConnections() string {
	return string(handleGetConnectionsRaw())
}

func handleCloseConnections() bool {
	closeConnectionsWithReason("ipc:closeConnections")
	return true
}

func closeConnections() {
	closeConnectionsWithReason("unspecified")
}

func closeConnectionsWithReason(reason string) int {
	return closeConnectionsBefore(time.Time{}, true, reason)
}

func closeConnectionsBefore(cutoff time.Time, resetPools bool, reason string) int {
	var toClose []statistic.Tracker
	preserved := 0
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		if !cutoff.IsZero() {
			if info := c.Info(); info != nil && !info.Start.IsZero() && info.Start.After(cutoff) {
				preserved++
				return true
			}
		}
		toClose = append(toClose, c)
		return true
	})
	for _, c := range toClose {
		_ = c.Close()
	}
	if resetPools {
		resetOutboundAdapterPools()
	}
	closed := len(toClose)
	if closed > 0 || preserved > 0 || strings.Contains(reason, "ipc") {
		log.Infoln("[Connections] closed=%d preserved=%d reason=%s", closed, preserved, reason)
	}
	return closed
}

func handleResetConnections() bool {
	recoverFromIPCNetworkReset()
	return true
}

func handleCloseConnection(connectionId string) bool {
	c := statistic.DefaultManager.Get(connectionId)
	if c == nil {
		return false
	}
	_ = c.Close()
	return true
}

func handleGetExternalProvidersPayload() []ExternalProvider {
	runLock.Lock()
	defer runLock.Unlock()
	externalProviders = getExternalProvidersRaw()
	eps := make([]ExternalProvider, 0, len(externalProviders))
	for _, p := range externalProviders {
		externalProvider, err := toExternalProvider(p)
		if err != nil {
			continue
		}
		eps = append(eps, *externalProvider)
	}
	sort.Sort(ExternalProviders(eps))
	return eps
}

func handleGetExternalProviders() string {
	data, err := json.Marshal(handleGetExternalProvidersPayload())
	if err != nil {
		return ""
	}
	return string(data)
}

func lookupExternalProviderLocked(name string) (cp.Provider, bool) {
	ep, exist := externalProviders[name]
	if !exist {
		externalProviders = getExternalProvidersRaw()
		ep, exist = externalProviders[name]
	}
	return ep, exist
}

func handleGetExternalProviderPayload(externalProviderName string) *ExternalProvider {
	runLock.Lock()
	defer runLock.Unlock()
	externalProvider, exist := lookupExternalProviderLocked(externalProviderName)
	if !exist {
		return nil
	}
	e, err := toExternalProvider(externalProvider)
	if err != nil {
		return nil
	}
	return e
}

func handleGetExternalProvider(externalProviderName string) string {
	e := handleGetExternalProviderPayload(externalProviderName)
	if e == nil {
		return ""
	}
	data, err := json.Marshal(e)
	if err != nil {
		return ""
	}
	return string(data)
}

func handleUpdateGeoData(geoType string, geoName string, fn func(value string)) {
	go func() {
		var err error
		switch geoType {
		case "MMDB":
			mmdbMu.Lock()
			err = updater.UpdateMMDB()
			mmdbMu.Unlock()
		case "ASN":
			err = updater.UpdateASN()
		case "GeoIp":
			err = updater.UpdateGeoIp()
		case "GeoSite":
			err = updater.UpdateGeoSite()
		}
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

func handleUpdateExternalProvider(providerName string, fn func(value string)) {
	go func() {
		runLock.Lock()
		externalProvider, exist := lookupExternalProviderLocked(providerName)
		runLock.Unlock()
		if !exist {
			fn("external provider is not exist")
			return
		}
		err := externalProvider.Update()
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

func handleSideLoadExternalProvider(providerName string, data []byte, fn func(value string)) {
	go func() {
		// Snapshot the provider under runLock, then release it before the update and
		// the fn (JNI) callback — mirrors handleUpdateExternalProvider and keeps the
		// upcall off the lock. (externalProviders is only mutated under runLock.)
		runLock.Lock()
		externalProvider, exist := lookupExternalProviderLocked(providerName)
		runLock.Unlock()
		if !exist {
			fn("external provider is not exist")
			return
		}
		err := sideUpdateExternalProvider(externalProvider, data)
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

var logMu sync.Mutex

func handleStartLog() {
	logMu.Lock()
	defer logMu.Unlock()
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	logSubscriber = log.Subscribe()
	sub := logSubscriber
	go func() {
		for logData := range sub {
			if logData.LogLevel < log.Level() {
				continue
			}
			if strings.Contains(logData.Payload, "http: Server closed") {
				continue
			}
			// Don't marshal + cross-process IPC every log line to a UI nobody is
			// watching: while the app is backgrounded the log view isn't visible, so
			// forwarding under the standby wakelock is wasted CPU/IPC. (The channel is
			// still drained, so there's no backpressure on the core's logger.)
			if !uiActive.Load() {
				continue
			}
			message := &Message{
				Type: LogMessage,
				Data: logData,
			}
			sendMessage(*message)
		}
	}()
}

func handleStopLog() {
	logMu.Lock()
	defer logMu.Unlock()
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
}

func handleGetCountryCode(ip string, fn func(value string)) {
	go func() {
		// Look up outside locks and invoke fn (a JNI/IPC callback) after
		// resolution finishes to avoid re-entrant deadlocks or contention.
		fn(resolveCountryCode(ip))
	}()
}

func handleGetMemory(fn func(value string)) {
	go func() {
		fn(strconv.FormatUint(statistic.DefaultManager.Memory(), 10))
	}()
}

func handleSetState(params string) {
	runLock.Lock()
	defer runLock.Unlock()
	if err := json.Unmarshal([]byte(params), state.CurrentState); err != nil {
		log.Warnln("[State] unmarshal failed: %v", err)
	}
}

func handleGetConfig(path string) (*config.RawConfig, error) {
	if path == "fcx://runtime" {
		return runtimeConfigSnapshot()
	}
	if !constant.Path.IsSafePath(path) {
		return nil, constant.Path.ErrNotSafePath(path)
	}
	bytes, err := readFile(path)
	if err != nil {
		return nil, err
	}
	prof, err := config.UnmarshalRawConfig(bytes)
	if err != nil {
		return nil, err
	}
	return prof, nil
}

func handleHealthCheck(groupName string, fn func(value string)) {
	runLock.Lock()
	testUrl := currentTestURL
	runLock.Unlock()
	go func() {
		proxyStateMu.RLock()
		rawProxies := tunnel.Proxies()
		proxies := make(map[string]constant.Proxy, len(rawProxies))
		for name, proxy := range rawProxies {
			if groupName != "" && name != groupName {
				continue
			}
			proxies[name] = proxy
		}
		proxyStateMu.RUnlock()
		expectedStatus, _ := utils.NewUnsignedRanges[uint16]("")
		defaultUrl := testUrl

		for name, proxy := range proxies {
			if groupName != "" && name != groupName {
				continue
			}
			group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
			if !ok {
				continue
			}
			testUrl := ""
			for _, p := range group.Providers() {
				if u := p.HealthCheckURL(); u != "" {
					testUrl = u
					break
				}
			}
			if testUrl == "" {
				testUrl = defaultUrl
			}
			log.Infoln("[HealthCheck] testing group: %s url: %s", name, testUrl)
			for _, p := range group.Providers() {
				for _, px := range p.Proxies() {
					sendMessage(Message{
						Type: DelayMessage,
						Data: &Delay{Url: testUrl, Name: px.Name(), Value: 0},
					})
				}
			}
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			dm, err := group.URLTest(ctx, testUrl, expectedStatus)
			cancel()
			if err != nil {
				log.Warnln("[HealthCheck] group %s error: %v", name, err)
				continue
			}
			for proxyName, delay := range dm {
				sendMessage(Message{
					Type: DelayMessage,
					Data: &Delay{Url: testUrl, Name: proxyName, Value: int32(delay)},
				})
			}
			log.Infoln("[HealthCheck] group %s done, %d results", name, len(dm))
		}
		fn("")
	}()
}

// handleHealthProbe is a cheap liveness probe for the background watchdog: a
// SINGLE generate_204 through the currently-selected GLOBAL outbound, instead of
// URL-testing every proxy in every group (which woke the radio to ping the whole
// node list every cycle). Calls fn("ok") on success and fn("") on failure/timeout
// (the Kotlin watchdog treats non-"ok" as a failed cycle and resets connections).
// fn is always called so the JNI callback global ref is released.
func handleHealthProbe(fn func(value string)) {
	runLock.Lock()
	testUrl := currentTestURL
	hasConfig := currentConfig != nil
	runLock.Unlock()
	if !hasConfig {
		fn("")
		return
	}
	go func() {
		proxyStateMu.RLock()
		active := tunnel.Proxies()["GLOBAL"]
		proxyStateMu.RUnlock()
		if active == nil {
			fn("")
			return
		}
		expectedStatus, _ := utils.NewUnsignedRanges[uint16]("")
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		delay, err := active.URLTest(ctx, testUrl, expectedStatus)
		if err != nil || delay == 0 {
			fn("")
			return
		}
		fn("ok")
	}()
}

func handleCrash() {
	panic("handle invoke crash")
}

func handleUpdateConfig(bytes []byte) string {
	var params = &UpdateParams{}
	err := json.Unmarshal(bytes, params)
	if err != nil {
		return err.Error()
	}
	if err := updateConfig(params); err != nil {
		return err.Error()
	}
	return ""
}

func handleSetupConfig(bytes []byte) string {
	var envelope struct {
		Config json.RawMessage `json:"config"`
	}
	if err := json.Unmarshal(bytes, &envelope); err != nil {
		return err.Error()
	}
	if len(envelope.Config) == 0 || string(envelope.Config) == "null" {
		return "configuration is required"
	}
	var params = defaultSetupParams()
	err := UnmarshalJson(bytes, params)
	if err != nil {
		log.Errorln("unmarshalRawConfig error %v", err)
		return err.Error()
	}
	err = setupConfig(params)
	if err != nil {
		return err.Error()
	}
	return ""
}
