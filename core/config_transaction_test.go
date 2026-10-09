package main

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
)

func isolateConfigRuntime(t *testing.T) *int {
	t.Helper()
	oldApply, oldController, oldListeners := applyRuntimeConfig, recreateRuntimeController, refreshRuntimeListeners
	oldClear, oldRestore, oldSelect, oldHealth := clearRuntimeStrictIngress, restoreRuntimeStrictIngress, selectRuntimeGroups, startRuntimeHealthChecks
	oldConfig, oldRaw, oldPending, oldURL, oldInterval, oldDescriptions := currentConfig, appliedRawConfig, pendingTunEnable, currentTestURL, minHealthCheckInterval, proxyDescriptions
	oldControllerEnabled := runtimeControllerEnabled
	oldStrict, oldMacStrict := activeStrictIngress, macStrictIngressIntent
	activeStrictIngress, macStrictIngressIntent = nil, nil
	calls := new(int)
	applyRuntimeConfig = func(*config.Config, bool) { *calls++ }
	recreateRuntimeController = func(*config.Config) error { *calls++; return nil }
	refreshRuntimeListeners = func() { *calls++ }
	clearRuntimeStrictIngress = func() { *calls++ }
	restoreRuntimeStrictIngress = func() error { *calls++; return nil }
	selectRuntimeGroups = func(map[string]string) { *calls++ }
	startRuntimeHealthChecks = func() { *calls++ }
	t.Cleanup(func() {
		applyRuntimeConfig, recreateRuntimeController, refreshRuntimeListeners = oldApply, oldController, oldListeners
		clearRuntimeStrictIngress, restoreRuntimeStrictIngress, selectRuntimeGroups, startRuntimeHealthChecks = oldClear, oldRestore, oldSelect, oldHealth
		currentConfig, appliedRawConfig, pendingTunEnable, currentTestURL, minHealthCheckInterval, proxyDescriptions = oldConfig, oldRaw, oldPending, oldURL, oldInterval, oldDescriptions
		runtimeControllerEnabled = oldControllerEnabled
		activeStrictIngress, macStrictIngressIntent = oldStrict, oldMacStrict
	})
	return calls
}

func TestConfigInvalidCandidatePreservesLastRuntime(t *testing.T) {
	calls := isolateConfigRuntime(t)
	previous := &config.Config{General: &config.General{}, Controller: &config.Controller{Secret: "last-secret"}}
	currentConfig = previous
	appliedRawConfig = []byte("last-raw")
	pendingTunEnable = true
	currentTestURL = "https://last.test"
	minHealthCheckInterval = time.Minute
	proxyDescriptions = map[string]string{"last": "description"}
	strict := &strictIngressSession{}
	activeStrictIngress = strict
	params := defaultSetupParams()
	params.Config.Rule = []string{"MATCH,__missing_group__"}
	params.TestURL = "https://invalid.test"
	if err := setupConfig(params); err == nil {
		t.Fatal("invalid target accepted")
	}
	if *calls != 0 {
		t.Errorf("invalid candidate touched %d runtime boundaries", *calls)
	}
	if currentConfig != previous || activeStrictIngress != strict || string(appliedRawConfig) != "last-raw" || !pendingTunEnable || currentTestURL != "https://last.test" || minHealthCheckInterval != time.Minute || proxyDescriptions["last"] != "description" {
		t.Error("invalid candidate replaced last runtime or metadata")
	}
}

func TestConfigMalformedEnvelopeDoesNotApplyDefaults(t *testing.T) {
	calls := isolateConfigRuntime(t)
	for _, input := range []string{"", "{", "null", `{}`, `{"config":null}`, `{"config":{}} {}`} {
		if result := handleSetupConfig([]byte(input)); result == "" {
			t.Errorf("invalid envelope accepted: %q", input)
		}
	}
	if *calls != 0 {
		t.Errorf("bad envelopes applied defaults %d times", *calls)
	}
}

func TestConfigSuccessfulApplyFailureRetryAndFirstFailure(t *testing.T) {
	calls := isolateConfigRuntime(t)
	currentConfig = nil
	bad := defaultSetupParams()
	bad.Config.Rule = []string{"MATCH,__missing_group__"}
	if setupConfig(bad) == nil || currentConfig != nil || *calls != 0 {
		t.Fatal("first invalid setup applied a fallback")
	}
	good := defaultSetupParams()
	good.TestURL = "https://first.test"
	good.Config.Secret = "first-secret"
	if err := setupConfig(good); err != nil {
		t.Fatal(err)
	}
	first := currentConfig
	firstRaw := string(appliedRawConfig)
	if first == nil || first.Controller.Secret != "first-secret" || currentTestURL != good.TestURL || firstRaw == "" {
		t.Fatal("valid configuration was not committed")
	}
	*calls = 0
	if setupConfig(bad) == nil || currentConfig != first || string(appliedRawConfig) != firstRaw || *calls != 0 {
		t.Fatal("failed update damaged successful setup")
	}
	good.Config.Secret = "second-secret"
	good.TestURL = "https://second.test"
	if err := setupConfig(good); err != nil {
		t.Fatal(err)
	}
	if currentConfig.Controller.Secret != "second-secret" || currentTestURL != good.TestURL {
		t.Fatal("valid retry was not applied")
	}
}

