import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/profiles/add_profile.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

part 'profile_selector.dart';

/// Shared state/action bridge between ProxiesView's AppBar accessory slot
/// and the active NodeOverviewView instance.
class NodeOverviewCommandController extends ChangeNotifier {
  String? selectedProfile;
  String? selectedCountry;
  bool _availableOnly = false;
  bool get availableOnly => _availableOnly;
  bool _importingSubscription = false;
  bool get importingSubscription => _importingSubscription;
  bool _localProxyTogglePending = false;
  bool get localProxyTogglePending => _localProxyTogglePending;
  final Set<String> visibleProfileIds = <String>{};
  final Map<String, _IndexedProfileCountrySummary> _indexedProfiles =
      <String, _IndexedProfileCountrySummary>{};
  List<String> stableProfileOrderIds = const <String>[];
  final Set<String> updatingOrderFreezeIds = <String>{};
  Widget? inlineAccessoryWidget;

  Object? _owner;
  VoidCallback? _onOpenAddSubscription;
  void Function(Profile profile, {String? targetGroupOverride})?
      _onActivateSmartSelection;
  void Function(Profile profile)? _onActivateManualSelection;
  void Function(Profile profile, String groupName, String proxyName)?
      _onUseActiveNode;
  void Function(Profile profile, CatalogNode node, String groupName)?
      _onUseCatalogNode;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  void notifySafely() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  void bindView({
    required Object owner,
    required VoidCallback onOpenAddSubscription,
    required void Function(Profile profile, {String? targetGroupOverride})
        onActivateSmartSelection,
    required void Function(Profile profile) onActivateManualSelection,
    required void Function(Profile profile, String groupName, String proxyName)
        onUseActiveNode,
    required void Function(Profile profile, CatalogNode node, String groupName)
        onUseCatalogNode,
    String? selectedProfile,
    String? selectedCountry,
    bool availableOnly = false,
    bool importingSubscription = false,
    bool localProxyTogglePending = false,
  }) {
    _owner = owner;
    _onOpenAddSubscription = onOpenAddSubscription;
    _onActivateSmartSelection = onActivateSmartSelection;
    _onActivateManualSelection = onActivateManualSelection;
    _onUseActiveNode = onUseActiveNode;
    _onUseCatalogNode = onUseCatalogNode;
    this.selectedProfile = selectedProfile;
    this.selectedCountry = selectedCountry;
    _availableOnly = availableOnly;
    _importingSubscription = importingSubscription;
    _localProxyTogglePending = localProxyTogglePending;
    notifySafely();
  }

  void unbindView(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _onOpenAddSubscription = null;
    _onActivateSmartSelection = null;
    _onActivateManualSelection = null;
    _onUseActiveNode = null;
    _onUseCatalogNode = null;
    visibleProfileIds.clear();
    _indexedProfiles.clear();
    stableProfileOrderIds = const <String>[];
    updatingOrderFreezeIds.clear();
    selectedProfile = null;
    selectedCountry = null;
    _availableOnly = false;
    _importingSubscription = false;
    _localProxyTogglePending = false;
  }

  void openAddSubscription() => _onOpenAddSubscription?.call();

  void activateSmartSelection(
    Profile profile, {
    String? targetGroupOverride,
  }) =>
      _onActivateSmartSelection?.call(
        profile,
        targetGroupOverride: targetGroupOverride,
      );

  void activateManualSelection(Profile profile) =>
      _onActivateManualSelection?.call(profile);

  void useActiveNode(Profile profile, String groupName, String proxyName) =>
      _onUseActiveNode?.call(profile, groupName, proxyName);

  void useCatalogNode(Profile profile, CatalogNode node, String groupName) =>
      _onUseCatalogNode?.call(profile, node, groupName);

  set importingSubscription(bool value) {
    if (_importingSubscription == value) return;
    _importingSubscription = value;
    notifySafely();
  }

  set localProxyTogglePending(bool value) {
    if (_localProxyTogglePending == value) return;
    _localProxyTogglePending = value;
    notifySafely();
  }

  void setSelectedProfile(String? value) {
    if (selectedProfile == value) return;
    selectedProfile = value;
    notifySafely();
  }

  void setSelectedCountry(String? value) {
    if (selectedCountry == value) return;
    selectedCountry = value;
    notifySafely();
  }

  set availableOnly(bool value) {
    if (_availableOnly == value) return;
    _availableOnly = value;
    notifySafely();
  }

  void recordVisibleProfile(String profileId) {
    if (visibleProfileIds.add(profileId)) {
      notifySafely();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _onOpenAddSubscription = null;
    _onActivateSmartSelection = null;
    _onActivateManualSelection = null;
    _onUseActiveNode = null;
    _onUseCatalogNode = null;
    super.dispose();
  }
}

/// Selects only the page body; the scope control belongs to the existing app bar.
class NodeOverviewScopeView extends ConsumerWidget {
  const NodeOverviewScopeView({
    super.key,
    required this.currentView,
    this.commandController,
  });

  final Widget currentView;
  final NodeOverviewCommandController? commandController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled) return currentView;
    ref.watch(_overviewSwitchTrackerProvider);
    final expertExpanded = ref.watch(expertNavigationExpandedProvider);
    final lockedToOverviewInNovice = !expertExpanded &&
        (context.commonScaffoldState?.hasNavigationBar ?? false);
    if (count == 0 || lockedToOverviewInNovice) {
      return NodeOverviewView(commandController: commandController);
    }
    final scope = ref.watch(proxiesScopeProvider);
    return scope == ProxiesScope.all
        ? NodeOverviewView(commandController: commandController)
        : currentView;
  }
}

