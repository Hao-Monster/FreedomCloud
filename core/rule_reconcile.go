package main

import (
	"net/netip"

	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	T "github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var defaultFakeIPv4Range = netip.MustParsePrefix("198.18.0.0/15")

func isFakeDestinationIP(cfg *config.Config, ip netip.Addr) bool {
	if !ip.IsValid() {
		return false
	}
	unmapped := ip.Unmap()
	if resolver.IsFakeIP(unmapped) {
		return true
	}
	if cfg != nil && cfg.DNS != nil && cfg.DNS.EnhancedMode == C.DNSFakeIP {
		if cfg.DNS.FakeIPRange.IsValid() && cfg.DNS.FakeIPRange.Contains(unmapped) {
			return true
		}
		if cfg.DNS.FakeIPRange6.IsValid() && cfg.DNS.FakeIPRange6.Contains(unmapped) {
			return true
		}
		if defaultFakeIPv4Range.Contains(unmapped) {
			return true
		}
	}
	return false
}

func rulesSignatureChanged(previous []C.Rule, candidate []C.Rule) bool {
	if len(previous) != len(candidate) {
		return true
	}
	for i := range candidate {
		p, c := previous[i], candidate[i]
		if p.RuleType() != c.RuleType() ||
			p.Payload() != c.Payload() ||
			p.Adapter() != c.Adapter() {
			return true
		}
	}
	return false
}

// evaluateTopLevelTarget evaluates which top-level adapter [meta] would match
// under [cfg] without performing any blocking DNS or process lookups.
// It returns (targetAdapter, ambiguousDueToUnresolvedIP).
func evaluateTopLevelTarget(cfg *config.Config, meta *C.Metadata) (string, bool) {
	if cfg == nil || cfg.General == nil || meta == nil {
		return "", false
	}
	if meta.SpecialProxy != "" {
		return meta.SpecialProxy, false
	}
	switch cfg.General.Mode {
	case T.Direct:
		return "DIRECT", false
	case T.Global:
		return "GLOBAL", false
	}

	evalMeta := *meta
	if evalMeta.Host != "" && isFakeDestinationIP(cfg, evalMeta.DstIP) {
		evalMeta.DstIP = netip.Addr{}
	}

	neededIPResolution := false
	helper := C.RuleMatchHelper{
		ResolveIP: func() {
			if !evalMeta.DstIP.IsValid() {
				neededIPResolution = true
			}
		},
		FindProcess: func() {},
		CheckPassRule: func(adapterName string) bool {
			if adapterName == "PASS" {
				return true
			}
			if cfg.Proxies != nil {
				if proxy, ok := cfg.Proxies[adapterName]; ok && proxy.Type() == C.Pass {
					return true
				}
			}
			return false
		},
	}

	activeRules := cfg.Rules
	if evalMeta.SpecialRules != "" && cfg.SubRules != nil {
		if sub, ok := cfg.SubRules[evalMeta.SpecialRules]; ok {
			activeRules = sub
		}
	}

	for _, rule := range activeRules {
		if wrapper, ok := rule.(C.RuleWrapper); ok && wrapper.IsDisabled() {
			continue
		}
		matched, adapterName := rule.Match(&evalMeta, helper)
		if neededIPResolution {
			return "", true
		}
		if !matched {
			continue
		}
		if helper.CheckPassRule(adapterName) {
			continue
		}
		if cfg.Proxies != nil {
			if adapter, ok := cfg.Proxies[adapterName]; ok {
				if evalMeta.NetWork == C.UDP && !adapter.SupportUDP() {
					continue
				}
			} else {
				continue
			}
		}
		return adapterName, false
	}

	return "DIRECT", false
}

// reconcileActiveConnectionsLocked surgically closes active connections whose
// top-level routing adapter under [candidate] differs from their established
// chain adapter (for example, pooled HTTP/2 or QUIC sockets to domestic domains
// that were opened via PROXY before a DIRECT rule or mode change took effect),
// while keeping unaffected connections uninterrupted.
func reconcileActiveConnectionsLocked(previous *config.Config, candidate *config.Config) int {
	if candidate == nil || candidate.General == nil {
		return 0
	}
	rulesChanged := previous == nil ||
		previous.General == nil ||
		previous.General.Mode != candidate.General.Mode ||
		rulesSignatureChanged(previous.Rules, candidate.Rules)

	var toClose []statistic.Tracker
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		info := c.Info()
		if info == nil || info.Metadata == nil || len(info.Chain) == 0 {
			return true
		}
		oldTopAdapter := info.Chain[len(info.Chain)-1]
		if oldTopAdapter == "" {
			return true
		}
		newTopAdapter, ambiguousIP := evaluateTopLevelTarget(candidate, info.Metadata)
		if ambiguousIP {
			if rulesChanged {
				toClose = append(toClose, c)
			}
			return true
		}
		if newTopAdapter != "" && newTopAdapter != oldTopAdapter {
			toClose = append(toClose, c)
		}
		return true
	})

	for _, c := range toClose {
		_ = c.Close()
	}
	if len(toClose) > 0 {
		log.Infoln("[Reconcile] closed %d stale connection(s) whose routing target changed", len(toClose))
	}
	return len(toClose)
}
