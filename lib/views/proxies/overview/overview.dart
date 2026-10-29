import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
import 'package:flclashx/views/profiles/add_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

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
  ref
    ..listen<List<Group>>(groupsProvider, (_, __) => recordUpdate())
    ..listen<int>(versionProvider, (_, __) => recordUpdate());
  return tracker;
});

typedef _ExplicitLiveMeasurement = ({int delayMs, DateTime testedAt});

class _OverviewExplicitLiveResultsNotifier extends AutoDisposeNotifier<
    Map<(String, String, String), _ExplicitLiveMeasurement>> {
  @override
  Map<(String, String, String), _ExplicitLiveMeasurement> build() {
    ref
      ..listen<String?>(currentProfileIdProvider, (previous, next) {
        if (previous == next || state.isEmpty) return;
        state = {
          for (final entry in state.entries)
            if (entry.key.$1 == next) entry.key: entry.value,
        };
      })
      ..listen<List<Profile>>(profilesProvider, (previous, next) {
        if (previous == null || state.isEmpty) return;
        final invalidatedIds = <String>{};
        for (final old in previous) {
          final updated = next.getProfile(old.id);
          if (updated == null ||
              updated.url != old.url ||
              updated.lastUpdateDate != old.lastUpdateDate ||
              updated.isUpdating != old.isUpdating) {
            invalidatedIds.add(old.id);
          }
        }
        if (invalidatedIds.isNotEmpty &&
            state.keys.any((key) => invalidatedIds.contains(key.$1))) {
          state = {
            for (final entry in state.entries)
              if (!invalidatedIds.contains(entry.key.$1))
                entry.key: entry.value,
          };
        }
      })
      ..listen<ScriptProps>(scriptStateProvider, (previous, next) {
        if (previous != null &&
            previous.currentScript != next.currentScript &&
            state.isNotEmpty) {
          state = const {};
        }
      });
    return const <(String, String, String), _ExplicitLiveMeasurement>{};
  }

  void merge(
    Map<(String, String, String), _ExplicitLiveMeasurement> updates,
  ) {
    if (updates.isEmpty) return;
    state = {...state, ...updates};
  }
}

final _overviewExplicitLiveResultsProvider = NotifierProvider.autoDispose<
    _OverviewExplicitLiveResultsNotifier,
    Map<(String, String, String), _ExplicitLiveMeasurement>>(
  _OverviewExplicitLiveResultsNotifier.new,
);

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
    required this.protocolSummary,
    required this.providerName,
    required this.parseFailed,
  });

  factory _IndexedNodeSummary.fromNode(CatalogNode node) => _IndexedNodeSummary(
        identityKey: node.identityKey,
        endpointKey: node.endpointKey,
        name: node.name,
        type: node.type,
        protocolSummary: node.protocolSummary,
        providerName: node.providerName,
        parseFailed: node.unsupported == CatalogUnsupportedReason.parseFailed,
      );

  final String identityKey;
  final String endpointKey;
  final String name;
  final String type;
  final String? protocolSummary;
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

class _IndexScanEpochState {
  _IndexScanEpochState(this.generation);

  final int generation;
  final Set<String> indexingProfileIds = <String>{};
  final Set<ProviderSubscription<Object?>> subscriptions =
      <ProviderSubscription<Object?>>{};
  int activeWorkers = 0;
  bool dirty = false;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    indexingProfileIds.clear();
    activeWorkers = 0;
    dirty = false;
    for (final sub in subscriptions.toList()) {
      sub.close();
    }
    subscriptions.clear();
  }
}

class _NodeOverviewViewState extends ConsumerState<NodeOverviewView> {
  static const int _maxIndexScanConcurrency = 2;

