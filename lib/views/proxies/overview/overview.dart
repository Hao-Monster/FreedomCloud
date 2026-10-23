import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Selects only the page body; the scope control belongs to the existing app bar.
class NodeOverviewScopeView extends ConsumerWidget {
  const NodeOverviewScopeView({super.key, required this.currentView});

  final Widget currentView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled || count < 2) return currentView;
    ref.watch(_overviewSwitchTrackerProvider);
    final scope = ref.watch(proxiesScopeProvider);
    return scope == ProxiesScope.all ? const NodeOverviewView() : currentView;
  }
}

class NodeOverviewScopeAction extends ConsumerWidget {
  const NodeOverviewScopeAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled || count < 2) return const SizedBox.shrink();
    final scope = ref.watch(proxiesScopeProvider);
    final labels = {
      ProxiesScope.current: appLocalizations.nodeOverviewCurrentProfile,
      ProxiesScope.all: appLocalizations.nodeOverviewAllProfiles,
    };
    void select(ProxiesScope value) =>
        ref.read(proxiesScopeProvider.notifier).state = value;
    if (ref.watch(viewWidthProvider) <= maxLaptopWidth) {
      return PopupMenuButton<ProxiesScope>(
        key: const ValueKey('overview-scope-menu'),
        tooltip: labels[scope],
        icon: Icon(
            scope == ProxiesScope.all ? Icons.layers : Icons.layers_outlined),
        onSelected: select,
        itemBuilder: (context) => [
          for (final value in ProxiesScope.values)
            CheckedPopupMenuItem(
                value: value,
                checked: scope == value,
                child: Text(labels[value]!)),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<ProxiesScope>(
        key: const ValueKey('overview-scope-segments'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final value in ProxiesScope.values)
            ButtonSegment(value: value, label: Text(labels[value]!))
        ],
        selected: {scope},
        onSelectionChanged: (value) => select(value.single),
      ),
    );
  }
}

class _OverviewSwitchTracker {
  String? pendingProfileId;
  String? pendingProfileLabel;
  String? pendingNodeName;
  List<Group>? pendingGroups;
  int? pendingVersion;
  List<Group>? attestedGroups;
  int? attestedVersion;
  String? attestedProfileId;
  String? feedback;

  bool matchesAttested(List<Group> groups, int version) =>
      attestedGroups != null &&
      version == attestedVersion &&
      globalState.isSameGroupsList(groups, attestedGroups);

  void onSnapshotChanged({
    required List<Group> groups,
    required int version,
    required String? runtimeProfileId,
  }) {
    attestedGroups = groups;
    attestedVersion = version;
    attestedProfileId = groups.isEmpty ? null : runtimeProfileId;
    if (pendingProfileId != null && runtimeProfileId != pendingProfileId) {
      pendingGroups = groups;
      pendingVersion = version;
    }
  }
}

final _overviewSwitchTrackerProvider =
    Provider<_OverviewSwitchTracker>((ref) {
  final tracker = _OverviewSwitchTracker();
  final initialGroups = ref.read(groupsProvider);
  final initialVersion = ref.read(versionProvider);
  if (globalState.matchesGroupsSnapshot(initialGroups, initialVersion)) {
    tracker.onSnapshotChanged(
      groups: initialGroups,
      version: initialVersion,
      runtimeProfileId: globalState.groupsSnapshotProfileId ??
          (globalState.lastRuntimeProfileId == null
              ? ref.read(activeNodeCatalogProvider)?.profileId
              : null),
    );
  }
  void recordUpdate() {
    final nextGroups = ref.read(groupsProvider);
    final nextVersion = ref.read(versionProvider);
    if (!globalState.matchesGroupsSnapshot(nextGroups, nextVersion)) {
      return;
    }
    final runtimeProfileId = globalState.groupsSnapshotProfileId ??
        (globalState.lastRuntimeProfileId == null
            ? ref.read(activeNodeCatalogProvider)?.profileId
            : null);
    tracker.onSnapshotChanged(
      groups: nextGroups,
      version: nextVersion,
      runtimeProfileId: runtimeProfileId,
    );
  }
  ref.listen<List<Group>>(groupsProvider, (_, __) => recordUpdate());
  ref.listen<int>(versionProvider, (_, __) => recordUpdate());
  return tracker;
});

class NodeOverviewView extends ConsumerStatefulWidget {
  const NodeOverviewView({super.key});

  @override
  ConsumerState<NodeOverviewView> createState() => _NodeOverviewViewState();
}

class _IndexedNodeSummary {
  const _IndexedNodeSummary({
    required this.identityKey,
    required this.endpointKey,
    required this.name,
    required this.type,
    required this.providerName,
    required this.parseFailed,
  });

  factory _IndexedNodeSummary.fromNode(CatalogNode node) => _IndexedNodeSummary(
        identityKey: node.identityKey,
        endpointKey: node.endpointKey,
        name: node.name,
        type: node.type,
        providerName: node.providerName,
        parseFailed: node.unsupported == CatalogUnsupportedReason.parseFailed,
      );

  final String identityKey;
  final String endpointKey;
  final String name;
  final String type;
  final String? providerName;
  final bool parseFailed;
}

class _IndexedProfileCountrySummary {
  const _IndexedProfileCountrySummary({
    required this.url,
    required this.lastUpdateDate,
    required this.isUpdating,
    required this.scriptId,
    required this.scriptContent,
    required this.status,
    required this.nodes,
  });

  final String? url;
  final DateTime? lastUpdateDate;
  final bool isUpdating;
  final String? scriptId;
  final String? scriptContent;
  final ProfileCatalogStatus status;
  final List<_IndexedNodeSummary> nodes;

  bool matchesProfile(Profile profile, Script? currentScript) =>
      url == profile.url &&
      lastUpdateDate == profile.lastUpdateDate &&
      isUpdating == profile.isUpdating &&
      scriptId == currentScript?.id &&
      scriptContent == currentScript?.content;
}

class _NodeOverviewViewState extends ConsumerState<NodeOverviewView> {
  static const int _maxIndexScanConcurrency = 2;

  String? _selectedProfile;
  String? _selectedCountry;
  bool _availableOnly = false;
  final Set<String> _visibleProfileIds = <String>{};
  final Map<String, _IndexedProfileCountrySummary> _indexedProfiles =
      <String, _IndexedProfileCountrySummary>{};
  final Set<String> _indexingProfileIds = <String>{};
  final List<ProviderSubscription<Object?>> _lifecycleSubscriptions =
      <ProviderSubscription<Object?>>[];
  final Set<ProviderSubscription<Object?>> _activeScanSubscriptions =
      <ProviderSubscription<Object?>>{};
  int _activeIndexWorkers = 0;
  int _indexScanGeneration = 0;
  bool _indexScanDirty = false;
  bool _disposed = false;
  Timer? _clock;
  late final NodeCatalogTester _tester;
  String? _feedback;

  void _onProfileVisibilityChanged(String profileId, bool visible) {
    if (visible && _visibleProfileIds.add(profileId) && mounted) {
      setState(() {});
    }
  }

  ({bool verified, String? profileId}) _resolveSnapshotAttestation(
    _OverviewSwitchTracker tracker,
    List<Group> groups,
    int version,
  ) {
    if (tracker.matchesAttested(groups, version)) {
      return (verified: true, profileId: tracker.attestedProfileId);
    }
    if (globalState.matchesGroupsSnapshot(groups, version)) {
      return (
        verified: true,
        profileId: globalState.groupsSnapshotProfileId,
      );
    }
    return (verified: false, profileId: null);
  }

  bool _isSnapshotLiveForProfile({
    required String profileId,
    required List<Group> groups,
    required ({bool verified, String? profileId}) attestation,
  }) {
    if (groups.isEmpty) return true;
    if (!attestation.verified) return false;
    if (attestation.profileId != null) {
      return attestation.profileId == profileId;
    }
    return globalState.lastRuntimeProfileId == null;
  }

  void _recordIndexedCatalog(
    Profile profile,
    Script? currentScript,
    ProfileCatalog catalog,
  ) {
    if (catalog.status == ProfileCatalogStatus.loading) return;
    _indexedProfiles[profile.id] = _IndexedProfileCountrySummary(
      url: profile.url,
      lastUpdateDate: profile.lastUpdateDate,
      isUpdating: profile.isUpdating,
      scriptId: currentScript?.id,
      scriptContent: currentScript?.content,
      status: catalog.status,
      nodes: catalog.nodes.map(_IndexedNodeSummary.fromNode).toList(),
    );
  }

