// mihomo-overlay creates a checked Go build overlay without modifying the module
// cache. The fixed upstream source hashes make dependency drift a build error.
package main

import (
	"bytes"
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
const urlTestGroupSHA256 = "6d58af720ff6bcb368b2d43253a784865fd040d6871598cd2cc7eb8237083565"
const groupBaseSHA256 = "4f073f75e1deaff8468458adecaaf674e720200f5c056967e5ee7f9dee25fc38"
const dnsDoHSHA256 = "1ba0170bed4aabf6b295471f9fddb03da20122d339526a97170dff537fbde57b"
const dnsResolverSHA256 = "400765c7dde15950c324ab8fce1a7dc1d7730b3c7f3bff6a85fd64e4238e2b48"
const dnsPolicySHA256 = "a46f9e8cb408b0ea1863fc5bf926e7ce461afb3b6a842394421b5c9951b10116"
const dnsSystemCommonSHA256 = "c59c64d225d28747b41630a46dd28d14fdaba63418cb5607fb5fe9dc99418fbf"
const dnsDHCPSHA256 = "0e3f4b9faae24e1c3b0928a5876cd6fe0986ebf8649f88e31c63ea492a07a5dc"
const converterSHA256 = "503aac2968628ab826f8208d620bcd5939ca67219426cf0189fab76346626ede"
const ifaceSHA256 = "67d3d4f54999bdb6875ef87cdbb87c61d5f9e299aa20c1108de3e391eac18605"
const dialerBindWindowsSHA256 = "75af61a7176ed1a0dbcb53cf9a93fe532b7a7be2d01b374c89ba9be8c23c6926"
const singTunServerSHA256 = "8b0d766e346aa5a36ec40dc66c1fe7cd3466ead48a687cfb4a262342ca9a3335"
const singTunServerWindowsSHA256 = "9e4604f9691915bb7968097b73c945f64136398c92e0c34c12bbd4c43f17863c"
const cacheFileSHA256 = "cf48b5ba8d034847073c189a755b63bfbce43e1d1e0cebe3c2ce72267fd8cb65"
const fakeIpSHA256 = "1f98752ff24228483d6a52bc9902d5607762a6a0990d203a9e7bf35acf70ebbc"
const processWindowsSHA256 = "a4d41ae370ca76690b5594f81c051bc856d8adbf10d9cc897ab1958d84b8d794"
const memConservativeSHA256 = "c4b9c920b5ff6e0f5098a639df0bda013696f54f1a28962e498301bc5645fc3d"
const configSHA256 = "a242e1fd06378e01371153122d51b20862af24b4904fdec2a7b54843e70b1203"
const fetcherSHA256 = "647fdd5906c41202974577ff96a00ebc6bda441ae3e9d7717037cedff4eee903"
const ruleProviderSHA256 = "ec6e3ec5314b09bb33206ae0f01d1865533a406f718697cfeb0979445c004295"
const proxyProviderSHA256 = "69cb24313f68cc457c5f4e45ecab0d1355c1f5d22e3e2ec0559a7d753ee1672f"
const singTunVersion = "v0.4.27"
const singTunModuleSum = "h1:dWCpFDlWelQrhH3y5KkMrJXEXYeJ0V2LROP8Cxv96MI="
const singTunWindowsSHA256 = "e463b674d33694dbaa02d165e6a1e24d310a6f12066aab4d3bbe10683be9aff0"
const singTunStackGvisorSHA256 = "45fb9d63e825c40f90797535d299e44cd1a9737ec08e112cc3d4b53b6fa89180"
const singTunMonitorWindowsSHA256 = "afb6d993c87203594336266933cc373a4db1ed6078d76212be281aa33886f8da"
const singTunMonitorSharedSHA256 = "c0a043a2f419ffd8adf278852c8f60795e17131995a0cc112941f0fa63e187a9"

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
		"ResetConnection": "dns_reset_connection.txt",
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
			if !fcxNotifyDefaultInterfaceChanged(defaultInterface, event) {
				if defaultInterface != nil {
					log.Warnln("[TUN] default interface changed by monitor, => %s", defaultInterface.Name)
				} else {
					log.Errorln("[TUN] default interface lost by monitor")
				}
				iface.FlushCache()
				resolver.ResetConnection() // reset resolver's connection after default interface changed
			}
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

func patchSingTunServerWindows(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "server_windows.go", source, 0); err != nil {
		return nil, err
	}
	// Upstream retries every tun.New failure that took >= 1s. A Wintun adapter
	// Windows refused to add fails only after Wintun's ~15s arrival wait, so the
	// loop held tunMux and the Core runLock for ~47s with the same outcome.
	const retryAnchor = `func tunNew(options tun.Options) (tunIf tun.Tun, err error) {
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
}`
	const retryReplacement = `func tunNew(options tun.Options) (tunIf tun.Tun, err error) {
	return fcxTunNewWithRetry(func() (tun.Tun, error) {
		return tun.New(options)
	}, time.Now, func(err error, attempt, maxRetry int) {
		log.Warnln("Start Tun interface timeout: %s [retrying %d/%d]", err, attempt, maxRetry)
	}, func(err error) {
		log.Warnln("Wintun adapter refused by Windows; not retrying: %s", err)
	})
}`
	patched := string(source)
	if strings.Count(patched, retryAnchor) != 1 {
		return nil, fmt.Errorf("upstream sing_tun server_windows tunNew block changed")
	}
	patched = strings.Replace(patched, retryAnchor, retryReplacement, 1)
	return format.Source([]byte(patched))
}

