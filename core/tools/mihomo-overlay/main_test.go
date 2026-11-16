package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckedSourceRejectsTampering(t *testing.T) {
	path := filepath.Join(t.TempDir(), "source.go")
	initial := []byte("package original\n")
	if err := os.WriteFile(path, initial, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := checkedSource(path, digest(initial)); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("package changed\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := checkedSource(path, digest(initial)); err == nil {
		t.Fatal("changed upstream source accepted")
	}
}

const minimalListener = `package listener
import (
	"github.com/metacubex/mihomo/listener/sing_tun"
)
var tunLister *sing_tun.Listener
func GetTunConf() LC.Tun { return LastTunConf }
func ReCreateTun(tunConf LC.Tun, tunnel C.Tunnel) {}
func closeTunListener() {}
func Cleanup() {}
`

func TestPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchListener([]byte(minimalListener))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchListener([]byte(minimalListener))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("patch is nondeterministic: %v", err)
	}
	if !bytes.Contains(first, []byte("fcxCreateTun")) || !bytes.Contains(first, []byte("tunMux.Lock()")) {
		t.Fatal("lifecycle patch missing")
	}
	changed := strings.Replace(minimalListener, "func Cleanup() {}", "", 1)
	if _, err := patchListener([]byte(changed)); err == nil {
		t.Fatal("missing upstream function accepted")
	}
}

const minimalDNSDoH = `package dns
type dnsOverHTTPS struct {
	client   *http.Client
	clientMu sync.Mutex
}
func (doh *dnsOverHTTPS) ExchangeContext(ctx context.Context, m *D.Msg) (msg *D.Msg, err error) {}
func (doh *dnsOverHTTPS) resetClient(ctx context.Context, resetErr error) (client *http.Client, err error) {}
func (doh *dnsOverHTTPS) getClient(ctx context.Context) (c *http.Client, isCached bool, err error) {}
func (doh *dnsOverHTTPS) ResetConnection() { originalReset() }
`

func TestDNSPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchDNSDoH([]byte(minimalDNSDoH))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchDNSDoH([]byte(minimalDNSDoH))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("DoH patch is nondeterministic: %v", err)
	}
	for _, required := range []string{"failedClient *http.Client", "ctx.Err()", "doh.fcxHealth.adopt(nil)", "doh.resetQUICConfig()", "fcxHealth fcxDoHHealth", "fcxNoteCallerTimeout"} {
		if !bytes.Contains(first, []byte(required)) {
			t.Fatalf("DoH recovery patch lost %q", required)
		}
	}
	if bytes.Contains(first, []byte("originalReset()")) {
		t.Fatal("DoH ResetConnection was not patched")
	}
	for name, source := range map[string]string{
		"missing":        strings.Replace(minimalDNSDoH, " getClient(", " removedClient(", 1),
		"other receiver": strings.Replace(minimalDNSDoH, "*dnsOverHTTPS", "*otherClient", 1),
		"value receiver": strings.Replace(minimalDNSDoH, "*dnsOverHTTPS", "dnsOverHTTPS", 1),
		"not a method":   strings.Replace(minimalDNSDoH, "(doh *dnsOverHTTPS) ", "", 1),
		"duplicate":      minimalDNSDoH + "\nfunc (doh *dnsOverHTTPS) getClient() {}\n",
		"invalid syntax": "package dns\nfunc (",
		"no struct":      strings.Replace(minimalDNSDoH, "type dnsOverHTTPS struct", "type otherClient struct", 1),
		"two structs":    minimalDNSDoH + "\ntype dnsOverHTTPS struct{}\n",
		"not a struct":   strings.Replace(minimalDNSDoH, "type dnsOverHTTPS struct {\n\tclient   *http.Client\n\tclientMu sync.Mutex\n}", "type dnsOverHTTPS int", 1),
		"already patched": strings.Replace(minimalDNSDoH, "clientMu sync.Mutex\n", "clientMu sync.Mutex\n\tfcxHealth int\n", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchDNSDoH([]byte(source)); err == nil {
				t.Fatal("changed upstream DoH shape accepted")
			}
		})
	}
}

func TestProvenanceDigestIgnoresMapOrderAndDetectsAnyFileChange(t *testing.T) {
	left := map[string]string{"b": digest([]byte("b")), "a": digest([]byte("a"))}
	right := map[string]string{"a": digest([]byte("a")), "b": digest([]byte("b"))}
	if aggregateHashes(left) != aggregateHashes(right) {
		t.Fatal("manifest ordering affects digest")
	}
	right["b"] = digest([]byte("tampered"))
	if aggregateHashes(left) == aggregateHashes(right) {
		t.Fatal("manifest missed changed file")
	}
}

func TestModuleCopyDoesNotModifySourceOrReuseOldFiles(t *testing.T) {
	source, target := t.TempDir(), t.TempDir()
	if err := os.WriteFile(filepath.Join(source, "module.go"), []byte("original"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := copyModule(source, target); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "module.go"), []byte("modified"), 0600); err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(filepath.Join(source, "module.go"))
	if err != nil || string(contents) != "original" {
		t.Fatalf("module source changed: %q %v", contents, err)
	}
	fresh := t.TempDir()
	if err := copyModule(source, fresh); err != nil {
		t.Fatal(err)
	}
	hashes, err := treeHashes(fresh)
	if err != nil || hashes["module.go"] != digest([]byte("original")) {
		t.Fatal("fresh copy inherited altered output")
	}
}

