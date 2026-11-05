import 'package:flclashx/common/local_network_protection.dart';
import 'package:flclashx/common/per_app_policy.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/foundation.dart';

/// Semantic proxy target used in cross-profile Global Override rules so a single
/// rule automatically binds to each subscription's primary outbound group
/// (e.g. `PROXY`, `Proxy`, `🚀 节点选择`) without failing `ParseRawConfig`.
const String semanticDefaultProxyTarget = 'DEFAULT_PROXY';

const Set<String> _builtinTargetsUpper = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
};

/// Minimal domestic root-domain suffix fallback used only when local
/// `GeoSite.dat` is absent or unreadable (e.g. stripped test environments).
const List<String> fallbackDomesticSuffixRules = [
  'DOMAIN-SUFFIX,local,DIRECT',
  'DOMAIN-SUFFIX,lan,DIRECT',
  'DOMAIN,localhost,DIRECT',
  'DOMAIN-SUFFIX,cn,DIRECT',
  'DOMAIN-SUFFIX,baidu.com,DIRECT',
  'DOMAIN-SUFFIX,bdstatic.com,DIRECT',
  'DOMAIN-SUFFIX,bdimg.com,DIRECT',
  'DOMAIN-SUFFIX,baidustatic.com,DIRECT',
  'DOMAIN-SUFFIX,qq.com,DIRECT',
  'DOMAIN-SUFFIX,weixin.qq.com,DIRECT',
  'DOMAIN-SUFFIX,qpic.cn,DIRECT',
  'DOMAIN-SUFFIX,gtimg.cn,DIRECT',
  'DOMAIN-SUFFIX,taobao.com,DIRECT',
  'DOMAIN-SUFFIX,tmall.com,DIRECT',
  'DOMAIN-SUFFIX,alicdn.com,DIRECT',
  'DOMAIN-SUFFIX,aliyun.com,DIRECT',
  'DOMAIN-SUFFIX,aliyuncs.com,DIRECT',
  'DOMAIN-SUFFIX,jd.com,DIRECT',
  'DOMAIN-SUFFIX,360buyimg.com,DIRECT',
  'DOMAIN-SUFFIX,bilibili.com,DIRECT',
  'DOMAIN-SUFFIX,hdslb.com,DIRECT',
  'DOMAIN-SUFFIX,163.com,DIRECT',
  'DOMAIN-SUFFIX,126.net,DIRECT',
  'DOMAIN-SUFFIX,douyin.com,DIRECT',
  'DOMAIN-SUFFIX,toutiao.com,DIRECT',
  'DOMAIN-SUFFIX,zhihu.com,DIRECT',
  'DOMAIN-SUFFIX,zhimg.com,DIRECT',
  'DOMAIN-SUFFIX,weibo.com,DIRECT',
];

class CompiledRuleResult {
  const CompiledRuleResult({
    required this.rules,
    required this.primaryProxyTarget,
    required this.isBareProfile,
    required this.localSplitActivated,
  });

  final List<String> rules;
  final String primaryProxyTarget;
  final bool isBareProfile;
  final bool localSplitActivated;
}

