package main

import (
	"context"
	"net"
	"net/netip"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
)

var (
	mmdbReady      atomic.Bool
	nonCountryISO2 = map[string]struct{}{
		"UN": {},
		"EU": {},
		"XX": {},
		"ZZ": {},
		"AA": {},
	}
	specialHostIPv4Prefixes = []netip.Prefix{
		netip.MustParsePrefix("0.0.0.0/8"),
		netip.MustParsePrefix("100.64.0.0/10"),   // RFC 6598 CGNAT / Tailscale
		netip.MustParsePrefix("192.0.0.0/24"),    // IETF protocol assignments
		netip.MustParsePrefix("192.0.2.0/24"),    // TEST-NET-1
		netip.MustParsePrefix("198.18.0.0/15"),   // RFC 2544 / Mihomo default Fake-IP pool
		netip.MustParsePrefix("198.51.100.0/24"), // TEST-NET-2
		netip.MustParsePrefix("203.0.113.0/24"),  // TEST-NET-3
		netip.MustParsePrefix("224.0.0.0/4"),     // Multicast
		netip.MustParsePrefix("240.0.0.0/4"),     // Reserved / Broadcast
	}
	ipv6DocPrefix = netip.MustParsePrefix("2001:db8::/32")
)

const countryLookupTimeout = 2 * time.Second

// pickIsoCountryCode extracts the first valid ISO 3166-1 alpha-2 country code
// from a Meta-geoip0 multi-tag slice (skipping CDN/service tags such as
// "cloudflare", "cloudfront", "telegram", "private", etc.).
func pickIsoCountryCode(codes []string) string {
	for _, raw := range codes {
		trimmed := strings.ToUpper(strings.TrimSpace(raw))
		if trimmed == "UK" {
			return "GB"
		}
		if len(trimmed) != 2 {
			continue
		}
		a, b := trimmed[0], trimmed[1]
		if a < 'A' || a > 'Z' || b < 'A' || b > 'Z' {
			continue
		}
		if _, reserved := nonCountryISO2[trimmed]; reserved {
			continue
		}
		return trimmed
	}
	return ""
}

func isPublicRoutableAddr(addr netip.Addr) bool {
	if !addr.IsValid() {
		return false
	}
	addr = addr.Unmap()
	if addr.IsUnspecified() ||
		addr.IsLoopback() ||
		addr.IsPrivate() ||
		addr.IsLinkLocalUnicast() ||
		addr.IsLinkLocalMulticast() ||
		addr.IsInterfaceLocalMulticast() ||
		addr.IsMulticast() {
		return false
	}
	if resolver.IsFakeIP(addr) {
		return false
	}
	if addr.Is4() {
		for _, prefix := range specialHostIPv4Prefixes {
			if prefix.Contains(addr) {
				return false
			}
		}
		return addr.IsGlobalUnicast()
	}
	if ipv6DocPrefix.Contains(addr) {
		return false
	}
	return addr.IsGlobalUnicast()
}

func selectPreferredPublicAddr(addrs []netip.Addr) (netip.Addr, bool) {
	var fallbackV6 netip.Addr
	for _, raw := range addrs {
		addr := raw.Unmap()
		if !isPublicRoutableAddr(addr) {
			continue
		}
		if addr.Is4() {
			return addr, true
		}
		if !fallbackV6.IsValid() {
			fallbackV6 = addr
		}
	}
	if fallbackV6.IsValid() {
		return fallbackV6, true
	}
	return netip.Addr{}, false
}

func isBogonOrLocalHost(host string) bool {
	trimmed := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	if trimmed == "" || trimmed == "localhost" {
		return true
	}
	for _, suffix := range []string{".invalid", ".example", ".local", ".lan", ".test"} {
		if strings.HasSuffix(trimmed, suffix) {
			return true
		}
	}
	return !strings.Contains(trimmed, ".")
}

func normalizeCountryTarget(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") && len(trimmed) > 2 {
		trimmed = trimmed[1 : len(trimmed)-1]
	}
	return strings.TrimSpace(trimmed)
}

