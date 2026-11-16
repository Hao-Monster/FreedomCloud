package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"net/netip"
	"os"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/buf"
	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/component/iface"
	C "github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
)

type stabilityFakeProvider struct {
	*networkRecoveryFakeProvider
	mu      sync.RWMutex
	proxies []C.Proxy
}

func (p *stabilityFakeProvider) Proxies() []C.Proxy {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return append([]C.Proxy(nil), p.proxies...)
}

type stabilityFakeAdapter struct {
	*outbound.Base
	dialFn       func(context.Context, *C.Metadata) (C.Conn, error)
	dialPacketFn func(context.Context, *C.Metadata) (C.PacketConn, error)
}

func (a *stabilityFakeAdapter) DialContext(ctx context.Context, metadata *C.Metadata) (C.Conn, error) {
	if a.dialFn != nil {
		return a.dialFn(ctx, metadata)
	}
	return nil, errors.New("dialFn not set")
}

func (a *stabilityFakeAdapter) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	if a.dialPacketFn != nil {
		return a.dialPacketFn(ctx, metadata)
	}
	return nil, errors.New("dialPacketFn not set")
}

type stabilityStubProxy struct {
	*adapter.Proxy
	mu    sync.RWMutex
	alive bool
	delay uint16
}

func newStabilityStubProxy(
	name string,
	alive bool,
	delay uint16,
	dialFn func(context.Context, *C.Metadata) (C.Conn, error),
	dialPacketFn func(context.Context, *C.Metadata) (C.PacketConn, error),
) *stabilityStubProxy {
	base := outbound.NewBase(outbound.BaseOption{
		Name: name,
		Type: C.Trojan,
	})
	fa := &stabilityFakeAdapter{
		Base:         base,
		dialFn:       dialFn,
		dialPacketFn: dialPacketFn,
	}
	return &stabilityStubProxy{
		Proxy: adapter.NewProxy(fa),
		alive: alive,
		delay: delay,
	}
}

func (p *stabilityStubProxy) AliveForTestUrl(_ string) bool {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return p.alive
}

func (p *stabilityStubProxy) LastDelayForTestUrl(_ string) uint16 {
	p.mu.RLock()
	defer p.mu.RUnlock()
	if !p.alive || p.delay == 0 {
		return math.MaxUint16
	}
	return p.delay
}

type scriptedChunk struct {
	data []byte
	err  error
	wait <-chan struct{}
}

type scriptedExtendedConn struct {
	mu           sync.Mutex
	reads        []scriptedChunk
	readIdx      int
	writeErr     error
	needHS       bool
	closed       atomic.Bool
	closeCh      chan struct{}
	chains       C.Chain
	writtenBytes atomic.Int64
}

func newScriptedExtendedConn(reads []scriptedChunk, writeErr error, needHandshake bool) *scriptedExtendedConn {
	return &scriptedExtendedConn{
		reads:    reads,
		writeErr: writeErr,
		needHS:   needHandshake,
		closeCh:  make(chan struct{}),
	}
}

func (c *scriptedExtendedConn) Read(b []byte) (int, error) {
	c.mu.Lock()
	if c.readIdx >= len(c.reads) {
		c.mu.Unlock()
		return 0, io.EOF
	}
	chunk := c.reads[c.readIdx]
	c.readIdx++
	c.mu.Unlock()

	if chunk.wait != nil {
		select {
		case <-chunk.wait:
		case <-c.closeCh:
			return 0, net.ErrClosed
		}
	}
	if c.closed.Load() {
		return 0, net.ErrClosed
	}
	n := copy(b, chunk.data)
	return n, chunk.err
}

func (c *scriptedExtendedConn) ReadBuffer(buffer *buf.Buffer) error {
	tmp := make([]byte, 1024)
	n, err := c.Read(tmp)
	if n > 0 {
		_, _ = buffer.Write(tmp[:n])
	}
	return err
}

func (c *scriptedExtendedConn) Write(b []byte) (int, error) {
	if c.closed.Load() {
		return 0, net.ErrClosed
	}
	if c.writeErr != nil {
		return 0, c.writeErr
	}
	c.writtenBytes.Add(int64(len(b)))
	return len(b), nil
}