class NodeOverviewScopeAction extends ConsumerWidget {
  const NodeOverviewScopeAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Localizations.maybeLocaleOf(context);
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled || count == 0) return const SizedBox.shrink();
    final scope = ref.watch(proxiesScopeProvider);
    final labels = {
      ProxiesScope.current: appLocalizations.nodeOverviewCurrentProfile,
      ProxiesScope.all: appLocalizations.nodeOverviewAllProfiles,
    };
    void select(ProxiesScope value) =>
        ref.read(proxiesScopeProvider.notifier).state = value;
    final viewWidth = ref.watch(viewWidthProvider);
    final mediaWidth = MediaQuery.maybeSizeOf(context)?.width;
    final effectiveWidth = (mediaWidth != null && mediaWidth > 0)
        ? math.min(viewWidth, mediaWidth)
        : viewWidth;
    // Keep narrow desktop (<1200px) in compact menu mode so the Plan A inline
    // command bar keeps comfortable width across all locales and text scales
    // without morphing when toggling between all and current profile scopes.
    final useCompactScopeMenu = effectiveWidth < 1200;
    if (useCompactScopeMenu) {
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
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
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
  const NodeOverviewView({
    super.key,
    this.commandController,
  });

  final NodeOverviewCommandController? commandController;

  @override
  ConsumerState<NodeOverviewView> createState() => _NodeOverviewViewState();
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

class _OverviewComputedSnapshot {
  const _OverviewComputedSnapshot({
    required this.profiles,
    required this.testerBusy,
    required this.tester,
    required this.activeId,
    required this.tracker,
    required this.liveActiveProfileIds,
    required this.isMobile,
    required this.sort,
    required this.selected,
    required this.cachedCatalogs,
    required this.currentScript,
    required this.query,
    required this.searching,
    required this.locale,
    required this.countryCounts,
    required this.availableCounts,
    required this.activeDisplayCounts,
    required this.healthByProfile,
    required this.loadErrorIds,
    required this.resolvedCatalogs,
    required this.anyVisibleCatalogLoading,
    required this.orderedProfiles,
    required this.visible,
    required this.activeCountry,
    required this.sortedCountries,
    required this.activeCountryMatchCount,
    required this.targetTestProfile,
    required this.canTestCurrent,
    required this.quickUseAction,
    required this.isProxyRunning,
    required this.effectivePendingTarget,
    required this.statusStartCancelable,
    required this.activeProfileObj,
    required this.activeIsSmart,
    required this.targetModeProfile,
    required this.currentSelectionMode,
    required this.canSwitchSelectionMode,
    required this.activeNodeLabel,
    required this.availableFilterHidAllNodes,
  });

  final List<Profile> profiles;
  final bool testerBusy;
  final NodeCatalogTester tester;
  final String? activeId;
  final _OverviewSwitchTracker tracker;
  final Set<String> liveActiveProfileIds;
  final bool isMobile;
  final ProxiesSortType sort;
  final String? selected;
  final Map<String, ProfileCatalog> cachedCatalogs;
  final Script? currentScript;
  final String query;
  final bool searching;
  final Locale locale;
  final Map<String, int> countryCounts;
  final Map<String, int> availableCounts;
  final Map<String, int> activeDisplayCounts;
  final Map<String, Map<String, NodeHealthRecord>> healthByProfile;
  final Set<String> loadErrorIds;
  final Map<String, ProfileCatalog?> resolvedCatalogs;
  final bool anyVisibleCatalogLoading;
  final List<Profile> orderedProfiles;
  final List<Profile> visible;
  final String? activeCountry;
  final List<String> sortedCountries;
  final int activeCountryMatchCount;
  final Profile? targetTestProfile;
  final bool canTestCurrent;
  final VoidCallback? quickUseAction;
  final bool isProxyRunning;
  final bool? effectivePendingTarget;
  final bool statusStartCancelable;
  final Profile? activeProfileObj;
  final bool activeIsSmart;
  final Profile? targetModeProfile;
  final NodeSelectionMode currentSelectionMode;
  final bool canSwitchSelectionMode;
  final String? activeNodeLabel;
  final bool availableFilterHidAllNodes;
}

_OverviewComputedSnapshot _computeOverviewSnapshot({
  required WidgetRef ref,
  required Locale locale,
  required String? rawSelectedProfile,
  required String? rawSelectedCountry,
  required bool availableOnly,
  required bool localProxyTogglePending,
  required Set<String> visibleProfileIds,
  required Map<String, _IndexedProfileCountrySummary> indexedProfiles,
  required List<String> stableProfileOrderIds,
  required Set<String> updatingOrderFreezeIds,
  required bool mutateCaches,
  void Function(List<String> nextOrder)? onUpdateStableOrder,
  required void Function(Profile profile, {String? targetGroupOverride})
      onActivateSmartSelection,
  required void Function(Profile profile) onActivateManualSelection,
  required void Function(Profile profile, String groupName, String proxyName)
      onUseActiveNode,
  required void Function(Profile profile, CatalogNode node, String groupName)
      onUseCatalogNode,
}) {
  final profiles = ref.watch(profilesProvider);
  final testerBusy =
      ref.watch(nodeCatalogTesterProvider.select((t) => t.busy));
  final tester = ref.read(nodeCatalogTesterProvider);
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
        tracker.feedback ??= appLocalizations.nodeOverviewSwitchedToNode(
            tracker.pendingProfileLabel!, tracker.pendingNodeName!);
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

  final isMobile = ref.watch(isMobileViewProvider);
  final sort = ref.watch(proxiesStyleSettingProvider.select((s) => s.sortType));
  final selected = profiles.any((p) => p.id == rawSelectedProfile)
      ? rawSelectedProfile
      : null;
  final countryResolver = ref.watch(nodeCountryResolverProvider);
  final cachedCatalogs = ref.watch(cachedProfileCatalogsProvider);
  final currentScript =
      ref.watch(scriptStateProvider.select((state) => state.currentScript));
  final query = ref.watch(proxiesQueryProvider).trim().toLowerCase();
  final searching = query.isNotEmpty;
  final mode =
      ref.watch(patchClashConfigProvider.select((state) => state.mode));
  final currentGroups = ref.watch(currentGroupsStateProvider).value;
  final scopeCountries = <String>{};
  final countryCounts = <String, int>{};
  final availableCounts = <String, int>{};
  final activeDisplayCounts = <String, int>{};
  final healthByProfile = <String, Map<String, NodeHealthRecord>>{};
  final loadErrorIds = <String>{};
  final originalIndexes = <String, int>{};
  final resolvedCatalogs = <String, ProfileCatalog?>{};
  final liveActiveProfileIds = <String>{};
  var anyVisibleCatalogLoading = false;

  for (var i = 0; i < profiles.length; i++) {
    final profile = profiles[i];
    originalIndexes[profile.id] = i;
    final liveActive = isLiveActive(profile);
    if (liveActive) {
      liveActiveProfileIds.add(profile.id);
    }
    final inSelectedScope = selected == null || selected == profile.id;
    final shouldWatchCatalog = selected == profile.id ||
        visibleProfileIds.contains(profile.id) ||
        (inSelectedScope && (searching || rawSelectedCountry != null));
    final loaded = shouldWatchCatalog
        ? ref.watch(profileCatalogProvider(profile.id))
        : null;
    if (loaded?.hasError ?? false) {
      loadErrorIds.add(profile.id);
    }
    final catalog = loaded?.valueOrNull ?? cachedCatalogs[profile.id];
    resolvedCatalogs[profile.id] = catalog;
    if (mutateCaches) {
      final catalogReloadingAfterSync =
          ((loaded?.isLoading ?? false) && catalog == null) ||
              catalog?.status == ProfileCatalogStatus.loading ||
              catalog?.status == ProfileCatalogStatus.updating;
      if (profile.isUpdating) {
        updatingOrderFreezeIds.add(profile.id);
      } else if (!catalogReloadingAfterSync) {
        updatingOrderFreezeIds.remove(profile.id);
      }
      if (catalog != null && catalog.status != ProfileCatalogStatus.loading) {
        indexedProfiles[profile.id] = _IndexedProfileCountrySummary(
          url: profile.url,
          lastUpdateDate: profile.lastUpdateDate,
          isUpdating: profile.isUpdating,
          scriptId: currentScript?.id,
          scriptContent: currentScript?.content,
          status: catalog.status,
          errorSummary: catalog.errorSummary,
          hasUnresolvedProviders:
              catalog.providerNodeCounts.values.any((count) => count < 0),
          nodes: catalog.nodes.map(_IndexedNodeSummary.fromNode).toList(),
        );
      }
    }
    final indexedSummary = indexedProfiles[profile.id];
    final validIndexed = indexedSummary != null &&
            indexedSummary.matchesProfile(profile, currentScript)
        ? indexedSummary
        : null;
    if (inSelectedScope) {
      final pendingIndex = !liveActive &&
          catalog == null &&
          validIndexed == null &&
          !profile.isUpdating;
      if (((loaded?.isLoading ?? false) && catalog == null) ||
          (mutateCaches && pendingIndex) ||
          profile.isUpdating ||
          catalog?.status == ProfileCatalogStatus.loading ||
          catalog?.status == ProfileCatalogStatus.updating) {
        anyVisibleCatalogLoading = true;
      }
    }
    final profileMatches =
        (profile.label ?? profile.id).toLowerCase().contains(query);
    final health = ref.watch(nodeHealthEntriesProvider(profile.id));
    healthByProfile[profile.id] = health;
    if (liveActive) {
      final displays = _activeDisplays(
          ref, profile.id, profile.isUpdating ? null : catalog);
      activeDisplayCounts[profile.id] = displays.length;
      if (displays.isNotEmpty || profile.isUpdating) {
        availableCounts[profile.id] =
            displays.values.where((entry) => (entry.delay ?? -1) > 0).length;
      } else {
        availableCounts[profile.id] = _resolveStaticPickerStats(
          loadedHasError: loaded?.hasError ?? false,
          catalog: catalog,
          validIndexed: validIndexed,
          health: health,
        ).availableCount;
      }
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
          if (!matches || (availableOnly && (entry.delay ?? -1) <= 0)) {
            continue;
          }
          countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    } else {
      if (catalog != null) {
        final unusableCatalog =
            catalog.status == ProfileCatalogStatus.loading ||
                catalog.status == ProfileCatalogStatus.fileMissing ||
                catalog.status == ProfileCatalogStatus.parseFailed;
        availableCounts[profile.id] = unusableCatalog
            ? 0
            : catalog.nodes
                .where((node) => (_nodeHealth(node, health)?.delayMs ?? -1) > 0)
                .length;
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
                (availableOnly &&
                    (_nodeHealth(node, health)?.delayMs ?? -1) <= 0)) {
              continue;
            }
            countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
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
            if (!matchesQuery || (availableOnly && (delayMs ?? -1) <= 0)) {
              continue;
            }
            countryCounts.update(code, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      } else {
        availableCounts[profile.id] = 0;
      }
    }
  }
  if (mutateCaches) {
    updatingOrderFreezeIds.retainAll(originalIndexes.keys);
  }
  final List<Profile> orderedProfiles;
  if (stableProfileOrderIds.isNotEmpty &&
      (testerBusy || updatingOrderFreezeIds.isNotEmpty)) {
    final byId = <String, Profile>{
      for (final profile in profiles) profile.id: profile,
    };
    orderedProfiles = <Profile>[
      for (final id in stableProfileOrderIds)
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
    if (mutateCaches) {
      onUpdateStableOrder?.call(<String>[
        for (final profile in orderedProfiles) profile.id,
      ]);
    }
  }
  final visible = selected == null
      ? orderedProfiles
      : orderedProfiles.where((p) => p.id == selected).toList();
  final activeCountry = rawSelectedCountry != null &&
          (scopeCountries.contains(rawSelectedCountry) ||
              anyVisibleCatalogLoading)
      ? rawSelectedCountry
      : null;
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
  final canTestCurrent = !testerBusy &&
      !(targetTestProfile?.isUpdating ?? false) &&
      !(selected != null && targetTestProfile == null) &&
      !(selected == null && (activeId == null || currentGroups.isEmpty));

  VoidCallback? resolveQuickUseAction() {
    for (final profile in visible) {
      if (profile.isUpdating) {
        return null;
      }
      final profileMatches =
          (profile.label ?? profile.id).toLowerCase().contains(query);
      final catalog = resolvedCatalogs[profile.id];
      if (liveActiveProfileIds.contains(profile.id)) {
        final effectiveQuery = profileMatches ? '' : query;
        final rows = _activeDisplays(
          ref,
          profile.id,
          profile.isUpdating ? null : catalog,
        ).values.where((entry) {
          final matches = _activeEntryMatchesQuery(entry, effectiveQuery);
          if (!matches || (availableOnly && (entry.delay ?? -1) <= 0)) {
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
        for (final allowInformational in const [false, true]) {
          for (final entry in rows) {
            if (!allowInformational &&
                isInformationalProxyName(entry.proxy.name)) {
              continue;
            }
            if (entry.selectGroup != null &&
                (entry.delay == null || entry.delay! >= 0)) {
              final targetGroup = entry.selectGroup!;
              if (resolveProfileSelectionMode(profile) ==
                      NodeSelectionMode.smart &&
                  query.isEmpty &&
                  activeCountry == null) {
                return () => onActivateSmartSelection(
                      profile,
                      targetGroupOverride: targetGroup,
                    );
              }
              final targetProxy = entry.proxy.name;
              return () => onUseActiveNode(profile, targetGroup, targetProxy);
            }
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
        if (availableOnly || activeCountry != null || query.isNotEmpty) {
          continue;
        }
        return null;
      }
      final health =
          healthByProfile[profile.id] ?? const <String, NodeHealthRecord>{};
      final nodes = catalog.nodes.where((node) {
        final matches = profileMatches || _matches(node, query);
        if (!matches ||
            (availableOnly && (_nodeHealth(node, health)?.delayMs ?? -1) <= 0)) {
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
      for (final allowInformational in const [false, true]) {
        for (final node in nodes) {
          if (!allowInformational && isInformationalProxyName(node.name)) {
            continue;
          }
          final delayMs = _nodeHealth(node, health)?.delayMs;
          if (delayMs != null && delayMs < 0) {
            continue;
          }
          final targetGroup = _targetGroupForCatalogNode(profile, node, mode);
          if (targetGroup != null) {
            if (resolveProfileSelectionMode(profile) ==
                    NodeSelectionMode.smart &&
                query.isEmpty &&
                activeCountry == null) {
              return () => onActivateSmartSelection(
                    profile,
                    targetGroupOverride: targetGroup,
                  );
            }
            return () => onUseCatalogNode(profile, node, targetGroup);
          }
        }
      }
      return null;
    }
    return null;
  }

  final quickUseAction = resolveQuickUseAction();
  final isProxyRunning = ref.watch(runTimeProvider.select((s) => s != null));
  final statusSwitchPending = ref.watch(statusSwitchPendingProvider);
  final statusStartCancelable = ref.watch(statusStartCancelableProvider);
  final effectivePendingTarget =
      statusSwitchPending ?? (localProxyTogglePending ? !isProxyRunning : null);
  final activeProfileObj =
      activeId == null ? null : profiles.getProfile(activeId);
  final activeIsSmart = activeProfileObj != null &&
      resolveProfileSelectionMode(activeProfileObj) == NodeSelectionMode.smart;
  final targetModeProfile = selected != null
      ? visible.firstOrNull
      : (activeProfileObj ?? orderedProfiles.firstOrNull);
  final currentSelectionMode = targetModeProfile == null
      ? NodeSelectionMode.smart
      : resolveProfileSelectionMode(targetModeProfile);
  final canSwitchSelectionMode =
      targetModeProfile != null && !targetModeProfile.isUpdating;
  String? activeNodeLabel;
  if (activeProfileObj != null) {
    final preferredGroup = activeProfileObj.currentGroupName;
    if (activeIsSmart) {
      if (groups.isNotEmpty && liveActiveProfileIds.contains(activeProfileObj.id)) {
        Group? targetGroup;
        if (preferredGroup != null) {
          targetGroup = currentGroups
              .where((g) => g.name == preferredGroup)
              .firstOrNull;
        }
        targetGroup ??= currentGroups
            .where((g) => g.type == GroupType.Selector)
            .firstOrNull;
        activeNodeLabel = resolveSmartActiveLeafName(
          selectorGroupName: targetGroup?.name ?? preferredGroup,
          allGroups: groups,
          selectedMap: activeProfileObj.selectedMap,
        );
      }
    } else {
      if (currentGroups.isNotEmpty &&
          liveActiveProfileIds.contains(activeProfileObj.id)) {
        Group? targetGroup;
        if (preferredGroup != null) {
          targetGroup = currentGroups
              .where((g) => g.name == preferredGroup)
              .firstOrNull;
        }
        targetGroup ??= currentGroups
            .where((g) => g.type == GroupType.Selector)
            .firstOrNull;
        if (targetGroup != null) {
          final candidate = (targetGroup.type == GroupType.Selector
                  ? activeProfileObj.selectedMap[targetGroup.name]
                  : null) ??
              targetGroup.now ??
              activeProfileObj.selectedMap[targetGroup.name];
          if (!isManagedSmartGroupName(candidate)) {
            activeNodeLabel = candidate;
          }
        }
      }
      final fallbackLabel = preferredGroup != null
          ? activeProfileObj.selectedMap[preferredGroup]
          : activeProfileObj.selectedMap.values.firstOrNull;
      if (activeNodeLabel == null && !isManagedSmartGroupName(fallbackLabel)) {
        activeNodeLabel = fallbackLabel;
      }
    }
  }
  final visibleMatchingNodeCount =
      countryCounts.values.fold<int>(0, (sum, count) => sum + count);
  final availableFilterHidAllNodes = profiles.isNotEmpty &&
      availableOnly &&
      !searching &&
      activeCountry == null &&
      scopeCountries.isNotEmpty &&
      visibleMatchingNodeCount == 0 &&
      !anyVisibleCatalogLoading;

  return _OverviewComputedSnapshot(
    profiles: profiles,
    testerBusy: testerBusy,
    tester: tester,
    activeId: activeId,
    tracker: tracker,
    liveActiveProfileIds: liveActiveProfileIds,
    isMobile: isMobile,
    sort: sort,
    selected: selected,
    cachedCatalogs: cachedCatalogs,
    currentScript: currentScript,
    query: query,
    searching: searching,
    locale: locale,
    countryCounts: countryCounts,
    availableCounts: availableCounts,
    activeDisplayCounts: activeDisplayCounts,
    healthByProfile: healthByProfile,
    loadErrorIds: loadErrorIds,
    resolvedCatalogs: resolvedCatalogs,
    anyVisibleCatalogLoading: anyVisibleCatalogLoading,
    orderedProfiles: orderedProfiles,
    visible: visible,
    activeCountry: activeCountry,
    sortedCountries: sortedCountries,
    activeCountryMatchCount: activeCountryMatchCount,
    targetTestProfile: targetTestProfile,
    canTestCurrent: canTestCurrent,
    quickUseAction: quickUseAction,
    isProxyRunning: isProxyRunning,
    effectivePendingTarget: effectivePendingTarget,
    statusStartCancelable: statusStartCancelable,
    activeProfileObj: activeProfileObj,
    activeIsSmart: activeIsSmart,
    targetModeProfile: targetModeProfile,
    currentSelectionMode: currentSelectionMode,
    canSwitchSelectionMode: canSwitchSelectionMode,
    activeNodeLabel: activeNodeLabel,
    availableFilterHidAllNodes: availableFilterHidAllNodes,
  );
}

/// Inline AppBar command accessory rendered when [CommonScaffoldState.isInlineTitleAccessoryActive] is true.
class NodeOverviewAppBarCommandBar extends ConsumerStatefulWidget {
  const NodeOverviewAppBarCommandBar({
    super.key,
    required this.controller,
  });

  final NodeOverviewCommandController controller;

  @override
  ConsumerState<NodeOverviewAppBarCommandBar> createState() =>
      _NodeOverviewAppBarCommandBarState();
}

class _NodeOverviewAppBarCommandBarState
    extends ConsumerState<NodeOverviewAppBarCommandBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant NodeOverviewAppBarCommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (!oldWidget.controller.isDisposed) {
        oldWidget.controller.removeListener(_onControllerChanged);
      }
      if (!widget.controller.isDisposed) {
        widget.controller.addListener(_onControllerChanged);
      }
    }
  }

  @override
  void dispose() {
    if (!widget.controller.isDisposed) {
      widget.controller.removeListener(_onControllerChanged);
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.isDisposed) {
      return const SizedBox.shrink();
    }
    final snapshot = _computeOverviewSnapshot(
      ref: ref,
      locale: Localizations.localeOf(context),
      rawSelectedProfile: controller.selectedProfile,
      rawSelectedCountry: controller.selectedCountry,
      availableOnly: controller.availableOnly,
      localProxyTogglePending: controller.localProxyTogglePending,
      visibleProfileIds: controller.visibleProfileIds,
      indexedProfiles: controller._indexedProfiles,
      stableProfileOrderIds: controller.stableProfileOrderIds,
      updatingOrderFreezeIds: controller.updatingOrderFreezeIds,
      mutateCaches: false,
      onActivateSmartSelection: controller.activateSmartSelection,
      onActivateManualSelection: controller.activateManualSelection,
      onUseActiveNode: controller.useActiveNode,
      onUseCatalogNode: controller.useCatalogNode,
    );
    return OverviewTopCommandBar(
      key: const ValueKey('overview-top-command-bar'),
      inline: true,
      hasProfiles: snapshot.profiles.isNotEmpty,
      isRunning: snapshot.isProxyRunning,
      pendingTarget: snapshot.effectivePendingTarget,
      isSmartMode: snapshot.activeIsSmart,
      activeProfileLabel:
          snapshot.activeProfileObj?.label ?? snapshot.activeProfileObj?.id,
      activeNodeName: snapshot.activeNodeLabel,
      selectionMode: snapshot.currentSelectionMode,
      onAddSubscription: controller.importingSubscription
          ? null
          : controller.openAddSubscription,
      onQuickUse: snapshot.quickUseAction,
      onSelectSmart: snapshot.canSwitchSelectionMode
          ? () => controller.activateSmartSelection(snapshot.targetModeProfile!)
          : null,
      onSelectManual: snapshot.canSwitchSelectionMode
          ? () => controller.activateManualSelection(snapshot.targetModeProfile!)
          : null,
    );
  }
}

String _formatOverviewConnectionStatusText({
  required bool isRunning,
  required bool? pendingTarget,
  required bool isSmartMode,
  required String? activeProfileLabel,
  required String? activeNodeName,
}) {
  if (pendingTarget != null) {
    return pendingTarget
        ? appLocalizations.nodeOverviewProxyStarting
        : appLocalizations.nodeOverviewProxyStopping;
  }
  if (isRunning) {
    final hasNode = activeProfileLabel != null &&
        activeNodeName != null &&
        activeNodeName.trim().isNotEmpty;
    if (isSmartMode && activeProfileLabel != null) {
      return hasNode
          ? appLocalizations.nodeOverviewProxyConnectedSmartWithNode(
              activeProfileLabel,
              activeNodeName,
            )
          : appLocalizations.nodeOverviewProxyConnectedSmart(
              activeProfileLabel,
            );
    }
    return hasNode
        ? appLocalizations.nodeOverviewProxyConnectedWithNode(
            activeProfileLabel,
            activeNodeName,
          )
        : appLocalizations.nodeOverviewProxyConnected;
  }
  return appLocalizations.nodeOverviewProxyDisconnected;
}

ButtonStyle _overviewTopActionButtonStyle(
  BuildContext context, {
  required bool emphasized,
  required bool inline,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  return ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: WidgetStatePropertyAll(Size(0, inline ? 32 : 30)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
    ),
    textStyle: WidgetStatePropertyAll(
      theme.textTheme.labelMedium?.copyWith(
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
        letterSpacing: 0.1,
      ),
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
        borderColor = colors.primary.withValues(alpha: hovered ? 0.68 : 0.48);
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
  );
}

class _OverviewCommandSegmentedButton extends StatelessWidget {
  const _OverviewCommandSegmentedButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.inline,
    this.allowEllipsis = true,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final String tooltip;
  final bool selected;
  final bool inline;
  final bool allowEllipsis;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onPressed != null;
    final bgColor = !enabled
        ? Colors.transparent
        : selected
            ? colors.primary.withValues(alpha: isDark ? 0.18 : 0.12)
            : Colors.transparent;
    final borderColor = selected && enabled
        ? colors.primary.withValues(alpha: isDark ? 0.42 : 0.30)
        : Colors.transparent;
    final fgColor = !enabled
        ? colors.onSurface.withValues(alpha: 0.38)
        : selected
            ? colors.primary
            : colors.onSurfaceVariant;
    final textWidget = Text(
      label,
      maxLines: 1,
      softWrap: allowEllipsis,
      overflow: allowEllipsis ? TextOverflow.ellipsis : TextOverflow.clip,
      style: theme.textTheme.labelMedium?.copyWith(
        color: fgColor,
        fontWeight: selected && enabled ? FontWeight.w700 : FontWeight.w500,
      ),
    );

    return Tooltip(
      message: tooltip,
      child: TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 28),
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: inline ? 4 : 3,
          ),
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          side: BorderSide(color: borderColor, width: 1.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 4),
            if (allowEllipsis) Flexible(child: textWidget) else textWidget,
          ],
        ),
      ),
    );
  }
}

/// Top command bar uniting subscription import, live connection status capsule,
/// smart/fixed selection mode switch, and one-click fastest connect.
class OverviewTopCommandBar extends StatelessWidget {
  const OverviewTopCommandBar({
    super.key,
    required this.inline,
    required this.hasProfiles,
    required this.isRunning,
    required this.pendingTarget,
    required this.isSmartMode,
    required this.activeProfileLabel,
    required this.activeNodeName,
    required this.selectionMode,
    required this.onAddSubscription,
    required this.onQuickUse,
    this.onSelectSmart,
    this.onSelectManual,
  });

  final bool inline;
  final bool hasProfiles;
  final bool isRunning;
  final bool? pendingTarget;
  final bool isSmartMode;
  final String? activeProfileLabel;
  final String? activeNodeName;
  final NodeSelectionMode selectionMode;
  final VoidCallback? onAddSubscription;
  final VoidCallback? onQuickUse;
  final VoidCallback? onSelectSmart;
  final VoidCallback? onSelectManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Widget buildActionButton({
      required Key buttonKey,
      required IconData icon,
      required String label,
      required bool emphasized,
      required VoidCallback? onPressed,
      required bool allowEllipsis,
    }) {
      final textWidget = Text(
        label,
        maxLines: 1,
        softWrap: allowEllipsis,
        overflow: allowEllipsis ? TextOverflow.ellipsis : TextOverflow.clip,
      );
      return TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: _overviewTopActionButtonStyle(
          context,
          emphasized: emphasized,
          inline: inline,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            if (allowEllipsis) Flexible(child: textWidget) else textWidget,
          ],
        ),
      );
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    Widget? buildConnectionBar({required bool singleRow}) {
      if (!hasProfiles) return null;
      final statusText = _formatOverviewConnectionStatusText(
        isRunning: isRunning,
        pendingTarget: pendingTarget,
        isSmartMode: isSmartMode,
        activeProfileLabel: activeProfileLabel,
        activeNodeName: activeNodeName,
      );
      final isBusy = pendingTarget != null;
      final effectiveConnected = pendingTarget ?? isRunning;
      final green = isDark ? kLatencyFastColor : const Color(0xFF059669);
      final bgColor = effectiveConnected
          ? Color.alphaBlend(
              green.withValues(alpha: isDark ? 0.14 : 0.09),
              colors.surfaceContainerLow,
            )
          : (isDark ? colors.surfaceContainer : colors.surfaceContainerLowest);
      final borderColor = effectiveConnected
          ? green.withValues(alpha: isDark ? 0.42 : 0.34)
          : freedomNetHairlineColor(colors);
      final leadingIcon = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveConnected
              ? green.withValues(alpha: isDark ? 0.20 : 0.14)
              : colors.surfaceContainerHighest.withValues(
                  alpha: isDark ? 0.65 : 0.85,
                ),
        ),
        child: SizedBox(
          width: inline ? 20 : 22,
          height: inline ? 20 : 22,
          child: Center(
            child: isBusy
                ? ExcludeSemantics(
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: effectiveConnected ? green : colors.primary,
                      ),
                    ),
                  )
                : Icon(
                    isRunning
                        ? Icons.shield_rounded
                        : Icons.power_settings_new_rounded,
                    size: 13,
                    color: isRunning ? green : colors.onSurfaceVariant,
                  ),
          ),
        ),
      );
      return DecoratedBox(
        key: const ValueKey('overview-connection-bar'),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Tooltip(
          message: statusText,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: inline ? 8 : 10,
              vertical: 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leadingIcon,
                SizedBox(width: inline ? 5 : 7),
                Flexible(
                  child: Text(
                    statusText,
                    maxLines: singleRow ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: isRunning ? FontWeight.w600 : FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildModeSegmentedTrack({
      required bool singleRow,
      required bool allowEllipsis,
    }) {
      final smartButton = _OverviewCommandSegmentedButton(
        buttonKey: const ValueKey('overview-mode-smart'),
        icon: Icons.auto_awesome_rounded,
        label: appLocalizations.nodeOverviewSmartSelectCompact,
        tooltip:
            '${appLocalizations.nodeOverviewSmartSelectTitle} · ${appLocalizations.nodeOverviewSmartSelectSubtitle}',
        selected: selectionMode == NodeSelectionMode.smart,
        inline: inline,
        allowEllipsis: allowEllipsis,
        onPressed: onSelectSmart,
      );
      final manualButton = _OverviewCommandSegmentedButton(
        buttonKey: const ValueKey('overview-mode-manual'),
        icon: Icons.push_pin_rounded,
        label: appLocalizations.nodeOverviewManualSelectCompact,
        tooltip:
            '${appLocalizations.nodeOverviewManualSelectTitle} · ${appLocalizations.nodeOverviewManualSelectSubtitle}',
        selected: selectionMode == NodeSelectionMode.manual,
        inline: inline,
        allowEllipsis: allowEllipsis,
        onPressed: onSelectManual,
      );
      return Container(
        key: const ValueKey('overview-mode-segmented-track'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.surfaceDim,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: freedomNetHairlineColor(colors)),
        ),
        child: singleRow
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  smartButton,
                  const SizedBox(width: 2),
                  manualButton,
                ],
              )
            : Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  smartButton,
                  manualButton,
                ],
              ),
      );
    }

    Widget buildSingleRowBar() {
      final addButton = buildActionButton(
        buttonKey: const ValueKey('overview-add-subscription'),
        icon: Icons.add_link_rounded,
        label: appLocalizations.nodeOverviewAddSubscription,
        emphasized: false,
        onPressed: onAddSubscription,
        allowEllipsis: false,
      );
      final connectionBar = buildConnectionBar(singleRow: true);
      final modeTrack = buildModeSegmentedTrack(
        singleRow: true,
        allowEllipsis: false,
      );
      final quickButton = buildActionButton(
        buttonKey: const ValueKey('overview-quick-use'),
        icon: Icons.bolt_rounded,
        label: appLocalizations.nodeOverviewQuickUse,
        emphasized: true,
        onPressed: onQuickUse,
        allowEllipsis: false,
      );
      return _InlineCommandBarRow(
        hasConnectionBar: connectionBar != null,
        textDirection: Directionality.of(context),
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: addButton,
          ),
          if (connectionBar != null) connectionBar,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: modeTrack,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: quickButton,
          ),
        ],
      );
    }

    if (inline) {
      return buildSingleRowBar();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(
          alpha: isDark ? 0.88 : 0.96,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: freedomNetHairlineColor(colors)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useSingleRow =
                constraints.maxWidth >= 840 && textScale <= 1.20;
            if (useSingleRow) {
              return buildSingleRowBar();
            }
            final addButton = buildActionButton(
              buttonKey: const ValueKey('overview-add-subscription'),
              icon: Icons.add_link_rounded,
              label: appLocalizations.nodeOverviewAddSubscription,
              emphasized: false,
              onPressed: onAddSubscription,
              allowEllipsis: true,
            );
            final connectionBar = buildConnectionBar(singleRow: false);
            final modeTrack = buildModeSegmentedTrack(
              singleRow: false,
              allowEllipsis: true,
            );
            final quickButton = buildActionButton(
              buttonKey: const ValueKey('overview-quick-use'),
              icon: Icons.bolt_rounded,
              label: appLocalizations.nodeOverviewQuickUse,
              emphasized: true,
              onPressed: onQuickUse,
              allowEllipsis: true,
            );
            return SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      addButton,
                      if (connectionBar != null) connectionBar,
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      modeTrack,
                      quickButton,
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InlineCommandBarRow extends MultiChildRenderObjectWidget {
  const _InlineCommandBarRow({
    required this.hasConnectionBar,
    required this.textDirection,
    required super.children,
  });

  final bool hasConnectionBar;
  final TextDirection textDirection;

  @override
  _RenderInlineCommandBarRow createRenderObject(BuildContext context) =>
      _RenderInlineCommandBarRow(
        hasConnectionBar: hasConnectionBar,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInlineCommandBarRow renderObject,
  ) {
    renderObject
      ..hasConnectionBar = hasConnectionBar
      ..textDirection = textDirection;
  }
}

class _InlineCommandBarParentData extends ContainerBoxParentData<RenderBox> {}

/// Single-row command layout that guarantees non-zero readable width for the
/// status capsule while scaling action buttons proportionally when tight.
class _RenderInlineCommandBarRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _InlineCommandBarParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox,
            _InlineCommandBarParentData> {
  _RenderInlineCommandBarRow({
    required bool hasConnectionBar,
    required TextDirection textDirection,
  })  : _hasConnectionBar = hasConnectionBar,
        _textDirection = textDirection;

  bool _hasConnectionBar;
  set hasConnectionBar(bool value) {
    if (_hasConnectionBar == value) return;
    _hasConnectionBar = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _InlineCommandBarParentData) {
      child.parentData = _InlineCommandBarParentData();
    }
  }

  double _gapForWidth(double maxWidth) =>
      maxWidth.isFinite && maxWidth < 460 ? 4.0 : 8.0;

  ({
    RenderBox add,
    RenderBox? conn,
    RenderBox mode,
    RenderBox quick,
  }) _orderedChildren() {
    final add = firstChild!;
    final second = childAfter(add)!;
    if (_hasConnectionBar) {
      final mode = childAfter(second)!;
      final quick = childAfter(mode)!;
      return (add: add, conn: second, mode: mode, quick: quick);
    }
    final quick = childAfter(second)!;
    return (add: add, conn: null, mode: second, quick: quick);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var total = 0.0;
    var count = 0;
    var child = firstChild;
    while (child != null) {
      total += child.getMinIntrinsicWidth(height);
      count++;
      child = childAfter(child);
    }
    if (count > 1) {
      total += 4.0 * (count - 1);
    }
    return total;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var total = 0.0;
    var count = 0;
    var child = firstChild;
    while (child != null) {
      total += child.getMaxIntrinsicWidth(height);
      count++;
      child = childAfter(child);
    }
    if (count > 1) {
      total += 8.0 * (count - 1);
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    var maxH = 0.0;
    var child = firstChild;
    while (child != null) {
      maxH = math.max(maxH, child.getMinIntrinsicHeight(width));
      child = childAfter(child);
    }
    return maxH;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    var maxH = 0.0;
    var child = firstChild;
    while (child != null) {
      maxH = math.max(maxH, child.getMaxIntrinsicHeight(width));
      child = childAfter(child);
    }
    return maxH;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (firstChild == null) {
      return constraints.smallest;
    }
    final slots = _orderedChildren();
    final maxHeight = constraints.maxHeight;
    final buttonDryConstraints = BoxConstraints(maxHeight: maxHeight);
    final addDry = slots.add.getDryLayout(buttonDryConstraints);
    final modeDry = slots.mode.getDryLayout(buttonDryConstraints);
    final quickDry = slots.quick.getDryLayout(buttonDryConstraints);

    if (!constraints.hasBoundedWidth) {
      const gap = 8.0;
      var totalW = addDry.width + modeDry.width + quickDry.width;
      var maxH = math.max(
        addDry.height,
        math.max(modeDry.height, quickDry.height),
      );
      if (slots.conn != null) {
        final connDry = slots.conn!.getDryLayout(buttonDryConstraints);
        totalW += connDry.width + gap * 3;
        maxH = math.max(maxH, connDry.height);
      } else {
        totalW += gap * 2;
      }
      return constraints.constrain(Size(totalW, maxH));
    }

    final maxWidth = constraints.maxWidth;
    final gap = _gapForWidth(maxWidth);
    final totalGaps = gap * (slots.conn != null ? 3 : 2);
    final avail = math.max(0.0, maxWidth - totalGaps);
    final buttonsNatural = addDry.width + modeDry.width + quickDry.width;
    final lower = slots.conn == null ? 0.0 : math.min(92.0, avail * 0.30);
    final upper = slots.conn == null
        ? 0.0
        : math.max(lower, math.min(148.0, avail * 0.42));
    final minConnWidth = slots.conn == null || avail <= 0
        ? 0.0
        : (maxWidth * 0.26).clamp(lower, upper);
    final buttonsBudget = math.max(0.0, avail - minConnWidth);
    final scale = (buttonsNatural > 0 && buttonsNatural > buttonsBudget)
        ? (buttonsBudget / buttonsNatural)
        : 1.0;

    var maxH = math.max(
      addDry.height * scale,
      math.max(modeDry.height * scale, quickDry.height * scale),
    );
    if (slots.conn != null) {
      final usedButtons = buttonsNatural * scale;
      final connDry = slots.conn!.getDryLayout(
        BoxConstraints(
          maxWidth: math.max(0.0, avail - usedButtons),
          maxHeight: maxHeight,
        ),
      );
      maxH = math.max(maxH, connDry.height);
    }
    return Size(
      constraints.constrainWidth(maxWidth),
      constraints.constrainHeight(maxH),
    );
  }

  @override
  void performLayout() {
    if (firstChild == null) {
      size = constraints.smallest;
      return;
    }
    final slots = _orderedChildren();
    final maxHeight = constraints.maxHeight;
    final dryConstraints = BoxConstraints(maxHeight: maxHeight);

    if (!constraints.hasBoundedWidth) {
      const gap = 8.0;
      slots.add.layout(dryConstraints, parentUsesSize: true);
      slots.conn?.layout(dryConstraints, parentUsesSize: true);
      slots.mode.layout(dryConstraints, parentUsesSize: true);
      slots.quick.layout(dryConstraints, parentUsesSize: true);

      var totalW =
          slots.add.size.width + slots.mode.size.width + slots.quick.size.width;
      var rowH = math.max(
        slots.add.size.height,
        math.max(slots.mode.size.height, slots.quick.size.height),
      );
      if (slots.conn != null) {
        totalW += slots.conn!.size.width + gap * 3;
        rowH = math.max(rowH, slots.conn!.size.height);
      } else {
        totalW += gap * 2;
      }
      final finalSize = constraints.constrain(Size(totalW, rowH));
      size = finalSize;

      final ordered = <RenderBox>[
        slots.add,
        if (slots.conn != null) slots.conn!,
        slots.mode,
        slots.quick,
      ];
      var x = 0.0;
      for (final child in ordered) {
        final pd = child.parentData! as _InlineCommandBarParentData;
        final dx = _textDirection == TextDirection.rtl
            ? finalSize.width - x - child.size.width
            : x;
        final dy = (finalSize.height - child.size.height) / 2;
        pd.offset = Offset(dx, dy);
        x += child.size.width + gap;
      }
      return;
    }

    final maxWidth = constraints.maxWidth;
    final gap = _gapForWidth(maxWidth);
    final totalGaps = gap * (slots.conn != null ? 3 : 2);
    final avail = math.max(0.0, maxWidth - totalGaps);

    final addDry = slots.add.getDryLayout(dryConstraints);
    final modeDry = slots.mode.getDryLayout(dryConstraints);
    final quickDry = slots.quick.getDryLayout(dryConstraints);
    final buttonsNatural = addDry.width + modeDry.width + quickDry.width;

    final lower = slots.conn == null ? 0.0 : math.min(92.0, avail * 0.30);
    final upper = slots.conn == null
        ? 0.0
        : math.max(lower, math.min(148.0, avail * 0.42));
    final minConnWidth = slots.conn == null || avail <= 0
        ? 0.0
        : (maxWidth * 0.26).clamp(lower, upper);
    final buttonsBudget = math.max(0.0, avail - minConnWidth);
    final scale = (buttonsNatural > 0 && buttonsNatural > buttonsBudget)
        ? (buttonsBudget / buttonsNatural)
        : 1.0;

    slots.add.layout(
      BoxConstraints(maxWidth: addDry.width * scale, maxHeight: maxHeight),
      parentUsesSize: true,
    );
    slots.mode.layout(
      BoxConstraints(maxWidth: modeDry.width * scale, maxHeight: maxHeight),
      parentUsesSize: true,
    );
    slots.quick.layout(
      BoxConstraints(maxWidth: quickDry.width * scale, maxHeight: maxHeight),
      parentUsesSize: true,
    );

    final usedButtons =
        slots.add.size.width + slots.mode.size.width + slots.quick.size.width;
    var rowH = math.max(
      slots.add.size.height,
      math.max(slots.mode.size.height, slots.quick.size.height),
    );
    if (slots.conn != null) {
      final connMaxWidth = math.max(0.0, avail - usedButtons);
      slots.conn!.layout(
        BoxConstraints(maxWidth: connMaxWidth, maxHeight: maxHeight),
        parentUsesSize: true,
      );
      rowH = math.max(rowH, slots.conn!.size.height);
    }

    final finalW = constraints.constrainWidth(maxWidth);
    final finalH = constraints.constrainHeight(rowH);
    size = Size(finalW, finalH);

    void place(RenderBox child, double logicalStart) {
      final pd = child.parentData! as _InlineCommandBarParentData;
      final dx = _textDirection == TextDirection.rtl
          ? finalW - logicalStart - child.size.width
          : logicalStart;
      final dy = (finalH - child.size.height) / 2;
      pd.offset = Offset(dx, dy);
    }

    place(slots.add, 0.0);
    if (slots.conn != null) {
      place(slots.conn!, slots.add.size.width + gap);
    }
    final quickStart = math.max(0.0, finalW - slots.quick.size.width);
    final modeStart = math.max(0.0, quickStart - gap - slots.mode.size.width);
    place(slots.mode, modeStart);
    place(slots.quick, quickStart);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
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
    required this.errorSummary,
    required this.hasUnresolvedProviders,
    required this.nodes,
  });

  final String? url;
  final DateTime? lastUpdateDate;
  final bool isUpdating;
  final String? scriptId;
  final String? scriptContent;
  final ProfileCatalogStatus status;
  final String? errorSummary;
  final bool hasUnresolvedProviders;
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
  final Set<String> failedProfileIds = <String>{};
  final Set<String> deferredProfileIds = <String>{};
  final Set<ProviderSubscription<Object?>> subscriptions =
      <ProviderSubscription<Object?>>{};
  int activeWorkers = 0;
  bool dirty = false;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    indexingProfileIds.clear();
    failedProfileIds.clear();
    deferredProfileIds.clear();
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
  final Set<String> _localVisibleProfileIds = <String>{};
  final Map<String, _IndexedProfileCountrySummary> _localIndexedProfiles =
      <String, _IndexedProfileCountrySummary>{};
  final List<ProviderSubscription<Object?>> _lifecycleSubscriptions =
      <ProviderSubscription<Object?>>[];
  List<String> _localStableProfileOrderIds = const <String>[];
  final Set<String> _localUpdatingOrderFreezeIds = <String>{};
  final Set<String> _syncingProfileIds = <String>{};
  final Set<String> _deletingProfileIds = <String>{};
  bool _syncingAll = false;
  bool _importingSubscription = false;
  bool _localProxyTogglePending = false;
  _IndexScanEpochState _scanEpoch = _IndexScanEpochState(0);
  bool _disposed = false;
  Timer? _clock;
  bool _tickerEnabled = true;
  bool _clockPaused = false;
  bool _pendingCountryScanOnResume = false;
  late final NodeCatalogTester _tester;
  String? _feedback;

  Set<String> get _visibleProfileIds =>
      widget.commandController?.visibleProfileIds ?? _localVisibleProfileIds;

  Map<String, _IndexedProfileCountrySummary> get _indexedProfiles =>
      widget.commandController?._indexedProfiles ?? _localIndexedProfiles;

  List<String> get _stableProfileOrderIds =>
      widget.commandController?.stableProfileOrderIds ??
      _localStableProfileOrderIds;

  set _stableProfileOrderIds(List<String> value) {
    final controller = widget.commandController;
    if (controller != null) {
      controller.stableProfileOrderIds = value;
    } else {
      _localStableProfileOrderIds = value;
    }
  }

  Set<String> get _updatingOrderFreezeIds =>
      widget.commandController?.updatingOrderFreezeIds ??
      _localUpdatingOrderFreezeIds;

  void _bindCommandController(NodeOverviewCommandController? controller) {
    controller?.bindView(
      owner: this,
      onOpenAddSubscription: () => unawaited(_openUrlSubscriptionImport()),
      onActivateSmartSelection: _activateSmartSelection,
      onActivateManualSelection: _activateManualSelection,
      onUseActiveNode: _useActiveNode,
      onUseCatalogNode: _useCatalogNode,
      selectedProfile: _selectedProfile,
      selectedCountry: _selectedCountry,
      availableOnly: _availableOnly,
      importingSubscription: _importingSubscription,
      localProxyTogglePending: _localProxyTogglePending,
    );
  }

  void _onProfileVisibilityChanged(String profileId, bool visible) {
    if (visible && _visibleProfileIds.add(profileId) && mounted) {
      setState(() {});
      widget.commandController?.notifySafely();
    }
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
      errorSummary: catalog.errorSummary,
      hasUnresolvedProviders:
          catalog.providerNodeCounts.values.any((count) => count < 0),
      nodes: catalog.nodes.map(_IndexedNodeSummary.fromNode).toList(),
    );
  }

  void _scheduleCountryIndexScan() {
    if (_disposed || !mounted) return;
    if (!ref.read(nodeOverviewEnabledProvider)) return;
    if (!_tickerEnabled || !uiActivity.value) {
      _pendingCountryScanOnResume = true;
      return;
    }
    _pendingCountryScanOnResume = false;
    _pumpCountryIndexWorkers(_scanEpoch);
  }

  void _pumpCountryIndexWorkers(_IndexScanEpochState epoch) {
    if (_disposed ||
        !mounted ||
        epoch.cancelled ||
        !identical(epoch, _scanEpoch)) {
      return;
    }
    if (!_tickerEnabled || !uiActivity.value) {
      _pendingCountryScanOnResume = true;
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
      if (epoch.indexingProfileIds.contains(profile.id) ||
          epoch.failedProfileIds.contains(profile.id) ||
          epoch.deferredProfileIds.contains(profile.id)) {
        continue;
      }
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
      widget.commandController?.notifySafely();
    }
  }

  Future<void> _indexSingleProfile(
    String profileId,
    _IndexScanEpochState epoch,
  ) async {
    ProviderSubscription<AsyncValue<ProfileCatalog>>? sub;
    Profile? snapshotAtStart;
    try {
      if (_disposed ||
          !mounted ||
          epoch.cancelled ||
          !identical(epoch, _scanEpoch)) {
        return;
      }
      snapshotAtStart = ref.read(profilesProvider).getProfile(profileId);
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
        if (catalog.status == ProfileCatalogStatus.loading) {
          epoch.deferredProfileIds.add(profile.id);
        } else {
          final currentScript = ref.read(scriptStateProvider).currentScript;
          _recordIndexedCatalog(profile, currentScript, catalog);
          epoch.dirty = true;
        }
      }
    } catch (_) {
      if (!_disposed &&
          mounted &&
          !epoch.cancelled &&
          identical(epoch, _scanEpoch)) {
        final profile = ref.read(profilesProvider).getProfile(profileId);
        final unchangedSinceStart = snapshotAtStart != null &&
            profile != null &&
            profile.url == snapshotAtStart.url &&
            profile.lastUpdateDate == snapshotAtStart.lastUpdateDate &&
            profile.isUpdating == snapshotAtStart.isUpdating;
        if (unchangedSinceStart && !profile.isUpdating) {
          final currentScript = ref.read(scriptStateProvider).currentScript;
          _indexedProfiles[profile.id] = _IndexedProfileCountrySummary(
            url: profile.url,
            lastUpdateDate: profile.lastUpdateDate,
            isUpdating: profile.isUpdating,
            scriptId: currentScript?.id,
            scriptContent: currentScript?.content,
            status: ProfileCatalogStatus.parseFailed,
            errorSummary: null,
            hasUnresolvedProviders: false,
            nodes: const [],
          );
          epoch.dirty = true;
        } else {
          epoch.failedProfileIds.add(profileId);
        }
      }
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
    _bindCommandController(widget.commandController);
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
      )
      ..add(
        ref.listenManual<int>(coreCatalogEpochProvider, (previous, next) {
          _scanEpoch.deferredProfileIds.clear();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_disposed) _scheduleCountryIndexScan();
          });
        }),
      )
      ..add(
        ref.listenManual<bool>(
          initProvider,
          (previous, isInit) {
            if (!isInit) return;
            _scanEpoch.deferredProfileIds.clear();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _disposed) return;
              _scheduleCountryIndexScan();
              if (ref.read(coldStartZeroProfilePromptedProvider)) return;
              ref.read(coldStartZeroProfilePromptedProvider.notifier).state =
                  true;
              if (ref.read(appSettingProvider).silentLaunch) return;
              if (!_tickerEnabled) return;
              if (ref.read(profilesProvider).isNotEmpty) return;
              unawaited(_openUrlSubscriptionImport());
            });
          },
          fireImmediately: true,
        ),
      )
      ..add(
        ref.listenManual<String?>(
          pendingNoviceFirstProfileAutoTestProvider,
          (previous, next) {
            if (next == null) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _consumePendingFirstProfileAutoTest();
            });
          },
          fireImmediately: true,
        ),
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
    uiActivity.addListener(_handleClockActivityChange);
    _syncClockState();
  }

  void _consumePendingFirstProfileAutoTest() {
    if (!mounted || _disposed || !_tickerEnabled) return;
    final pendingProfileId = ref.read(pendingNoviceFirstProfileAutoTestProvider);
    if (pendingProfileId == null) return;
    final imported = ref.read(profilesProvider).getProfile(pendingProfileId);
    ref.read(pendingNoviceFirstProfileAutoTestProvider.notifier).state = null;
    if (imported == null) return;
    unawaited(_autoTestAndActivateFirstProfile(imported));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled != enabled) {
      _tickerEnabled = enabled;
      _syncClockState(refreshOnResume: true);
      if (enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _consumePendingFirstProfileAutoTest();
        });
      }
    }
  }

  void _handleClockActivityChange() {
    _syncClockState(refreshOnResume: true);
  }

  void _syncClockState({bool refreshOnResume = false}) {
    final shouldRun = !_disposed && _tickerEnabled && uiActivity.value;
    if (!shouldRun) {
      if (_clock != null) {
        _clock?.cancel();
        _clock = null;
        _clockPaused = true;
      }
      return;
    }
    final resumed = _clockPaused;
    _clockPaused = false;
    _clock ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    if (resumed && refreshOnResume && mounted) {
      setState(() {});
    }
    if (_pendingCountryScanOnResume && mounted) {
      _scheduleCountryIndexScan();
    }
  }

  @override
  void didUpdateWidget(covariant NodeOverviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commandController != widget.commandController) {
      oldWidget.commandController?.unbindView(this);
      _bindCommandController(widget.commandController);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.commandController?.unbindView(this);
    uiActivity.removeListener(_handleClockActivityChange);
    _scanEpoch.cancel();
    for (final sub in _lifecycleSubscriptions) {
      sub.close();
    }
    _lifecycleSubscriptions.clear();
    _clock?.cancel();
    _clock = null;
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

  void _ensureProxyStartedIfStopped() {
    if (!globalState.isAppControllerReady) return;
    final isRunning = ref.read(runTimeProvider) != null;
    final pending = ref.read(statusSwitchPendingProvider);
    if (!isRunning && pending != true) {
      unawaited(
        globalState.appController
            .updateStatus(true)
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _toggleProxyMasterSwitch() async {
    if (!globalState.isAppControllerReady || _localProxyTogglePending) return;
    final providerPending = ref.read(statusSwitchPendingProvider);
    final startCancelable = ref.read(statusStartCancelableProvider);
    if (providerPending != null) {
      if (providerPending && startCancelable) {
        await globalState.appController.updateStatus(false);
      }
      return;
    }
    final isStart = ref.read(runTimeProvider) != null;
    setState(() {
      _localProxyTogglePending = true;
    });
    widget.commandController?.localProxyTogglePending = true;
    try {
      await globalState.appController.updateStatus(!isStart);
    } finally {
      if (mounted) {
        setState(() {
          _localProxyTogglePending = false;
        });
      } else {
        _localProxyTogglePending = false;
      }
      widget.commandController?.localProxyTogglePending = false;
    }
  }

  void _useActiveNode(
    Profile profile,
    String groupName,
    String proxyName, {
    String? feedbackOverride,
  }) {
    detectionState.notifyRoutingChanged();
    ref.read(nodeCountryResolverProvider).markSwitchingNode();
    if (globalState.isAppControllerReady) {
      globalState.appController
        ..updateCurrentSelectedMap(groupName, proxyName)
        ..changeProxyDebounce(groupName, proxyName);
    }
    final current =
        ref.read(profilesProvider).getProfile(profile.id) ?? profile;
    final updated = markProfileSelectionMode(
      current,
      NodeSelectionMode.manual,
      targetGroup: groupName,
      manualNodeName: proxyName,
    );
    if (updated != current) {
      ref.read(profilesProvider.notifier).setProfile(updated);
    }
    _ensureProxyStartedIfStopped();
    final feedback = feedbackOverride ??
        appLocalizations.nodeOverviewSwitchedToNode(
            updated.label ?? updated.id, proxyName);
    ref.read(_overviewSwitchTrackerProvider).feedback = feedback;
    if (mounted) {
      setState(() {
        _feedback = feedback;
      });
    }
  }

  void _useCatalogNode(
    Profile profile,
    CatalogNode node,
    String targetGroup, {
    String? feedbackOverride,
  }) {
    detectionState.notifyRoutingChanged();
    ref.read(nodeCountryResolverProvider).markSwitchingNode();
    if (_tester.busy) {
      unawaited(_tester.cancel());
    }
    final latest =
        ref.read(profilesProvider).getProfile(profile.id) ?? profile;
    final updated = markProfileSelectionMode(
      latest,
      NodeSelectionMode.manual,
      targetGroup: targetGroup,
      manualNodeName: node.name,
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
        ..pendingNodeName = feedbackOverride == null ? node.name : null
        ..pendingGroups = currentGroups
        ..pendingVersion = currentVersion
        ..feedback = feedbackOverride;
      ref.read(currentProfileIdProvider.notifier).value = updated.id;
    } else if (!isAlreadyLiveActive) {
      tracker
        ..pendingProfileId = updated.id
        ..pendingProfileLabel = updated.label ?? updated.id
        ..pendingNodeName = feedbackOverride == null ? node.name : null
        ..pendingGroups = currentGroups
        ..pendingVersion = currentVersion
        ..feedback = feedbackOverride;
      if (globalState.isAppControllerReady) {
        globalState.appController
          ..applyProfileDebounce(silence: true)
          ..changeProxyDebounce(targetGroup, node.name);
      }
    } else {
      if (globalState.isAppControllerReady) {
        globalState.appController.changeProxyDebounce(targetGroup, node.name);
      }
      tracker.feedback = feedbackOverride ??
          appLocalizations.nodeOverviewSwitchedToNode(
              updated.label ?? updated.id, node.name);
    }
    _ensureProxyStartedIfStopped();
    if (mounted) {
      setState(() {
        _feedback = tracker.feedback;
      });
    }
  }

  String _resolvePrimaryTargetGroupForProfile(
    Profile profile,
    ProfileCatalog? catalog,
  ) {
    final configuredMode = ref.read(patchClashConfigProvider).mode;
    final globalModeAllowed =
        profile.providerHeaders['flclashx-globalmode']?.toLowerCase() !=
            'false';
    final effectiveMode = configuredMode == Mode.direct
        ? Mode.rule
        : (configuredMode == Mode.global && !globalModeAllowed
            ? Mode.rule
            : configuredMode);
    if (effectiveMode == Mode.global) {
      return GroupName.GLOBAL.name;
    }
    final currentGroups = ref.read(currentGroupsStateProvider).value;
    final currentActiveId = ref.read(currentProfileIdProvider);
    if (currentActiveId == profile.id && currentGroups.isNotEmpty) {
      final preferred = profile.currentGroupName;
      if (preferred != null &&
          preferred != GroupName.GLOBAL.name &&
          currentGroups.any(
            (g) => g.name == preferred && g.type == GroupType.Selector,
          )) {
        return preferred;
      }
      final selector = currentGroups
          .where(
            (g) =>
                g.type == GroupType.Selector &&
                g.name != GroupName.GLOBAL.name &&
                !isManagedSmartGroupName(g.name),
          )
          .firstOrNull;
      if (selector != null) return selector.name;
    }
    if (catalog != null && catalog.nodes.isNotEmpty) {
      for (final allowInfo in const [false, true]) {
        for (final node in catalog.nodes) {
          if (!allowInfo && isInformationalProxyName(node.name)) continue;
          final g = _targetGroupForCatalogNode(profile, node, effectiveMode);
          if (g != null && g.isNotEmpty) return g;
        }
      }
    }
    final preferred = profile.currentGroupName;
    if (preferred != null &&
        preferred.isNotEmpty &&
        preferred != GroupName.GLOBAL.name) {
      return preferred;
    }
    final existingKey = profile.selectedMap.keys
        .where((k) => k.isNotEmpty && k != GroupName.GLOBAL.name)
        .firstOrNull;
    return existingKey ?? 'Proxy';
  }

  void _activateSmartSelection(
    Profile profile, {
    String? targetGroupOverride,
    bool silentFeedback = false,
  }) {
    detectionState.notifyRoutingChanged();
    ref.read(nodeCountryResolverProvider).markSwitchingNode();
    if (_tester.busy && !silentFeedback) {
      unawaited(_tester.cancel());
    }
    if (ref.read(patchClashConfigProvider).mode == Mode.direct) {
      ref
          .read(patchClashConfigProvider.notifier)
          .updateState((s) => s.copyWith(mode: Mode.rule));
    }
    final latest =
        ref.read(profilesProvider).getProfile(profile.id) ?? profile;
    final catalog = ref.read(profileCatalogProvider(latest.id)).valueOrNull ??
        ref.read(cachedProfileCatalogsProvider)[latest.id];
    final targetGroup = targetGroupOverride ??
        _resolvePrimaryTargetGroupForProfile(latest, catalog);
    final smartGroupName = managedSmartGroupNameFor(targetGroup);

    final tracker = ref.read(_overviewSwitchTrackerProvider);
    final currentActiveId = ref.read(currentProfileIdProvider);
    final verifiedRuntimeProfileId = globalState.lastRuntimeProfileId ??
        ref.read(activeNodeCatalogProvider)?.profileId;
    final allGroups = ref.read(groupsProvider);
    final currentVersion = ref.read(versionProvider);
    final attestation = _resolveSnapshotAttestation(
      tracker,
      allGroups,
      currentVersion,
    );
    final isAlreadyLiveActive = currentActiveId == latest.id &&
        (verifiedRuntimeProfileId == null ||
            verifiedRuntimeProfileId == latest.id) &&
        _isSnapshotLiveForProfile(
          profileId: latest.id,
          groups: allGroups,
          attestation: attestation,
        ) &&
        tracker.pendingProfileId != latest.id;

    final updated = markProfileSelectionMode(
      latest,
      NodeSelectionMode.smart,
      targetGroup: targetGroup,
    );

    if (currentActiveId != updated.id) {
      ref.read(profilesProvider.notifier).setProfile(updated);
      tracker
        ..pendingProfileId = updated.id
        ..pendingProfileLabel = updated.label ?? updated.id
        ..pendingNodeName = null
        ..pendingGroups = allGroups
        ..pendingVersion = currentVersion;
      ref.read(currentProfileIdProvider.notifier).value = updated.id;
    } else if (!isAlreadyLiveActive) {
      if (globalState.isAppControllerReady) {
        globalState.appController
            .updateCurrentSelectedMap(targetGroup, smartGroupName);
      }
      ref.read(profilesProvider.notifier).setProfile(updated);
      tracker
        ..pendingProfileId = updated.id
        ..pendingProfileLabel = updated.label ?? updated.id
        ..pendingNodeName = null
        ..pendingGroups = allGroups
        ..pendingVersion = currentVersion;
      if (globalState.isAppControllerReady) {
        globalState.appController
          ..applyProfileDebounce(silence: true)
          ..changeProxyDebounce(targetGroup, smartGroupName);
      }
    } else {
      if (globalState.isAppControllerReady) {
        globalState.appController
          ..updateCurrentSelectedMap(targetGroup, smartGroupName)
          ..changeProxyDebounce(targetGroup, smartGroupName);
      }
      ref.read(profilesProvider.notifier).setProfile(updated);
    }

    _ensureProxyStartedIfStopped();

    if (!silentFeedback) {
      final hitLeaf = (currentActiveId == updated.id && isAlreadyLiveActive)
          ? resolveSmartActiveLeafName(
              selectorGroupName: targetGroup,
              allGroups: allGroups,
              selectedMap: updated.selectedMap,
            )
          : null;
      final nextFeedback = hitLeaf != null
          ? appLocalizations.nodeOverviewSwitchedToSmartWithNode(
              updated.label ?? updated.id,
              hitLeaf,
            )
          : appLocalizations.nodeOverviewSwitchedToSmart(
              updated.label ?? updated.id,
            );
      tracker.feedback = nextFeedback;
      if (mounted) {
        setState(() {
          _feedback = nextFeedback;
        });
      }
    }
  }

  void _activateManualSelection(Profile profile) {
    if (ref.read(patchClashConfigProvider).mode == Mode.direct) {
      ref
          .read(patchClashConfigProvider.notifier)
          .updateState((s) => s.copyWith(mode: Mode.rule));
    }
    final latest =
        ref.read(profilesProvider).getProfile(profile.id) ?? profile;
    final catalog = ref.read(profileCatalogProvider(latest.id)).valueOrNull ??
        ref.read(cachedProfileCatalogsProvider)[latest.id];
    final targetGroup = _resolvePrimaryTargetGroupForProfile(latest, catalog);

    final tracker = ref.read(_overviewSwitchTrackerProvider);
    final currentActiveId = ref.read(currentProfileIdProvider);
    final verifiedRuntimeProfileId = globalState.lastRuntimeProfileId ??
        ref.read(activeNodeCatalogProvider)?.profileId;
    final allGroups = ref.read(groupsProvider);
    final currentVersion = ref.read(versionProvider);
    final attestation = _resolveSnapshotAttestation(
      tracker,
      allGroups,
      currentVersion,
    );
    final isAlreadyLiveActive = currentActiveId == latest.id &&
        (verifiedRuntimeProfileId == null ||
            verifiedRuntimeProfileId == latest.id) &&
        _isSnapshotLiveForProfile(
          profileId: latest.id,
          groups: allGroups,
          attestation: attestation,
        ) &&
        tracker.pendingProfileId != latest.id;

    if (isAlreadyLiveActive && allGroups.isNotEmpty) {
      final groupNames = {for (final g in allGroups) g.name};
      var chosenGroup = targetGroup;
      var chosenLeaf = resolveSmartActiveLeafName(
        selectorGroupName: targetGroup,
        allGroups: allGroups,
        selectedMap: latest.selectedMap,
      );

      if (chosenLeaf == null &&
          resolveProfileSelectionMode(latest) == NodeSelectionMode.manual) {
        final existing = latest.selectedMap[targetGroup];
        final selectorObj = allGroups.getGroup(targetGroup);
        if (existing != null &&
            existing.isNotEmpty &&
            !isManagedSmartGroupName(existing) &&
            (selectorObj?.all.any((p) => p.name == existing) ?? false)) {
          chosenLeaf = existing;
        }
      }

      if (chosenLeaf == null) {
        final visibleGroups = ref.read(currentGroupsStateProvider).value;
        final orderedSelectors = <Group>[
          if (allGroups.getGroup(targetGroup) case final Group primary
              when primary.type == GroupType.Selector)
            primary,
          for (final g in visibleGroups)
            if (g.type == GroupType.Selector && g.name != targetGroup) g,
        ];
        final health = ref.read(nodeHealthEntriesProvider(latest.id));
        final runtimeNodes = _uniqueCatalogNodes(
          ref.read(activeNodeCatalogProvider)?.profileId == latest.id
              ? ref.read(activeNodeCatalogProvider)
              : catalog,
        );
        for (final selector in orderedSelectors) {
          final leaves =
              selector.all.where((p) => _isLeaf(p, groupNames)).toList();
          if (leaves.isEmpty) continue;
          final nonInfo = leaves
              .where((p) => !isInformationalProxyName(p.name))
              .toList();
          final pool = (nonInfo.isNotEmpty ? nonInfo : leaves)
            ..sort((a, b) {
              final nodeA = runtimeNodes[a.name];
              final nodeB = runtimeNodes[b.name];
              final delayA =
                  nodeA != null ? _nodeHealth(nodeA, health)?.delayMs : null;
              final delayB =
                  nodeB != null ? _nodeHealth(nodeB, health)?.delayMs : null;
              final byDelay = _compareDelay(delayA, delayB);
              if (byDelay != 0) return byDelay;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          chosenGroup = selector.name;
          chosenLeaf = pool.first.name;
          break;
        }
      }

      if (chosenLeaf != null) {
        _useActiveNode(
          latest,
          chosenGroup,
          chosenLeaf,
          feedbackOverride: appLocalizations.nodeOverviewLockedManualNode(
            latest.label ?? latest.id,
            chosenLeaf,
          ),
        );
        return;
      }
    }

    if (catalog != null && catalog.nodes.isNotEmpty) {
      final effectiveMode = ref.read(patchClashConfigProvider).mode;
      final existingLeaf =
          resolveProfileSelectionMode(latest) == NodeSelectionMode.manual
              ? latest.selectedMap[targetGroup]
              : null;
      if (existingLeaf != null &&
          existingLeaf.isNotEmpty &&
          !isManagedSmartGroupName(existingLeaf)) {
        final match = catalog.nodes
            .where((n) => n.name == existingLeaf)
            .firstOrNull;
        if (match != null) {
          final grp =
              _targetGroupForCatalogNode(latest, match, effectiveMode) ??
                  targetGroup;
          _useCatalogNode(
            latest,
            match,
            grp,
            feedbackOverride: appLocalizations.nodeOverviewLockedManualNode(
              latest.label ?? latest.id,
              match.name,
            ),
          );
          return;
        }
      }

      final selectable = <(CatalogNode, String)>[];
      for (final node in catalog.nodes) {
        final grp = _targetGroupForCatalogNode(latest, node, effectiveMode);
        if (grp != null) selectable.add((node, grp));
      }
      if (selectable.isNotEmpty) {
        final nonInfo = selectable
            .where((pair) => !isInformationalProxyName(pair.$1.name))
            .toList();
        final pool = nonInfo.isNotEmpty ? nonInfo : selectable;
        final health = ref.read(nodeHealthEntriesProvider(latest.id));
        final candidateNodes = [for (final pair in pool) pair.$1];
        _sortNodes(candidateNodes, health, ProxiesSortType.delay);
        final chosenNode = candidateNodes.first;
        final chosenGrp =
            pool.firstWhere((pair) => identical(pair.$1, chosenNode)).$2;
        _useCatalogNode(
          latest,
          chosenNode,
          chosenGrp,
          feedbackOverride: appLocalizations.nodeOverviewLockedManualNode(
            latest.label ?? latest.id,
            chosenNode.name,
          ),
        );
        return;
      }
    }

    final updated = markProfileSelectionMode(latest, NodeSelectionMode.manual);
    ref.read(profilesProvider.notifier).setProfile(updated);
    if (ref.read(currentProfileIdProvider) != updated.id) {
      ref.read(currentProfileIdProvider.notifier).value = updated.id;
    }
    _ensureProxyStartedIfStopped();
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

  Future<void> _syncAllSubscriptions() async {
    if (_syncingAll || !globalState.isAppControllerReady) return;
    final targets = ref
        .read(profilesProvider)
        .where((p) =>
            p.type == ProfileType.url &&
            !p.isUpdating &&
            !_syncingProfileIds.contains(p.id))
        .toList();
    if (targets.isEmpty) return;
    final appController = globalState.appController;
    final targetIds = targets.map((p) => p.id).toSet();
    _syncingProfileIds.addAll(targetIds);
    setState(() {
      _syncingAll = true;
    });
    try {
      await globalState.safeRun(silence: false, () async {
        for (final target in targets) {
          appController.setProfile(target.copyWith(isUpdating: true));
        }
        Object? firstError;
        StackTrace? firstStack;
        await Future.wait(targets.map((target) async {
          try {
            await appController.updateProfile(target);
          } catch (e, st) {
            firstError ??= e;
            firstStack ??= st;
            final latest = mounted
                ? ref.read(profilesProvider).getProfile(target.id)
                : globalState.config.profiles.getProfile(target.id);
            final rollback = rollbackFailedProfileUpdate(latest);
            if (rollback != null) {
              appController.setProfile(rollback);
            }
          }
        }));
        if (firstError != null) {
          Error.throwWithStackTrace(firstError!, firstStack!);
        }
      });
    } finally {
      _syncingProfileIds.removeAll(targetIds);
      if (mounted) {
        setState(() {
          _syncingAll = false;
        });
      } else {
        _syncingAll = false;
      }
    }
  }

  Future<void> _confirmAndDeleteProfile(Profile targetProfile) async {
    if (_deletingProfileIds.contains(targetProfile.id) ||
        targetProfile.isUpdating ||
        !mounted) {
      return;
    }
    final bool? confirmed;
    if (globalState.navigatorKey.currentState != null) {
      confirmed = await globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(
          text: appLocalizations.deleteTip(appLocalizations.profile),
        ),
      );
    } else {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => CommonDialog(
          title: appLocalizations.tip,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(appLocalizations.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(appLocalizations.confirm),
            ),
          ],
          child: SizedBox(
            width: 300,
            child: Text(appLocalizations.deleteTip(appLocalizations.profile)),
          ),
        ),
      );
    }
    if (confirmed != true || !mounted || !globalState.isAppControllerReady) {
      return;
    }
    setState(() {
      _deletingProfileIds.add(targetProfile.id);
    });
    try {
      await globalState.safeRun(silence: false, () async {
        await globalState.appController.deleteProfile(targetProfile.id);
      });
      _visibleProfileIds.remove(targetProfile.id);
      _indexedProfiles.remove(targetProfile.id);
      _updatingOrderFreezeIds.remove(targetProfile.id);
      if (mounted) {
        setState(() {
          if (_selectedProfile == targetProfile.id) {
            _selectedProfile = null;
          }
        });
        widget.commandController?.setSelectedProfile(_selectedProfile);
      }
    } finally {
      _deletingProfileIds.remove(targetProfile.id);
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool _isTrafficExhausted(Profile profile) {
    final info = profile.subscriptionInfo;
    if (info == null || info.total <= 0) return false;
    return info.upload + info.download >= info.total;
  }

  Future<void> _autoTestAndActivateFirstProfile(Profile imported) async {
    if (!mounted || _disposed) return;
    if (ref.read(currentProfileIdProvider) == null) {
      ref.read(currentProfileIdProvider.notifier).value = imported.id;
    }
    final testUrl = ref.read(nodeOverviewTestUrlProvider);
    try {
      await _tester.testAll([imported], testUrl);
    } catch (_) {
      // Proceed to fallback node selection even if latency test could not run.
    }
    if (!mounted || _disposed) return;
    final latest = ref.read(profilesProvider).getProfile(imported.id);
    if (latest == null) return;

    ProfileCatalog? catalog =
        ref.read(cachedProfileCatalogsProvider)[latest.id];
    if (catalog == null || catalog.status == ProfileCatalogStatus.loading) {
      try {
        catalog = await ref.read(profileCatalogProvider(latest.id).future);
      } catch (_) {
        catalog = null;
      }
    }
    if (!mounted || _disposed) return;

    final configuredMode = ref.read(patchClashConfigProvider).mode;
    final effectiveMode =
        configuredMode == Mode.direct ? Mode.rule : configuredMode;
    final health = ref.read(nodeHealthEntriesProvider(latest.id));

    if (catalog != null && catalog.nodes.isNotEmpty) {
      final selectable = <(CatalogNode, String)>[];
      for (final node in catalog.nodes) {
        final group = _targetGroupForCatalogNode(latest, node, effectiveMode);
        if (group != null) {
          selectable.add((node, group));
        }
      }
      if (selectable.isNotEmpty) {
        final nonInfo = selectable
            .where((pair) => !isInformationalProxyName(pair.$1.name))
            .toList();
        final pool = nonInfo.isNotEmpty ? nonInfo : selectable;
        final candidateNodes = [for (final pair in pool) pair.$1];
        _sortNodes(candidateNodes, health, ProxiesSortType.delay);
        final chosenNode = candidateNodes.first;
        final chosenGroup =
            pool.firstWhere((pair) => identical(pair.$1, chosenNode)).$2;
        final chosenDelay = _nodeHealth(chosenNode, health)?.delayMs;

        if (configuredMode == Mode.direct) {
          ref
              .read(patchClashConfigProvider.notifier)
              .updateState((s) => s.copyWith(mode: Mode.rule));
        }
        _activateSmartSelection(
          latest,
          targetGroupOverride: chosenGroup,
          silentFeedback: true,
        );

        final String postFeedback;
        if (chosenDelay != null && chosenDelay > 0) {
          postFeedback = appLocalizations.nodeOverviewAutoConnectedSmartBest(
            latest.label ?? latest.id,
            chosenNode.name,
            chosenDelay,
          );
        } else if (_expired(latest, DateTime.now())) {
          postFeedback = appLocalizations
              .nodeOverviewAutoSelectedExpiredWarning(chosenNode.name);
        } else if (_isTrafficExhausted(latest)) {
          postFeedback = appLocalizations
              .nodeOverviewAutoSelectedTrafficExhaustedWarning(chosenNode.name);
        } else {
          postFeedback = appLocalizations
              .nodeOverviewAutoSelectedAllFailedWarning(chosenNode.name);
        }
        ref.read(_overviewSwitchTrackerProvider).feedback = postFeedback;
        if (mounted) {
          setState(() {
            _feedback = postFeedback;
          });
        }
        return;
      }
    }

    final groups = ref.read(currentGroupsStateProvider).value;
    final groupNames = {for (final g in ref.read(groupsProvider)) g.name};
    for (final group in groups) {
      if (group.type != GroupType.Selector) continue;
      final leaves = group.all.where((p) => _isLeaf(p, groupNames)).toList();
      if (leaves.isEmpty) continue;
      _activateSmartSelection(latest, targetGroupOverride: group.name);
      return;
    }
    _activateSmartSelection(latest);
  }

  Future<void> _openUrlSubscriptionImport({
    String? initialUrl,
    String? initialErrorText,
  }) async {
    if (_importingSubscription) return;
    setState(() {
      _importingSubscription = true;
    });
    widget.commandController?.importingSubscription = true;
    try {
      var nextInitialUrl = initialUrl;
      var nextInitialError = initialErrorText;
      while (mounted && !_disposed) {
        final String? url;
        var redirectedToPurchase = false;
        final dialog = URLFormDialog(
          initialUrl: nextInitialUrl,
          initialErrorText: nextInitialError,
          onGoToPurchase: () {
            redirectedToPurchase = true;
            if (globalState.isAppControllerReady) {
              globalState.appController.toPage(PageLabel.purchase);
            } else if (mounted) {
              ref.read(currentPageLabelProvider.notifier).value =
                  PageLabel.purchase;
            }
          },
        );
        if (globalState.navigatorKey.currentState != null) {
          url = await globalState.showCommonDialog<String>(
            child: dialog,
          );
        } else {
          if (!mounted) return;
          url = await showDialog<String>(
            context: context,
            builder: (_) => dialog,
          );
        }
        if (redirectedToPurchase ||
            url == null ||
            url.isEmpty ||
            !globalState.isAppControllerReady) {
          return;
        }
        final existingBeforeImport = {
          for (final p in ref.read(profilesProvider)) p.id,
        };
        final wasZeroProfiles = existingBeforeImport.isEmpty;
        globalState.lastSubscriptionImportError = null;
        globalState.suppressNextSubscriptionImportErrorDialog = true;
        String? importError;
        try {
          await globalState.appController.addProfileFormURL(url);
          importError = globalState.lastSubscriptionImportError;
        } catch (err) {
          importError = formatSubscriptionImportError(err);
        } finally {
          globalState.suppressNextSubscriptionImportErrorDialog = false;
        }
        if (importError != null) {
          nextInitialUrl = url;
          nextInitialError = importError;
          continue;
        }
        if (mounted && !_disposed) {
          final currentProfiles = ref.read(profilesProvider);
          for (final added in currentProfiles) {
            if (!existingBeforeImport.contains(added.id) &&
                !added.providerHeaders.containsKey(smartSelectionModeMarker) &&
                added.selectedMap.isEmpty) {
              ref.read(profilesProvider.notifier).setProfile(
                    markProfileSelectionMode(added, NodeSelectionMode.smart),
                  );
            }
          }
        }
        if (wasZeroProfiles && mounted && !_disposed) {
          final imported = ref.read(profilesProvider).firstOrNull;
          if (imported != null) {
            unawaited(_autoTestAndActivateFirstProfile(imported));
          }
        }
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingSubscription = false;
        });
      } else {
        _importingSubscription = false;
      }
      widget.commandController?.importingSubscription = false;
    }
  }

  bool _isInlineHeaderMounted(
    CommonScaffoldState? scaffoldState,
    BuildContext callerContext,
  ) {
    final controller = widget.commandController;
    final inlineAccessory = controller?.inlineAccessoryWidget;
    return controller != null &&
        inlineAccessory != null &&
        scaffoldState != null &&
        _tickerEnabled &&
        scaffoldState.isInlineTitleAccessoryActiveFor(callerContext) &&
        identical(scaffoldState.titleAccessory, inlineAccessory);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _computeOverviewSnapshot(
      ref: ref,
      locale: Localizations.localeOf(context),
      rawSelectedProfile: _selectedProfile,
      rawSelectedCountry: _selectedCountry,
      availableOnly: _availableOnly,
      localProxyTogglePending: _localProxyTogglePending,
      visibleProfileIds: _visibleProfileIds,
      indexedProfiles: _indexedProfiles,
      stableProfileOrderIds: _stableProfileOrderIds,
      updatingOrderFreezeIds: _updatingOrderFreezeIds,
      mutateCaches: true,
      onUpdateStableOrder: (nextOrder) => _stableProfileOrderIds = nextOrder,
      onActivateSmartSelection: _activateSmartSelection,
      onActivateManualSelection: _activateManualSelection,
      onUseActiveNode: _useActiveNode,
      onUseCatalogNode: _useCatalogNode,
    );
    final profiles = snapshot.profiles;
    final testerBusy = snapshot.testerBusy;
    final tester = snapshot.tester;
    final activeId = snapshot.activeId;
    final tracker = snapshot.tracker;
    bool isLiveActive(Profile profile) =>
        snapshot.liveActiveProfileIds.contains(profile.id);
    if (tracker.feedback != null && _feedback != tracker.feedback) {
      _feedback = tracker.feedback;
    }
    final feedback = tracker.feedback ?? _feedback;
    final isMobile = snapshot.isMobile;
    final sort = snapshot.sort;
    final selected = snapshot.selected;
    final currentScript = snapshot.currentScript;
    final searching = snapshot.searching;
    final locale = snapshot.locale;
    final countryCounts = snapshot.countryCounts;
    final availableCounts = snapshot.availableCounts;
    final activeDisplayCounts = snapshot.activeDisplayCounts;
    final healthByProfile = snapshot.healthByProfile;
    final loadErrorIds = snapshot.loadErrorIds;
    final resolvedCatalogs = snapshot.resolvedCatalogs;
    final anyVisibleCatalogLoading = snapshot.anyVisibleCatalogLoading;
    final orderedProfiles = snapshot.orderedProfiles;
    final visible = snapshot.visible;
    final activeCountry = snapshot.activeCountry;
    if (_selectedCountry != null &&
        activeCountry == null &&
        !anyVisibleCatalogLoading) {
      final staleCountry = _selectedCountry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedCountry == staleCountry) {
          setState(() => _selectedCountry = null);
          widget.commandController?.setSelectedCountry(null);
        }
      });
    }
    final sortedCountries = snapshot.sortedCountries;
    final activeCountryMatchCount = snapshot.activeCountryMatchCount;
    final testCurrentAction = snapshot.canTestCurrent
        ? () => _testCurrent(selected == null ? null : snapshot.targetTestProfile)
        : null;
    final quickUseAction = snapshot.quickUseAction;
    final isProxyRunning = snapshot.isProxyRunning;
    final effectivePendingTarget = snapshot.effectivePendingTarget;
    final statusStartCancelable = snapshot.statusStartCancelable;
    final activeProfileObj = snapshot.activeProfileObj;
    final activeIsSmart = snapshot.activeIsSmart;
    final targetModeProfile = snapshot.targetModeProfile;
    final currentSelectionMode = snapshot.currentSelectionMode;
    final canSwitchSelectionMode = snapshot.canSwitchSelectionMode;
    final activeNodeLabel = snapshot.activeNodeLabel;
    final availableFilterHidAllNodes = snapshot.availableFilterHidAllNodes;
    final now = DateTime.now();
    final scaffoldState = context.commonScaffoldState;
    final slotListenable = scaffoldState?.headerSlotListenable;
    final toggleAction = globalState.isAppControllerReady
        ? () => unawaited(_toggleProxyMasterSwitch())
        : null;
    String? activeFallbackCountryCode;
    if (activeNodeLabel != null && activeNodeLabel.isNotEmpty) {
      final resolved = ref.read(nodeCountryResolverProvider).resolveCountryCode(
            profileId: activeProfileObj?.id ?? '',
            profileLabel: activeProfileObj?.label,
            nodeName: activeNodeLabel,
            isLiveActive: activeProfileObj != null &&
                snapshot.liveActiveProfileIds.contains(activeProfileObj.id),
            inUse: true,
          );
      activeFallbackCountryCode = resolved != kUnknownCountryCode
          ? resolved
          : inferCountryCodeFromText(activeNodeLabel);
    }
    final floatingProxyDock = profiles.isNotEmpty
        ? FloatingProxyDock(
            key: const ValueKey('overview-floating-proxy-dock'),
            isRunning: isProxyRunning,
            pendingTarget: effectivePendingTarget,
            startCancelable: statusStartCancelable,
            fallbackCountryCode: activeFallbackCountryCode,
            onToggle: toggleAction,
          )
        : null;

    Widget buildFallbackTopCommandBar() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: OverviewTopCommandBar(
            key: const ValueKey('overview-top-command-bar'),
            inline: false,
            hasProfiles: profiles.isNotEmpty,
            isRunning: isProxyRunning,
            pendingTarget: effectivePendingTarget,
            isSmartMode: activeIsSmart,
            activeProfileLabel:
                activeProfileObj?.label ?? activeProfileObj?.id,
            activeNodeName: activeNodeLabel,
            selectionMode: currentSelectionMode,
            onAddSubscription: _importingSubscription
                ? null
                : () => unawaited(_openUrlSubscriptionImport()),
            onQuickUse: quickUseAction,
            onSelectSmart: canSwitchSelectionMode
                ? () => _activateSmartSelection(targetModeProfile!)
                : null,
            onSelectManual: canSwitchSelectionMode
                ? () => _activateManualSelection(targetModeProfile!)
                : null,
          ),
        );

    return LayoutBuilder(builder: (context, constraints) {
      final wide = !isMobile && constraints.maxWidth > maxLaptopWidth;
      return FloatingProxyDockOverlay(
        viewportWidth: constraints.maxWidth,
        viewportHeight: constraints.maxHeight,
        dock: floatingProxyDock,
        child: Column(children: [
        if (slotListenable != null)
          ListenableBuilder(
            listenable: slotListenable,
            builder: (slotContext, _) {
              // Ensure MediaQuery dependency is registered regardless of branch short-circuiting.
              MediaQuery.maybeOf(slotContext);
              if (_isInlineHeaderMounted(
                slotContext.commonScaffoldState,
                slotContext,
              )) {
                return const SizedBox(height: 4);
              }
              return buildFallbackTopCommandBar();
            },
          )
        else
          buildFallbackTopCommandBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
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
                    items: _buildNarrowPickerItems(
                      orderedProfiles: orderedProfiles,
                      activeId: activeId,
                      isLiveActive: isLiveActive,
                      activeDisplayCounts: activeDisplayCounts,
                      availableCounts: availableCounts,
                      resolvedCatalogs: resolvedCatalogs,
                      indexedProfiles: _indexedProfiles,
                      currentScript: currentScript,
                      healthByProfile: healthByProfile,
                      loadErrorIds: loadErrorIds,
                      now: now,
                    ),
                    onChanged: (value) {
                      setState(() => _selectedProfile = value);
                      widget.commandController?.setSelectedProfile(value);
                    },
                  ),
                _OverviewAvailableFilterButton(
                  key: const ValueKey('overview-available-only'),
                  selected: _availableOnly,
                  onChanged: (value) {
                    setState(() => _availableOnly = value);
                    widget.commandController?.availableOnly = value;
                  },
                ),
                _OverviewSortSelector(
                  value: sort,
                  onChanged: (value) {
                    ref
                        .read(proxiesStyleSettingProvider.notifier)
                        .updateState((state) => state.copyWith(sortType: value));
                  },
                ),
                TextButton(
                  key: const ValueKey('overview-test-current'),
                  onPressed: testCurrentAction,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, size: 17),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          appLocalizations.nodeOverviewTestCurrent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('overview-test-all'),
                  onPressed: testerBusy || profiles.isEmpty
                      ? null
                      : () => _testAll(profiles),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, size: 17),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          appLocalizations.nodeOverviewTestAll,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final code in sortedCountries)
                  FilterChip(
                    key: ValueKey('overview-country-$code'),
                    label: _CountryLabelText(
                      emoji: nodeCountryEmoji(code),
                      text:
                          '${nodeCountryName(code, locale: locale)} (${countryCounts[code] ?? 0})',
                    ),
                    selected: activeCountry == code,
                    onSelected: (value) {
                      final nextCountry = value ? code : null;
                      setState(() => _selectedCountry = nextCountry);
                      widget.commandController?.setSelectedCountry(nextCountry);
                    },
                  ),
                if (testerBusy) ...[
                  Consumer(
                    builder: (context, ref, _) {
                      final (completed, total) = ref.watch(
                        nodeCatalogTesterProvider.select(
                          (t) => (t.completed, t.total),
                        ),
                      );
                      return Text(
                        appLocalizations.nodeOverviewProgress(completed, total),
                      );
                    },
                  ),
                  TextButton(
                    key: const ValueKey('overview-cancel'),
                    onPressed: () => unawaited(tester.cancel()),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.close, size: 17),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            appLocalizations.cancel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!_isNoviceAppShell(
                  context,
                  ref.watch(expertNavigationExpandedProvider),
                ))
                  Tooltip(
                    key: const ValueKey('overview-history-notice-tooltip'),
                    message: appLocalizations.nodeOverviewHistoryNotice,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (testerBusy)
          Consumer(
            builder: (context, ref, _) {
              final (completed, total) = ref.watch(
                nodeCatalogTesterProvider.select(
                  (t) => (t.completed, t.total),
                ),
              );
              return ExcludeSemantics(
                child: LinearProgressIndicator(
                    value: total == 0
                        ? null
                        : (completed / total).clamp(0.0, 1.0)),
              );
            },
          ),
        if (feedback != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: freedomNetHairlineColor(
                    Theme.of(context).colorScheme,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        feedback,
                        key: const ValueKey('overview-feedback'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('overview-feedback-dismiss'),
                      onPressed: () {
                        ref.read(_overviewSwitchTrackerProvider).feedback =
                            null;
                        setState(() => _feedback = null);
                      },
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: appLocalizations.cancel,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(4),
                        minimumSize: const Size(28, 28),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                        final urlProfiles = orderedProfiles
                            .where((p) => p.type == ProfileType.url)
                            .toList();
                        final allUrlUpdating = urlProfiles.isNotEmpty &&
                            (_syncingAll ||
                                urlProfiles.every((p) => p.isUpdating));
                        String? liveActiveId;
                        for (final p in orderedProfiles) {
                          if (isLiveActive(p)) {
                            liveActiveId = p.id;
                            break;
                          }
                        }
                        return _SidebarAllProfilesCard(
                          profiles: orderedProfiles,
                          selected: selected == null,
                          activeId: activeId,
                          liveActiveProfileId: liveActiveId,
                          resolvedCatalogs: resolvedCatalogs,
                          indexedProfiles: _indexedProfiles,
                          currentScript: currentScript,
                          healthByProfile: healthByProfile,
                          loadErrorIds: loadErrorIds,
                          failedIndexIds: _scanEpoch.failedProfileIds,
                          now: now,
                          updatingAll: allUrlUpdating,
                          onSyncAll: urlProfiles.isNotEmpty
                              ? () => unawaited(_syncAllSubscriptions())
                              : null,
                          onSelect: () {
                            setState(() => _selectedProfile = null);
                            widget.commandController?.setSelectedProfile(null);
                          },
                        );
                      }
                      final profile = orderedProfiles[index - 1];
                      final isCurrent = profile.id == activeId;
                      final isExpired = _expired(profile, now);
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
                          showDelete: isExpired,
                          deleting: _deletingProfileIds.contains(profile.id),
                          onDelete: isExpired && !profile.isUpdating
                              ? () =>
                                  unawaited(_confirmAndDeleteProfile(profile))
                              : null,
                          onVisible: () =>
                              _onProfileVisibilityChanged(profile.id, true),
                          onSelect: () {
                            setState(() => _selectedProfile = profile.id);
                            widget.commandController
                                ?.setSelectedProfile(profile.id);
                          });
                    },
                  )),
              const VerticalDivider(width: 16),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, paneConstraints) {
                  final paneTextScale =
                      MediaQuery.textScalerOf(context).scale(1.0);
                  final floatingBottomMargin =
                      computeFloatingProxyDockBottomMargin(
                    constraints.maxHeight,
                  );
                  final bottomScrollClearance = profiles.isNotEmpty
                      ? computeFloatingProxyDockScrollClearance(
                          textScale: paneTextScale,
                          bottomMargin: floatingBottomMargin,
                          viewportWidth: constraints.maxWidth,
                          viewportHeight: constraints.maxHeight,
                        )
                      : 32.0;
                  return CustomScrollView(
                    key: const ValueKey('overview-nodes'),
                    slivers: [
                      for (final profile in visible)
                        _ProfileNodesSliver(
                            key: ValueKey('overview-section-${profile.id}'),
                            profile: profile,
                            active: profile.id == activeId,
                            liveActive: isLiveActive(profile),
                            showHeader: selected == null,
                            showSubscriptionSummary: !wide || selected != null,
                            onSyncSubscription:
                                profile.type == ProfileType.url &&
                                        (!wide || selected != null)
                                    ? () =>
                                        unawaited(_syncSubscription(profile))
                                    : null,
                            syncButtonKey: wide
                                ? ValueKey('overview-detail-sync-${profile.id}')
                                : ValueKey('overview-sync-${profile.id}'),
                            showDeleteSubscription: _expired(profile, now) &&
                                (!wide || selected != null),
                            deletingSubscription:
                                _deletingProfileIds.contains(profile.id),
                            onDeleteSubscription: _expired(profile, now) &&
                                    !profile.isUpdating &&
                                    (!wide || selected != null)
                                ? () => unawaited(
                                    _confirmAndDeleteProfile(profile))
                                : null,
                            deleteButtonKey: wide
                                ? ValueKey(
                                    'overview-detail-delete-${profile.id}')
                                : ValueKey('overview-delete-${profile.id}'),
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
                      if (profiles.isEmpty)
                        SliverToBoxAdapter(
                          child: _OverviewEmptyProfilesCard(
                            key: const ValueKey('overview-empty-profiles'),
                            onAddSubscription: _importingSubscription
                                ? null
                                : () => unawaited(_openUrlSubscriptionImport()),
                            onGoToPurchase: () {
                              if (globalState.isAppControllerReady) {
                                globalState.appController
                                    .toPage(PageLabel.purchase);
                              } else {
                                ref
                                    .read(currentPageLabelProvider.notifier)
                                    .value = PageLabel.purchase;
                              }
                            },
                          ),
                        ),
                      if (availableFilterHidAllNodes)
                        SliverToBoxAdapter(
                          child: _OverviewAvailableFilterEmptyBanner(
                            key: const ValueKey(
                                'overview-available-only-empty'),
                            onShowAllNodes: () {
                              setState(() => _availableOnly = false);
                              final controller = widget.commandController;
                              if (controller != null) {
                                controller.availableOnly = false;
                              }
                            },
                          ),
                        ),
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
                      SliverToBoxAdapter(
                        child: SizedBox(height: bottomScrollClearance),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        )),
      ]),
    );
    });
  }
}

