package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"sync/atomic"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/tunnel"
)

// A strict-only route resolves the dynamic group exactly once per dial, then
// calls the pinned protocol adapter. Calling the group again after validation
// would race selector/fallback/provider changes and could silently select DIRECT.
type strictProxyRoute struct {
	C.Proxy
	alias string
	username string
	listenerName string
	closed atomic.Bool
}

func strictProxyAlias(generation uint64, target string) string {
	digest := sha256.Sum256([]byte(target))
	return fmt.Sprintf("flclashx-strict-route-%d-%s", generation, hex.EncodeToString(digest[:16]))
}
// Alias is only the registry key; diagnostics and connection chains retain the user group.
func (p *strictProxyRoute) Name() string { return p.Proxy.Name() }
func (p *strictProxyRoute) Adapter() C.ProxyAdapter { return p }
func (p *strictProxyRoute) Unwrap(_ *C.Metadata, _ bool) C.Proxy { return nil }
func (p *strictProxyRoute) Close() error { p.closed.Store(true); return nil }

func (p *strictProxyRoute) leaf(metadata *C.Metadata) (C.Proxy, error) {
	if p.closed.Load() || metadata == nil || metadata.SpecialProxy != p.alias ||
		metadata.InUser != p.username || !metadata.SrcIP.IsLoopback() ||
		(metadata.InName != p.listenerName && metadata.InName != "flclashx-strict-udp") {
		return nil, errors.New("strict proxy route requires its authenticated generation ingress")
	}
	candidate := p.Proxy
	// Group recursion is bounded; cycles and new unsupported adapter classes
	// are denied without ever invoking a potentially direct dial operation.
	seen := make(map[string]bool)
	for depth := 0; depth < 32 && candidate != nil; depth++ {
		if seen[candidate.Name()] { return nil, errors.New("strict proxy group contains a cycle") }
		seen[candidate.Name()] = true
		switch candidate.Type() {
		case C.Selector, C.Fallback, C.URLTest, C.LoadBalance:
			candidate = candidate.Unwrap(metadata, true)
			continue
		case C.Shadowsocks, C.ShadowsocksR, C.Snell, C.Socks5, C.Http,
			C.Vmess, C.Vless, C.Trojan, C.Hysteria, C.Hysteria2, C.WireGuard,
			C.Tuic, C.Ssh, C.Mieru, C.AnyTLS, C.Sudoku, C.Masque,
			C.TrustTunnel, C.OpenVPN, C.Tailscale, C.GostRelay:
			return candidate, nil
		default:
			return nil, errors.New("strict PROXY selection resolved to a non-proxy exit")
		}
	}
	return nil, errors.New("strict proxy group is unavailable or exceeds its recursion limit")
}
func (p *strictProxyRoute) DialContext(ctx context.Context, metadata *C.Metadata) (C.Conn, error) {
	leaf, err := p.leaf(metadata)
	if err != nil { return nil, err }
	// Use this exact leaf object, never a mutable group or a name lookup.
	conn, err := leaf.DialContext(ctx, metadata)
	if err != nil { return nil, err }
	if p.closed.Load() { _ = conn.Close(); return nil, errors.New("strict proxy generation was revoked") }
	conn.AppendToChains(p.Proxy)
	return conn, nil
}
func (p *strictProxyRoute) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	leaf, err := p.leaf(metadata)
	if err != nil { return nil, err }
	if !leaf.SupportUDP() { return nil, errors.New("strict selected proxy does not support UDP") }
	conn, err := leaf.ListenPacketContext(ctx, metadata)
	if err != nil { return nil, err }
	if p.closed.Load() { _ = conn.Close(); return nil, errors.New("strict proxy generation was revoked") }
	conn.AppendToChains(p.Proxy)
	return conn, nil
}

// Called only under the existing Core configuration lock. UpdateProxies swaps
// an immutable map under Mihomo's config lock; normal proxy objects are retained.
func installStrictProxyRoutes(request *StrictIngressRequest, cfg *config.Config,
	ordered []strictIngressBuildEntry) ([]*strictProxyRoute, error) {
	next := make(map[string]C.Proxy)
	for name, proxy := range tunnel.Proxies() { next[name] = proxy }
	listeners := make(map[string]string)
	for _, entry := range ordered { listeners[entry.TargetGroup] = entry.ListenerName }
	routes := make([]*strictProxyRoute, 0, len(request.Entries))
	for _, entry := range request.Entries {
		alias := strictProxyAlias(request.Generation, entry.TargetGroup)
		if _, exists := next[alias]; exists { return nil, errors.New("strict proxy route name collision") }
		proxy := cfg.Proxies[entry.TargetGroup]
		if proxy == nil { return nil, errors.New("strict proxy group disappeared") }
		route := &strictProxyRoute{Proxy: proxy, alias: alias, username: entry.Username,
			listenerName: listeners[entry.TargetGroup]}
		routes = append(routes, route)
		next[alias] = route
	}
	tunnel.UpdateProxies(next, cfg.Providers)
	return routes, nil
}
func revokeStrictProxyRoutes(routes []*strictProxyRoute) {
	if len(routes) == 0 { return }
	next := make(map[string]C.Proxy)
	for name, proxy := range tunnel.Proxies() { next[name] = proxy }
	for _, route := range routes {
		_ = route.Close()
		// Never remove an unrelated replacement sharing a textual name.
		if next[route.alias] == route { delete(next, route.alias) }
	}
	tunnel.UpdateProxies(next, tunnel.Providers())
}