func (c *scriptedExtendedConn) WriteBuffer(buffer *buf.Buffer) error {
	_, err := c.Write(buffer.Bytes())
	if err == nil {
		buffer.Advance(buffer.Len())
	}
	return err
}

func (c *scriptedExtendedConn) Close() error {
	if c.closed.CompareAndSwap(false, true) {
		close(c.closeCh)
	}
	return nil
}

func (c *scriptedExtendedConn) LocalAddr() net.Addr                { return &net.TCPAddr{} }
func (c *scriptedExtendedConn) RemoteAddr() net.Addr               { return &net.TCPAddr{} }
func (c *scriptedExtendedConn) SetDeadline(_ time.Time) error      { return nil }
func (c *scriptedExtendedConn) SetReadDeadline(_ time.Time) error  { return nil }
func (c *scriptedExtendedConn) SetWriteDeadline(_ time.Time) error { return nil }
func (c *scriptedExtendedConn) FrontHeadroom() int                 { return 0 }
func (c *scriptedExtendedConn) RearHeadroom() int                  { return 0 }
func (c *scriptedExtendedConn) NeedAdditionalReadTimeout() bool    { return false }
func (c *scriptedExtendedConn) NeedAdditionalWriteTimeout() bool   { return false }
func (c *scriptedExtendedConn) WriterReplaceable() bool            { return true }
func (c *scriptedExtendedConn) ReaderReplaceable() bool            { return true }
func (c *scriptedExtendedConn) NeedHandshake() bool                { return c.needHS }
func (c *scriptedExtendedConn) Chains() C.Chain                  { return c.chains }
func (c *scriptedExtendedConn) ProviderChains() C.Chain          { return nil }
func (c *scriptedExtendedConn) AppendToChains(a C.ProxyAdapter)    { c.chains = append(c.chains, a.Name()) }
func (c *scriptedExtendedConn) RemoteDestination() string        { return "" }
func (c *scriptedExtendedConn) CustomContext() any                 { return nil }
func (c *scriptedExtendedConn) SetCustomContext(_ any)             {}

func newTestURLTestGroup(t *testing.T, proxies ...C.Proxy) *outboundgroup.URLTest {
	t.Helper()
	rejectFallback := newStabilityStubProxy("REJECT", true, 65000, nil, nil)
	prov := &stabilityFakeProvider{
		networkRecoveryFakeProvider: &networkRecoveryFakeProvider{name: "stability-provider"},
		proxies:                     proxies,
	}
	group, err := outboundgroup.NewURLTest(
		outboundgroup.GroupCommonOption{
			Name: "AI-Auto",
			URL:  "https://cp.cloudflare.com/generate_204",
		},
		outboundgroup.URLTestOption{Tolerance: 50},
		rejectFallback,
		[]cp.ProxyProvider{prov},
	)
	if err != nil {
		t.Fatalf("NewURLTest failed: %v", err)
	}
	return group
}

