package main

import (
	"fmt"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

// These test doubles expose only the history/provider reads used by the real
// forwarder. Any accidental network-test call fails instead of opening sockets.
type healthCheckTestProxy struct {
	C.Proxy
	name    string
	history []C.DelayHistory
	extra   map[string]C.ProxyState
	entered chan struct{}
	release <-chan struct{}
	once    sync.Once
}

func (p *healthCheckTestProxy) Name() string { return p.name }
func (p *healthCheckTestProxy) DelayHistory() []C.DelayHistory {
	if p.entered != nil {
		p.once.Do(func() { close(p.entered) })
		<-p.release
	}
	return p.history
}
func (p *healthCheckTestProxy) ExtraDelayHistories() map[string]C.ProxyState { return p.extra }

type healthCheckTestProvider struct {
	P.ProxyProvider
	mu      sync.Mutex
	proxies []C.Proxy
	touches atomic.Int64
}

func (p *healthCheckTestProvider) Proxies() []C.Proxy {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]C.Proxy(nil), p.proxies...)
}
func (p *healthCheckTestProvider) Touch() { p.touches.Add(1) }
func (p *healthCheckTestProvider) replace(proxies []C.Proxy) {
	p.mu.Lock()
	p.proxies = proxies
	p.mu.Unlock()
}

func healthCheckHistory(delay uint16) []C.DelayHistory {
	return []C.DelayHistory{{Time: time.Unix(1700000000, 123), Delay: delay}}
}

func healthCheckProxy(name string) *healthCheckTestProxy {
	return &healthCheckTestProxy{name: name, history: healthCheckHistory(31)}
}

func isolateHealthCheckForwarder(t *testing.T) {
	t.Helper()
	healthCheckChMu.Lock()
	running := healthCheckStopCh != nil
	healthCheckChMu.Unlock()
	if running {
		t.Fatal("test requires no existing background health-check forwarder")
	}
	runLock.Lock()
	oldConfig := currentConfig
	oldProxies, oldProviders := tunnel.Proxies(), tunnel.Providers()
	oldTouch := lastProviderTouchNs.Load()
	currentConfig = &config.Config{}
	tunnel.UpdateProxies(map[string]C.Proxy{}, map[string]P.ProxyProvider{})
	healthCheckMu.Lock()
	oldSeen := healthCheckSeen
	healthCheckMu.Unlock()
	resetHealthCheckForwarderState()
	runLock.Unlock()
	t.Cleanup(func() {
		runLock.Lock()
		currentConfig = oldConfig
		tunnel.UpdateProxies(oldProxies, oldProviders)
		resetHealthCheckForwarderState()
		healthCheckMu.Lock()
		healthCheckSeen = oldSeen
		healthCheckMu.Unlock()
		lastProviderTouchNs.Store(oldTouch)
		runLock.Unlock()
	})
}

func setHealthCheckProxies(proxies ...C.Proxy) {
	runLock.Lock()
	defer runLock.Unlock()
	current := make(map[string]C.Proxy, len(proxies))
	for _, proxy := range proxies {
		current[proxy.Name()] = proxy
	}
	tunnel.UpdateProxies(current, map[string]P.ProxyProvider{})
}

func healthCheckCacheSize() int {
	healthCheckMu.Lock()
	defer healthCheckMu.Unlock()
	return len(healthCheckSeen)
}

func copyHealthCheckCache[K comparable, V any](source map[K]V) map[K]V {
	copy := make(map[K]V, len(source))
	for key, value := range source {
		copy[key] = value
	}
	return copy
}

func awaitHealthCheck(t *testing.T, signal <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(5 * time.Second):
		t.Fatalf("timed out waiting for %s", what)
	}
}