func TestContentAddressedPublicationRejectsInjectedFilesAndRetainsEvidence(t *testing.T) {
	root := t.TempDir()
	staging, destination := filepath.Join(root, "staging"), filepath.Join(root, "published")
	if err := os.Mkdir(staging, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staging, "legitimate.go"), []byte("original"), 0600); err != nil {
		t.Fatal(err)
	}
	expected, err := treeHashes(staging)
	if err != nil {
		t.Fatal(err)
	}
	if err := publishModuleCopy(staging, destination, expected); err != nil {
		t.Fatal(err)
	}
	if err := publishModuleCopy(staging, destination, expected); err != nil {
		t.Fatal("identical source tree rejected:", err)
	}
	injected := filepath.Join(destination, "injected.go")
	if err := os.WriteFile(injected, []byte("unexpected"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := publishModuleCopy(staging, destination, expected); err == nil {
		t.Fatal("extra build input accepted")
	}
	if contents, err := os.ReadFile(injected); err != nil || string(contents) != "unexpected" {
		t.Fatal("untrusted existing source was changed or deleted")
	}
}

const minimalIface = `package iface

import (
	"net"
	"net/netip"
	"time"

	"github.com/metacubex/mihomo/common/singledo"
	"github.com/metacubex/mihomo/component/iface/anet"

	"github.com/metacubex/bart"
)

type ifaceCache struct {
	ifMapByName map[string]*Interface
	ifMapByAddr map[netip.Addr]*Interface
	ifTable     bart.Table[*Interface]
}

var caches = singledo.NewSingle[*ifaceCache](time.Second * 20)

func getCache() (*ifaceCache, error) {
	value, err, _ := caches.Do(func() (*ifaceCache, error) {
		_, _ = anet.Interfaces()
		var dummy net.Flags
		_ = dummy
		return nil, nil
	})
	return value, err
}
`

func TestIfacePatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchIface([]byte(minimalIface))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchIface([]byte(minimalIface))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("iface patch is nondeterministic: %v", err)
	}
	if !bytes.Contains(first, []byte("fcxBuildIfaceCache()")) {
		t.Fatal("iface patch missing fcxBuildIfaceCache call")
	}
	if bytes.Contains(first, []byte("component/iface/anet")) {
		t.Fatal("iface patch retained unused anet import")
	}
	for name, source := range map[string]string{
		"missing getCache":   strings.Replace(minimalIface, "func getCache()", "func otherCache()", 1),
		"duplicate getCache": minimalIface + "\nfunc getCache() (*ifaceCache, error) { return nil, nil }\n",
		"missing anet":       strings.Replace(minimalIface, "\t\"github.com/metacubex/mihomo/component/iface/anet\"\n", "", 1),
		"invalid syntax":     "package iface\nfunc (",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchIface([]byte(source)); err == nil {
				t.Fatal("changed upstream iface shape accepted")
			}
		})
	}
}

const minimalSingTunServer = `package sing_tun

func New() (l *Listener, err error) {
	if options.AutoRoute || options.AutoDetectInterface { // don't start NetworkUpdateMonitor because netlink banned by google on Android14+
		networkUpdateMonitor, err = tun.NewNetworkUpdateMonitor(log.SingLogger)
		if err != nil {
			err = E.Cause(err, "create NetworkUpdateMonitor")
			return
		}
		l.networkUpdateMonitor = networkUpdateMonitor
		err = networkUpdateMonitor.Start()
		if err != nil {
			err = E.Cause(err, "start NetworkUpdateMonitor")
			return
		}

		overrideAndroidVPN := true
		if disable, _ := strconv.ParseBool(os.Getenv("DISABLE_OVERRIDE_ANDROID_VPN")); disable {
			overrideAndroidVPN = false
		}
		defaultInterfaceMonitor, err = tun.NewDefaultInterfaceMonitor(networkUpdateMonitor, log.SingLogger, tun.DefaultInterfaceMonitorOptions{InterfaceFinder: interfaceFinder, OverrideAndroidVPN: overrideAndroidVPN})
		if err != nil {
			err = E.Cause(err, "create DefaultInterfaceMonitor")
			return
		}
		l.defaultInterfaceMonitor = defaultInterfaceMonitor
		defaultInterfaceMonitor.RegisterCallback(func(defaultInterface *control.Interface, event int) {
			if defaultInterface != nil {
				log.Warnln("[TUN] default interface changed by monitor, => %s", defaultInterface.Name)
			} else {
				log.Errorln("[TUN] default interface lost by monitor")
			}
			iface.FlushCache()
			resolver.ResetConnection() // reset resolver's connection after default interface changed
		})
		err = defaultInterfaceMonitor.Start()
		if err != nil {
			err = E.Cause(err, "start DefaultInterfaceMonitor")
			return
		}
	}
	tunIf, err := tunNew(tunOptions)
	if err != nil {
		err = E.Cause(err, "configure tun interface")
		return
	}
	tunStack, err := tun.NewStack(strings.ToLower(options.Stack.String()), stackOptions)
	if err != nil {
		return
	}

	err = tunStack.Start()
	if err != nil {
		return
	}
	return l, nil
}
`

func TestSingTunServerPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchSingTunServer([]byte(minimalSingTunServer))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchSingTunServer([]byte(minimalSingTunServer))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("sing_tun server patch is nondeterministic: %v", err)
	}
	patched := string(first)
	startIdx := strings.Index(patched, "err = defaultInterfaceMonitor.Start()")
	registerIdx := strings.Index(patched, "defaultInterfaceMonitor.RegisterCallback(")
	if startIdx < 0 || registerIdx < 0 || startIdx > registerIdx {
		t.Fatalf("defaultInterfaceMonitor.Start must precede RegisterCallback: start=%d register=%d", startIdx, registerIdx)
	}
	for _, stage := range []string{"sing_tun.monitors", "sing_tun.device", "sing_tun.stack"} {
		if !strings.Contains(patched, stage) {
			t.Fatalf("missing timing stage %q", stage)
		}
	}
	for name, source := range map[string]string{
		"missing monitor block": strings.Replace(minimalSingTunServer, "defaultInterfaceMonitor.RegisterCallback(", "otherRegisterCallback(", 1),
		"missing tunNew":        strings.Replace(minimalSingTunServer, "tunIf, err := tunNew(tunOptions)", "tunIf, err := otherTunNew(tunOptions)", 1),
		"missing tunStack":      strings.Replace(minimalSingTunServer, "err = tunStack.Start()", "err = otherStackStart()", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchSingTunServer([]byte(source)); err == nil {
				t.Fatal("changed upstream sing_tun server shape accepted")
			}
		})
	}
}

