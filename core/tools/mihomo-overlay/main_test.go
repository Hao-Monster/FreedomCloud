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
	for _, required := range []string{"failedClient *http.Client", "ctx.Err()", "originalReset()", "fcxHealth fcxDoHHealth", "fcxNoteCallerTimeout"} {
		if !bytes.Contains(first, []byte(required)) {
			t.Fatalf("DoH recovery patch lost %q", required)
		}
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
		if err := luid.SetIPAddressesForFamily(0, t.options.Inet4Address); err != nil {
			return err
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
		if err := windnsapi.FlushResolverCache(); err != nil {
			return err
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
	second, err := patchSingTunWindows([]byte(minimalSingTunWindows))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("sing-tun windows patch is nondeterministic: %v", err)
	}
	patched := string(first)
	for _, stage := range []string{
		"sing_tun.device.wintun_create",
		"sing_tun.device.session_start",
		"sing_tun.device.ip_dns_config",
		"sing_tun.device.route_config",
		"sing_tun.device.strict_route",
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
	for name, source := range map[string]string{
		"missing CreateAdapter": strings.Replace(minimalSingTunWindows, "wintun.CreateAdapter(", "wintun.OtherCreate(", 1),
		"missing StartSession":  strings.Replace(minimalSingTunWindows, "adapter.StartSession(0x800000)", "adapter.OtherSession()", 1),
		"missing DisableDNS":    strings.Replace(minimalSingTunWindows, "_ = luid.DisableDNSRegistration()", "_ = luid.OtherDNS()", 1),
		"missing RouteLoop":     strings.Replace(minimalSingTunWindows, "err = luid.AddRoute(routeRange, gateway4, 0)", "err = luid.OtherAddRoute(routeRange)", 1),
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
