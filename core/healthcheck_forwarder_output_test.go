//go:build !cgo

package main

import (
	"encoding/json"
	"fmt"
	"net"
	"reflect"
	"sort"
	"sync"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

// Observe the production nonblocking stream queue without starting a server or
// dialing the running Core. The writer is deliberately absent: drains below are
// synchronous and no sleeps are needed to assert that dedup emits nothing.
func captureHealthCheckOutput(t *testing.T) func() []Delay {
	t.Helper()
	left, right := net.Pipe()
	output := newCoreOutput(left, time.Second, time.Second)
	connMu.Lock()
	previous := conn
	conn = output
	connMu.Unlock()
	t.Cleanup(func() {
		connMu.Lock()
		conn = previous
		connMu.Unlock()
		output.close()
		right.Close()
	})
	return func() []Delay {
		var delays []Delay
		for {
			select {
			case frame := <-output.queue:
				output.bytes.Add(-int64(len(frame)))
				var envelope struct {
					Method Method `json:"method"`
					Data   struct {
						Type MessageType `json:"type"`
						Data Delay       `json:"data"`
					} `json:"data"`
				}
				if err := json.Unmarshal(frame, &envelope); err != nil {
					t.Fatal(err)
				}
				if envelope.Method != messageMethod || envelope.Data.Type != DelayMessage {
					t.Fatalf("unexpected forwarder output: %s", frame)
				}
				delays = append(delays, envelope.Data.Data)
			default:
				sort.Slice(delays, func(i, j int) bool {
					if delays[i].Name == delays[j].Name {
						return delays[i].Url < delays[j].Url
					}
					return delays[i].Name < delays[j].Name
				})
				return delays
			}
		}
	}
}

func TestHealthCheckOutputDedupAndLatestSampleContract(t *testing.T) {
	isolateHealthCheckForwarder(t)
	drain := captureHealthCheckOutput(t)
	proxy := healthCheckProxy("sample")
	proxy.history = append(healthCheckHistory(8), healthCheckHistory(31)...)
	proxy.extra = map[string]C.ProxyState{"https://zero.test": {History: healthCheckHistory(0)}}
	setHealthCheckProxies(proxy)
	forwardHealthCheckDelays()
	want := []Delay{{Name: "sample", Value: 31}, {Name: "sample", Url: "https://zero.test", Value: -1}}
	if got := drain(); !reflect.DeepEqual(got, want) {
		t.Fatalf("latest/default/URL mapping: got %+v, want %+v", got, want)
	}
	forwardHealthCheckDelays()
	if got := drain(); len(got) != 0 {
		t.Fatalf("unchanged history emitted again: %+v", got)
	}
	proxy.history[len(proxy.history)-1].Time = time.Unix(1700000001, 123)
	forwardHealthCheckDelays()
	if got := drain(); !reflect.DeepEqual(got, want[:1]) {
		t.Fatalf("new timestamp was not emitted: %+v", got)
	}
	proxy.history[len(proxy.history)-1].Delay = 45
	forwardHealthCheckDelays()
	if got := drain(); !reflect.DeepEqual(got, []Delay{{Name: "sample", Value: 45}}) {
		t.Fatalf("changed delay was not emitted: %+v", got)
	}
	resetHealthCheckForwarderState()
	forwardHealthCheckDelays()
	want[0].Value = 45
	if got := drain(); !reflect.DeepEqual(got, want) {
		t.Fatalf("foreground reset failed to republish history: %+v", got)
	}
}

func TestHealthCheckOutputReturningNodePublishesSameSample(t *testing.T) {
	isolateHealthCheckForwarder(t)
	drain := captureHealthCheckOutput(t)
	proxy := healthCheckProxy("returning")
	setHealthCheckProxies(proxy)
	forwardHealthCheckDelays()
	if got := drain(); len(got) != 1 {
		t.Fatalf("first sample missing: %+v", got)
	}
	setHealthCheckProxies()
	forwardHealthCheckDelays()
	if got := drain(); len(got) != 0 {
		t.Fatalf("empty directory emitted delays: %+v", got)
	}
	setHealthCheckProxies(proxy)
	forwardHealthCheckDelays()
	if got := drain(); !reflect.DeepEqual(got, []Delay{{Name: "returning", Value: 31}}) {
		t.Fatalf("returning node's same sample suppressed by stale cache: %+v", got)
	}
}

func TestHealthCheckOutputKeyPartsCannotCollide(t *testing.T) {
	isolateHealthCheckForwarder(t)
	drain := captureHealthCheckOutput(t)
	setHealthCheckProxies(
		&healthCheckTestProxy{name: "a|https://x.test", extra: map[string]C.ProxyState{"https://y.test": {History: healthCheckHistory(31)}}},
		&healthCheckTestProxy{name: "a", extra: map[string]C.ProxyState{"https://x.test|https://y.test": {History: healthCheckHistory(31)}}},
	)
	forwardHealthCheckDelays()
	if got := drain(); len(got) != 2 {
		t.Fatalf("distinct node/URL pairs suppressed each other: %+v", got)
	}
	forwardHealthCheckDelays()
	if got := drain(); len(got) != 0 {
		t.Fatalf("distinct pairs did not independently dedup: %+v", got)
	}
}

func TestHealthCheckOutputConcurrentFlushesEmitOnce(t *testing.T) {
	isolateHealthCheckForwarder(t)
	drain := captureHealthCheckOutput(t)
	setHealthCheckProxies(healthCheckProxy("shared"))
	var workers sync.WaitGroup
	for i := 0; i < 64; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			forwardHealthCheckDelays()
		}()
	}
	workers.Wait()
	if got := drain(); !reflect.DeepEqual(got, []Delay{{Name: "shared", Value: 31}}) {
		t.Fatalf("concurrent snapshots emitted duplicates or lost data: %+v", got)
	}
}