const minimalSingTunWindows = `package tun

func New(options Options) (WinTun, error) {
	if options.FileDescriptor != 0 {
		return nil, os.ErrInvalid
	}
	adapter, err := wintun.CreateAdapter(options.Name, TunnelType, generateGUIDByDeviceName(options.Name))
	if err != nil {
		if !errors.Is(err, os.ErrExist) {
			return nil, err
		}
		createErr := err
		adapter, err = wintun.OpenAdapter(options.Name)
		if err != nil {
			return nil, E.Errors(E.Cause(createErr, "create adapter"), E.Cause(err, "open existing adapter"))
		}
	}
	nativeTun := &NativeTun{
		adapter: adapter,
		options: options,
	}
	session, err := adapter.StartSession(0x800000)
	if err != nil {
		return nil, err
	}
	nativeTun.session = session
	nativeTun.readWait = session.ReadWaitEvent()
	err = nativeTun.configure()
	if err != nil {
		session.End()
		adapter.Close()
		return nil, err
	}
	return nativeTun, nil
}

func (t *NativeTun) configure() error {
	luid := winipcfg.LUID(t.adapter.LUID())
	if len(t.options.Inet4Address) > 0 {
		err := luid.SetIPAddressesForFamily(winipcfg.AddressFamily(windows.AF_INET), t.options.Inet4Address)
		if err != nil {
			return E.Cause(err, "set ipv4 address")
		}
		if t.options.AutoRoute && !t.options.EXP_DisableDNSHijack {
			dnsServers := common.Filter(t.options.DNSServers, netip.Addr.Is4)
			if len(dnsServers) == 0 && HasNextAddress(t.options.Inet4Address[0], 1) {
				dnsServers = []netip.Addr{t.options.Inet4Address[0].Addr().Next()}
			}
			if len(dnsServers) > 0 {
				err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET), dnsServers, nil)
				if err != nil {
					return E.Cause(err, "set ipv4 dns")
				}
			}
		} else {
			err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET), nil, nil)
			if err != nil {
				return E.Cause(err, "set ipv4 dns")
			}
		}
	}
	if len(t.options.Inet6Address) > 0 {
		err := luid.SetIPAddressesForFamily(winipcfg.AddressFamily(windows.AF_INET6), t.options.Inet6Address)
		if err != nil {
			return E.Cause(err, "set ipv6 address")
		}
		if t.options.AutoRoute && !t.options.EXP_DisableDNSHijack {
			dnsServers := common.Filter(t.options.DNSServers, netip.Addr.Is6)
			if len(dnsServers) == 0 && HasNextAddress(t.options.Inet6Address[0], 1) {
				dnsServers = []netip.Addr{t.options.Inet6Address[0].Addr().Next()}
			}
			if len(dnsServers) > 0 {
				err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET6), dnsServers, nil)
				if err != nil {
					return E.Cause(err, "set ipv6 dns")
				}
			}
		} else {
			err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET6), nil, nil)
			if err != nil {
				return E.Cause(err, "set ipv6 dns")
			}
		}
	}
	if len(t.options.Inet4Address) > 0 || len(t.options.Inet6Address) > 0 {
		_ = luid.DisableDNSRegistration()
	}
	if t.options.AutoRoute {
		gateway4, gateway6 := t.options.Inet4GatewayAddr(), t.options.Inet6GatewayAddr()
		routeRanges, err := t.options.BuildAutoRouteRanges(false)
		if err != nil {
			return err
		}
		for _, routeRange := range routeRanges {
			if routeRange.Addr().Is4() {
				err = luid.AddRoute(routeRange, gateway4, 0)
			} else {
				err = luid.AddRoute(routeRange, gateway6, 0)
			}
		}
		if err != nil {
			return err
		}
		err = windnsapi.FlushResolverCache()
		if err != nil {
			return err
		}
	}
	if len(t.options.Inet4Address) > 0 {
		inetIf, err := luid.IPInterface(winipcfg.AddressFamily(windows.AF_INET))
		if err != nil {
			return err
		}
		err = inetIf.Set()
		if err != nil {
			return E.Cause(err, "set ipv4 options")
		}
	}
	if len(t.options.Inet6Address) > 0 {
		inet6If, err := luid.IPInterface(winipcfg.AddressFamily(windows.AF_INET6))
		if err != nil {
			return err
		}
		err = inet6If.Set()
		if err != nil {
			return E.Cause(err, "set ipv6 options")
		}
	}

	if t.options.AutoRoute && t.options.StrictRoute {
		if err := configureStrictWFP(); err != nil {
			return err
		}
	}

	return nil
}
`

func TestSingTunWindowsPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchSingTunWindows([]byte(minimalSingTunWindows))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchSingTunWindows([]byte(strings.ReplaceAll(minimalSingTunWindows, "\n", "\r\n")))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("sing-tun windows patch is nondeterministic across LF/CRLF: %v", err)
	}
	patched := string(first)
	for _, stage := range []string{
		"sing_tun.device.wintun_create",
		"tun.wintun_create_adapter",
		"tun.wintun_open_adapter",
		"tun.route_ranges_build",
		"tun.ipv4_interface_lookup",
		"tun.ipv6_interface_lookup",
		"sing_tun.device.session_start",
		"sing_tun.device.ip_dns_config",
		"sing_tun.device.route_config",
		"sing_tun.device.strict_route",
		"tun.ipv4_address_set",
		"tun.ipv4_dns_set",
		"tun.ipv6_address_set",
		"tun.ipv6_dns_set",
		"tun.disable_dns_registration",
		"tun.routes_add",
		"tun.dns_cache_flush",
		"tun.ipv4_interface_set",
		"tun.ipv6_interface_set",
	} {
		if !strings.Contains(patched, stage) {
			t.Fatalf("missing sing-tun windows sub-stage %q", stage)
		}
	}
	if !strings.Contains(patched, "session.End()") || !strings.Contains(patched, "adapter.Close()") {
		t.Fatal("lost session/adapter cleanup on configure failure")
	}
	if !strings.Contains(patched, "FCXAddAutoRoutes(routeRanges, gateway4, gateway6, luid.AddRoute,") {
		t.Fatal("missing FCXAddAutoRoutes replacement for routeRanges loop")
	}
	if strings.Contains(patched, "for _, routeRange := range routeRanges") {
		t.Fatal("retained upstream error-swallowing routeRanges loop")
	}
	if count := strings.Count(patched, "return nil, FCXWrapAdapterCreateError(err)"); count != 2 {
		t.Fatalf("adapter create/open failures must be typed on both return paths, got %d", count)
	}
	for name, source := range map[string]string{
		"missing CreateAdapter": strings.Replace(minimalSingTunWindows, "wintun.CreateAdapter(", "wintun.OtherCreate(", 1),
		"missing StartSession":  strings.Replace(minimalSingTunWindows, "adapter.StartSession(0x800000)", "adapter.OtherSession()", 1),
		"missing ipv4 address":  strings.Replace(minimalSingTunWindows, `return E.Cause(err, "set ipv4 address")`, `return err`, 1),
		"missing ipv6 address":  strings.Replace(minimalSingTunWindows, `return E.Cause(err, "set ipv6 address")`, `return err`, 1),
		"missing DisableDNS":    strings.Replace(minimalSingTunWindows, "_ = luid.DisableDNSRegistration()", "_ = luid.OtherDNS()", 1),
		"missing RouteLoop":     strings.Replace(minimalSingTunWindows, "err = luid.AddRoute(routeRange, gateway4, 0)", "err = luid.OtherAddRoute(routeRange)", 1),
		"missing FlushDNS":      strings.Replace(minimalSingTunWindows, "err = windnsapi.FlushResolverCache()", "err = windnsapi.OtherFlush()", 1),
		"missing ipv4 options":  strings.Replace(minimalSingTunWindows, `return E.Cause(err, "set ipv4 options")`, `return err`, 1),
		"missing ipv6 options":  strings.Replace(minimalSingTunWindows, `return E.Cause(err, "set ipv6 options")`, `return err`, 1),
		"missing StrictRoute":   strings.Replace(minimalSingTunWindows, "if t.options.AutoRoute && t.options.StrictRoute {", "if t.options.StrictRoute {", 1),
		"invalid syntax":        "package tun\nfunc (",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchSingTunWindows([]byte(source)); err == nil {
				t.Fatal("changed upstream sing-tun windows shape accepted")
			}
		})
	}
}