  String? _selectedProfile;
  String? _selectedCountry;
  bool _availableOnly = false;
  final Set<String> _visibleProfileIds = <String>{};
  final Map<String, _IndexedProfileCountrySummary> _indexedProfiles =
      <String, _IndexedProfileCountrySummary>{};
  final List<ProviderSubscription<Object?>> _lifecycleSubscriptions =
      <ProviderSubscription<Object?>>[];
  List<String> _stableProfileOrderIds = const <String>[];
  final Set<String> _updatingOrderFreezeIds = <String>{};
  final Set<String> _syncingProfileIds = <String>{};
  bool _importingSubscription = false;
  _IndexScanEpochState _scanEpoch = _IndexScanEpochState(0);
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
    _pumpCountryIndexWorkers(_scanEpoch);
  }

  void _pumpCountryIndexWorkers(_IndexScanEpochState epoch) {
    if (_disposed ||
        !mounted ||
        epoch.cancelled ||
        !identical(epoch, _scanEpoch)) {
      return;
    }
    final profiles = ref.read(profilesProvider);
    final currentScript = ref.read(scriptStateProvider).currentScript;
    final cachedCatalogs = ref.read(cachedProfileCatalogsProvider);
    for (final profile in profiles) {
      if (epoch.activeWorkers >= _maxIndexScanConcurrency) break;
      if (profile.isUpdating) continue;
      final existing = _indexedProfiles[profile.id];
      if (existing != null && existing.matchesProfile(profile, currentScript)) {
        continue;
      }
      final cached = cachedCatalogs[profile.id];
      if (cached != null && cached.status != ProfileCatalogStatus.loading) {
        _recordIndexedCatalog(profile, currentScript, cached);
        epoch.dirty = true;
        continue;
      }
      if (epoch.indexingProfileIds.contains(profile.id)) continue;
      epoch.indexingProfileIds.add(profile.id);
      epoch.activeWorkers++;
      unawaited(_indexSingleProfile(profile.id, epoch));
    }
    if (epoch.dirty &&
        (epoch.activeWorkers == 0 || _indexedProfiles.length % 8 == 0) &&
        mounted &&
        !_disposed &&
        !epoch.cancelled &&
        identical(epoch, _scanEpoch)) {
      epoch.dirty = false;
      setState(() {});
    }
  }

  Future<void> _indexSingleProfile(
    String profileId,
    _IndexScanEpochState epoch,
  ) async {
    ProviderSubscription<AsyncValue<ProfileCatalog>>? sub;
    try {
      if (_disposed ||
          !mounted ||
          epoch.cancelled ||
          !identical(epoch, _scanEpoch)) {
        return;
      }
      final snapshotAtStart = ref.read(profilesProvider).getProfile(profileId);
      sub = ref.listenManual(profileCatalogProvider(profileId), (_, __) {});
      epoch.subscriptions.add(sub);
      final catalog = await ref.read(profileCatalogProvider(profileId).future);
      if (_disposed ||
          !mounted ||
          epoch.cancelled ||
          !identical(epoch, _scanEpoch)) {
        return;
      }
      final profile = ref.read(profilesProvider).getProfile(profileId);
      final unchangedSinceStart = snapshotAtStart != null &&
          profile != null &&
          profile.url == snapshotAtStart.url &&
          profile.lastUpdateDate == snapshotAtStart.lastUpdateDate &&
          profile.isUpdating == snapshotAtStart.isUpdating;
      if (unchangedSinceStart && !profile.isUpdating) {
        final currentScript = ref.read(scriptStateProvider).currentScript;
        _recordIndexedCatalog(profile, currentScript, catalog);
        epoch.dirty = true;
      }
    } catch (_) {
      // Catalog load errors are surfaced through ProfileCatalogStatus.
    } finally {
      if (sub != null && epoch.subscriptions.remove(sub)) {
        sub.close();
      }
      if (!epoch.cancelled && identical(epoch, _scanEpoch)) {
        epoch.indexingProfileIds.remove(profileId);
        if (epoch.activeWorkers > 0) {
          epoch.activeWorkers--;
        }
        if (!_disposed && mounted) {
          _pumpCountryIndexWorkers(epoch);
        }
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
          final nextGen = _scanEpoch.generation + 1;
          _scanEpoch.cancel();
          _scanEpoch = _IndexScanEpochState(nextGen);
          _indexedProfiles.clear();
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
    _scanEpoch.cancel();
    for (final sub in _lifecycleSubscriptions) {
      sub.close();
    }
    _lifecycleSubscriptions.clear();
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

  Future<DelayBatchResult> _runExplicitCurrentTest(
    List<DelayTestTarget> targets,
  ) async {
    final activeId = ref.read(currentProfileIdProvider);
    if (activeId == null || targets.isEmpty) {
      return _tester.testCurrent(targets);
    }
    final requestedKeys = <(String, String)>{
      for (final target in targets)
        if (target.name.isNotEmpty) (target.name, target.url),
    };
    final startedTargets = <(String, String)>{};
    final convergedMeasurements = <(String, String), _ExplicitLiveMeasurement>{};
    final sub = ref.listenManual<DelayMap>(
      delayDataSourceProvider,
      (previous, next) {
        final observedAt = DateTime.now();
        for (final key in requestedKeys) {
          final prevVal = previous?[key.$2]?[key.$1];
          final nextVal = next[key.$2]?[key.$1];
          if (nextVal == prevVal) continue;
          if (nextVal == null) {
            startedTargets.remove(key);
            convergedMeasurements.remove(key);
          } else if (nextVal == 0) {
            startedTargets.add(key);
            convergedMeasurements.remove(key);
          } else if (startedTargets.contains(key)) {
            convergedMeasurements[key] = (
              delayMs: nextVal,
              testedAt: observedAt,
            );
          }
        }
      },
    );
    try {
      final result = await _tester.testCurrent(targets);
      if (!_disposed &&
          mounted &&
          result.completed > 0 &&
          ref.read(currentProfileIdProvider) == activeId &&
          convergedMeasurements.isNotEmpty) {
        final updates = <(String, String, String), _ExplicitLiveMeasurement>{};
        for (final entry in convergedMeasurements.entries) {
          // Preserve previous history if an in-flight target was cancelled or
          // interrupted by batch/session termination.
          if (entry.value.delayMs < 0 && result.reason != null) continue;
          updates[(activeId, entry.key.$1, entry.key.$2)] = entry.value;
        }
        ref.read(_overviewExplicitLiveResultsProvider.notifier).merge(updates);
      }
      return result;
    } finally {
      sub.close();
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
    unawaited(_run(() => _runExplicitCurrentTest(targets)));
  }

  void _testAll(List<Profile> profiles) => unawaited(_run(
      () => _tester.testAll(profiles, ref.read(nodeOverviewTestUrlProvider)),
      summarize: true));

  void _testNode(Profile profile, CatalogNode node) =>
      unawaited(_run(() => _tester.testVisible([
            (profile: profile, nodes: [node])
          ], ref.read(nodeOverviewTestUrlProvider))));

  void _testActiveNode(Proxy proxy, String? testUrl) {
    final state = ref.read(getProxyCardStateProvider(proxy.name));
    if (state.proxyName.isEmpty) return;
    final url = state.testUrl.getSafeValue(
      ref.read(getRealTestUrlProvider(testUrl)),
    );
    unawaited(
      _run(
        () => _runExplicitCurrentTest([DelayTestTarget(state.proxyName, url)]),
      ),
    );
  }

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

  Future<void> _syncSubscription(Profile targetProfile) async {
    if (_syncingProfileIds.contains(targetProfile.id)) return;
    final current =
        ref.read(profilesProvider).getProfile(targetProfile.id) ??
            targetProfile;
    if (current.type != ProfileType.url || current.isUpdating) return;
    if (!globalState.isAppControllerReady) return;
    final appController = globalState.appController;
    _syncingProfileIds.add(current.id);
    try {
      await globalState.safeRun(silence: false, () async {
        try {
          appController.setProfile(
            current.copyWith(
              isUpdating: true,
            ),
          );
          await appController.updateProfile(current);
        } catch (e) {
          final latest = mounted
              ? ref.read(profilesProvider).getProfile(current.id)
              : globalState.config.profiles.getProfile(current.id);
          final rollback = rollbackFailedProfileUpdate(latest);
          if (rollback != null) {
            appController.setProfile(rollback);
          }
          rethrow;
        }
      });
    } finally {
      _syncingProfileIds.remove(current.id);
    }
  }

  Future<void> _openUrlSubscriptionImport() async {
    if (_importingSubscription) return;
    setState(() {
      _importingSubscription = true;
    });
    try {
      final String? url;
      if (globalState.navigatorKey.currentState != null) {
        url = await globalState.showCommonDialog<String>(
          child: const URLFormDialog(),
        );
      } else {
        if (!mounted) return;
        url = await showDialog<String>(
          context: context,
          builder: (_) => const URLFormDialog(),
        );
      }
      if (url != null && url.isNotEmpty && globalState.isAppControllerReady) {
        await globalState.appController.addProfileFormURL(url);
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingSubscription = false;
        });
      } else {
        _importingSubscription = false;
      }
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
    final countryResolver = ref.watch(nodeCountryResolverProvider);
    final cachedCatalogs = ref.watch(cachedProfileCatalogsProvider);
    final currentScript =
        ref.watch(scriptStateProvider.select((state) => state.currentScript));
    final query = ref.watch(proxiesQueryProvider).trim().toLowerCase();
    final searching = query.isNotEmpty;
    final locale = Localizations.localeOf(context);
    final mode =
        ref.watch(patchClashConfigProvider.select((state) => state.mode));
    final currentGroups = ref.watch(currentGroupsStateProvider).value;
    final scopeCountries = <String>{};
    final countryCounts = <String, int>{};
    final availableCounts = <String, int>{};
    final pickerNodeStats =
        <String, ({bool isLoaded, int totalCount, String? statusIssue})>{};
    final originalIndexes = <String, int>{};
    final resolvedCatalogs = <String, ProfileCatalog?>{};
    var anyVisibleCatalogLoading = false;
    for (var i = 0; i < profiles.length; i++) {
      final profile = profiles[i];
      originalIndexes[profile.id] = i;
      final liveActive = isLiveActive(profile);
      final inSelectedScope = selected == null || selected == profile.id;
      final shouldWatchCatalog = selected == profile.id ||
          _visibleProfileIds.contains(profile.id) ||
          (inSelectedScope && (searching || _selectedCountry != null));
      final loaded = shouldWatchCatalog
          ? ref.watch(profileCatalogProvider(profile.id))
          : null;
      final catalog = loaded?.valueOrNull ?? cachedCatalogs[profile.id];
      resolvedCatalogs[profile.id] = catalog;
      final catalogReloadingAfterSync =
          ((loaded?.isLoading ?? false) && catalog == null) ||
              catalog?.status == ProfileCatalogStatus.loading ||
              catalog?.status == ProfileCatalogStatus.updating;
      if (profile.isUpdating) {
        _updatingOrderFreezeIds.add(profile.id);
      } else if (!catalogReloadingAfterSync) {
        _updatingOrderFreezeIds.remove(profile.id);
      }
      if (catalog != null && catalog.status != ProfileCatalogStatus.loading) {
        _recordIndexedCatalog(profile, currentScript, catalog);
      }
      final indexedSummary = _indexedProfiles[profile.id];
      final validIndexed = indexedSummary != null &&
              indexedSummary.matchesProfile(profile, currentScript)
          ? indexedSummary
          : null;
      if (inSelectedScope) {
        final pendingIndex = !liveActive &&
            catalog == null &&
            validIndexed == null &&
            !profile.isUpdating &&
            _scanEpoch.indexingProfileIds.contains(profile.id);
        if (((loaded?.isLoading ?? false) && catalog == null) ||
            pendingIndex ||
            profile.isUpdating ||
            catalog?.status == ProfileCatalogStatus.loading ||
            catalog?.status == ProfileCatalogStatus.updating) {
          anyVisibleCatalogLoading = true;
        }
      }
      final profileMatches =
          (profile.label ?? profile.id).toLowerCase().contains(query);
      if (liveActive) {
        final displays = _activeDisplays(
            ref, profile.id, profile.isUpdating ? null : catalog);
        availableCounts[profile.id] =
            displays.values.where((entry) => (entry.delay ?? -1) > 0).length;
        pickerNodeStats[profile.id] = (
          isLoaded: true,
          totalCount: displays.length,
          statusIssue: null,
        );
        if (inSelectedScope) {
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
            final matches = _activeEntryMatchesQuery(entry, effectiveQuery);
            if (!matches || (_availableOnly && (entry.delay ?? -1) <= 0)) {
              continue;
            }
            countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      } else {
        final health = ref.watch(nodeHealthEntriesProvider(profile.id));
        if (catalog != null) {
          final unusableCatalog =
              catalog.status == ProfileCatalogStatus.loading ||
                  catalog.status == ProfileCatalogStatus.fileMissing ||
                  catalog.status == ProfileCatalogStatus.parseFailed;
          availableCounts[profile.id] = unusableCatalog
              ? 0
              : catalog.nodes
                  .where(
                      (node) => (_nodeHealth(node, health)?.delayMs ?? -1) > 0)
                  .length;
          if (catalog.status == ProfileCatalogStatus.loading) {
            pickerNodeStats[profile.id] = (
              isLoaded: false,
              totalCount: 0,
              statusIssue: null,
            );
          } else if (catalog.status == ProfileCatalogStatus.fileMissing) {
            pickerNodeStats[profile.id] = (
              isLoaded: true,
              totalCount: 0,
              statusIssue: appLocalizations.nodeOverviewFileMissing,
            );
          } else if (catalog.status == ProfileCatalogStatus.parseFailed) {
            pickerNodeStats[profile.id] = (
              isLoaded: true,
              totalCount: 0,
              statusIssue: catalog.errorSummary == 'tooManyNodes'
                  ? appLocalizations.nodeOverviewTooManyNodes
                  : appLocalizations.nodeOverviewParseFailed,
            );
          } else {
            pickerNodeStats[profile.id] = (
              isLoaded: true,
              totalCount: catalog.nodes
                  .where(
                    (node) =>
                        node.unsupported !=
                        CatalogUnsupportedReason.parseFailed,
                  )
                  .length,
              statusIssue: null,
            );
          }
          if (inSelectedScope) {
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
              countryCounts.update(
                  code, (count) => count + 1, ifAbsent: () => 1);
            }
          }
        } else if (validIndexed != null) {
          final unusableIndexed =
              validIndexed.status == ProfileCatalogStatus.loading ||
                  validIndexed.status == ProfileCatalogStatus.fileMissing ||
                  validIndexed.status == ProfileCatalogStatus.parseFailed;
          availableCounts[profile.id] = unusableIndexed
              ? 0
              : validIndexed.nodes
                  .where((node) =>
                      !node.parseFailed &&
                      (health[node.identityKey]?.delayMs ?? -1) > 0)
                  .length;
          if (validIndexed.status == ProfileCatalogStatus.loading) {
            pickerNodeStats[profile.id] = (
              isLoaded: false,
              totalCount: 0,
              statusIssue: null,
            );
          } else if (validIndexed.status == ProfileCatalogStatus.fileMissing) {
            pickerNodeStats[profile.id] = (
              isLoaded: true,
              totalCount: 0,
              statusIssue: appLocalizations.nodeOverviewFileMissing,
            );
          } else if (validIndexed.status == ProfileCatalogStatus.parseFailed) {
            pickerNodeStats[profile.id] = (
              isLoaded: true,
              totalCount: 0,
              statusIssue: appLocalizations.nodeOverviewParseFailed,
            );
          } else {
            pickerNodeStats[profile.id] = (
              isLoaded: true,
              totalCount:
                  validIndexed.nodes.where((node) => !node.parseFailed).length,
              statusIssue: null,
            );
          }
          if (inSelectedScope) {
            for (final node in validIndexed.nodes) {
              final code = countryResolver.resolveCountryCode(
                profileId: profile.id,
                profileLabel: profile.label,
                nodeName: node.name,
                endpointKey: node.endpointKey,
              );
              scopeCountries.add(code);
              final matchesQuery = profileMatches ||
                  '${node.name}\n${node.type}\n${node.protocolSummary ?? ''}\n${node.providerName ?? ''}'
                      .toLowerCase()
                      .contains(query);
              final delayMs =
                  node.parseFailed ? null : health[node.identityKey]?.delayMs;
              if (!matchesQuery || (_availableOnly && (delayMs ?? -1) <= 0)) {
                continue;
              }
              countryCounts.update(
                  code, (count) => count + 1, ifAbsent: () => 1);
            }
          }
        } else {
          availableCounts[profile.id] = 0;
          pickerNodeStats[profile.id] = (
            isLoaded: false,
            totalCount: 0,
            statusIssue: null,
          );
        }
      }
    }
    _updatingOrderFreezeIds.retainAll(originalIndexes.keys);
    final List<Profile> orderedProfiles;
    if (_stableProfileOrderIds.isNotEmpty &&
        (tester.busy || _updatingOrderFreezeIds.isNotEmpty)) {
      final byId = <String, Profile>{
        for (final profile in profiles) profile.id: profile,
      };
      orderedProfiles = <Profile>[
        for (final id in _stableProfileOrderIds)
          if (byId.remove(id) case final Profile existing) existing,
        ...byId.values,
      ];
    } else {
      orderedProfiles = profiles.toList()
        ..sort((a, b) {
          final byAvailable = (availableCounts[b.id] ?? 0)
              .compareTo(availableCounts[a.id] ?? 0);
          if (byAvailable != 0) return byAvailable;
          return (originalIndexes[a.id] ?? 0)
              .compareTo(originalIndexes[b.id] ?? 0);
        });
      _stableProfileOrderIds = <String>[
        for (final profile in orderedProfiles) profile.id,
      ];
    }
    final visible = selected == null
        ? orderedProfiles
        : orderedProfiles.where((p) => p.id == selected).toList();
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
    final targetTestProfile = selected != null
        ? visible.firstOrNull
        : (activeId == null ? null : profiles.getProfile(activeId));
    final testCurrentAction = tester.busy ||
            (targetTestProfile?.isUpdating ?? false) ||
            (selected != null && targetTestProfile == null) ||
            (selected == null && (activeId == null || currentGroups.isEmpty))
        ? null
        : () => _testCurrent(selected == null ? null : targetTestProfile);
    VoidCallback? resolveQuickUseAction() {
      for (final profile in visible) {
        if (profile.isUpdating) {
          return null;
        }
        final profileMatches =
            (profile.label ?? profile.id).toLowerCase().contains(query);
        final catalog = resolvedCatalogs[profile.id];
        if (isLiveActive(profile)) {
          final effectiveQuery = profileMatches ? '' : query;
          final rows = _activeDisplays(
            ref,
            profile.id,
            profile.isUpdating ? null : catalog,
          ).values.where((entry) {
            final matches = _activeEntryMatchesQuery(entry, effectiveQuery);
            if (!matches || (_availableOnly && (entry.delay ?? -1) <= 0)) {
              return false;
            }
            if (activeCountry != null) {
              final code = countryResolver.resolveCountryCode(
                profileId: profile.id,
                profileLabel: profile.label,
                nodeName: entry.proxy.name,
                endpointKey: entry.node?.endpointKey,
                isLiveActive: true,
                inUse: entry.inUse,
              );
              if (code != activeCountry) return false;
            }
            return true;
          }).toList();
          if (rows.isEmpty) {
            continue;
          }
          if (sort != ProxiesSortType.none) {
            rows.sort((a, b) {
              if (sort == ProxiesSortType.delay) {
                final result = _compareDelay(a.delay, b.delay);
                if (result != 0) return result;
              }
              return a.proxy.name
                  .toLowerCase()
                  .compareTo(b.proxy.name.toLowerCase());
            });
          }
          for (final entry in rows) {
            if (entry.selectGroup != null &&
                (entry.delay == null || entry.delay! >= 0)) {
              final targetGroup = entry.selectGroup!;
              final targetProxy = entry.proxy.name;
              return () => _useActiveNode(profile, targetGroup, targetProxy);
            }
          }
          return null;
        }
        if (catalog == null ||
            catalog.status == ProfileCatalogStatus.loading ||
            catalog.status == ProfileCatalogStatus.updating) {
          return null;
        }
        if (catalog.status != ProfileCatalogStatus.ready) {
          if (_availableOnly || activeCountry != null || query.isNotEmpty) {
            continue;
          }
          return null;
        }
        final health = ref.watch(nodeHealthEntriesProvider(profile.id));
        final nodes = catalog.nodes.where((node) {
          final matches = profileMatches || _matches(node, query);
          if (!matches ||
              (_availableOnly &&
                  (_nodeHealth(node, health)?.delayMs ?? -1) <= 0)) {
            return false;
          }
          if (activeCountry != null) {
            final code = countryResolver.resolveCountryCode(
              profileId: profile.id,
              profileLabel: profile.label,
              nodeName: node.name,
              endpointKey: node.endpointKey,
            );
            if (code != activeCountry) return false;
          }
          return true;
        }).toList();
        if (nodes.isEmpty) {
          continue;
        }
        _sortNodes(nodes, health, sort);
        for (final node in nodes) {
          final delayMs = _nodeHealth(node, health)?.delayMs;
          if (delayMs != null && delayMs < 0) {
            continue;
          }
          final targetGroup = _targetGroupForCatalogNode(profile, node, mode);
          if (targetGroup != null) {
            return () => _useCatalogNode(profile, node, targetGroup);
          }
        }
        return null;
      }
      return null;
    }

    final quickUseAction = resolveQuickUseAction();
    final now = DateTime.now();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = !isMobile && constraints.maxWidth > maxLaptopWidth;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!wide)
                  _OverviewProfileSelector(
                    buttonKey: const ValueKey('overview-profile-filter'),
                    selectedProfileId: selected,
                    maxTriggerWidth: math.max(156.0, constraints.maxWidth - 32),
                    items: [
                      for (final profile in orderedProfiles)
                        () {
                          final stats = pickerNodeStats[profile.id];
                          final (expiryLabel, expiryTone) =
                              _resolvePickerExpiry(profile, now);
                          return (
                            id: profile.id,
                            label: profile.label ?? profile.id,
                            isActive: profile.id == activeId,
                            isUpdating: profile.isUpdating,
                            isLoaded: stats?.isLoaded ?? false,
                            availableCount: availableCounts[profile.id] ?? 0,
                            totalCount: stats?.totalCount ?? 0,
                            statusIssue: stats?.statusIssue,
                            expiryLabel: expiryLabel,
                            expiryTone: expiryTone,
                          );
                        }(),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedProfile = value),
                  ),
                _OverviewAvailableFilterButton(
                  key: const ValueKey('overview-available-only'),
                  selected: _availableOnly,
                  onChanged: (value) => setState(() => _availableOnly = value),
                ),
                _OverviewSortSelector(
                  value: sort,
                  onChanged: (value) {
                    ref
                        .read(proxiesStyleSettingProvider.notifier)
                        .updateState((state) => state.copyWith(sortType: value));
                  },
                ),
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
                  width: 296,
                  child: ListView.builder(
                    key: const ValueKey('overview-sidebar'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 16),
                    itemCount: orderedProfiles.length + 1,
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
                      final profile = orderedProfiles[index - 1];
                      final isCurrent = profile.id == activeId;
                      return _SidebarProfileCard(
                          key: ValueKey('overview-sidebar-card-${profile.id}'),
                          profile: profile,
                          selected: selected == profile.id,
                          active: isCurrent,
                          liveActive: isLiveActive(profile),
                          now: now,
                          onSync: profile.type == ProfileType.url
                              ? () => unawaited(_syncSubscription(profile))
                              : null,
                          onVisible: () =>
                              _onProfileVisibilityChanged(profile.id, true),
                          onSelect: () =>
                              setState(() => _selectedProfile = profile.id));
                    },
                  )),
              const VerticalDivider(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OverviewQuickWorkflowBar(
                    key: const ValueKey('overview-workflow-bar'),
                    onAddSubscription: _importingSubscription
                        ? null
                        : () => unawaited(_openUrlSubscriptionImport()),
                    onTestCurrent: testCurrentAction,
                    onQuickUse: quickUseAction,
                  ),
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
                              showSubscriptionSummary:
                                  !wide || selected != null,
                              onSyncSubscription:
                                  profile.type == ProfileType.url &&
                                          (!wide || selected != null)
                                      ? () =>
                                          unawaited(_syncSubscription(profile))
                                      : null,
                              syncButtonKey: wide
                                  ? ValueKey(
                                      'overview-detail-sync-${profile.id}')
                                  : ValueKey('overview-sync-${profile.id}'),
                              loadImmediately: selected != null ||
                                  searching ||
                                  activeCountry != null,
                              availableOnly: _availableOnly,
                              countryFilter: activeCountry,
                              onVisibilityChanged: (isVisible) =>
                                  _onProfileVisibilityChanged(
                                      profile.id, isVisible),
                              onTest: _testNode,
                              onTestActive: _testActiveNode,
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
                    ),
                  ),
                ],
              ),
            ),
          ],
        )),
      ]);
    });
  }
}

