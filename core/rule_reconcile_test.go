package main

import (
	"net/netip"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	T "github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type ruleReconcileTestTracker struct {
	statistic.Tracker
	id     string
	info   *statistic.TrackerInfo
	closed atomic.Bool
}

func newRuleReconcileTestTracker(t *testing.T, id string, metadata C.Metadata, chain C.Chain) *ruleReconcileTestTracker {
	t.Helper()
	metaCopy := metadata
	tr := &ruleReconcileTestTracker{
		id: id,
		info: &statistic.TrackerInfo{
			Metadata: &metaCopy,
			Chain:    chain,
		},
	}
	statistic.DefaultManager.Join(tr)
	t.Cleanup(func() {
		statistic.DefaultManager.Leave(tr)
	})
	return tr
}

func (tr *ruleReconcileTestTracker) ID() string {
	return tr.id
}

func (tr *ruleReconcileTestTracker) Info() *statistic.TrackerInfo {
	return tr.info
}

func (tr *ruleReconcileTestTracker) Chains() C.Chain {
	return tr.info.Chain
}

func (tr *ruleReconcileTestTracker) Close() error {
	tr.closed.Store(true)
	statistic.DefaultManager.Leave(tr)
	return nil
}

func minimalProxySetupParams(rules []string) *SetupParams {
	params := defaultSetupParams()
	params.Config.Mode = T.Rule
	params.Config.Proxy = []map[string]any{
		{
			"name":     "node-1",
			"type":     "socks5",
			"server":   "127.0.0.1",
			"port":     1080,
			"udp":      true,
			"skip-cert-verify": true,
		},
	}
	params.Config.ProxyGroup = []map[string]any{
		{
			"name":    "PROXY",
			"type":    "select",
			"proxies": []string{"node-1", "DIRECT"},
		},
	}
	params.Config.Rule = rules
	return params
}

func TestSetupConfigSurgicallyEvictsConnectionsWhoseRuleTargetChangedWhilePreservingUnchangedProxyConnections(t *testing.T) {
	isolateConfigRuntime(t)

	initial := minimalProxySetupParams([]string{
		"MATCH,PROXY",
	})
	if err := setupConfig(initial); err != nil {
		t.Fatalf("initial setupConfig failed: %v", err)
	}

	baiduMiao := newRuleReconcileTestTracker(
		t,
		"reconcile-baidu-miao",
		C.Metadata{Host: "miao.baidu.com", DstPort: 443, NetWork: C.TCP},
		C.Chain{"node-1", "PROXY"},
	)
	baiduCloud := newRuleReconcileTestTracker(
		t,
		"reconcile-baidu-cloud",
		C.Metadata{Host: "cloud.baidu.com", DstPort: 443, NetWork: C.TCP},
		C.Chain{"node-1", "PROXY"},
	)
	githubProxy := newRuleReconcileTestTracker(
		t,
		"reconcile-github-proxy",
		C.Metadata{Host: "github.com", DstPort: 443, NetWork: C.TCP},
		C.Chain{"node-1", "PROXY"},
	)

	updated := minimalProxySetupParams([]string{
		"DOMAIN-SUFFIX,baidu.com,DIRECT",
		"MATCH,PROXY",
	})
	if err := setupConfig(updated); err != nil {
		t.Fatalf("updated setupConfig failed: %v", err)
	}

	if !baiduMiao.closed.Load() {
		t.Error("expected pooled miao.baidu.com PROXY connection to be closed after rule changed to DIRECT")
	}
	if !baiduCloud.closed.Load() {
		t.Error("expected pooled cloud.baidu.com PROXY connection to be closed after rule changed to DIRECT")
	}
	if githubProxy.closed.Load() {
		t.Error("expected github.com PROXY connection whose routing target remained PROXY to stay open")
	}
}