const minimalSingTunStackGvisor = `//go:build with_gvisor

package tun

func NewGVisorStackWithOptions(ep stack.LinkEndpoint, opts stack.NICOptions) (*stack.Stack, error) {
	ipStack.SetSpoofing(DefaultNIC, true)
	ipStack.SetPromiscuousMode(DefaultNIC, true)
	bufSize := 20 * 1024
	ipStack.SetTransportProtocolOption(tcp.ProtocolNumber, &tcpip.TCPReceiveBufferSizeRangeOption{
		Min:     1,
		Default: bufSize,
		Max:     bufSize,
	})
	ipStack.SetTransportProtocolOption(tcp.ProtocolNumber, &tcpip.TCPSendBufferSizeRangeOption{
		Min:     1,
		Default: bufSize,
		Max:     bufSize,
	})
	sOpt := tcpip.TCPSACKEnabled(true)
	return ipStack, nil
}
`

func TestSingTunStackGvisorPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchSingTunStackGvisor([]byte(minimalSingTunStackGvisor))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchSingTunStackGvisor([]byte(minimalSingTunStackGvisor))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("sing-tun stack_gvisor patch is nondeterministic: %v", err)
	}
	patched := string(first)
	for _, want := range []string{"4 * 1024", "256 * 1024", "4 * 1024 * 1024"} {
		if !strings.Contains(patched, want) {
			t.Fatalf("patched stack_gvisor missing %q", want)
		}
	}
	if strings.Contains(patched, "20 * 1024") {
		t.Fatal("patched stack_gvisor retained 20 KiB cap")
	}
	mutated := strings.Replace(minimalSingTunStackGvisor, "bufSize := 20 * 1024", "bufSize := 32 * 1024", 1)
	if _, err := patchSingTunStackGvisor([]byte(mutated)); err == nil {
		t.Fatal("changed upstream stack_gvisor shape accepted")
	}
}

const minimalMemConservative = `package memconservative

import (
	"errors"
	"fmt"
	"runtime"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/geodata/router"
)

type memConservativeLoader struct{}

func (m *memConservativeLoader) LoadIPByPath(filename, country string) ([]*router.CIDR, error) {
	defer runtime.GC()
	return nil, fmt.Errorf("failed: %s", filename)
}

func (m *memConservativeLoader) LoadSiteByPath(filename, list string) ([]*router.Domain, error) {
	defer runtime.GC()
	return nil, errors.New("unsupported")
}
`

const minimalConfigGeoCleanup = `package config

func ParseRawConfig(rawCfg *RawConfig) (*Config, error) {
	rollback := temporaryUpdateGeneral(config.General)
	defer rollback()
	return config, nil
}
`

func TestMemConservativeAndConfigGeoCleanupPatchesAreDeterministic(t *testing.T) {
	patchedMemc, err := patchMemConservative([]byte(minimalMemConservative))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(patchedMemc, []byte("runtime.GC()")) || bytes.Contains(patchedMemc, []byte(`"runtime"`)) {
		t.Fatal("memconservative patch retained per-rule runtime.GC()")
	}
	if _, err := patchMemConservative([]byte(strings.Replace(minimalMemConservative, "defer runtime.GC()", "", 1))); err == nil {
		t.Fatal("changed memconservative shape accepted")
	}

	patchedCfg, err := patchConfigGeoCleanup([]byte(minimalConfigGeoCleanup))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"geodata.ClearGeoSiteCache()", "geodata.ClearGeoIPCache()"} {
		if !bytes.Contains(patchedCfg, []byte(want)) {
			t.Fatalf("config geo cleanup patch missing %q", want)
		}
	}
	if _, err := patchConfigGeoCleanup([]byte("package config\nfunc Other() {}\n")); err == nil {
		t.Fatal("changed config ParseRawConfig shape accepted")
	}
}

const minimalCacheFile = `package cachefile

type CacheFile struct {
	DB *bbolt.DB
}

func (c *CacheFile) Close() error {
	return c.DB.Close()
}
`

const minimalFakeIp = `package cachefile

import (
	"net/netip"

	"github.com/metacubex/mihomo/log"

	"github.com/metacubex/bbolt"
)

type FakeIpStore struct {
	*CacheFile
	bucketName []byte
}

func (c *FakeIpStore) GetByHost(host string) (ip netip.Addr, exist bool) { return }
func (c *FakeIpStore) PutByHost(host string, ip netip.Addr) { _ = log.Warnln; var _ *bbolt.Tx }
func (c *FakeIpStore) GetByIP(ip netip.Addr) (host string, exist bool) { return }
func (c *FakeIpStore) PutByIP(ip netip.Addr, host string) {}
func (c *FakeIpStore) DelByIP(ip netip.Addr) {}
func (c *FakeIpStore) FlushFakeIP() error { return nil }
`

func TestFakeIpCachePatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	firstCache, err := patchCacheFile([]byte(minimalCacheFile))
	if err != nil {
		t.Fatal(err)
	}
	secondCache, err := patchCacheFile([]byte(minimalCacheFile))
	if err != nil || !bytes.Equal(firstCache, secondCache) {
		t.Fatalf("cache.go patch is nondeterministic: %v", err)
	}
	if !bytes.Contains(firstCache, []byte("fcxCloseFakeIPCache(c.DB)")) {
		t.Fatal("cache.go patch missing fcxCloseFakeIPCache(c.DB)")
	}
	if _, err := patchCacheFile([]byte("package cachefile\nfunc Other() {}\n")); err == nil {
		t.Fatal("changed cache.go shape accepted")
	}

	firstFake, err := patchFakeIpStore([]byte(minimalFakeIp))
	if err != nil {
		t.Fatal(err)
	}
	secondFake, err := patchFakeIpStore([]byte(minimalFakeIp))
	if err != nil || !bytes.Equal(firstFake, secondFake) {
		t.Fatalf("fakeip.go patch is nondeterministic: %v", err)
	}
	for _, want := range []string{"fcxGetByHost", "fcxPutByHost", "fcxGetByIP", "fcxPutByIP", "fcxDelByIP", "fcxFlushFakeIP"} {
		if !bytes.Contains(firstFake, []byte(want)) {
			t.Fatalf("fakeip.go patch missing %q", want)
		}
	}
	if _, err := patchFakeIpStore([]byte(strings.Replace(minimalFakeIp, "FlushFakeIP()", "OtherFlush()", 1))); err == nil {
		t.Fatal("changed fakeip.go shape accepted")
	}
}