func TestHealthCheckCacheTracksLiveHistories(t *testing.T) {
	isolateHealthCheckForwarder(t)
	for _, step := range []struct {
		name    string
		proxies []C.Proxy
		want    int
	}{
		{"initial", []C.Proxy{healthCheckProxy("a"), healthCheckProxy("b")}, 2},
		{"node replacement", []C.Proxy{healthCheckProxy("b"), healthCheckProxy("c")}, 2},
		{"extra history", []C.Proxy{&healthCheckTestProxy{name: "b", history: healthCheckHistory(31), extra: map[string]C.ProxyState{"https://a.test": {History: healthCheckHistory(41)}, "https://b.test": {History: healthCheckHistory(42)}}}}, 3},
		{"removed URL", []C.Proxy{&healthCheckTestProxy{name: "b", history: healthCheckHistory(31), extra: map[string]C.ProxyState{"https://b.test": {History: healthCheckHistory(42)}}}}, 2},
		{"empty histories", []C.Proxy{&healthCheckTestProxy{name: "b", extra: map[string]C.ProxyState{"https://b.test": {}}}}, 0},
		{"returning node", []C.Proxy{healthCheckProxy("a")}, 1},
		{"empty directory", nil, 0},
	} {
		setHealthCheckProxies(step.proxies...)
		forwardHealthCheckDelays()
		if got := healthCheckCacheSize(); got != step.want {
			t.Fatalf("%s: retained %d histories, want %d live histories", step.name, got, step.want)
		}
	}
}

func TestHealthCheckCacheProviderUpdatesRemainBounded(t *testing.T) {
	isolateHealthCheckForwarder(t)
	provider := &healthCheckTestProvider{}
	runLock.Lock()
	tunnel.UpdateProxies(map[string]C.Proxy{}, map[string]P.ProxyProvider{"test": provider})
	runLock.Unlock()
	for batch := 0; batch < 2000; batch++ {
		proxies := make([]C.Proxy, 8)
		for index := range proxies {
			proxies[index] = &healthCheckTestProxy{
				name: fmt.Sprintf("batch-%d-node-%d", batch, index), history: healthCheckHistory(31),
				extra: map[string]C.ProxyState{
					fmt.Sprintf("https://a.test/%d", batch): {History: healthCheckHistory(41)},
					fmt.Sprintf("https://b.test/%d", batch): {History: healthCheckHistory(42)},
				},
			}
		}
		provider.replace(proxies)
		forwardHealthCheckDelays()
		if got := healthCheckCacheSize(); got != 24 {
			t.Fatalf("provider update %d retained %d histories, want 24", batch, got)
		}
	}
	provider.replace(nil)
	forwardHealthCheckDelays()
	if got := healthCheckCacheSize(); got != 0 {
		t.Fatalf("empty provider retained %d histories", got)
	}
	if got := provider.touches.Load(); got != 2001 {
		t.Fatalf("provider Touch cadence changed: got %d, want 2001", got)
	}
}

func TestHealthCheckCacheLargeDirectoryIsNotTruncated(t *testing.T) {
	isolateHealthCheckForwarder(t)
	proxies := make([]C.Proxy, 9000)
	for i := range proxies {
		proxies[i] = healthCheckProxy(fmt.Sprintf("large-%d", i))
	}
	setHealthCheckProxies(proxies...)
	forwardHealthCheckDelays()
	if got := healthCheckCacheSize(); got != len(proxies) {
		t.Fatalf("large live directory lost dedup state: %d/%d", got, len(proxies))
	}
	healthCheckMu.Lock()
	before := copyHealthCheckCache(healthCheckSeen)
	healthCheckMu.Unlock()
	forwardHealthCheckDelays()
	healthCheckMu.Lock()
	unchanged := reflect.DeepEqual(before, healthCheckSeen)
	healthCheckMu.Unlock()
	if !unchanged {
		t.Fatal("unchanged large directory changed its dedup state")
	}
	setHealthCheckProxies(proxies[0])
	forwardHealthCheckDelays()
	if got := healthCheckCacheSize(); got != 1 {
		t.Fatalf("shrinking directory retained %d histories", got)
	}
	setHealthCheckProxies()
	forwardHealthCheckDelays()
	if got := healthCheckCacheSize(); got != 0 {
		t.Fatalf("removed large directory retained %d histories", got)
	}
}

