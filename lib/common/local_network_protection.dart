import 'package:flclashx/enum/enum.dart';

/// Domains that must never receive `198.18.0.0/16` Fake-IP answers because OS
/// network connectivity probes (Windows NCSI), mDNS/LAN resolution, loopback
/// auth helpers, NTP, and STUN break when given synthetic addresses.
const List<String> defaultEssentialFakeIpFilter = [
  '*.lan',
  '*.local',
  '*.localhost',
  '*.home.arpa',
  'localhost.ptlogin2.qq.com',
  'localhost.sec.qq.com',
  '+.msftconnecttest.com',
  '+.msftncsi.com',
  'time.*.com',
  'time.*.gov',
  'time.*.apple.com',
  'ntp.*.com',
  '+.stun.*.*',
];

/// Private, loopback, link-local, multicast, and CGNAT/Tailscale CIDRs routed
/// `DIRECT` (`no-resolve`) before a terminal catch-all `MATCH` rule when
/// Desktop `RouteMode.bypassPrivate` is enabled.
///
/// Note: `198.18.0.0/15` is intentionally excluded so Fake-IP (`198.18.0.1/16`)
/// remains intercepted by Mihomo.
const List<String> desktopBypassPrivateRules = [
  'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
  'IP-CIDR,100.64.0.0/10,DIRECT,no-resolve',
  'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
  'IP-CIDR,169.254.0.0/16,DIRECT,no-resolve',
  'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
  'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
  'IP-CIDR,224.0.0.0/4,DIRECT,no-resolve',
  'IP-CIDR,240.0.0.0/4,DIRECT,no-resolve',
  'IP-CIDR6,::1/128,DIRECT,no-resolve',
  'IP-CIDR6,fc00::/7,DIRECT,no-resolve',
  'IP-CIDR6,fe80::/10,DIRECT,no-resolve',
  'IP-CIDR6,ff00::/8,DIRECT,no-resolve',
];

/// Merges [defaultEssentialFakeIpFilter] with [configuredFilter] while
/// preserving user/profile ordering and avoiding duplicates.
List<String> mergeEssentialFakeIpFilter(Iterable<Object?> configuredFilter) {
  final seen = <String>{};
  final merged = <String>[];

  void addEntry(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final normalized = trimmed.toLowerCase();
    if (seen.add(normalized)) {
      merged.add(trimmed);
    }
  }

  for (final item in configuredFilter) {
    if (item is String) {
      addEntry(item);
    }
  }
  defaultEssentialFakeIpFilter.forEach(addEntry);
  return merged;
}

bool _isTerminalMatchRule(Object? rawRule) {
  if (rawRule is! String) return false;
  final normalized = rawRule.trimLeft().toUpperCase();
  return normalized.startsWith('MATCH,');
}

/// Inserts [desktopBypassPrivateRules] immediately before the first terminal
/// `MATCH,...` rule when [isDesktop] is true and [routeMode] is
/// [RouteMode.bypassPrivate].
///
/// Placing these rules right before `MATCH` guarantees:
/// 1. Per-application `PROCESS-PATH` policies (prepended afterwards) win first.
/// 2. Explicit profile rules (e.g., corporate subnet `IP-CIDR,10.8.0.0/16,VPN`)
///    declared above `MATCH` still take precedence.
/// 3. Minimal profiles containing only `MATCH,PROXY` no longer tunnel local LAN,
///    loopback, link-local, or Tailscale (`100.64.0.0/10`) traffic abroad.
List<Object?> applyDesktopBypassPrivateRules(
  Iterable<Object?> profileRules, {
  required bool isDesktop,
  required RouteMode routeMode,
}) {
  final rules = List<Object?>.of(profileRules);
  if (!isDesktop || routeMode != RouteMode.bypassPrivate) {
    return rules;
  }

  final existingNormalized = <String>{
    for (final item in rules)
      if (item is String) item.trim().toUpperCase(),
  };

  final toInsert = <String>[
    for (final bypass in desktopBypassPrivateRules)
      if (!existingNormalized.contains(bypass.toUpperCase())) bypass,
  ];
  if (toInsert.isEmpty) {
    return rules;
  }

  final matchIndex = rules.indexWhere(_isTerminalMatchRule);
  if (matchIndex >= 0) {
    rules.insertAll(matchIndex, toInsert);
  } else {
    rules.addAll(toInsert);
  }
  return rules;
}
