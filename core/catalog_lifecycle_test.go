package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
)

type catalogTestProxy struct {
	constant.Proxy
	closed   atomic.Int32
	started  chan struct{}
	finish   chan struct{}
	blocking bool
}

type closingCatalogTestProxy struct {
	catalogTestProxy
	entered, finish chan struct{}
}

func (proxy *closingCatalogTestProxy) Adapter() constant.ProxyAdapter { return proxy }
func (proxy *closingCatalogTestProxy) Close() error {
	close(proxy.entered)
	<-proxy.finish
	return proxy.catalogTestProxy.Close()
}

func TestCatalogClosingAdapterStillConsumesResourceBudget(t *testing.T) {
	catalogFixture(t)
	closing := &closingCatalogTestProxy{entered: make(chan struct{}), finish: make(chan struct{})}
	first := true
	parseCatalogProxy = func(map[string]any) (constant.Proxy, error) {
		if first {
			first = false
			return closing, nil
		}
		return &catalogTestProxy{}, nil
	}
	catalogPrepareOK(t, "c-closing-0001", nil)
	b := catalogPrepareOK(t, "c-closing-0002", nil)
	c := catalogPrepareOK(t, "c-closing-0003", nil)
	catalogMu.Lock()
	b.refs = 1
	c.refs = 1
	catalogMu.Unlock()
	done := make(chan struct{})
	go func() { releaseCatalog("c-closing-0001", nil); close(done) }()
	<-closing.entered
	_, reason := prepareCatalog(catalogInput("c-closing-0004"), nil)
	close(closing.finish)
	<-done
	catalogMu.Lock()
	b.refs = 0
	c.refs = 0
	catalogMu.Unlock()
	if reason != "overloaded" {
		t.Fatalf("admitted fourth adapter before Close completed: %s", reason)
	}
}

func (proxy *catalogTestProxy) Adapter() constant.ProxyAdapter { return proxy }
func (proxy *catalogTestProxy) Close() error                   { proxy.closed.Add(1); return nil }
func (proxy *catalogTestProxy) URLTest(ctx context.Context, _ string, _ utils.IntRanges[uint16]) (uint16, error) {
	if proxy.started != nil {
		proxy.started <- struct{}{}
	}
	if proxy.blocking {
		<-ctx.Done()
		if proxy.finish != nil {
			<-proxy.finish
		}
		return 0, ctx.Err()
	}
	return 17, nil
}

func catalogFixture(t *testing.T) *[]*catalogTestProxy {
	t.Helper()
	clearCatalogs()
	resumeCatalogs()
	setCatalogStrictBlocked(false)
	original := parseCatalogProxy
	proxies := []*catalogTestProxy{}
	parseCatalogProxy = func(map[string]any) (constant.Proxy, error) {
		proxy := &catalogTestProxy{}
		proxies = append(proxies, proxy)
		return proxy, nil
	}
	t.Cleanup(func() {
		clearCatalogs()
		resumeCatalogs()
		setCatalogStrictBlocked(false)
		parseCatalogProxy = original
	})
	return &proxies
}

func catalogInput(id string) string {
	return fmt.Sprintf(`{"catalog-id":%q,"proxies":[{"name":"fixture","type":"ss","server":"192.0.2.1","port":443}]}`, id)
}
func catalogPrepareOK(t *testing.T, id string, owner *catalogOwner) *catalogEntry {
	t.Helper()
	if _, reason := prepareCatalog(catalogInput(id), owner); reason != "" {
		t.Fatalf("prepare: %s", reason)
	}
	catalogMu.RLock()
	entry := catalogs[catalogKey{owner: owner, id: id}]
	catalogMu.RUnlock()
	return entry
}
func catalogRequest(id, request string, timeout int) string {
	return fmt.Sprintf(`{"catalog-id":%q,"index":0,"request-id":%q,"test-url":"https://example.invalid/check","timeout":%d}`, id, request, timeout)
}
func catalogResult(t *testing.T, done <-chan string) Delay {
	t.Helper()
	select {
	case data := <-done:
		var result Delay
		if err := json.Unmarshal([]byte(data), &result); err != nil {
			t.Fatal(err)
		}
		return result
	case <-time.After(3 * time.Second):
		t.Fatal("delay did not finish")
		return Delay{}
	}
}

