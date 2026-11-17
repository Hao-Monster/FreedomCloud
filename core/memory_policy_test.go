package main

import (
	"bytes"
	"crypto/tls"
	"net"
	"net/netip"
	"os"
	"runtime"
	"runtime/debug"
	"testing"
	"time"

	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/component/sniffer"
)

func TestRuntimeMemoryLimitForGOOS(t *testing.T) {
	if got := runtimeMemoryLimitForGOOS("android"); got != 96*1024*1024 {
		t.Fatalf("android memory limit: got %d want %d", got, 96*1024*1024)
	}
	for _, goos := range []string{"windows", "darwin", "linux"} {
		if got := runtimeMemoryLimitForGOOS(goos); got != 512*1024*1024 {
			t.Fatalf("%s memory limit: got %d want %d", goos, got, 512*1024*1024)
		}
	}
}

func TestConfigureRuntimeMemory(t *testing.T) {
	oldGC := debug.SetGCPercent(-1)
	oldLimit := debug.SetMemoryLimit(-1)
	t.Cleanup(func() {
		debug.SetGCPercent(oldGC)
		debug.SetMemoryLimit(oldLimit)
	})

	wantLimit := runtimeMemoryLimitForGOOS(runtime.GOOS)
	configureRuntimeMemory()
	if current := debug.SetGCPercent(runtimeGCPercent); current != runtimeGCPercent {
		t.Fatalf("unexpected GC percent: got %d want %d", current, runtimeGCPercent)
	}
	if current := debug.SetMemoryLimit(wantLimit); current != wantLimit {
		t.Fatalf(
			"unexpected memory limit: got %d want %d",
			current,
			wantLimit,
		)
	}
}

func buildTestTLSClientHello(t *testing.T, serverName string) []byte {
	t.Helper()
	clientConn, serverConn := net.Pipe()
	defer clientConn.Close()
	defer serverConn.Close()

	var helloBuf bytes.Buffer
	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = serverConn.SetReadDeadline(time.Now().Add(2 * time.Second))
		buf := make([]byte, 4096)
		n, _ := serverConn.Read(buf)
		if n > 0 {
			helloBuf.Write(buf[:n])
		}
		_ = serverConn.Close()
	}()

	tlsClient := tls.Client(clientConn, &tls.Config{
		ServerName:         serverName,
		InsecureSkipVerify: true,
	})
	_ = tlsClient.SetDeadline(time.Now().Add(2 * time.Second))
	_ = tlsClient.Handshake()
	<-done
	if helloBuf.Len() == 0 {
		t.Fatal("failed to capture TLS ClientHello bytes")
	}
	return helloBuf.Bytes()
}