func TestConfigControllerFailurePrecedesRuntimeMutation(t *testing.T) {
	calls := isolateConfigRuntime(t)
	previous := &config.Config{General: &config.General{}, Controller: &config.Controller{Secret: "last-secret"}}
	currentConfig = previous
	recreateRuntimeController = func(*config.Config) error { return errors.New("synthetic bind failure") }
	if err := setupConfig(defaultSetupParams()); err == nil {
		t.Fatal("controller failure hidden")
	}
	if currentConfig != previous || *calls != 0 {
		t.Fatal("controller failure changed runtime")
	}
	endpoint := "127.0.0.1:9191"
	port := 9123
	if err := updateConfig(&UpdateParams{ExternalController: &endpoint, MixedPort: &port}); err == nil {
		t.Fatal("update bind failure hidden")
	}
	if currentConfig != previous || previous.General.MixedPort != 0 || *calls != 0 {
		t.Fatal("update partially committed before controller failure")
	}
}

func TestConfigConcurrentSetupsSerializeCommit(t *testing.T) {
	isolateConfigRuntime(t)
	entered := make(chan struct{})
	unblock := make(chan struct{})
	var once sync.Once
	applyRuntimeConfig = func(*config.Config, bool) { once.Do(func() { close(entered); <-unblock }) }
	first := defaultSetupParams()
	first.TestURL = "https://first.test"
	second := defaultSetupParams()
	second.TestURL = "https://second.test"
	results := make(chan error, 2)
	go func() { results <- setupConfig(first) }()
	<-entered
	go func() { results <- setupConfig(second) }()
	close(unblock)
	for i := 0; i < 2; i++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	if currentTestURL != second.TestURL {
		t.Fatal("concurrent setup committed out of sequence")
	}
}

func TestConfigFirstPostApplyFailureClosesCandidateRuntime(t *testing.T) {
	isolateConfigRuntime(t)
	currentConfig = nil
	var applied []*config.Config
	var controllers []*config.Config
	applyRuntimeConfig = func(cfg *config.Config, _ bool) { applied = append(applied, cfg) }
	recreateRuntimeController = func(cfg *config.Config) error { controllers = append(controllers, cfg); return nil }
	restoreRuntimeStrictIngress = func() error { return errors.New("synthetic post-apply failure") }
	params := defaultSetupParams()
	params.Config.MixedPort = 9123
	params.Config.ExternalController = "127.0.0.1:9191"
	if err := setupConfig(params); err == nil {
		t.Fatal("post-apply failure hidden")
	}
	if currentConfig != nil || len(applied) != 2 || len(controllers) != 2 {
		t.Fatal("initial failure did not roll back operating-system boundaries")
	}
	dormant := applied[1]
	if dormant.General.MixedPort != 0 || dormant.General.Tun.Enable || dormant.DNS.Enable || dormant.NTP.Enable || len(dormant.Listeners) != 0 || len(dormant.Tunnels) != 0 {
		t.Fatal("rollback retained candidate listeners or scheduled network work")
	}
	if controllers[1].Controller.ExternalController != "" || controllers[1].Controller.ExternalControllerTLS != "" {
		t.Fatal("initial failure left controller listening")
	}
}

func TestConfigOnlySuccessfulCommitCancelsPreviousDelayGeneration(t *testing.T) {
	isolateConfigRuntime(t)
	if err := testDelaySem.Acquire(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	defer testDelaySem.Release(50)
	done := make(chan string, 1)
	handleAsyncTestDelay(`{"request-id":"previous-config","proxy-name":"synthetic","timeout":5000}`, func(value string) { done <- value })
	t.Cleanup(func() { cancelDelayTask("previous-config", "cancelled") })
	bad := defaultSetupParams()
	bad.Config.Rule = []string{"MATCH,__missing_group__"}
	if setupConfig(bad) == nil {
		t.Fatal("invalid configuration accepted")
	}
	delayTasksMu.Lock()
	task := delayTasks["previous-config"]
	cancelled := task == nil || task.reason != ""
	delayTasksMu.Unlock()
	if cancelled {
		t.Fatal("failed candidate cancelled previous generation")
	}
	if err := setupConfig(defaultSetupParams()); err != nil {
		t.Fatal(err)
	}
	select {
	case value := <-done:
		var result Delay
		if err := json.Unmarshal([]byte(value), &result); err != nil || result.Reason != "configChanged" {
			t.Fatalf("%q %v", value, err)
		}
	case <-time.After(time.Second):
		t.Fatal("successful apply retained old tasks")
	}
}