  void _scheduleCountryIndexScan() {
    if (_disposed || !mounted) return;
    if (!ref.read(nodeOverviewEnabledProvider)) return;
    _pumpCountryIndexWorkers(_indexScanGeneration);
  }

  void _pumpCountryIndexWorkers(int generation) {
    if (_disposed || !mounted || generation != _indexScanGeneration) return;
    final profiles = ref.read(profilesProvider);
    final currentScript = ref.read(scriptStateProvider).currentScript;
    final cachedCatalogs = ref.read(cachedProfileCatalogsProvider);
    for (final profile in profiles) {
      if (_activeIndexWorkers >= _maxIndexScanConcurrency) break;
      if (profile.isUpdating) continue;
      final existing = _indexedProfiles[profile.id];
      if (existing != null && existing.matchesProfile(profile, currentScript)) {
        continue;
      }
      final cached = cachedCatalogs[profile.id];
      if (cached != null && cached.status != ProfileCatalogStatus.loading) {
        _recordIndexedCatalog(profile, currentScript, cached);
        _indexScanDirty = true;
        continue;
      }
      if (_indexingProfileIds.contains(profile.id)) continue;
      _indexingProfileIds.add(profile.id);
      _activeIndexWorkers++;
      unawaited(_indexSingleProfile(profile.id, generation));
    }
    if (_indexScanDirty &&
        (_activeIndexWorkers == 0 || _indexedProfiles.length % 8 == 0) &&
        mounted &&
        !_disposed) {
      _indexScanDirty = false;
      setState(() {});
    }
  }