func TestStabilityPenaltyDecay180sHalfLifeAndBounds(t *testing.T) {
	gb := outboundgroup.NewGroupBase(outboundgroup.GroupBaseOption{Name: "TestGroup", Type: C.URLTest})
	start := time.Now()
	if !gb.RecordDialErrorFCX("node-a", syscall.ECONNRESET, context.Background(), nil) {
		t.Fatal("expected ECONNRESET dial error to record penalty")
	}

	initialScore := gb.StabilityPenaltyScoreAtFCX("node-a", start)
	if math.Abs(initialScore-1.0) > 0.02 {
		t.Fatalf("expected initial score ~1.0, got %v", initialScore)
	}
	if got := gb.EffectiveDelayAtFCX("node-a", 80, start); got != 330 {
		t.Fatalf("expected effective delay 330ms, got %d", got)
	}

	at180s := start.Add(180 * time.Second)
	score180 := gb.StabilityPenaltyScoreAtFCX("node-a", at180s)
	if math.Abs(score180-0.5) > 0.02 {
		t.Fatalf("expected 180s half-life score ~0.5, got %v", score180)
	}
	delay180 := gb.EffectiveDelayAtFCX("node-a", 80, at180s)
	if delay180 < 204 || delay180 > 206 {
		t.Fatalf("expected 180s effective delay ~205ms, got %d", delay180)
	}

	at360s := start.Add(360 * time.Second)
	score360 := gb.StabilityPenaltyScoreAtFCX("node-a", at360s)
	if math.Abs(score360-0.25) > 0.02 {
		t.Fatalf("expected 360s two-half-life score ~0.25, got %v", score360)
	}

	at2000s := start.Add(2000 * time.Second)
	if score := gb.StabilityPenaltyScoreAtFCX("node-a", at2000s); score != 0 {
		t.Fatalf("expected stale entry to prune to 0, got %v", score)
	}
	if got := gb.EffectiveDelayAtFCX("node-a", 80, at2000s); got != 80 {
		t.Fatalf("expected base delay 80 after decay, got %d", got)
	}

	// Score capping preserves dead-node ordering below math.MaxUint16 sentinel.
	for i := 0; i < 40; i++ {
		gb.RecordReadErrorFCX("node-cap", io.ErrUnexpectedEOF, 10, 10, nil)
	}
	if got := gb.EffectiveDelayFCX("node-cap", 63000); got != math.MaxUint16-1 {
		t.Fatalf("expected penalized alive delay to clamp at MaxUint16-1 (%d), got %d", math.MaxUint16-1, got)
	}
	if got := gb.EffectiveDelayFCX("node-cap", math.MaxUint16); got != math.MaxUint16 {
		t.Fatalf("expected dead-node sentinel MaxUint16 preserved, got %d", got)
	}
}

func TestStabilityErrorClassificationIgnoresCleanEOFAndCancelAndClose(t *testing.T) {
	gb := outboundgroup.NewGroupBase(outboundgroup.GroupBaseOption{Name: "TestGroup", Type: C.URLTest})

	// 1. Clean response followed by io.EOF via Read -> 0 penalty.
	cleanConn := newScriptedExtendedConn([]scriptedChunk{
		{data: []byte("HTTP/1.1 200 OK\r\n\r\nhello")},
		{err: io.EOF},
	}, nil, false)
	wrappedClean := gb.WrapStableConnFCX("node-clean", cleanConn, nil)
	if _, err := wrappedClean.Write([]byte("GET / HTTP/1.1\r\n\r\n")); err != nil {
		t.Fatal(err)
	}
	bufBytes := make([]byte, 64)
	if _, err := wrappedClean.Read(bufBytes); err != nil {
		t.Fatal(err)
	}
	if _, err := wrappedClean.Read(bufBytes); !errors.Is(err, io.EOF) {
		t.Fatalf("expected io.EOF, got %v", err)
	}
	if score := gb.StabilityPenaltyScoreFCX("node-clean"); score != 0 {
		t.Fatalf("expected 0 penalty on clean post-bytes io.EOF, got %v", score)
	}

	// 2. Clean ReadBuffer path -> 0 penalty.
	cleanBufConn := newScriptedExtendedConn([]scriptedChunk{
		{data: []byte("sse-event")},
		{err: io.EOF},
	}, nil, false)
	wrappedBuf := gb.WrapStableConnFCX("node-clean-buf", cleanBufConn, nil)
	rb := buf.NewSize(64)
	defer rb.Release()
	if err := wrappedBuf.ReadBuffer(rb); err != nil {
		t.Fatal(err)
	}
	if err := wrappedBuf.ReadBuffer(rb); !errors.Is(err, io.EOF) {
		t.Fatalf("expected io.EOF from ReadBuffer, got %v", err)
	}
	if score := gb.StabilityPenaltyScoreFCX("node-clean-buf"); score != 0 {
		t.Fatalf("expected 0 penalty on clean ReadBuffer EOF, got %v", score)
	}

	// 3. Explicit Close() while Read unblocks with ECONNRESET / net.ErrClosed -> 0 penalty.
	unblockCh := make(chan struct{})
	closeConn := newScriptedExtendedConn([]scriptedChunk{
		{err: syscall.ECONNRESET, wait: unblockCh},
	}, nil, false)
	wrappedClose := gb.WrapStableConnFCX("node-close", closeConn, nil)
	readDone := make(chan error, 1)
	go func() {
		_, err := wrappedClose.Read(make([]byte, 16))
		readDone <- err
	}()
	time.Sleep(15 * time.Millisecond)
	_ = wrappedClose.Close()
	close(unblockCh)
	<-readDone
	if score := gb.StabilityPenaltyScoreFCX("node-close"); score != 0 {
		t.Fatalf("expected 0 penalty on local Close(), got %v", score)
	}

	// 4. Context cancellation during DialContext -> 0 penalty.
	canceledCtx, cancel := context.WithCancel(context.Background())
	cancel()
	if gb.RecordDialErrorFCX("node-cancel", context.Canceled, canceledCtx, nil) {
		t.Fatal("expected context.Canceled dial error not to penalize")
	}
	if gb.RecordDialErrorFCX("node-cancel", syscall.ECONNRESET, canceledCtx, nil) {
		t.Fatal("expected canceled dialCtx to suppress penalty")
	}
	if score := gb.StabilityPenaltyScoreFCX("node-cancel"); score != 0 {
		t.Fatalf("expected 0 penalty for canceled operations, got %v", score)
	}

	// 5. DialDeadline expiring AFTER dial completion must NOT suppress real mid-stream ErrUnexpectedEOF.
	dialCtx, dialCancel := context.WithTimeout(context.Background(), 5*time.Millisecond)
	defer dialCancel()
	nodeA := newStabilityStubProxy("node-a", true, 80, func(_ context.Context, _ *C.Metadata) (C.Conn, error) {
		return newScriptedExtendedConn([]scriptedChunk{
			{data: []byte("data: chunk1\n")},
			{err: io.ErrUnexpectedEOF},
		}, nil, false), nil
	}, nil)
	group := newTestURLTestGroup(t, nodeA)
	conn, err := group.DialContext(dialCtx, &C.Metadata{Host: "api.openai.com", DstPort: 443})
	if err != nil {
		t.Fatalf("unexpected dial error: %v", err)
	}
	time.Sleep(20 * time.Millisecond)
	if dialCtx.Err() == nil {
		t.Fatal("expected dialCtx deadline to expire before mid-stream read")
	}
	if _, err := conn.Read(make([]byte, 32)); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.Read(make([]byte, 32)); !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("expected ErrUnexpectedEOF, got %v", err)
	}
	if score := group.StabilityPenaltyScoreFCX("node-a"); score < 0.9 {
		t.Fatalf("expected mid-stream ErrUnexpectedEOF after expired dialCtx to penalize, got %v", score)
	}
}