const minimalProcessWindows = `package process

func findProcessName(network string, ip netip.Addr, srcPort int) (uint32, string, error) {
	buf, err := getTransportTable(fn, family, class)
	if err != nil {
		return 0, "", err
	}
	s := newSearcher(family == windows.AF_INET, network == TCP)
	pid, err := s.Search(buf, ip, uint16(srcPort))
	if err != nil {
		return 0, "", err
	}
	pp, err := getExecPathFromPID(pid)
	return 0, pp, err
}

func getTransportTable(fn uintptr, family int, class int) ([]byte, error) {
	return nil, nil
}

func getExecPathFromPID(pid uint32) (string, error) {
	return "", nil
}
`

func TestProcessWindowsPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchProcessWindows([]byte(minimalProcessWindows))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchProcessWindows([]byte(minimalProcessWindows))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("process_windows.go patch is nondeterministic: %v", err)
	}
	for _, want := range []string{"fcxAcquireTransportTable", "fcxGetExecPathFromPID"} {
		if !bytes.Contains(first, []byte(want)) {
			t.Fatalf("process_windows.go patch missing %q", want)
		}
	}
	if _, err := patchProcessWindows([]byte(strings.Replace(minimalProcessWindows, "getExecPathFromPID", "otherExecPath", 1))); err == nil {
		t.Fatal("changed process_windows.go shape accepted")
	}
}

const minimalFetcher = `package resource

type Fetcher[V any] struct{}

func (f *Fetcher[V]) UpdatedAt() time.Time {
	return f.updatedAt
}

func (f *Fetcher[V]) Initial() (V, error) {
	if local {
		f.updatedAt = modTime
	}
	if bundle {
		f.updatedAt = modTime
	}
	contents, _, updateErr := f.Update()
	if updateErr != nil {
		return contents, updateErr
	}
	return contents, nil
}

func (f *Fetcher[V]) Update() (V, bool, error) {
	return f.loadBuf(nil, f.hash, true)
}

func (f *Fetcher[V]) SideUpdate(buf []byte) (V, bool, error) {
	return f.loadBuf(buf, f.hash, true)
}

func (f *Fetcher[V]) pullLoop(forceUpdate bool) {
	initialInterval := f.interval - time.Since(f.updatedAt)
	_ = initialInterval
}
`

const minimalRuleProvider = `package provider

type baseProvider struct {
	behavior P.RuleBehavior
	strategy ruleStrategy
}

func (bp *baseProvider) Count() int {
	return bp.strategy.Count()
}

func (bp *baseProvider) Match(metadata *C.Metadata, helper C.RuleMatchHelper) bool {
	return bp.strategy != nil && bp.strategy.Match(metadata, helper)
}

func (bp *baseProvider) Strategy() any {
	return bp.strategy
}

func (rp *ruleSetProvider) MarshalJSON() ([]byte, error) {
	return json.Marshal(providerForApi{
		RuleCount:   rp.strategy.Count(),
	})
}

func NewRuleSetProvider() {
	onUpdate := func(strategy ruleStrategy) {
		rp.strategy = strategy
	}
	_ = onUpdate
	rp.strategy = newStrategy(behavior, parse)
	if len(payload) > 0 { // using as fallback rules
		rp.strategy = rulesParseInline(payload, rp.strategy)
	}
}

func (i *inlineProvider) MarshalJSON() ([]byte, error) {
	return json.Marshal(providerForApi{
		RuleCount:   i.strategy.Count(),
	})
}

func NewInlineProvider() {
	ip := &inlineProvider{
		baseProvider: baseProvider{
			behavior: behavior,
			strategy: newStrategy(behavior, parse),
		},
		payload:  payload,
		name:     name,
		updateAt: time.Now(),
	}
	ip.strategy = rulesParseInline(payload, ip.strategy)
}
`

const minimalProxyProvider = `package provider

func (pp *proxySetProvider) MarshalJSON() ([]byte, error) {
	return json.Marshal(providerForApi{
		SubscriptionInfo: pp.subscriptionInfo,
	})
}

func (pp *proxySetProvider) Initial() error {
	if subscriptionInfo != "" {
		pp.subscriptionInfo = NewSubscriptionInfo(subscriptionInfo)
	}
	return nil
}

func NewProxySetProvider() {
	if subscriptionInfo != "" {
		pd.subscriptionInfo = NewSubscriptionInfo(subscriptionInfo)
	}
}
`

func TestProviderNonblockingPatchesAreDeterministicAndRejectChangedShape(t *testing.T) {
	firstF, err := patchResourceFetcher([]byte(minimalFetcher))
	if err != nil {
		t.Fatal(err)
	}
	secondF, err := patchResourceFetcher([]byte(minimalFetcher))
	if err != nil || !bytes.Equal(firstF, secondF) {
		t.Fatalf("fetcher.go patch is nondeterministic: %v", err)
	}
	for _, want := range []string{"fcxStartInitialRemotePull", "fcxNotifyProviderUpdated", "currentHash()", "setUpdatedAt(modTime)", "time.Since(f.UpdatedAt())"} {
		if !bytes.Contains(firstF, []byte(want)) {
			t.Fatalf("fetcher.go patch missing %q", want)
		}
	}
	if _, err := patchResourceFetcher([]byte(strings.Replace(minimalFetcher, "SideUpdate", "OtherSideUpdate", 1))); err == nil {
		t.Fatal("changed fetcher.go shape accepted")
	}

	firstR, err := patchRuleProvider([]byte(minimalRuleProvider))
	if err != nil {
		t.Fatal(err)
	}
	secondR, err := patchRuleProvider([]byte(minimalRuleProvider))
	if err != nil || !bytes.Equal(firstR, secondR) {
		t.Fatalf("rules/provider/provider.go patch is nondeterministic: %v", err)
	}
	if !bytes.Contains(firstR, []byte("fcxAtomicRuleStrategy")) || !bytes.Contains(firstR, []byte("bp.strategy.load()")) {
		t.Fatal("rules/provider/provider.go patch missing atomic strategy")
	}
	if _, err := patchRuleProvider([]byte(strings.Replace(minimalRuleProvider, "strategy ruleStrategy", "strategy any", 1))); err == nil {
		t.Fatal("changed rules/provider/provider.go shape accepted")
	}

	firstP, err := patchProxyProvider([]byte(minimalProxyProvider))
	if err != nil {
		t.Fatal(err)
	}
	secondP, err := patchProxyProvider([]byte(minimalProxyProvider))
	if err != nil || !bytes.Equal(firstP, secondP) {
		t.Fatalf("adapter/provider/provider.go patch is nondeterministic: %v", err)
	}
	for _, want := range []string{"pp.getSubscriptionInfo()", "pp.setSubscriptionInfoIfNil(", "pd.setSubscriptionInfo("} {
		if !bytes.Contains(firstP, []byte(want)) {
			t.Fatalf("adapter/provider/provider.go patch missing %q", want)
		}
	}
	if _, err := patchProxyProvider([]byte(strings.Replace(minimalProxyProvider, "SubscriptionInfo: pp.subscriptionInfo,", "", 1))); err == nil {
		t.Fatal("changed adapter/provider/provider.go shape accepted")
	}
}