  Future<void> _indexSingleProfile(String profileId, int generation) async {
    ProviderSubscription<AsyncValue<ProfileCatalog>>? sub;
    try {
      if (_disposed || !mounted || generation != _indexScanGeneration) return;
      sub = ref.listenManual(profileCatalogProvider(profileId), (_, __) {});
      _activeScanSubscriptions.add(sub);
      final catalog = await ref.read(profileCatalogProvider(profileId).future);
      if (_disposed || !mounted || generation != _indexScanGeneration) return;
      final profile = ref.read(profilesProvider).getProfile(profileId);
      if (profile != null && !profile.isUpdating) {
        final currentScript = ref.read(scriptStateProvider).currentScript;
        _recordIndexedCatalog(profile, currentScript, catalog);
        _indexScanDirty = true;
      }
    } catch (_) {
      // Catalog load errors are surfaced through ProfileCatalogStatus.
    } finally {
      if (sub != null) {
        _activeScanSubscriptions.remove(sub);
        sub.close();
      }
      _indexingProfileIds.remove(profileId);
      if (_activeIndexWorkers > 0) {
        _activeIndexWorkers--;
      }
      if (!_disposed && mounted && generation == _indexScanGeneration) {
        _pumpCountryIndexWorkers(generation);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tester = ref.read(nodeCatalogTesterProvider);
    _feedback = ref.read(_overviewSwitchTrackerProvider).feedback;
    _lifecycleSubscriptions
      ..add(
        ref.listenManual<List<Profile>>(profilesProvider, (previous, next) {
          final script = ref.read(scriptStateProvider).currentScript;
          final nextIds = <String>{for (final profile in next) profile.id};
          _indexedProfiles.removeWhere((id, summary) {
            if (!nextIds.contains(id)) return true;
            final profile = next.getProfile(id);
            return profile == null || !summary.matchesProfile(profile, script);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_disposed) _scheduleCountryIndexScan();
          });
        }),
      )
      ..add(
        ref.listenManual<ScriptProps>(scriptStateProvider, (previous, next) {
          if (previous?.currentScript == next.currentScript) return;
          _indexScanGeneration++;
          _indexedProfiles.clear();
          _indexingProfileIds.clear();
          for (final sub in _activeScanSubscriptions.toList()) {
            sub.close();
          }
          _activeScanSubscriptions.clear();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_disposed) _scheduleCountryIndexScan();
          });
        }),
      );
    // Schedule background country indexing one frame after initial sliver
    // visibility settles so visible slivers attach their own catalog watches
    // first without causing duplicate initial loads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) _scheduleCountryIndexScan();
      });
    });
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _indexScanGeneration++;
    for (final sub in _lifecycleSubscriptions) {
      sub.close();
    }
    _lifecycleSubscriptions.clear();
    for (final sub in _activeScanSubscriptions.toList()) {
      sub.close();
    }
    _activeScanSubscriptions.clear();
    _clock?.cancel();
    _tester.disposeScope();
    super.dispose();
  }

  Future<void> _run(Future<DelayBatchResult> Function() action,
      {bool summarize = false}) async {
    ref.read(_overviewSwitchTrackerProvider).feedback = null;
    setState(() => _feedback = null);
    String? feedback;
    try {
      final result = await action();
      if (summarize) {
        final explanations = {
          if (result.reason != null) _testFailure(result.reason!),
          for (final issue in result.issues) _testFailure(issue.reason),
        };
        feedback = [
          appLocalizations.nodeOverviewBatchSummary(
              result.completed,
              result.failed,
              result.untested,
              result.issues.map((issue) => issue.profileId).toSet().length),
          ...explanations.take(3),
          if (explanations.length > 3)
            appLocalizations.nodeOverviewMoreIssues(explanations.length - 3),
        ].join('\n');
      } else {
        feedback = result.reason == null
            ? result.completed == 0
                ? appLocalizations.nodeOverviewNoNodes
                : null
            : _testFailure(result.reason!);
      }
    } catch (_) {
      feedback = appLocalizations.nodeOverviewTestUnavailable;
    }
    if (mounted) {
      ref.read(_overviewSwitchTrackerProvider).feedback = feedback;
      setState(() => _feedback = feedback);
    }
  }

  void _testCurrent(Profile? selected) {
    if (selected != null) {
      _testAll([selected]);
      return;
    }
    final targets = <DelayTestTarget>[];
    for (final group in ref.read(currentGroupsStateProvider).value) {
      for (final proxy in group.all) {
        // Keep the existing current-profile action's nested group and URL
        // resolution. Overview display deduplication must not alter that API.
        final state = ref.read(getProxyCardStateProvider(proxy.name));
        if (state.proxyName.isEmpty) continue;
        targets.add(DelayTestTarget(
            state.proxyName,
            state.testUrl.getSafeValue(
                ref.read(getRealTestUrlProvider(group.testUrl)))));
      }
    }
    unawaited(_run(() => _tester.testCurrent(targets)));
  }

  void _testAll(List<Profile> profiles) => unawaited(_run(
      () => _tester.testAll(profiles, ref.read(nodeOverviewTestUrlProvider)),
      summarize: true));

  void _testNode(Profile profile, CatalogNode node) =>
      unawaited(_run(() => _tester.testVisible([
            (profile: profile, nodes: [node])
          ], ref.read(nodeOverviewTestUrlProvider))));

  void _useActiveNode(Profile profile, String groupName, String proxyName) {
    detectionState.notifyRoutingChanged();
    ref.read(nodeCountryResolverProvider).markSwitchingNode();
    if (globalState.isAppControllerReady) {
      globalState.appController
        ..updateCurrentSelectedMap(groupName, proxyName)
        ..changeProxyDebounce(groupName, proxyName);
    }
    final current =
        ref.read(profilesProvider).getProfile(profile.id) ?? profile;
    if (current.selectedMap[groupName] != proxyName ||
        current.currentGroupName != groupName) {
      final selectedMap = Map<String, String>.from(current.selectedMap)
        ..[groupName] = proxyName;
      ref.read(profilesProvider.notifier).setProfile(
            current.copyWith(
              selectedMap: selectedMap,
              currentGroupName: groupName,
            ),
          );
    }
    final feedback = appLocalizations.nodeOverviewSwitchedToNode(
        current.label ?? current.id, proxyName);
    ref.read(_overviewSwitchTrackerProvider).feedback = feedback;
    if (mounted) {
      setState(() {
        _feedback = feedback;
      });
    }
  }

  void _useCatalogNode(
      Profile profile, CatalogNode node, String targetGroup) {
    detectionState.notifyRoutingChanged();
    ref.read(nodeCountryResolverProvider).markSwitchingNode();
    if (_tester.busy) {
      unawaited(_tester.cancel());
    }
    final latest =
        ref.read(profilesProvider).getProfile(profile.id) ?? profile;
    final selectedMap = Map<String, String>.from(latest.selectedMap)
        ..[targetGroup] = node.name;
    final updated = latest.copyWith(
      selectedMap: selectedMap,
      currentGroupName: targetGroup,
    );
    ref.read(profilesProvider.notifier).setProfile(updated);
    final tracker = ref.read(_overviewSwitchTrackerProvider);
    final currentActiveId = ref.read(currentProfileIdProvider);
    final verifiedRuntimeProfileId = globalState.lastRuntimeProfileId ??
        ref.read(activeNodeCatalogProvider)?.profileId;
    final currentGroups = ref.read(groupsProvider);
    final currentVersion = ref.read(versionProvider);
    final attestation = _resolveSnapshotAttestation(
      tracker,
      currentGroups,
      currentVersion,
    );
    final isAlreadyLiveActive = currentActiveId == updated.id &&
        (verifiedRuntimeProfileId == null ||
            verifiedRuntimeProfileId == updated.id) &&
        _isSnapshotLiveForProfile(
          profileId: updated.id,
          groups: currentGroups,
          attestation: attestation,
        ) &&
        tracker.pendingProfileId != updated.id;
    if (currentActiveId != updated.id) {
      tracker
        ..pendingProfileId = updated.id
        ..pendingProfileLabel = updated.label ?? updated.id
        ..pendingNodeName = node.name
        ..pendingGroups = currentGroups
        ..pendingVersion = currentVersion
        ..feedback = null;
      ref.read(currentProfileIdProvider.notifier).value = updated.id;
    } else if (!isAlreadyLiveActive) {
      tracker
        ..pendingProfileId = updated.id
        ..pendingProfileLabel = updated.label ?? updated.id
        ..pendingNodeName = node.name
        ..pendingGroups = currentGroups
        ..pendingVersion = currentVersion
        ..feedback = null;
      if (globalState.isAppControllerReady) {
        globalState.appController
          ..applyProfileDebounce(silence: true)
          ..changeProxyDebounce(targetGroup, node.name);
      }
    } else {
      if (globalState.isAppControllerReady) {
        globalState.appController.changeProxyDebounce(targetGroup, node.name);
      }
      tracker.feedback = appLocalizations.nodeOverviewSwitchedToNode(
          updated.label ?? updated.id, node.name);
    }
    if (mounted) {
      setState(() {
        _feedback = tracker.feedback;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final tester = ref.watch(nodeCatalogTesterProvider);
    final activeId = ref.watch(currentProfileIdProvider);
    final groups = ref.watch(groupsProvider);
    final version = ref.watch(versionProvider);
    final tracker = ref.watch(_overviewSwitchTrackerProvider);
    final verifiedRuntimeProfileId = globalState.lastRuntimeProfileId ??
        ref.watch(activeNodeCatalogProvider)?.profileId;
    final attestation = _resolveSnapshotAttestation(tracker, groups, version);
    final runtimeMatchesPending = tracker.pendingProfileId != null &&
        verifiedRuntimeProfileId == tracker.pendingProfileId &&
        attestation.verified &&
        attestation.profileId == tracker.pendingProfileId;
    if (tracker.pendingProfileId != null) {
      if (activeId != tracker.pendingProfileId) {
        tracker
          ..pendingProfileId = null
          ..pendingProfileLabel = null
          ..pendingNodeName = null
          ..pendingGroups = null
          ..pendingVersion = null;
      } else if (runtimeMatchesPending &&
          (!globalState.isSameGroupsList(groups, tracker.pendingGroups) ||
              version != tracker.pendingVersion)) {
        if (tracker.pendingProfileLabel != null &&
            tracker.pendingNodeName != null) {
          tracker.feedback = appLocalizations.nodeOverviewSwitchedToNode(
              tracker.pendingProfileLabel!, tracker.pendingNodeName!);
          _feedback = tracker.feedback;
        }
        tracker
          ..pendingProfileId = null
          ..pendingProfileLabel = null
          ..pendingNodeName = null
          ..pendingGroups = null
          ..pendingVersion = null;
      } else if (!runtimeMatchesPending) {
        tracker
          ..pendingGroups = groups
          ..pendingVersion = version;
      }
    } else if (activeId != null &&
        ((verifiedRuntimeProfileId != null &&
                verifiedRuntimeProfileId != activeId) ||
            !_isSnapshotLiveForProfile(
              profileId: activeId,
              groups: groups,
              attestation: attestation,
            ))) {
      tracker
        ..pendingProfileId = activeId
        ..pendingGroups = groups
        ..pendingVersion = version;
    }
    bool isLiveActive(Profile profile) =>
        profile.id == activeId &&
        (verifiedRuntimeProfileId == null ||
            verifiedRuntimeProfileId == profile.id) &&
        _isSnapshotLiveForProfile(
          profileId: profile.id,
          groups: groups,
          attestation: attestation,
        ) &&
        tracker.pendingProfileId != profile.id;
    final feedback = _feedback ?? tracker.feedback;
    final isMobile = ref.watch(isMobileViewProvider);
    final sort =
        ref.watch(proxiesStyleSettingProvider.select((s) => s.sortType));
    final selected =
        profiles.any((p) => p.id == _selectedProfile) ? _selectedProfile : null;
    final visible = selected == null
        ? profiles
        : profiles.where((p) => p.id == selected).toList();
    final countryResolver = ref.watch(nodeCountryResolverProvider);
    final cachedCatalogs = ref.watch(cachedProfileCatalogsProvider);
    final currentScript =
        ref.watch(scriptStateProvider.select((state) => state.currentScript));
    final query = ref.watch(proxiesQueryProvider).trim().toLowerCase();
    final searching = query.isNotEmpty;
    final locale = Localizations.localeOf(context);
    final scopeCountries = <String>{};
    final countryCounts = <String, int>{};
    var anyVisibleCatalogLoading = false;
    for (final profile in visible) {
      final liveActive = isLiveActive(profile);
      final shouldWatchCatalog = selected != null ||
          searching ||
          _selectedCountry != null ||
          _visibleProfileIds.contains(profile.id);
      final loaded = shouldWatchCatalog
          ? ref.watch(profileCatalogProvider(profile.id))
          : null;
      final catalog = loaded?.valueOrNull ?? cachedCatalogs[profile.id];
      if (catalog != null && catalog.status != ProfileCatalogStatus.loading) {
        _recordIndexedCatalog(profile, currentScript, catalog);
      }
      final indexedSummary = _indexedProfiles[profile.id];
      final validIndexed = indexedSummary != null &&
              indexedSummary.matchesProfile(profile, currentScript)
          ? indexedSummary
          : null;
      final pendingIndex = !liveActive &&
          catalog == null &&
          validIndexed == null &&
          !profile.isUpdating &&
          _indexingProfileIds.contains(profile.id);
      if (((loaded?.isLoading ?? false) && catalog == null) ||
          pendingIndex ||
          profile.isUpdating ||
          catalog?.status == ProfileCatalogStatus.loading ||
          catalog?.status == ProfileCatalogStatus.updating) {
        anyVisibleCatalogLoading = true;
      }
      final profileMatches =
          (profile.label ?? profile.id).toLowerCase().contains(query);
      if (liveActive) {
        final displays = _activeDisplays(
            ref, profile.id, profile.isUpdating ? null : catalog);
        final effectiveQuery = profileMatches ? '' : query;
        for (final entry in displays.values) {
          final code = countryResolver.resolveCountryCode(
            profileId: profile.id,
            profileLabel: profile.label,
            nodeName: entry.proxy.name,
            endpointKey: entry.node?.endpointKey,
            isLiveActive: true,
            inUse: entry.inUse,
          );
          scopeCountries.add(code);
          final matches =
              '${entry.proxy.name}\n${entry.fileSource ? entry.node!.type : entry.proxy.type}\n${entry.node?.providerName ?? ''}'
                  .toLowerCase()
                  .contains(effectiveQuery);
          if (!matches || (_availableOnly && (entry.delay ?? -1) <= 0)) {
            continue;
          }
          countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
        }
      } else {
        final health = ref.watch(nodeHealthEntriesProvider(profile.id));
        if (catalog != null) {
          for (final node in catalog.nodes) {
            final code = countryResolver.resolveCountryCode(
              profileId: profile.id,
              profileLabel: profile.label,
              nodeName: node.name,
              endpointKey: node.endpointKey,
            );
            scopeCountries.add(code);
            if (!(profileMatches || _matches(node, query)) ||
                (_availableOnly &&
                    (_nodeHealth(node, health)?.delayMs ?? -1) <= 0)) {
              continue;
            }
            countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
          }
        } else if (validIndexed != null) {
          for (final node in validIndexed.nodes) {
            final code = countryResolver.resolveCountryCode(
              profileId: profile.id,
              profileLabel: profile.label,
              nodeName: node.name,
              endpointKey: node.endpointKey,
            );
            scopeCountries.add(code);
            final matchesQuery = profileMatches ||
                '${node.name}\n${node.type}\n${node.providerName ?? ''}'
                    .toLowerCase()
                    .contains(query);
            final delayMs =
                node.parseFailed ? null : health[node.identityKey]?.delayMs;
            if (!matchesQuery || (_availableOnly && (delayMs ?? -1) <= 0)) {
              continue;
            }
            countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      }
    }
    final activeCountry = _selectedCountry != null &&
            (scopeCountries.contains(_selectedCountry) ||
                anyVisibleCatalogLoading)
        ? _selectedCountry
        : null;
    if (_selectedCountry != null &&
        activeCountry == null &&
        !anyVisibleCatalogLoading) {
      final staleCountry = _selectedCountry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedCountry == staleCountry) {
          setState(() => _selectedCountry = null);
        }
      });
    }
    if (activeCountry != null && !countryCounts.containsKey(activeCountry)) {
      countryCounts[activeCountry] = 0;
    }
    final showCountryChips =
        countryCounts.keys.any((code) => code != kUnknownCountryCode) ||
            activeCountry != null;
    final sortedCountries = showCountryChips
        ? sortCountryCodes(countryCounts.keys, countryCounts)
        : const <String>[];
    final activeCountryMatchCount =
        activeCountry == null ? 0 : (countryCounts[activeCountry] ?? 0);
    final now = DateTime.now();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = !isMobile && constraints.maxWidth > maxLaptopWidth;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!wide)
                  DropdownButton<String>(
                    key: const ValueKey('overview-profile-filter'),
                    value: selected ?? '',
                    items: [
                      DropdownMenuItem(
                          value: '',
                          child:
                              Text(appLocalizations.nodeOverviewAllProfiles)),
                      for (final profile in profiles)
                        DropdownMenuItem(
                            value: profile.id,
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                child: Text(profile.label ?? profile.id,
                                    overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (value) => setState(
                        () => _selectedProfile = value == '' ? null : value),
                  ),
                FilterChip(
                    label: Text(appLocalizations.nodeOverviewAvailableOnly),
                    selected: _availableOnly,
                    onSelected: (value) =>
                        setState(() => _availableOnly = value)),
                DropdownButton<ProxiesSortType>(
                  value: sort,
                  items: [
                    DropdownMenuItem(
                        value: ProxiesSortType.none,
                        child: Text(appLocalizations.defaultText)),
                    DropdownMenuItem(
                        value: ProxiesSortType.name,
                        child: Text(appLocalizations.name)),
                    DropdownMenuItem(
                        value: ProxiesSortType.delay,
                        child: Text(appLocalizations.delay)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(proxiesStyleSettingProvider.notifier)
                          .updateState(
                              (state) => state.copyWith(sortType: value));
                    }
                  },
                ),
                TextButton.icon(
                    key: const ValueKey('overview-test-current'),
                    onPressed: tester.busy ||
                            (selected == null &&
                                (activeId == null ||
                                    ref
                                        .watch(currentGroupsStateProvider)
                                        .value
                                        .isEmpty))
                        ? null
                        : () => _testCurrent(
                            selected == null ? null : visible.single),
                    icon: const Icon(Icons.speed),
                    label: Text(appLocalizations.nodeOverviewTestCurrent)),
                TextButton.icon(
                    key: const ValueKey('overview-test-all'),
                    onPressed: tester.busy || profiles.isEmpty
                        ? null
                        : () => _testAll(profiles),
                    icon: const Icon(Icons.bolt),
                    label: Text(appLocalizations.nodeOverviewTestAll)),
                for (final code in sortedCountries)
                  FilterChip(
                    key: ValueKey('overview-country-$code'),
                    label: _CountryLabelText(
                      emoji: nodeCountryEmoji(code),
                      text:
                          '${nodeCountryName(code, locale: locale)} (${countryCounts[code] ?? 0})',
                    ),
                    selected: activeCountry == code,
                    onSelected: (value) => setState(() {
                      _selectedCountry = value ? code : null;
                    }),
                  ),
                if (tester.busy) ...[
                  Text(appLocalizations.nodeOverviewProgress(
                      tester.completed, tester.total)),
                  TextButton.icon(
                      key: const ValueKey('overview-cancel'),
                      onPressed: () => unawaited(tester.cancel()),
                      icon: const Icon(Icons.close),
                      label: Text(appLocalizations.cancel)),
                ],
              ],
            ),
          ),
        ),
        if (tester.busy)
          LinearProgressIndicator(
              value: tester.total == 0
                  ? null
                  : (tester.completed / tester.total).clamp(0.0, 1.0)),
        if (feedback != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(feedback,
                      key: const ValueKey('overview-feedback')))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text(appLocalizations.nodeOverviewHistoryNotice,
                  style: Theme.of(context).textTheme.bodySmall)),
        ),
        Expanded(
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) ...[
              SizedBox(
                  width: 280,
                  child: ListView.builder(
                    key: const ValueKey('overview-sidebar'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 16),
                    itemCount: profiles.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                            key: const ValueKey('overview-select-all'),
                            title:
                                Text(appLocalizations.nodeOverviewAllProfiles),
                            selected: selected == null,
                            onTap: () =>
                                setState(() => _selectedProfile = null));
                      }
                      final profile = profiles[index - 1];
                      final isCurrent = profile.id == activeId;
                      return _SidebarProfileCard(
                          profile: profile,
                          selected: selected == profile.id,
                          active: isCurrent,
                          liveActive: isLiveActive(profile),
                          now: now,
                          onVisible: () =>
                              _onProfileVisibilityChanged(profile.id, true),
                          onSelect: () =>
                              setState(() => _selectedProfile = profile.id));
                    },
                  )),
              const VerticalDivider(width: 16),
            ],
            Expanded(
                child: CustomScrollView(
              key: const ValueKey('overview-nodes'),
              slivers: [
                for (final profile in visible)
                  _ProfileNodesSliver(
                      key: ValueKey('overview-section-${profile.id}'),
                      profile: profile,
                      active: profile.id == activeId,
                      liveActive: isLiveActive(profile),
                      showHeader: selected == null,
                      loadImmediately:
                          selected != null || searching || activeCountry != null,
                      availableOnly: _availableOnly,
                      countryFilter: activeCountry,
                      onVisibilityChanged: (isVisible) =>
                          _onProfileVisibilityChanged(profile.id, isVisible),
                      onTest: _testNode,
                      onUseActive: _useActiveNode,
                      onUseCatalog: _useCatalogNode,
                      now: now),
                if (selected == null &&
                    activeCountry != null &&
                    activeCountryMatchCount == 0 &&
                    !anyVisibleCatalogLoading)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      child: Text(appLocalizations.nodeOverviewNoNodes),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            )),
          ],
        )),
      ]);
    });
  }
}

