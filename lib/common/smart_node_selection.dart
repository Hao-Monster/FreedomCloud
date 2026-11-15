import 'package:flclashx/common/constant.dart' as app_constant;
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart'
    show isInformationalProxyName;

export 'package:flclashx/models/profile.dart' show smartSelectionModeMarker;

enum NodeSelectionMode {
  smart,
  manual,
}

/// Display-friendly prefix for synthesized hidden `url-test` groups.
const String kManagedSmartGroupPrefix = '智能选择节点 · 自动优选';
const int kManagedSmartTestIntervalSec = 180;
const int kManagedSmartToleranceMs = 150;
const int kManagedSmartMaxFailedTimes = 2;
const int kManagedSmartTestTimeoutMs = 5000;

const String _trafficBadgePrefixPattern =
    r'(?:(?:📊|📈|📉|🔋|💾|剩余流量|可用流量|已用流量|流量剩余|剩余|可用|流量|余量|remaining(?:\s+traffic)?|left)\s*[:：=]?\s*)*';
const String _trafficBadgeUnitPattern =
    r'(?:KiB|MiB|GiB|TiB|PiB|KB|MB|GB|TB|PB|B)';
const String _trafficBadgeAmountPattern =
    '$_trafficBadgePrefixPattern'
    r'\d+(?:\.\d+)?(?:\s*'
    '$_trafficBadgeUnitPattern'
    r'?\s*/\s*'
    '$_trafficBadgePrefixPattern'
    r'\d+(?:\.\d+)?)?\s*'
    '$_trafficBadgeUnitPattern';
const List<(String, String)> _trafficBadgeBracketPairs = <(String, String)>[
  (r'\(', r'\)'),
  (r'\[', r'\]'),
  ('（', '）'),
  ('【', '】'),
];

final RegExp _dynamicTrafficBadgeSuffixPattern = RegExp(
  '(?:'
  r'(?:\s*[|｜/、]\s*|\s+[-–—:：·]\s*)'
  '$_trafficBadgeAmountPattern'
  '|'
  r'(?:\s*[|｜/、]\s*|\s+[-–—:：·]\s*|\s*)'
  '(?:${_trafficBadgeBracketPairs.map((pair) => '${pair.$1}\\s*$_trafficBadgeAmountPattern\\s*${pair.$2}').join('|')})'
  r')\s*$',
  caseSensitive: false,
);

/// Strips a trailing dynamic remaining-traffic badge (containing a numeric value
/// and byte unit) from [name], returning the trimmed stem when stripped or
/// `null` when no traffic badge matched or the resulting stem would be empty.
String? stripDynamicTrafficBadge(String name) {
  if (name.isEmpty) return null;
  final match = _dynamicTrafficBadgeSuffixPattern.firstMatch(name);
  if (match == null) return null;
  final stem = name.substring(0, match.start).trim();
  if (stem.isEmpty) return null;
  return stem;
}

/// Aligns a persisted [selected] proxy name against updated [candidates] when
/// subscription traffic badges change while preserving exact hits and failing
/// closed on missing or ambiguous candidates.
String reconcileDynamicTrafficNodeName(
  String selected,
  Iterable<String> candidates,
) {
  if (selected.isEmpty) return selected;
  final candidateList = candidates is List<String>
      ? candidates
      : candidates.toList(growable: false);
  if (candidateList.isEmpty || candidateList.contains(selected)) {
    return selected;
  }

  final selectedStripped = stripDynamicTrafficBadge(selected);
  final selectedStem = selectedStripped ?? selected.trim();
  if (selectedStem.isEmpty) return selected;

  final matches = <String>{};
  for (final candidate in candidateList) {
    if (candidate.isEmpty) continue;
    final candidateStripped = stripDynamicTrafficBadge(candidate);
    if (selectedStripped != null) {
      final candidateStem = candidateStripped ?? candidate.trim();
      if (candidateStem == selectedStem) {
        matches.add(candidate);
      }
    } else if (candidateStripped != null && candidateStripped == selectedStem) {
      matches.add(candidate);
    }
  }
  return matches.length == 1 ? matches.first : selected;
}

const String kInformationalProxyExcludeRegex =
    r'(剩余流量|可用流量|已用流量|总流量|流量剩余|流量已用|流量重置|距离下次重置|下次重置|重置剩余'
    r'|套餐到期|到期时间|过期时间|有效期限|有效期至|订阅到期'
    r'|官网|官方网址|最新网址|备用网址|发布页|防失联|机场地址'
    r'|公告\s*[:：]|通知\s*[:：]|群组|客服|售后|请更新订阅'
    r'|(?i:remaining\s+traffic|traffic\s+reset|expire\s*date|official\s+website))';