const minimalSingTunServerWindows = `package sing_tun

import (
	"time"

	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/log"

	tun "github.com/metacubex/sing-tun"
)

func tunNew(options tun.Options) (tunIf tun.Tun, err error) {
	maxRetry := 3
	for i := 0; i < maxRetry; i++ {
		timeBegin := time.Now()
		tunIf, err = tun.New(options)
		if err == nil {
			return
		}
		timeEnd := time.Now()
		if timeEnd.Sub(timeBegin) < 1*time.Second { // retrying for "Cannot create a file when that file already exists."
			return
		}
		log.Warnln("Start Tun interface timeout: %s [retrying %d/%d]", err, i+1, maxRetry)
	}
	return
}

func init() {
	tun.TunnelType = InterfaceName

	if features.WindowsMajorVersion < 10 {
		// to resolve "bind: The requested address is not valid in its context"
		EnforceBindInterface = true
	}
}
`

func TestSingTunServerWindowsPatchStopsRetryingAdapterCreateFailures(t *testing.T) {
	first, err := patchSingTunServerWindows([]byte(minimalSingTunServerWindows))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchSingTunServerWindows([]byte(strings.ReplaceAll(minimalSingTunServerWindows, "\n", "\r\n")))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("server_windows.go patch is nondeterministic across LF/CRLF: %v", err)
	}
	patched := string(first)
	if !strings.Contains(patched, "return fcxTunNewWithRetry(") {
		t.Fatal("tunNew does not delegate to the classified retry policy")
	}
	if !strings.Contains(patched, "Wintun adapter refused by Windows; not retrying") {
		t.Fatal("skipped retries for a refused adapter must be logged")
	}
	if strings.Contains(patched, "maxRetry := 3") {
		t.Fatal("retained upstream unconditional slow-failure retry loop")
	}
	if !strings.Contains(patched, "tun.TunnelType = InterfaceName") || !strings.Contains(patched, "EnforceBindInterface = true") {
		t.Fatal("lost upstream Windows init behaviour")
	}
	for name, source := range map[string]string{
		"missing retry loop": strings.Replace(minimalSingTunServerWindows, "maxRetry := 3", "maxRetry := 5", 1),
		"missing tun.New":    strings.Replace(minimalSingTunServerWindows, "tunIf, err = tun.New(options)", "tunIf, err = other(options)", 1),
		"invalid syntax":     "package sing_tun\nfunc (",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchSingTunServerWindows([]byte(source)); err == nil {
				t.Fatal("changed upstream server_windows.go shape accepted")
			}
		})
	}
}