func TestHealthCheckCacheResetRejectsInflightSnapshot(t *testing.T) {
	isolateHealthCheckForwarder(t)
	current := healthCheckProxy("new-generation")
	setHealthCheckProxies(current)
	forwardHealthCheckDelays()
	healthCheckMu.Lock()
	want := copyHealthCheckCache(healthCheckSeen)
	healthCheckMu.Unlock()
	resetHealthCheckForwarderState()

	release := make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	old := healthCheckProxy("retired-generation")
	old.entered, old.release = make(chan struct{}), release
	setHealthCheckProxies(old)
	oldDone := make(chan struct{})
	go func() { defer close(oldDone); forwardHealthCheckDelays() }()
	awaitHealthCheck(t, old.entered, "old history snapshot")
	setHealthCheckProxies(current)
	resetHealthCheckForwarderState()
	newDone := make(chan struct{})
	go func() { defer close(newDone); forwardHealthCheckDelays() }()
	unblock()
	awaitHealthCheck(t, oldDone, "retired sweep")
	awaitHealthCheck(t, newDone, "current sweep")
	healthCheckMu.Lock()
	got := copyHealthCheckCache(healthCheckSeen)
	healthCheckMu.Unlock()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("retired snapshot changed current dedup state: got %v, want %v", got, want)
	}
}

func TestHealthCheckCacheStopClearsWithoutWorker(t *testing.T) {
	isolateHealthCheckForwarder(t)
	setHealthCheckProxies(healthCheckProxy("sample"))
	forwardHealthCheckDelays()
	stopHealthCheckForwarder()
	if got := healthCheckCacheSize(); got != 0 {
		t.Fatalf("stopped forwarder retained %d histories without a worker", got)
	}
	stopHealthCheckForwarder()
}

func TestHealthCheckCacheStopRejectsInflightSnapshot(t *testing.T) {
	isolateHealthCheckForwarder(t)
	release := make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	old := healthCheckProxy("stopping")
	old.entered, old.release = make(chan struct{}), release
	setHealthCheckProxies(old)
	done := make(chan struct{})
	go func() { defer close(done); forwardHealthCheckDelays() }()
	awaitHealthCheck(t, old.entered, "history read before stop")
	runLock.Lock()
	stopHealthCheckForwarder()
	currentConfig = nil
	runLock.Unlock()
	unblock()
	awaitHealthCheck(t, done, "sweep after stop")
	if got := healthCheckCacheSize(); got != 0 {
		t.Fatalf("inflight snapshot repopulated %d stopped histories", got)
	}
}

func TestHealthCheckCacheNoConfigDoesNotTouchProvider(t *testing.T) {
	isolateHealthCheckForwarder(t)
	provider := &healthCheckTestProvider{proxies: []C.Proxy{healthCheckProxy("sample")}}
	runLock.Lock()
	currentConfig = nil
	tunnel.UpdateProxies(map[string]C.Proxy{}, map[string]P.ProxyProvider{"test": provider})
	runLock.Unlock()
	forwardHealthCheckDelays()
	if provider.touches.Load() != 0 || healthCheckCacheSize() != 0 {
		t.Fatal("forwarder touched provider or emitted histories without configuration")
	}
}

func TestHealthCheckStoppedRunDoesNotTouchOrRepopulate(t *testing.T) {
	isolateHealthCheckForwarder(t)
	provider := &healthCheckTestProvider{proxies: []C.Proxy{healthCheckProxy("sample")}}
	runLock.Lock()
	tunnel.UpdateProxies(map[string]C.Proxy{}, map[string]P.ProxyProvider{"test": provider})
	runLock.Unlock()
	stopCh := make(chan struct{})
	close(stopCh)
	forwardHealthCheckDelaysForRun(stopCh)
	touchProvidersSafelyForRun(stopCh)
	if provider.touches.Load() != 0 || healthCheckCacheSize() != 0 {
		t.Fatal("retired timer touched provider or repopulated dedup state")
	}
	// The explicit screen-on path still touches the current provider normally.
	touchProvidersSafely()
	if got := provider.touches.Load(); got != 1 {
		t.Fatalf("explicit foreground touch changed: got %d, want 1", got)
	}
}

func TestHealthCheckCacheConcurrentResetsAndFlushes(t *testing.T) {
	isolateHealthCheckForwarder(t)
	setHealthCheckProxies(healthCheckProxy("concurrent"))
	var workers sync.WaitGroup
	for worker := 0; worker < 32; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for iteration := 0; iteration < 20; iteration++ {
				forwardHealthCheckDelays()
			}
		}()
	}
	for iteration := 0; iteration < 20; iteration++ {
		resetHealthCheckForwarderState()
	}
	workers.Wait()
	forwardHealthCheckDelays()
	if got := healthCheckCacheSize(); got != 1 {
		t.Fatalf("concurrent resets corrupted current history: %d", got)
	}
}