func TestSetupConfigEvictsAmbiguousFakeIPConnectionWhenNewIPRuleRequiresResolution(t *testing.T) {
	isolateConfigRuntime(t)

	initial := minimalProxySetupParams([]string{
		"MATCH,PROXY",
	})
	initial.Config.DNS = config.RawDNS{
		Enable:            true,
		EnhancedMode:      C.DNSFakeIP,
		FakeIPRange:       "198.18.0.1/16",
		DefaultNameserver: []string{"114.114.114.114"},
		NameServer:        []string{"114.114.114.114"},
	}
	if err := setupConfig(initial); err != nil {
		t.Fatalf("initial setupConfig failed: %v", err)
	}

	// Unlisted domestic domain that previously hit MATCH,PROXY with only Fake-IP DstIP.
	unlistedFakeIP := newRuleReconcileTestTracker(
		t,
		"reconcile-unlisted-fakeip",
		C.Metadata{
			Host:    "unlisted-enterprise.example",
			DstIP:   netip.MustParseAddr("198.18.0.42"),
			DstPort: 443,
			NetWork: C.TCP,
		},
		C.Chain{"node-1", "PROXY"},
	)
	// Known foreign domain matched before the IP rule via DOMAIN-SUFFIX -> PROXY.
	knownForeign := newRuleReconcileTestTracker(
		t,
		"reconcile-known-foreign",
		C.Metadata{
			Host:    "api.openai.com",
			DstIP:   netip.MustParseAddr("198.18.0.43"),
			DstPort: 443,
			NetWork: C.TCP,
		},
		C.Chain{"node-1", "PROXY"},
	)

	updated := minimalProxySetupParams([]string{
		"DOMAIN-SUFFIX,openai.com,PROXY",
		"IP-CIDR,223.5.5.0/24,DIRECT",
		"MATCH,PROXY",
	})
	updated.Config.DNS = initial.Config.DNS
	if err := setupConfig(updated); err != nil {
		t.Fatalf("updated setupConfig failed: %v", err)
	}

	if !unlistedFakeIP.closed.Load() {
		t.Error("expected unresolved Fake-IP connection reaching an IP-resolving rule to be evicted cleanly")
	}
	if knownForeign.closed.Load() {
		t.Error("expected api.openai.com connection matched by earlier domain rule to remain open")
	}
}

func TestSetupConfigEvictsPerAppProcessPathChangedConnectionsOnly(t *testing.T) {
	isolateConfigRuntime(t)

	initial := minimalProxySetupParams([]string{
		"MATCH,PROXY",
	})
	if err := setupConfig(initial); err != nil {
		t.Fatalf("initial setupConfig failed: %v", err)
	}

	chromeTracker := newRuleReconcileTestTracker(
		t,
		"reconcile-chrome-proc",
		C.Metadata{
			Host:        "example.org",
			DstPort:     443,
			NetWork:     C.TCP,
			ProcessPath: `C:\Program Files\Google\Chrome\Application\chrome.exe`,
		},
		C.Chain{"node-1", "PROXY"},
	)
	gitTracker := newRuleReconcileTestTracker(
		t,
		"reconcile-git-proc",
		C.Metadata{
			Host:        "example.org",
			DstPort:     443,
			NetWork:     C.TCP,
			ProcessPath: `C:\Program Files\Git\bin\git.exe`,
		},
		C.Chain{"node-1", "PROXY"},
	)

	updated := minimalProxySetupParams([]string{
		`PROCESS-PATH,C:\Program Files\Google\Chrome\Application\chrome.exe,DIRECT`,
		"MATCH,PROXY",
	})
	if err := setupConfig(updated); err != nil {
		t.Fatalf("updated setupConfig failed: %v", err)
	}

	if !chromeTracker.closed.Load() {
		t.Error("expected chrome.exe connection to be closed when per-app policy switched it to DIRECT")
	}
	if gitTracker.closed.Load() {
		t.Error("expected git.exe connection to remain open when only chrome.exe changed")
	}
}

func TestUpdateConfigModeSwitchReconcilesActiveConnections(t *testing.T) {
	isolateConfigRuntime(t)

	initial := minimalProxySetupParams([]string{
		"DOMAIN-SUFFIX,baidu.com,DIRECT",
		"MATCH,PROXY",
	})
	if err := setupConfig(initial); err != nil {
		t.Fatalf("initial setupConfig failed: %v", err)
	}

	baiduDirect := newRuleReconcileTestTracker(
		t,
		"reconcile-mode-baidu",
		C.Metadata{Host: "www.baidu.com", DstPort: 443, NetWork: C.TCP},
		C.Chain{"DIRECT"},
	)
	githubProxy := newRuleReconcileTestTracker(
		t,
		"reconcile-mode-github",
		C.Metadata{Host: "github.com", DstPort: 443, NetWork: C.TCP},
		C.Chain{"node-1", "PROXY"},
	)

	directMode := T.Direct
	if err := updateConfig(&UpdateParams{Mode: &directMode}); err != nil {
		t.Fatalf("updateConfig Mode=Direct failed: %v", err)
	}

	if !githubProxy.closed.Load() {
		t.Error("expected github.com PROXY connection to be closed when switching Mode to Direct")
	}
	if baiduDirect.closed.Load() {
		t.Error("expected www.baidu.com DIRECT connection to stay open when switching Mode to Direct")
	}
}