const Set<String> _nonLeafProxyTypes = <String>{
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
  'compatible',
};

const Set<String> _builtInPolicyNames = <String>{
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
};

String managedSmartGroupNameFor(String selectorGroupName) =>
    '$kManagedSmartGroupPrefix ($selectorGroupName)';

bool isManagedSmartGroupName(String? name) {
  if (name == null || name.isEmpty) return false;
  return name == kManagedSmartGroupPrefix ||
      (name.startsWith('$kManagedSmartGroupPrefix (') && name.endsWith(')'));
}

String _combineExcludeFilter(String? existing) {
  final trimmed = existing?.trim() ?? '';
  if (trimmed.isEmpty) return kInformationalProxyExcludeRegex;
  if (trimmed.contains('剩余流量') && trimmed.contains('套餐到期')) {
    return trimmed;
  }
  return '(?:$trimmed)|(?:$kInformationalProxyExcludeRegex)';
}

/// Synthesizes hidden `url-test` smart groups for selectable groups and `GLOBAL`
/// so switching between Smart Mode and Manual Fixed-IP Mode is an in-memory
/// `changeProxy` operation with zero Core restarts or TUN reconnects.
void injectManagedSmartProxyGroups(
  Map<String, dynamic> rawConfig, {
  required String defaultTestUrl,
}) {
  final effectiveDefaultUrl = defaultTestUrl.trim().isNotEmpty
      ? defaultTestUrl.trim()
      : app_constant.defaultTestUrl;

  final rawProxies = rawConfig['proxies'];
  final inlineLeafNames = <String>[];
  final inlineLeafSet = <String>{};
  if (rawProxies is List) {
    for (final item in rawProxies) {
      if (item is! Map) continue;
      final name = item['name'];
      final type = item['type'];
      if (name is! String || name.trim().isEmpty) continue;
      if (_builtInPolicyNames.contains(name.trim().toUpperCase())) continue;
      if (type is String && _nonLeafProxyTypes.contains(type.trim().toLowerCase())) {
        continue;
      }
      if (inlineLeafSet.add(name)) {
        inlineLeafNames.add(name);
      }
    }
  }

  final rawProviders = rawConfig['proxy-providers'];
  final providerNames = <String>[];
  final providerNameSet = <String>{};
  if (rawProviders is Map) {
    for (final key in rawProviders.keys) {
      if (key is String && key.trim().isNotEmpty && providerNameSet.add(key)) {
        providerNames.add(key);
      }
    }
  }

  final existingGroupsRaw = rawConfig['proxy-groups'];
  if (existingGroupsRaw != null && existingGroupsRaw is! List) {
    return;
  }

  // Strip any previously synthesized managed smart groups & references so
  // repeated calls are strictly idempotent.
  final baseGroups = <Map<String, dynamic>>[];
  final groupByName = <String, Map<String, dynamic>>{};
  for (final rawGroup in (existingGroupsRaw as List?) ?? const []) {
    if (rawGroup is! Map) continue;
    final groupName = rawGroup['name'];
    if (groupName is String && isManagedSmartGroupName(groupName)) {
      continue;
    }
    final copy = Map<String, dynamic>.from(rawGroup);
    if (copy['proxies'] is List) {
      copy['proxies'] = [
        for (final entry in copy['proxies'] as List)
          if (entry is! String || !isManagedSmartGroupName(entry)) entry,
      ];
    }
    baseGroups.add(copy);
    if (groupName is String && groupName.isNotEmpty) {
      groupByName[groupName] = copy;
    }
  }

  void collectReachableMembers(
    String groupName, {
    required List<String> leavesOut,
    required Set<String> seenLeaves,
    required List<String> providersOut,
    required Set<String> seenProviders,
    required Set<String> visitedGroups,
  }) {
    if (!visitedGroups.add(groupName)) return;
    final group = groupByName[groupName];
    if (group == null) return;

    final includeAll = group['include-all'] == true;
    final includeAllProxies =
        includeAll || group['include-all-proxies'] == true;
    final includeAllProviders =
        includeAll || group['include-all-providers'] == true;

    if (includeAllProxies) {
      for (final leaf in inlineLeafNames) {
        if (seenLeaves.add(leaf)) leavesOut.add(leaf);
      }
    }
    if (includeAllProviders) {
      for (final p in providerNames) {
        if (seenProviders.add(p)) providersOut.add(p);
      }
    }
    if (group['use'] is List) {
      for (final item in group['use'] as List) {
        if (item is String &&
            providerNameSet.contains(item) &&
            seenProviders.add(item)) {
          providersOut.add(item);
        }
      }
    }
    if (group['proxies'] is List) {
      for (final item in group['proxies'] as List) {
        if (item is! String || item.isEmpty) continue;
        if (_builtInPolicyNames.contains(item.toUpperCase())) continue;
        if (inlineLeafSet.contains(item)) {
          if (seenLeaves.add(item)) leavesOut.add(item);
        } else if (groupByName.containsKey(item)) {
          collectReachableMembers(
            item,
            leavesOut: leavesOut,
            seenLeaves: seenLeaves,
            providersOut: providersOut,
            seenProviders: seenProviders,
            visitedGroups: visitedGroups,
          );
        }
      }
    }
  }

  final synthesizedGroups = <Map<String, dynamic>>[];

  for (final group in baseGroups) {
    final name = group['name'];
    final type = group['type'];
    if (name is! String ||
        name.isEmpty ||
        name == 'GLOBAL' ||
        type != 'select' ||
        group['hidden'] == true) {
      continue;
    }

    final candidateLeaves = <String>[];
    final seenLeaves = <String>{};
    final candidateProviders = <String>[];
    final seenProviders = <String>{};
    collectReachableMembers(
      name,
      leavesOut: candidateLeaves,
      seenLeaves: seenLeaves,
      providersOut: candidateProviders,
      seenProviders: seenProviders,
      visitedGroups: <String>{},
    );

    final includeAllProviders =
        group['include-all'] == true || group['include-all-providers'] == true;
    final nonInfoLeaves = candidateLeaves
        .where((leaf) => !isInformationalProxyName(leaf))
        .toList();
    final finalLeaves = nonInfoLeaves.isNotEmpty
        ? nonInfoLeaves
        : (candidateProviders.isEmpty && !includeAllProviders
            ? candidateLeaves
            : const <String>[]);

    if (finalLeaves.isEmpty &&
        candidateProviders.isEmpty &&
        !includeAllProviders) {
      continue;
    }

    final smartName = managedSmartGroupNameFor(name);
    final groupUrlRaw = group['url'];
    final groupUrl = groupUrlRaw is String && groupUrlRaw.trim().isNotEmpty
        ? groupUrlRaw.trim()
        : effectiveDefaultUrl;
    final existingFilter = group['filter'] is String
        ? (group['filter'] as String).trim()
        : '';
    final existingExcludeFilter = group['exclude-filter'] is String
        ? (group['exclude-filter'] as String).trim()
        : '';
    final existingExcludeType = group['exclude-type'] is String
        ? (group['exclude-type'] as String).trim()
        : '';
    final needsExcludeRegex = candidateProviders.isNotEmpty ||
        includeAllProviders ||
        existingExcludeFilter.isNotEmpty;

    final smartGroup = <String, dynamic>{
      'name': smartName,
      'type': 'url-test',
      'hidden': true,
      'url': groupUrl,
      'interval': kManagedSmartTestIntervalSec,
      'tolerance': kManagedSmartToleranceMs,
      'timeout': kManagedSmartTestTimeoutMs,
      'max-failed-times': kManagedSmartMaxFailedTimes,
      'lazy': false,
      if (finalLeaves.isNotEmpty) 'proxies': finalLeaves,
      if (candidateProviders.isNotEmpty) 'use': candidateProviders,
      if (existingFilter.isNotEmpty) 'filter': existingFilter,
      if (needsExcludeRegex)
        'exclude-filter': _combineExcludeFilter(existingExcludeFilter),
      if (existingExcludeType.isNotEmpty) 'exclude-type': existingExcludeType,
    };
    synthesizedGroups.add(smartGroup);

    final updatedProxies = <String>[
      if (group['proxies'] is List)
        ...(group['proxies'] as List).whereType<String>(),
      smartName,
    ];
    group['proxies'] = updatedProxies;
  }

  // Synthesize GLOBAL smart group covering all real inline leaves + providers.
  final nonInfoGlobalLeaves = inlineLeafNames
      .where((leaf) => !isInformationalProxyName(leaf))
      .toList();
  final finalGlobalLeaves = nonInfoGlobalLeaves.isNotEmpty
      ? nonInfoGlobalLeaves
      : (providerNames.isEmpty ? inlineLeafNames : const <String>[]);

  if (finalGlobalLeaves.isNotEmpty || providerNames.isNotEmpty) {
    final globalSmartName = managedSmartGroupNameFor('GLOBAL');
    synthesizedGroups.add(<String, dynamic>{
      'name': globalSmartName,
      'type': 'url-test',
      'hidden': true,
      'url': effectiveDefaultUrl,
      'interval': kManagedSmartTestIntervalSec,
      'tolerance': kManagedSmartToleranceMs,
      'timeout': kManagedSmartTestTimeoutMs,
      'max-failed-times': kManagedSmartMaxFailedTimes,
      'lazy': false,
      if (finalGlobalLeaves.isNotEmpty) 'proxies': finalGlobalLeaves,
      if (providerNames.isNotEmpty) 'use': providerNames,
      if (providerNames.isNotEmpty)
        'exclude-filter': kInformationalProxyExcludeRegex,
    });

    final explicitGlobal = groupByName['GLOBAL'];
    if (explicitGlobal != null && explicitGlobal['proxies'] is List) {
      final explicitProxies = (explicitGlobal['proxies'] as List)
          .whereType<String>()
          .toList();
      if (!explicitProxies.contains(globalSmartName)) {
        explicitGlobal['proxies'] = <String>[
          ...explicitProxies,
          globalSmartName,
        ];
      }
    }
  }

  if (baseGroups.isNotEmpty || synthesizedGroups.isNotEmpty) {
    rawConfig['proxy-groups'] = <Map<String, dynamic>>[
      ...baseGroups,
      ...synthesizedGroups,
    ];
  }
}