func TestHealthCheckOutputLargeDirectoryDoesNotRepeat(t *testing.T) {
	isolateHealthCheckForwarder(t)
	drain := captureHealthCheckOutput(t)
	proxies := make([]C.Proxy, 9000)
	for i := range proxies {
		proxies[i] = healthCheckProxy(fmt.Sprintf("large-output-%d", i))
	}
	setHealthCheckProxies(proxies...)
	forwardHealthCheckDelays()
	// Stream queue capacity is deliberately bounded and may drop the rest of
	// this batch. Dedup must nevertheless cover every live key on the next tick.
	if got := drain(); len(got) == 0 {
		t.Fatal("initial large directory emitted no samples")
	}
	forwardHealthCheckDelays()
	if got := drain(); len(got) != 0 {
		t.Fatalf("large directory repeated %d samples without a history change", len(got))
	}
}

func TestHealthCheckOutputResetDiscardsInflightSnapshot(t *testing.T) {
	isolateHealthCheckForwarder(t)
	drain := captureHealthCheckOutput(t)
	release := make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	old := healthCheckProxy("retired")
	old.entered, old.release = make(chan struct{}), release
	setHealthCheckProxies(old)
	done := make(chan struct{})
	go func() { defer close(done); forwardHealthCheckDelays() }()
	t.Cleanup(func() { unblock(); awaitHealthCheck(t, done, "retired sweep cleanup") })
	awaitHealthCheck(t, old.entered, "old snapshot read")
	setHealthCheckProxies(healthCheckProxy("current"))
	resetHealthCheckForwarderState()
	unblock()
	awaitHealthCheck(t, done, "retired sweep")
	if got := drain(); len(got) != 0 {
		t.Fatalf("reset snapshot emitted stale delays before current flush: %+v", got)
	}
	if got := healthCheckCacheSize(); got != 0 {
		t.Fatalf("reset snapshot repopulated cache before current flush: %d", got)
	}
	forwardHealthCheckDelays()
	if got := drain(); !reflect.DeepEqual(got, []Delay{{Name: "current", Value: 31}}) {
		t.Fatalf("current snapshot was lost after retiring old data: %+v", got)
	}
}