func TestNetworkSwitchPatchesAreDeterministicAndRejectChangedShapes(t *testing.T) {
	const minimalPolicy = `package dns
type dnsPolicy interface {
	Match(domain string) []dnsClient
}
type domainTriePolicy struct {
	*trie.DomainTrie[[]dnsClient]
}
func (p domainMatcherPolicy) Match(domain string) []dnsClient {
	if p.matcher.MatchDomain(domain) {
		return p.dnsClients
	}
	return nil
}
`
	firstPolicy, err := patchDNSPolicy([]byte(minimalPolicy))
	if err != nil {
		t.Fatal(err)
	}
	secondPolicy, err := patchDNSPolicy([]byte(strings.ReplaceAll(minimalPolicy, "\n", "\r\n")))
	if err != nil || !bytes.Equal(firstPolicy, secondPolicy) {
		t.Fatalf("policy.go patch nondeterministic: %v", err)
	}
	if !bytes.Contains(firstPolicy, []byte("func (p domainTriePolicy) ResetConnection()")) ||
		!bytes.Contains(firstPolicy, []byte("func (p domainMatcherPolicy) ResetConnection()")) {
		t.Fatal("policy.go ResetConnection methods missing")
	}
	if _, err := patchDNSPolicy([]byte(strings.Replace(minimalPolicy, "Match(domain string)", "Other(domain string)", 1))); err == nil {
		t.Fatal("changed policy.go shape accepted")
	}

	const minimalDialerBind = `package dialer

import (
	"net"
	"net/netip"
	"syscall"
)

func bindIfaceToDialer(ifaceName string, dialer *net.Dialer, _ string, destination netip.Addr) error {
	ifaceObj, err := iface.ResolveInterface(ifaceName)
	if err != nil {
		return err
	}

	addControlToDialer(dialer, bindControl(ifaceObj.Index, netip.AddrPortFrom(destination, 0)))
	return nil
}
`
	firstDialer, err := patchDialerBindWindows([]byte(minimalDialerBind))
	if err != nil {
		t.Fatal(err)
	}
	secondDialer, err := patchDialerBindWindows([]byte(strings.ReplaceAll(minimalDialerBind, "\n", "\r\n")))
	if err != nil || !bytes.Equal(firstDialer, secondDialer) {
		t.Fatalf("bind_windows.go patch nondeterministic: %v", err)
	}
	if !bytes.Contains(firstDialer, []byte("LookupLocalAddrFromIfaceName")) || !bytes.Contains(firstDialer, []byte("destination.Unmap()")) {
		t.Fatal("bind_windows.go missing LookupLocalAddrFromIfaceName or destination.Unmap()")
	}
	if _, err := patchDialerBindWindows([]byte(strings.Replace(minimalDialerBind, "addControlToDialer", "otherControl", 1))); err == nil {
		t.Fatal("changed bind_windows.go shape accepted")
	}

	const minimalResolver = `package dns

func (r *Resolver) ClearCache() {
	if r != nil && r.cache != nil {
		r.cache.Clear()
	}
}

func (r *Resolver) ResetConnection() {
	if r != nil {
		for _, c := range r.main {
			c.ResetConnection()
		}
		for _, c := range r.fallback {
			c.ResetConnection()
		}
		if dr := r.defaultResolver; dr != nil {
			dr.ResetConnection()
		}
	}
}

func newResolver() {
	makePolicy := func(policies []Policy) (dnsPolicies []dnsPolicy) {
		var triePolicy *trie.DomainTrie[[]dnsClient]
		insertPolicy := func(policy dnsPolicy) {
			if triePolicy != nil {
				triePolicy.Optimize()
				dnsPolicies = append(dnsPolicies, domainTriePolicy{triePolicy})
				triePolicy = nil
			}
			if policy != nil {
				dnsPolicies = append(dnsPolicies, policy)
			}
		}

		for _, policy := range policies {
			if policy.Matcher != nil {
				insertPolicy(domainMatcherPolicy{matcher: policy.Matcher, dnsClients: cacheTransform(policy.NameServers)})
			} else {
				if triePolicy == nil {
					triePolicy = trie.New[[]dnsClient]()
				}
				if err := triePolicy.Insert(policy.Domain, cacheTransform(policy.NameServers)); err != nil {
					log.Warnln("[DNS] skip invalid nameserver policy: %s", err)
				}
			}
		}
		insertPolicy(nil)
		return
	}
	_ = makePolicy
}
`
	firstResolver, err := patchDNSResolver([]byte(minimalResolver))
	if err != nil {
		t.Fatal(err)
	}
	secondResolver, err := patchDNSResolver([]byte(strings.ReplaceAll(minimalResolver, "\n", "\r\n")))
	if err != nil || !bytes.Equal(firstResolver, secondResolver) {
		t.Fatalf("dns/resolver.go patch nondeterministic: %v", err)
	}
	if !bytes.Contains(firstResolver, []byte("dr.ClearCache()")) || !bytes.Contains(firstResolver, []byte("p.ResetConnection()")) {
		t.Fatal("dns/resolver.go missing defaultResolver.ClearCache() or policy.ResetConnection()")
	}
	if _, err := patchDNSResolver([]byte(strings.Replace(minimalResolver, "r.cache.Clear()", "r.cache.Purge()", 1))); err == nil {
		t.Fatal("changed dns/resolver.go shape accepted")
	}

	const minimalSystemCommon = `package dns

import "time"

func (c *systemClient) ResetConnection() {}
`
	firstSys, err := patchDNSSystemCommon([]byte(minimalSystemCommon))
	if err != nil {
		t.Fatal(err)
	}
	secondSys, err := patchDNSSystemCommon([]byte(strings.ReplaceAll(minimalSystemCommon, "\n", "\r\n")))
	if err != nil || !bytes.Equal(firstSys, secondSys) {
		t.Fatalf("dns/system_common.go patch nondeterministic: %v", err)
	}
	if !bytes.Contains(firstSys, []byte("c.lastFlush = time.Time{}")) {
		t.Fatal("dns/system_common.go missing lastFlush reset")
	}
	if _, err := patchDNSSystemCommon([]byte("package dns\n")); err == nil {
		t.Fatal("changed dns/system_common.go shape accepted")
	}

	const minimalDHCP = `package dns

import "time"

func (d *dhcpClient) ResetConnection() {
	for _, client := range d.clients {
		client.ResetConnection()
	}
}
`
	firstDHCP, err := patchDNSDHCP([]byte(minimalDHCP))
	if err != nil {
		t.Fatal(err)
	}
	secondDHCP, err := patchDNSDHCP([]byte(strings.ReplaceAll(minimalDHCP, "\n", "\r\n")))
	if err != nil || !bytes.Equal(firstDHCP, secondDHCP) {
		t.Fatalf("dns/dhcp.go patch nondeterministic: %v", err)
	}
	if !bytes.Contains(firstDHCP, []byte("d.ifaceInvalidate = time.Time{}")) || !bytes.Contains(firstDHCP, []byte("d.dnsInvalidate = time.Time{}")) {
		t.Fatal("dns/dhcp.go missing TTL invalidation")
	}
	if _, err := patchDNSDHCP([]byte("package dns\n")); err == nil {
		t.Fatal("changed dns/dhcp.go shape accepted")
	}

	const minimalURLTest = `package outboundgroup

import "context"

func (u *URLTest) DialContext(ctx context.Context, metadata *C.Metadata) (c C.Conn, err error) {
	proxy := u.fast(true)
	c, err = proxy.DialContext(ctx, metadata)
	if err == nil {
		c.AppendToChains(u)
	} else {
		u.onDialFailed(proxy.Type(), err, u.healthCheck)
	}

	if N.NeedHandshake(c) {
		c = callback.NewFirstWriteCallBackConn(c, func(err error) {
			if err == nil {
				u.onDialSuccess()
			} else {
				u.onDialFailed(proxy.Type(), err, u.healthCheck)
			}
		})
	}

	return c, err
}

func (u *URLTest) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	proxy := u.fast(true)
	pc, err := proxy.ListenPacketContext(ctx, metadata)
	if err == nil {
		pc.AppendToChains(u)
	} else {
		u.onDialFailed(proxy.Type(), err, u.healthCheck)
	}

	return pc, err
}

func (u *URLTest) fast(touch bool) C.Proxy {
	elm, _, shared := u.fastSingle.Do(func() (C.Proxy, error) {
		proxies := u.GetProxies(touch)
		if u.selected != "" {
			for _, proxy := range proxies {
				if !proxy.AliveForTestUrl(u.testUrl) {
					continue
				}
				if proxy.Name() == u.selected {
					u.fastNode = proxy
					return proxy, nil
				}
			}
		}

		fast := proxies[0]
		minDelay := fast.LastDelayForTestUrl(u.testUrl)
		fastNotExist := true

		for _, proxy := range proxies[1:] {
			if u.fastNode != nil && proxy.Name() == u.fastNode.Name() {
				fastNotExist = false
			}

			if !proxy.AliveForTestUrl(u.testUrl) {
				continue
			}

			delay := proxy.LastDelayForTestUrl(u.testUrl)
			if delay < minDelay {
				fast = proxy
				minDelay = delay
			}

		}
		// tolerance
		if u.fastNode == nil || fastNotExist || !u.fastNode.AliveForTestUrl(u.testUrl) || u.fastNode.LastDelayForTestUrl(u.testUrl) > fast.LastDelayForTestUrl(u.testUrl)+u.tolerance {
			u.fastNode = fast
		}
		return u.fastNode, nil
	})
	_ = shared
	return elm
}

func (u *URLTest) ForceSet(name string) {
	u.selected = name
	u.fastSingle.Reset()
}
`
	firstURLTest, err := patchURLTestGroup([]byte(minimalURLTest))
	if err != nil {
		t.Fatalf("urltest.go patch failed: %v", err)
	}
	secondURLTest, err := patchURLTestGroup([]byte(strings.ReplaceAll(minimalURLTest, "\n", "\r\n")))
	if err != nil || !bytes.Equal(firstURLTest, secondURLTest) {
		t.Fatalf("urltest.go patch nondeterministic: %v", err)
	}
	for _, want := range []string{
		"RecordDialErrorFCX",
		"WrapStableConnFCX",
		"EffectiveDelayFCX",
		"ResetFastCacheFCX",
	} {
		if !bytes.Contains(firstURLTest, []byte(want)) {
			t.Fatalf("urltest.go missing %q:\n%s", want, firstURLTest)
		}
	}
	for name, tampered := range map[string]string{
		"empty":                "package outboundgroup\n",
		"missing DialContext":  strings.Replace(minimalURLTest, "N.NeedHandshake(c)", "false", 1),
		"missing ListenPacket": strings.Replace(minimalURLTest, "proxy.ListenPacketContext", "proxy.DialPacket", 1),
		"missing fast":         strings.Replace(minimalURLTest, "minDelay := fast.LastDelayForTestUrl(u.testUrl)", "minDelay := uint16(0)", 1),
		"missing ForceSet":     strings.Replace(minimalURLTest, "func (u *URLTest) ForceSet(name string)", "func (u *URLTest) Other(name string)", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchURLTestGroup([]byte(tampered)); err == nil {
				t.Fatalf("changed urltest.go shape (%s) accepted", name)
			}
		})
	}
}

