//go:build !cgo

package main

import (
	"bytes"
	"encoding/json"
	"testing"

	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
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