func TestURLTestDemotesMidStreamEOFAndRSTAndSinglePenaltyPerConn(t *testing.T) {
	var connMode atomic.Int32
	nodeA := newStabilityStubProxy("node-a", true, 80, func(_ context.Context, _ *C.Metadata) (C.Conn, error) {
		switch connMode.Load() {
		case 0:
			// NeedHandshake + partial SSE stream followed by ErrUnexpectedEOF, and also write fail later.
			return newScriptedExtendedConn([]scriptedChunk{
				{data: []byte("data: partial\n")},
				{err: io.ErrUnexpectedEOF},
			}, nil, true), nil
		case 1:
			// Request written, then zero-byte io.EOF without any response byte -> penalized!
			return newScriptedExtendedConn([]scriptedChunk{
				{err: io.EOF},
			}, nil, false), nil
		case 2:
			// Handshake first-write RST -> penalized ONCE (not doubled by FirstWriteCallBackConn + Write).
			return newScriptedExtendedConn(nil, syscall.ECONNRESET, true), nil
		default:
			// Timeout mid-stream -> penalized.
			return newScriptedExtendedConn([]scriptedChunk{
				{err: os.ErrDeadlineExceeded},
			}, nil, false), nil
		}
	}, nil)
	nodeB := newStabilityStubProxy("node-b", true, 150, func(_ context.Context, _ *C.Metadata) (C.Conn, error) {
		return newScriptedExtendedConn([]scriptedChunk{
			{data: []byte("ok")},
			{err: io.EOF},
		}, nil, false), nil
	}, nil)

	group := newTestURLTestGroup(t, nodeA, nodeB)
	if got := group.Now(); got != "node-a" {
		t.Fatalf("expected initial best proxy node-a (80ms < 120ms), got %q", got)
	}

	// Verify NeedHandshake propagates via Upstream() AND UnwrapReader stops at fcxStabilityConn.
	c1, err := group.DialContext(context.Background(), &C.Metadata{Host: "api.anthropic.com", DstPort: 443})
	if err != nil {
		t.Fatalf("DialContext failed: %v", err)
	}
	if !N.NeedHandshake(c1) {
		t.Fatal("expected wrapped NeedHandshake connection to report NeedHandshake() == true via Upstream()")
	}
	if unwrapped := N.UnwrapReader(c1); unwrapped != c1 {
		t.Fatal("expected ReaderReplaceable() == false to keep UnwrapReader at fcxStabilityConn")
	}

	if _, err := c1.Write([]byte("POST /v1/messages HTTP/1.1\r\n")); err != nil {
		t.Fatal(err)
	}
	tmp := make([]byte, 64)
	if _, err := c1.Read(tmp); err != nil {
		t.Fatal(err)
	}
	if _, err := c1.Read(tmp); !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("expected ErrUnexpectedEOF, got %v", err)
	}
	// Second failure on same conn must not add a second penalty.
	_, _ = c1.Read(tmp)
	scoreAfterC1 := group.StabilityPenaltyScoreFCX("node-a")
	if math.Abs(scoreAfterC1-1.0) > 0.02 {
		t.Fatalf("expected single penalty 1.0 on node-a, got %v", scoreAfterC1)
	}
	if got := group.Now(); got != "node-b" {
		t.Fatalf("expected URLTest to immediately demote node-a and route to node-b, got %q", got)
	}

	// Verify ResetStabilityPenaltiesFCX restores node-a, then test zero-byte EOF after write and first-write RST.
	group.ResetStabilityPenaltiesFCX()
	group.ResetFastCacheFCX()
	if got := group.Now(); got != "node-a" {
		t.Fatalf("expected node-a to recover after penalty reset, got %q", got)
	}

	connMode.Store(1)
	c2, err := group.DialContext(context.Background(), &C.Metadata{Host: "api.openai.com", DstPort: 443})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c2.Write([]byte("GET / HTTP/1.1\r\n")); err != nil {
		t.Fatal(err)
	}
	if _, err := c2.Read(tmp); !errors.Is(err, io.EOF) {
		t.Fatalf("expected zero-byte io.EOF, got %v", err)
	}
	if score := group.StabilityPenaltyScoreFCX("node-a"); math.Abs(score-1.0) > 0.02 {
		t.Fatalf("expected zero-byte EOF after request write to add penalty 1.0, got %v", score)
	}
	if got := group.Now(); got != "node-b" {
		t.Fatalf("expected node-b after zero-byte EOF, got %q", got)
	}

	group.ResetStabilityPenaltiesFCX()
	group.ResetFastCacheFCX()
	connMode.Store(2)
	c3, err := group.DialContext(context.Background(), &C.Metadata{Host: "api.openai.com", DstPort: 443})
	if err != nil {
		t.Fatal(err)
	}
	wb := buf.NewSize(16)
	_, _ = wb.Write([]byte("clienthello"))
	if err := c3.WriteBuffer(wb); !errors.Is(err, syscall.ECONNRESET) {
		t.Fatalf("expected ECONNRESET from WriteBuffer, got %v", err)
	}
	wb.Release()
	if score := group.StabilityPenaltyScoreFCX("node-a"); math.Abs(score-1.0) > 0.02 {
		t.Fatalf("expected single penalty 1.0 for first-write handshake ECONNRESET, got %v", score)
	}

	group.ResetStabilityPenaltiesFCX()
	group.ResetFastCacheFCX()
	connMode.Store(3)
	c4, err := group.DialContext(context.Background(), &C.Metadata{Host: "api.openai.com", DstPort: 443})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c4.Read(tmp); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("expected deadline exceeded, got %v", err)
	}
	if score := group.StabilityPenaltyScoreFCX("node-a"); math.Abs(score-1.0) > 0.02 {
		t.Fatalf("expected timeout read to add penalty 1.0, got %v", score)
	}
}