func TestSingTunServerPatchDelegatesDNSToHandledObserver(t *testing.T) {
	patchedBytes, err := patchSingTunServer([]byte(minimalSingTunServer))
	if err != nil {
		t.Fatal(err)
	}
	patched := string(patchedBytes)
	if !strings.Contains(patched, "if !fcxNotifyDefaultInterfaceChanged(defaultInterface, event)") {
		t.Fatalf("expected RegisterCallback closure to guard fallback DNS/iface reset behind !fcxNotifyDefaultInterfaceChanged(...), got:\n%s", patched)
	}
	notifyIdx := strings.Index(patched, "fcxNotifyDefaultInterfaceChanged(defaultInterface, event)")
	resolverIdx := strings.Index(patched, "resolver.ResetConnection()")
	if notifyIdx < 0 || resolverIdx < notifyIdx {
		t.Fatalf("expected resolver.ResetConnection() to sit inside !fcxNotifyDefaultInterfaceChanged fallback branch after notify call (notifyIdx=%d resolverIdx=%d)", notifyIdx, resolverIdx)
	}
}

func TestOutboundGroupBasePatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	const minimalGroupBase = `package outboundgroup

import (
	"sync"
	"sync/atomic"
	"time"
)

type GroupBase struct {
	failedTestMux  sync.Mutex
	failedTimes    int
	failedTime     time.Time
	failedTesting  atomic.Bool
	testTimeout    int
	maxFailedTimes int
	providers      []interface{ HealthCheck() }
}

func (gb *GroupBase) Name() string { return "g" }

func (gb *GroupBase) onDialFailed(fn func()) {
	go func() {
		gb.failedTestMux.Lock()
		defer gb.failedTestMux.Unlock()

		gb.failedTimes++
		if gb.failedTimes == 1 {
			log.Debugln("ProxyGroup: %s first failed", gb.Name())
			gb.failedTime = time.Now()
		} else {
			if time.Since(gb.failedTime) > time.Duration(gb.testTimeout)*time.Millisecond {
				gb.failedTimes = 0
				return
			}

			log.Debugln("ProxyGroup: %s failed count: %d", gb.Name(), gb.failedTimes)
			if gb.failedTimes >= gb.maxFailedTimes {
				log.Warnln("because %s failed multiple times, activate health check", gb.Name())
				fn()
			}
		}
	}()
}

func (gb *GroupBase) healthCheck() {
	if gb.failedTesting.Load() {
		return
	}
	gb.failedTesting.Store(true)
	wg := sync.WaitGroup{}
	for _, proxyProvider := range gb.providers {
		wg.Add(1)
		proxyProvider := proxyProvider
		go func() {
			defer wg.Done()
			proxyProvider.HealthCheck()
		}()
	}
	wg.Wait()
	gb.failedTesting.Store(false)
	gb.failedTimes = 0
}

func (gb *GroupBase) onDialSuccess() {
	if !gb.failedTesting.Load() {
		gb.failedTimes = 0
	}
}
`
	first, err := patchOutboundGroupBase([]byte(minimalGroupBase))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchOutboundGroupBase([]byte(minimalGroupBase))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("groupbase.go patch is nondeterministic: %v", err)
	}
	patched := string(first)
	for _, want := range []string{
		"fcxStability",
		"fcxStabilityTracker",
		"30 * time.Second",
		"gb.failedTimes = 1",
		"gb.failedTime = time.Now()",
		"gb.failedTestMux.Lock()",
		"shouldTrigger := func() bool",
	} {
		if !strings.Contains(patched, want) {
			t.Fatalf("patched groupbase.go missing %q:\n%s", want, patched)
		}
	}
	shouldTriggerIdx := strings.Index(patched, "shouldTrigger := func() bool")
	invokeIdx := strings.Index(patched, "if shouldTrigger {\n\t\t\tfn()\n\t\t}")
	if shouldTriggerIdx < 0 || invokeIdx <= shouldTriggerIdx {
		t.Fatalf("expected fn() invocation after releasing failedTestMux in onDialFailed:\n%s", patched)
	}
	for name, tampered := range map[string]string{
		"missing timeout check": strings.Replace(minimalGroupBase, "time.Duration(gb.testTimeout)*time.Millisecond", "time.Second", 1),
		"missing healthCheck":   strings.Replace(minimalGroupBase, "wg.Wait()", "wg.Done()", 1),
		"missing onDialSuccess": strings.Replace(minimalGroupBase, "func (gb *GroupBase) onDialSuccess()", "func (gb *GroupBase) otherSuccess()", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := patchOutboundGroupBase([]byte(tampered)); err == nil {
				t.Fatal("changed upstream groupbase.go shape accepted")
			}
		})
	}
}