class _SidebarProfileCard extends ConsumerWidget {
  const _SidebarProfileCard(
      {required this.profile,
      required this.selected,
      required this.active,
      required this.liveActive,
      required this.now,
      required this.onVisible,
      required this.onSelect});
  final Profile profile;
  final bool selected;
  final bool active;
  final bool liveActive;
  final DateTime now;
  final VoidCallback onVisible;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ListView builds only the visible/cached sidebar rows. Share the same
    // family future with the main section instead of starting a second parse.
    final loaded = ref.watch(profileCatalogProvider(profile.id));
    final catalog = loaded.valueOrNull ??
        ref.watch(cachedProfileCatalogsProvider)[profile.id];
    WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    return Card(
        color:
            selected ? Theme.of(context).colorScheme.secondaryContainer : null,
        child: InkWell(
          key: ValueKey('overview-select-${profile.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onSelect,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.label ?? profile.id,
                      style: Theme.of(context).textTheme.titleSmall),
                  if (active) Text(appLocalizations.nodeOverviewActive),
                  _HealthSummary(
                      profile: profile,
                      catalog: catalog,
                      liveActive: liveActive,
                      now: now),
                ],
              )),
        ));
  }
}

class _ProfileNodesSliver extends ConsumerStatefulWidget {
  const _ProfileNodesSliver(
      {super.key,
      required this.profile,
      required this.active,
      required this.liveActive,
      required this.showHeader,
      required this.loadImmediately,
      required this.availableOnly,
      required this.countryFilter,
      required this.onVisibilityChanged,
      required this.onTest,
      required this.onUseActive,
      required this.onUseCatalog,
      required this.now});
  final Profile profile;
  final bool active;
  final bool liveActive;
  final bool showHeader;
  final bool loadImmediately;
  final bool availableOnly;
  final String? countryFilter;
  final ValueChanged<bool> onVisibilityChanged;
  final void Function(Profile, CatalogNode) onTest;
  final void Function(Profile, String groupName, String proxyName) onUseActive;
  final void Function(Profile, CatalogNode, String targetGroup) onUseCatalog;
  final DateTime now;

