package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/constant"
)

const (
	maxCatalogs     = 3
	maxCatalogNodes = 2000
	catalogIdleTTL  = 10 * time.Minute
)

type catalogOwner struct {
	id     uint64
	closed bool // catalogMu
}

type catalogKey struct {
	owner *catalogOwner
	id    string
}
type catalogEntry struct {
	key                         catalogKey
	nodes                       []catalogNode
	proxies                     []constant.Proxy
	lastUsed                    time.Time
	refs                        int
	building, retired, disposed bool
	timer                       *time.Timer
}

type catalogNode struct {
	Index     int    `json:"index"`
	Name      string `json:"name"`
	Type      string `json:"type"`
	Server    string `json:"server"`
	Port      int    `json:"port"`
	Supported bool   `json:"supported"`
	Reason    string `json:"reason"`
}
type catalogProvider struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	Count  int    `json:"count"`
}
type catalogPrepareParams struct {
	ID        string            `json:"catalog-id"`
	Proxies   []json.RawMessage `json:"proxies"`
	Providers []struct {
		Name string `json:"name"`
		Path string `json:"path"`
	} `json:"providers"`
}
type catalogPrepareResponse struct {
	ID        string            `json:"catalog-id"`
	Nodes     []catalogNode     `json:"nodes"`
	Providers []catalogProvider `json:"providers"`
}
type catalogDelayParams struct {
	ID        string `json:"catalog-id"`
	Index     *int   `json:"index"`
	RequestID string `json:"request-id"`
	TestURL   string `json:"test-url"`
	Timeout   int64  `json:"timeout"`
}

var (
	catalogMu sync.RWMutex
	catalogs  = map[catalogKey]*catalogEntry{}
	// Includes building and retired entries awaiting their last test reference.
	catalogResourceCount int
	catalogStrictBlocked bool
	catalogStopped       bool
	catalogOwnerSequence atomic.Uint64
	catalogIDPattern     = regexp.MustCompile(`^c-[A-Za-z0-9-]{8,64}$`)
	catalogPathMu        sync.RWMutex
	parseCatalogProxy    = func(mapping map[string]any) (constant.Proxy, error) { return adapter.ParseProxy(mapping) }
)

func newCatalogOwner() *catalogOwner { return &catalogOwner{id: catalogOwnerSequence.Add(1)} }

func catalogText(value any, limit int) string {
	text, ok := value.(string)
	if !ok || len(text) > limit || strings.IndexFunc(text, unicode.IsControl) >= 0 {
		return ""
	}
	return text
}

func catalogPort(value any) int {
	var port int
	switch value := value.(type) {
	case float64:
		if value != float64(int(value)) {
			return 0
		}
		port = int(value)
	case string:
		port, _ = strconv.Atoi(value)
	}
	if port < 1 || port > 65535 {
		return 0
	}
	return port
}

func parseCatalogNode(index int, raw json.RawMessage) (catalogNode, constant.Proxy) {
	node := catalogNode{Index: index, Reason: "parseFailed"}
	var mapping map[string]any
	if json.Unmarshal(raw, &mapping) != nil || mapping == nil {
		return node, nil
	}
	node.Name = catalogText(mapping["name"], 1024)
	node.Type = catalogText(mapping["type"], 64)
	node.Server = catalogText(mapping["server"], 1024)
	node.Port = catalogPort(mapping["port"])
	hasMux, hasRetainedTransport := false, false
	for key, value := range mapping {
		// Match the decoder's case-insensitive underscore/hyphen aliases too.
		if strings.EqualFold(strings.ReplaceAll(key, "_", "-"), "dialer-proxy") {
			node.Reason = "chainUnsupported"
			return node, nil
		}
		if strings.EqualFold(key, "smux") {
			hasMux = true
		}
		if node.Type == "ss" && strings.EqualFold(key, "plugin") {
			plugin, _ := value.(string)
			hasRetainedTransport = hasRetainedTransport || strings.EqualFold(plugin, "kcptun")
		}
		if node.Type == "hysteria2" && strings.EqualFold(strings.ReplaceAll(key, "_", "-"), "realm-opts") {
			hasRetainedTransport = true
		}
	}
	if node.Type == "" {
		return node, nil
	}
	// Only standalone, lazily dialing transports are admitted. L3/mesh adapters
	// can start interfaces or autonomous traffic merely by being constructed.
	switch node.Type {
	case "ss", "ssr", "socks5", "http", "vmess", "vless", "trojan", "hysteria2", "ssh":
	default:
		// TUIC/Snell pools and AnyTLS maintenance routines lack deterministic
		// release; Hysteria v1's control handshake does not honor cancellation.
		node.Reason = "typeUnsupported"
		return node, nil
	}
	// Mihomo's mux parse failure does not return the already-created adapter.
	// Keep those configurations explicit until construction can be transactional.
	// KCP's mux pool and Hysteria2 realm's HTTP pool also outlive Close.
	if hasMux || hasRetainedTransport {
		node.Reason = "typeUnsupported"
		return node, nil
	}
	if node.Name == "" || node.Server == "" || node.Port == 0 {
		return node, nil
	}
	proxy, err := parseCatalogProxy(mapping)
	if err != nil || proxy == nil {
		if proxy != nil {
			_ = proxy.Adapter().Close()
		}
		return node, nil
	}
	node.Supported, node.Reason = true, ""
	return node, proxy
}