func TestPhysicalNetworkSwitchResetsStabilityPenaltiesAndHealthCheckDoesNot(t *testing.T) {
	_, _, fakeProv := setupSurgicalRecoveryEnv(t, "stability-recovery-provider")

	nodeA := newStabilityStubProxy("node-a", true, 80, nil, nil)
	nodeB := newStabilityStubProxy("node-b", true, 150, nil, nil)
	group := newTestURLTestGroup(t, nodeA, nodeB)
	wrappedGroup := adapter.NewProxy(group)

	proxyStateMu.Lock()
	tunnel.UpdateProxies(map[string]C.Proxy{
		"AI-Auto": wrappedGroup,
	}, map[string]cp.ProxyProvider{
		fakeProv.name: fakeProv,
	})
	proxyStateMu.Unlock()

	if !group.RecordDialErrorFCX("node-a", syscall.ECONNRESET, context.Background(), group.ResetFastCacheFCX) {
		t.Fatal("expected penalty on node-a")
	}
	if got := group.Now(); got != "node-b" {
		t.Fatalf("expected node-b when node-a is penalized, got %q", got)
	}

	// Health checks alone must NOT wipe mid-stream stability penalties.
	networkRecoveryMu.Lock()
	networkHealthCheckEpoch++
	epoch := networkHealthCheckEpoch
	networkRecoveryMu.Unlock()
	runNetworkRecoveryHealthChecks(epoch)
	if score := group.StabilityPenaltyScoreFCX("node-a"); score == 0 {
		t.Fatal("runNetworkRecoveryHealthChecks must not reset stability penalties")
	}

	// Real physical interface switch resets stability penalties so node-a is evaluated fresh.
	restoreIfaces := iface.FCXOverrideInterfacesForTest([]*iface.Interface{
		{
			Index:     42,
			MTU:       1500,
			Name:      "Ethernet",
			Addresses: []netip.Prefix{netip.MustParsePrefix("10.20.30.40/24")},
		},
	})
	t.Cleanup(restoreIfaces)

	onTunDefaultInterfaceChanged(sing_tun.FCXDefaultInterfaceEvent{
		Name:      "Ethernet",
		Index:     42,
		Addresses: []netip.Prefix{netip.MustParsePrefix("10.20.30.40/24")},
	})
	if score := group.StabilityPenaltyScoreFCX("node-a"); score != 0 {
		t.Fatalf("expected physical interface switch to reset stability penalties, got %v", score)
	}
	if got := group.Now(); got != "node-a" {
		t.Fatalf("expected node-a to become preferred after physical network switch reset, got %q", got)
	}
}