func TestCatalogPreparationDoesNotTakeConfigurationLock(t *testing.T) {
	catalogFixture(t)
	beforeConfig, beforeRunning := currentConfig, isRunning
	runLock.Lock()
	defer runLock.Unlock()
	done := make(chan string, 1)
	go func() { _, reason := prepareCatalog(catalogInput("c-isolated-0001"), nil); done <- reason }()
	select {
	case reason := <-done:
		if reason != "" {
			t.Fatal(reason)
		}
	case <-time.After(time.Second):
		t.Fatal("prepare waited for active configuration lock")
	}
	if currentConfig != beforeConfig || isRunning != beforeRunning {
		t.Fatal("catalog preparation changed active runtime")
	}
}

func TestCatalogMalformedNodesAndUnsupportedTransportsAreExplicit(t *testing.T) {
	catalogFixture(t)
	for _, tc := range []struct{ raw, reason string }{
		{`null`, "parseFailed"}, {`"PRIVATE-RAW"`, "parseFailed"}, {`{"password":"PRIVATE-RAW"}`, "parseFailed"},
		{`{"type":"wireguard","name":"wg"}`, "typeUnsupported"}, {`{"type":"amneziawg"}`, "typeUnsupported"}, {`{"type":"tailscale"}`, "typeUnsupported"},
		{`{"type":"ss","smux":{"enabled":true}}`, "typeUnsupported"}, {`{"type":"ss","dialer-proxy":null}`, "chainUnsupported"},
		{`{"type":"ss","SMUX":{"enabled":true}}`, "typeUnsupported"}, {`{"type":"ss","Smux":{"enabled":true}}`, "typeUnsupported"},
		{`{"type":"ss","name":"bad","port":0}`, "parseFailed"}, {`{"type":"ss","name":"bad","server":"192.0.2.1","port":65536}`, "parseFailed"},
	} {
		node, proxy := parseCatalogNode(4, json.RawMessage(tc.raw))
		if node.Supported || proxy != nil || node.Reason != tc.reason || node.Index != 4 {
			t.Fatalf("unexpected node %#v", node)
		}
		data, _ := json.Marshal(node)
		if strings.Contains(string(data), "PRIVATE-RAW") {
			t.Fatal("raw input leaked")
		}
	}
	parseCatalogProxy = func(map[string]any) (constant.Proxy, error) { return nil, errors.New("PRIVATE-RAW parser failure") }
	node, _ := parseCatalogNode(0, json.RawMessage(`{"type":"ss","name":"bad","server":"192.0.2.1","port":443}`))
	if node.Reason != "parseFailed" {
		t.Fatalf("parser error was not redacted: %#v", node)
	}
}

func TestCatalogRejectsAdaptersWithoutDeterministicCloseBeforeConstruction(t *testing.T) {
	for _, protocol := range []string{"tuic", "snell", "anytls", "hysteria"} {
		t.Run(protocol, func(t *testing.T) {
			catalogFixture(t)
			constructed := []string{}
			parseCatalogProxy = func(mapping map[string]any) (constant.Proxy, error) {
				constructed = append(constructed, mapping["type"].(string))
				return &catalogTestProxy{}, nil
			}
			data := fmt.Sprintf(`{"catalog-id":"c-close-contract-%s","proxies":[{"name":"blocked","type":%q,"server":"192.0.2.1","port":443},{"name":"normal","type":"ss","server":"192.0.2.2","port":8388}]}`, protocol, protocol)
			result, reason := prepareCatalog(data, nil)
			if reason != "" || len(result.Nodes) != 2 {
				t.Fatalf("prepare failed: %s", reason)
			}
			if len(constructed) != 1 || constructed[0] != "ss" {
				t.Fatalf("constructed resource-unsafe adapter: %v", constructed)
			}
			if result.Nodes[0].Index != 0 || result.Nodes[0].Supported || result.Nodes[0].Reason != "typeUnsupported" {
				t.Fatalf("blocked node metadata: %#v", result.Nodes[0])
			}
			if result.Nodes[1].Index != 1 || !result.Nodes[1].Supported || result.Nodes[1].Reason != "" {
				t.Fatalf("normal node lost: %#v", result.Nodes[1])
			}
		})
	}
}