NodeSelectionMode resolveProfileSelectionMode(Profile? profile) {
  if (profile == null) return NodeSelectionMode.manual;
  final marker = profile.providerHeaders[smartSelectionModeMarker]
      ?.trim()
      .toLowerCase();
  if (marker == 'smart') return NodeSelectionMode.smart;
  if (marker == 'manual') return NodeSelectionMode.manual;
  if (profile.selectedMap.values.any(isManagedSmartGroupName)) {
    return NodeSelectionMode.smart;
  }
  return NodeSelectionMode.manual;
}

Map<String, String> _reconcileEffectiveSelectedMap({
  required Map<String, String> effective,
  required Map<String, List<String>> inlineProxiesByGroup,
  required Map<String, bool> hasProvidersByGroup,
}) {
  if (effective.isEmpty || inlineProxiesByGroup.isEmpty) {
    return effective;
  }
  for (final groupName in effective.keys.toList(growable: false)) {
    final selected = effective[groupName];
    if (selected == null ||
        selected.isEmpty ||
        isManagedSmartGroupName(selected)) {
      continue;
    }
    final inlineProxies = inlineProxiesByGroup[groupName];
    if (inlineProxies == null || inlineProxies.isEmpty) {
      continue;
    }
    final reconciled = reconcileDynamicTrafficNodeName(
      selected,
      inlineProxies,
    );
    if (reconciled != selected) {
      effective[groupName] = reconciled;
      continue;
    }
    if (hasProvidersByGroup[groupName] ?? false) {
      // Inline candidates did not match; preserve original selection so Go Core
      // can reconcile against expanded provider proxies at runtime.
      continue;
    }
  }
  return effective;
}