List<String> _splitTopLevelRuleParts(String rawRule) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < rawRule.length; i++) {
    final ch = rawRule.codeUnitAt(i);
    if (ch == 0x28 /* '(' */) {
      depth++;
    } else if (ch == 0x29 /* ')' */ && depth > 0) {
      depth--;
    } else if (ch == 0x2C /* ',' */ && depth == 0) {
      parts.add(rawRule.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(rawRule.substring(start));
  return parts;
}

bool _isTerminalCatchAllRule(String rawRule) {
  final trimmed = rawRule.trimLeft();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return false;
  final comma = trimmed.indexOf(',');
  if (comma <= 0) return false;
  final action = trimmed.substring(0, comma).trim().toUpperCase();
  return action == 'MATCH' || action == 'FINAL';
}

bool _isPrivateOrReservedCidr(String cidr) {
  final normalized = cidr.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized.startsWith('10.') ||
      normalized.startsWith('127.') ||
      normalized.startsWith('169.254.') ||
      normalized.startsWith('192.168.') ||
      normalized.startsWith('0.')) {
    return true;
  }
  if (normalized.startsWith('172.')) {
    final secondDot = normalized.indexOf('.', 4);
    if (secondDot > 4) {
      final secondOctet = int.tryParse(normalized.substring(4, secondDot));
      if (secondOctet != null && secondOctet >= 16 && secondOctet <= 31) {
        return true;
      }
    }
  }
  if (normalized.startsWith('100.')) {
    final secondDot = normalized.indexOf('.', 4);
    if (secondDot > 4) {
      final secondOctet = int.tryParse(normalized.substring(4, secondDot));
      if (secondOctet != null && secondOctet >= 64 && secondOctet <= 127) {
        return true;
      }
    }
  }
  if (normalized.startsWith('224.') || normalized.startsWith('240.')) {
    return true;
  }
  if (normalized == '::1/128' ||
      normalized.startsWith('fc00:') ||
      normalized.startsWith('fd') ||
      normalized.startsWith('fe80:') ||
      normalized.startsWith('ff00:')) {
    return true;
  }
  return false;
}

bool _isPurelyLocalOrPrivateRule(List<String> parts) {
  if (parts.length < 2) return true;
  final action = parts[0].trim().toUpperCase();
  final payload = parts[1].trim().toLowerCase();
  if (action == 'MATCH' || action == 'FINAL') return true;
  if (action == 'GEOSITE') {
    return payload == 'private';
  }
  if (action == 'GEOIP' || action == 'SRC-GEOIP') {
    return payload == 'private' || payload == 'lan';
  }
  if (action == 'IP-CIDR' ||
      action == 'IP-CIDR6' ||
      action == 'SRC-IP-CIDR') {
    return _isPrivateOrReservedCidr(payload);
  }
  if (action == 'DOMAIN' || action == 'DOMAIN-SUFFIX') {
    return payload == 'localhost' ||
        payload == 'local' ||
        payload == 'lan' ||
        payload == 'home.arpa' ||
        payload.endsWith('.local') ||
        payload.endsWith('.lan') ||
        payload.endsWith('.localhost') ||
        payload.endsWith('.home.arpa');
  }
  return false;
}

/// Returns `true` when [rawRules] contains no public internet traffic-splitting
/// rules (e.g., `rules: []`, a single `MATCH,PROXY`, or only private/loopback
/// LAN bypass rules plus `MATCH,PROXY`) and does not reference active
/// [ruleProviders] via `RULE-SET`.
bool isBareRuleProfile(
  Iterable<Object?> rawRules, {
  Map<Object?, Object?>? ruleProviders,
}) {
  final hasProviders = ruleProviders != null && ruleProviders.isNotEmpty;
  for (final item in rawRules) {
    if (item is! String) continue;
    final trimmed = item.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final parts = _splitTopLevelRuleParts(trimmed);
    final action = parts.first.trim().toUpperCase();
    if (action == 'RULE-SET' && hasProviders) {
      return false;
    }
    if (!_isPurelyLocalOrPrivateRule(parts)) {
      return false;
    }
  }
  return true;
}

/// Resolves the active subscription's primary outbound proxy group or node.
String resolvePrimaryProxyTarget({
  required Iterable<Object?> rawRules,
  Iterable<Object?> proxyGroups = const [],
  Iterable<Object?> proxies = const [],
}) {
  final groupNames = <String>[];
  final visibleGroupNames = <String>[];
  for (final raw in proxyGroups) {
    if (raw is! Map) continue;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final trimmed = name.trim();
    groupNames.add(trimmed);
    if (raw['hidden'] != true && trimmed.toUpperCase() != 'GLOBAL') {
      visibleGroupNames.add(trimmed);
    }
  }

  final proxyNames = <String>[];
  for (final raw in proxies) {
    if (raw is! Map) continue;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final trimmed = name.trim();
    if (!_builtinTargetsUpper.contains(trimmed.toUpperCase())) {
      proxyNames.add(trimmed);
    }
  }

  final validOutbounds = <String>{
    ...groupNames,
    ...proxyNames,
    'GLOBAL',
  };

  for (final item in rawRules) {
    if (item is! String || !_isTerminalCatchAllRule(item)) continue;
    final parts = _splitTopLevelRuleParts(item.trim());
    if (parts.length >= 2) {
      final candidate = parts[1].trim();
      if (candidate.isNotEmpty &&
          !_builtinTargetsUpper.contains(candidate.toUpperCase()) &&
          validOutbounds.contains(candidate)) {
        return candidate;
      }
    }
  }

  for (final preferred in const ['PROXY', 'Proxy', 'proxy']) {
    if (groupNames.contains(preferred)) {
      return preferred;
    }
  }

  if (visibleGroupNames.isNotEmpty) {
    return visibleGroupNames.first;
  }
  for (final group in groupNames) {
    if (group.toUpperCase() != 'GLOBAL') {
      return group;
    }
  }
  if (proxyNames.isNotEmpty) {
    return proxyNames.first;
  }
  return 'GLOBAL';
}

/// Rewrites `DEFAULT_PROXY` (and optionally missing subscription-specific group
/// names) to [primaryProxyTarget] so global rules work across heterogeneous
/// subscriptions without breaking `ParseRawConfig`.
String rewriteRuleTargetForProfile(
  String rawRule, {
  required String primaryProxyTarget,
  required Set<String> availableTargets,
  bool fallbackUnknownTargetToPrimary = true,
}) {
  final trimmed = rawRule.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) {
    return trimmed;
  }
  final parts = _splitTopLevelRuleParts(trimmed);
  if (parts.isEmpty) return trimmed;
  final action = parts[0].trim().toUpperCase();
  if (action == 'SUB-RULE') {
    return trimmed;
  }
  final targetIndex = (action == 'MATCH' || action == 'FINAL') ? 1 : 2;
  if (targetIndex >= parts.length) {
    return trimmed;
  }
  final rawTarget = parts[targetIndex].trim();
  final upperTarget = rawTarget.toUpperCase();
  if (upperTarget == semanticDefaultProxyTarget) {
    parts[targetIndex] = primaryProxyTarget;
    return parts.join(',');
  }
  if (_builtinTargetsUpper.contains(upperTarget) ||
      availableTargets.contains(rawTarget)) {
    return trimmed;
  }
  if (fallbackUnknownTargetToPrimary) {
    parts[targetIndex] = primaryProxyTarget;
    return parts.join(',');
  }
  return trimmed;
}