func TestCatalogRejectsRetainedTransportResourcesBeforeConstruction(t *testing.T) {
	for _, tc := range []struct{ name, protocol, key, value string }{
		{"kcptun", "ss", "plugin", `"kcptun"`},
		{"kcptun-upper-key", "ss", "PLUGIN", `"kcptun"`},
		{"kcptun-mixed", "ss", "Plugin", `"KCPTUN"`},
		{"realm", "hysteria2", "realm-opts", `{"enable":true}`},
		{"realm-upper", "hysteria2", "REALM-OPTS", `{"enable":true}`},
		{"realm-underscore", "hysteria2", "Realm_Opts", `{"enable":true}`},
		{"realm-disabled", "hysteria2", "realm-opts", `{"enable":false}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			catalogFixture(t)
			constructed := 0
			parseCatalogProxy = func(map[string]any) (constant.Proxy, error) {
				constructed++
				return &catalogTestProxy{}, nil
			}
			raw := fmt.Sprintf(`{"name":"blocked","type":%q,"server":"192.0.2.1","port":443,%q:%s}`, tc.protocol, tc.key, tc.value)
			node, proxy := parseCatalogNode(7, json.RawMessage(raw))
			if constructed != 0 {
				t.Fatal("constructed transport with unbounded retained resources")
			}
			if node.Supported || proxy != nil || node.Reason != "typeUnsupported" || node.Index != 7 {
				t.Fatalf("blocked transport metadata: %#v", node)
			}
		})
	}
	for _, raw := range []string{
		`{"name":"plain","type":"ss","server":"192.0.2.1","port":443}`,
		`{"name":"obfs","type":"ss","server":"192.0.2.1","port":443,"plugin":"obfs"}`,
		`{"name":"plain","type":"hysteria2","server":"192.0.2.1","port":443}`,
	} {
		catalogFixture(t)
		node, proxy := parseCatalogNode(0, json.RawMessage(raw))
		if !node.Supported || proxy == nil || node.Reason != "" {
			t.Fatalf("standalone transport rejected: %#v", node)
		}
		_ = proxy.Adapter().Close()
	}
}

func TestCatalogShutdownRejectsInflightAndLatePreparation(t *testing.T) {
	catalogFixture(t)
	entered, finish := make(chan struct{}), make(chan struct{})
	proxy := &catalogTestProxy{}
	parseCatalogProxy = func(map[string]any) (constant.Proxy, error) { close(entered); <-finish; return proxy, nil }
	done := make(chan string, 1)
	go func() { _, reason := prepareCatalog(catalogInput("c-shutdown-0001"), nil); done <- reason }()
	<-entered
	clearCatalogsForShutdown(true)
	close(finish)
	if reason := <-done; reason != "sessionClosed" {
		t.Fatalf("shutdown prepare: %s", reason)
	}
	if proxy.closed.Load() != 1 {
		t.Fatal("shutdown leaked in-flight construction")
	}
	if _, reason := prepareCatalog(catalogInput("c-shutdown-0002"), nil); reason != "sessionClosed" {
		t.Fatalf("late shutdown prepare: %s", reason)
	}
}

func TestCatalogNodeLimitIncludesExactlyTwoThousand(t *testing.T) {
	catalogFixture(t)
	proxies := make([]any, maxCatalogNodes)
	for i := range proxies {
		proxies[i] = map[string]any{"name": fmt.Sprintf("n-%d", i), "type": "ss", "server": "192.0.2.1", "port": 443}
	}
	data, _ := json.Marshal(map[string]any{"catalog-id": "c-max-nodes-0001", "proxies": proxies})
	result, reason := prepareCatalog(string(data), nil)
	if reason != "" || len(result.Nodes) != 2000 || result.Nodes[1999].Index != 1999 || !result.Nodes[1999].Supported {
		t.Fatalf("maximum boundary: %d nodes %s", len(result.Nodes), reason)
	}
}

func TestCatalogRejectsMihomoChainKeyAliases(t *testing.T) {
	catalogFixture(t)
	for _, key := range []string{"dialer-proxy", "dialer_proxy", "DIALER_PROXY", "Dialer-Proxy"} {
		raw := fmt.Sprintf(`{"name":"alias","type":"ss","server":"192.0.2.1","port":443,%q:"active-group"}`, key)
		node, proxy := parseCatalogNode(0, json.RawMessage(raw))
		if proxy != nil || node.Supported || node.Reason != "chainUnsupported" {
			t.Fatalf("accepted chain alias %s", key)
		}
	}
}

func TestCatalogLRUEvictsOnlyIdleAndTTLClosesAdapters(t *testing.T) {
	proxies := catalogFixture(t)
	a := catalogPrepareOK(t, "c-cache-0001", nil)
	b := catalogPrepareOK(t, "c-cache-0002", nil)
	catalogPrepareOK(t, "c-cache-0003", nil)
	catalogMu.Lock()
	a.lastUsed = time.Now()
	b.lastUsed = time.Now().Add(-time.Minute)
	catalogMu.Unlock()
	d := catalogPrepareOK(t, "c-cache-0004", nil)
	if (*proxies)[1].closed.Load() != 1 || (*proxies)[0].closed.Load() != 0 {
		t.Fatal("LRU evicted wrong adapter")
	}
	expireCatalog(d, time.Now().Add(catalogIdleTTL-time.Second))
	if (*proxies)[3].closed.Load() != 0 {
		t.Fatal("catalog expired before TTL")
	}
	expireCatalog(d, time.Now().Add(catalogIdleTTL+time.Second))
	if (*proxies)[3].closed.Load() != 1 {
		t.Fatal("idle TTL retained adapter")
	}
	releaseCatalog(d.key.id, nil)
	if (*proxies)[3].closed.Load() != 1 {
		t.Fatal("release double closed adapter")
	}
}

func TestCatalogReleaseDefersCloseAndRetainsResourceBudget(t *testing.T) {
	proxies := catalogFixture(t)
	done := make(chan string, 3)
	for i := 0; i < 3; i++ {
		id := fmt.Sprintf("c-held-%04d", i)
		entry := catalogPrepareOK(t, id, nil)
		proxy := (*proxies)[i]
		proxy.blocking = true
		proxy.started = make(chan struct{}, 1)
		proxy.finish = make(chan struct{})
		handleCatalogTestDelay(catalogRequest(id, fmt.Sprintf("held-%d", i), 2000), nil, func(data string) { done <- data })
		<-proxy.started
		expireCatalog(entry, time.Now().Add(2*catalogIdleTTL))
		if proxy.closed.Load() != 0 {
			t.Fatal("TTL closed a referenced adapter")
		}
	}
	if _, reason := prepareCatalog(catalogInput("c-fourth-0001"), nil); reason != "overloaded" {
		t.Fatalf("active cache admission: %s", reason)
	}
	for i := 0; i < 3; i++ {
		releaseCatalog(fmt.Sprintf("c-held-%04d", i), nil)
		if (*proxies)[i].closed.Load() != 0 {
			t.Fatal("release closed adapter during URLTest")
		}
	}
	if _, reason := prepareCatalog(catalogInput("c-fourth-0001"), nil); reason != "overloaded" {
		t.Fatalf("retired refs escaped resource cap: %s", reason)
	}
	for i := 0; i < 3; i++ {
		close((*proxies)[i].finish)
	}
	for i := 0; i < 3; i++ {
		if result := catalogResult(t, done); result.Reason != "cancelled" {
			t.Fatalf("release completion: %#v", result)
		}
	}
	for i := 0; i < 3; i++ {
		if (*proxies)[i].closed.Load() != 1 {
			t.Fatal("last reference did not close adapter")
		}
	}
	catalogPrepareOK(t, "c-fourth-0001", nil)
}

func TestCatalogStrictTransitionRetiresConstruction(t *testing.T) {
	catalogFixture(t)
	entered, finish := make(chan struct{}), make(chan struct{})
	proxy := &catalogTestProxy{}
	parseCatalogProxy = func(map[string]any) (constant.Proxy, error) { close(entered); <-finish; return proxy, nil }
	done := make(chan string, 1)
	go func() { _, reason := prepareCatalog(catalogInput("c-building-0001"), nil); done <- reason }()
	<-entered
	setCatalogStrictBlocked(true)
	close(finish)
	if reason := <-done; reason != "strictModeUnsupported" {
		t.Fatalf("construction survived strict: %s", reason)
	}
	if proxy.closed.Load() != 1 {
		t.Fatal("rejected construction leaked adapter")
	}
	if _, reason := prepareCatalog(catalogInput("c-blocked-0001"), nil); reason != "strictModeUnsupported" {
		t.Fatalf("strict admission: %s", reason)
	}
}

func TestCatalogStrictTransitionCancelsRunningAndQueuedTests(t *testing.T) {
	proxies := catalogFixture(t)
	id := "c-strict-0001"
	catalogPrepareOK(t, id, nil)
	proxy := (*proxies)[0]
	proxy.blocking = true
	proxy.started = make(chan struct{}, 1)
	done := make(chan string, 1)
	handleCatalogTestDelay(catalogRequest(id, "strict-running", 2000), nil, func(data string) { done <- data })
	<-proxy.started
	setCatalogStrictBlocked(true)
	if result := catalogResult(t, done); result.Value != -1 || result.Reason != "strictModeUnsupported" {
		t.Fatalf("strict result: %#v", result)
	}
	if proxy.closed.Load() != 1 {
		t.Fatal("strict transition retained adapter")
	}
	handleCatalogTestDelay(catalogRequest(id, "strict-new", 2000), nil, func(data string) { done <- data })
	if result := catalogResult(t, done); result.Reason != "strictModeUnsupported" {
		t.Fatalf("new strict request: %#v", result)
	}
}

func TestCatalogOwnerIsolationAndLateActions(t *testing.T) {
	proxies := catalogFixture(t)
	oldOwner, newOwner := newCatalogOwner(), newCatalogOwner()
	id := "c-sessions-0001"
	catalogPrepareOK(t, id, oldOwner)
	catalogPrepareOK(t, id, newOwner)
	closeCatalogOwner(oldOwner)
	if (*proxies)[0].closed.Load() != 1 || (*proxies)[1].closed.Load() != 0 {
		t.Fatal("old session cleanup crossed ownership")
	}
	if _, reason := prepareCatalog(catalogInput(id), oldOwner); reason != "sessionClosed" {
		t.Fatalf("late action: %s", reason)
	}
	done := make(chan string, 2)
	handleCatalogTestDelay(catalogRequest(id, "same-request", 2000), oldOwner, func(data string) { done <- data })
	if result := catalogResult(t, done); result.Reason != "sessionClosed" {
		t.Fatalf("old session test: %#v", result)
	}
	handleCatalogTestDelay(catalogRequest(id, "same-request", 2000), newOwner, func(data string) { done <- data })
	if result := catalogResult(t, done); result.Value != 17 || result.Reason != "" {
		t.Fatalf("new session test: %#v", result)
	}
	releaseCatalog(id, oldOwner)
	if (*proxies)[1].closed.Load() != 0 {
		t.Fatal("old release affected new owner")
	}
}

func TestCatalogProviderCacheIsSafeLocalAndExplicitlyPending(t *testing.T) {
	catalogFixture(t)
	home := t.TempDir()
	catalogPathMu.Lock()
	oldHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	catalogPathMu.Unlock()
	t.Cleanup(func() { catalogPathMu.Lock(); constant.SetHomeDir(oldHome); catalogPathMu.Unlock() })
	cache := filepath.Join(home, "profiles", "providers", "fixture", "proxies", "cache.yaml")
	if err := os.MkdirAll(filepath.Dir(cache), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cache, []byte("PRIVATE-CACHE-NEVER-PARSED"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		path, status string
		valid        bool
	}{
		{cache, "providerPending", true}, {cache + "-missing", "notCached", true},
		{filepath.Join(home, "outside.yaml"), "", false}, {filepath.Join(home, "profiles", "providers", "fixture", "rules", "x"), "", false},
		{filepath.Join(home, "profiles", "providers", "fixture", "proxies", "..", "..", "..", "..", "outside"), "", false},
		{cache + ":stream", "", false}, {"https://example.invalid/cache", "", false},
	} {
		status, valid := catalogProviderStatus(tc.path)
		if valid != tc.valid || status != tc.status {
			t.Fatalf("provider status %q %v, want %q %v", status, valid, tc.status, tc.valid)
		}
	}
	encoded, _ := json.Marshal(map[string]any{"catalog-id": "c-provider-0001", "providers": []any{map[string]any{"name": "fixture", "path": cache}}})
	result, reason := prepareCatalog(string(encoded), nil)
	if reason != "" || len(result.Providers) != 1 || result.Providers[0].Status != "providerPending" || len(result.Nodes) != 0 {
		t.Fatalf("provider result %#v %s", result, reason)
	}
	metadata, _ := json.Marshal(result)
	if strings.Contains(string(metadata), "PRIVATE-CACHE") || strings.Contains(string(metadata), "path") {
		t.Fatal("provider content or path leaked")
	}
}

func TestCatalogAndLiveTestsShareAdmissionAndQueueDeadline(t *testing.T) {
	catalogFixture(t)
	id := "c-budget-0001"
	catalogPrepareOK(t, id, nil)
	if err := testDelaySem.Acquire(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	defer testDelaySem.Release(50)
	done := make(chan string, 151)
	for i := 0; i < 100; i++ {
		handleAsyncTestDelay(fmt.Sprintf(`{"proxy-name":"fixture","request-id":"live-%d","timeout":2000}`, i), func(data string) { done <- data })
	}
	for i := 0; i < 50; i++ {
		handleCatalogTestDelay(catalogRequest(id, fmt.Sprintf("catalog-%d", i), 2000), nil, func(data string) { done <- data })
	}
	handleCatalogTestDelay(catalogRequest(id, "overflow", 2000), nil, func(data string) { done <- data })
	if result := catalogResult(t, done); result.Reason != "overloaded" {
		t.Fatalf("shared admission: %#v", result)
	}
	if len(delayTaskSlots) != 150 {
		t.Fatalf("admitted %d tasks", len(delayTaskSlots))
	}
	cancelAllDelayTasks("uiInactive")
	for i := 0; i < 150; i++ {
		if result := catalogResult(t, done); result.Reason != "uiInactive" {
			t.Fatalf("cancelled task: %#v", result)
		}
	}
	if len(delayTaskSlots) != 0 {
		t.Fatal("cancelled tasks retained admission slots")
	}
	handleCatalogTestDelay(catalogRequest(id, "queue-deadline", 10), nil, func(data string) { done <- data })
	if result := catalogResult(t, done); result.Reason != "deadlineExceeded" {
		t.Fatalf("queue deadline: %#v", result)
	}
}

func TestCatalogQueuedRequestCannotUseReplacementWithSameID(t *testing.T) {
	proxies := catalogFixture(t)
	id := "c-replaced-0001"
	catalogPrepareOK(t, id, nil)
	if err := testDelaySem.Acquire(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	done := make(chan string, 1)
	handleCatalogTestDelay(catalogRequest(id, "old-generation", 2000), nil, func(data string) { done <- data })
	releaseCatalog(id, nil)
	catalogPrepareOK(t, id, nil)
	testDelaySem.Release(50)
	if result := catalogResult(t, done); result.Value != -1 || result.Reason != "cancelled" {
		t.Fatalf("old request crossed generation: %#v", result)
	}
	if (*proxies)[0].closed.Load() != 1 || (*proxies)[1].closed.Load() != 0 {
		t.Fatal("replacement lifecycle incorrect")
	}
}

func TestCatalogTestValidationDoesNotRunUnsupportedNodes(t *testing.T) {
	catalogFixture(t)
	id := "c-validation-0001"
	if _, reason := prepareCatalog(`{"catalog-id":"c-validation-0001","proxies":[{"name":"wg","type":"wireguard"}]}`, nil); reason != "" {
		t.Fatal(reason)
	}
	for _, tc := range []struct{ data, reason string }{
		{catalogRequest(id, "unsupported", 100), "typeUnsupported"},
		{`{"catalog-id":"c-validation-0001","request-id":"missing-index"}`, "invalidParameters"},
		{`{"catalog-id":"c-validation-0001","index":-1,"request-id":"negative"}`, "invalidParameters"},
		{`{"catalog-id":"c-validation-0001","index":1,"request-id":"overflow"}`, "invalidParameters"},
		{catalogRequest("c-missing-0001", "missing", 100), "catalogNotFound"},
	} {
		done := make(chan string, 1)
		handleCatalogTestDelay(tc.data, nil, func(data string) { done <- data })
		if result := catalogResult(t, done); result.Reason != tc.reason || result.Value != -1 {
			t.Fatalf("validation: %#v", result)
		}
	}
	if len(delayTaskSlots) != 0 {
		t.Fatal("unsupported requests consumed task slots")
	}
}

func TestCatalogConcurrentStrictTransitionsAndPreparation(t *testing.T) {
	catalogFixture(t)
	parseCatalogProxy = func(map[string]any) (constant.Proxy, error) { return &catalogTestProxy{}, nil }
	var workers sync.WaitGroup
	failures := make(chan string, 200)
	for worker := 0; worker < 4; worker++ {
		workers.Add(1)
		go func(worker int) {
			defer workers.Done()
			owner := newCatalogOwner()
			defer closeCatalogOwner(owner)
			for i := 0; i < 30; i++ {
				id := fmt.Sprintf("c-concurrent-%d-%04d", worker, i)
				_, reason := prepareCatalog(catalogInput(id), owner)
				switch reason {
				case "", "strictModeUnsupported", "catalogNotFound", "overloaded":
				default:
					failures <- reason
				}
				releaseCatalog(id, owner)
				catalogMu.RLock()
				count := catalogResourceCount
				catalogMu.RUnlock()
				if count < 0 || count > maxCatalogs {
					failures <- fmt.Sprintf("resource count %d", count)
				}
			}
		}(worker)
	}
	workers.Add(1)
	go func() {
		defer workers.Done()
		for i := 0; i < 50; i++ {
			setCatalogStrictBlocked(true)
			setCatalogStrictBlocked(false)
		}
	}()
	workers.Wait()
	close(failures)
	for failure := range failures {
		t.Error(failure)
	}
	catalogMu.RLock()
	defer catalogMu.RUnlock()
	if catalogResourceCount != 0 || len(catalogs) != 0 {
		t.Fatalf("concurrent cleanup retained %d resources", catalogResourceCount)
	}
}

func TestCatalogProviderRejectsSymlinkEscape(t *testing.T) {
	catalogFixture(t)
	home, outside := t.TempDir(), t.TempDir()
	catalogPathMu.Lock()
	oldHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	catalogPathMu.Unlock()
	t.Cleanup(func() { catalogPathMu.Lock(); constant.SetHomeDir(oldHome); catalogPathMu.Unlock() })
	root := filepath.Join(home, "profiles", "providers")
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(outside, "proxies"), 0700); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "linked")
	if err := os.Symlink(outside, link); err != nil {
		t.Skip("NOT RUN: local filesystem does not permit isolated symlink fixture")
	}
	if _, valid := catalogProviderStatus(filepath.Join(link, "proxies", "missing.yaml")); valid {
		t.Fatal("provider symlink escaped private cache root")
	}
}

func catalogAliasedHome(t *testing.T) (string, string) {
	t.Helper()
	parent := t.TempDir()
	physical := filepath.Join(parent, "physical")
	home := filepath.Join(physical, "home")
	if err := os.MkdirAll(home, 0700); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(parent, "alias")
	if err := os.Symlink(physical, alias); err != nil {
		t.Skip("NOT RUN: local filesystem does not permit isolated symlink fixture")
	}
	return home, filepath.Join(alias, "home")
}

func catalogUseTestHome(t *testing.T, home string) {
	t.Helper()
	catalogPathMu.Lock()
	oldHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	catalogPathMu.Unlock()
	t.Cleanup(func() { catalogPathMu.Lock(); constant.SetHomeDir(oldHome); catalogPathMu.Unlock() })
}

func TestCatalogProviderAcceptsTrustedHomeAlias(t *testing.T) {
	catalogFixture(t)
	physical, home := catalogAliasedHome(t)
	catalogUseTestHome(t, home)
	rel := filepath.Join("profiles", "providers", "fixture", "proxies", "cache.yaml")
	cache := filepath.Join(physical, rel)
	if err := os.MkdirAll(filepath.Dir(cache), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cache, []byte("PRIVATE-CACHE-NEVER-PARSED"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, path, status string }{
		{"cached", filepath.Join(home, rel), "providerPending"},
		{"missing", filepath.Join(home, rel+"-missing"), "notCached"},
		{"relative", rel, "providerPending"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			status, valid := catalogProviderStatus(tc.path)
			if !valid || status != tc.status {
				t.Fatalf("trusted home alias rejected: status=%q valid=%v", status, valid)
			}
		})
	}
}

func TestCatalogProviderMissingDirectoriesBelowTrustedAlias(t *testing.T) {
	for _, missingHome := range []bool{false, true} {
		t.Run(fmt.Sprintf("missing-home-%v", missingHome), func(t *testing.T) {
			catalogFixture(t)
			_, home := catalogAliasedHome(t)
			if missingHome {
				home = filepath.Join(home, "not-created", "nested")
			}
			catalogUseTestHome(t, home)
			path := filepath.Join(home, "profiles", "providers", "fixture", "proxies", "cache.yaml")
			if status, valid := catalogProviderStatus(path); !valid || status != "notCached" {
				t.Fatalf("missing cache below trusted alias: status=%q valid=%v", status, valid)
			}
		})
	}
}

func TestCatalogProviderHomeAliasDoesNotPermitManagedSymlinks(t *testing.T) {
	for _, linkParts := range [][]string{
		{"profiles"},
		{"profiles", "providers"},
		{"profiles", "providers", "fixture"},
		{"profiles", "providers", "fixture", "proxies"},
	} {
		t.Run(strings.Join(linkParts, "-"), func(t *testing.T) {
			catalogFixture(t)
			physical, home := catalogAliasedHome(t)
			catalogUseTestHome(t, home)
			link := filepath.Join(append([]string{physical}, linkParts...)...)
			if err := os.MkdirAll(filepath.Dir(link), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(t.TempDir(), link); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(home, "profiles", "providers", "fixture", "proxies", "missing.yaml")
			if status, valid := catalogProviderStatus(path); valid || status != "" {
				t.Fatalf("managed symlink accepted below home alias: status=%q valid=%v", status, valid)
			}
		})
	}
}