  @override
  ConsumerState<_ProfileNodesSliver> createState() =>
      _ProfileNodesSliverState();
}

class _ProfileNodesSliverState extends ConsumerState<_ProfileNodesSliver> {
  bool _visible = false;
  bool _nextVisible = false;
  bool _visibilityScheduled = false;

  void _visibilityChanged(bool value) {
    _nextVisible = value;
    if (_visibilityScheduled || _visible == value) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (mounted && _visible != _nextVisible) {
        setState(() => _visible = _nextVisible);
        widget.onVisibilityChanged(_visible);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final loaded = widget.loadImmediately || _visible
        ? ref.watch(profileCatalogProvider(profile.id))
        : null;
    final catalog = loaded?.valueOrNull ??
        ref.watch(cachedProfileCatalogsProvider)[profile.id];
    final health = ref.watch(nodeHealthEntriesProvider(profile.id));
    final tester = ref.watch(nodeCatalogTesterProvider);
    final countryResolver = ref.watch(nodeCountryResolverProvider);
    final locale = Localizations.localeOf(context);
    final query = ref.watch(proxiesQueryProvider).trim().toLowerCase();
    final sort =
        ref.watch(proxiesStyleSettingProvider.select((s) => s.sortType));
    final mode =
        ref.watch(patchClashConfigProvider.select((state) => state.mode));
    final profileMatches =
        (profile.label ?? profile.id).toLowerCase().contains(query);
    final nodes = (catalog?.nodes ?? <CatalogNode>[])
        .where((node) {
          if (!(profileMatches || _matches(node, query))) return false;
          if (widget.availableOnly &&
              (_nodeHealth(node, health)?.delayMs ?? -1) <= 0) {
            return false;
          }
          if (widget.countryFilter != null) {
            final code = countryResolver.resolveCountryCode(
              profileId: profile.id,
              profileLabel: profile.label,
              nodeName: node.name,
              endpointKey: node.endpointKey,
            );
            if (code != widget.countryFilter) return false;
          }
          return true;
        })
        .toList();
    _sortNodes(nodes, health, sort);
    final isLoading = ((loaded?.isLoading ?? false) && catalog == null) ||
        catalog?.status == ProfileCatalogStatus.loading;
    if (widget.showHeader && widget.countryFilter != null) {
      if (widget.liveActive) {
        final effectiveQuery = profileMatches ? '' : query;
        final hasActiveMatch = _activeDisplays(
                ref, profile.id, profile.isUpdating ? null : catalog)
            .values
            .any((entry) {
          final matches =
              '${entry.proxy.name}\n${entry.fileSource ? entry.node!.type : entry.proxy.type}\n${entry.node?.providerName ?? ''}'
                  .toLowerCase()
                  .contains(effectiveQuery);
          if (!matches || (widget.availableOnly && (entry.delay ?? -1) <= 0)) {
            return false;
          }
          final code = countryResolver.resolveCountryCode(
            profileId: profile.id,
            profileLabel: profile.label,
            nodeName: entry.proxy.name,
            endpointKey: entry.node?.endpointKey,
            isLiveActive: true,
            inUse: entry.inUse,
          );
          return code == widget.countryFilter;
        });
        if (!hasActiveMatch) {
          return _PaintVisibilitySliver(
            onVisibilityChanged: _visibilityChanged,
            child: const SliverToBoxAdapter(child: SizedBox.shrink()),
          );
        }
      } else if (!isLoading && nodes.isEmpty) {
        return _PaintVisibilitySliver(
          onVisibilityChanged: _visibilityChanged,
          child: const SliverToBoxAdapter(child: SizedBox.shrink()),
        );
      }
    }
    final error = (loaded?.hasError ?? false) ||
        catalog?.status == ProfileCatalogStatus.fileMissing ||
        catalog?.status == ProfileCatalogStatus.parseFailed;
    return _PaintVisibilitySliver(
      onVisibilityChanged: _visibilityChanged,
      child: SliverMainAxisGroup(slivers: [
        if (widget.showHeader)
          SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedProfileHeader(
                  profile: profile, active: widget.active)),
        if (isLoading)
          const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator())),
        if (_expired(profile, widget.now))
          _notice(appLocalizations.nodeOverviewExpired),
        if (profile.isUpdating ||
            catalog?.status == ProfileCatalogStatus.updating)
          _notice(appLocalizations.nodeOverviewUpdating),
        if (error)
          _notice(catalog?.status == ProfileCatalogStatus.fileMissing
              ? appLocalizations.nodeOverviewFileMissing
              : catalog?.errorSummary == 'tooManyNodes'
                  ? appLocalizations.nodeOverviewTooManyNodes
                  : appLocalizations.nodeOverviewParseFailed),
        if (error || _expired(profile, widget.now))
          SliverToBoxAdapter(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextButton.icon(
                          onPressed: () => globalState.appController
                              .toPage(PageLabel.profiles),
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: Text(
                              appLocalizations.nodeOverviewManageProfiles))))),
        if (widget.liveActive)
          _ActiveNodes(
              profile: profile,
              fileCatalog: profile.isUpdating ? null : catalog,
              query: profileMatches ? '' : query,
              availableOnly: widget.availableOnly,
              countryFilter: widget.countryFilter,
              onUse: widget.onUseActive,
              now: widget.now,
              sort: sort)
        else if (nodes.isNotEmpty)
          SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                  itemCount: nodes.length,
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    final targetGroup =
                        _targetGroupForCatalogNode(profile, node, mode);
                    final countryCode = countryResolver.resolveCountryCode(
                      profileId: profile.id,
                      profileLabel: profile.label,
                      nodeName: node.name,
                      endpointKey: node.endpointKey,
                    );
                    final badgeCode = countryCode == kUnknownCountryCode
                        ? null
                        : countryCode;
                    return _InactiveNodeRow(
                        key: ValueKey(
                            'overview-node-${profile.id}-${node.identityKey}'),
                        node: node,
                        countryEmoji:
                            badgeCode == null ? null : nodeCountryEmoji(badgeCode),
                        countryName: badgeCode == null
                            ? null
                            : nodeCountryName(badgeCode, locale: locale),
                        pending: tester.pending(profile.id, node.identityKey),
                        testKey: ValueKey(
                            'overview-test-${profile.id}-${node.identityKey}'),
                        onTest: tester.busy ||
                                profile.isUpdating ||
                                catalog?.status != ProfileCatalogStatus.ready
                            ? null
                            : () => widget.onTest(profile, node),
                        useKey: ValueKey(
                            'overview-use-${profile.id}-${node.identityKey}'),
                        inUse: false,
                        onUse: targetGroup == null ||
                                profile.isUpdating ||
                                catalog?.status != ProfileCatalogStatus.ready
                            ? null
                            : () =>
                                widget.onUseCatalog(profile, node, targetGroup),
                        health: _nodeHealth(node, health),
                        now: widget.now);
                  }))
        else if (catalog?.status == ProfileCatalogStatus.ready)
          _notice(appLocalizations.nodeOverviewNoNodes),
        if (!widget.liveActive && catalog != null)
          for (final provider in catalog.providerNodeCounts.entries)
            if (provider.value < 0)
              _notice(
                  '${provider.key}: ${appLocalizations.nodeOverviewProviderUnloaded}'),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ]),
    );
  }

  Widget _notice(String text) => SliverToBoxAdapter(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(text)));
}

