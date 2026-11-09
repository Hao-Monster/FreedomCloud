package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func TestSetupConfigDoesNotBlockOnRemoteProviders(t *testing.T) {
	homeDir := t.TempDir()
	oldHomeDir := constant.Path.HomeDir()
	constant.SetHomeDir(homeDir)

	oldHealth := startRuntimeHealthChecks
	oldListeners := refreshRuntimeListeners
	oldController := recreateRuntimeController
	oldRestoreStrict := restoreRuntimeStrictIngress
	oldClearStrict := clearRuntimeStrictIngress
	oldEmitLoaded := emitLoadedProviderMessage
	oldIsRunning := isRunning
	oldIsInit := isInit.Load()

	var loadedMu sync.Mutex
	var loadedEvents []string
	startRuntimeHealthChecks = func() {}
	refreshRuntimeListeners = func() {}
	recreateRuntimeController = func(*config.Config) error { return nil }
	restoreRuntimeStrictIngress = func() error { return nil }
	clearRuntimeStrictIngress = func() {}
	emitLoadedProviderMessage = func(name string) {
		loadedMu.Lock()
		loadedEvents = append(loadedEvents, name)
		loadedMu.Unlock()
	}
	isRunning = false
	isInit.Store(true)

	t.Cleanup(func() {
		_ = setupConfig(defaultSetupParams())
		_ = cachefile.Cache().Close()
		startRuntimeHealthChecks = oldHealth
		refreshRuntimeListeners = oldListeners
		recreateRuntimeController = oldController
		restoreRuntimeStrictIngress = oldRestoreStrict
		clearRuntimeStrictIngress = oldClearStrict
		emitLoadedProviderMessage = oldEmitLoaded
		isRunning = oldIsRunning
		isInit.Store(oldIsInit)
		constant.SetHomeDir(oldHomeDir)
	})

	releaseCh := make(chan struct{})
	var proxyHits, ruleHits int
	var hitsMu sync.Mutex

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-releaseCh
		hitsMu.Lock()
		defer hitsMu.Unlock()
		switch r.URL.Path {
		case "/proxies.yaml":
			proxyHits++
			w.Header().Set("subscription-userinfo", fmt.Sprintf("upload=%d; download=200; total=1000; expire=1893456000", 100+proxyHits))
			_, _ = fmt.Fprintf(w, "# rev %d\nproxies:\n  - name: remote-ss-1\n    type: ss\n    server: 127.0.0.1\n    port: 8388\n    cipher: aes-128-gcm\n    password: secret\n", proxyHits)
		case "/rules.yaml":
			ruleHits++
			_, _ = fmt.Fprintf(w, "# rev %d\npayload:\n  - '+.nonblocking-provider.example'\n", ruleHits)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	defer func() {
		select {
		case <-releaseCh:
		default:
			close(releaseCh)
		}
	}()

	params := defaultSetupParams()
	params.Config.ProxyProvider = map[string]map[string]any{
		"remote-proxies": {
			"type":     "http",
			"url":      srv.URL + "/proxies.yaml",
			"path":     filepath.Join(homeDir, "providers", "remote-proxies.yaml"),
			"interval": 3600,
		},
	}
	params.Config.ProxyGroup = []map[string]any{
		{
			"name": "Proxy",
			"type": "select",
			"use":  []string{"remote-proxies"},
		},
	}
	params.Config.RuleProvider = map[string]map[string]any{
		"remote-rules": {
			"type":     "http",
			"behavior": "domain",
			"format":   "yaml",
			"url":      srv.URL + "/rules.yaml",
			"path":     filepath.Join(homeDir, "ruleset", "remote-rules.yaml"),
			"interval": 3600,
		},
	}
	params.Config.Rule = []string{
		"RULE-SET,remote-rules,Proxy",
		"MATCH,DIRECT",
	}
	params.SelectedMap = map[string]string{"Proxy": "remote-ss-1"}

	if err := os.MkdirAll(filepath.Join(homeDir, "providers"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(homeDir, "ruleset"), 0o755); err != nil {
		t.Fatal(err)
	}

	setupDone := make(chan error, 1)
	start := time.Now()
	go func() {
		setupDone <- setupConfig(params)
	}()

	select {
	case err := <-setupDone:
		if err != nil {
			t.Fatalf("setupConfig returned error: %v", err)
		}
		if elapsed := time.Since(start); elapsed > 400*time.Millisecond {
			t.Fatalf("setupConfig took %s (>400ms), should not wait on stalled remote HTTP providers", elapsed)
		}
	case <-time.After(400 * time.Millisecond):
		close(releaseCh)
		<-setupDone
		t.Fatal("setupConfig blocked on stalled remote HTTP providers (>400ms)")
	}

	// Immediately after setupConfig returns, single-provider lookup must already
	// resolve the registered providers (even before remote HTTP finishes).
	if ep := handleGetExternalProviderPayload("remote-proxies"); ep == nil {
		t.Fatal("handleGetExternalProviderPayload(remote-proxies) returned nil before full list query")
	}

	// Now release the stalled HTTP server and verify both providers populate in background.
	close(releaseCh)

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		pp := tunnel.Providers()["remote-proxies"]
		rp := tunnel.RuleProviders()["remote-rules"]
		loadedMu.Lock()
		hasProxyLoaded := slices.Contains(loadedEvents, "remote-proxies")
		hasRuleLoaded := slices.Contains(loadedEvents, "remote-rules")
		loadedMu.Unlock()
		if pp != nil && pp.Count() == 1 && rp != nil && rp.Count() == 1 && hasProxyLoaded && hasRuleLoaded {
			break
		}
		time.Sleep(15 * time.Millisecond)
	}

	pp := tunnel.Providers()["remote-proxies"]
	if pp == nil || pp.Count() != 1 {
		t.Fatalf("expected remote-proxies Count() == 1 after background fetch, got %v", pp)
	}
	rp := tunnel.RuleProviders()["remote-rules"]
	if rp == nil || rp.Count() != 1 {
		t.Fatalf("expected remote-rules Count() == 1 after background fetch, got %v", rp)
	}

	loadedMu.Lock()
	gotEvents := append([]string(nil), loadedEvents...)
	loadedMu.Unlock()
	for _, want := range []string{"all", "remote-proxies", "remote-rules"} {
		if !slices.Contains(gotEvents, want) {
			t.Fatalf("expected LoadedMessage %q in %v", want, gotEvents)
		}
	}

	ep := handleGetExternalProviderPayload("remote-proxies")
	if ep == nil || ep.SubscriptionInfo == nil || ep.SubscriptionInfo.Total != 1000 {
		t.Fatalf("expected SubscriptionInfo Total=1000 on remote-proxies, got %+v", ep)
	}

	// Verify concurrent Match/Count/MarshalJSON/SubscriptionInfoFCX reads while
	// Update() refreshes both providers are race-free.
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(2)
		go func() {
			defer wg.Done()
			for j := 0; j < 10; j++ {
				_ = pp.Update()
				_ = rp.Update()
			}
		}()
		go func() {
			defer wg.Done()
			for j := 0; j < 25; j++ {
				_ = rp.Match(&constant.Metadata{Host: "a.nonblocking-provider.example"}, constant.RuleMatchHelper{})
				_ = rp.Count()
				_ = pp.Count()
				_ = handleGetExternalProviderPayload("remote-proxies")
				_ = handleGetExternalProviderPayload("remote-rules")
			}
		}()
	}
	wg.Wait()
}