// HomeDir is trusted configuration and may itself use a filesystem alias. Resolve
// its nearest existing ancestor so a not-yet-created home remains a cache miss.
func canonicalCatalogHome(home string) (string, bool) {
	var missing []string
	for {
		_, err := os.Lstat(home)
		if err == nil {
			canonical, err := filepath.EvalSymlinks(home)
			if err != nil {
				return "", false
			}
			info, err := os.Stat(canonical)
			if err != nil || !info.IsDir() {
				return "", false
			}
			for i := len(missing) - 1; i >= 0; i-- {
				canonical = filepath.Join(canonical, missing[i])
			}
			return canonical, true
		}
		if !os.IsNotExist(err) {
			return "", false
		}
		parent := filepath.Dir(home)
		if parent == home {
			return "", false
		}
		missing = append(missing, filepath.Base(home))
		home = parent
	}
}

// Provider cache contents are deliberately not parsed or downloaded in P1.
// Reject traversal and symlink/reparse escapes even when SAFE_PATHS is broader.
func catalogProviderStatus(path string) (string, bool) {
	catalogPathMu.RLock()
	defer catalogPathMu.RUnlock()
	if path == "" || strings.ContainsRune(path, 0) || !constant.Path.IsSafePath(path) {
		return "", false
	}
	home, err := filepath.Abs(constant.Path.HomeDir())
	if err != nil {
		return "", false
	}
	root := filepath.Join(home, "profiles", "providers")
	resolved, err := filepath.Abs(constant.Path.Resolve(path))
	if err != nil {
		return "", false
	}
	rel, err := filepath.Rel(root, resolved)
	if err != nil || !filepath.IsLocal(rel) || rel == "." {
		return "", false
	}
	parts := strings.Split(filepath.ToSlash(rel), "/")
	found := false
	for i, part := range parts {
		if strings.Contains(part, ":") {
			return "", false
		}
		if part == "proxies" && i > 0 && i < len(parts)-1 {
			found = true
		}
	}
	if !found {
		return "", false
	}
	current, valid := canonicalCatalogHome(home)
	if !valid {
		return "", false
	}
	// Only the trusted home may contain aliases. Check every managed component,
	// including profiles/providers, before accepting any missing descendant.
	parts = append([]string{"profiles", "providers"}, parts...)
	for i := -1; i < len(parts); i++ {
		if i >= 0 {
			current = filepath.Join(current, parts[i])
		}
		info, statErr := os.Lstat(current)
		if os.IsNotExist(statErr) {
			return "notCached", true
		}
		if statErr != nil || info.Mode()&os.ModeSymlink != 0 {
			return "", false
		}
		canonical, evalErr := filepath.EvalSymlinks(current)
		if evalErr != nil || !strings.EqualFold(filepath.Clean(canonical), filepath.Clean(current)) {
			return "", false
		}
		if i < len(parts)-1 && !info.IsDir() {
			return "", false
		}
		if i == len(parts)-1 && !info.Mode().IsRegular() {
			return "", false
		}
	}
	return "providerPending", true
}

func closeCatalogProxies(entries []*catalogEntry) {
	for _, entry := range entries {
		for _, proxy := range entry.proxies {
			if proxy != nil {
				_ = proxy.Adapter().Close()
			}
		}
		catalogMu.Lock()
		entry.proxies = nil
		catalogResourceCount--
		catalogMu.Unlock()
	}
}

func disposeCatalogLocked(entry *catalogEntry) []*catalogEntry {
	if !entry.retired || entry.building || entry.refs != 0 || entry.disposed {
		return nil
	}
	entry.disposed = true
	return []*catalogEntry{entry}
}

func retireCatalogLocked(entry *catalogEntry) []*catalogEntry {
	if catalogs[entry.key] == entry {
		delete(catalogs, entry.key)
	}
	entry.retired = true
	if entry.timer != nil {
		entry.timer.Stop()
		entry.timer = nil
	}
	return disposeCatalogLocked(entry)
}