Map<String, String> buildEffectiveSelectedMapForProfile({
  required Profile? profile,
  required Map<String, dynamic> patchedRawConfig,
}) {
  if (profile == null) return const <String, String>{};

  final availableGroupNames = <String>{};
  final selectableRuleGroups = <String>[];
  final inlineProxiesByGroup = <String, List<String>>{};
  final hasProvidersByGroup = <String, bool>{};
  final rawGroups = patchedRawConfig['proxy-groups'];
  if (rawGroups is List) {
    for (final item in rawGroups) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is! String || name.isEmpty) continue;
      availableGroupNames.add(name);
      final rawProxies = item['proxies'];
      inlineProxiesByGroup[name] = rawProxies is List
          ? rawProxies.whereType<String>().toList(growable: false)
          : const <String>[];
      final rawUse = item['use'];
      final hasUse = rawUse is List &&
          rawUse.whereType<String>().any((entry) => entry.trim().isNotEmpty);
      hasProvidersByGroup[name] = hasUse ||
          item['include-all'] == true ||
          item['include-all-providers'] == true;
      if (item['type'] == 'select' &&
          item['hidden'] != true &&
          name != 'GLOBAL' &&
          !isManagedSmartGroupName(name)) {
        selectableRuleGroups.add(name);
      }
    }
  }

  final mode = resolveProfileSelectionMode(profile);
  if (mode == NodeSelectionMode.manual) {
    final explicitManual = profile.providerHeaders[smartSelectionModeMarker]
            ?.trim()
            .toLowerCase() ==
        'manual';
    final effective = !explicitManual
        ? Map<String, String>.from(profile.selectedMap)
        : <String, String>{
            for (final entry in profile.selectedMap.entries)
              if (!isManagedSmartGroupName(entry.value)) entry.key: entry.value,
          };
    return _reconcileEffectiveSelectedMap(
      effective: effective,
      inlineProxiesByGroup: inlineProxiesByGroup,
      hasProvidersByGroup: hasProvidersByGroup,
    );
  }

  final effective = Map<String, String>.from(profile.selectedMap);
  String? primaryRuleSelector;
  final preferred = profile.currentGroupName;
  if (preferred != null &&
      preferred != 'GLOBAL' &&
      availableGroupNames.contains(managedSmartGroupNameFor(preferred))) {
    primaryRuleSelector = preferred;
  } else {
    for (final name in selectableRuleGroups) {
      if (availableGroupNames.contains(managedSmartGroupNameFor(name))) {
        primaryRuleSelector = name;
        break;
      }
    }
  }

  if (primaryRuleSelector != null) {
    effective[primaryRuleSelector] =
        managedSmartGroupNameFor(primaryRuleSelector);
  }
  final globalSmartName = managedSmartGroupNameFor('GLOBAL');
  if (availableGroupNames.contains(globalSmartName)) {
    effective['GLOBAL'] = globalSmartName;
  }
  return _reconcileEffectiveSelectedMap(
    effective: effective,
    inlineProxiesByGroup: inlineProxiesByGroup,
    hasProvidersByGroup: hasProvidersByGroup,
  );
}