func TestStabilityTrackerConcurrentRace(t *testing.T) {
	nodeA := newStabilityStubProxy("node-a", true, 80, func(_ context.Context, _ *C.Metadata) (C.Conn, error) {
		return newScriptedExtendedConn([]scriptedChunk{
			{data: []byte("abc")},
			{err: io.ErrUnexpectedEOF},
		}, nil, false), nil
	}, nil)
	nodeB := newStabilityStubProxy("node-b", true, 100, func(_ context.Context, _ *C.Metadata) (C.Conn, error) {
		return newScriptedExtendedConn([]scriptedChunk{
			{data: []byte("ok")},
			{err: io.EOF},
		}, nil, false), nil
	}, nil)
	group := newTestURLTestGroup(t, nodeA, nodeB)

	var wg sync.WaitGroup
	for g := 0; g < 12; g++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for i := 0; i < 16; i++ {
				conn, err := group.DialContext(context.Background(), &C.Metadata{Host: fmt.Sprintf("h-%d.test", id), DstPort: 443})
				if err != nil {
					continue
				}
				_, _ = conn.Write([]byte("ping"))
				tmp := make([]byte, 16)
				_, _ = conn.Read(tmp)
				_, _ = conn.Read(tmp)
				_ = conn.Close()
			}
		}(g)
	}
	for g := 0; g < 4; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 20; i++ {
				_ = group.Now()
				_ = group.EffectiveDelayFCX("node-a", 80)
				_ = group.StabilityPenaltyScoreFCX("node-a")
				if i%7 == 0 {
					group.ResetStabilityPenaltiesFCX()
				}
			}
		}()
	}
	wg.Wait()
}
