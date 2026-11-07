// mihomo-overlay creates a checked Go build overlay without modifying the module
// cache. The fixed upstream source hashes make dependency drift a build error.
package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed patches/*.txt
var patchFiles embed.FS

const upstreamVersion = "v1.19.32"
const upstreamCommit = "88dcbf7f1614a67c3b36b848ee3592dfa92ada36"
const upstreamModuleSum = "h1:uD7ZC3P77isWD554NNvtee65L+99+/C5hyc+Lk8rVEk="
const listenerSHA256 = "1a11cda3fb4a87875d817fe29f1e79973cb8cb6eeccc0ae5e22db15df1277758"
const configsSHA256 = "d11710296ea68a8d12f7593ec50cec9fef830272b3a54f64f707ec86920baf9f"
const controllerSHA256 = "01724bd82002cf80b85448ef664ca53a7cb82f529ccf2b7f4a6383282768d256"
const adapterSHA256 = "0a0524f342ff1672fdb94ad675d176d069b1f6e16ddfe462ece2f55b9e10212c"
const dnsDoHSHA256 = "1ba0170bed4aabf6b295471f9fddb03da20122d339526a97170dff537fbde57b"
const converterSHA256 = "503aac2968628ab826f8208d620bcd5939ca67219426cf0189fab76346626ede"
const ifaceSHA256 = "67d3d4f54999bdb6875ef87cdbb87c61d5f9e299aa20c1108de3e391eac18605"
const singTunServerSHA256 = "8b0d766e346aa5a36ec40dc66c1fe7cd3466ead48a687cfb4a262342ca9a3335"
const singTunVersion = "v0.4.27"
const singTunModuleSum = "h1:dWCpFDlWelQrhH3y5KkMrJXEXYeJ0V2LROP8Cxv96MI="
const singTunWindowsSHA256 = "e463b674d33694dbaa02d165e6a1e24d310a6f12066aab4d3bbe10683be9aff0"

func patchController(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "server.go", source, 0)
	if err != nil {
		return nil, err
	}
	names := map[string]bool{"ReCreateServer": true, "SetUIPath": true, "start": true, "startTLS": true, "startUnix": true, "startPipe": true}
	var changes []replacement
	for _, declaration := range file.Decls {
		fn, ok := declaration.(*ast.FuncDecl)
		if !ok || !names[fn.Name.Name] {
			continue
		}
		replacementText := ""
		if fn.Name.Name == "ReCreateServer" {
			replacementText = `func ReCreateServer(cfg *Config) {
				if err := ReCreateServerChecked(cfg); err != nil { log.Errorln("External controller: %v", err) }
			}`
		}
		if fn.Name.Name == "SetUIPath" {
			replacementText = `func SetUIPath(path string) { fcxControllerMu.Lock(); defer fcxControllerMu.Unlock(); uiPath = path; if path != "" { uiPath=C.Path.Resolve(path) } }`
		}
		changes = append(changes, replacement{fset.Position(fn.Pos()).Offset, fset.Position(fn.End()).Offset, replacementText})
	}
	if len(changes) != len(names) {
		return nil, fmt.Errorf("upstream controller function set changed")
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	patched = strings.Replace(patched, "type Config struct {", "type Config struct {\n\tUIPath *string // optional embedded-controller UI path", 1)
	patched = strings.Replace(patched, "r.Mount(\"/debug\", func() http.Handler {\n\t\t\tr := chi.NewRouter()", "r.Mount(\"/debug\", func() http.Handler {\n\t\t\tr := chi.NewRouter()\n\t\t\tif secret != \"\" { r.Use(authentication(secret)) }", 1)
	for _, name := range []string{"context", "os", "path/filepath", "syscall", "github.com/metacubex/mihomo/adapter/inbound", "github.com/metacubex/mihomo/component/ca", "github.com/metacubex/mihomo/component/ech", "github.com/metacubex/mihomo/ntp", "github.com/metacubex/tls"} {
		patched = strings.Replace(patched, "\t\""+name+"\"\n", "", 1)
	}
	return format.Source([]byte(patched))
}

func main() {
	out := flag.String("out", ".generated/mihomo-overlay.json", "generated overlay path")
	flag.Parse()
	if err := generate(*out); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func checkedSource(path, expected string) ([]byte, error) {
	source, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	digest := sha256.Sum256(source)
	if hex.EncodeToString(digest[:]) != expected {
		return nil, fmt.Errorf("upstream source hash mismatch: %s", path)
	}
	return source, nil
}

type replacement struct {
	start, end int
	text       string
}

func patchListener(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "listener.go", source, 0)
	if err != nil {
		return nil, err
	}
	names := map[string]string{
		"GetTunConf": "get_tun_conf.txt", "ReCreateTun": "recreate_tun.txt",
		"closeTunListener": "close_tun.txt", "Cleanup": "cleanup.txt",
	}
	var changes []replacement
	for _, declaration := range file.Decls {
		fn, ok := declaration.(*ast.FuncDecl)
		if !ok {
			continue
		}
		name, ok := names[fn.Name.Name]
		if !ok {
			continue
		}
		body, err := patchFiles.ReadFile("patches/" + name)
		if err != nil {
			return nil, err
		}
		changes = append(changes, replacement{fset.Position(fn.Pos()).Offset, fset.Position(fn.End()).Offset, string(body)})
	}
	if len(changes) != len(names) {
		return nil, fmt.Errorf("upstream TUN function set changed")
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	if strings.Count(patched, "*sing_tun.Listener") != 1 {
		return nil, fmt.Errorf("upstream TUN listener declaration changed")
	}
	patched = strings.Replace(patched, "*sing_tun.Listener", "fcxTunListener", 1)
	patched = strings.Replace(patched, "\t\"github.com/metacubex/mihomo/listener/sing_tun\"\n", "", 1)
	return format.Source([]byte(patched))
}

func patchDNSDoH(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "doh.go", source, 0)
	if err != nil {
		return nil, err
	}
	names := map[string]string{
		"ExchangeContext": "dns_exchange_context.txt",
		"resetClient":     "dns_reset_client.txt",
		"getClient":       "dns_get_client.txt",
	}
	seen := map[string]bool{}
	var changes []replacement
	for _, declaration := range file.Decls {
		fn, ok := declaration.(*ast.FuncDecl)
		if !ok {
			continue
		}
		name, ok := names[fn.Name.Name]
		if !ok {
			continue
		}
		if seen[fn.Name.Name] || fn.Recv == nil || len(fn.Recv.List) != 1 {
			return nil, fmt.Errorf("upstream DoH method set changed: %s", fn.Name.Name)
		}
		pointer, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
		if !ok {
			return nil, fmt.Errorf("upstream DoH receiver changed: %s", fn.Name.Name)
		}
		receiver, ok := pointer.X.(*ast.Ident)
		if !ok || receiver.Name != "dnsOverHTTPS" {
			return nil, fmt.Errorf("upstream DoH receiver changed: %s", fn.Name.Name)
		}
		seen[fn.Name.Name] = true
		body, err := patchFiles.ReadFile("patches/" + name)
		if err != nil {
			return nil, err
		}
		changes = append(changes, replacement{fset.Position(fn.Pos()).Offset, fset.Position(fn.End()).Offset, string(body)})
	}
	if len(changes) != len(names) {
		return nil, fmt.Errorf("upstream DoH method set changed")
	}
	// Connection health state lives with the upstream object so it is freed
	// with it; exactly one dnsOverHTTPS struct must exist.
	structs := 0
	for _, declaration := range file.Decls {
		generic, ok := declaration.(*ast.GenDecl)
		if !ok || generic.Tok != token.TYPE {
			continue
		}
		for _, spec := range generic.Specs {
			typeSpec, ok := spec.(*ast.TypeSpec)
			if !ok || typeSpec.Name.Name != "dnsOverHTTPS" {
				continue
			}
			structType, ok := typeSpec.Type.(*ast.StructType)
			if !ok || structType.Fields == nil || !structType.Fields.Closing.IsValid() {
				return nil, fmt.Errorf("upstream DoH struct changed")
			}
			for _, field := range structType.Fields.List {
				for _, fieldName := range field.Names {
					if fieldName.Name == "fcxHealth" {
						return nil, fmt.Errorf("upstream DoH struct already has fcxHealth")
					}
				}
			}
			structs++
			closing := fset.Position(structType.Fields.Closing).Offset
			changes = append(changes, replacement{closing, closing, "\n\tfcxHealth fcxDoHHealth\n"})
		}
	}
	if structs != 1 {
		return nil, fmt.Errorf("upstream DoH struct changed")
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	return format.Source([]byte(patched))
}

func patchIface(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "iface.go", source, 0)
	if err != nil {
		return nil, err
	}
	var changes []replacement
	for _, declaration := range file.Decls {
		fn, ok := declaration.(*ast.FuncDecl)
		if !ok || fn.Name.Name != "getCache" {
			continue
		}
		if fn.Recv != nil {
			return nil, fmt.Errorf("upstream iface getCache became a method")
		}
		changes = append(changes, replacement{
			fset.Position(fn.Pos()).Offset,
			fset.Position(fn.End()).Offset,
			`func getCache() (*ifaceCache, error) {
	value, err, _ := caches.Do(func() (*ifaceCache, error) {
		return fcxBuildIfaceCache()
	})
	return value, err
}`,
		})
	}
	if len(changes) != 1 {
		return nil, fmt.Errorf("upstream iface getCache declaration changed")
	}
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	const anetImport = "\t\"github.com/metacubex/mihomo/component/iface/anet\"\n"
	if strings.Count(patched, anetImport) != 1 {
		return nil, fmt.Errorf("upstream iface anet import changed")
	}
	patched = strings.Replace(patched, anetImport, "", 1)
	return format.Source([]byte(patched))
}

func patchSingTunServer(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "server.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)

	const monitorAnchor = `		networkUpdateMonitor, err = tun.NewNetworkUpdateMonitor(log.SingLogger)
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
		}`
	const monitorReplacement = `		monitorsStartedAt := fcxSingTunTimingStart()
		networkUpdateMonitor, err = tun.NewNetworkUpdateMonitor(log.SingLogger)
		if err != nil {
			fcxLogSingTunStage("sing_tun.monitors", monitorsStartedAt, err)
			err = E.Cause(err, "create NetworkUpdateMonitor")
			return
		}
		l.networkUpdateMonitor = networkUpdateMonitor
		err = networkUpdateMonitor.Start()
		if err != nil {
			fcxLogSingTunStage("sing_tun.monitors", monitorsStartedAt, err)
			err = E.Cause(err, "start NetworkUpdateMonitor")
			return
		}

		overrideAndroidVPN := true
		if disable, _ := strconv.ParseBool(os.Getenv("DISABLE_OVERRIDE_ANDROID_VPN")); disable {
			overrideAndroidVPN = false
		}
		defaultInterfaceMonitor, err = tun.NewDefaultInterfaceMonitor(networkUpdateMonitor, log.SingLogger, tun.DefaultInterfaceMonitorOptions{InterfaceFinder: interfaceFinder, OverrideAndroidVPN: overrideAndroidVPN})
		if err != nil {
			fcxLogSingTunStage("sing_tun.monitors", monitorsStartedAt, err)
			err = E.Cause(err, "create DefaultInterfaceMonitor")
			return
		}
		l.defaultInterfaceMonitor = defaultInterfaceMonitor
		err = defaultInterfaceMonitor.Start()
		if err != nil {
			fcxLogSingTunStage("sing_tun.monitors", monitorsStartedAt, err)
			err = E.Cause(err, "start DefaultInterfaceMonitor")
			return
		}
		defaultInterfaceMonitor.RegisterCallback(func(defaultInterface *control.Interface, event int) {
			if defaultInterface != nil {
				log.Warnln("[TUN] default interface changed by monitor, => %s", defaultInterface.Name)
			} else {
				log.Errorln("[TUN] default interface lost by monitor")
			}
			iface.FlushCache()
			resolver.ResetConnection() // reset resolver's connection after default interface changed
		})
		fcxLogSingTunStage("sing_tun.monitors", monitorsStartedAt, nil)`

	const deviceAnchor = `	tunIf, err := tunNew(tunOptions)
	if err != nil {
		err = E.Cause(err, "configure tun interface")
		return
	}`
	const deviceReplacement = `	tunDeviceStartedAt := fcxSingTunTimingStart()
	tunIf, err := tunNew(tunOptions)
	fcxLogSingTunStage("sing_tun.device", tunDeviceStartedAt, err)
	if err != nil {
		err = E.Cause(err, "configure tun interface")
		return
	}`

	const stackAnchor = `	tunStack, err := tun.NewStack(strings.ToLower(options.Stack.String()), stackOptions)
	if err != nil {
		return
	}

	err = tunStack.Start()
	if err != nil {
		return
	}`
	const stackReplacement = `	tunStackStartedAt := fcxSingTunTimingStart()
	tunStack, err := tun.NewStack(strings.ToLower(options.Stack.String()), stackOptions)
	if err != nil {
		fcxLogSingTunStage("sing_tun.stack", tunStackStartedAt, err)
		return
	}

	err = tunStack.Start()
	fcxLogSingTunStage("sing_tun.stack", tunStackStartedAt, err)
	if err != nil {
		return
	}`

	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"monitors", monitorAnchor, monitorReplacement},
		{"device", deviceAnchor, deviceReplacement},
		{"stack", stackAnchor, stackReplacement},
	} {
		if strings.Count(patched, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream sing_tun %s block changed", pair.name)
		}
		patched = strings.Replace(patched, pair.anchor, pair.replacement, 1)
	}
	return format.Source([]byte(patched))
}

func patchSingTunWindows(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "tun_windows.go", source, 0)
	if err != nil {
		return nil, err
	}
	var newFn, configureFn *ast.FuncDecl
	for _, declaration := range file.Decls {
		fn, ok := declaration.(*ast.FuncDecl)
		if !ok {
			continue
		}
		switch fn.Name.Name {
		case "New":
			if fn.Recv == nil {
				if newFn != nil {
					return nil, fmt.Errorf("duplicate sing-tun New function")
				}
				newFn = fn
			}
		case "configure":
			if fn.Recv != nil {
				if configureFn != nil {
					return nil, fmt.Errorf("duplicate sing-tun configure method")
				}
				configureFn = fn
			}
		}
	}
	if newFn == nil || configureFn == nil {
		return nil, fmt.Errorf("upstream sing-tun windows functions missing")
	}

	newText := string(source[fset.Position(newFn.Pos()).Offset:fset.Position(newFn.End()).Offset])
	const createAnchor = `	adapter, err := wintun.CreateAdapter(options.Name, TunnelType, generateGUIDByDeviceName(options.Name))
	if err != nil {
		if !errors.Is(err, os.ErrExist) {
			return nil, err
		}
		createErr := err
		adapter, err = wintun.OpenAdapter(options.Name)
		if err != nil {
			return nil, E.Errors(E.Cause(createErr, "create adapter"), E.Cause(err, "open existing adapter"))
		}
	}`
	const createReplacement = `	wintunCreateStartedAt := fcxDeviceTimingStart()
	adapter, err := wintun.CreateAdapter(options.Name, TunnelType, generateGUIDByDeviceName(options.Name))
	if err != nil {
		if !errors.Is(err, os.ErrExist) {
			fcxLogDeviceStage("sing_tun.device.wintun_create", wintunCreateStartedAt, err)
			return nil, err
		}
		createErr := err
		adapter, err = wintun.OpenAdapter(options.Name)
		if err != nil {
			err = E.Errors(E.Cause(createErr, "create adapter"), E.Cause(err, "open existing adapter"))
			fcxLogDeviceStage("sing_tun.device.wintun_create", wintunCreateStartedAt, err)
			return nil, err
		}
	}
	fcxLogDeviceStage("sing_tun.device.wintun_create", wintunCreateStartedAt, nil)`

	const sessionAnchor = `	session, err := adapter.StartSession(0x800000)
	if err != nil {
		return nil, err
	}`
	const sessionReplacement = `	sessionStartedAt := fcxDeviceTimingStart()
	session, err := adapter.StartSession(0x800000)
	fcxLogDeviceStage("sing_tun.device.session_start", sessionStartedAt, err)
	if err != nil {
		return nil, err
	}`

	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"wintun_create", createAnchor, createReplacement},
		{"session_start", sessionAnchor, sessionReplacement},
	} {
		if strings.Count(newText, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream sing-tun New %s block changed", pair.name)
		}
		newText = strings.Replace(newText, pair.anchor, pair.replacement, 1)
	}

	configureText := string(source[fset.Position(configureFn.Pos()).Offset:fset.Position(configureFn.End()).Offset])
	const configureHeaderAnchor = "func (t *NativeTun) configure() error {\n\tluid := winipcfg.LUID(t.adapter.LUID())\n"
	const configureHeaderReplacement = `func (t *NativeTun) configure() error {
	luid := winipcfg.LUID(t.adapter.LUID())
	ipDnsStartedAt := fcxDeviceTimingStart()
	if err := func() error {
`
	const ipToRouteAnchor = `	if len(t.options.Inet4Address) > 0 || len(t.options.Inet6Address) > 0 {
		_ = luid.DisableDNSRegistration()
	}
	if t.options.AutoRoute {`
	const ipToRouteReplacement = `	if len(t.options.Inet4Address) > 0 || len(t.options.Inet6Address) > 0 {
		_ = luid.DisableDNSRegistration()
	}
	return nil
	}(); err != nil {
		fcxLogDeviceStage("sing_tun.device.ip_dns_config", ipDnsStartedAt, err)
		return err
	}
	fcxLogDeviceStage("sing_tun.device.ip_dns_config", ipDnsStartedAt, nil)
	routeStartedAt := fcxDeviceTimingStart()
	if err := func() error {
	if t.options.AutoRoute {`

	const routeLoopAnchor = `		for _, routeRange := range routeRanges {
			if routeRange.Addr().Is4() {
				err = luid.AddRoute(routeRange, gateway4, 0)
			} else {
				err = luid.AddRoute(routeRange, gateway6, 0)
			}
		}
		if err != nil {
			return err
		}`
	const routeLoopReplacement = `		err = FCXAddAutoRoutes(routeRanges, gateway4, gateway6, luid.AddRoute, func(routeErr error) bool {
			return errors.Is(routeErr, windows.ERROR_OBJECT_ALREADY_EXISTS)
		})
		if err != nil {
			return err
		}`

	const routeToStrictAnchor = `		err = inet6If.Set()
		if err != nil {
			return E.Cause(err, "set ipv6 options")
		}
	}

	if t.options.AutoRoute && t.options.StrictRoute {`
	const routeToStrictReplacement = `		err = inet6If.Set()
		if err != nil {
			return E.Cause(err, "set ipv6 options")
		}
	}
	return nil
	}(); err != nil {
		fcxLogDeviceStage("sing_tun.device.route_config", routeStartedAt, err)
		return err
	}
	fcxLogDeviceStage("sing_tun.device.route_config", routeStartedAt, nil)

	if t.options.AutoRoute && t.options.StrictRoute {
		strictRouteStartedAt := fcxDeviceTimingStart()
		if err := func() error {`

	const configureTailAnchor = "\t}\n\n\treturn nil\n}"
	const configureTailReplacement = `			return nil
		}(); err != nil {
			fcxLogDeviceStage("sing_tun.device.strict_route", strictRouteStartedAt, err)
			return err
		}
		fcxLogDeviceStage("sing_tun.device.strict_route", strictRouteStartedAt, nil)
	}

	return nil
}`

	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"configure_header", configureHeaderAnchor, configureHeaderReplacement},
		{"ip_to_route", ipToRouteAnchor, ipToRouteReplacement},
		{"route_loop", routeLoopAnchor, routeLoopReplacement},
		{"route_to_strict", routeToStrictAnchor, routeToStrictReplacement},
	} {
		if strings.Count(configureText, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream sing-tun configure %s block changed", pair.name)
		}
		configureText = strings.Replace(configureText, pair.anchor, pair.replacement, 1)
	}
	if !strings.HasSuffix(configureText, configureTailAnchor) {
		return nil, fmt.Errorf("upstream sing-tun configure tail changed")
	}
	configureText = configureText[:len(configureText)-len(configureTailAnchor)] + configureTailReplacement

	changes := []replacement{
		{fset.Position(newFn.Pos()).Offset, fset.Position(newFn.End()).Offset, newText},
		{fset.Position(configureFn.Pos()).Offset, fset.Position(configureFn.End()).Offset, configureText},
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	return format.Source([]byte(patched))
}

func generate(out string) error {
	command := exec.Command("go", "list", "-m", "-json", "github.com/metacubex/mihomo")
	data, err := command.Output()
	if err != nil {
		return fmt.Errorf("resolve pinned mihomo module: %w", err)
	}
	var module struct {
		Version, Dir, Sum string
		Replace           json.RawMessage
	}
	if err := json.Unmarshal(data, &module); err != nil {
		return err
	}
	if module.Version != upstreamVersion || len(module.Replace) != 0 {
		return fmt.Errorf("expected unmodified mihomo %s module", upstreamVersion)
	}
	command = exec.Command("go", "mod", "download", "-json", "github.com/metacubex/mihomo@"+upstreamVersion)
	data, err = command.Output()
	if err != nil {
		return fmt.Errorf("download pinned mihomo module: %w", err)
	}
	if err := json.Unmarshal(data, &module); err != nil {
		return err
	}
	if module.Dir == "" || module.Sum != upstreamModuleSum {
		return fmt.Errorf("pinned mihomo module checksum mismatch")
	}
	var singTunModule struct {
		Version, Dir, Sum string
		Replace           json.RawMessage
	}
	data, err = exec.Command("go", "list", "-m", "-json", "github.com/metacubex/sing-tun").Output()
	if err != nil {
		return fmt.Errorf("resolve pinned sing-tun module: %w", err)
	}
	if err := json.Unmarshal(data, &singTunModule); err != nil {
		return err
	}
	if singTunModule.Version != singTunVersion || len(singTunModule.Replace) != 0 {
		return fmt.Errorf("expected unmodified sing-tun %s module", singTunVersion)
	}
	data, err = exec.Command("go", "mod", "download", "-json", "github.com/metacubex/sing-tun@"+singTunVersion).Output()
	if err != nil {
		return fmt.Errorf("download pinned sing-tun module: %w", err)
	}
	if err := json.Unmarshal(data, &singTunModule); err != nil {
		return err
	}
	if singTunModule.Dir == "" || singTunModule.Sum != singTunModuleSum {
		return fmt.Errorf("pinned sing-tun module checksum mismatch")
	}
	if output, err := exec.Command("go", "mod", "verify").CombinedOutput(); err != nil {
		return fmt.Errorf("module integrity verification failed: %w: %s", err, output)
	}
	listenerPath := filepath.Join(module.Dir, "listener", "listener.go")
	listenerSource, err := checkedSource(listenerPath, listenerSHA256)
	if err != nil {
		return err
	}
	patchedListener, err := patchListener(listenerSource)
	if err != nil {
		return err
	}
	configsPath := filepath.Join(module.Dir, "hub", "route", "configs.go")
	configsSource, err := checkedSource(configsPath, configsSHA256)
	if err != nil {
		return err
	}
	if strings.Count(string(configsSource), "listener.LastTunConf") != 1 {
		return fmt.Errorf("upstream TUN route configuration access changed")
	}
	patchedConfigs := []byte(strings.Replace(string(configsSource), "listener.LastTunConf", "listener.GetTunConf()", 1))
	controllerSource, err := checkedSource(filepath.Join(module.Dir, "hub", "route", "server.go"), controllerSHA256)
	if err != nil {
		return err
	}
	patchedController, err := patchController(controllerSource)
	if err != nil {
		return err
	}
	adapterSource, err := checkedSource(filepath.Join(module.Dir, "adapter", "adapter.go"), adapterSHA256)
	if err != nil {
		return err
	}
	adapterHistoryAnchor := "defer func() {\n\t\talive := err == nil"
	if strings.Count(string(adapterSource), adapterHistoryAnchor) != 1 {
		return fmt.Errorf("upstream URLTest history function changed")
	}
	adapterSource = []byte(strings.Replace(string(adapterSource), adapterHistoryAnchor, "defer func() {\n\t\trelease,commit:=fcxBeginURLTestHistory(ctx)\n\t\tif !commit { return }\n\t\tif release!=nil {defer release()}\n\t\talive := err == nil", 1))
	adapterSource, err = format.Source(adapterSource)
	if err != nil {
		return err
	}
	dnsDoHSource, err := checkedSource(filepath.Join(module.Dir, "dns", "doh.go"), dnsDoHSHA256)
	if err != nil {
		return err
	}
	patchedDNSDoH, err := patchDNSDoH(dnsDoHSource)
	if err != nil {
		return err
	}
	converterSource, err := checkedSource(filepath.Join(module.Dir, "common", "convert", "converter.go"), converterSHA256)
	if err != nil {
		return err
	}
	converterHeader := "func ConvertsV2Ray(buf []byte) ([]map[string]any, error) {"
	converterLog := `log.Warnln("error:%s line:%s", err.Error(), line)`
	if strings.Count(string(converterSource), converterHeader) != 1 || strings.Count(string(converterSource), converterLog) != 2 {
		return fmt.Errorf("upstream subscription conversion diagnostics changed")
	}
	// Keep active/import behavior unchanged. The isolated parser uses a
	// per-call quiet entry point, never a mutable global logging setting.
	converterSource = []byte(strings.Replace(string(converterSource), converterHeader, `func ConvertsV2Ray(buf []byte) ([]map[string]any, error) { return convertsV2RayFCX(buf, true) }
func ConvertsV2RayQuietFCX(buf []byte) ([]map[string]any, error) { return convertsV2RayFCX(buf, false) }
func convertsV2RayFCX(buf []byte, diagnostics bool) ([]map[string]any, error) {`, 1))
	converterSource = []byte(strings.ReplaceAll(string(converterSource), converterLog, "if diagnostics { "+converterLog+" }"))
	converterSource, err = format.Source(converterSource)
	if err != nil {
		return err
	}
	ifaceSource, err := checkedSource(filepath.Join(module.Dir, "component", "iface", "iface.go"), ifaceSHA256)
	if err != nil {
		return err
	}
	patchedIface, err := patchIface(ifaceSource)
	if err != nil {
		return err
	}
	singTunServerSource, err := checkedSource(filepath.Join(module.Dir, "listener", "sing_tun", "server.go"), singTunServerSHA256)
	if err != nil {
		return err
	}
	patchedSingTunServer, err := patchSingTunServer(singTunServerSource)
	if err != nil {
		return err
	}
	singTunWindowsSource, err := checkedSource(filepath.Join(singTunModule.Dir, "tun_windows.go"), singTunWindowsSHA256)
	if err != nil {
		return err
	}
	patchedSingTunWindows, err := patchSingTunWindows(singTunWindowsSource)
	if err != nil {
		return err
	}
	out, err = filepath.Abs(out)
	if err != nil {
		return err
	}
	directory := filepath.Join(filepath.Dir(out), "mihomo-"+upstreamVersion)
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	// Go deliberately forbids overlays inside GOMODCACHE. Build against an
	// isolated generated module copy instead; never alter cached dependency files.
	stagingDirectory, err := os.MkdirTemp(filepath.Dir(out), "mihomo-"+upstreamVersion+"-staging-")
	if err != nil {
		return err
	}
	if err := copyModule(module.Dir, stagingDirectory); err != nil {
		return err
	}
	stagingHashes, err := treeHashes(stagingDirectory)
	if err != nil {
		return err
	}
	sourceDirectory := filepath.Join(filepath.Dir(out), "mihomo-"+upstreamVersion+"-source-"+aggregateHashes(stagingHashes))
	if err := publishModuleCopy(stagingDirectory, sourceDirectory, stagingHashes); err != nil {
		return err
	}
	singTunStagingDirectory, err := os.MkdirTemp(filepath.Dir(out), "sing-tun-"+singTunVersion+"-staging-")
	if err != nil {
		return err
	}
	if err := copyModule(singTunModule.Dir, singTunStagingDirectory); err != nil {
		return err
	}
	singTunStagingHashes, err := treeHashes(singTunStagingDirectory)
	if err != nil {
		return err
	}
	singTunSourceDirectory := filepath.Join(filepath.Dir(out), "sing-tun-"+singTunVersion+"-source-"+aggregateHashes(singTunStagingHashes))
	if err := publishModuleCopy(singTunStagingDirectory, singTunSourceDirectory, singTunStagingHashes); err != nil {
		return err
	}
	listenerPath = filepath.Join(sourceDirectory, "listener", "listener.go")
	configsPath = filepath.Join(sourceDirectory, "hub", "route", "configs.go")
	replacements := map[string]string{}
	write := func(original, name string, contents []byte) error {
		target := filepath.Join(directory, name)
		if err := os.WriteFile(target, contents, 0644); err != nil {
			return err
		}
		replacements[original] = target
		return nil
	}
	if err := write(listenerPath, "listener.go", patchedListener); err != nil {
		return err
	}
	if err := write(configsPath, "configs.go", patchedConfigs); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "hub", "route", "server.go"), "server.go", patchedController); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "adapter", "adapter.go"), "adapter.go", adapterSource); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "dns", "doh.go"), "doh.go", patchedDNSDoH); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "common", "convert", "converter.go"), "catalog_converter.go", converterSource); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "component", "iface", "iface.go"), "iface.go", patchedIface); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "listener", "sing_tun", "server.go"), "sing_tun_server.go", patchedSingTunServer); err != nil {
		return err
	}
	for _, name := range []string{
		"iface_cache_fcx.go",
		"iface_other_fcx.go",
		"iface_windows_fcx.go",
		"iface_fcx_test.go",
		"iface_windows_fcx_test.go",
	} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "component", "iface", name), name, contents); err != nil {
			return err
		}
	}
	for _, name := range []string{"sing_tun_timing_fcx.go", "sing_tun_timing_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "listener", "sing_tun", name), name, contents); err != nil {
			return err
		}
	}
	if err := write(filepath.Join(singTunSourceDirectory, "tun_windows.go"), "sing_tun_windows.go", patchedSingTunWindows); err != nil {
		return err
	}
	singTunDeviceTiming, err := patchFiles.ReadFile("patches/sing_tun_device_timing_fcx.go.txt")
	if err != nil {
		return err
	}
	singTunDeviceTiming, err = format.Source(singTunDeviceTiming)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(singTunSourceDirectory, "sing_tun_device_timing_fcx.go"), "sing_tun_device_timing_fcx.go", singTunDeviceTiming); err != nil {
		return err
	}
	dnsTests, err := patchFiles.ReadFile("patches/dns_doh_lifecycle_fcx_test.go.txt")
	if err != nil {
		return err
	}
	dnsTests, err = format.Source(dnsTests)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "dns", "doh_lifecycle_fcx_test.go"), "doh_lifecycle_fcx_test.go", dnsTests); err != nil {
		return err
	}
	dnsHealth, err := patchFiles.ReadFile("patches/dns_doh_health_fcx.go.txt")
	if err != nil {
		return err
	}
	dnsHealth, err = format.Source(dnsHealth)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "dns", "doh_health_fcx.go"), "doh_health_fcx.go", dnsHealth); err != nil {
		return err
	}
	for _, name := range []string{"urltest_history_fcx.go", "urltest_history_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "adapter", name), name, contents); err != nil {
			return err
		}
	}
	for _, name := range []string{"controller_fcx.go", "controller_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "hub", "route", name), name, contents); err != nil {
			return err
		}
	}
	for _, name := range []string{"tun_status_fcx.go", "tun_usable_other_fcx.go", "tun_usable_windows_fcx.go", "tun_status_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "listener", name), name, contents); err != nil {
			return err
		}
	}
	catalogParser, err := patchFiles.ReadFile("patches/catalog_provider_fcx.go.txt")
	if err != nil {
		return err
	}
	catalogParser, err = format.Source(catalogParser)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "adapter", "provider", "catalog_provider_fcx.go"), "catalog_provider_fcx.go", catalogParser); err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(struct{ Replace map[string]string }{replacements}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(out, append(encoded, '\n'), 0644); err != nil {
		return err
	}
	modfile := filepath.Join(filepath.Dir(out), "go.mod")
	for _, name := range []string{"go.mod", "go.sum"} {
		contents, err := os.ReadFile(name)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(filepath.Dir(out), name), contents, 0644); err != nil {
			return err
		}
	}
	workingDirectory, err := os.Getwd()
	if err != nil {
		return err
	}
	relativeSource, err := filepath.Rel(workingDirectory, sourceDirectory)
	if err != nil {
		return err
	}
	relativeSource = filepath.ToSlash(relativeSource)
	if !strings.HasPrefix(relativeSource, "../") {
		relativeSource = "./" + relativeSource
	}
	relativeSingTunSource, err := filepath.Rel(workingDirectory, singTunSourceDirectory)
	if err != nil {
		return err
	}
	relativeSingTunSource = filepath.ToSlash(relativeSingTunSource)
	if !strings.HasPrefix(relativeSingTunSource, "../") {
		relativeSingTunSource = "./" + relativeSingTunSource
	}
	command = exec.Command(
		"go",
		"mod",
		"edit",
		"-modfile="+modfile,
		"-replace=github.com/metacubex/mihomo="+relativeSource,
		"-replace=github.com/metacubex/sing-tun="+relativeSingTunSource,
	)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("create isolated module file: %w: %s", err, output)
	}
	patchHashes := map[string]string{}
	patchEntries, err := patchFiles.ReadDir("patches")
	if err != nil {
		return err
	}
	for _, entry := range patchEntries {
		contents, err := patchFiles.ReadFile("patches/" + entry.Name())
		if err != nil {
			return err
		}
		patchHashes[entry.Name()] = digest(contents)
	}
	moduleHashes, err := treeHashes(sourceDirectory)
	if err != nil {
		return err
	}
	singTunModuleHashes, err := treeHashes(singTunSourceDirectory)
	if err != nil {
		return err
	}
	for original, overlay := range replacements {
		contents, err := os.ReadFile(overlay)
		if err != nil {
			return err
		}
		if relative, err := filepath.Rel(sourceDirectory, original); err == nil && !strings.HasPrefix(filepath.ToSlash(relative), "../") {
			moduleHashes[filepath.ToSlash(relative)] = digest(contents)
			continue
		}
		relative, err := filepath.Rel(singTunSourceDirectory, original)
		if err != nil || strings.HasPrefix(filepath.ToSlash(relative), "../") {
			return fmt.Errorf("unexpected overlay target outside generated module trees: %s", original)
		}
		singTunModuleHashes[filepath.ToSlash(relative)] = digest(contents)
	}
	generatorSource, err := os.ReadFile(filepath.Join("tools", "mihomo-overlay", "main.go"))
	if err != nil {
		return err
	}
	rootMod, err := os.ReadFile("go.mod")
	if err != nil {
		return err
	}
	manifest, err := json.MarshalIndent(map[string]any{
		"schemaVersion": 1, "module": "github.com/metacubex/mihomo", "version": upstreamVersion,
		"commit": upstreamCommit, "moduleSum": module.Sum,
		"upstreamSourceSHA256": map[string]string{"listener/listener.go": listenerSHA256, "listener/sing_tun/server.go": singTunServerSHA256, "component/iface/iface.go": ifaceSHA256, "hub/route/configs.go": configsSHA256, "hub/route/server.go": controllerSHA256, "adapter/adapter.go": adapterSHA256, "dns/doh.go": dnsDoHSHA256, "common/convert/converter.go": converterSHA256},
		"singTunOverlay": map[string]any{
			"module":               "github.com/metacubex/sing-tun",
			"version":              singTunVersion,
			"moduleSum":            singTunModule.Sum,
			"upstreamSourceSHA256": map[string]string{"tun_windows.go": singTunWindowsSHA256},
			"effectiveModuleSHA256": aggregateHashes(singTunModuleHashes),
		},
		"patchesSHA256":         patchHashes, "generatorSHA256": digest(generatorSource), "projectGoModSHA256": digest(rootMod),
		"effectiveModuleSHA256": aggregateHashes(moduleHashes), "effectiveModuleFiles": moduleHashes,
	}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "manifest.json"), append(manifest, '\n'), 0644); err != nil {
		return err
	}
	fmt.Println(out)
	return nil
}

// Publication never overwrites or deletes an existing generated source tree.
// Every file and extra path is checked before a content-addressed tree is reused.
func publishModuleCopy(staging, destination string, expected map[string]string) error {
	if _, err := os.Lstat(destination); os.IsNotExist(err) {
		if err := os.Rename(staging, destination); err != nil {
			return fmt.Errorf("publish generated module: %w", err)
		}
		return nil
	} else if err != nil {
		return err
	}
	actual, err := treeHashes(destination)
	if err != nil {
		return err
	}
	if aggregateHashes(actual) != aggregateHashes(expected) {
		return fmt.Errorf("generated module integrity mismatch; refusing existing source tree: %s", destination)
	}
	return nil
}

func digest(contents []byte) string {
	value := sha256.Sum256(contents)
	return hex.EncodeToString(value[:])
}

func aggregateHashes(hashes map[string]string) string {
	paths := make([]string, 0, len(hashes))
	for path := range hashes {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	var content strings.Builder
	for _, path := range paths {
		content.WriteString(path + "\x00" + hashes[path] + "\n")
	}
	return digest([]byte(content.String()))
}

func treeHashes(root string) (map[string]string, error) {
	result := map[string]string{}
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("unexpected symlink in source tree: %s", path)
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		result[filepath.ToSlash(relative)] = digest(contents)
		return nil
	})
	return result, err
}

func copyModule(source, destination string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		target := filepath.Join(destination, relative)
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("unexpected symlink in verified module: %s", relative)
		}
		if entry.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, contents, 0644)
	})
}