class _PinnedProfileHeader extends SliverPersistentHeaderDelegate {
  _PinnedProfileHeader({required this.profile, required this.active});
  final Profile profile;
  final bool active;
  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(
          color: Theme.of(context).colorScheme.surface,
          child: SizedBox.expand(
              child: Padding(
            key: ValueKey('overview-header-${profile.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Expanded(
                  child: Text(profile.label ?? profile.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall)),
              if (active)
                Text(appLocalizations.nodeOverviewActive,
                    style: Theme.of(context).textTheme.labelSmall),
            ]),
          )));
  @override
  bool shouldRebuild(covariant _PinnedProfileHeader oldDelegate) =>
      profile != oldDelegate.profile || active != oldDelegate.active;
}

/// A sliver's painted geometry is the viewport authority; mounted headers alone
/// are insufficient because CustomScrollView mounts every section sliver.
class _PaintVisibilitySliver extends SingleChildRenderObjectWidget {
  const _PaintVisibilitySliver(
      {required this.onVisibilityChanged, required super.child});
  final ValueChanged<bool> onVisibilityChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintVisibilitySliver(onVisibilityChanged);

  @override
  void updateRenderObject(
      BuildContext context, _RenderPaintVisibilitySliver renderObject) {
    renderObject.onVisibilityChanged = onVisibilityChanged;
  }
}

class _RenderPaintVisibilitySliver extends RenderProxySliver {
  _RenderPaintVisibilitySliver(this.onVisibilityChanged);
  ValueChanged<bool> onVisibilityChanged;
  bool? _visible;

  @override
  void performLayout() {
    super.performLayout();
    final visible = geometry?.visible ?? false;
    if (_visible != visible) {
      _visible = visible;
      onVisibilityChanged(visible);
    }
  }
}

NodeHealthRecord? _nodeHealth(
        CatalogNode node, Map<String, NodeHealthRecord> health) =>
    node.unsupported == CatalogUnsupportedReason.parseFailed
        ? null
        : health[node.identityKey];

bool _expired(Profile profile, DateTime now) {
  final expire = profile.subscriptionInfo?.expire ?? 0;
  return expire > 0 && expire * 1000 <= now.millisecondsSinceEpoch;
}

bool _matches(CatalogNode node, String query) =>
    '${node.name}\n${node.type}\n${node.providerName ?? ''}'
        .toLowerCase()
        .contains(query);

int _compareDelay(int? a, int? b) {
  final aRank = a != null && a > 0 ? a : 1 << 62;
  final bRank = b != null && b > 0 ? b : 1 << 62;
  return aRank.compareTo(bRank);
}

void _sortNodes(List<CatalogNode> nodes, Map<String, NodeHealthRecord> health,
    ProxiesSortType sort) {
  if (sort == ProxiesSortType.none) return;
  nodes.sort((a, b) {
    if (sort == ProxiesSortType.delay) {
      final result = _compareDelay(
          _nodeHealth(a, health)?.delayMs, _nodeHealth(b, health)?.delayMs);
      if (result != 0) return result;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

bool _isLeaf(Proxy proxy, Set<String> groupNames) =>
    !groupNames.contains(proxy.name) &&
    !{'direct', 'reject', 'reject-drop', 'pass', 'dns', 'compatible'}
        .contains(proxy.type.toLowerCase());

Map<String, CatalogNode> _uniqueCatalogNodes(ProfileCatalog? catalog) {
  final counts = <String, int>{};
  for (final node in catalog?.nodes ?? <CatalogNode>[]) {
    counts.update(node.name, (count) => count + 1, ifAbsent: () => 1);
  }
  return {
    for (final node in catalog?.nodes ?? <CatalogNode>[])
      if (counts[node.name] == 1 &&
          node.unsupported != CatalogUnsupportedReason.parseFailed)
        node.name: node
  };
}

Map<String, NodeHealthRecord> _activeHealthForUrl(
    WidgetRef ref, String profileId, String? testUrl) {
  final effectiveUrl = ref.watch(getRealTestUrlProvider(testUrl));
  if (effectiveUrl == ref.watch(nodeOverviewTestUrlProvider)) {
    return ref.watch(nodeHealthEntriesProvider(profileId));
  }
  // Card delays resolve the group's effective URL. Read the same URL's history
  // so a default-URL timestamp cannot be attached to a custom-URL result.
  return ref
      .watch(nodeHealthStoreProvider)
      .readProfile(profileId, testUrl: effectiveUrl);
}

// Explicit measurements keep their value and timestamp together until the next
// measurement. A transient live cancellation must not erase that result.
int? _activeDelay(int? live, NodeHealthRecord? history) =>
    live == 0 ? 0 : history?.delayMs ?? live;

String? _targetGroupForCatalogNode(
    Profile profile, CatalogNode node, Mode mode) {
  if (node.unsupported == CatalogUnsupportedReason.parseFailed) {
    return null;
  }
  final globalModeAllowed =
      profile.providerHeaders['flclashx-globalmode']?.toLowerCase() != 'false';
  final effectiveMode =
      mode == Mode.global && !globalModeAllowed ? Mode.rule : mode;
  return switch (effectiveMode) {
    Mode.direct => null,
    Mode.global => GroupName.GLOBAL.name,
    Mode.rule => node.selectGroups
        .where((name) => name != GroupName.GLOBAL.name)
        .firstOrNull,
  };
}

Widget _buildUseButton(
  BuildContext context, {
  required Key buttonKey,
  required bool inUse,
  required VoidCallback? onPressed,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextButton(
    key: buttonKey,
    onPressed: inUse ? null : onPressed,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: inUse
          ? colorScheme.secondaryContainer
          : colorScheme.surfaceContainerLow,
      foregroundColor: colorScheme.primary,
      disabledBackgroundColor: inUse ? colorScheme.secondaryContainer : null,
      disabledForegroundColor: inUse ? colorScheme.onSecondaryContainer : null,
    ),
    child: Text(
      inUse
          ? appLocalizations.nodeOverviewInUse
          : appLocalizations.nodeOverviewUseNode,
    ),
  );
}

Map<String, ({Proxy proxy, String? testUrl, String? selectGroup})>
    _activeLeaves(WidgetRef ref) {
  final rawMode =
      ref.watch(patchClashConfigProvider.select((state) => state.mode));
  final globalModeEnabled = ref.watch(globalModeEnabledProvider);
  final mode =
      rawMode == Mode.global && !globalModeEnabled ? Mode.rule : rawMode;
  final groups = ref.watch(currentGroupsStateProvider).value;
  final allGroups = ref.watch(groupsProvider);
  final groupNames = allGroups.map((g) => g.name).toSet();
  final selectorGroups = <String, String>{};
  if (mode == Mode.global) {
    final global = allGroups
        .where((g) =>
            g.name == GroupName.GLOBAL.name && g.type == GroupType.Selector)
        .firstOrNull;
    if (global != null) {
      for (final proxy in global.all.where((p) => _isLeaf(p, groupNames))) {
        selectorGroups[proxy.name] = global.name;
      }
    }
  } else if (mode == Mode.rule) {
    for (final group in groups) {
      if (group.type != GroupType.Selector) continue;
      for (final proxy in group.all.where((p) => _isLeaf(p, groupNames))) {
        selectorGroups.putIfAbsent(proxy.name, () => group.name);
      }
    }
  }
  final leaves =
      <String, ({Proxy proxy, String? testUrl, String? selectGroup})>{};
  for (final group in groups) {
    for (final proxy in group.all.where((p) => _isLeaf(p, groupNames))) {
      leaves.putIfAbsent(
          proxy.name,
          () => (
                proxy: proxy,
                testUrl: group.testUrl,
                selectGroup: selectorGroups[proxy.name],
              ));
    }
  }
  return leaves;
}

typedef _ActiveDisplay = ({
  Proxy proxy,
  CatalogNode? node,
  NodeHealthRecord? history,
  int? delay,
  bool fileSource,
  bool independent,
  String? selectGroup,
  bool inUse,
});

Map<String, _ActiveDisplay> _activeDisplays(
    WidgetRef ref, String profileId, ProfileCatalog? fileCatalog) {
  final runtime = ref.watch(activeNodeCatalogProvider);
  final runtimeNodes =
      _uniqueCatalogNodes(runtime?.profileId == profileId ? runtime : null);
  final fileNodes = _uniqueCatalogNodes(fileCatalog?.profileId == profileId &&
          fileCatalog?.status == ProfileCatalogStatus.ready
      ? fileCatalog
      : null);
  final allUrl = ref.watch(nodeOverviewTestUrlProvider);
  final allHistory = ref.watch(nodeHealthEntriesProvider(profileId));
  final groupHistory = <String?, Map<String, NodeHealthRecord>>{};
  return {
    for (final entry in _activeLeaves(ref).values)
      entry.proxy.name: () {
        var node = runtimeNodes[entry.proxy.name];
        NodeHealthRecord? history;
        var fileSource = false;
        var independent = false;
        if (node != null) {
          history = _nodeHealth(
              node,
              groupHistory.putIfAbsent(entry.testUrl,
                  () => _activeHealthForUrl(ref, profileId, entry.testUrl)));
          final allRecord = _nodeHealth(node, allHistory);
          if (allRecord != null &&
              (history == null ||
                  allRecord.testedAt.isAfter(history.testedAt))) {
            history = allRecord;
            independent =
                ref.watch(getRealTestUrlProvider(entry.testUrl)) != allUrl;
          }
        } else {
          // Name is only a display association. File endpoints never attest
          // runtime identity, and ambiguous names cannot select file history.
          final candidate = fileNodes[entry.proxy.name];
          if (candidate?.source == CatalogNodeSource.provider) {
            history = _nodeHealth(candidate!, allHistory);
            if (history != null) {
              node = candidate;
              fileSource = independent = true;
            }
          }
        }
        final selectGroup = entry.selectGroup;
        final selectedProxyName = selectGroup == null
            ? null
            : ref.watch(getSelectedProxyNameProvider(selectGroup));
        return (
          proxy: entry.proxy,
          node: node,
          history: history,
          delay: _activeDelay(
              ref.watch(getDelayProvider(
                  proxyName: entry.proxy.name, testUrl: entry.testUrl)),
              history),
          fileSource: fileSource,
          independent: independent,
          selectGroup: selectGroup,
          inUse: selectGroup != null && selectedProxyName == entry.proxy.name,
        );
      }(),
  };
}

class _ActiveNodes extends ConsumerWidget {
  const _ActiveNodes(
      {required this.profile,
      required this.fileCatalog,
      required this.query,
      required this.availableOnly,
      required this.countryFilter,
      required this.onUse,
      required this.now,
      required this.sort});
  final Profile profile;
  final ProfileCatalog? fileCatalog;
  final String query;
  final bool availableOnly;
  final String? countryFilter;
  final void Function(Profile, String groupName, String proxyName) onUse;
  final DateTime now;
  final ProxiesSortType sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countryResolver = ref.watch(nodeCountryResolverProvider);
    final locale = Localizations.localeOf(context);
    final rows =
        _activeDisplays(ref, profile.id, fileCatalog).values.where((entry) {
      final matches =
          '${entry.proxy.name}\n${entry.fileSource ? entry.node!.type : entry.proxy.type}\n${entry.node?.providerName ?? ''}'
              .toLowerCase()
              .contains(query);
      if (!matches || (availableOnly && (entry.delay ?? -1) <= 0)) {
        return false;
      }
      if (countryFilter != null) {
        final code = countryResolver.resolveCountryCode(
          profileId: profile.id,
          profileLabel: profile.label,
          nodeName: entry.proxy.name,
          endpointKey: entry.node?.endpointKey,
          isLiveActive: true,
          inUse: entry.inUse,
        );
        if (code != countryFilter) return false;
      }
      return true;
    }).toList();
    if (sort != ProxiesSortType.none) {
      rows.sort((a, b) {
        if (sort == ProxiesSortType.delay) {
          final result = _compareDelay(a.delay, b.delay);
          if (result != 0) return result;
        }
        return a.proxy.name.toLowerCase().compareTo(b.proxy.name.toLowerCase());
      });
    }
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(appLocalizations.nodeOverviewNoNodes)));
    }
    return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final entry = rows[index];
              final countryCode = countryResolver.resolveCountryCode(
                profileId: profile.id,
                profileLabel: profile.label,
                nodeName: entry.proxy.name,
                endpointKey: entry.node?.endpointKey,
                isLiveActive: true,
                inUse: entry.inUse,
              );
              final badgeCode =
                  countryCode == kUnknownCountryCode ? null : countryCode;
              return _ActiveNodeRow(
                  key: ValueKey('overview-active-${entry.proxy.name}'),
                  proxy: entry.proxy,
                  node: entry.node,
                  countryEmoji:
                      badgeCode == null ? null : nodeCountryEmoji(badgeCode),
                  countryName: badgeCode == null
                      ? null
                      : nodeCountryName(badgeCode, locale: locale),
                  delay: entry.delay,
                  history: entry.history,
                  fileSource: entry.fileSource,
                  independent: entry.independent,
                  useKey: ValueKey(
                      'overview-use-${profile.id}-${entry.proxy.name}'),
                  inUse: entry.inUse,
                  onUse: entry.inUse ||
                          entry.selectGroup == null ||
                          profile.isUpdating
                      ? null
                      : () =>
                          onUse(profile, entry.selectGroup!, entry.proxy.name),
                  now: now);
            }));
  }
}