func TestBundledGeoDataBareProfileSplitRoutesBaiduDirectAndForeignProxyWithoutDNSLeak(t *testing.T) {
	isolateConfigRuntime(t)

	assetsDir, err := filepath.Abs(filepath.Join("..", "assets", "data"))
	if err != nil {
		t.Fatalf("resolve assets/data failed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(assetsDir, "GeoSite.dat")); err != nil {
		t.Skipf("bundled GeoSite.dat unavailable: %v", err)
	}
	if _, err := os.Stat(filepath.Join(assetsDir, "geoip.metadb")); err != nil {
		t.Skipf("bundled geoip.metadb unavailable: %v", err)
	}

	prevHome := C.Path.HomeDir()
	prevLoader := geodata.LoaderName()
	C.SetHomeDir(assetsDir)
	t.Cleanup(func() {
		C.SetHomeDir(prevHome)
		geodata.SetLoader(prevLoader)
	})

	params := minimalProxySetupParams([]string{
		"IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
		"IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
		"GEOSITE,private,DIRECT",
		"GEOSITE,cn,DIRECT",
		"GEOSITE,geolocation-!cn,PROXY",
		"GEOIP,CN,DIRECT",
		"MATCH,PROXY",
	})
	params.Config.GeodataLoader = "memconservative"
	if err := setupConfig(params); err != nil {
		t.Fatalf("setupConfig with bundled GeoSite.dat + geoip.metadb failed: %v", err)
	}

	parsed := currentConfig
	if parsed == nil {
		t.Fatal("expected currentConfig to be populated")
	}

	// Every Baidu subdomain from the user's screenshot must hit GEOSITE,cn,DIRECT
	// in 0ms without triggering any IP resolution even under Fake-IP dstIP.
	baiduDomains := []string{
		"baidu.com",
		"www.baidu.com",
		"miao.baidu.com",
		"cloud.baidu.com",
		"fclog.baidu.com",
		"dlswbr.baidu.com",
		"fxgate.baidu.com",
		"bce.baidu.com",
	}
	for _, host := range baiduDomains {
		target, ambiguous := evaluateTopLevelTarget(parsed, &C.Metadata{
			Host:    host,
			DstIP:   netip.MustParseAddr("198.18.0.55"),
			DstPort: 443,
			NetWork: C.TCP,
		})
		if ambiguous {
			t.Errorf("host %s unexpectedly triggered DNS ResolveIP", host)
		}
		if target != "DIRECT" {
			t.Errorf("host %s matched %q, want DIRECT", host, target)
		}
	}

	// Known foreign domains must hit GEOSITE,geolocation-!cn,PROXY BEFORE GEOIP,CN,DIRECT,
	// so Fake-IP connections never leak local DNS queries!
	for _, foreign := range []string{"github.com", "www.google.com"} {
		target, ambiguous := evaluateTopLevelTarget(parsed, &C.Metadata{
			Host:    foreign,
			DstIP:   netip.MustParseAddr("198.18.0.88"),
			DstPort: 443,
			NetWork: C.TCP,
		})
		if ambiguous {
			t.Errorf("foreign host %s unexpectedly triggered local DNS ResolveIP before geolocation-!cn", foreign)
		}
		if target != "PROXY" {
			t.Errorf("foreign host %s matched %q, want PROXY", foreign, target)
		}
	}

	// Direct IP connection to a domestic IP (e.g. 223.5.5.5) hits GEOIP,CN,DIRECT without DNS.
	cnIPTarget, cnIPAmbiguous := evaluateTopLevelTarget(parsed, &C.Metadata{
		DstIP:   netip.MustParseAddr("223.5.5.5"),
		DstPort: 443,
		NetWork: C.TCP,
	})
	if cnIPAmbiguous || cnIPTarget != "DIRECT" {
		t.Errorf("223.5.5.5 matched (%q, ambiguous=%v), want (DIRECT, false)", cnIPTarget, cnIPAmbiguous)
	}
}