class _OverviewQuickWorkflowBar extends StatelessWidget {
  const _OverviewQuickWorkflowBar({
    super.key,
    required this.onAddSubscription,
    required this.onTestCurrent,
    required this.onQuickUse,
  });

  final VoidCallback? onAddSubscription;
  final VoidCallback? onTestCurrent;
  final VoidCallback? onQuickUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(
            alpha: isDark ? 0.56 : 0.72,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.outlineVariant.withValues(
              alpha: isDark ? 0.46 : 0.58,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _WorkflowStepButton(
                buttonKey: const ValueKey('overview-add-subscription'),
                stepNumber: 1,
                icon: Icons.add_link_rounded,
                label: appLocalizations.nodeOverviewAddSubscription,
                onPressed: onAddSubscription,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WorkflowStepArrow(
                    key: const ValueKey('overview-workflow-arrow-1'),
                    active: onTestCurrent != null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _WorkflowStepButton(
                      buttonKey: const ValueKey('overview-test-current'),
                      stepNumber: 2,
                      icon: Icons.speed_rounded,
                      label: appLocalizations.nodeOverviewTestCurrent,
                      onPressed: onTestCurrent,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WorkflowStepArrow(
                    key: const ValueKey('overview-workflow-arrow-2'),
                    active: onQuickUse != null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _WorkflowStepButton(
                      buttonKey: const ValueKey('overview-quick-use'),
                      stepNumber: 3,
                      icon: Icons.play_arrow_rounded,
                      label: appLocalizations.nodeOverviewQuickUse,
                      onPressed: onQuickUse,
                      emphasized: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowStepButton extends StatelessWidget {
  const _WorkflowStepButton({
    required this.buttonKey,
    required this.stepNumber,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final Key buttonKey;
  final int stepNumber;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onPressed != null;

    final badgeBg = !enabled
        ? colors.onSurface.withValues(alpha: 0.08)
        : emphasized
            ? colors.primary.withValues(alpha: isDark ? 0.28 : 0.20)
            : colors.primary.withValues(alpha: isDark ? 0.16 : 0.11);
    final badgeFg = !enabled
        ? colors.onSurface.withValues(alpha: 0.38)
        : colors.primary;

    return TextButton(
      key: buttonKey,
      onPressed: onPressed,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceContainerHigh.withValues(
              alpha: isDark ? 0.24 : 0.38,
            );
          }
          final hovered = states.contains(WidgetState.hovered);
          if (emphasized) {
            return colors.primary.withValues(
              alpha: hovered ? (isDark ? 0.24 : 0.17) : (isDark ? 0.16 : 0.11),
            );
          }
          return hovered
              ? colors.surfaceContainerHighest.withValues(
                  alpha: isDark ? 0.78 : 0.94,
                )
              : colors.surfaceContainerHigh.withValues(
                  alpha: isDark ? 0.52 : 0.78,
                );
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.onSurface.withValues(alpha: 0.38);
          }
          return emphasized
              ? colors.primary
              : colors.onSurface.withValues(alpha: 0.92);
        }),
        overlayColor: WidgetStatePropertyAll(
          colors.primary.withValues(alpha: 0.08),
        ),
        shape: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          final hovered = states.contains(WidgetState.hovered);
          final focused = states.contains(WidgetState.focused);
          final Color borderColor;
          if (disabled) {
            borderColor = colors.outlineVariant.withValues(alpha: 0.32);
          } else if (focused) {
            borderColor = colors.primary.withValues(alpha: 0.72);
          } else if (emphasized) {
            borderColor =
                colors.primary.withValues(alpha: hovered ? 0.68 : 0.48);
          } else if (hovered) {
            borderColor = colors.outline.withValues(alpha: 0.58);
          } else {
            borderColor = colors.outlineVariant.withValues(alpha: 0.62);
          }
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderColor),
          );
        }),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBg,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$stepNumber',
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: badgeFg,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            icon,
            size: 15,
            color: !enabled
                ? colors.onSurface.withValues(alpha: 0.38)
                : emphasized
                    ? colors.primary
                    : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowStepArrow extends StatelessWidget {
  const _WorkflowStepArrow({
    super.key,
    required this.active,
  });

  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return ExcludeSemantics(
      child: SizedBox(
        width: 34,
        height: 18,
        child: CustomPaint(
          painter: _WorkflowArrowPainter(
            color: active ? colors.primary : colors.outline,
            active: active,
            isDark: theme.brightness == Brightness.dark,
            isRtl: isRtl,
          ),
        ),
      ),
    );
  }
}

class _WorkflowArrowPainter extends CustomPainter {
  const _WorkflowArrowPainter({
    required this.color,
    required this.active,
    required this.isDark,
    required this.isRtl,
  });

  final Color color;
  final bool active;
  final bool isDark;
  final bool isRtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (isRtl) {
      canvas
        ..save()
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }

    final cy = size.height / 2;
    const startX = 3.5;
    final tipX = size.width - 3.5;
    final shaftEndX = tipX - 1.2;

    // 1. Subtle origin dot.
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: active ? 0.46 : 0.24);
    canvas.drawCircle(Offset(startX, cy), 2.0, dotPaint);

    // 2. Gradient shaft fading into crisp arrowhead.
    final shaftRect = Rect.fromLTRB(startX, cy - 2, tipX, cy + 2);
    final shaftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: active ? 0.20 : 0.10),
          color.withValues(alpha: active ? 0.88 : 0.40),
        ],
      ).createShader(shaftRect);
    canvas.drawLine(Offset(startX + 2.5, cy), Offset(shaftEndX, cy), shaftPaint);

    // 3. Soft trailing motion chevron.
    final trailX = tipX - 6.8;
    final trailPath = Path()
      ..moveTo(trailX - 3.6, cy - 3.4)
      ..lineTo(trailX, cy)
      ..lineTo(trailX - 3.6, cy + 3.4);
    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: active ? 0.38 : 0.18);
    canvas.drawPath(trailPath, trailPaint);

    // 4. Primary crisp arrowhead (+ subtle glow in dark mode when active).
    final headPath = Path()
      ..moveTo(tipX - 4.8, cy - 4.4)
      ..lineTo(tipX, cy)
      ..lineTo(tipX - 4.8, cy + 4.4);
    if (active && isDark) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2)
        ..color = color.withValues(alpha: 0.26);
      canvas.drawPath(headPath, glowPaint);
    }
    final headPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.85
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: active ? 0.94 : 0.44);
    canvas.drawPath(headPath, headPaint);

    if (isRtl) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WorkflowArrowPainter oldDelegate) =>
      color != oldDelegate.color ||
      active != oldDelegate.active ||
      isDark != oldDelegate.isDark ||
      isRtl != oldDelegate.isRtl;
}

