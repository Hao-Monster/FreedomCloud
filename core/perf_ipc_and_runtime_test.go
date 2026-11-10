//go:build !cgo

package main

import (
	"bytes"
	"encoding/json"
	"runtime"
	"strings"
	"testing"
	"time"

	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	logrus "github.com/sirupsen/logrus"
)

func invokeWireActionForTest(t *testing.T, wireJSON string) ([]byte, ActionResult) {
	t.Helper()
	var action Action
	if err := json.Unmarshal([]byte(wireJSON), &action); err != nil {
		t.Fatalf("unmarshal Action failed: %v", err)
	}
	var encoded []byte
	var captured ActionResult
	done := make(chan struct{})
	res := ActionResult{
		Id:     action.Id,
		Method: action.Method,
		Response: func(b []byte) {
			encoded = append([]byte(nil), b...)
			_ = json.Unmarshal(b, &captured)
			close(done)
		},
	}
	handleAction(&action, res)
	<-done
	return encoded, captured
}

func TestActionAcceptsRawObjectDataAndAvoidsDoubleEncodingResponses(t *testing.T) {
	calls := isolateConfigRuntime(t)
	_ = calls

	// 1. Raw JSON object in Action.data (zero string-wrapping from Dart) must be accepted.
	rawSetupWire := `{"id":"setup#1","method":"setupConfig","data":{"config":{"mixed-port":7895,"allow-lan":true},"selected-map":{},"test-url":"https://cp.cloudflare.com/generate_204"}}`
	_, setupRes := invokeWireActionForTest(t, rawSetupWire)
	if setupRes.Code != 0 || setupRes.Data != "" {
		t.Fatalf("expected raw-object setupConfig to succeed, got code=%d data=%v", setupRes.Code, setupRes.Data)
	}

	// 2. Legacy string-encoded Action.data must continue to work identically.
	legacyUpdatePayload, _ := json.Marshal(map[string]any{"mixed-port": 7896})
	legacyUpdateQuoted, _ := json.Marshal(string(legacyUpdatePayload))
	legacyUpdateWire := `{"id":"upd#1","method":"updateConfig","data":` + string(legacyUpdateQuoted) + `}`
	_, updRes := invokeWireActionForTest(t, legacyUpdateWire)
	if updRes.Code != 0 || updRes.Data != "" || currentConfig.General.MixedPort != 7896 {
		t.Fatalf("expected legacy-string updateConfig to succeed, got code=%d data=%v port=%d", updRes.Code, updRes.Data, currentConfig.General.MixedPort)
	}

	// 3. Outbound getConnections, getTraffic, getTotalTraffic, getExternalProviders must NOT double-encode JSON into a quoted string.
	for _, method := range []string{"getConnections", "getTraffic", "getTotalTraffic", "getExternalProviders"} {
		wire, _ := invokeWireActionForTest(t, `{"id":"req#1","method":"`+method+`"}`)
		var envelope struct {
			Data json.RawMessage `json:"data"`
			Code int             `json:"code"`
		}
		if err := json.Unmarshal(wire, &envelope); err != nil {
			t.Fatalf("%s invalid response JSON: %v", method, err)
		}
		trimmed := bytes.TrimSpace(envelope.Data)
		if len(trimmed) == 0 || trimmed[0] == '"' {
			t.Fatalf("%s double-encoded ActionResult.data as JSON string: %s", method, string(trimmed))
		}
	}
}

func TestRequestForwarderStaysIdleUntilRequestsViewIsActive(t *testing.T) {
	oldRunning := isRunning
	oldTunUp := tunUp.Load()
	oldUi := uiActive.Load()
	t.Cleanup(func() {
		stopRequestForwarder()
		isRunning = oldRunning
		tunUp.Store(oldTunUp)
		uiActive.Store(oldUi)
		_, _ = invokeWireActionForTest(t, `{"id":"cleanup","method":"setRequestsActive","data":false}`)
	})

	stopRequestForwarder()
	isRunning = true
	tunUp.Store(true)
	uiActive.Store(true)
	_, _ = invokeWireActionForTest(t, `{"id":"r0","method":"setRequestsActive","data":false}`)

	// Even when proxy is running and UI is foregrounded, forwarder must stay stopped while drawer is closed.
	startRequestForwarder()
	requestChMu.Lock()
	runningWhileDrawerClosed := requestStopCh != nil
	requestChMu.Unlock()
	if runningWhileDrawerClosed {
		t.Fatal("request forwarder started while RequestLogView drawer is closed")
	}

	// Activating RequestLogView starts the forwarder immediately.
	_, activeRes := invokeWireActionForTest(t, `{"id":"r1","method":"setRequestsActive","data":true}`)
	if activeRes.Code != 0 {
		t.Fatalf("setRequestsActive(true) failed: code=%d data=%v", activeRes.Code, activeRes.Data)
	}
	requestChMu.Lock()
	runningWhileDrawerOpen := requestStopCh != nil
	requestChMu.Unlock()
	if !runningWhileDrawerOpen {
		t.Fatal("request forwarder did not start when setRequestsActive(true) was invoked")
	}

	// Closing RequestLogView stops the forwarder immediately.
	_, _ = invokeWireActionForTest(t, `{"id":"r2","method":"setRequestsActive","data":false}`)
	requestChMu.Lock()
	runningAfterClose := requestStopCh != nil
	requestChMu.Unlock()
	if runningAfterClose {
		t.Fatal("request forwarder remained running after setRequestsActive(false)")
	}
}