class _ActiveNodeRow extends StatelessWidget {
  const _ActiveNodeRow(
      {super.key,
      required this.proxy,
      required this.node,
      required this.countryEmoji,
      required this.countryName,
      required this.delay,
      required this.history,
      required this.fileSource,
      required this.independent,
      required this.useKey,
      required this.inUse,
      required this.onUse,
      required this.now});
  final Proxy proxy;
  final CatalogNode? node;
  final String? countryEmoji;
  final String? countryName;
  final int? delay;
  final NodeHealthRecord? history;
  final bool fileSource;
  final bool independent;
  final Key useKey;
  final bool inUse;
  final VoidCallback? onUse;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = utils.getDelayColor(delay);
    final source = node == null
        ? appLocalizations.nodeOverviewRuntimeSource
        : fileSource
            ? appLocalizations.nodeOverviewFileSource(_source(node!))
            : _source(node!);
    final type = fileSource ? node!.type : proxy.type;
    final description = [
      type,
      source,
      if (independent) appLocalizations.nodeOverviewIndependentTest,
    ].join(' · ');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(proxy.name)),
                const SizedBox(width: 8),
                if (delay == 0)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Text(
                      delay == null
                          ? appLocalizations.nodeOverviewUntested
                          : delay! > 0
                              ? '$delay ms'
                              : appLocalizations.nodeOverviewTestFailed,
                      style: TextStyle(color: color)),
                const SizedBox(width: 8),
                _buildUseButton(
                  context,
                  buttonKey: useKey,
                  inUse: inUse,
                  onPressed: onUse,
                ),
              ]),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (countryEmoji != null && countryName != null) ...[
                    _CountryBadge(emoji: countryEmoji!, name: countryName!),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  history == null
                      ? appLocalizations.nodeOverviewLive
                      : _testedAt(history!, now),
                  style: Theme.of(context).textTheme.bodySmall),
            ])));
  }
}

class _CountryLabelText extends StatelessWidget {
  const _CountryLabelText({
    required this.emoji,
    required this.text,
    this.style,
  });

  final String emoji;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: emoji,
              style: TextStyle(fontFamily: FontFamily.twEmoji.value),
            ),
            TextSpan(text: ' $text'),
          ],
        ),
      );
}

class _CountryBadge extends StatelessWidget {
  const _CountryBadge({
    required this.emoji,
    required this.name,
  });