class _OverviewEmptyProfilesCard extends StatelessWidget {
  const _OverviewEmptyProfilesCard({
    super.key,
    required this.onAddSubscription,
    this.onGoToPurchase,
  });

  final VoidCallback? onAddSubscription;
  final VoidCallback? onGoToPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_link_rounded,
                size: 40,
                color: colors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                appLocalizations.nodeOverviewEmptyTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appLocalizations.nodeOverviewEmptySubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  appLocalizations.nodeOverviewEmptyStepsHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('overview-empty-add-subscription'),
                onPressed: onAddSubscription,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.content_paste_go_rounded, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        appLocalizations.nodeOverviewAddSubscription,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (onGoToPurchase != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('overview-empty-go-purchase'),
                  onPressed: onGoToPurchase,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          appLocalizations.goToPurchasePrompt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewAvailableFilterEmptyBanner extends StatelessWidget {
  const _OverviewAvailableFilterEmptyBanner({
    super.key,
    required this.onShowAllNodes,
  });

  final VoidCallback onShowAllNodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                appLocalizations.nodeOverviewAvailableFilterEmpty,
                style: theme.textTheme.bodyMedium,
              ),
              FilledButton.tonal(
                key: const ValueKey('overview-reset-available-filter'),
                onPressed: onShowAllNodes,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(appLocalizations.nodeOverviewShowAllNodes),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

typedef _AllProfilesOverviewSummary = ({
  int usableProfileCount,
  bool hasPendingProfiles,
  int availableNodes,
  int testedNodes,
  int totalNodes,
  int fastCount,
  int slowCount,
  int failedCount,
  int untestedCount,
  int? medianMs,
  int? bestMs,
  int expiredCount,
  int expiringSoonCount,
});

class _SidebarAllProfilesCard extends ConsumerWidget {
  const _SidebarAllProfilesCard({
    required this.profiles,
    required this.selected,
    required this.activeId,
    required this.liveActiveProfileId,
    required this.resolvedCatalogs,
    required this.indexedProfiles,
    required this.currentScript,
    required this.healthByProfile,
    required this.loadErrorIds,
    required this.failedIndexIds,
    required this.now,
    required this.updatingAll,
    required this.onSyncAll,
    required this.onSelect,
  });

  final List<Profile> profiles;
  final bool selected;
  final String? activeId;
  final String? liveActiveProfileId;
  final Map<String, ProfileCatalog?> resolvedCatalogs;
  final Map<String, _IndexedProfileCountrySummary> indexedProfiles;
  final Script? currentScript;
  final Map<String, Map<String, NodeHealthRecord>> healthByProfile;
  final Set<String> loadErrorIds;
  final Set<String> failedIndexIds;
  final DateTime now;
  final bool updatingAll;
  final VoidCallback? onSyncAll;
  final VoidCallback onSelect;

  _AllProfilesOverviewSummary _computeSummary(WidgetRef ref) {
    var usableProfileCount = 0;
    var hasPendingProfiles = false;
    var availableNodes = 0;
    var testedNodes = 0;
    var totalNodes = 0;
    var fastCount = 0;
    var slowCount = 0;
    var failedCount = 0;
    var expiredCount = 0;
    var expiringSoonCount = 0;
    final positiveDelays = <int>[];

    void accumulateDelay(int? delay) {
      if (delay == null || delay == 0) return;
      testedNodes++;
      if (delay > 0) {
        availableNodes++;
        positiveDelays.add(delay);
        if (delay <= kLatencyFastMaxMs) {
          fastCount++;
        } else {
          slowCount++;
        }
      } else {
        failedCount++;
      }
    }

    for (final profile in profiles) {
      final sub = _hasMeaningfulSubscriptionInfo(profile.subscriptionInfo)
          ? profile.subscriptionInfo
          : null;
      if (sub != null) {
        final expiry = _resolveSubscriptionExpiryState(sub.expire, now);
        if (expiry != null) {
          if (expiry.isExpired) {
            expiredCount++;
          } else if (expiry.isExpiringSoon) {
            expiringSoonCount++;
          }
        }
      }

      if (profile.id == liveActiveProfileId) {
        final displays = _activeDisplays(
          ref,
          profile.id,
          profile.isUpdating ? null : resolvedCatalogs[profile.id],
        );
        if (displays.isNotEmpty) {
          usableProfileCount++;
          totalNodes += displays.length;
          for (final entry in displays.values) {
            accumulateDelay(entry.delay);
          }
          continue;
        }
        if (profile.isUpdating) {
          hasPendingProfiles = true;
          continue;
        }
      }

      if (profile.isUpdating) {
        hasPendingProfiles = true;
        continue;
      }

      final catalog = resolvedCatalogs[profile.id];
      final indexed = indexedProfiles[profile.id];
      final validIndexed =
          indexed != null && indexed.matchesProfile(profile, currentScript)
              ? indexed
              : null;
      final health =
          healthByProfile[profile.id] ?? const <String, NodeHealthRecord>{};

      if (catalog != null) {
        if (catalog.status == ProfileCatalogStatus.loading ||
            catalog.status == ProfileCatalogStatus.updating) {
          hasPendingProfiles = true;
        } else if (catalog.status == ProfileCatalogStatus.fileMissing ||
            catalog.status == ProfileCatalogStatus.parseFailed) {
          // Excluded from usable count without marking as pending.
        } else {
          usableProfileCount++;
          for (final node in catalog.nodes) {
            if (node.unsupported == CatalogUnsupportedReason.parseFailed) {
              continue;
            }
            totalNodes++;
            accumulateDelay(_nodeHealth(node, health)?.delayMs);
          }
        }
      } else if (validIndexed != null) {
        if (validIndexed.status == ProfileCatalogStatus.loading ||
            validIndexed.status == ProfileCatalogStatus.updating) {
          hasPendingProfiles = true;
        } else if (validIndexed.status == ProfileCatalogStatus.fileMissing ||
            validIndexed.status == ProfileCatalogStatus.parseFailed) {
          // Excluded from usable count without marking as pending.
        } else {
          usableProfileCount++;
          for (final node in validIndexed.nodes) {
            if (node.parseFailed) continue;
            totalNodes++;
            accumulateDelay(health[node.identityKey]?.delayMs);
          }
        }
      } else if (loadErrorIds.contains(profile.id) ||
          failedIndexIds.contains(profile.id)) {
        // Known load failure.
      } else {
        hasPendingProfiles = true;
      }
    }

    positiveDelays.sort();
    final int? medianMs;
    final int? bestMs;
    if (positiveDelays.isEmpty) {
      medianMs = null;
      bestMs = null;
    } else {
      bestMs = positiveDelays.first;
      medianMs = positiveDelays.length.isOdd
          ? positiveDelays[positiveDelays.length ~/ 2]
          : ((positiveDelays[positiveDelays.length ~/ 2 - 1] +
                      positiveDelays[positiveDelays.length ~/ 2]) /
                  2)
              .round();
    }

    return (
      usableProfileCount: usableProfileCount,
      hasPendingProfiles: hasPendingProfiles,
      availableNodes: availableNodes,
      testedNodes: testedNodes,
      totalNodes: totalNodes,
      fastCount: fastCount,
      slowCount: slowCount,
      failedCount: failedCount,
      untestedCount: math.max(0, totalNodes - testedNodes),
      medianMs: medianMs,
      bestMs: bestMs,
      expiredCount: expiredCount,
      expiringSoonCount: expiringSoonCount,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = _computeSummary(ref);
    Profile? activeProfile;
    if (activeId != null) {
      for (final p in profiles) {
        if (p.id == activeId) {
          activeProfile = p;
          break;
        }
      }
    }

    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      height: 1.35,
      color: colors.onSurfaceVariant,
    );

    final syncAllButton = onSyncAll == null
        ? null
        : _ProfileSyncButton(
            key: const ValueKey('overview-sync-all'),
            updating: updatingAll,
            selectedCard: selected,
            maxWidth: 118,
            idleLabel: appLocalizations.nodeOverviewUpdateAllSubscriptions,
            tooltipIdleLabel:
                appLocalizations.nodeOverviewUpdateAllSubscriptions,
            onPressed: onSyncAll,
          );

    return Card(
      color: selected ? colors.secondaryContainer : null,
      child: InkWell(
        key: const ValueKey('overview-select-all'),
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.layers_rounded,
                    size: 15,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      appLocalizations.nodeOverviewAllProfiles,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (syncAllButton != null) ...[
                    const SizedBox(width: 6),
                    syncAllButton,
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _SubscriptionTagPill(
                    icon: Icons.inventory_2_outlined,
                    label: appLocalizations
                        .nodeOverviewAllProfilesCount(profiles.length),
                    foreground: colors.onSurfaceVariant,
                    background:
                        colors.surfaceContainerHighest.withValues(alpha: 0.65),
                    border: colors.outlineVariant.withValues(alpha: 0.55),
                  ),
                  if (summary.expiredCount > 0)
                    _SubscriptionTagPill(
                      icon: Icons.event_busy_rounded,
                      label: appLocalizations
                          .nodeOverviewExpiredCountBadge(summary.expiredCount),
                      foreground: colors.error,
                      background: colors.error.withValues(alpha: 0.12),
                      border: colors.error.withValues(alpha: 0.32),
                    ),
                  if (summary.expiringSoonCount > 0)
                    _SubscriptionTagPill(
                      icon: Icons.schedule_rounded,
                      label: appLocalizations.nodeOverviewExpiringSoonCountBadge(
                        summary.expiringSoonCount,
                      ),
                      foreground: Colors.orange,
                      background: Colors.orange.withValues(alpha: 0.12),
                      border: Colors.orange.withValues(alpha: 0.34),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    activeProfile != null
                        ? Icons.check_circle_outline_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 13.5,
                    color: activeProfile != null
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      activeProfile != null
                          ? appLocalizations.nodeOverviewCurrentActiveProfile(
                              activeProfile.label ?? activeProfile.id,
                            )
                          : appLocalizations.nodeOverviewNoActiveProfile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.90),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  height: 1,
                  thickness: 0.6,
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              if (summary.usableProfileCount == 0)
                const Text('—')
              else ...[
                Text(
                  summary.hasPendingProfiles
                      ? '${appLocalizations.nodeOverviewAllHealthCounts(summary.availableNodes, summary.testedNodes, summary.totalNodes)}+'
                      : appLocalizations.nodeOverviewAllHealthCounts(
                          summary.availableNodes,
                          summary.testedNodes,
                          summary.totalNodes,
                        ),
                ),
                Text(
                  summary.medianMs != null && summary.bestMs != null
                      ? appLocalizations.nodeOverviewGlobalMedianAndBest(
                          '${summary.medianMs} ms',
                          '${summary.bestMs} ms',
                        )
                      : appLocalizations.nodeOverviewGlobalMedian('—'),
                ),
                if (summary.totalNodes > 0) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        _DelayBandLegendItem(
                          color: kLatencyFastColor,
                          label: appLocalizations
                              .nodeOverviewBandFast(summary.fastCount),
                        ),
                        _DelayBandLegendItem(
                          color: kLatencyMediumColor,
                          label: appLocalizations
                              .nodeOverviewBandSlow(summary.slowCount),
                        ),
                        _DelayBandLegendItem(
                          color: kLatencyErrorColor,
                          label: appLocalizations
                              .nodeOverviewBandFailed(summary.failedCount),
                        ),
                        _DelayBandLegendItem(
                          color:
                              colors.onSurfaceVariant.withValues(alpha: 0.55),
                          label: appLocalizations
                              .nodeOverviewBandUntested(summary.untestedCount),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      label: appLocalizations.nodeOverviewAllHealthCounts(
                        summary.availableNodes,
                        summary.testedNodes,
                        summary.totalNodes,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Row(
                          children: [
                            if (summary.fastCount > 0)
                              Expanded(
                                flex: summary.fastCount,
                                child: Container(
                                  height: 5,
                                  color: kLatencyFastColor,
                                ),
                              ),
                            if (summary.slowCount > 0)
                              Expanded(
                                flex: summary.slowCount,
                                child: Container(
                                  height: 5,
                                  color: kLatencyMediumColor,
                                ),
                              ),
                            if (summary.failedCount > 0)
                              Expanded(
                                flex: summary.failedCount,
                                child: Container(
                                  height: 5,
                                  color: kLatencyErrorColor,
                                ),
                              ),
                            if (summary.untestedCount > 0)
                              Expanded(
                                flex: summary.untestedCount,
                                child: Container(
                                  height: 5,
                                  color: colors.surfaceContainerHighest,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DelayBandLegendItem extends StatelessWidget {
  const _DelayBandLegendItem({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3.5),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            height: 1.25,
          ),
        ),
      ],
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
      this.showDelete = false,
      this.deleting = false,
      this.onDelete,
      required this.onVisible,
      required this.onSelect});
  final Profile profile;
  final bool selected;
  final bool active;
  final bool liveActive;
  final DateTime now;
  final VoidCallback? onSync;
  final bool showDelete;
  final bool deleting;
  final VoidCallback? onDelete;
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
                      showDeleteExpired: showDelete,
                      deletingExpired: deleting,
                      onDeleteExpired: onDelete,
                      deleteButtonKey: ValueKey('overview-delete-${profile.id}'),
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
                      showExpiredNotice: metadata == null,
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
    this.idleLabel,
    this.tooltipIdleLabel,
  });

  final bool updating;
  final VoidCallback? onPressed;
  final bool selectedCard;
  final double maxWidth;
  final String? idleLabel;
  final String? tooltipIdleLabel;

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
        : (widget.idleLabel ?? appLocalizations.nodeOverviewUpdateSubscription);
    final tooltipMessage = updating
        ? appLocalizations.nodeOverviewUpdating
        : (widget.tooltipIdleLabel ??
            widget.idleLabel ??
            appLocalizations.nodeOverviewUpdateSubscription);
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

class _ProfileDeleteButton extends StatefulWidget {
  const _ProfileDeleteButton({
    super.key,
    required this.deleting,
    required this.onPressed,
  });

  final bool deleting;
  final VoidCallback? onPressed;

  @override
  State<_ProfileDeleteButton> createState() => _ProfileDeleteButtonState();
}

class _ProfileDeleteButtonState extends State<_ProfileDeleteButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final deleting = widget.deleting;
    final enabled = !deleting && widget.onPressed != null;
    final label = appLocalizations.delete;
    final borderRadius = BorderRadius.circular(999);

    final Color backgroundColor;
    final Color borderColor;
    final foregroundColor = enabled || deleting
        ? colors.error
        : colors.error.withValues(alpha: 0.45);

    if (!enabled) {
      backgroundColor = colors.error.withValues(alpha: isDark ? 0.10 : 0.06);
      borderColor = colors.error.withValues(alpha: 0.28);
    } else if (_hovered || _focused) {
      backgroundColor = colors.error.withValues(alpha: isDark ? 0.26 : 0.16);
      borderColor = colors.error.withValues(alpha: 0.78);
    } else {
      backgroundColor = colors.error.withValues(alpha: isDark ? 0.16 : 0.10);
      borderColor = colors.error.withValues(alpha: 0.45);
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
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
              constraints: const BoxConstraints(maxWidth: 112),
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
                    splashColor: colors.error.withValues(alpha: 0.14),
                    highlightColor: colors.error.withValues(alpha: 0.08),
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
                          if (deleting)
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
                              Icons.delete_outline_rounded,
                              size: 12.5,
                              color: foregroundColor,
                            ),
                          const SizedBox(width: 3),
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

class _ProfileSubscriptionSummary extends StatelessWidget {
  const _ProfileSubscriptionSummary({
    required this.data,
    required this.now,
    this.trailingAction,
    this.showDeleteExpired = false,
    this.deletingExpired = false,
    this.onDeleteExpired,
    this.deleteButtonKey,
  });

  final _ProfileMetadataViewData data;
  final DateTime now;
  final Widget? trailingAction;
  final bool showDeleteExpired;
  final bool deletingExpired;
  final VoidCallback? onDeleteExpired;
  final Key? deleteButtonKey;

  Widget _buildExpiredInfoColumn({
    required ColorScheme colors,
    required TextStyle? metaStyle,
    required String expireText,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_busy_rounded,
                size: 13.5,
                color: colors.error,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  appLocalizations.nodeOverviewExpired,
                  style: metaStyle?.copyWith(
                    color: colors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1.5),
          Text(
            expireText,
            style: metaStyle?.copyWith(
              fontSize: 11,
              color: colors.error.withValues(alpha: 0.88),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );

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
                ? kLatencyMediumColor
                : colors.primary;

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
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: usedRatio,
                minHeight: 5,
                backgroundColor: colors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
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
      final expiryState = _resolveSubscriptionExpiryState(sub.expire, now);
      if (expiryState == null) {
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
      } else if (expiryState.isExpired) {
        final expireText =
            '${appLocalizations.nodeOverviewExpireAt(expiryState.dateStr)} · ${expiryState.countdownText}';
        final isDark = theme.brightness == Brightness.dark;
        final deleteAction =
            (showDeleteExpired || onDeleteExpired != null)
                ? _ProfileDeleteButton(
                    key: deleteButtonKey,
                    deleting: deletingExpired,
                    onPressed: onDeleteExpired,
                  )
                : null;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final stackActionBelow = deleteAction != null && textScale > 1.5;
        children.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: colors.error.withValues(alpha: 0.32),
                width: 0.8,
              ),
            ),
            child: stackActionBelow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildExpiredInfoColumn(
                        colors: colors,
                        metaStyle: metaStyle,
                        expireText: expireText,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: deleteAction,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _buildExpiredInfoColumn(
                          colors: colors,
                          metaStyle: metaStyle,
                          expireText: expireText,
                        ),
                      ),
                      if (deleteAction != null) ...[
                        const SizedBox(width: 8),
                        deleteAction,
                      ],
                    ],
                  ),
          ),
        );
      } else {
        final expireText =
            '${appLocalizations.nodeOverviewExpireAt(expiryState.dateStr)} · ${expiryState.countdownText}';
        final expireColor = expiryState.isExpiringSoon
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
                    fontWeight: expiryState.isExpiringSoon
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
      this.showDeleteSubscription = false,
      this.deletingSubscription = false,
      this.onDeleteSubscription,
      this.deleteButtonKey,
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
  final bool showDeleteSubscription;
  final bool deletingSubscription;
  final VoidCallback? onDeleteSubscription;
  final Key? deleteButtonKey;
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
    final testerBusy =
        ref.watch(nodeCatalogTesterProvider.select((t) => t.busy));
    final pendingIdentities = ref.watch(
      nodeCatalogTesterProvider.select(
        (t) => t.pendingIdentitySnapshot(profile.id),
      ),
    );
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                  surfaceColor: DayNightSkyScope.isActiveOf(context)
                      ? colors.surface.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.64
                              : 0.72,
                        )
                      : colors.surface,
                  hairlineColor: freedomNetHairlineColor(colors),
                  titleStyle: theme.textTheme.titleSmall,
                  activeTextStyle: theme.textTheme.labelSmall,
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
                    showDeleteExpired: widget.showDeleteSubscription,
                    deletingExpired: widget.deletingSubscription,
                    onDeleteExpired: widget.onDeleteSubscription,
                    deleteButtonKey: widget.deleteButtonKey ??
                        ValueKey('overview-delete-${profile.id}'),
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
                  child: ExcludeSemantics(child: LinearProgressIndicator()))),
        if (metadata == null && _expired(profile, widget.now))
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
                        pending: pendingIdentities.contains(node.identityKey),
                        testKey: ValueKey(
                            'overview-test-${profile.id}-${node.identityKey}'),
                        onTest: testerBusy ||
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
    required this.surfaceColor,
    required this.hairlineColor,
    required this.titleStyle,
    required this.activeTextStyle,
    this.extent = 44,
  });
  final Profile profile;
  final bool active;
  final Color surfaceColor;
  final Color hairlineColor;
  final TextStyle? titleStyle;
  final TextStyle? activeTextStyle;
  final double extent;
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(
          animationDuration: Duration.zero,
          color: surfaceColor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: hairlineColor),
              ),
            ),
            child: SizedBox.expand(
                child: Padding(
              key: ValueKey('overview-header-${profile.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                    child: Text(profile.label ?? profile.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle)),
                if (active) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 0,
                    child: Text(
                      appLocalizations.nodeOverviewActive,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: activeTextStyle,
                    ),
                  ),
                ],
              ]),
            )),
          ));
  @override
  bool shouldRebuild(covariant _PinnedProfileHeader oldDelegate) =>
      profile != oldDelegate.profile ||
      active != oldDelegate.active ||
      extent != oldDelegate.extent ||
      surfaceColor != oldDelegate.surfaceColor ||
      hairlineColor != oldDelegate.hairlineColor ||
      titleStyle != oldDelegate.titleStyle ||
      activeTextStyle != oldDelegate.activeTextStyle;
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
    !isManagedSmartGroupName(proxy.name) &&
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
  bool smartInUse = false,
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
          : smartInUse
              ? colorScheme.primary.withValues(alpha: 0.16)
              : colorScheme.surfaceContainerLow,
      foregroundColor: colorScheme.primary,
      disabledBackgroundColor: inUse ? colorScheme.secondaryContainer : null,
      disabledForegroundColor: inUse ? colorScheme.onSecondaryContainer : null,
    ),
    child: Text(
      inUse
          ? appLocalizations.nodeOverviewInUse
          : smartInUse
              ? appLocalizations.nodeOverviewSmartInUse
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
        final minSingleRowWidth =
            (actions.length <= 1 ? 520.0 : 680.0) * textScale;
        final singleRow =
            actions.isEmpty || constraints.maxWidth >= minSingleRowWidth;
        if (singleRow) {
          return Row(
            children: [
              Expanded(child: Text(name)),
              const SizedBox(width: 8),
              if (actions.isEmpty) Flexible(child: status) else status,
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
  bool smartInUse,
});

Map<String, _ActiveDisplay> _activeDisplays(
    WidgetRef ref, String profileId, ProfileCatalog? fileCatalog) {
  final runtime = ref.watch(activeNodeCatalogProvider);
  final allGroups = ref.watch(groupsProvider);
  final profileObj = ref.watch(
    profilesProvider.select((list) => list.getProfile(profileId)),
  );
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
        final isSmartGroupSelected = isManagedSmartGroupName(selectedProxyName) ||
            (profileObj != null &&
                selectGroup != null &&
                resolveProfileSelectionMode(profileObj) ==
                    NodeSelectionMode.smart &&
                isManagedSmartGroupName(profileObj.selectedMap[selectGroup]));
        final smartResolvedLeaf = (selectGroup != null && isSmartGroupSelected)
            ? resolveSmartActiveLeafName(
                selectorGroupName: selectGroup,
                allGroups: allGroups,
                selectedMap:
                    profileObj?.selectedMap ?? const <String, String>{},
              )
            : null;
        return (
          proxy: entry.proxy,
          testUrl: entry.testUrl,
          node: node,
          history: history,
          delay: _activeDelay(live, history),
          fileSource: fileSource,
          independent: independent,
          selectGroup: selectGroup,
          inUse: selectGroup != null &&
              !isSmartGroupSelected &&
              selectedProxyName == entry.proxy.name,
          smartInUse:
              smartResolvedLeaf != null && smartResolvedLeaf == entry.proxy.name,
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
    final testerBusy =
        ref.watch(nodeCatalogTesterProvider.select((t) => t.busy));
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
                  onTest: testerBusy || entry.delay == 0 || profile.isUpdating
                      ? null
                      : () => onTest(entry.proxy, entry.testUrl),
                  useKey: ValueKey(
                      'overview-use-${profile.id}-${entry.proxy.name}'),
                  inUse: entry.inUse,
                  smartInUse: entry.smartInUse,
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

bool _isNoviceAppShell(BuildContext context, bool expertExpanded) =>
    !expertExpanded &&
    (context.commonScaffoldState?.hasNavigationBar ?? false);

Widget _buildLatencyStatusPill(
  BuildContext context, {
  required String label,
  required Color? color,
  required bool hasMeasurement,
  bool isStale = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final effectiveTextColor = (!hasMeasurement || color == null)
      ? color
      : isStale
          ? color.withValues(alpha: isDark ? 0.82 : 0.80)
          : color;
  final text = Text(
    label,
    style: TextStyle(
      color: effectiveTextColor,
      fontSize: 12,
      fontWeight: hasMeasurement ? FontWeight.w600 : FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  if (!hasMeasurement || color == null) {
    return text;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(
        alpha: isStale ? (isDark ? 0.06 : 0.04) : (isDark ? 0.14 : 0.10),
      ),
      borderRadius: BorderRadius.circular(6),
      border: isStale
          ? Border.all(
              color: color.withValues(alpha: isDark ? 0.28 : 0.24),
              width: 1,
            )
          : null,
    ),
    child: text,
  );
}

class _ActiveNodeRow extends ConsumerWidget {
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
      this.smartInUse = false,
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
  final bool smartInUse;
  final VoidCallback? onUse;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inNoviceAppShell = _isNoviceAppShell(
      context,
      ref.watch(expertNavigationExpandedProvider),
    );
    final color = utils.getDelayColor(delay);
    final stale = delay != null &&
        delay != 0 &&
        history != null &&
        history!.delayMs == delay &&
        history!.isStale(now);
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
    final hasCountry = countryEmoji != null && countryName != null;
    final showMetaRow = hasCountry || !inNoviceAppShell;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildNodeHeaderLayout(
                context,
                name: proxy.name,
                status: delay == 0
                    ? const ExcludeSemantics(
                        child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _buildLatencyStatusPill(
                        context,
                        label: delay == null
                            ? appLocalizations.nodeOverviewUntested
                            : delay! > 0
                                ? '$delay ms'
                                : appLocalizations.nodeOverviewTestFailed,
                        color: color,
                        hasMeasurement: delay != null,
                        isStale: stale,
                      ),
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
                    smartInUse: smartInUse,
                    onPressed: onUse,
                  ),
                ],
              ),
              if (showMetaRow) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasCountry)
                      _CountryBadge(emoji: countryEmoji!, name: countryName!),
                    if (!inNoviceAppShell)
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
              if (!inNoviceAppShell) ...[
                const SizedBox(height: 4),
                Text(
                    history == null
                        ? appLocalizations.nodeOverviewLive
                        : _testedAt(history!, now),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ])));
  }
}

class _CountryLabelText extends StatelessWidget {
  const _CountryLabelText({
    required this.emoji,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String emoji;
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

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
        maxLines: maxLines,
        overflow: overflow,
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

class _InactiveNodeRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final inNoviceAppShell = _isNoviceAppShell(
      context,
      ref.watch(expertNavigationExpandedProvider),
    );
    final invalid = node.unsupported == CatalogUnsupportedReason.parseFailed;
    final record = invalid ? null : health;
    final stale = record?.isStale(now) ?? false;
    final color = utils.getDelayColor(record?.delayMs);
    final hasCountry = countryEmoji != null && countryName != null;
    final showMetaRow = hasCountry || !inNoviceAppShell;
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
                          ? const ExcludeSemantics(
                              child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : _buildLatencyStatusPill(
                              context,
                              label: record == null
                                  ? appLocalizations.nodeOverviewUntested
                                  : record.delayMs > 0
                                      ? '${record.delayMs} ms'
                                      : appLocalizations.nodeOverviewTestFailed,
                              color: color,
                              hasMeasurement: record != null,
                              isStale: stale,
                            ),
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
                if (showMetaRow) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasCountry)
                        _CountryBadge(emoji: countryEmoji!, name: countryName!),
                      if (!inNoviceAppShell)
                        Text(
                          [
                            _catalogProtocolLabel(node),
                            if (_providerSourceLabel(node) case final src?) src,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
                if (node.unsupported != CatalogUnsupportedReason.none)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_unsupported(node.unsupported),
                          style: Theme.of(context).textTheme.bodySmall)),
                if (record != null && !inNoviceAppShell)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_testedAt(record, now),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: stale
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : color,
                              ))),
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
      this.showExpiredNotice = true,
      required this.now});
  final Profile profile;
  final ProfileCatalog? catalog;
  final bool liveActive;
  final bool showExpiredNotice;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(nodeHealthEntriesProvider(profile.id));
    final active = liveActive;
    final status = <Widget>[
      if (showExpiredNotice && _expired(profile, now))
        Text(appLocalizations.nodeOverviewExpired),
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