func TestInjectJSONStringFieldEscapesSpecialCharsWithoutUnmarshaling(t *testing.T) {
	original := []byte(`{"name":"Node-1","type":"Shadowsocks","udp":true}`)
	injected, ok := injectJSONStringField(original, "serverDescription", `HK "IPLC" \ Fast`)
	if !ok {
		t.Fatal("injectJSONStringField returned ok=false")
	}
	var parsed map[string]any
	if err := json.Unmarshal(injected, &parsed); err != nil {
		t.Fatalf("injected JSON invalid: %v (%s)", err, string(injected))
	}
	if parsed["name"] != "Node-1" || parsed["serverDescription"] != `HK "IPLC" \ Fast` {
		t.Fatalf("unexpected parsed map: %#v", parsed)
	}
}

func TestRuntimeConfigSnapshotReflectsLiveGeneralAndTunState(t *testing.T) {
	isolateConfigRuntime(t)
	oldRunning := isRunning
	t.Cleanup(func() { isRunning = oldRunning })

	params := defaultSetupParams()
	params.Config.MixedPort = 7890
	params.Config.AllowLan = false
	params.Config.Tun.Enable = true
	params.Config.Tun.Stack = constant.TunGvisor
	if err := setupConfig(params); err != nil {
		t.Fatal(err)
	}

	isRunning = false
	currentConfig.General.MixedPort = 17890
	currentConfig.General.AllowLan = true
	currentConfig.General.Mode = tunnel.Global
	currentConfig.General.LogLevel = log.WARNING
	currentConfig.General.FindProcessMode = P.FindProcessOff
	currentConfig.Controller.ExternalController = "127.0.0.1:19090"

	snapStopped, err := runtimeConfigSnapshot()
	if err != nil {
		t.Fatal(err)
	}
	if snapStopped.MixedPort != 17890 || !snapStopped.AllowLan || snapStopped.Mode != tunnel.Global || snapStopped.LogLevel != log.WARNING || snapStopped.FindProcessMode != P.FindProcessOff || snapStopped.ExternalController != "127.0.0.1:19090" {
		t.Fatalf("snapshot missed live General/Controller mutations: %+v", snapStopped)
	}
	if snapStopped.Tun.Enable {
		t.Fatal("snapshot reported Tun.Enable=true while listener is stopped")
	}

	isRunning = true
	snapRunning, err := runtimeConfigSnapshot()
	if err != nil {
		t.Fatal(err)
	}
	if !snapRunning.Tun.Enable || snapRunning.Tun.Stack != constant.TunGvisor {
		t.Fatalf("snapshot missed running TUN state: %+v", snapRunning.Tun)
	}
}

func TestCoreStdoutSuppressesDebugWhilePreservingSubscriberStream(t *testing.T) {
	oldLevel := log.Level()
	oldOut := logrus.StandardLogger().Out
	oldLogrusLevel := logrus.GetLevel()
	var stdoutBuf bytes.Buffer
	logrus.SetOutput(&stdoutBuf)
	log.SetLevel(log.DEBUG)
	t.Cleanup(func() {
		log.SetLevel(oldLevel)
		logrus.SetOutput(oldOut)
		logrus.SetLevel(oldLogrusLevel)
	})

	sub := log.Subscribe()
	defer log.UnSubscribe(sub)

	const debugMsg = "XTLS Vision read padding: command=0, payloadLen=1300, paddingLen=176"
	const infoMsg = "[TUN] Tun adapter listening at: 198.18.0.1/16"
	log.Debugln("%s", debugMsg)
	log.Infoln("%s", infoMsg)

	var gotDebugSub, gotInfoSub bool
	deadline := time.After(time.Second)
	for !(gotDebugSub && gotInfoSub) {
		select {
		case ev := <-sub:
			if ev.LogLevel == log.DEBUG && strings.Contains(ev.Payload, debugMsg) {
				gotDebugSub = true
			}
			if ev.LogLevel == log.INFO && strings.Contains(ev.Payload, infoMsg) {
				gotInfoSub = true
			}
		case <-deadline:
			t.Fatalf("timed out waiting for log subscriber events (gotDebug=%v gotInfo=%v)", gotDebugSub, gotInfoSub)
		}
	}

	out := stdoutBuf.String()
	if !strings.Contains(out, infoMsg) {
		t.Fatalf("expected Core stdout to preserve info log %q, got: %s", infoMsg, out)
	}
	if strings.Contains(out, debugMsg) {
		t.Fatalf("expected Core stdout to suppress per-packet debug log %q, got: %s", debugMsg, out)
	}
}