Profile markProfileSelectionMode(
  Profile profile,
  NodeSelectionMode mode, {
  String? targetGroup,
  String? manualNodeName,
}) {
  final headers = Map<String, String>.from(profile.providerHeaders)
    ..[smartSelectionModeMarker] =
        mode == NodeSelectionMode.smart ? 'smart' : 'manual';
  final selectedMap = Map<String, String>.from(profile.selectedMap);

  if (mode == NodeSelectionMode.smart) {
    if (targetGroup != null && targetGroup.isNotEmpty) {
      selectedMap[targetGroup] = managedSmartGroupNameFor(targetGroup);
    }
    selectedMap['GLOBAL'] = managedSmartGroupNameFor('GLOBAL');
    return profile.copyWith(
      providerHeaders: headers,
      selectedMap: selectedMap,
      currentGroupName:
          (targetGroup != null && targetGroup.isNotEmpty)
              ? targetGroup
              : profile.currentGroupName,
    );
  }

  selectedMap.removeWhere((_, value) => isManagedSmartGroupName(value));
  if (targetGroup != null &&
      targetGroup.isNotEmpty &&
      manualNodeName != null &&
      manualNodeName.isNotEmpty) {
    selectedMap[targetGroup] = manualNodeName;
  }
  return profile.copyWith(
    providerHeaders: headers,
    selectedMap: selectedMap,
    currentGroupName:
        (targetGroup != null && targetGroup.isNotEmpty)
            ? targetGroup
            : profile.currentGroupName,
  );
}

String? resolveSmartActiveLeafName({
  required String? selectorGroupName,
  required List<Group> allGroups,
  required Map<String, String> selectedMap,
}) {
  if (allGroups.isEmpty) return null;
  String? candidateGroupName;
  if (selectorGroupName != null && selectorGroupName.isNotEmpty) {
    final mapped = selectedMap[selectorGroupName];
    if (isManagedSmartGroupName(mapped)) {
      candidateGroupName = mapped;
    } else {
      final groupNow = allGroups.getGroup(selectorGroupName)?.now;
      if (isManagedSmartGroupName(groupNow)) {
        candidateGroupName = groupNow;
      } else {
        candidateGroupName = managedSmartGroupNameFor(selectorGroupName);
      }
    }
  } else {
    candidateGroupName =
        selectedMap.values.where(isManagedSmartGroupName).firstOrNull;
  }

  if (candidateGroupName == null ||
      allGroups.getGroup(candidateGroupName) == null) {
    return null;
  }

  final leaf = allGroups.resolveToLeafProxy(candidateGroupName);
  if (leaf.isEmpty ||
      isManagedSmartGroupName(leaf) ||
      allGroups.getGroup(leaf) != null ||
      _builtInPolicyNames.contains(leaf.toUpperCase())) {
    return null;
  }
  return leaf;
}