func patchSingTunWindows(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
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
	const createReplacement = `	wintunCreateStartedAt := fcxDeviceTimingStartFor("sing_tun.device.wintun_create")
	createAdapterStartedAt := fcxDeviceTimingStartFor("tun.wintun_create_adapter")
	adapter, err := wintun.CreateAdapter(options.Name, TunnelType, generateGUIDByDeviceName(options.Name))
	fcxLogDeviceStage("tun.wintun_create_adapter", createAdapterStartedAt, err)
	if err != nil {
		if !errors.Is(err, os.ErrExist) {
			fcxLogDeviceStage("sing_tun.device.wintun_create", wintunCreateStartedAt, err)
			return nil, FCXWrapAdapterCreateError(err)
		}
		createErr := err
		openAdapterStartedAt := fcxDeviceTimingStartFor("tun.wintun_open_adapter")
		adapter, err = wintun.OpenAdapter(options.Name)
		fcxLogDeviceStage("tun.wintun_open_adapter", openAdapterStartedAt, err)
		if err != nil {
			err = E.Errors(E.Cause(createErr, "create adapter"), E.Cause(err, "open existing adapter"))
			fcxLogDeviceStage("sing_tun.device.wintun_create", wintunCreateStartedAt, err)
			return nil, FCXWrapAdapterCreateError(err)
		}
	}
	fcxLogDeviceStage("sing_tun.device.wintun_create", wintunCreateStartedAt, nil)`

	const sessionAnchor = `	session, err := adapter.StartSession(0x800000)
	if err != nil {
		return nil, err
	}`
	const sessionReplacement = `	sessionStartedAt := fcxDeviceTimingStartFor("sing_tun.device.session_start")
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
	ipDnsStartedAt := fcxDeviceTimingStartFor("sing_tun.device.ip_dns_config")
	if err := func() error {
`
	const ipv4BlockAnchor = `	if len(t.options.Inet4Address) > 0 {
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
	}`
	const ipv4BlockReplacement = `	if len(t.options.Inet4Address) > 0 {
		ipv4StartedAt := fcxDeviceTimingStartFor("tun.ipv4_address_set")
		err := luid.SetIPAddressesForFamily(winipcfg.AddressFamily(windows.AF_INET), t.options.Inet4Address)
		fcxLogDeviceStage("tun.ipv4_address_set", ipv4StartedAt, err)
		if err != nil {
			return E.Cause(err, "set ipv4 address")
		}
		if t.options.AutoRoute && !t.options.EXP_DisableDNSHijack {
			dnsServers := common.Filter(t.options.DNSServers, netip.Addr.Is4)
			if len(dnsServers) == 0 && HasNextAddress(t.options.Inet4Address[0], 1) {
				dnsServers = []netip.Addr{t.options.Inet4Address[0].Addr().Next()}
			}
			if len(dnsServers) > 0 {
				ipv4DNSStartedAt := fcxDeviceTimingStartFor("tun.ipv4_dns_set")
				err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET), dnsServers, nil)
				fcxLogDeviceStage("tun.ipv4_dns_set", ipv4DNSStartedAt, err)
				if err != nil {
					return E.Cause(err, "set ipv4 dns")
				}
			}
		} else {
			ipv4DNSStartedAt := fcxDeviceTimingStartFor("tun.ipv4_dns_set")
			err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET), nil, nil)
			fcxLogDeviceStage("tun.ipv4_dns_set", ipv4DNSStartedAt, err)
			if err != nil {
				return E.Cause(err, "set ipv4 dns")
			}
		}
	}`

	const ipv6BlockAnchor = `	if len(t.options.Inet6Address) > 0 {
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
	}`
	const ipv6BlockReplacement = `	if len(t.options.Inet6Address) > 0 {
		ipv6AddrStartedAt := fcxDeviceTimingStartFor("tun.ipv6_address_set")
		err := luid.SetIPAddressesForFamily(winipcfg.AddressFamily(windows.AF_INET6), t.options.Inet6Address)
		fcxLogDeviceStage("tun.ipv6_address_set", ipv6AddrStartedAt, err)
		if err != nil {
			return E.Cause(err, "set ipv6 address")
		}
		if t.options.AutoRoute && !t.options.EXP_DisableDNSHijack {
			dnsServers := common.Filter(t.options.DNSServers, netip.Addr.Is6)
			if len(dnsServers) == 0 && HasNextAddress(t.options.Inet6Address[0], 1) {
				dnsServers = []netip.Addr{t.options.Inet6Address[0].Addr().Next()}
			}
			if len(dnsServers) > 0 {
				ipv6DNSStartedAt := fcxDeviceTimingStartFor("tun.ipv6_dns_set")
				err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET6), dnsServers, nil)
				fcxLogDeviceStage("tun.ipv6_dns_set", ipv6DNSStartedAt, err)
				if err != nil {
					return E.Cause(err, "set ipv6 dns")
				}
			}
		} else {
			ipv6DNSStartedAt := fcxDeviceTimingStartFor("tun.ipv6_dns_set")
			err = luid.SetDNS(winipcfg.AddressFamily(windows.AF_INET6), nil, nil)
			fcxLogDeviceStage("tun.ipv6_dns_set", ipv6DNSStartedAt, err)
			if err != nil {
				return E.Cause(err, "set ipv6 dns")
			}
		}
	}`

	const ipToRouteAnchor = `	if len(t.options.Inet4Address) > 0 || len(t.options.Inet6Address) > 0 {
		_ = luid.DisableDNSRegistration()
	}
	if t.options.AutoRoute {`
	const ipToRouteReplacement = `	if len(t.options.Inet4Address) > 0 || len(t.options.Inet6Address) > 0 {
		dnsRegistrationStartedAt := fcxDeviceTimingStartFor("tun.disable_dns_registration")
		dnsRegistrationErr := luid.DisableDNSRegistration()
		fcxLogDeviceStage("tun.disable_dns_registration", dnsRegistrationStartedAt, dnsRegistrationErr)
	}
	return nil
	}(); err != nil {
		fcxLogDeviceStage("sing_tun.device.ip_dns_config", ipDnsStartedAt, err)
		return err
	}
	fcxLogDeviceStage("sing_tun.device.ip_dns_config", ipDnsStartedAt, nil)
	routeStartedAt := fcxDeviceTimingStartFor("sing_tun.device.route_config")
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
		}
		err = windnsapi.FlushResolverCache()
		if err != nil {
			return err
		}`
	const routeLoopReplacement = `		routesAddStartedAt := fcxDeviceTimingStartFor("tun.routes_add")
		err = FCXAddAutoRoutes(routeRanges, gateway4, gateway6, luid.AddRoute, func(routeErr error) bool {
			return errors.Is(routeErr, windows.ERROR_OBJECT_ALREADY_EXISTS)
		})
		fcxLogDeviceStage("tun.routes_add", routesAddStartedAt, err)
		if err != nil {
			return err
		}
		dnsFlushStartedAt := fcxDeviceTimingStartFor("tun.dns_cache_flush")
		err = windnsapi.FlushResolverCache()
		fcxLogDeviceStage("tun.dns_cache_flush", dnsFlushStartedAt, err)
		if err != nil {
			return err
		}`

	const ipv4InterfaceAnchor = `		err = inetIf.Set()
		if err != nil {
			return E.Cause(err, "set ipv4 options")
		}`
	const ipv4InterfaceReplacement = `		ipv4IfStartedAt := fcxDeviceTimingStartFor("tun.ipv4_interface_set")
		err = inetIf.Set()
		fcxLogDeviceStage("tun.ipv4_interface_set", ipv4IfStartedAt, err)
		if err != nil {
			return E.Cause(err, "set ipv4 options")
		}`

	const routeToStrictAnchor = `		err = inet6If.Set()
		if err != nil {
			return E.Cause(err, "set ipv6 options")
		}
	}

	if t.options.AutoRoute && t.options.StrictRoute {`
	const routeToStrictReplacement = `		ipv6IfStartedAt := fcxDeviceTimingStartFor("tun.ipv6_interface_set")
		err = inet6If.Set()
		fcxLogDeviceStage("tun.ipv6_interface_set", ipv6IfStartedAt, err)
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
		strictRouteStartedAt := fcxDeviceTimingStartFor("sing_tun.device.strict_route")
		if err := func() error {`
	const routeRangesAnchor = `		routeRanges, err := t.options.BuildAutoRouteRanges(false)`
	const routeRangesReplacement = `		routeRangesStartedAt := fcxDeviceTimingStartFor("tun.route_ranges_build")
		routeRanges, err := t.options.BuildAutoRouteRanges(false)
		fcxLogDeviceStage("tun.route_ranges_build", routeRangesStartedAt, err)`
	const ipv4LookupAnchor = `		inetIf, err := luid.IPInterface(winipcfg.AddressFamily(windows.AF_INET))`
	const ipv4LookupReplacement = `		ipv4LookupStartedAt := fcxDeviceTimingStartFor("tun.ipv4_interface_lookup")
		inetIf, err := luid.IPInterface(winipcfg.AddressFamily(windows.AF_INET))
		fcxLogDeviceStage("tun.ipv4_interface_lookup", ipv4LookupStartedAt, err)`
	const ipv6LookupAnchor = `		inet6If, err := luid.IPInterface(winipcfg.AddressFamily(windows.AF_INET6))`
	const ipv6LookupReplacement = `		ipv6LookupStartedAt := fcxDeviceTimingStartFor("tun.ipv6_interface_lookup")
		inet6If, err := luid.IPInterface(winipcfg.AddressFamily(windows.AF_INET6))
		fcxLogDeviceStage("tun.ipv6_interface_lookup", ipv6LookupStartedAt, err)`

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
		{"ipv4_address_dns", ipv4BlockAnchor, ipv4BlockReplacement},
		{"ipv6_address_dns", ipv6BlockAnchor, ipv6BlockReplacement},
		{"ip_to_route", ipToRouteAnchor, ipToRouteReplacement},
		{"route_loop", routeLoopAnchor, routeLoopReplacement},
		{"route_ranges", routeRangesAnchor, routeRangesReplacement},
		{"ipv4_lookup", ipv4LookupAnchor, ipv4LookupReplacement},
		{"ipv6_lookup", ipv6LookupAnchor, ipv6LookupReplacement},
		{"ipv4_interface", ipv4InterfaceAnchor, ipv4InterfaceReplacement},
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

func patchSingTunStackGvisor(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "stack_gvisor.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const anchor = `	bufSize := 20 * 1024
	ipStack.SetTransportProtocolOption(tcp.ProtocolNumber, &tcpip.TCPReceiveBufferSizeRangeOption{
		Min:     1,
		Default: bufSize,
		Max:     bufSize,
	})
	ipStack.SetTransportProtocolOption(tcp.ProtocolNumber, &tcpip.TCPSendBufferSizeRangeOption{
		Min:     1,
		Default: bufSize,
		Max:     bufSize,
	})`
	const expanded = `	const (
		fcxTCPMinBuf     = 4 * 1024
		fcxTCPDefaultBuf = 256 * 1024
		fcxTCPMaxBuf     = 4 * 1024 * 1024
	)
	ipStack.SetTransportProtocolOption(tcp.ProtocolNumber, &tcpip.TCPReceiveBufferSizeRangeOption{
		Min:     fcxTCPMinBuf,
		Default: fcxTCPDefaultBuf,
		Max:     fcxTCPMaxBuf,
	})
	ipStack.SetTransportProtocolOption(tcp.ProtocolNumber, &tcpip.TCPSendBufferSizeRangeOption{
		Min:     fcxTCPMinBuf,
		Default: fcxTCPDefaultBuf,
		Max:     fcxTCPMaxBuf,
	})`
	if strings.Count(patched, anchor) != 1 {
		return nil, fmt.Errorf("upstream sing-tun stack_gvisor TCP buffer block changed")
	}
	patched = strings.Replace(patched, anchor, expanded, 1)
	return format.Source([]byte(patched))
}

func patchDNSPolicy(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "policy.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const ifaceAnchor = `type dnsPolicy interface {
	Match(domain string) []dnsClient
}`
	const ifaceReplacement = `type dnsPolicy interface {
	Match(domain string) []dnsClient
	ResetConnection()
}`
	const trieAnchor = `type domainTriePolicy struct {
	*trie.DomainTrie[[]dnsClient]
}`
	const trieReplacement = `type domainTriePolicy struct {
	*trie.DomainTrie[[]dnsClient]
	dnsClients []dnsClient
}

func (p domainTriePolicy) ResetConnection() {
	for _, c := range p.dnsClients {
		c.ResetConnection()
	}
}`
	const matcherTailAnchor = `func (p domainMatcherPolicy) Match(domain string) []dnsClient {
	if p.matcher.MatchDomain(domain) {
		return p.dnsClients
	}
	return nil
}`
	const matcherTailReplacement = `func (p domainMatcherPolicy) Match(domain string) []dnsClient {
	if p.matcher.MatchDomain(domain) {
		return p.dnsClients
	}
	return nil
}

func (p domainMatcherPolicy) ResetConnection() {
	for _, c := range p.dnsClients {
		c.ResetConnection()
	}
}`
	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"dnsPolicy", ifaceAnchor, ifaceReplacement},
		{"domainTriePolicy", trieAnchor, trieReplacement},
		{"domainMatcherPolicy", matcherTailAnchor, matcherTailReplacement},
	} {
		if strings.Count(patched, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream dns/policy.go %s block changed", pair.name)
		}
		patched = strings.Replace(patched, pair.anchor, pair.replacement, 1)
	}
	return format.Source([]byte(patched))
}

func patchDNSResolver(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "resolver.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const clearCacheAnchor = `func (r *Resolver) ClearCache() {
	if r != nil && r.cache != nil {
		r.cache.Clear()
	}
}`
	const clearCacheReplacement = `func (r *Resolver) ClearCache() {
	if r != nil {
		if r.cache != nil {
			r.cache.Clear()
		}
		if dr := r.defaultResolver; dr != nil {
			dr.ClearCache()
		}
	}
}`
	const resetAnchor = `func (r *Resolver) ResetConnection() {
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
}`
	const resetReplacement = `func (r *Resolver) ResetConnection() {
	if r != nil {
		for _, c := range r.main {
			c.ResetConnection()
		}
		for _, c := range r.fallback {
			c.ResetConnection()
		}
		for _, p := range r.policy {
			p.ResetConnection()
		}
		if dr := r.defaultResolver; dr != nil {
			dr.ResetConnection()
		}
	}
}`
	const makePolicyAnchor = `	makePolicy := func(policies []Policy) (dnsPolicies []dnsPolicy) {
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
	}`
	const makePolicyReplacement = `	makePolicy := func(policies []Policy) (dnsPolicies []dnsPolicy) {
		var triePolicy *trie.DomainTrie[[]dnsClient]
		var trieClients []dnsClient
		insertPolicy := func(policy dnsPolicy) {
			if triePolicy != nil {
				triePolicy.Optimize()
				dnsPolicies = append(dnsPolicies, domainTriePolicy{
					DomainTrie: triePolicy,
					dnsClients: trieClients,
				})
				triePolicy = nil
				trieClients = nil
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
				clients := cacheTransform(policy.NameServers)
				if err := triePolicy.Insert(policy.Domain, clients); err != nil {
					log.Warnln("[DNS] skip invalid nameserver policy: %s", err)
				} else {
					trieClients = append(trieClients, clients...)
				}
			}
		}
		insertPolicy(nil)
		return
	}`
	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"ClearCache", clearCacheAnchor, clearCacheReplacement},
		{"ResetConnection", resetAnchor, resetReplacement},
		{"makePolicy", makePolicyAnchor, makePolicyReplacement},
	} {
		if strings.Count(patched, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream dns/resolver.go %s block changed", pair.name)
		}
		patched = strings.Replace(patched, pair.anchor, pair.replacement, 1)
	}
	return format.Source([]byte(patched))
}

func patchDNSSystemCommon(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "system_common.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const resetAnchor = "func (c *systemClient) ResetConnection() {}"
	const resetReplacement = `func (c *systemClient) ResetConnection() {
	c.mu.Lock()
	c.lastFlush = time.Time{}
	clients := make([]dnsClient, 0, len(c.dnsClients)+len(c.defaultNS))
	for _, sdc := range c.dnsClients {
		if sdc != nil && sdc.dnsClient != nil {
			clients = append(clients, sdc.dnsClient)
		}
	}
	clients = append(clients, c.defaultNS...)
	c.mu.Unlock()
	for _, client := range clients {
		client.ResetConnection()
	}
}`
	if strings.Count(patched, resetAnchor) != 1 {
		return nil, fmt.Errorf("upstream dns/system_common.go ResetConnection changed")
	}
	patched = strings.Replace(patched, resetAnchor, resetReplacement, 1)
	return format.Source([]byte(patched))
}

func patchDNSDHCP(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "dhcp.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const resetAnchor = `func (d *dhcpClient) ResetConnection() {
	for _, client := range d.clients {
		client.ResetConnection()
	}
}`
	const resetReplacement = `func (d *dhcpClient) ResetConnection() {
	d.lock.Lock()
	d.ifaceInvalidate = time.Time{}
	d.dnsInvalidate = time.Time{}
	clients := append([]dnsClient(nil), d.clients...)
	d.lock.Unlock()
	for _, client := range clients {
		client.ResetConnection()
	}
}`
	if strings.Count(patched, resetAnchor) != 1 {
		return nil, fmt.Errorf("upstream dns/dhcp.go ResetConnection changed")
	}
	patched = strings.Replace(patched, resetAnchor, resetReplacement, 1)
	return format.Source([]byte(patched))
}

func patchDialerBindWindows(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "bind_windows.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const importAnchor = "\t\"net/netip\"\n\t\"syscall\""
	const importReplacement = "\t\"net/netip\"\n\t\"strings\"\n\t\"syscall\""
	const fnAnchor = `func bindIfaceToDialer(ifaceName string, dialer *net.Dialer, _ string, destination netip.Addr) error {
	ifaceObj, err := iface.ResolveInterface(ifaceName)
	if err != nil {
		return err
	}

	addControlToDialer(dialer, bindControl(ifaceObj.Index, netip.AddrPortFrom(destination, 0)))
	return nil
}`
	const fnReplacement = `func bindIfaceToDialer(ifaceName string, dialer *net.Dialer, network string, destination netip.Addr) error {
	ifaceObj, err := iface.ResolveInterface(ifaceName)
	if err != nil {
		return err
	}
	unmapped := destination.Unmap()
	if dialer.LocalAddr == nil && unmapped.IsGlobalUnicast() && (strings.HasPrefix(network, "tcp") || strings.HasPrefix(network, "udp")) {
		localAddr, err := LookupLocalAddrFromIfaceName(ifaceName, network, unmapped, 0)
		if err != nil {
			return err
		}
		dialer.LocalAddr = localAddr
	}

	addControlToDialer(dialer, bindControl(ifaceObj.Index, netip.AddrPortFrom(destination, 0)))
	return nil
}`
	if strings.Count(patched, importAnchor) != 1 || strings.Count(patched, fnAnchor) != 1 {
		return nil, fmt.Errorf("upstream component/dialer/bind_windows.go shape changed")
	}
	patched = strings.Replace(patched, importAnchor, importReplacement, 1)
	patched = strings.Replace(patched, fnAnchor, fnReplacement, 1)
	return format.Source([]byte(patched))
}

func patchURLTestGroup(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "urltest.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)

	const dialAnchor = `func (u *URLTest) DialContext(ctx context.Context, metadata *C.Metadata) (c C.Conn, err error) {
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
}`
	const dialReplacement = `func (u *URLTest) DialContext(ctx context.Context, metadata *C.Metadata) (c C.Conn, err error) {
	proxy := u.fast(true)
	c, err = proxy.DialContext(ctx, metadata)
	if err == nil {
		c.AppendToChains(u)
	} else {
		u.RecordDialErrorFCX(proxy.Name(), err, ctx, u.ResetFastCacheFCX)
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
	if err == nil && c != nil {
		c = u.WrapStableConnFCX(proxy.Name(), c, u.ResetFastCacheFCX)
	}

	return c, err
}`
	if strings.Count(patched, dialAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/urltest.go DialContext changed")
	}
	patched = strings.Replace(patched, dialAnchor, dialReplacement, 1)

	const listenPacketAnchor = `func (u *URLTest) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	proxy := u.fast(true)
	pc, err := proxy.ListenPacketContext(ctx, metadata)
	if err == nil {
		pc.AppendToChains(u)
	} else {
		u.onDialFailed(proxy.Type(), err, u.healthCheck)
	}

	return pc, err
}`
	const listenPacketReplacement = `func (u *URLTest) ListenPacketContext(ctx context.Context, metadata *C.Metadata) (C.PacketConn, error) {
	proxy := u.fast(true)
	pc, err := proxy.ListenPacketContext(ctx, metadata)
	if err == nil {
		pc.AppendToChains(u)
	} else {
		u.RecordDialErrorFCX(proxy.Name(), err, ctx, u.ResetFastCacheFCX)
		u.onDialFailed(proxy.Type(), err, u.healthCheck)
	}

	return pc, err
}`
	if strings.Count(patched, listenPacketAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/urltest.go ListenPacketContext changed")
	}
	patched = strings.Replace(patched, listenPacketAnchor, listenPacketReplacement, 1)

	const fastAnchor = `	elm, _, shared := u.fastSingle.Do(func() (C.Proxy, error) {
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
	})`
	const fastReplacement = `	elm, _, shared := u.fastSingle.Do(func() (C.Proxy, error) {
		u.LockFastMuFCX()
		defer u.UnlockFastMuFCX()
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
		fastAlive := fast.AliveForTestUrl(u.testUrl)
		minDelay := uint32(u.EffectiveDelayFCX(fast.Name(), fast.LastDelayForTestUrl(u.testUrl)))
		fastNotExist := u.fastNode == nil || fast.Name() != u.fastNode.Name()

		for _, proxy := range proxies[1:] {
			if u.fastNode != nil && proxy.Name() == u.fastNode.Name() {
				fastNotExist = false
			}

			if !proxy.AliveForTestUrl(u.testUrl) {
				continue
			}

			delay := uint32(u.EffectiveDelayFCX(proxy.Name(), proxy.LastDelayForTestUrl(u.testUrl)))
			if !fastAlive || delay < minDelay {
				fast = proxy
				fastAlive = true
				minDelay = delay
			}

		}
		// tolerance
		if u.fastNode == nil || fastNotExist || !u.fastNode.AliveForTestUrl(u.testUrl) || uint32(u.EffectiveDelayFCX(u.fastNode.Name(), u.fastNode.LastDelayForTestUrl(u.testUrl))) > uint32(u.EffectiveDelayFCX(fast.Name(), fast.LastDelayForTestUrl(u.testUrl)))+uint32(u.tolerance) {
			u.fastNode = fast
		}
		return u.fastNode, nil
	})`
	if strings.Count(patched, fastAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/urltest.go fast changed")
	}
	patched = strings.Replace(patched, fastAnchor, fastReplacement, 1)

	const forceSetAnchor = `func (u *URLTest) ForceSet(name string) {
	u.selected = name
	u.fastSingle.Reset()
}`
	const forceSetReplacement = `func (u *URLTest) ForceSet(name string) {
	u.LockFastMuFCX()
	u.selected = name
	u.UnlockFastMuFCX()
	u.fastSingle.Reset()
}

func (u *URLTest) ResetFastCacheFCX() {
	u.fastSingle.Reset()
}`
	if strings.Count(patched, forceSetAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/urltest.go ForceSet changed")
	}
	patched = strings.Replace(patched, forceSetAnchor, forceSetReplacement, 1)
	return format.Source([]byte(patched))
}

func patchOutboundGroupBase(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "groupbase.go", source, 0)
	if err != nil {
		return nil, err
	}
	patched := string(source)

	var structCloseOffset int
	structs := 0
	for _, declaration := range file.Decls {
		generic, ok := declaration.(*ast.GenDecl)
		if !ok || generic.Tok != token.TYPE {
			continue
		}
		for _, spec := range generic.Specs {
			typeSpec, ok := spec.(*ast.TypeSpec)
			if !ok || typeSpec.Name.Name != "GroupBase" {
				continue
			}
			structType, ok := typeSpec.Type.(*ast.StructType)
			if !ok || structType.Fields == nil || !structType.Fields.Closing.IsValid() {
				return nil, fmt.Errorf("upstream outboundgroup/groupbase.go GroupBase struct changed")
			}
			for _, field := range structType.Fields.List {
				for _, fieldName := range field.Names {
					if fieldName.Name == "fcxStability" {
						return nil, fmt.Errorf("upstream outboundgroup/groupbase.go GroupBase already has fcxStability")
					}
				}
			}
			structs++
			structCloseOffset = fset.Position(structType.Fields.Closing).Offset
		}
	}
	if structs != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/groupbase.go GroupBase struct changed")
	}

	var changes []replacement
	changes = append(changes, replacement{structCloseOffset, structCloseOffset, "\n\tfcxStability fcxStabilityTracker\n"})

	const dialFailedBlockAnchor = `		gb.failedTestMux.Lock()
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
		}`
	const dialFailedBlockReplacement = `		shouldTrigger := func() bool {
			gb.failedTestMux.Lock()
			defer gb.failedTestMux.Unlock()

			gb.failedTimes++
			if gb.failedTimes == 1 {
				log.Debugln("ProxyGroup: %s first failed", gb.Name())
				gb.failedTime = time.Now()
				return false
			}

			failedWindow := 3 * time.Duration(gb.testTimeout) * time.Millisecond
			if failedWindow < 30*time.Second {
				failedWindow = 30 * time.Second
			}
			if time.Since(gb.failedTime) > failedWindow {
				gb.failedTimes = 1
				gb.failedTime = time.Now()
				return false
			}

			log.Debugln("ProxyGroup: %s failed count: %d", gb.Name(), gb.failedTimes)
			if gb.failedTimes >= gb.maxFailedTimes {
				log.Warnln("because %s failed multiple times, activate health check", gb.Name())
				return true
			}
			return false
		}()
		if shouldTrigger {
			fn()
		}`
	dialFailedIdx := strings.Index(patched, dialFailedBlockAnchor)
	if dialFailedIdx < 0 || strings.Count(patched, dialFailedBlockAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/groupbase.go onDialFailed block changed")
	}
	changes = append(changes, replacement{dialFailedIdx, dialFailedIdx + len(dialFailedBlockAnchor), dialFailedBlockReplacement})

	const healthCheckResetAnchor = `	wg.Wait()
	gb.failedTesting.Store(false)
	gb.failedTimes = 0`
	const healthCheckResetReplacement = `	wg.Wait()
	gb.failedTesting.Store(false)
	gb.failedTestMux.Lock()
	gb.failedTimes = 0
	gb.failedTestMux.Unlock()`
	healthCheckIdx := strings.Index(patched, healthCheckResetAnchor)
	if healthCheckIdx < 0 || strings.Count(patched, healthCheckResetAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/groupbase.go healthCheck reset changed")
	}
	changes = append(changes, replacement{healthCheckIdx, healthCheckIdx + len(healthCheckResetAnchor), healthCheckResetReplacement})

	const dialSuccessAnchor = `func (gb *GroupBase) onDialSuccess() {
	if !gb.failedTesting.Load() {
		gb.failedTimes = 0
	}
}`
	const dialSuccessReplacement = `func (gb *GroupBase) onDialSuccess() {
	if !gb.failedTesting.Load() {
		gb.failedTestMux.Lock()
		gb.failedTimes = 0
		gb.failedTestMux.Unlock()
	}
}`
	dialSuccessIdx := strings.Index(patched, dialSuccessAnchor)
	if dialSuccessIdx < 0 || strings.Count(patched, dialSuccessAnchor) != 1 {
		return nil, fmt.Errorf("upstream outboundgroup/groupbase.go onDialSuccess changed")
	}
	changes = append(changes, replacement{dialSuccessIdx, dialSuccessIdx + len(dialSuccessAnchor), dialSuccessReplacement})

	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}

	return format.Source([]byte(patched))
}

func patchSingTunMonitorWindows(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "monitor_windows.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const structAnchor = `type networkUpdateMonitor struct {
	routeListener     *winipcfg.RouteChangeCallback
	interfaceListener *winipcfg.InterfaceChangeCallback
	errorHandler      E.Handler`
	const structReplacement = `type networkUpdateMonitor struct {
	routeListener     *winipcfg.RouteChangeCallback
	interfaceListener *winipcfg.InterfaceChangeCallback
	unicastListener   *winipcfg.UnicastAddressChangeCallback
	errorHandler      E.Handler`
	const startCloseAnchor = `	m.interfaceListener = interfaceListener
	return nil
}

func (m *networkUpdateMonitor) Close() error {
	if m.routeListener != nil {
		m.routeListener.Unregister()
		m.routeListener = nil
	}
	if m.interfaceListener != nil {
		m.interfaceListener.Unregister()
		m.interfaceListener = nil
	}
	return nil
}`
	const startCloseReplacement = `	m.interfaceListener = interfaceListener
	unicastListener, err := winipcfg.RegisterUnicastAddressChangeCallback(func(notificationType winipcfg.MibNotificationType, unicastAddress *winipcfg.MibUnicastIPAddressRow) {
		m.emit()
	})
	if err != nil {
		interfaceListener.Unregister()
		routeListener.Unregister()
		m.interfaceListener = nil
		m.routeListener = nil
		return err
	}
	m.unicastListener = unicastListener
	return nil
}

func (m *networkUpdateMonitor) Close() error {
	if m.routeListener != nil {
		m.routeListener.Unregister()
		m.routeListener = nil
	}
	if m.interfaceListener != nil {
		m.interfaceListener.Unregister()
		m.interfaceListener = nil
	}
	if m.unicastListener != nil {
		m.unicastListener.Unregister()
		m.unicastListener = nil
	}
	return nil
}`
	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"struct", structAnchor, structReplacement},
		{"start_close", startCloseAnchor, startCloseReplacement},
	} {
		if strings.Count(patched, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream sing-tun monitor_windows %s block changed", pair.name)
		}
		patched = strings.Replace(patched, pair.anchor, pair.replacement, 1)
	}
	return format.Source([]byte(patched))
}

func patchSingTunMonitorShared(source []byte) ([]byte, error) {
	source = bytes.ReplaceAll(source, []byte("\r\n"), []byte("\n"))
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "monitor_shared.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const structAnchor = `	networkMonitor        NetworkUpdateMonitor
	checkUpdateTimer      *time.Timer
	checkAccess           sync.Mutex`
	const structReplacement = `	networkMonitor        NetworkUpdateMonitor
	checkUpdateTimer      *time.Timer
	debounceBurstStart    time.Time
	debouncePending       bool
	closed                atomic.Bool
	checkAccess           sync.Mutex`
	const delayAnchor = `func (m *defaultInterfaceMonitor) delayCheckUpdate() {
	m.access.Lock()
	defer m.access.Unlock()
	if m.checkUpdateTimer == nil {
		m.checkUpdateTimer = time.AfterFunc(time.Second, m.postCheckUpdate)
	} else {
		m.checkUpdateTimer.Reset(time.Second)
	}
}`
	const delayReplacement = `const (
	fcxMonitorDebounceDelay = 250 * time.Millisecond
	fcxMonitorMaxBurstDelay = 1000 * time.Millisecond
)

func (m *defaultInterfaceMonitor) delayCheckUpdate() {
	m.access.Lock()
	defer m.access.Unlock()
	if m.closed.Load() {
		return
	}
	now := time.Now()
	if !m.debouncePending {
		m.debouncePending = true
		m.debounceBurstStart = now
		if m.checkUpdateTimer == nil {
			m.checkUpdateTimer = time.AfterFunc(fcxMonitorDebounceDelay, m.runScheduledCheckUpdate)
		} else {
			m.checkUpdateTimer.Reset(fcxMonitorDebounceDelay)
		}
		return
	}
	remaining := fcxMonitorMaxBurstDelay - now.Sub(m.debounceBurstStart)
	if remaining <= 0 {
		return
	}
	delay := fcxMonitorDebounceDelay
	if remaining < delay {
		delay = remaining
	}
	m.checkUpdateTimer.Reset(delay)
}

func (m *defaultInterfaceMonitor) runScheduledCheckUpdate() {
	m.access.Lock()
	if m.closed.Load() {
		m.debouncePending = false
		m.access.Unlock()
		return
	}
	m.debouncePending = false
	m.debounceBurstStart = time.Time{}
	m.access.Unlock()
	m.postCheckUpdate()
}`
	const closeAnchor = `func (m *defaultInterfaceMonitor) Close() error {
	if m.element != nil {
		m.networkMonitor.UnregisterCallback(m.element)
	}
	return nil
}`
	const closeReplacement = `func (m *defaultInterfaceMonitor) Close() error {
	m.closed.Store(true)
	m.access.Lock()
	if m.checkUpdateTimer != nil {
		m.checkUpdateTimer.Stop()
	}
	m.debouncePending = false
	m.access.Unlock()
	if m.element != nil {
		m.networkMonitor.UnregisterCallback(m.element)
	}
	return nil
}`
	for _, pair := range []struct {
		name, anchor, replacement string
	}{
		{"struct", structAnchor, structReplacement},
		{"delayCheckUpdate", delayAnchor, delayReplacement},
		{"Close", closeAnchor, closeReplacement},
	} {
		if strings.Count(patched, pair.anchor) != 1 {
			return nil, fmt.Errorf("upstream sing-tun monitor_shared %s block changed", pair.name)
		}
		patched = strings.Replace(patched, pair.anchor, pair.replacement, 1)
	}
	return format.Source([]byte(patched))
}

func patchMemConservative(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "memc.go", source, 0); err != nil {
		return nil, err
	}
	patched := string(source)
	const gcStmt = "\tdefer runtime.GC()\n"
	const runtimeImport = "\t\"runtime\"\n"
	if strings.Count(patched, gcStmt) != 2 || strings.Count(patched, runtimeImport) != 1 {
		return nil, fmt.Errorf("upstream memconservative runtime.GC shape changed")
	}
	patched = strings.ReplaceAll(patched, gcStmt, "")
	patched = strings.Replace(patched, runtimeImport, "", 1)
	return format.Source([]byte(patched))
}

func patchConfigGeoCleanup(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "config.go", source, 0)
	if err != nil {
		return nil, err
	}
	var parseFn *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok && fn.Recv == nil && fn.Name.Name == "ParseRawConfig" {
			if parseFn != nil {
				return nil, fmt.Errorf("duplicate ParseRawConfig function")
			}
			parseFn = fn
		}
	}
	if parseFn == nil {
		return nil, fmt.Errorf("upstream ParseRawConfig missing")
	}
	fnText := string(source[fset.Position(parseFn.Pos()).Offset:fset.Position(parseFn.End()).Offset])
	const anchor = "\trollback := temporaryUpdateGeneral(config.General)\n\tdefer rollback()\n"
	const withCleanup = "\trollback := temporaryUpdateGeneral(config.General)\n\tdefer rollback()\n\tdefer func() {\n\t\tgeodata.ClearGeoSiteCache()\n\t\tgeodata.ClearGeoIPCache()\n\t}()\n"
	if strings.Count(fnText, anchor) != 1 {
		return nil, fmt.Errorf("upstream ParseRawConfig rollback anchor changed")
	}
	fnText = strings.Replace(fnText, anchor, withCleanup, 1)
	patched := string(source[:fset.Position(parseFn.Pos()).Offset]) + fnText + string(source[fset.Position(parseFn.End()).Offset:])
	return format.Source([]byte(patched))
}

func patchCacheFile(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "cache.go", source, 0)
	if err != nil {
		return nil, err
	}
	var closeFn *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Name.Name != "Close" || fn.Recv == nil || len(fn.Recv.List) != 1 {
			continue
		}
		ptr, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
		if !ok {
			continue
		}
		ident, ok := ptr.X.(*ast.Ident)
		if ok && ident.Name == "CacheFile" {
			if closeFn != nil {
				return nil, fmt.Errorf("duplicate CacheFile.Close method")
			}
			closeFn = fn
		}
	}
	if closeFn == nil {
		return nil, fmt.Errorf("upstream CacheFile.Close method missing")
	}
	const replacementText = `func (c *CacheFile) Close() error {
	if c == nil || c.DB == nil {
		return nil
	}
	fcxCloseFakeIPCache(c.DB)
	return c.DB.Close()
}`
	patched := string(source[:fset.Position(closeFn.Pos()).Offset]) + replacementText + string(source[fset.Position(closeFn.End()).Offset:])
	return format.Source([]byte(patched))
}

func patchFakeIpStore(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "fakeip.go", source, 0)
	if err != nil {
		return nil, err
	}
	methods := map[string]string{
		"GetByHost": `func (c *FakeIpStore) GetByHost(host string) (ip netip.Addr, exist bool) {
	return c.fcxGetByHost(host)
}`,
		"PutByHost": `func (c *FakeIpStore) PutByHost(host string, ip netip.Addr) {
	c.fcxPutByHost(host, ip)
}`,
		"GetByIP": `func (c *FakeIpStore) GetByIP(ip netip.Addr) (host string, exist bool) {
	return c.fcxGetByIP(ip)
}`,
		"PutByIP": `func (c *FakeIpStore) PutByIP(ip netip.Addr, host string) {
	c.fcxPutByIP(ip, host)
}`,
		"DelByIP": `func (c *FakeIpStore) DelByIP(ip netip.Addr) {
	c.fcxDelByIP(ip)
}`,
		"FlushFakeIP": `func (c *FakeIpStore) FlushFakeIP() error {
	return c.fcxFlushFakeIP()
}`,
	}
	seen := map[string]bool{}
	var changes []replacement
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok {
			continue
		}
		text, wanted := methods[fn.Name.Name]
		if !wanted {
			continue
		}
		if seen[fn.Name.Name] || fn.Recv == nil || len(fn.Recv.List) != 1 {
			return nil, fmt.Errorf("upstream FakeIpStore method changed: %s", fn.Name.Name)
		}
		ptr, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
		if !ok {
			return nil, fmt.Errorf("upstream FakeIpStore receiver changed: %s", fn.Name.Name)
		}
		ident, ok := ptr.X.(*ast.Ident)
		if !ok || ident.Name != "FakeIpStore" {
			return nil, fmt.Errorf("upstream FakeIpStore receiver changed: %s", fn.Name.Name)
		}
		seen[fn.Name.Name] = true
		changes = append(changes, replacement{
			fset.Position(fn.Pos()).Offset,
			fset.Position(fn.End()).Offset,
			text,
		})
	}
	if len(changes) != len(methods) {
		return nil, fmt.Errorf("upstream FakeIpStore method set changed")
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	for _, unused := range []string{"\t\"github.com/metacubex/mihomo/log\"\n", "\t\"github.com/metacubex/bbolt\"\n"} {
		if strings.Count(patched, unused) != 1 {
			return nil, fmt.Errorf("upstream FakeIpStore import changed: %s", strings.TrimSpace(unused))
		}
		patched = strings.Replace(patched, unused, "", 1)
	}
	return format.Source([]byte(patched))
}

func patchProcessWindows(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "process_windows.go", source, 0)
	if err != nil {
		return nil, err
	}
	var findFn, tableFn, execFn *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Recv != nil {
			continue
		}
		switch fn.Name.Name {
		case "findProcessName":
			if findFn != nil {
				return nil, fmt.Errorf("duplicate findProcessName")
			}
			findFn = fn
		case "getTransportTable":
			if tableFn != nil {
				return nil, fmt.Errorf("duplicate getTransportTable")
			}
			tableFn = fn
		case "getExecPathFromPID":
			if execFn != nil {
				return nil, fmt.Errorf("duplicate getExecPathFromPID")
			}
			execFn = fn
		}
	}
	if findFn == nil || tableFn == nil || execFn == nil {
		return nil, fmt.Errorf("upstream process_windows functions changed")
	}
	findText := string(source[fset.Position(findFn.Pos()).Offset:fset.Position(findFn.End()).Offset])
	const tableCallAnchor = "\tbuf, err := getTransportTable(fn, family, class)\n\tif err != nil {\n\t\treturn 0, \"\", err\n\t}"
	const tableCallReplacement = "\tbuf, releaseTable, err := fcxAcquireTransportTable(fn, family, class)\n\tif err != nil {\n\t\treturn 0, \"\", err\n\t}\n\tdefer releaseTable()"
	const execCallAnchor = "\tpp, err := getExecPathFromPID(pid)\n"
	if strings.Count(findText, tableCallAnchor) != 1 || strings.Count(findText, execCallAnchor) != 1 {
		return nil, fmt.Errorf("upstream findProcessName lookup shape changed")
	}
	findText = strings.Replace(findText, tableCallAnchor, tableCallReplacement, 1)

	changes := []replacement{
		{fset.Position(findFn.Pos()).Offset, fset.Position(findFn.End()).Offset, findText},
		{
			fset.Position(tableFn.Pos()).Offset,
			fset.Position(tableFn.End()).Offset,
			`func getTransportTable(fn uintptr, family int, class int) ([]byte, error) {
	buf, release, err := fcxAcquireTransportTable(fn, family, class)
	if err != nil {
		return nil, err
	}
	copied := append([]byte(nil), buf...)
	release()
	return copied, nil
}`,
		},
		{
			fset.Position(execFn.Pos()).Offset,
			fset.Position(execFn.End()).Offset,
			`func getExecPathFromPID(pid uint32) (string, error) {
	return fcxGetExecPathFromPID(pid)
}`,
		},
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	return format.Source([]byte(patched))
}

func isFetcherMethod(fn *ast.FuncDecl) bool {
	if fn == nil || fn.Recv == nil || len(fn.Recv.List) != 1 {
		return false
	}
	ptr, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
	if !ok {
		return false
	}
	idx, ok := ptr.X.(*ast.IndexExpr)
	if !ok {
		return false
	}
	ident, ok := idx.X.(*ast.Ident)
	return ok && ident.Name == "Fetcher"
}

func patchResourceFetcher(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "fetcher.go", source, 0)
	if err != nil {
		return nil, err
	}
	methods := map[string]*ast.FuncDecl{}
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || !isFetcherMethod(fn) {
			continue
		}
		switch fn.Name.Name {
		case "UpdatedAt", "Initial", "Update", "SideUpdate", "pullLoop":
			if methods[fn.Name.Name] != nil {
				return nil, fmt.Errorf("duplicate Fetcher.%s method", fn.Name.Name)
			}
			methods[fn.Name.Name] = fn
		}
	}
	for _, name := range []string{"UpdatedAt", "Initial", "Update", "SideUpdate", "pullLoop"} {
		if methods[name] == nil {
			return nil, fmt.Errorf("upstream Fetcher.%s method missing", name)
		}
	}

	changes := []replacement{
		{
			fset.Position(methods["UpdatedAt"].Pos()).Offset,
			fset.Position(methods["UpdatedAt"].End()).Offset,
			`func (f *Fetcher[V]) UpdatedAt() time.Time {
	f.loadBufMutex.Lock()
	defer f.loadBufMutex.Unlock()
	return f.updatedAt
}`,
		},
		{
			fset.Position(methods["Update"].Pos()).Offset,
			fset.Position(methods["Update"].End()).Offset,
			`func (f *Fetcher[V]) Update() (V, bool, error) {
	buf, hash, err := f.vehicle.Read(f.ctx, f.currentHash())
	if err != nil {
		f.backoff.AddAttempt()
		return lo.Empty[V](), false, err
	}
	contents, same, err := f.loadBuf(buf, hash, f.vehicle.Type() != P.File)
	if err == nil && !same {
		fcxNotifyProviderUpdated(f.Name())
	}
	return contents, same, err
}`,
		},
		{
			fset.Position(methods["SideUpdate"].Pos()).Offset,
			fset.Position(methods["SideUpdate"].End()).Offset,
			`func (f *Fetcher[V]) SideUpdate(buf []byte) (V, bool, error) {
	contents, same, err := f.loadBuf(buf, utils.MakeHash(buf), true)
	if err == nil && !same {
		fcxNotifyProviderUpdated(f.Name())
	}
	return contents, same, err
}`,
		},
	}

	initialSrc := string(source[fset.Position(methods["Initial"].Pos()).Offset:fset.Position(methods["Initial"].End()).Offset])
	const modTimeAssign = "f.updatedAt = modTime"
	const remoteFallbackAnchor = "contents, _, updateErr := f.Update()"
	if strings.Count(initialSrc, modTimeAssign) != 2 || strings.Count(initialSrc, remoteFallbackAnchor) != 1 {
		return nil, fmt.Errorf("upstream Fetcher.Initial body changed")
	}
	patchedInitial := strings.ReplaceAll(initialSrc, modTimeAssign, "f.setUpdatedAt(modTime)")
	patchedInitial = strings.Replace(
		patchedInitial,
		remoteFallbackAnchor,
		`if f.vehicle.Type() != P.File {
		f.fcxStartInitialRemotePull()
		return lo.Empty[V](), nil
	}
	`+remoteFallbackAnchor,
		1,
	)
	changes = append(changes, replacement{
		fset.Position(methods["Initial"].Pos()).Offset,
		fset.Position(methods["Initial"].End()).Offset,
		patchedInitial,
	})

	pullLoopSrc := string(source[fset.Position(methods["pullLoop"].Pos()).Offset:fset.Position(methods["pullLoop"].End()).Offset])
	const pullUpdatedAtAnchor = "time.Since(f.updatedAt)"
	if strings.Count(pullLoopSrc, pullUpdatedAtAnchor) != 1 {
		return nil, fmt.Errorf("upstream Fetcher.pullLoop body changed")
	}
	changes = append(changes, replacement{
		fset.Position(methods["pullLoop"].Pos()).Offset,
		fset.Position(methods["pullLoop"].End()).Offset,
		strings.Replace(pullLoopSrc, pullUpdatedAtAnchor, "time.Since(f.UpdatedAt())", 1),
	})

	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	return format.Source([]byte(patched))
}

func patchRuleProvider(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "provider.go", source, 0); err != nil {
		return nil, err
	}
	patched := strings.ReplaceAll(string(source), "\r\n", "\n")
	rewrites := [][2]string{
		{
			"type baseProvider struct {\n\tbehavior P.RuleBehavior\n\tstrategy ruleStrategy\n}",
			"type baseProvider struct {\n\tbehavior P.RuleBehavior\n\tstrategy fcxAtomicRuleStrategy\n}",
		},
		{
			"func (bp *baseProvider) Count() int {\n\treturn bp.strategy.Count()\n}",
			"func (bp *baseProvider) Count() int {\n\ts := bp.strategy.load()\n\tif s == nil {\n\t\treturn 0\n\t}\n\treturn s.Count()\n}",
		},
		{
			"func (bp *baseProvider) Match(metadata *C.Metadata, helper C.RuleMatchHelper) bool {\n\treturn bp.strategy != nil && bp.strategy.Match(metadata, helper)\n}",
			"func (bp *baseProvider) Match(metadata *C.Metadata, helper C.RuleMatchHelper) bool {\n\ts := bp.strategy.load()\n\treturn s != nil && s.Match(metadata, helper)\n}",
		},
		{
			"func (bp *baseProvider) Strategy() any {\n\treturn bp.strategy\n}",
			"func (bp *baseProvider) Strategy() any {\n\treturn bp.strategy.load()\n}",
		},
		{
			"RuleCount:   rp.strategy.Count(),",
			"RuleCount:   rp.Count(),",
		},
		{
			"rp.strategy = strategy",
			"rp.strategy.store(strategy)",
		},
		{
			"\trp.strategy = newStrategy(behavior, parse)\n\tif len(payload) > 0 { // using as fallback rules\n\t\trp.strategy = rulesParseInline(payload, rp.strategy)\n\t}",
			"\tinitialStrategy := newStrategy(behavior, parse)\n\tif len(payload) > 0 { // using as fallback rules\n\t\tinitialStrategy = rulesParseInline(payload, initialStrategy)\n\t}\n\trp.strategy.store(initialStrategy)",
		},
		{
			"RuleCount:   i.strategy.Count(),",
			"RuleCount:   i.Count(),",
		},
		{
			"\t\tbaseProvider: baseProvider{\n\t\t\tbehavior: behavior,\n\t\t\tstrategy: newStrategy(behavior, parse),\n\t\t},\n\t\tpayload:  payload,\n\t\tname:     name,\n\t\tupdateAt: time.Now(),\n\t}\n\tip.strategy = rulesParseInline(payload, ip.strategy)",
			"\t\tbaseProvider: baseProvider{\n\t\t\tbehavior: behavior,\n\t\t},\n\t\tpayload:  payload,\n\t\tname:     name,\n\t\tupdateAt: time.Now(),\n\t}\n\tip.strategy.store(rulesParseInline(payload, newStrategy(behavior, parse)))",
		},
	}
	for _, rw := range rewrites {
		if strings.Count(patched, rw[0]) != 1 {
			return nil, fmt.Errorf("upstream rules/provider/provider.go shape changed around %q", rw[0])
		}
		patched = strings.Replace(patched, rw[0], rw[1], 1)
	}
	return format.Source([]byte(patched))
}

func patchProxyProvider(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	if _, err := parser.ParseFile(fset, "provider.go", source, 0); err != nil {
		return nil, err
	}
	patched := strings.ReplaceAll(string(source), "\r\n", "\n")
	rewrites := [][2]string{
		{
			"SubscriptionInfo: pp.subscriptionInfo,",
			"SubscriptionInfo: pp.getSubscriptionInfo(),",
		},
		{
			"pp.subscriptionInfo = NewSubscriptionInfo(subscriptionInfo)",
			"pp.setSubscriptionInfoIfNil(NewSubscriptionInfo(subscriptionInfo))",
		},
		{
			"pd.subscriptionInfo = NewSubscriptionInfo(subscriptionInfo)",
			"pd.setSubscriptionInfo(NewSubscriptionInfo(subscriptionInfo))",
		},
	}
	for _, rw := range rewrites {
		if strings.Count(patched, rw[0]) != 1 {
			return nil, fmt.Errorf("upstream adapter/provider/provider.go shape changed around %q", rw[0])
		}
		patched = strings.Replace(patched, rw[0], rw[1], 1)
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
	singTunServerWindowsSource, err := checkedSource(filepath.Join(module.Dir, "listener", "sing_tun", "server_windows.go"), singTunServerWindowsSHA256)
	if err != nil {
		return err
	}
	patchedSingTunServerWindows, err := patchSingTunServerWindows(singTunServerWindowsSource)
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
	singTunStackGvisorSource, err := checkedSource(filepath.Join(singTunModule.Dir, "stack_gvisor.go"), singTunStackGvisorSHA256)
	if err != nil {
		return err
	}
	patchedSingTunStackGvisor, err := patchSingTunStackGvisor(singTunStackGvisorSource)
	if err != nil {
		return err
	}
	cacheFileSource, err := checkedSource(filepath.Join(module.Dir, "component", "profile", "cachefile", "cache.go"), cacheFileSHA256)
	if err != nil {
		return err
	}
	patchedCacheFile, err := patchCacheFile(cacheFileSource)
	if err != nil {
		return err
	}
	fakeIpSource, err := checkedSource(filepath.Join(module.Dir, "component", "profile", "cachefile", "fakeip.go"), fakeIpSHA256)
	if err != nil {
		return err
	}
	patchedFakeIp, err := patchFakeIpStore(fakeIpSource)
	if err != nil {
		return err
	}
	processWindowsSource, err := checkedSource(filepath.Join(module.Dir, "component", "process", "process_windows.go"), processWindowsSHA256)
	if err != nil {
		return err
	}
	patchedProcessWindows, err := patchProcessWindows(processWindowsSource)
	if err != nil {
		return err
	}
	memcSource, err := checkedSource(filepath.Join(module.Dir, "component", "geodata", "memconservative", "memc.go"), memConservativeSHA256)
	if err != nil {
		return err
	}
	patchedMemc, err := patchMemConservative(memcSource)
	if err != nil {
		return err
	}
	configSource, err := checkedSource(filepath.Join(module.Dir, "config", "config.go"), configSHA256)
	if err != nil {
		return err
	}
	patchedConfig, err := patchConfigGeoCleanup(configSource)
	if err != nil {
		return err
	}
	fetcherSource, err := checkedSource(filepath.Join(module.Dir, "component", "resource", "fetcher.go"), fetcherSHA256)
	if err != nil {
		return err
	}
	patchedFetcher, err := patchResourceFetcher(fetcherSource)
	if err != nil {
		return err
	}
	ruleProviderSource, err := checkedSource(filepath.Join(module.Dir, "rules", "provider", "provider.go"), ruleProviderSHA256)
	if err != nil {
		return err
	}
	patchedRuleProvider, err := patchRuleProvider(ruleProviderSource)
	if err != nil {
		return err
	}
	proxyProviderSource, err := checkedSource(filepath.Join(module.Dir, "adapter", "provider", "provider.go"), proxyProviderSHA256)
	if err != nil {
		return err
	}
	patchedProxyProvider, err := patchProxyProvider(proxyProviderSource)
	if err != nil {
		return err
	}
	dnsPolicySource, err := checkedSource(filepath.Join(module.Dir, "dns", "policy.go"), dnsPolicySHA256)
	if err != nil {
		return err
	}
	patchedDNSPolicy, err := patchDNSPolicy(dnsPolicySource)
	if err != nil {
		return err
	}
	dnsResolverSource, err := checkedSource(filepath.Join(module.Dir, "dns", "resolver.go"), dnsResolverSHA256)
	if err != nil {
		return err
	}
	patchedDNSResolver, err := patchDNSResolver(dnsResolverSource)
	if err != nil {
		return err
	}
	dnsSystemCommonSource, err := checkedSource(filepath.Join(module.Dir, "dns", "system_common.go"), dnsSystemCommonSHA256)
	if err != nil {
		return err
	}
	patchedDNSSystemCommon, err := patchDNSSystemCommon(dnsSystemCommonSource)
	if err != nil {
		return err
	}
	dnsDHCPSource, err := checkedSource(filepath.Join(module.Dir, "dns", "dhcp.go"), dnsDHCPSHA256)
	if err != nil {
		return err
	}
	patchedDNSDHCP, err := patchDNSDHCP(dnsDHCPSource)
	if err != nil {
		return err
	}
	dialerBindWindowsSource, err := checkedSource(filepath.Join(module.Dir, "component", "dialer", "bind_windows.go"), dialerBindWindowsSHA256)
	if err != nil {
		return err
	}
	patchedDialerBindWindows, err := patchDialerBindWindows(dialerBindWindowsSource)
	if err != nil {
		return err
	}
	urlTestGroupSource, err := checkedSource(filepath.Join(module.Dir, "adapter", "outboundgroup", "urltest.go"), urlTestGroupSHA256)
	if err != nil {
		return err
	}
	patchedURLTestGroup, err := patchURLTestGroup(urlTestGroupSource)
	if err != nil {
		return err
	}
	groupBaseSource, err := checkedSource(filepath.Join(module.Dir, "adapter", "outboundgroup", "groupbase.go"), groupBaseSHA256)
	if err != nil {
		return err
	}
	patchedGroupBase, err := patchOutboundGroupBase(groupBaseSource)
	if err != nil {
		return err
	}
	singTunMonitorWindowsSource, err := checkedSource(filepath.Join(singTunModule.Dir, "monitor_windows.go"), singTunMonitorWindowsSHA256)
	if err != nil {
		return err
	}
	patchedSingTunMonitorWindows, err := patchSingTunMonitorWindows(singTunMonitorWindowsSource)
	if err != nil {
		return err
	}
	singTunMonitorSharedSource, err := checkedSource(filepath.Join(singTunModule.Dir, "monitor_shared.go"), singTunMonitorSharedSHA256)
	if err != nil {
		return err
	}
	patchedSingTunMonitorShared, err := patchSingTunMonitorShared(singTunMonitorSharedSource)
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
	defer os.RemoveAll(stagingDirectory)
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
	defer os.RemoveAll(singTunStagingDirectory)
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
	if err := write(filepath.Join(sourceDirectory, "dns", "policy.go"), "dns_policy.go", patchedDNSPolicy); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "dns", "resolver.go"), "dns_resolver.go", patchedDNSResolver); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "dns", "system_common.go"), "dns_system_common.go", patchedDNSSystemCommon); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "dns", "dhcp.go"), "dns_dhcp.go", patchedDNSDHCP); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "component", "dialer", "bind_windows.go"), "dialer_bind_windows.go", patchedDialerBindWindows); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "adapter", "outboundgroup", "urltest.go"), "outboundgroup_urltest.go", patchedURLTestGroup); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "adapter", "outboundgroup", "groupbase.go"), "outboundgroup_groupbase.go", patchedGroupBase); err != nil {
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
	if err := write(filepath.Join(sourceDirectory, "listener", "sing_tun", "server_windows.go"), "sing_tun_server_windows.go", patchedSingTunServerWindows); err != nil {
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
	dialerBindWindowsTest, err := patchFiles.ReadFile("patches/dialer_bind_windows_fcx_test.go.txt")
	if err != nil {
		return err
	}
	dialerBindWindowsTest, err = format.Source(dialerBindWindowsTest)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "component", "dialer", "dialer_bind_windows_fcx_test.go"), "dialer_bind_windows_fcx_test.go", dialerBindWindowsTest); err != nil {
		return err
	}
	for _, name := range []string{"sing_tun_timing_fcx.go", "sing_tun_timing_sink_windows.go", "sing_tun_timing_sink_unix.go", "sing_tun_timing_fcx_test.go"} {
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
	if err := write(filepath.Join(singTunSourceDirectory, "monitor_windows.go"), "sing_tun_monitor_windows.go", patchedSingTunMonitorWindows); err != nil {
		return err
	}
	if err := write(filepath.Join(singTunSourceDirectory, "monitor_shared.go"), "sing_tun_monitor_shared.go", patchedSingTunMonitorShared); err != nil {
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
	singTunMonitorTest, err := patchFiles.ReadFile("patches/sing_tun_monitor_fcx_test.go.txt")
	if err != nil {
		return err
	}
	singTunMonitorTest, err = format.Source(singTunMonitorTest)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "listener", "sing_tun", "sing_tun_monitor_fcx_test.go"), "sing_tun_monitor_fcx_test.go", singTunMonitorTest); err != nil {
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
	groupBaseTest, err := patchFiles.ReadFile("patches/outboundgroup_groupbase_fcx_test.go.txt")
	if err != nil {
		return err
	}
	groupBaseTest, err = format.Source(groupBaseTest)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "adapter", "outboundgroup", "groupbase_fcx_test.go"), "outboundgroup_groupbase_fcx_test.go", groupBaseTest); err != nil {
		return err
	}
	for _, spec := range []struct {
		patchFile string
		destFile  string
	}{
		{"patches/outboundgroup_stability_fcx.go.txt", "stability_fcx.go"},
	} {
		contents, err := patchFiles.ReadFile(spec.patchFile)
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "adapter", "outboundgroup", spec.destFile), spec.destFile, contents); err != nil {
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
	if err := write(filepath.Join(singTunSourceDirectory, "stack_gvisor.go"), "sing_tun_stack_gvisor.go", patchedSingTunStackGvisor); err != nil {
		return err
	}
	singTunGvisorTest, err := patchFiles.ReadFile("patches/sing_tun_gvisor_window_fcx_test.go.txt")
	if err != nil {
		return err
	}
	singTunGvisorTest, err = format.Source(singTunGvisorTest)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "listener", "sing_tun", "sing_tun_gvisor_window_fcx_test.go"), "sing_tun_gvisor_window_fcx_test.go", singTunGvisorTest); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "component", "profile", "cachefile", "cache.go"), "cachefile_cache.go", patchedCacheFile); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "component", "profile", "cachefile", "fakeip.go"), "cachefile_fakeip.go", patchedFakeIp); err != nil {
		return err
	}
	for _, name := range []string{"fakeip_cache_fcx.go", "fakeip_cache_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "component", "profile", "cachefile", name), name, contents); err != nil {
			return err
		}
	}
	if err := write(filepath.Join(sourceDirectory, "component", "process", "process_windows.go"), "process_windows.go", patchedProcessWindows); err != nil {
		return err
	}
	for _, name := range []string{"process_windows_fcx.go", "process_windows_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "component", "process", name), name, contents); err != nil {
			return err
		}
	}
	if err := write(filepath.Join(sourceDirectory, "component", "geodata", "memconservative", "memc.go"), "geodata_memc.go", patchedMemc); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "config", "config.go"), "config.go", patchedConfig); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "component", "resource", "fetcher.go"), "resource_fetcher.go", patchedFetcher); err != nil {
		return err
	}
	for _, name := range []string{"fetcher_fcx.go", "fetcher_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "component", "resource", name), name, contents); err != nil {
			return err
		}
	}
	if err := write(filepath.Join(sourceDirectory, "rules", "provider", "provider.go"), "rule_provider.go", patchedRuleProvider); err != nil {
		return err
	}
	ruleProviderHelper, err := patchFiles.ReadFile("patches/rule_provider_fcx.go.txt")
	if err != nil {
		return err
	}
	ruleProviderHelper, err = format.Source(ruleProviderHelper)
	if err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "rules", "provider", "rule_provider_fcx.go"), "rule_provider_fcx.go", ruleProviderHelper); err != nil {
		return err
	}
	if err := write(filepath.Join(sourceDirectory, "adapter", "provider", "provider.go"), "proxy_provider.go", patchedProxyProvider); err != nil {
		return err
	}
	for _, sidecar := range []struct {
		relDir   string
		destFile string
		patchTxt string
	}{
		{"component/pool", "pool_fcx.go", "patches/pool_fcx.go.txt"},
		{"transport/snell", "snell_pool_fcx.go", "patches/snell_pool_fcx.go.txt"},
		{"transport/tuic", "tuic_pool_client_fcx.go", "patches/tuic_pool_client_fcx.go.txt"},
		{"transport/anytls/session", "anytls_session_client_fcx.go", "patches/anytls_session_client_fcx.go.txt"},
		{"transport/anytls", "anytls_client_fcx.go", "patches/anytls_client_fcx.go.txt"},
		{"transport/xhttp", "xhttp_client_fcx.go", "patches/xhttp_client_fcx.go.txt"},
		{"transport/hysteria/core", "hysteria_client_fcx.go", "patches/hysteria_client_fcx.go.txt"},
		{"transport/shadowquic", "shadowquic_client_fcx.go", "patches/shadowquic_client_fcx.go.txt"},
		{"adapter/outbound", "outbound_reset_fcx.go", "patches/outbound_reset_fcx.go.txt"},
		{"adapter/outbound", "outbound_reset_fcx_test.go", "patches/outbound_reset_fcx_test.go.txt"},
	} {
		contents, err := patchFiles.ReadFile(sidecar.patchTxt)
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return fmt.Errorf("format %s: %w", sidecar.patchTxt, err)
		}
		if err := write(filepath.Join(sourceDirectory, filepath.FromSlash(sidecar.relDir), sidecar.destFile), sidecar.destFile, contents); err != nil {
			return err
		}
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
		"upstreamSourceSHA256": map[string]string{
			"listener/listener.go":                      listenerSHA256,
			"listener/sing_tun/server.go":               singTunServerSHA256,
			"listener/sing_tun/server_windows.go":       singTunServerWindowsSHA256,
			"component/iface/iface.go":                  ifaceSHA256,
			"component/dialer/bind_windows.go":          dialerBindWindowsSHA256,
			"component/profile/cachefile/cache.go":      cacheFileSHA256,
			"component/profile/cachefile/fakeip.go":     fakeIpSHA256,
			"component/process/process_windows.go":      processWindowsSHA256,
			"component/geodata/memconservative/memc.go": memConservativeSHA256,
			"component/resource/fetcher.go":             fetcherSHA256,
			"rules/provider/provider.go":                ruleProviderSHA256,
			"adapter/provider/provider.go":              proxyProviderSHA256,
			"adapter/outboundgroup/urltest.go":          urlTestGroupSHA256,
			"adapter/outboundgroup/groupbase.go":        groupBaseSHA256,
			"config/config.go":                          configSHA256,
			"hub/route/configs.go":                      configsSHA256,
			"hub/route/server.go":                       controllerSHA256,
			"adapter/adapter.go":                        adapterSHA256,
			"dns/doh.go":                                dnsDoHSHA256,
			"dns/policy.go":                             dnsPolicySHA256,
			"dns/resolver.go":                           dnsResolverSHA256,
			"dns/system_common.go":                      dnsSystemCommonSHA256,
			"dns/dhcp.go":                               dnsDHCPSHA256,
			"common/convert/converter.go":               converterSHA256,
		},
		"singTunOverlay": map[string]any{
			"module":    "github.com/metacubex/sing-tun",
			"version":   singTunVersion,
			"moduleSum": singTunModule.Sum,
			"upstreamSourceSHA256": map[string]string{
				"tun_windows.go":     singTunWindowsSHA256,
				"stack_gvisor.go":    singTunStackGvisorSHA256,
				"monitor_windows.go": singTunMonitorWindowsSHA256,
				"monitor_shared.go":  singTunMonitorSharedSHA256,
			},
			"effectiveModuleSHA256": aggregateHashes(singTunModuleHashes),
		},
		"patchesSHA256": patchHashes, "generatorSHA256": digest(generatorSource), "projectGoModSHA256": digest(rootMod),
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