func TestSetupConfigWhileRunningDoesNotRecreateTunTwice(t *testing.T) {
	if runtime.GOOS == "android" {
		t.Skip("desktop TUN lifecycle test")
	}
	isolateConfigRuntime(t)
	oldRunning := isRunning
	oldRecreateTun := recreateRuntimeTun
	oldUi := uiActive.Load()
	oldConfigured := configuredFindProcessMode.Load()
	oldCtrl := externalControllerListening.Load()
	oldMode := tunnel.FindProcessMode()
	t.Cleanup(func() {
		isRunning = oldRunning
		recreateRuntimeTun = oldRecreateTun
		uiActive.Store(oldUi)
		configuredFindProcessMode.Store(oldConfigured)
		externalControllerListening.Store(oldCtrl)
		tunnel.SetFindProcessMode(oldMode)
	})

	isRunning = true
	uiActive.Store(false)
	tunRecreateCalls := 0
	var findProcessModeDuringTunBringUp P.FindProcessMode
	var selectedProxyDuringTunBringUp string

	var lastAppliedCfg *config.Config
	recreateRuntimeTun = func(LC.Tun, constant.Tunnel) {
		tunRecreateCalls++
		findProcessModeDuringTunBringUp = tunnel.FindProcessMode()
		if lastAppliedCfg != nil {
			if proxy, ok := lastAppliedCfg.Proxies["Proxy"]; ok {
				if unwrapped := proxy.Unwrap(nil, false); unwrapped != nil {
					selectedProxyDuringTunBringUp = unwrapped.Name()
				}
			}
		}
	}
	applyRuntimeConfig = func(cfg *config.Config, _ bool) {
		lastAppliedCfg = cfg
		// Mirror mihomo executor.ApplyConfig -> updateGeneral + updateTun(cfg.General).
		tunnel.SetFindProcessMode(cfg.General.FindProcessMode)
		if runtime.GOOS != "android" {
			recreateRuntimeTun(cfg.General.Tun, tunnel.Tunnel)
		}
	}
	refreshRuntimeListeners = updateListeners

	params := defaultSetupParams()
	params.Config.Tun.Enable = true
	params.Config.Tun.Stack = constant.TunGvisor
	params.Config.FindProcessMode = P.FindProcessAlways
	params.Config.Proxy = []map[string]any{
		{
			"name":   "NodeA",
			"type":   "socks5",
			"server": "127.0.0.1",
			"port":   1080,
		},
		{
			"name":   "NodeB",
			"type":   "socks5",
			"server": "127.0.0.1",
			"port":   1081,
		},
	}
	params.Config.ProxyGroup = []map[string]any{
		{
			"name":    "Proxy",
			"type":    "select",
			"proxies": []string{"NodeA", "NodeB"},
		},
	}
	params.SelectedMap = map[string]string{
		"Proxy": "NodeB",
	}
	if err := setupConfig(params); err != nil {
		t.Fatalf("setupConfig failed: %v", err)
	}
	if tunRecreateCalls != 1 {
		t.Fatalf("expected 1 TUN recreate call during running setupConfig, got %d", tunRecreateCalls)
	}
	if findProcessModeDuringTunBringUp != P.FindProcessStrict {
		t.Fatalf("expected effective FindProcessStrict during ApplyConfig TUN bring-up when UI is hidden, got %v", findProcessModeDuringTunBringUp)
	}
	if selectedProxyDuringTunBringUp != "NodeB" {
		t.Fatalf("expected SelectedMap target NodeB to be applied before ApplyConfig TUN bring-up, got %q", selectedProxyDuringTunBringUp)
	}
}