  final String emoji;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: _CountryLabelText(
        emoji: emoji,
        text: name,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

String _source(CatalogNode node) => node.source == CatalogNodeSource.inline
    ? appLocalizations.nodeOverviewInline
    : node.providerName ?? appLocalizations.providers;

String _testedAt(NodeHealthRecord record, DateTime now) {
  final time = DateFormat.yMd().add_Hm().format(record.testedAt.toLocal());
  final label = appLocalizations.nodeOverviewLastTest(time);
  return record.isStale(now)
      ? '$label · ${appLocalizations.nodeOverviewStale}'
      : label;
}

class _InactiveNodeRow extends StatelessWidget {
  const _InactiveNodeRow(
      {super.key,
      required this.node,
      required this.countryEmoji,
      required this.countryName,
      required this.health,
      required this.now,
      required this.pending,
      required this.onTest,
      required this.testKey,
      required this.useKey,
      required this.inUse,
      required this.onUse});
  final CatalogNode node;
  final String? countryEmoji;
  final String? countryName;
  final NodeHealthRecord? health;
  final DateTime now;
  final bool pending;
  final VoidCallback? onTest;
  final Key testKey;
  final Key useKey;
  final bool inUse;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final invalid = node.unsupported == CatalogUnsupportedReason.parseFailed;
    final record = invalid ? null : health;
    final stale = record?.isStale(now) ?? false;
    final color = stale
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : utils.getDelayColor(record?.delayMs);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(node.name)),
                  const SizedBox(width: 8),
                  if (invalid)
                    Icon(Icons.help_outline,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)
                  else if (pending)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Text(
                        record == null
                            ? appLocalizations.nodeOverviewUntested
                            : record.delayMs > 0
                                ? '${record.delayMs} ms'
                                : appLocalizations.nodeOverviewTestFailed,
                        style: TextStyle(color: color)),
                  if (node.unsupported == CatalogUnsupportedReason.none)
                    IconButton(
                        key: testKey,
                        onPressed: onTest,
                        icon: const Icon(Icons.bolt),
                        tooltip: appLocalizations.nodeOverviewTestNode),
                  if (!invalid) ...[
                    if (node.unsupported != CatalogUnsupportedReason.none)
                      const SizedBox(width: 8),
                    _buildUseButton(
                      context,
                      buttonKey: useKey,
                      inUse: inUse,
                      onPressed: onUse,
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (countryEmoji != null && countryName != null) ...[
                      _CountryBadge(emoji: countryEmoji!, name: countryName!),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        '${node.type} · ${_source(node)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (node.unsupported != CatalogUnsupportedReason.none)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_unsupported(node.unsupported),
                          style: Theme.of(context).textTheme.bodySmall)),
                if (record != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_testedAt(record, now),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: color))),
              ],
            )));
  }
}

String _unsupported(CatalogUnsupportedReason reason) => switch (reason) {
      CatalogUnsupportedReason.parseFailed =>
        appLocalizations.nodeOverviewNodeUnidentified,
      CatalogUnsupportedReason.chainUnsupported =>
        appLocalizations.nodeOverviewChainUnsupported,
      CatalogUnsupportedReason.typeUnsupported =>
        appLocalizations.nodeOverviewTypeUnsupported,
      CatalogUnsupportedReason.providerNotCached =>
        appLocalizations.nodeOverviewProviderNotCached,
      CatalogUnsupportedReason.strictModeUnsupported =>
        appLocalizations.nodeOverviewStrictUnsupported,
      CatalogUnsupportedReason.none => '',
    };

String _testFailure(String reason) => switch (reason) {
      'healthStoreUnavailable' =>
        appLocalizations.nodeOverviewHealthStoreUnavailable,
      'providerUnsafeUrl' => appLocalizations.nodeOverviewProviderUnsafeUrl,
      'providerUnsafePath' => appLocalizations.nodeOverviewProviderUnsafePath,
      'providerDownloadFailed' =>
        appLocalizations.nodeOverviewProviderDownloadFailed,
      'providerTooLarge' => appLocalizations.nodeOverviewProviderTooLarge,
      'providerOptionsUnsupported' =>
        appLocalizations.nodeOverviewProviderOptionsUnsupported,
      'deadlineExceeded' => appLocalizations.nodeOverviewTestTimedOut,
      'ambiguousNode' => appLocalizations.nodeOverviewAmbiguousNode,
      'healthCapacityExceeded' =>
        appLocalizations.nodeOverviewHealthCapacityExceeded,
      'chainUnsupported' => appLocalizations.nodeOverviewChainUnsupported,
      'typeUnsupported' => appLocalizations.nodeOverviewTypeUnsupported,
      'providerNotCached' => appLocalizations.nodeOverviewProviderNotCached,
      'providerPending' ||
      'notSupportedInPreview' =>
        appLocalizations.nodeOverviewPreviewUnsupported,
      'strictModeUnsupported' => appLocalizations.nodeOverviewStrictUnsupported,
      'fileMissing' => appLocalizations.nodeOverviewFileMissing,
      'parseFailed' => appLocalizations.nodeOverviewParseFailed,
      'tooManyNodes' ||
      'overloaded' =>
        appLocalizations.nodeOverviewTooManyNodes,
      'updating' => appLocalizations.nodeOverviewUpdating,
      'cancelled' ||
      'uiInactive' ||
      'configChanged' ||
      'coreRestarted' ||
      'batchDeadlineExceeded' ||
      'transportFailure' ||
      'sessionClosed' =>
        appLocalizations.nodeOverviewTestInterrupted,
      'busy' => '${appLocalizations.delay}: ${appLocalizations.running}',
      _ => appLocalizations.nodeOverviewTestUnavailable,
    };

class _HealthSummary extends ConsumerWidget {
  const _HealthSummary(
      {required this.profile,
      required this.catalog,
      required this.liveActive,
      required this.now});
  final Profile profile;
  final ProfileCatalog? catalog;
  final bool liveActive;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(nodeHealthEntriesProvider(profile.id));
    final active = liveActive;
    final status = <Widget>[
      if (_expired(profile, now)) Text(appLocalizations.nodeOverviewExpired),
      if (profile.isUpdating ||
          catalog?.status == ProfileCatalogStatus.updating)
        Text(appLocalizations.nodeOverviewUpdating),
    ];
    if (!active &&
        (catalog == null || catalog!.status == ProfileCatalogStatus.loading)) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...status, const Text('—')]);
    }
    if (catalog?.status == ProfileCatalogStatus.fileMissing ||
        catalog?.status == ProfileCatalogStatus.parseFailed) {
      status.add(Text(catalog!.status == ProfileCatalogStatus.fileMissing
          ? appLocalizations.nodeOverviewFileMissing
          : catalog!.errorSummary == 'tooManyNodes'
              ? appLocalizations.nodeOverviewTooManyNodes
              : appLocalizations.nodeOverviewParseFailed));
      if (!active) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: status);
      }
    }
    final records = <NodeHealthRecord>[];
    final delays = <int>[];
    var total = catalog?.nodes
            .where((node) =>
                node.unsupported != CatalogUnsupportedReason.parseFailed)
            .length ??
        0;
    if (active) {
      final displays =
          _activeDisplays(ref, profile.id, profile.isUpdating ? null : catalog);
      total = displays.length;
      for (final entry in displays.values) {
        final displayedDelay = entry.delay;
        if (displayedDelay != null && displayedDelay != 0) {
          delays.add(displayedDelay);
        }
        if (entry.history != null) records.add(entry.history!);
      }
    } else {
      records.addAll((catalog?.nodes ?? <CatalogNode>[])
          .map((node) => _nodeHealth(node, entries))
          .whereType<NodeHealthRecord>());
      delays.addAll(records.map((record) => record.delayMs));
    }
    final success = delays.where((d) => d > 0).toList()..sort();
    final median = success.isEmpty
        ? '—'
        : '${success.length.isOdd ? success[success.length ~/ 2] : ((success[success.length ~/ 2 - 1] + success[success.length ~/ 2]) / 2).round()} ms';
    records.sort((a, b) => b.testedAt.compareTo(a.testedAt));
    // Group by the same color function as every node card, so future threshold
    // changes cannot leave the summary's proportions on an older scale.
    final bands = <Color, int>{};
    for (final delay in [...success, ...delays.where((delay) => delay < 0)]) {
      final color = utils.getDelayColor(delay)!;
      bands.update(color, (count) => count + 1, ifAbsent: () => 1);
    }
    if (total > delays.length) {
      bands[Theme.of(context).colorScheme.surfaceContainerHighest] =
          total - delays.length;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...status,
      Text(appLocalizations.nodeOverviewHealthCounts(
          success.length, delays.length, total)),
      if (!active &&
          catalog!.providerNodeCounts.values.any((count) => count < 0))
        Text(appLocalizations.nodeOverviewPartialSummary,
            style: Theme.of(context).textTheme.bodySmall),
      Text(appLocalizations.nodeOverviewMedian(median)),
      if (records.isNotEmpty)
        Text(_testedAt(records.first, now),
            style: Theme.of(context).textTheme.bodySmall),
      if (total > 0)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              label: appLocalizations.nodeOverviewHealthCounts(
                  success.length, delays.length, total),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(children: [
                    for (final band in bands.entries)
                      Expanded(
                          flex: band.value,
                          child: Container(height: 5, color: band.key)),
                  ])),
            )),
    ]);
  }
}