func expireCatalog(entry *catalogEntry, now time.Time) {
	catalogMu.Lock()
	var closing []*catalogEntry
	if catalogs[entry.key] == entry && !entry.building && entry.refs == 0 && now.Sub(entry.lastUsed) >= catalogIdleTTL {
		closing = retireCatalogLocked(entry)
	}
	catalogMu.Unlock()
	closeCatalogProxies(closing)
}

func armCatalogExpiryLocked(entry *catalogEntry) {
	if entry.timer != nil {
		entry.timer.Stop()
	}
	entry.timer = time.AfterFunc(catalogIdleTTL, func() { expireCatalog(entry, time.Now()) })
}

func prepareCatalog(data string, owner *catalogOwner) (catalogPrepareResponse, string) {
	var params catalogPrepareParams
	result := catalogPrepareResponse{Nodes: []catalogNode{}, Providers: []catalogProvider{}}
	if json.Unmarshal([]byte(data), &params) != nil || !catalogIDPattern.MatchString(params.ID) {
		return result, "invalidParameters"
	}
	if len(params.Proxies) > maxCatalogNodes {
		return result, "tooManyNodes"
	}
	if len(params.Providers) > maxCatalogNodes {
		return result, "invalidParameters"
	}
	for _, provider := range params.Providers {
		if catalogText(provider.Name, 1024) == "" {
			return result, "invalidParameters"
		}
		status, ok := catalogProviderStatus(provider.Path)
		if !ok {
			return result, "invalidParameters"
		}
		result.Providers = append(result.Providers, catalogProvider{Name: provider.Name, Status: status})
	}
	key := catalogKey{owner: owner, id: params.ID}
	var entry *catalogEntry
	var closing []*catalogEntry
	// Close outside the mutex, but keep its reservation until Close completes.
	// Retry only a bounded number of times if concurrent preparations race us.
	for attempt := 0; attempt <= maxCatalogs; attempt++ {
		catalogMu.Lock()
		if catalogStopped || owner != nil && owner.closed {
			catalogMu.Unlock()
			return result, "sessionClosed"
		}
		if catalogStrictBlocked {
			catalogMu.Unlock()
			return result, "strictModeUnsupported"
		}
		var victim *catalogEntry
		if old := catalogs[key]; old != nil {
			if old.refs != 0 || old.building {
				catalogMu.Unlock()
				return result, "overloaded"
			}
			victim = old
		} else if catalogResourceCount >= maxCatalogs {
			for _, candidate := range catalogs {
				if candidate.refs == 0 && !candidate.building && (victim == nil || candidate.lastUsed.Before(victim.lastUsed)) {
					victim = candidate
				}
			}
			if victim == nil {
				catalogMu.Unlock()
				return result, "overloaded"
			}
		}
		if victim != nil {
			closing = retireCatalogLocked(victim)
			catalogMu.Unlock()
			closeCatalogProxies(closing)
			continue
		}
		entry = &catalogEntry{key: key, building: true, lastUsed: time.Now()}
		catalogs[key] = entry
		catalogResourceCount++
		catalogMu.Unlock()
		break
	}
	if entry == nil {
		return result, "overloaded"
	}
	proxies := make([]constant.Proxy, len(params.Proxies))
	result.ID = params.ID
	for i, raw := range params.Proxies {
		node, proxy := parseCatalogNode(i, raw)
		result.Nodes = append(result.Nodes, node)
		proxies[i] = proxy
	}
	catalogMu.Lock()
	entry.building = false
	entry.nodes, entry.proxies = result.Nodes, proxies
	reason := ""
	if catalogStrictBlocked {
		reason = "strictModeUnsupported"
	} else if catalogStopped || owner != nil && owner.closed {
		reason = "sessionClosed"
	} else if entry.retired {
		reason = "catalogNotFound"
	}
	if reason != "" {
		closing = retireCatalogLocked(entry)
	} else {
		entry.lastUsed = time.Now()
		armCatalogExpiryLocked(entry)
		closing = nil
	}
	catalogMu.Unlock()
	closeCatalogProxies(closing)
	return result, reason
}

func handleCatalogPrepare(data string, result ActionResult) {
	prepared, reason := prepareCatalog(data, result.owner)
	if reason != "" {
		result.error(reason)
		return
	}
	encoded, _ := json.Marshal(prepared)
	result.success(string(encoded))
}

func releaseCatalog(id string, owner *catalogOwner) {
	catalogMu.Lock()
	entry := catalogs[catalogKey{owner: owner, id: id}]
	var closing []*catalogEntry
	if entry != nil {
		closing = retireCatalogLocked(entry)
		cancelCatalogDelayTasksLocked(entry, "cancelled")
	}
	catalogMu.Unlock()
	closeCatalogProxies(closing)
}