/// Synthesizes the complete 5-layer routing rule list for Mihomo Core.
CompiledRuleResult compileEffectiveRules({
  required Iterable<Object?> rawProfileRules,
  Map<Object?, Object?>? ruleProviders,
  Iterable<Object?> proxyGroups = const [],
  Iterable<Object?> proxies = const [],
  Iterable<PerAppPolicy> perAppPolicies = const [],
  OverrideData? globalOverrideData,
  OverrideData? profileOverrideData,
  bool scriptActive = false,
  required LocalSplitMode localSplitMode,
  required RouteMode routeMode,
  required bool isDesktop,
  required bool hasGeoSite,
  required bool hasGeoIp,
  ValueChanged<String>? onUnavailablePerAppTarget,
}) {
  final availableGroups = <String>{
    'GLOBAL',
    for (final raw in proxyGroups)
      if (raw is Map && raw['name'] is String && (raw['name'] as String).trim().isNotEmpty)
        (raw['name'] as String).trim(),
  };
  final availableAllTargets = <String>{
    ...availableGroups,
    for (final raw in proxies)
      if (raw is Map && raw['name'] is String && (raw['name'] as String).trim().isNotEmpty)
        (raw['name'] as String).trim(),
  };

  final primaryProxyTarget = resolvePrimaryProxyTarget(
    rawRules: rawProfileRules,
    proxyGroups: proxyGroups,
    proxies: proxies,
  );

  var bareProfile = isBareRuleProfile(
    rawProfileRules,
    ruleProviders: ruleProviders,
  );

  List<String> baseRules;
  var profileAddedRules = <String>[];
  if (!scriptActive &&
      profileOverrideData != null &&
      profileOverrideData.enable) {
    if (profileOverrideData.rule.type == OverrideRuleType.override) {
      baseRules = profileOverrideData.runningRule
          .map(
            (r) => rewriteRuleTargetForProfile(
              r,
              primaryProxyTarget: primaryProxyTarget,
              availableTargets: availableAllTargets,
            ),
          )
          .where((r) => r.isNotEmpty)
          .toList();
      bareProfile = isBareRuleProfile(baseRules, ruleProviders: ruleProviders);
    } else {
      baseRules = [
        for (final item in rawProfileRules)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
      profileAddedRules = profileOverrideData.runningRule
          .map(
            (r) => rewriteRuleTargetForProfile(
              r,
              primaryProxyTarget: primaryProxyTarget,
              availableTargets: availableAllTargets,
            ),
          )
          .where((r) => r.isNotEmpty)
          .toList();
    }
  } else {
    baseRules = [
      for (final item in rawProfileRules)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }

  final globalAddedRules = <String>[
    if (!scriptActive && globalOverrideData != null && globalOverrideData.enable)
      for (final r in globalOverrideData.runningRule)
        if (r.trim().isNotEmpty)
          rewriteRuleTargetForProfile(
            r,
            primaryProxyTarget: primaryProxyTarget,
            availableTargets: availableAllTargets,
          ),
  ];

  final mergedRules = <String>[
    ...profileAddedRules,
    ...globalAddedRules,
    ...baseRules,
  ];

  final activateLocalSplit = !scriptActive &&
      (localSplitMode == LocalSplitMode.always ||
          (localSplitMode == LocalSplitMode.auto && bareProfile));

  List<String> rulesBeforePerApp;
  if (activateLocalSplit) {
    final fallbackCandidates = <String>[
      ...desktopBypassPrivateRules,
      if (hasGeoSite) ...[
        'GEOSITE,private,DIRECT',
        'GEOSITE,cn,DIRECT',
        'GEOSITE,geolocation-!cn,$primaryProxyTarget',
      ] else
        ...fallbackDomesticSuffixRules,
      if (hasGeoIp) 'GEOIP,CN,DIRECT',
    ];

    final existingUpper = <String>{
      for (final r in mergedRules) r.trim().toUpperCase(),
    };
    final toInsert = <String>[
      for (final candidate in fallbackCandidates)
        if (existingUpper.add(candidate.toUpperCase())) candidate,
    ];

    final working = List<String>.of(mergedRules);
    final matchIndex = working.indexWhere(_isTerminalCatchAllRule);
    if (matchIndex >= 0) {
      working.insertAll(matchIndex, toInsert);
    } else {
      working
        ..addAll(toInsert)
        ..add('MATCH,$primaryProxyTarget');
    }
    rulesBeforePerApp = working;
  } else {
    rulesBeforePerApp = applyDesktopBypassPrivateRules(
      mergedRules,
      isDesktop: isDesktop,
      routeMode: routeMode,
    ).whereType<String>().toList();
  }

  final withPerApp = mergePerAppPolicyRules(
    perAppPolicies,
    rulesBeforePerApp,
    availableTargetGroups: availableGroups,
    onUnavailableTarget: onUnavailablePerAppTarget,
  ).whereType<String>().toList(growable: false);

  return CompiledRuleResult(
    rules: withPerApp,
    primaryProxyTarget: primaryProxyTarget,
    isBareProfile: bareProfile,
    localSplitActivated: activateLocalSplit,
  );
}
