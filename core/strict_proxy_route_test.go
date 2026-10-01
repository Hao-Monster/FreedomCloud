package main

import (
	C "github.com/metacubex/mihomo/constant"
	"net/netip"
	"testing"
)

type strictRouteTestProxy struct {
	C.Proxy
	name string
	kind C.AdapterType
	next C.Proxy
}

func (p *strictRouteTestProxy) Name() string                     { return p.name }
func (p *strictRouteTestProxy) Type() C.AdapterType              { return p.kind }
func (p *strictRouteTestProxy) Unwrap(*C.Metadata, bool) C.Proxy { return p.next }
func TestStrictProxyRouteRejectsDirectAndCycles(t *testing.T) {
	leaf := &strictRouteTestProxy{name: "proxy", kind: C.Socks5}
	group := &strictRouteTestProxy{name: "group", kind: C.Selector, next: leaf}
	route := &strictProxyRoute{Proxy: group, alias: "strict-test", username: "secret", listenerName: "listener"}
	metadata := &C.Metadata{SpecialProxy: "strict-test", InUser: "secret", InName: "listener", SrcIP: netip.MustParseAddr("127.0.0.1")}
	selected, err := route.leaf(metadata)
	if err != nil || selected != leaf {
		t.Fatalf("proxy leaf was not selected: %v", err)
	}
	group.next = &strictRouteTestProxy{name: "DIRECT", kind: C.Direct}
	if _, err = route.leaf(metadata); err == nil {
		t.Fatal("strict route admitted DIRECT")
	}
	group.next = group
	if _, err = route.leaf(metadata); err == nil {
		t.Fatal("strict route admitted cyclic group")
	}
}
func TestStrictProxyRouteRequiresAuthenticatedLiveIngress(t *testing.T) {
	route := &strictProxyRoute{Proxy: &strictRouteTestProxy{name: "proxy", kind: C.Socks5}, alias: "strict-test", username: "secret", listenerName: "listener"}
	good := C.Metadata{SpecialProxy: "strict-test", InUser: "secret", InName: "listener", SrcIP: netip.MustParseAddr("127.0.0.1")}
	for _, mutate := range []func(*C.Metadata){
		func(m *C.Metadata) { m.InUser = "wrong" },
		func(m *C.Metadata) { m.SpecialProxy = "other-generation" },
		func(m *C.Metadata) { m.InName = "ordinary" },
		func(m *C.Metadata) { m.SrcIP = netip.MustParseAddr("192.0.2.1") },
	} {
		bad := good
		mutate(&bad)
		if _, err := route.leaf(&bad); err == nil {
			t.Fatal("strict route admitted unauthenticated ingress")
		}
	}
	if _, err := route.leaf(&good); err != nil {
		t.Fatalf("valid ingress rejected: %v", err)
	}
	_ = route.Close()
	if _, err := route.leaf(&good); err == nil {
		t.Fatal("revoked route remained usable")
	}
}