func handleCatalogRelease(data string, result ActionResult) {
	var params struct {
		ID string `json:"catalog-id"`
	}
	if json.Unmarshal([]byte(data), &params) != nil || !catalogIDPattern.MatchString(params.ID) {
		result.error("invalidParameters")
		return
	}
	releaseCatalog(params.ID, result.owner)
	result.success(true)
}

func closeCatalogOwner(owner *catalogOwner) {
	catalogMu.Lock()
	if owner != nil {
		owner.closed = true
	}
	var closing []*catalogEntry
	for _, entry := range catalogs {
		if entry.key.owner == owner {
			closing = append(closing, retireCatalogLocked(entry)...)
		}
	}
	cancelOwnedDelayTasks(owner, "sessionClosed")
	catalogMu.Unlock()
	closeCatalogProxies(closing)
}

func clearCatalogs() { clearCatalogsForShutdown(false) }

func clearCatalogsForShutdown(stopping bool) {
	catalogMu.Lock()
	if stopping {
		catalogStopped = true
	}
	var closing []*catalogEntry
	for _, entry := range catalogs {
		closing = append(closing, retireCatalogLocked(entry)...)
		cancelCatalogDelayTasksLocked(entry, "sessionClosed")
	}
	catalogMu.Unlock()
	closeCatalogProxies(closing)
}

func resumeCatalogs() { catalogMu.Lock(); catalogStopped = false; catalogMu.Unlock() }

// Called at strict-state write boundaries. This projection is independently
// synchronized so catalog operations never read mutable listener pointers.
func setCatalogStrictBlocked(blocked bool) {
	catalogMu.Lock()
	catalogStrictBlocked = blocked
	var closing []*catalogEntry
	if blocked {
		for _, entry := range catalogs {
			closing = append(closing, retireCatalogLocked(entry)...)
			cancelCatalogDelayTasksLocked(entry, "strictModeUnsupported")
		}
	}
	catalogMu.Unlock()
	closeCatalogProxies(closing)
}

func handleCatalogTestDelay(data string, owner *catalogOwner, fn func(string)) {
	var params catalogDelayParams
	fail := func(reason string) {
		encoded, _ := json.Marshal(Delay{Value: -1, Reason: reason, Url: params.TestURL})
		fn(string(encoded))
	}
	if json.Unmarshal([]byte(data), &params) != nil || !catalogIDPattern.MatchString(params.ID) || params.Index == nil || *params.Index < 0 || params.RequestID == "" || len(params.RequestID) > 256 {
		fail("invalidParameters")
		return
	}
	catalogMu.Lock()
	if catalogStopped {
		catalogMu.Unlock()
		fail("sessionClosed")
		return
	}
	if catalogStrictBlocked {
		catalogMu.Unlock()
		fail("strictModeUnsupported")
		return
	}
	if owner != nil && owner.closed {
		catalogMu.Unlock()
		fail("sessionClosed")
		return
	}
	entry := catalogs[catalogKey{owner: owner, id: params.ID}]
	if entry == nil || entry.building {
		catalogMu.Unlock()
		fail("catalogNotFound")
		return
	}
	if *params.Index >= len(entry.nodes) {
		catalogMu.Unlock()
		fail("invalidParameters")
		return
	}
	node := entry.nodes[*params.Index]
	catalogMu.Unlock()
	if !node.Supported {
		fail(node.Reason)
		return
	}
	runDelayTask(TestDelayParams{RequestID: params.RequestID, ProxyName: node.Name, TestUrl: params.TestURL, Timeout: params.Timeout}, func(ctx context.Context) (constant.Proxy, string, func()) {
		catalogMu.Lock()
		defer catalogMu.Unlock()
		if catalogStrictBlocked {
			return nil, "strictModeUnsupported", nil
		}
		if entry.retired || catalogs[entry.key] != entry {
			return nil, "catalogNotFound", nil
		}
		if ctx.Err() != nil {
			return nil, "deadlineExceeded", nil
		}
		entry.refs++
		if entry.timer != nil {
			entry.timer.Stop()
			entry.timer = nil
		}
		return entry.proxies[*params.Index], "", func() {
			catalogMu.Lock()
			entry.refs--
			entry.lastUsed = time.Now()
			closing := disposeCatalogLocked(entry)
			if !entry.retired && entry.refs == 0 {
				armCatalogExpiryLocked(entry)
			}
			catalogMu.Unlock()
			closeCatalogProxies(closing)
		}
	}, fn, false, owner, entry)
}
