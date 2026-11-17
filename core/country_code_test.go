package main

import (
	"context"
	"net/netip"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/constant"
)

func TestPickIsoCountryCodeExtractsIsoTagFromMultiTagMetaGeoIP(t *testing.T) {
	cases := []struct {
		name  string
		codes []string
		want  string
	}{
		{name: "cloudflare_us", codes: []string{"cloudflare", "us"}, want: "US"},
		{name: "telegram_nl", codes: []string{"telegram", "nl"}, want: "NL"},
		{name: "cloudfront_de", codes: []string{"cloudfront", "de"}, want: "DE"},
		{name: "iso_first_au", codes: []string{"au", "cloudflare"}, want: "AU"},
		{name: "uk_maps_to_gb", codes: []string{"uk"}, want: "GB"},
		{name: "service_only_cloudflare", codes: []string{"cloudflare"}, want: ""},
		{name: "private_tag", codes: []string{"private"}, want: ""},
		{name: "region_eu", codes: []string{"eu"}, want: ""},
		{name: "unknown_xx", codes: []string{"xx"}, want: ""},
		{name: "empty_slice", codes: nil, want: ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := pickIsoCountryCode(tc.codes); got != tc.want {
				t.Fatalf("pickIsoCountryCode(%v) = %q, want %q", tc.codes, got, tc.want)
			}
		})
	}
}

func TestResolveCountryCodeWithDepsHandlesDirectIPDomainAndFakeIP(t *testing.T) {
	mmdbByIP := map[string][]string{
		"104.18.25.100":        {"cloudflare", "us"},
		"2606:4700::6810:85e5": {"cloudflare", "us"},
		"104.21.8.8":           {"cloudflare", "us"},
		"2606:4700::1":         {"cloudflare", "us"},
		"141.101.64.10":        {"cloudflare", "nl"},
	}

	mmdbCalls := 0
	lookupMMDB := func(addr netip.Addr) []string {
		mmdbCalls++
		return mmdbByIP[addr.String()]
	}

	var dnsCalls []string
	lookupHostIPs := func(_ context.Context, host string) ([]netip.Addr, error) {
		dnsCalls = append(dnsCalls, host)
		switch host {
		case "cf-prefer.freedomnet.net":
			return []netip.Addr{
				netip.MustParseAddr("198.18.0.55"),
				netip.MustParseAddr("2606:4700::1"),
				netip.MustParseAddr("104.21.8.8"),
			}, nil
		case "cf-v6.freedomnet.net":
			return []netip.Addr{
				netip.MustParseAddr("2606:4700::1"),
			}, nil
		case "cf-mapped.freedomnet.net":
			return []netip.Addr{
				netip.MustParseAddr("141.101.64.10"),
			}, nil
		default:
			return nil, nil
		}
	}

	findHostByFakeIP := func(addr netip.Addr) (string, bool) {
		if addr.String() == "198.18.0.99" {
			return "cf-mapped.freedomnet.net", true
		}
		return "", false
	}

	ctx := context.Background()

	if got := resolveCountryCodeWithDeps(ctx, "104.18.25.100", findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "US" {
		t.Fatalf("direct IPv4 = %q, want US", got)
	}
	if got := resolveCountryCodeWithDeps(ctx, "[2606:4700::6810:85e5]", findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "US" {
		t.Fatalf("bracketed IPv6 = %q, want US", got)
	}

	beforeBogonCalls := mmdbCalls
	for _, bogon := range []string{"127.0.0.1", "10.0.0.1", "198.18.0.55"} {
		if got := resolveCountryCodeWithDeps(ctx, bogon, findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "" {
			t.Fatalf("bogon/unmapped fake IP %q = %q, want empty", bogon, got)
		}
	}
	if mmdbCalls != beforeBogonCalls {
		t.Fatalf("expected bogon IPs not to invoke MMDB, calls increased %d -> %d", beforeBogonCalls, mmdbCalls)
	}

	if got := resolveCountryCodeWithDeps(ctx, "cf-prefer.freedomnet.net", findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "US" {
		t.Fatalf("domain resolution = %q, want US", got)
	}
	if got := resolveCountryCodeWithDeps(ctx, "cf-v6.freedomnet.net", findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "US" {
		t.Fatalf("ipv6-only domain = %q, want US", got)
	}
	if got := resolveCountryCodeWithDeps(ctx, "198.18.0.99", findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "NL" {
		t.Fatalf("mapped Fake-IP = %q, want NL", got)
	}

	beforeLocalDNS := len(dnsCalls)
	for _, localHost := range []string{"localhost", "node.local", "test.invalid", "singlelabel"} {
		if got := resolveCountryCodeWithDeps(ctx, localHost, findHostByFakeIP, lookupHostIPs, lookupMMDB); got != "" {
			t.Fatalf("local/bogon host %q = %q, want empty", localHost, got)
		}
	}
	if len(dnsCalls) != beforeLocalDNS {
		t.Fatalf("expected local/bogon hostnames not to trigger DNS, got calls %v", dnsCalls[beforeLocalDNS:])
	}
}

func TestHandleGetCountryCodeUninitializedDoesNotCrashAndReturnsEmpty(t *testing.T) {
	prevInit := isInit.Load()
	prevReady := mmdbReady.Load()
	t.Cleanup(func() {
		isInit.Store(prevInit)
		mmdbReady.Store(prevReady)
	})

	isInit.Store(false)
	mmdbReady.Store(false)

	var wg sync.WaitGroup
	wg.Add(1)
	var got string
	handleGetCountryCode("104.18.1.1", func(value string) {
		got = value
		wg.Done()
	})
	wg.Wait()

	if got != "" {
		t.Fatalf("uninitialized handleGetCountryCode = %q, want empty string", got)
	}
}

func TestBundledGeoIPMetaDBResolvesCloudflareDirectIPsToCountryCodes(t *testing.T) {
	assetsDir, err := filepath.Abs(filepath.Join("..", "assets", "data"))
	if err != nil {
		t.Fatalf("resolve assets/data failed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(assetsDir, "geoip.metadb")); err != nil {
		t.Skipf("bundled geoip.metadb unavailable: %v", err)
	}

	prevHome := constant.Path.HomeDir()
	prevInit := isInit.Load()
	prevReady := mmdbReady.Load()
	mmdb.ReloadIP()
	t.Cleanup(func() {
		constant.SetHomeDir(prevHome)
		isInit.Store(prevInit)
		mmdbReady.Store(prevReady)
		mmdb.ReloadIP()
	})

	constant.SetHomeDir(assetsDir)
	isInit.Store(true)
	mmdbReady.Store(false)

	cases := []struct {
		ip   string
		want string
	}{
		{ip: "104.18.1.1", want: "US"},
		{ip: "172.67.1.1", want: "US"},
		{ip: "141.101.64.1", want: "NL"},
		{ip: "149.154.167.50", want: "NL"},
	}

	for _, tc := range cases {
		var wg sync.WaitGroup
		wg.Add(1)
		var got string
		handleGetCountryCode(tc.ip, func(value string) {
			got = value
			wg.Done()
		})
		wg.Wait()
		if got != tc.want {
			t.Fatalf("handleGetCountryCode(%q) = %q, want %q", tc.ip, got, tc.want)
		}
	}
}