func TestMihomoParsesStabilityFieldsAndRecoversMissingFakeIP(t *testing.T) {
	prevHome := C.Path.HomeDir()
	tempHome, mkErr := os.MkdirTemp("", "fcx-mihomo-stability-*")
	if mkErr != nil {
		t.Fatalf("MkdirTemp failed: %v", mkErr)
	}
	C.SetHomeDir(tempHome)
	t.Cleanup(func() {
		C.SetHomeDir(prevHome)
		_ = os.RemoveAll(tempHome)
	})

	rawYAML := []byte(`
mixed-port: 7890
keep-alive-idle: 15
keep-alive-interval: 15
profile:
  store-selected: false
  store-fake-ip: true
tun:
  enable: true
  stack: mixed
  mtu: 1500
  auto-route: true
dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
sniffer:
  enable: true
  force-dns-mapping: false
  parse-pure-ip: true
  override-destination: true
  skip-dst-address:
    - 127.0.0.0/8
    - 10.0.0.0/8
    - 100.64.0.0/10
    - 169.254.0.0/16
    - 172.16.0.0/12
    - 192.168.0.0/16
    - fc00::/7
    - fe80::/10
  sniff:
    HTTP:
      ports: ["80", "8080-8880"]
      override-destination: true
    TLS:
      ports: ["443", "8443"]
      override-destination: true
    QUIC:
      ports: ["443", "8443"]
      override-destination: true
`)
	rawCfg, err := config.UnmarshalRawConfig(rawYAML)
	if err != nil {
		t.Fatalf("UnmarshalRawConfig failed: %v", err)
	}
	if rawCfg.KeepAliveIdle != 15 || rawCfg.KeepAliveInterval != 15 {
		t.Fatalf("unexpected keep-alive fields: idle=%d interval=%d", rawCfg.KeepAliveIdle, rawCfg.KeepAliveInterval)
	}
	if !rawCfg.Profile.StoreFakeIP || rawCfg.Profile.StoreSelected {
		t.Fatalf("unexpected profile flags: storeFakeIP=%v storeSelected=%v", rawCfg.Profile.StoreFakeIP, rawCfg.Profile.StoreSelected)
	}
	if rawCfg.Tun.MTU != 1500 {
		t.Fatalf("unexpected tun MTU: got %d want 1500", rawCfg.Tun.MTU)
	}

	parsed, err := config.ParseRawConfig(rawCfg)
	if err != nil {
		t.Fatalf("ParseRawConfig failed: %v", err)
	}
	if parsed.General.Tun.MTU != 1500 {
		t.Fatalf("parsed General.Tun.MTU = %d, want 1500", parsed.General.Tun.MTU)
	}
	dispatcher, err := sniffer.NewDispatcher(parsed.Sniffer)
	if err != nil {
		t.Fatalf("NewDispatcher failed: %v", err)
	}
	if !dispatcher.Enable() {
		t.Fatal("expected sniffer dispatcher to be enabled")
	}

	helloBytes := buildTestTLSClientHello(t, "chatgpt.com")

	// 1. Stale/missing Fake-IP (Host == "", DstIP == 198.18.0.48): must sniff SNI,
	// populate Host = "chatgpt.com", and clear bogus DstIP so outbound dials domain!
	c1, s1 := net.Pipe()
	defer c1.Close()
	defer s1.Close()
	go func() {
		_, _ = c1.Write(helloBytes)
	}()
	bufConn := N.NewBufferedConn(s1)
	missingFakeMeta := &C.Metadata{
		NetWork: C.TCP,
		SrcIP:   netip.MustParseAddr("198.18.0.1"),
		SrcPort: 54321,
		DstIP:   netip.MustParseAddr("198.18.0.48"),
		DstPort: 443,
	}
	if !dispatcher.TCPSniff(bufConn, missingFakeMeta) {
		t.Fatal("expected TCPSniff to recover domain for missing Fake-IP 198.18.0.48:443")
	}
	if missingFakeMeta.Host != "chatgpt.com" {
		t.Fatalf("recovered Host = %q, want %q", missingFakeMeta.Host, "chatgpt.com")
	}
	if missingFakeMeta.DstIP.IsValid() {
		t.Fatalf("expected bogus Fake-IP DstIP to be cleared, still got %s", missingFakeMeta.DstIP)
	}

	// 2. Normal Fake-IP hit or explicit domain proxy (Host != ""): must NOT sniff!
	c2, s2 := net.Pipe()
	defer c2.Close()
	defer s2.Close()
	normalMeta := &C.Metadata{
		NetWork: C.TCP,
		Host:    "api.openai.com",
		DNSMode: C.DNSFakeIP,
		DstPort: 443,
	}
	if dispatcher.TCPSniff(N.NewBufferedConn(s2), normalMeta) {
		t.Fatal("expected TCPSniff to skip connection that already has resolved Host")
	}

	// 3. Private LAN / Tailscale CGNAT direct-IP (100.100.100.100:443): must skip!
	c3, s3 := net.Pipe()
	defer c3.Close()
	defer s3.Close()
	lanMeta := &C.Metadata{
		NetWork: C.TCP,
		DstIP:   netip.MustParseAddr("100.100.100.100"),
		DstPort: 443,
	}
	if dispatcher.TCPSniff(N.NewBufferedConn(s3), lanMeta) {
		t.Fatal("expected TCPSniff to skip Tailscale/CGNAT destination IP")
	}
}