enum _PickerExpiryTone {
  normal,
  perpetual,
  warning,
  expired,
  local,
}

typedef _ProfilePickerItemData = ({
  String id,
  String label,
  bool isActive,
  bool isUpdating,
  bool isLoaded,
  int availableCount,
  int totalCount,
  String? statusIssue,
  String? expiryLabel,
  _PickerExpiryTone? expiryTone,
});

(String?, _PickerExpiryTone?) _resolvePickerExpiry(
  Profile profile,
  DateTime now,
) {
  final sub = _hasMeaningfulSubscriptionInfo(profile.subscriptionInfo)
      ? profile.subscriptionInfo
      : null;
  if (sub != null) {
    final expireDate = _parseSubscriptionExpireLocal(sub.expire);
    if (expireDate == null) {
      return (
        appLocalizations.nodeOverviewPickerPerpetual,
        _PickerExpiryTone.perpetual,
      );
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(expireDate);
    final dateLabel = appLocalizations.nodeOverviewPickerExpireDate(dateStr);
    final diff = expireDate.difference(now);
    final isExpired = !expireDate.isAfter(now);
    if (isExpired) {
      return (
        '$dateLabel · ${appLocalizations.nodeOverviewStatusExpired}',
        _PickerExpiryTone.expired,
      );
    }
    final isExpiringSoon = diff.inDays <= 7;
    final String countdown;
    if (diff.inDays >= 1) {
      countdown = appLocalizations.nodeOverviewExpireDaysLeft(diff.inDays);
    } else if (diff.inHours >= 1) {
      countdown = appLocalizations.nodeOverviewExpireHoursLeft(diff.inHours);
    } else {
      countdown = appLocalizations.nodeOverviewExpireSoon;
    }
    return (
      '$dateLabel · $countdown',
      isExpiringSoon ? _PickerExpiryTone.warning : _PickerExpiryTone.normal,
    );
  }
  if (profile.url.isEmpty) {
    return (
      appLocalizations.nodeOverviewLocalProfile,
      _PickerExpiryTone.local,
    );
  }
  return (null, null);
}

class _OverviewProfileSelector extends StatefulWidget {
  const _OverviewProfileSelector({
    required this.buttonKey,
    required this.selectedProfileId,
    required this.maxTriggerWidth,
    required this.items,
    required this.onChanged,
  });

  final Key buttonKey;
  final String? selectedProfileId;
  final double maxTriggerWidth;
  final List<_ProfilePickerItemData> items;
  final ValueChanged<String?> onChanged;

  @override
  State<_OverviewProfileSelector> createState() =>
      _OverviewProfileSelectorState();
}

class _OverviewProfileSelectorState extends State<_OverviewProfileSelector> {
  final MenuController _controller = MenuController();
  bool _hovered = false;
  bool _focused = false;
  bool _isOpen = false;

  void _toggleMenu() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  static Color _statusDotColorFor(
    _ProfilePickerItemData item,
    ColorScheme colors, {
    required bool isDark,
  }) {
    if (item.expiryTone == _PickerExpiryTone.expired ||
        item.statusIssue != null) {
      return colors.error;
    }
    if (item.availableCount > 0) {
      return isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    }
    if (item.expiryTone == _PickerExpiryTone.warning) {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }
    return colors.outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final viewportWidth = MediaQuery.sizeOf(context).width;

    _ProfilePickerItemData? selectedItem;
    var allAvailable = 0;
    var allTotal = 0;
    var anyLoadedHealthy = false;
    for (final item in widget.items) {
      if (item.id == widget.selectedProfileId) {
        selectedItem = item;
      }
      if (item.isLoaded && item.statusIssue == null) {
        anyLoadedHealthy = true;
        allAvailable += item.availableCount;
        allTotal += item.totalCount;
      }
    }

    final isFiltered = selectedItem != null;
    final triggerLabel =
        selectedItem?.label ?? appLocalizations.nodeOverviewAllProfiles;
    final borderRadius = BorderRadius.circular(10);
    final inkBorderRadius = BorderRadius.circular(9);

    final backgroundColor = _isOpen
        ? colors.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.86 : 0.96,
          )
        : isFiltered
            ? colors.primary.withValues(
                alpha: _hovered
                    ? (isDark ? 0.19 : 0.13)
                    : (isDark ? 0.13 : 0.09),
              )
            : _hovered
                ? colors.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.68 : 0.88,
                  )
                : colors.surfaceContainerHigh.withValues(
                    alpha: isDark ? 0.45 : 0.65,
                  );
    final borderColor = _isOpen || _focused
        ? colors.primary.withValues(alpha: 0.72)
        : isFiltered
            ? colors.primary.withValues(alpha: _hovered ? 0.62 : 0.45)
            : _hovered
                ? colors.outline.withValues(alpha: 0.55)
                : colors.outlineVariant.withValues(alpha: 0.60);
    final labelColor =
        isFiltered ? colors.primary : colors.onSurface.withValues(alpha: 0.92);
    final accentIconColor =
        isFiltered || _isOpen ? colors.primary : colors.onSurfaceVariant;

    final panelWidth = math
        .min(
          math.max(216.0, viewportWidth - 24.0),
          math.max(348.0, (324.0 * textScale).ceilToDouble()),
        )
        .clamp(216.0, 420.0);
    final innerWidth = math.max(196.0, panelWidth - 16.0);
    final triggerMaxWidth = math.min(
      widget.maxTriggerWidth,
      math.max(256.0, (236.0 * textScale).ceilToDouble()),
    );
    final showInlineTriggerCount = selectedItem != null &&
        selectedItem.isLoaded &&
        selectedItem.statusIssue == null &&
        triggerMaxWidth >= 232 &&
        textScale <= 1.45;

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 8),
      onOpen: () {
        if (mounted && !_isOpen) setState(() => _isOpen = true);
      },
      onClose: () {
        if (mounted && _isOpen) setState(() => _isOpen = false);
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(isDark ? 10 : 6),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.48 : 0.18),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colors.outlineVariant.withValues(
                alpha: isDark ? 0.68 : 0.78,
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        Padding(
          key: const ValueKey('overview-profile-menu'),
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: innerWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        size: 14,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          appLocalizations.nodeOverviewSelectProfileTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: innerWidth * 0.44),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: isDark ? 0.72 : 0.90,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  colors.outlineVariant.withValues(alpha: 0.50),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            appLocalizations.nodeOverviewProfileCountBadge(
                              widget.items.length,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10.5,
                              height: 1.2,
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _OverviewAllProfilesOptionCard(
                  key: const ValueKey('overview-profile-option-all'),
                  selected: !isFiltered,
                  hasNodeSummary: anyLoadedHealthy,
                  availableCount: allAvailable,
                  totalCount: allTotal,
                  maxContentWidth: innerWidth - 20,
                  onTap: () {
                    _controller.close();
                    if (widget.selectedProfileId != null) {
                      widget.onChanged(null);
                    }
                  },
                ),
                if (widget.items.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Divider(
                      height: 1,
                      thickness: 0.6,
                      color: colors.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                for (var i = 0; i < widget.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 5),
                  _OverviewProfileOptionCard(
                    key: ValueKey(
                      'overview-profile-option-${widget.items[i].id}',
                    ),
                    item: widget.items[i],
                    selected: widget.items[i].id == widget.selectedProfileId,
                    maxContentWidth: innerWidth - 20,
                    onTap: () {
                      final targetId = widget.items[i].id;
                      _controller.close();
                      if (targetId != widget.selectedProfileId) {
                        widget.onChanged(targetId);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      child: Semantics(
        button: true,
        expanded: _isOpen,
        excludeSemantics: true,
        onTap: _toggleMenu,
        label:
            '${appLocalizations.nodeOverviewSelectProfileTitle}: $triggerLabel',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: triggerMaxWidth),
            child: AnimatedContainer(
              key: widget.buttonKey,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 36),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: borderRadius,
                border: Border.all(color: borderColor),
                boxShadow: _isOpen
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(
                            alpha: isDark ? 0.16 : 0.08,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: inkBorderRadius,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  splashColor: colors.primary.withValues(alpha: 0.10),
                  highlightColor: colors.primary.withValues(alpha: 0.06),
                  onFocusChange: (value) {
                    if (mounted && _focused != value) {
                      setState(() => _focused = value);
                    }
                  },
                  onTap: _toggleMenu,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selectedItem != null)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusDotColorFor(
                                selectedItem,
                                colors,
                                isDark: isDark,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.layers_rounded,
                            size: 15,
                            color: accentIconColor,
                          ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            triggerLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight: isFiltered
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              letterSpacing: 0.1,
                              color: labelColor,
                            ),
                          ),
                        ),
                        if (showInlineTriggerCount) ...[
                          Container(
                            width: 1,
                            height: 11,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color:
                                colors.outlineVariant.withValues(alpha: 0.65),
                          ),
                          Text(
                            '${selectedItem.availableCount}/${selectedItem.totalCount}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: selectedItem.availableCount > 0
                                  ? (isDark
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF15803D))
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _isOpen ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: accentIconColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewAllProfilesOptionCard extends StatefulWidget {
  const _OverviewAllProfilesOptionCard({
    super.key,
    required this.selected,
    required this.hasNodeSummary,
    required this.availableCount,
    required this.totalCount,
    required this.maxContentWidth,
    required this.onTap,
  });

  final bool selected;
  final bool hasNodeSummary;
  final int availableCount;
  final int totalCount;
  final double maxContentWidth;
  final VoidCallback onTap;

  @override
  State<_OverviewAllProfilesOptionCard> createState() =>
      _OverviewAllProfilesOptionCardState();
}

class _OverviewAllProfilesOptionCardState
    extends State<_OverviewAllProfilesOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selected = widget.selected;
    final borderRadius = BorderRadius.circular(11);

    final backgroundColor = selected
        ? colors.primary.withValues(
            alpha: _hovered ? (isDark ? 0.22 : 0.15) : (isDark ? 0.16 : 0.10),
          )
        : _hovered
            ? colors.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.72 : 0.88,
              )
            : colors.surface.withValues(alpha: isDark ? 0.34 : 0.52);
    final borderColor = selected
        ? colors.primary.withValues(alpha: isDark ? 0.48 : 0.38)
        : _hovered
            ? colors.outlineVariant.withValues(alpha: 0.75)
            : colors.outlineVariant.withValues(alpha: isDark ? 0.34 : 0.44);
    final titleColor =
        selected ? colors.primary : colors.onSurface.withValues(alpha: 0.94);

    final summaryText = widget.hasNodeSummary
        ? appLocalizations.nodeOverviewPickerAvailableNodes(
            widget.availableCount,
            widget.totalCount,
          )
        : null;
    final semanticLabel = [
      appLocalizations.nodeOverviewAllProfiles,
      if (summaryText != null) summaryText,
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: semanticLabel,
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: 0.9),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              hoverColor: Colors.transparent,
              focusColor: colors.primary.withValues(alpha: 0.10),
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.primary.withValues(
                                alpha: isDark ? 0.22 : 0.14,
                              )
                            : colors.surfaceContainerHighest.withValues(
                                alpha: isDark ? 0.70 : 0.85,
                              ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.layers_rounded,
                        size: 15,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            appLocalizations.nodeOverviewAllProfiles,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                          if (summaryText != null) ...[
                            const SizedBox(height: 4),
                            _PickerMetaPill(
                              icon: widget.availableCount > 0
                                  ? Icons.bolt_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              label: summaryText,
                              foreground: widget.availableCount > 0
                                  ? (isDark
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF15803D))
                                  : colors.onSurfaceVariant,
                              background: widget.availableCount > 0
                                  ? Colors.green.withValues(
                                      alpha: isDark ? 0.15 : 0.10,
                                    )
                                  : colors.surfaceContainerHighest.withValues(
                                      alpha: isDark ? 0.58 : 0.75,
                                    ),
                              border: widget.availableCount > 0
                                  ? Colors.green.withValues(
                                      alpha: isDark ? 0.34 : 0.28,
                                    )
                                  : colors.outlineVariant.withValues(
                                      alpha: 0.48,
                                    ),
                              maxWidth: math.max(
                                120.0,
                                widget.maxContentWidth - 48.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewProfileOptionCard extends StatefulWidget {
  const _OverviewProfileOptionCard({
    super.key,
    required this.item,
    required this.selected,
    required this.maxContentWidth,
    required this.onTap,
  });

  final _ProfilePickerItemData item;
  final bool selected;
  final double maxContentWidth;
  final VoidCallback onTap;

  @override
  State<_OverviewProfileOptionCard> createState() =>
      _OverviewProfileOptionCardState();
}

class _OverviewProfileOptionCardState
    extends State<_OverviewProfileOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;
    final selected = widget.selected;
    final borderRadius = BorderRadius.circular(11);

    final backgroundColor = selected
        ? colors.primary.withValues(
            alpha: _hovered ? (isDark ? 0.22 : 0.15) : (isDark ? 0.16 : 0.10),
          )
        : _hovered
            ? colors.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.72 : 0.88,
              )
            : colors.surface.withValues(alpha: isDark ? 0.34 : 0.52);
    final borderColor = selected
        ? colors.primary.withValues(alpha: isDark ? 0.48 : 0.38)
        : _hovered
            ? colors.outlineVariant.withValues(alpha: 0.75)
            : colors.outlineVariant.withValues(alpha: isDark ? 0.34 : 0.44);
    final titleColor =
        selected ? colors.primary : colors.onSurface.withValues(alpha: 0.94);

    final dotColor = _OverviewProfileSelectorState._statusDotColorFor(
      item,
      colors,
      isDark: isDark,
    );
    final maxPillWidth = math.max(120.0, widget.maxContentWidth - 16.0);

    final Widget availabilityPill;
    final String availabilitySemantic;
    if (item.statusIssue != null) {
      availabilitySemantic = item.statusIssue!;
      availabilityPill = _PickerMetaPill(
        icon: Icons.warning_amber_rounded,
        label: item.statusIssue!,
        foreground: colors.error,
        background: colors.error.withValues(alpha: isDark ? 0.15 : 0.10),
        border: colors.error.withValues(alpha: 0.34),
        maxWidth: maxPillWidth,
      );
    } else if (!item.isLoaded) {
      availabilitySemantic = '—';
      availabilityPill = _PickerMetaPill(
        icon: Icons.hourglass_empty_rounded,
        label: '—',
        foreground: colors.onSurfaceVariant,
        background: colors.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.55 : 0.72,
        ),
        border: colors.outlineVariant.withValues(alpha: 0.45),
        maxWidth: maxPillWidth,
      );
    } else {
      final hasAvailable = item.availableCount > 0;
      availabilitySemantic = appLocalizations.nodeOverviewPickerAvailableNodes(
        item.availableCount,
        item.totalCount,
      );
      availabilityPill = _PickerMetaPill(
        icon: hasAvailable
            ? Icons.bolt_rounded
            : Icons.radio_button_unchecked_rounded,
        label: availabilitySemantic,
        foreground: hasAvailable
            ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
            : colors.onSurfaceVariant,
        background: hasAvailable
            ? Colors.green.withValues(alpha: isDark ? 0.15 : 0.10)
            : colors.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.58 : 0.75,
              ),
        border: hasAvailable
            ? Colors.green.withValues(alpha: isDark ? 0.34 : 0.28)
            : colors.outlineVariant.withValues(alpha: 0.48),
        maxWidth: maxPillWidth,
      );
    }

    Widget? expiryPill;
    if (item.expiryLabel != null && item.expiryTone != null) {
      final (icon, fg, bg, border) = switch (item.expiryTone!) {
        _PickerExpiryTone.expired => (
            Icons.event_busy_outlined,
            colors.error,
            colors.error.withValues(alpha: isDark ? 0.15 : 0.10),
            colors.error.withValues(alpha: 0.34),
          ),
        _PickerExpiryTone.warning => (
            Icons.schedule_rounded,
            isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
            Colors.orange.withValues(alpha: isDark ? 0.15 : 0.11),
            Colors.orange.withValues(alpha: 0.34),
          ),
        _PickerExpiryTone.perpetual => (
            Icons.verified_outlined,
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.55 : 0.72,
            ),
            colors.outlineVariant.withValues(alpha: 0.46),
          ),
        _PickerExpiryTone.local => (
            Icons.description_outlined,
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.55 : 0.72,
            ),
            colors.outlineVariant.withValues(alpha: 0.46),
          ),
        _PickerExpiryTone.normal => (
            Icons.event_outlined,
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.55 : 0.72,
            ),
            colors.outlineVariant.withValues(alpha: 0.46),
          ),
      };
      expiryPill = _PickerMetaPill(
        icon: icon,
        label: item.expiryLabel!,
        foreground: fg,
        background: bg,
        border: border,
        maxWidth: maxPillWidth,
      );
    }

    final semanticLabel = [
      item.label,
      if (item.isActive) appLocalizations.nodeOverviewActive,
      availabilitySemantic,
      if (item.expiryLabel != null) item.expiryLabel!,
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: semanticLabel,
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: 0.9),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              hoverColor: Colors.transparent,
              focusColor: colors.primary.withValues(alpha: 0.10),
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dotColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                        if (item.isUpdating) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(colors.primary),
                            ),
                          ),
                        ],
                        if (item.isActive) ...[
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  math.min(92.0, widget.maxContentWidth * 0.42),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color:
                                      colors.primary.withValues(alpha: 0.36),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                appLocalizations.nodeOverviewActive,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10.5,
                                  height: 1.2,
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (selected) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: colors.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 14.5),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          availabilityPill,
                          if (expiryPill != null) expiryPill,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerMetaPill extends StatelessWidget {
  const _PickerMetaPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.maxWidth,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11.5, color: foreground),
              const SizedBox(width: 3.5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _OverviewAvailableFilterButton extends StatefulWidget {
  const _OverviewAvailableFilterButton({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  State<_OverviewAvailableFilterButton> createState() =>
      _OverviewAvailableFilterButtonState();
}

class _OverviewAvailableFilterButtonState
    extends State<_OverviewAvailableFilterButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selected = widget.selected;
    final borderRadius = BorderRadius.circular(10);
    final inkBorderRadius = BorderRadius.circular(9);

    final backgroundColor = selected
        ? colors.primary.withValues(
            alpha: _hovered ? (isDark ? 0.22 : 0.16) : (isDark ? 0.16 : 0.11),
          )
        : _hovered
            ? colors.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.68 : 0.88,
              )
            : colors.surfaceContainerHigh.withValues(
                alpha: isDark ? 0.45 : 0.65,
              );
    final borderColor = selected
        ? colors.primary.withValues(
            alpha: _hovered || _focused ? 0.78 : 0.60,
          )
        : _focused
            ? colors.primary.withValues(alpha: 0.65)
            : _hovered
                ? colors.outline.withValues(alpha: 0.55)
                : colors.outlineVariant.withValues(alpha: 0.60);
    final foregroundColor =
        selected ? colors.primary : colors.onSurface.withValues(alpha: 0.90);
    final iconColor = selected ? colors.primary : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      toggled: selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 36),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(
                        alpha: isDark ? 0.14 : 0.08,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: inkBorderRadius,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              splashColor: colors.primary.withValues(alpha: 0.10),
              highlightColor: colors.primary.withValues(alpha: 0.06),
              onFocusChange: (value) {
                if (mounted && _focused != value) {
                  setState(() => _focused = value);
                }
              },
              onTap: () => widget.onChanged(!selected),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 140),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.check_circle_outline_rounded,
                        key: ValueKey<bool>(selected),
                        size: 15,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        appLocalizations.nodeOverviewAvailableOnly,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewSortSelector extends StatefulWidget {
  const _OverviewSortSelector({
    required this.value,
    required this.onChanged,
  });

  final ProxiesSortType value;
  final ValueChanged<ProxiesSortType> onChanged;

  @override
  State<_OverviewSortSelector> createState() => _OverviewSortSelectorState();
}

class _OverviewSortSelectorState extends State<_OverviewSortSelector> {
  static const List<ProxiesSortType> _orderedOptions = [
    ProxiesSortType.none,
    ProxiesSortType.name,
    ProxiesSortType.delay,
  ];

  final MenuController _controller = MenuController();
  bool _hovered = false;
  bool _focused = false;
  bool _isOpen = false;

  static String _labelFor(ProxiesSortType type) => switch (type) {
        ProxiesSortType.none => appLocalizations.defaultText,
        ProxiesSortType.name => appLocalizations.name,
        ProxiesSortType.delay => appLocalizations.delay,
      };

  static IconData _iconFor(ProxiesSortType type) => switch (type) {
        ProxiesSortType.none => Icons.swap_vert_rounded,
        ProxiesSortType.name => Icons.sort_by_alpha_rounded,
        ProxiesSortType.delay => Icons.timer_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isCustomSort = widget.value != ProxiesSortType.none;
    final borderRadius = BorderRadius.circular(10);
    final inkBorderRadius = BorderRadius.circular(9);

    final backgroundColor = _isOpen
        ? colors.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.82 : 0.96,
          )
        : isCustomSort
            ? colors.primary.withValues(
                alpha: _hovered
                    ? (isDark ? 0.17 : 0.12)
                    : (isDark ? 0.11 : 0.08),
              )
            : _hovered
                ? colors.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.68 : 0.88,
                  )
                : colors.surfaceContainerHigh.withValues(
                    alpha: isDark ? 0.45 : 0.65,
                  );
    final borderColor = _isOpen || _focused
        ? colors.primary.withValues(alpha: 0.68)
        : isCustomSort
            ? colors.primary.withValues(alpha: _hovered ? 0.58 : 0.42)
            : _hovered
                ? colors.outline.withValues(alpha: 0.55)
                : colors.outlineVariant.withValues(alpha: 0.60);
    final valueColor = isCustomSort
        ? colors.primary
        : colors.onSurface.withValues(alpha: 0.92);
    final accentIconColor =
        isCustomSort || _isOpen ? colors.primary : colors.onSurfaceVariant;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final menuMaxWidth = math.max(210.0, (190.0 * textScale).ceilToDouble());

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 8),
      onOpen: () {
        if (mounted && !_isOpen) setState(() => _isOpen = true);
      },
      onClose: () {
        if (mounted && _isOpen) setState(() => _isOpen = false);
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(isDark ? 4 : 3),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.36 : 0.14),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colors.outlineVariant.withValues(
                alpha: isDark ? 0.65 : 0.75,
              ),
            ),
          ),
        ),
      ),
      menuChildren: [
        Padding(
          key: const ValueKey('overview-sort-menu'),
          padding: const EdgeInsets.all(5),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: 144, maxWidth: menuMaxWidth),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _orderedOptions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 2),
                    _OverviewSortOptionTile(
                      key: ValueKey(
                        'overview-sort-option-${_orderedOptions[i].name}',
                      ),
                      icon: _iconFor(_orderedOptions[i]),
                      label: _labelFor(_orderedOptions[i]),
                      selected: _orderedOptions[i] == widget.value,
                      onTap: () {
                        final selectedOption = _orderedOptions[i];
                        _controller.close();
                        if (selectedOption != widget.value) {
                          widget.onChanged(selectedOption);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
      child: Semantics(
        button: true,
        expanded: _isOpen,
        excludeSemantics: true,
        onTap: () {
          if (_controller.isOpen) {
            _controller.close();
          } else {
            _controller.open();
          }
        },
        label: '${appLocalizations.sort}: ${_labelFor(widget.value)}',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            key: const ValueKey('overview-sort-button'),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 36),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: inkBorderRadius,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                splashColor: colors.primary.withValues(alpha: 0.10),
                highlightColor: colors.primary.withValues(alpha: 0.06),
                onFocusChange: (value) {
                  if (mounted && _focused != value) {
                    setState(() => _focused = value);
                  }
                },
                onTap: () {
                  if (_controller.isOpen) {
                    _controller.close();
                  } else {
                    _controller.open();
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconFor(widget.value),
                        size: 15,
                        color: accentIconColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          appLocalizations.sort,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w400,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 11,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: colors.outlineVariant.withValues(alpha: 0.65),
                      ),
                      Flexible(
                        child: Text(
                          _labelFor(widget.value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            color: valueColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _isOpen ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: accentIconColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewSortOptionTile extends StatefulWidget {
  const _OverviewSortOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OverviewSortOptionTile> createState() =>
      _OverviewSortOptionTileState();
}

class _OverviewSortOptionTileState extends State<_OverviewSortOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selected = widget.selected;
    final borderRadius = BorderRadius.circular(8);

    final backgroundColor = selected
        ? colors.primary.withValues(
            alpha: _hovered ? (isDark ? 0.22 : 0.15) : (isDark ? 0.16 : 0.11),
          )
        : _hovered
            ? colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.06)
            : Colors.transparent;
    final foregroundColor =
        selected ? colors.primary : colors.onSurface.withValues(alpha: 0.92);
    final iconColor = selected ? colors.primary : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              hoverColor: Colors.transparent,
              focusColor: colors.primary.withValues(alpha: 0.10),
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 15, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 15,
                      child: selected
                          ? Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: colors.primary,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarProfileCard extends ConsumerWidget {
  const _SidebarProfileCard(
      {super.key,
      required this.profile,
      required this.selected,
      required this.active,
      required this.liveActive,
      required this.now,
      this.onSync,
      required this.onVisible,
      required this.onSelect});
  final Profile profile;
  final bool selected;
  final bool active;
  final bool liveActive;
  final DateTime now;
  final VoidCallback? onSync;
  final VoidCallback onVisible;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ListView builds only the visible/cached sidebar rows. Share the same
    // family future with the main section instead of starting a second parse.
    final loaded = ref.watch(profileCatalogProvider(profile.id));
    final catalog = loaded.valueOrNull ??
        ref.watch(cachedProfileCatalogsProvider)[profile.id];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final locale = Localizations.localeOf(context);
    final metadata = _resolveProfileMetadata(profile);
    final titleWidget = Text(
      profile.label ?? profile.id,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    final activeBadge = active
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.36),
                ),
              ),
              child: Text(
                appLocalizations.nodeOverviewActive,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        : null;
    final syncButton = onSync != null
        ? _ProfileSyncButton(
            key: ValueKey('overview-sync-${profile.id}'),
            updating: profile.isUpdating,
            selectedCard: selected,
            maxWidth: 118,
            onPressed: onSync,
          )
        : null;
    final splitActiveHeader = activeBadge != null &&
        syncButton != null &&
        (textScale > 1.15 ||
            locale.languageCode == 'ru' ||
            locale.languageCode == 'ja');
    WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    return Card(
        color: selected ? colors.secondaryContainer : null,
        child: InkWell(
          key: ValueKey('overview-select-${profile.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onSelect,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (splitActiveHeader) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: titleWidget),
                        const SizedBox(width: 6),
                        syncButton,
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: activeBadge,
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: titleWidget),
                        if (activeBadge != null) ...[
                          const SizedBox(width: 6),
                          activeBadge,
                        ],
                        if (syncButton != null) ...[
                          const SizedBox(width: 6),
                          syncButton,
                        ],
                      ],
                    ),
                  if (metadata != null) ...[
                    const SizedBox(height: 8),
                    _ProfileSubscriptionSummary(
                      data: metadata,
                      now: now,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height: 1,
                        thickness: 0.6,
                        color: colors.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 4),
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

class _ProfileSyncButton extends StatefulWidget {
  const _ProfileSyncButton({
    super.key,
    required this.updating,
    required this.onPressed,
    this.selectedCard = false,
    this.maxWidth = 168,
  });

  final bool updating;
  final VoidCallback? onPressed;
  final bool selectedCard;
  final double maxWidth;

  @override
  State<_ProfileSyncButton> createState() => _ProfileSyncButtonState();
}

class _ProfileSyncButtonState extends State<_ProfileSyncButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final updating = widget.updating;
    final enabled = !updating && widget.onPressed != null;
    final label = updating
        ? appLocalizations.nodeOverviewUpdatingShort
        : appLocalizations.nodeOverviewUpdateSubscription;
    final tooltipMessage = updating
        ? appLocalizations.nodeOverviewUpdating
        : appLocalizations.nodeOverviewUpdateSubscription;
    final borderRadius = BorderRadius.circular(999);

    final Color backgroundColor;
    final Color borderColor;
    final Color foregroundColor;

    if (updating) {
      backgroundColor = colors.primary.withValues(alpha: isDark ? 0.14 : 0.09);
      borderColor = colors.primary.withValues(alpha: 0.36);
      foregroundColor = colors.primary;
    } else if (_hovered || _focused) {
      backgroundColor = colors.primary.withValues(alpha: isDark ? 0.20 : 0.12);
      borderColor = colors.primary.withValues(alpha: 0.68);
      foregroundColor = colors.primary;
    } else {
      backgroundColor = widget.selectedCard
          ? colors.surface.withValues(alpha: isDark ? 0.46 : 0.76)
          : colors.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.62 : 0.85,
            );
      borderColor = colors.outlineVariant.withValues(alpha: 0.78);
      foregroundColor = colors.onSurface.withValues(alpha: 0.90);
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltipMessage,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? null : () {},
          child: MouseRegion(
            cursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onEnter: (_) {
              if (!_hovered) setState(() => _hovered = true);
            },
            onExit: (_) {
              if (_hovered) setState(() => _hovered = false);
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: borderRadius,
                  border: Border.all(color: borderColor, width: 0.9),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: borderRadius,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    splashColor: colors.primary.withValues(alpha: 0.12),
                    highlightColor: colors.primary.withValues(alpha: 0.08),
                    onFocusChange: (value) {
                      if (mounted && _focused != value) {
                        setState(() => _focused = value);
                      }
                    },
                    onTap: enabled ? widget.onPressed : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (updating)
                            SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  foregroundColor,
                                ),
                              ),
                            )
                          else
                            Icon(
                              Icons.sync_rounded,
                              size: 12.5,
                              color: foregroundColor,
                            ),
                          const SizedBox(width: 3.5),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                height: 1.2,
                                color: foregroundColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _ProfileMetadataViewData = ({
  String? serviceName,
  String? updatePolicyText,
  IconData? updatePolicyIcon,
  SubscriptionInfo? subscriptionInfo,
  DateTime? lastUpdateDate,
  bool deviceLimitReached,
  String? announce,
});

bool _hasMeaningfulSubscriptionInfo(SubscriptionInfo? sub) =>
    sub != null &&
    (sub.total > 0 || sub.expire > 0 || sub.upload > 0 || sub.download > 0);

DateTime? _parseSubscriptionExpireLocal(int rawExpire) {
  if (rawExpire <= 0) return null;
  final ms = rawExpire >= 100000000000 ? rawExpire : rawExpire * 1000;
  // Sentinels beyond 9999-12-31T23:59:59Z (or int64 max) represent perpetual plans.
  if (ms <= 0 || ms > 253402300799000) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
}

bool _containsUnsafeHeaderChars(String text) => text.runes.any(
      (r) =>
          (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) ||
          r == 0x7F ||
          (r >= 0x80 && r <= 0x9F) ||
          r == 0xFFFD ||
          (r >= 0xD800 && r <= 0xDFFF) ||
          (r >= 0xE000 && r <= 0xF8FF) ||
          r >= 0xF0000 ||
          (r >= 0x202A && r <= 0x202E) ||
          (r >= 0x2066 && r <= 0x2069),
    );

String _truncateHeaderRunes(String text, int maxChars) {
  if (text.runes.length <= maxChars) return text;
  return '${String.fromCharCodes(text.runes.take(maxChars))}…';
}

String? _sanitizeHeaderPlainText(String text, int maxChars) {
  final buffer = StringBuffer();
  for (final r in text.runes) {
    if ((r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) ||
        r == 0x7F ||
        (r >= 0x80 && r <= 0x9F) ||
        r == 0xFFFD ||
        (r >= 0xD800 && r <= 0xDFFF) ||
        (r >= 0x202A && r <= 0x202E) ||
        (r >= 0x2066 && r <= 0x2069)) {
      continue;
    }
    buffer.writeCharCode(r);
  }
  final cleaned = buffer.toString().trim();
  if (cleaned.isEmpty) return null;
  return _truncateHeaderRunes(cleaned, maxChars);
}

String? _decodeSafeHeaderText(String? raw, {int maxChars = 120}) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  var candidate = trimmed;
  final explicitBase64 = candidate.length >= 7 &&
      candidate.substring(0, 7).toLowerCase() == 'base64:';
  if (explicitBase64) {
    candidate = candidate.substring(7).trim();
    if (candidate.isEmpty) return null;
  }
  final looksLikeBase64Token = !explicitBase64 &&
      candidate.length >= 4 &&
      candidate.length % 4 != 1 &&
      RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(candidate) &&
      // Unpadded pure-letter identifiers (e.g. 'FreedomCloudPlus') cannot encode
      // UTF-8 CJK/Emoji (which always start with Base64 digits '4'..'9') and
      // must never be corrupted into ASCII mojibake.
      (candidate.endsWith('=') || !RegExp(r'^[A-Za-z_-]+$').hasMatch(candidate));
  if (explicitBase64 || looksLikeBase64Token) {
    try {
      final normalized =
          base64.normalize(candidate.replaceAll('-', '+').replaceAll('_', '/'));
      final decoded =
          utf8.decode(base64.decode(normalized), allowMalformed: false).trim();
      if (decoded.isNotEmpty && !_containsUnsafeHeaderChars(decoded)) {
        if (explicitBase64) {
          return _truncateHeaderRunes(decoded, maxChars);
        }
        final hasNonAsciiUnicode = decoded.runes.any((r) => r > 0x9F);
        final isPaddedAscii = candidate.endsWith('=') &&
            RegExp(r'^[\x20-\x7E\r\n\t]+$').hasMatch(decoded);
        final isUnpaddedAsciiProse = !candidate.endsWith('=') &&
            candidate.length >= 12 &&
            !candidate.contains('-') &&
            !candidate.contains('_') &&
            decoded.contains(' ') &&
            RegExp(r'^[A-Za-z0-9 .,!?:;()\[\]\-/\r\n\t]+$').hasMatch(decoded);
        if (hasNonAsciiUnicode || isPaddedAscii || isUnpaddedAsciiProse) {
          return _truncateHeaderRunes(decoded, maxChars);
        }
      } else if (explicitBase64) {
        return null;
      }
    } catch (_) {
      if (explicitBase64) return null;
    }
  }
  return _sanitizeHeaderPlainText(trimmed, maxChars);
}

_ProfileMetadataViewData? _resolveProfileMetadata(Profile profile) {
  final headers = profile.providerHeaders;
  final rawServiceName =
      _decodeSafeHeaderText(headers['flclashx-servicename'], maxChars: 80);
  final profileTitle = (profile.label ?? profile.id).trim();
  final serviceName = rawServiceName != null && rawServiceName != profileTitle
      ? rawServiceName
      : null;

  final rawAnnounce =
      _decodeSafeHeaderText(headers['announce'], maxChars: 400);
  final normalizedAnnounce =
      rawAnnounce?.replaceAll(RegExp(r'\s+'), ' ').trim();
  final announce = normalizedAnnounce != null && normalizedAnnounce.isNotEmpty
      ? normalizedAnnounce
      : null;

  final deviceLimitReached =
      headers['x-hwid-max-devices-reached']?.trim().toLowerCase() == 'true';

  String? updatePolicyText;
  IconData? updatePolicyIcon;
  if (profile.url.isNotEmpty) {
    final minutes = profile.autoUpdateDuration.inMinutes;
    if (profile.realAutoUpdate && minutes > 0) {
      updatePolicyIcon = Icons.autorenew_rounded;
      if (minutes % 60 == 0 && profile.autoUpdateDuration.inHours >= 1) {
        updatePolicyText = appLocalizations
            .nodeOverviewAutoUpdateHours(profile.autoUpdateDuration.inHours);
      } else {
        updatePolicyText =
            appLocalizations.nodeOverviewAutoUpdateMinutes(minutes);
      }
    } else {
      updatePolicyIcon = Icons.sync_disabled_rounded;
      updatePolicyText = appLocalizations.nodeOverviewManualUpdate;
    }
  } else if (profile.lastUpdateDate != null) {
    updatePolicyIcon = Icons.description_outlined;
    updatePolicyText = appLocalizations.nodeOverviewLocalProfile;
  }

  final sub = _hasMeaningfulSubscriptionInfo(profile.subscriptionInfo)
      ? profile.subscriptionInfo
      : null;

  if (serviceName == null &&
      updatePolicyText == null &&
      sub == null &&
      profile.lastUpdateDate == null &&
      !deviceLimitReached &&
      announce == null) {
    return null;
  }

  return (
    serviceName: serviceName,
    updatePolicyText: updatePolicyText,
    updatePolicyIcon: updatePolicyIcon,
    subscriptionInfo: sub,
    lastUpdateDate: profile.lastUpdateDate,
    deviceLimitReached: deviceLimitReached,
    announce: announce,
  );
}

String _formatOverviewTraffic(int bytes) {
  final value = TrafficValue(value: math.max(0, bytes));
  return '${value.showValue} ${value.showUnit}';
}

class _ProfileSubscriptionSummary extends StatelessWidget {
  const _ProfileSubscriptionSummary({
    required this.data,
    required this.now,
    this.trailingAction,
  });

  final _ProfileMetadataViewData data;
  final DateTime now;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sub = data.subscriptionInfo;
    final serviceName = data.serviceName;
    final updatePolicyText = data.updatePolicyText;
    final announce = data.announce;
    final deviceLimitReached = data.deviceLimitReached;

    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      height: 1.35,
      color: colors.onSurfaceVariant,
    );

    final children = <Widget>[];

    if (serviceName != null ||
        updatePolicyText != null ||
        trailingAction != null) {
      final tagsWrap = Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (serviceName != null)
            _SubscriptionTagPill(
              icon: Icons.cloud_outlined,
              label: serviceName,
              foreground: colors.primary,
              background: colors.primary.withValues(alpha: 0.12),
              border: colors.primary.withValues(alpha: 0.30),
            ),
          if (updatePolicyText != null)
            _SubscriptionTagPill(
              icon: data.updatePolicyIcon ?? Icons.description_outlined,
              label: updatePolicyText,
              foreground: colors.onSurfaceVariant,
              background: colors.surfaceContainerHighest.withValues(
                alpha: 0.65,
              ),
              border: colors.outlineVariant.withValues(alpha: 0.55),
            ),
        ],
      );
      children.add(
        trailingAction == null
            ? tagsWrap
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: tagsWrap),
                  const SizedBox(width: 8),
                  trailingAction!,
                ],
              ),
      );
    }

    if (sub != null) {
      final upload = math.max(0, sub.upload);
      final download = math.max(0, sub.download);
      final used = upload + download;
      final total = math.max(0, sub.total);

      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 6));
      }

      if (total > 0) {
        final remaining = math.max(0, total - used);
        final usedRatio = (used / total).clamp(0.0, 1.0);
        final rawPercent = ((1.0 - usedRatio) * 100).round();
        final remainingPercent = remaining <= 0
            ? 0
            : remaining >= total
                ? 100
                : rawPercent.clamp(1, 99);
        final barColor = usedRatio > 0.90
            ? colors.error
            : usedRatio > 0.70
                ? Colors.orange
                : Colors.green;

        children.addAll([
          Row(
            children: [
              Icon(
                Icons.data_usage_rounded,
                size: 13.5,
                color: barColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  appLocalizations.nodeOverviewRemainingTraffic(
                    _formatOverviewTraffic(remaining),
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: usedRatio > 0.90 ? colors.error : colors.onSurface,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$remainingPercent%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: usedRatio,
              minHeight: 5,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            appLocalizations.nodeOverviewUsedOfTotalTraffic(
              _formatOverviewTraffic(used),
              _formatOverviewTraffic(total),
            ),
            style: metaStyle,
          ),
          if (upload > 0 || download > 0)
            Text(
              '↑ ${_formatOverviewTraffic(upload)} · ↓ ${_formatOverviewTraffic(download)}',
              style: metaStyle?.copyWith(
                fontSize: 11,
                color: colors.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
        ]);
      } else {
        children.add(
          Row(
            children: [
              Icon(
                Icons.all_inclusive_rounded,
                size: 13.5,
                color: colors.primary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  appLocalizations.nodeOverviewTrafficUnlimited,
                  style: metaStyle?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.90),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
        if (used > 0) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${appLocalizations.nodeOverviewUsedTrafficOnly(_formatOverviewTraffic(used))} · ↑ ${_formatOverviewTraffic(upload)} · ↓ ${_formatOverviewTraffic(download)}',
                style: metaStyle,
              ),
            ),
          );
        }
      }

      children.add(const SizedBox(height: 4));
      final expireDate = _parseSubscriptionExpireLocal(sub.expire);
      if (expireDate == null) {
        children.add(
          Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 13.5,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  appLocalizations.nodeOverviewNeverExpires,
                  style: metaStyle,
                ),
              ),
            ],
          ),
        );
      } else {
        final dateStr = DateFormat('yyyy-MM-dd').format(expireDate);
        final diff = expireDate.difference(now);
        final isExpired = !expireDate.isAfter(now);
        final isExpiringSoon = !isExpired && diff.inDays <= 7;
        final String expireText;
        if (isExpired) {
          expireText =
              '${appLocalizations.nodeOverviewExpireAt(dateStr)} · ${appLocalizations.nodeOverviewStatusExpired}';
        } else if (diff.inDays >= 1) {
          expireText =
              '${appLocalizations.nodeOverviewExpireAt(dateStr)} · ${appLocalizations.nodeOverviewExpireDaysLeft(diff.inDays)}';
        } else if (diff.inHours >= 1) {
          expireText =
              '${appLocalizations.nodeOverviewExpireAt(dateStr)} · ${appLocalizations.nodeOverviewExpireHoursLeft(diff.inHours)}';
        } else {
          expireText =
              '${appLocalizations.nodeOverviewExpireAt(dateStr)} · ${appLocalizations.nodeOverviewExpireSoon}';
        }
        final expireColor = isExpired
            ? colors.error
            : isExpiringSoon
                ? Colors.orange
                : colors.onSurfaceVariant;
        children.add(
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 13.5,
                color: expireColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  expireText,
                  style: metaStyle?.copyWith(
                    color: expireColor,
                    fontWeight: isExpired || isExpiringSoon
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    if (data.lastUpdateDate != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 3));
      }
      final syncStr = DateFormat('yyyy-MM-dd HH:mm')
          .format(data.lastUpdateDate!.toLocal());
      children.add(
        Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 13,
              color: colors.onSurfaceVariant.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                appLocalizations.nodeOverviewLastSync(syncStr),
                style: metaStyle,
              ),
            ),
          ],
        ),
      );
    }

    if (deviceLimitReached) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 4));
      }
      children.add(
        Row(
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: 13.5,
              color: colors.error,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                appLocalizations.nodeOverviewDeviceLimitReached,
                style: metaStyle?.copyWith(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (announce != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 4));
      }
      children.add(
        Tooltip(
          message: announce,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Icon(
                    Icons.campaign_outlined,
                    size: 13.5,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    appLocalizations.nodeOverviewAnnouncement(announce),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _SubscriptionTagPill extends StatelessWidget {
  const _SubscriptionTagPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11.5, color: foreground),
            const SizedBox(width: 3.5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      height: 1.2,
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
      );
}

class _ProfileNodesSliver extends ConsumerStatefulWidget {
  const _ProfileNodesSliver(
      {super.key,
      required this.profile,
      required this.active,
      required this.liveActive,
      required this.showHeader,
      required this.showSubscriptionSummary,
      this.onSyncSubscription,
      this.syncButtonKey,
      required this.loadImmediately,
      required this.availableOnly,
      required this.countryFilter,
      required this.onVisibilityChanged,
      required this.onTest,
      required this.onTestActive,
      required this.onUseActive,
      required this.onUseCatalog,
      required this.now});
  final Profile profile;
  final bool active;
  final bool liveActive;
  final bool showHeader;
  final bool showSubscriptionSummary;
  final VoidCallback? onSyncSubscription;
  final Key? syncButtonKey;
  final bool loadImmediately;
  final bool availableOnly;
  final String? countryFilter;
  final ValueChanged<bool> onVisibilityChanged;
  final void Function(Profile, CatalogNode) onTest;
  final void Function(Proxy, String? testUrl) onTestActive;
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
          final matches = _activeEntryMatchesQuery(entry, effectiveQuery);
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
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final headerExtent =
        math.max(44.0, (28.0 + 16.0 * textScale).ceilToDouble());
    final metadata =
        widget.showSubscriptionSummary ? _resolveProfileMetadata(profile) : null;
    return _PaintVisibilitySliver(
      onVisibilityChanged: _visibilityChanged,
      child: SliverMainAxisGroup(slivers: [
        if (widget.showHeader)
          SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedProfileHeader(
                  profile: profile,
                  active: widget.active,
                  extent: headerExtent)),
        if (metadata != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ProfileSubscriptionSummary(
                    data: metadata,
                    now: widget.now,
                    trailingAction: widget.onSyncSubscription == null
                        ? null
                        : _ProfileSyncButton(
                            key: widget.syncButtonKey ??
                                ValueKey('overview-sync-${profile.id}'),
                            updating: profile.isUpdating,
                            onPressed: widget.onSyncSubscription,
                          ),
                  ),
                ),
              ),
            ),
          ),
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
              onTest: widget.onTestActive,
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
  _PinnedProfileHeader({
    required this.profile,
    required this.active,
    this.extent = 44,
  });
  final Profile profile;
  final bool active;
  final double extent;
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
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
              if (active) ...[
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: Text(
                    appLocalizations.nodeOverviewActive,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ]),
          )));
  @override
  bool shouldRebuild(covariant _PinnedProfileHeader oldDelegate) =>
      profile != oldDelegate.profile ||
      active != oldDelegate.active ||
      extent != oldDelegate.extent;
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
  final expireDate =
      _parseSubscriptionExpireLocal(profile.subscriptionInfo?.expire ?? 0);
  return expireDate != null && !expireDate.isAfter(now);
}