func ensureMMDBReady() bool {
	if mmdbReady.Load() {
		return true
	}
	if !isInit.Load() {
		return false
	}
	catalogPathMu.RLock()
	mmdbPath := constant.Path.MMDB()
	catalogPathMu.RUnlock()
	if mmdbPath == "" {
		return false
	}
	if info, err := os.Stat(mmdbPath); err != nil || info.IsDir() {
		return false
	}
	mmdbReady.Store(true)
	return true
}

func lookupCoreMMDBCodes(addr netip.Addr) []string {
	if !ensureMMDBReady() {
		return nil
	}
	addr = addr.Unmap()
	ip := net.IP(addr.AsSlice())
	mmdbMu.RLock()
	codes := mmdb.IPInstance().LookupCode(ip)
	mmdbMu.RUnlock()
	return codes
}

func lookupCorePublicHostIPs(ctx context.Context, host string) ([]netip.Addr, error) {
	if node, ok := resolver.DefaultHosts.Search(host, false); ok {
		if preferred, found := selectPreferredPublicAddr(node.IPs); found {
			return []netip.Addr{preferred}, nil
		}
	}

	candidates := [4]resolver.Resolver{
		resolver.ProxyServerHostResolver,
		resolver.DefaultResolver,
		resolver.DirectHostResolver,
		resolver.SystemResolver,
	}
	tried := make([]resolver.Resolver, 0, len(candidates))
	for _, r := range candidates {
		// In mihomo/dns, r.Invalid() returns len(r.main) > 0, i.e. true means configured.
		if r == nil || !r.Invalid() {
			continue
		}
		alreadyTried := false
		for _, prev := range tried {
			if prev == r {
				alreadyTried = true
				break
			}
		}
		if alreadyTried {
			continue
		}
		tried = append(tried, r)

		if v4s, err := r.LookupIPv4(ctx, host); err == nil {
			if preferred, found := selectPreferredPublicAddr(v4s); found {
				return []netip.Addr{preferred}, nil
			}
		}
		if v6s, err := r.LookupIPv6(ctx, host); err == nil {
			if preferred, found := selectPreferredPublicAddr(v6s); found {
				return []netip.Addr{preferred}, nil
			}
		}
	}

	if !resolver.FakeIPEnabled() {
		if addrs, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host); err == nil {
			if preferred, found := selectPreferredPublicAddr(addrs); found {
				return []netip.Addr{preferred}, nil
			}
		}
	}
	return nil, resolver.ErrIPNotFound
}

func resolveCountryCodeWithDeps(
	ctx context.Context,
	rawInput string,
	findHostByFakeIP func(netip.Addr) (string, bool),
	lookupHostIPs func(context.Context, string) ([]netip.Addr, error),
	lookupMMDBCodes func(netip.Addr) []string,
) string {
	target := normalizeCountryTarget(rawInput)
	if target == "" {
		return ""
	}
	if addr, err := netip.ParseAddr(target); err == nil {
		addr = addr.Unmap()
		if findHostByFakeIP != nil {
			if mappedHost, ok := findHostByFakeIP(addr); ok && mappedHost != "" {
				return resolveCountryCodeWithDeps(
					ctx,
					mappedHost,
					nil,
					lookupHostIPs,
					lookupMMDBCodes,
				)
			}
		}
		if !isPublicRoutableAddr(addr) || lookupMMDBCodes == nil {
			return ""
		}
		return pickIsoCountryCode(lookupMMDBCodes(addr))
	}

	host := strings.TrimSuffix(strings.ToLower(target), ".")
	if isBogonOrLocalHost(host) || lookupHostIPs == nil || lookupMMDBCodes == nil {
		return ""
	}
	addrs, err := lookupHostIPs(ctx, host)
	if err != nil || len(addrs) == 0 {
		return ""
	}
	preferred, ok := selectPreferredPublicAddr(addrs)
	if !ok {
		return ""
	}
	return pickIsoCountryCode(lookupMMDBCodes(preferred))
}

func resolveCountryCode(rawInput string) string {
	ctx, cancel := context.WithTimeout(context.Background(), countryLookupTimeout)
	defer cancel()
	return resolveCountryCodeWithDeps(
		ctx,
		rawInput,
		resolver.FindHostByIP,
		lookupCorePublicHostIPs,
		lookupCoreMMDBCodes,
	)
}
