package main

import (
	"encoding/json"
	"testing"
	"time"

	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

func TestGetProxiesAndConnectionsDoNotBlockOnRunLock(t *testing.T) {
	proxyDescMu.Lock()
	oldDesc := proxyDescriptions
	proxyDescriptions = map[string]string{"DIRECT": "Builtin direct"}
	proxyDescMu.Unlock()
	t.Cleanup(func() {
		proxyDescMu.Lock()
		proxyDescriptions = oldDesc
		proxyDescMu.Unlock()
	})

	// Simulate handleStartListener holding runLock for multiple seconds while
	// creating Wintun on Windows.
	runLock.Lock()
	defer runLock.Unlock()

	done := make(chan struct{})
	go func() {
		defer close(done)
		proxies := handleGetProxies()
		encoded, err := json.Marshal(proxies)
		if err != nil {
			t.Errorf("marshal proxies failed: %v", err)
			return
		}
		var decoded map[string]map[string]any
		if err := json.Unmarshal(encoded, &decoded); err != nil {
			t.Errorf("unmarshal proxies failed: %v", err)
			return
		}
		if direct, ok := decoded["DIRECT"]; ok {
			if direct["serverDescription"] != "Builtin direct" {
				t.Errorf("expected serverDescription on DIRECT, got %v", direct["serverDescription"])
			}
		}
		_ = handleGetConnections()
	}()

	select {
	case <-done:
	case <-time.After(250 * time.Millisecond):
		t.Fatal("handleGetProxies / handleGetConnections blocked behind runLock")
	}
}

func TestUpdateConfigSkipsListenerRefreshForNonListenerFields(t *testing.T) {
	calls := isolateConfigRuntime(t)
	listenerRefreshes := 0
	refreshRuntimeListeners = func() { listenerRefreshes++ }

	general := &config.General{
		Mode:     tunnel.Rule,
		LogLevel: log.ERROR,
	}
	general.MixedPort = 7890
	general.AllowLan = false
	currentConfig = &config.Config{
		General:    general,
		Controller: &config.Controller{},
	}
	pendingTunEnable = false
	_ = calls

	mode := tunnel.Global
	level := log.WARNING
	procMode := P.FindProcessStrict
	unified := true
	tcpConc := true
	ipv6 := false
	samePort := 7890
	sameLan := false
	if err := updateConfig(&UpdateParams{
		MixedPort:       &samePort,
		AllowLan:        &sameLan,
		Mode:            &mode,
		LogLevel:        &level,
		FindProcessMode: &procMode,
		UnifiedDelay:    &unified,
		TCPConcurrent:   &tcpConc,
		IPv6:            &ipv6,
	}); err != nil {
		t.Fatal(err)
	}
	if listenerRefreshes != 0 {
		t.Fatalf("expected 0 listener refreshes for unchanged listener/TUN fields, got %d", listenerRefreshes)
	}

	newPort := 7899
	if err := updateConfig(&UpdateParams{MixedPort: &newPort}); err != nil {
		t.Fatal(err)
	}
	if listenerRefreshes != 1 || currentConfig.General.MixedPort != 7899 {
		t.Fatalf("expected 1 listener refresh after MixedPort change, got %d", listenerRefreshes)
	}

	allowLan := true
	if err := updateConfig(&UpdateParams{AllowLan: &allowLan}); err != nil {
		t.Fatal(err)
	}
	if listenerRefreshes != 2 || !currentConfig.General.AllowLan {
		t.Fatalf("expected AllowLan update + listener refresh, got refreshes=%d allowLan=%v", listenerRefreshes, currentConfig.General.AllowLan)
	}
}

func TestUiActiveDynamicallyDowngradesFindProcessAlways(t *testing.T) {
	oldMode := tunnel.FindProcessMode()
	oldUi := uiActive.Load()
	oldConfigured := configuredFindProcessMode.Load()
	oldCtrl := externalControllerListening.Load()
	t.Cleanup(func() {
		uiActive.Store(oldUi)
		configuredFindProcessMode.Store(oldConfigured)
		externalControllerListening.Store(oldCtrl)
		tunnel.SetFindProcessMode(oldMode)
	})

	uiActive.Store(true)
	externalControllerListening.Store(false)
	configuredFindProcessMode.Store(int32(P.FindProcessAlways))
	syncEffectiveFindProcessMode()
	if got := tunnel.FindProcessMode(); got != P.FindProcessAlways {
		t.Fatalf("foreground UI must keep FindProcessAlways, got %v", got)
	}

	// Backgrounded UI without external controller drops to Strict so PROCESS rules
	// still match without scanning TCP/UDP tables on every packet.
	handleSetUiActive(false)
	if got := tunnel.FindProcessMode(); got != P.FindProcessStrict {
		t.Fatalf("background UI without controller must downgrade to FindProcessStrict, got %v", got)
	}

	// Enabling external controller while backgrounded keeps FindProcessAlways for external Web UIs.
	externalControllerListening.Store(true)
	syncEffectiveFindProcessMode()
	if got := tunnel.FindProcessMode(); got != P.FindProcessAlways {
		t.Fatalf("external controller should retain FindProcessAlways, got %v", got)
	}

	// Returning UI to foreground restores FindProcessAlways.
	externalControllerListening.Store(false)
	handleSetUiActive(true)
	if got := tunnel.FindProcessMode(); got != P.FindProcessAlways {
		t.Fatalf("foreground return should restore FindProcessAlways, got %v", got)
	}

	// Explicit FindProcessOff is never upgraded.
	configuredFindProcessMode.Store(int32(P.FindProcessOff))
	handleSetUiActive(false)
	if got := tunnel.FindProcessMode(); got != P.FindProcessOff {
		t.Fatalf("FindProcessOff must remain FindProcessOff, got %v", got)
	}
}

func TestStrictRoutesAndHealthProbeAreRaceFreeUnderConcurrentProxyReads(t *testing.T) {
	prevProxies := tunnel.Proxies()
	prevProviders := tunnel.Providers()
	prevConfig := currentConfig
	t.Cleanup(func() {
		runLock.Lock()
		proxyStateMu.Lock()
		tunnel.UpdateProxies(prevProxies, prevProviders)
		proxyStateMu.Unlock()
		currentConfig = prevConfig
		runLock.Unlock()
	})

	cfg, err := config.Parse([]byte("mode: rule\nproxy-groups:\n  - name: PROXY\n    type: select\n    proxies:\n      - DIRECT\n"))
	if err != nil {
		t.Fatalf("config.Parse failed: %v", err)
	}
	runLock.Lock()
	proxyStateMu.Lock()
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	proxyStateMu.Unlock()
	currentConfig = cfg
	runLock.Unlock()

	stop := make(chan struct{})
	writerDone := make(chan error, 1)
	go func() {
		for gen := uint64(1); gen <= 40; gen++ {
			runLock.Lock()
			req := &StrictIngressRequest{
				Protocol:   strictIngressProtocol,
				Generation: gen,
				Entries: []StrictIngressRequestEntry{{
					TargetGroup: "PROXY",
					Username:    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
					Password:    "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
				}},
			}
			routes, installErr := installStrictProxyRoutes(req, cfg, []strictIngressBuildEntry{{
				TargetGroup:  "PROXY",
				ListenerName: "strict-test",
			}})
			if installErr != nil {
				runLock.Unlock()
				close(stop)
				writerDone <- installErr
				return
			}
			revokeStrictProxyRoutes(routes)
			runLock.Unlock()
		}
		close(stop)
		writerDone <- nil
	}()

	readerDone := make(chan struct{})
	go func() {
		defer close(readerDone)
		for {
			select {
			case <-stop:
				return
			default:
				_ = handleGetProxies()
				ch := make(chan string, 1)
				handleChangeProxy(`{"group-name":"PROXY","proxy-name":"DIRECT"}`, func(s string) { ch <- s })
				<-ch
				probeCh := make(chan string, 1)
				handleHealthProbe(func(s string) { probeCh <- s })
				<-probeCh
			}
		}
	}()

	if err := <-writerDone; err != nil {
		t.Fatalf("strict route writer failed: %v", err)
	}
	<-readerDone
}

func TestSetupConfigCommitsDescriptionsAndProcessModeBeforeListenerRefreshAndRollsBack(t *testing.T) {
	isolateConfigRuntime(t)
	oldUi := uiActive.Load()
	oldMode := tunnel.FindProcessMode()
	oldConfigured := configuredFindProcessMode.Load()
	oldCtrl := externalControllerListening.Load()
	t.Cleanup(func() {
		uiActive.Store(oldUi)
		configuredFindProcessMode.Store(oldConfigured)
		externalControllerListening.Store(oldCtrl)
		tunnel.SetFindProcessMode(oldMode)
	})

	uiActive.Store(false)
	applyRuntimeConfig = func(cfg *config.Config, _ bool) {
		// Mirror Mihomo executor.ApplyConfig overwriting tunnel.findProcessMode
		// with the raw configured mode (FindProcessAlways).
		tunnel.SetFindProcessMode(cfg.General.FindProcessMode)
	}

	previousGen := &config.General{FindProcessMode: P.FindProcessAlways}
	previous := &config.Config{
		General:    previousGen,
		Controller: &config.Controller{},
	}
	currentConfig = previous
	proxyDescMu.Lock()
	proxyDescriptions = map[string]string{"DIRECT": "Old description"}
	proxyDescMu.Unlock()

	var modeDuringListenerBringUp P.FindProcessMode
	var descDuringListenerBringUp string
	refreshRuntimeListeners = func() {
		modeDuringListenerBringUp = tunnel.FindProcessMode()
		proxyDescMu.RLock()
		descDuringListenerBringUp = proxyDescriptions["NodeA"]
		proxyDescMu.RUnlock()
	}

	params := defaultSetupParams()
	params.Config.FindProcessMode = P.FindProcessAlways
	params.Config.Proxy = []map[string]any{{
		"name":              "NodeA",
		"type":              "socks5",
		"server":            "127.0.0.1",
		"port":              1080,
		"serverDescription": "Fresh description",
	}}
	if err := setupConfig(params); err != nil {
		t.Fatalf("setupConfig failed: %v", err)
	}
	if modeDuringListenerBringUp != P.FindProcessStrict {
		t.Fatalf("expected hidden UI to already run FindProcessStrict during listener bring-up, got %v", modeDuringListenerBringUp)
	}
	if descDuringListenerBringUp != "Fresh description" {
		t.Fatalf("expected proxyDescriptions to already contain Fresh description during listener bring-up, got %q", descDuringListenerBringUp)
	}

	// Verify rollback restores previous proxyDescriptions if restoreRuntimeStrictIngress fails.
	restoreRuntimeStrictIngress = func() error { return errSyntheticStrictRollback }
	rollbackParams := defaultSetupParams()
	rollbackParams.Config.Proxy = []map[string]any{{
		"name":              "NodeA",
		"type":              "socks5",
		"server":            "127.0.0.1",
		"port":              1080,
		"serverDescription": "Broken candidate description",
	}}
	if err := setupConfig(rollbackParams); err == nil {
		t.Fatal("expected strict ingress rollback error")
	}
	proxyDescMu.RLock()
	restoredDesc := proxyDescriptions["NodeA"]
	proxyDescMu.RUnlock()
	if restoredDesc != "Fresh description" {
		t.Fatalf("expected rollback to restore previous proxyDescriptions ('Fresh description'), got %q", restoredDesc)
	}
}

var errSyntheticStrictRollback = &syntheticRollbackError{}

type syntheticRollbackError struct{}

func (*syntheticRollbackError) Error() string { return "synthetic strict rollback" }