bool _matches(CatalogNode node, String query) =>
    '${node.name}\n${node.type}\n${node.protocolSummary ?? ''}\n${node.providerName ?? ''}'
        .toLowerCase()
        .contains(query);

bool _activeEntryMatchesQuery(_ActiveDisplay entry, String query) {
  final rawType = entry.fileSource ? entry.node!.type : entry.proxy.type;
  return '${entry.proxy.name}\n$rawType\n${canonicalProtocolLabel(rawType)}\n${entry.node?.protocolSummary ?? ''}\n${entry.node?.providerName ?? ''}'
      .toLowerCase()
      .contains(query);
}

int _compareDelay(int? a, int? b) => utils.compareDelay(a, b);

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

Widget _buildTestButton(
  BuildContext context, {
  required Key buttonKey,
  required VoidCallback? onPressed,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextButton(
    key: buttonKey,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: colorScheme.surfaceContainerLow,
      foregroundColor: colorScheme.primary,
    ),
    child: Text(appLocalizations.nodeOverviewTestNode),
  );
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

Widget _buildNodeHeaderLayout(
  BuildContext context, {
  required String name,
  required Widget status,
  required List<Widget> actions,
}) =>
    LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final singleRow =
            actions.isEmpty || constraints.maxWidth >= 460 * textScale;
        if (singleRow) {
          return Row(
            children: [
              Expanded(child: Text(name)),
              const SizedBox(width: 8),
              status,
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name)),
                const SizedBox(width: 8),
                Flexible(child: status),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ),
          ],
        );
      },
    );

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
  String? testUrl,
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
  final explicitLiveResults = ref.watch(_overviewExplicitLiveResultsProvider);
  final groupHistory = <String?, Map<String, NodeHealthRecord>>{};
  return {
    for (final entry in _activeLeaves(ref).values)
      entry.proxy.name: () {
        var node = runtimeNodes[entry.proxy.name];
        NodeHealthRecord? history;
        var fileSource = false;
        var independent = false;
        final cardState = ref.watch(getProxyCardStateProvider(entry.proxy.name));
        final effectiveUrl = cardState.testUrl.getSafeValue(
          ref.watch(getRealTestUrlProvider(entry.testUrl)),
        );
        final explicitLive = cardState.proxyName.isEmpty
            ? null
            : explicitLiveResults[(profileId, cardState.proxyName, effectiveUrl)];
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
            } else if (explicitLive != null) {
              node = candidate;
            }
          }
        }
        final live = ref.watch(getDelayProvider(
            proxyName: entry.proxy.name, testUrl: entry.testUrl));
        if (explicitLive != null &&
            (history == null ||
                history.testedAt.isBefore(explicitLive.testedAt))) {
          history = NodeHealthRecord(
            delayMs: explicitLive.delayMs,
            testedAt: explicitLive.testedAt,
            testUrlHash: '',
          );
          fileSource = false;
          independent = false;
        }
        final selectGroup = entry.selectGroup;
        final selectedProxyName = selectGroup == null
            ? null
            : ref.watch(getSelectedProxyNameProvider(selectGroup));
        return (
          proxy: entry.proxy,
          testUrl: entry.testUrl,
          node: node,
          history: history,
          delay: _activeDelay(live, history),
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
      required this.onTest,
      required this.onUse,
      required this.now,
      required this.sort});
  final Profile profile;
  final ProfileCatalog? fileCatalog;
  final String query;
  final bool availableOnly;
  final String? countryFilter;
  final void Function(Proxy proxy, String? testUrl) onTest;
  final void Function(Profile, String groupName, String proxyName) onUse;
  final DateTime now;
  final ProxiesSortType sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tester = ref.watch(nodeCatalogTesterProvider);
    final countryResolver = ref.watch(nodeCountryResolverProvider);
    final locale = Localizations.localeOf(context);
    final rows =
        _activeDisplays(ref, profile.id, fileCatalog).values.where((entry) {
      final matches = _activeEntryMatchesQuery(entry, query);
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
                  testKey: ValueKey(
                      'overview-test-${profile.id}-${entry.proxy.name}'),
                  onTest: tester.busy || entry.delay == 0 || profile.isUpdating
                      ? null
                      : () => onTest(entry.proxy, entry.testUrl),
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
      required this.testKey,
      required this.onTest,
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
  final Key testKey;
  final VoidCallback? onTest;
  final Key useKey;
  final bool inUse;
  final VoidCallback? onUse;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = utils.getDelayColor(delay);
    final providerSource = node == null ? null : _providerSourceLabel(node!);
    final source = node == null
        ? appLocalizations.nodeOverviewRuntimeSource
        : fileSource
            ? (providerSource == null
                ? null
                : appLocalizations.nodeOverviewFileSource(providerSource))
            : providerSource;
    final protocol = fileSource
        ? _catalogProtocolLabel(node!)
        : (node?.protocolSummary != null && node!.protocolSummary!.isNotEmpty)
            ? node!.protocolSummary!
            : canonicalProtocolLabel(proxy.type);
    final description = [
      protocol,
      if (source != null) source,
      if (independent) appLocalizations.nodeOverviewIndependentTest,
    ].join(' · ');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildNodeHeaderLayout(
                context,
                name: proxy.name,
                status: delay == 0
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        delay == null
                            ? appLocalizations.nodeOverviewUntested
                            : delay! > 0
                                ? '$delay ms'
                                : appLocalizations.nodeOverviewTestFailed,
                        style: TextStyle(color: color)),
                actions: [
                  _buildTestButton(
                    context,
                    buttonKey: testKey,
                    onPressed: onTest,
                  ),
                  _buildUseButton(
                    context,
                    buttonKey: useKey,
                    inUse: inUse,
                    onPressed: onUse,
                  ),
                ],
              ),
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

String? _providerSourceLabel(CatalogNode node) =>
    node.source == CatalogNodeSource.inline
        ? null
        : node.providerName ?? appLocalizations.providers;

String _catalogProtocolLabel(CatalogNode node) {
  final summary = node.protocolSummary;
  return summary != null && summary.isNotEmpty ? summary : node.type;
}

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
                _buildNodeHeaderLayout(
                  context,
                  name: node.name,
                  status: invalid
                      ? Icon(Icons.help_outline,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)
                      : pending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              record == null
                                  ? appLocalizations.nodeOverviewUntested
                                  : record.delayMs > 0
                                      ? '${record.delayMs} ms'
                                      : appLocalizations.nodeOverviewTestFailed,
                              style: TextStyle(color: color)),
                  actions: [
                    if (node.unsupported == CatalogUnsupportedReason.none)
                      _buildTestButton(
                        context,
                        buttonKey: testKey,
                        onPressed: onTest,
                      ),
                    if (!invalid)
                      _buildUseButton(
                        context,
                        buttonKey: useKey,
                        inUse: inUse,
                        onPressed: onUse,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (countryEmoji != null && countryName != null) ...[
                      _CountryBadge(emoji: countryEmoji!, name: countryName!),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        [
                          _catalogProtocolLabel(node),
                          if (_providerSourceLabel(node) case final src?) src,
                        ].join(' · '),
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
