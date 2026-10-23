import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/node_runtime_catalog.dart';
import 'package:flclashx/common/path.dart';
import 'package:flclashx/common/print.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'config.dart';
import 'state.dart';

enum ProxiesScope { current, all }

final nodeOverviewEnabledProvider =
    Provider<bool>((ref) => nodeOverviewEnabled);
final proxiesScopeProvider =
    StateProvider<ProxiesScope>((ref) => ProxiesScope.current);
final cachedProfileCatalogsProvider =
    StateProvider<Map<String, ProfileCatalog>>((ref) => const {});
final nodeOverviewTestUrlProvider =
    Provider<String>((ref) => ref.watch(getRealTestUrlProvider(null)));

bool _isRuntimeSnapshotLiveForProfile({
  required String? verifiedRuntimeProfileId,
  required String profileId,
  required List<Group> groups,
  required int version,
}) {
  if (groups.isEmpty) return false;
  if (verifiedRuntimeProfileId != null &&
      verifiedRuntimeProfileId != profileId) {
    return false;
  }
  if (!globalState.matchesGroupsSnapshot(groups, version)) {
    return false;
  }
  final snapshotProfileId = globalState.groupsSnapshotProfileId;
  if (snapshotProfileId != null) {
    return snapshotProfileId == profileId;
  }
  return globalState.lastRuntimeProfileId == null;
}

String? _lookupEndpointKeyForProxy({
  required String profileId,
  required String proxyName,
  required ProfileCatalog? verifiedCatalog,
  required Map<String, ProfileCatalog> cachedCatalogs,
}) {
  final catalog =
      (verifiedCatalog?.profileId == profileId ? verifiedCatalog : null) ??
          cachedCatalogs[profileId];
  if (catalog == null) return null;
  for (final node in catalog.nodes) {
    if (node.name == proxyName && node.endpointKey.isNotEmpty) {
      return node.endpointKey;
    }
  }
  return null;
}

({String? leafName, bool ambiguous}) _resolveGroupToLeafProxy({
  required String entryName,
  required List<Group> allGroups,
  required Map<String, String> selectedMap,
  int depth = 0,
}) {
  if (depth > 16 || entryName.isEmpty) {
    return (leafName: null, ambiguous: true);
  }
  if (entryName == 'DIRECT' ||
      entryName == 'REJECT' ||
      entryName == 'REJECT-DROP') {
    return (leafName: entryName, ambiguous: false);
  }
  final group = allGroups.getGroup(entryName);
  if (group == null) {
    return (leafName: entryName, ambiguous: false);
  }
  if (group.type == GroupType.LoadBalance) {
    return (leafName: null, ambiguous: true);
  }
  final next = group.getCurrentSelectedName(selectedMap[group.name] ?? '');
  if (next.isEmpty) {
    return (leafName: null, ambiguous: true);
  }
  return _resolveGroupToLeafProxy(
    entryName: next,
    allGroups: allGroups,
    selectedMap: selectedMap,
    depth: depth + 1,
  );
}

ConnectionEvidenceEvaluation evaluateObservedConnectionEvidence({
  required String? activeId,
  required bool runtimeLive,
  required Mode effectiveMode,
  required List<Group> allGroups,
  required FixedList<Connection> requests,
  required String? matchedHost,
  required DateTime? checkStartedAt,
  DateTime? checkCompletedAt,
  required ProfileCatalog? verifiedCatalog,
  required Map<String, ProfileCatalog> cachedCatalogs,
}) {
  final normalizedHost = matchedHost?.trim().toLowerCase();
  if (activeId == null ||
      activeId.isEmpty ||
      !runtimeLive ||
      effectiveMode == Mode.direct ||
      normalizedHost == null ||
      normalizedHost.isEmpty ||
      checkStartedAt == null) {
    return (status: ConnectionEvidenceStatus.missing, target: null);
  }
  final groupNames = <String>{
    for (final group in allGroups) group.name,
    GroupName.GLOBAL.name,
  };
  final minStart = checkStartedAt.subtract(const Duration(seconds: 2));
  final maxStart =
      (checkCompletedAt ?? checkStartedAt.add(const Duration(seconds: 15)))
          .add(const Duration(seconds: 1));
  final list = requests.list;
  String? matchedLeaf;
  for (var i = list.length - 1; i >= 0; i--) {
    final conn = list[i];
    if (conn.start.isBefore(minStart) || conn.start.isAfter(maxStart)) {
      continue;
    }
    final host = conn.metadata.host.toLowerCase();
    final sniffHost = conn.metadata.sniffHost.toLowerCase();
    if (host != normalizedHost && sniffHost != normalizedHost) continue;
    if (conn.chains.isEmpty) continue;
    final leaf = conn.chains.firstWhere(
      (hop) => hop.isNotEmpty && !groupNames.contains(hop),
      orElse: () => conn.chains.first,
    );
    if (leaf.isEmpty) continue;
    if (matchedLeaf != null && matchedLeaf != leaf) {
      // Multiple concurrent connections to the same probe host within the
      // check window routed through different outbound leaves: ambiguous.
      return (status: ConnectionEvidenceStatus.ambiguous, target: null);
    }
    matchedLeaf = leaf;
  }
  if (matchedLeaf == null) {
    return (status: ConnectionEvidenceStatus.missing, target: null);
  }
  if (matchedLeaf == 'DIRECT' ||
      matchedLeaf == 'REJECT' ||
      matchedLeaf == 'REJECT-DROP') {
    return (
      status: ConnectionEvidenceStatus.matched,
      target: (
        profileId: activeId,
        proxyName: matchedLeaf,
        endpointKey: null,
        isDirectOrReject: true,
      ),
    );
  }
  return (
    status: ConnectionEvidenceStatus.matched,
    target: (
      profileId: activeId,
      proxyName: matchedLeaf,
      endpointKey: _lookupEndpointKeyForProxy(
        profileId: activeId,
        proxyName: matchedLeaf,
        verifiedCatalog: verifiedCatalog,
        cachedCatalogs: cachedCatalogs,
      ),
      isDirectOrReject: false,
    ),
  );
}

ConnectionOutboundTarget? resolveObservedConnectionTarget({
  required String? activeId,
  required bool runtimeLive,
  required Mode effectiveMode,
  required List<Group> allGroups,
  required FixedList<Connection> requests,
  required String? matchedHost,
  required DateTime? checkStartedAt,
  DateTime? checkCompletedAt,
  required ProfileCatalog? verifiedCatalog,
  required Map<String, ProfileCatalog> cachedCatalogs,
}) {
  final evidence = evaluateObservedConnectionEvidence(
    activeId: activeId,
    runtimeLive: runtimeLive,
    effectiveMode: effectiveMode,
    allGroups: allGroups,
    requests: requests,
    matchedHost: matchedHost,
    checkStartedAt: checkStartedAt,
    checkCompletedAt: checkCompletedAt,
    verifiedCatalog: verifiedCatalog,
    cachedCatalogs: cachedCatalogs,
  );
  return evidence.status == ConnectionEvidenceStatus.matched
      ? evidence.target
      : null;
}

({String profileId, String proxyName, String? endpointKey})?
    _computeUnambiguousStaticTarget({
  required String? activeId,
  required bool runtimeLive,
  required Mode effectiveMode,
  required List<Group> allGroups,
  required List<Group> visibleGroups,
  required Map<String, String> selectedMap,
  required ProfileCatalog? verifiedCatalog,
  required Map<String, ProfileCatalog> cachedCatalogs,
}) {
  // Static group selection only proves the probe's outbound in `Mode.global`,
  // where Mihomo bypasses routing rules. In `Mode.rule`, rules may route the
  // IP-detection host through `DIRECT`, a hidden group, or another proxy leaf,
  // so exit calibration must rely exclusively on observed connection telemetry.
  if (activeId == null ||
      activeId.isEmpty ||
      !runtimeLive ||
      effectiveMode != Mode.global ||
      allGroups.isEmpty) {
    return null;
  }
  final globalGroup = allGroups.getGroup(GroupName.GLOBAL.name) ??
      (visibleGroups.length == 1 ? visibleGroups.single : null);
  if (globalGroup == null) return null;
  final resolved = _resolveGroupToLeafProxy(
    entryName: globalGroup.name,
    allGroups: allGroups,
    selectedMap: selectedMap,
  );
  if (resolved.ambiguous ||
      resolved.leafName == null ||
      resolved.leafName == 'DIRECT' ||
      resolved.leafName == 'REJECT' ||
      resolved.leafName == 'REJECT-DROP') {
    return null;
  }
  final unambiguousLeaf = resolved.leafName!;
  return (
    profileId: activeId,
    proxyName: unambiguousLeaf,
    endpointKey: _lookupEndpointKeyForProxy(
      profileId: activeId,
      proxyName: unambiguousLeaf,
      verifiedCatalog: verifiedCatalog,
      cachedCatalogs: cachedCatalogs,
    ),
  );
}

void notifyProxyCardSelection(
  WidgetRef ref, {
  required String groupName,
  required String nextProxyName,
}) {
  detectionState.notifyRoutingChanged();
  if (!globalState.isAppStateInitialized) {
    ref.read(nodeCountryResolverProvider).notifyManualProxySelection(
          profileId: null,
          proxyName: '',
        );
    return;
  }
  final isProxyRunning = ref.read(runTimeProvider) != null;
  final activeId = ref.read(currentProfileIdProvider);
  final profiles = ref.read(profilesProvider);
  final allGroups = ref.read(groupsProvider);
  final visibleGroups = ref.read(currentGroupsStateProvider).value;
  final version = ref.read(versionProvider);
  final mode = ref.read(patchClashConfigProvider).mode;
  final cachedCatalogs = ref.read(cachedProfileCatalogsProvider);
  final currentProfile = profiles.getProfile(activeId);
  final effectiveSelectedMap = <String, String>{
    ...?currentProfile?.selectedMap,
    groupName: nextProxyName,
  };
  final runtimeLive = isProxyRunning &&
      activeId != null &&
      _isRuntimeSnapshotLiveForProfile(
        verifiedRuntimeProfileId: globalState.lastRuntimeProfileId,
        profileId: activeId,
        groups: allGroups,
        version: version,
      );
  final target = _computeUnambiguousStaticTarget(
    activeId: activeId,
    runtimeLive: runtimeLive,
    effectiveMode: mode,
    allGroups: allGroups,
    visibleGroups: visibleGroups,
    selectedMap: effectiveSelectedMap,
    verifiedCatalog: null,
    cachedCatalogs: cachedCatalogs,
  );
  ref.read(nodeCountryResolverProvider).notifyManualProxySelection(
        profileId: target?.profileId,
        proxyName: target?.proxyName ?? '',
        endpointKey: target?.endpointKey,
        unambiguous: target != null,
        isGlobalStaticTarget: mode == Mode.global && target != null,
      );
}

final ChangeNotifierProvider<NodeCountryResolver> nodeCountryResolverProvider =
    ChangeNotifierProvider<NodeCountryResolver>((ref) {
  ConnectionEvidenceEvaluation evaluateCurrentConnection() {
    if (!globalState.isAppStateInitialized) {
      return (status: ConnectionEvidenceStatus.missing, target: null);
    }
    if (ref.read(runTimeProvider) == null) {
      return (status: ConnectionEvidenceStatus.missing, target: null);
    }
    final activeId = ref.read(currentProfileIdProvider);
    final allGroups = ref.read(groupsProvider);
    final version = ref.read(versionProvider);
    final runtimeLive = activeId != null &&
        _isRuntimeSnapshotLiveForProfile(
          verifiedRuntimeProfileId: globalState.lastRuntimeProfileId,
          profileId: activeId,
          groups: allGroups,
          version: version,
        );
    return evaluateObservedConnectionEvidence(
      activeId: activeId,
      runtimeLive: runtimeLive,
      effectiveMode: ref.read(patchClashConfigProvider).mode,
      allGroups: allGroups,
      requests: ref.read(requestsProvider),
      matchedHost: detectionState.lastMatchedHost,
      checkStartedAt: detectionState.lastCheckStartedAt,
      checkCompletedAt: detectionState.lastCheckCompletedAt,
      verifiedCatalog: null,
      cachedCatalogs: ref.read(cachedProfileCatalogsProvider),
    );
  }

  late final NodeCountryResolver resolver;
  resolver = NodeCountryResolver(
    detectionListenable: detectionState.state,
    readDetectionMeta: () => (
      routingEpoch: detectionState.routingEpoch,
      completedGeneration: detectionState.lastCompletedGeneration,
      completedRoutingEpoch: detectionState.lastCompletedRoutingEpoch,
    ),
    readCheckCompletedAt: () => detectionState.lastCheckCompletedAt,
    isDetectionProxyEligible: () {
      if (!globalState.isAppStateInitialized) return false;
      if (ref.read(runTimeProvider) == null) return false;
      if (ref.read(patchClashConfigProvider).mode == Mode.direct) {
        return false;
      }
      final checkEligible = detectionState.lastCheckProxyEligible;
      if (checkEligible == false) return false;
      return true;
    },
    evaluateConnectionEvidence: evaluateCurrentConnection,
    resolveConnectionTarget: () {
      final evidence = evaluateCurrentConnection();
      return evidence.status == ConnectionEvidenceStatus.matched
          ? evidence.target
          : null;
    },
  );

  void syncCentralTarget({required bool notify}) {
    if (!globalState.isAppStateInitialized) {
      resolver.syncActiveNode(
        profileId: null,
        nodeName: null,
        isLiveActive: false,
        notify: notify,
      );
      return;
    }
    final isProxyRunning = ref.read(runTimeProvider) != null;
    final activeId = ref.read(currentProfileIdProvider);
    final profiles = ref.read(profilesProvider);
    final allGroups = ref.read(groupsProvider);
    final visibleGroups = ref.read(currentGroupsStateProvider).value;
    final version = ref.read(versionProvider);
    final mode = ref.read(patchClashConfigProvider).mode;
    final cachedCatalogs = ref.read(cachedProfileCatalogsProvider);
    final currentProfile = profiles.getProfile(activeId);
    final runtimeLive = isProxyRunning &&
        activeId != null &&
        !(currentProfile?.isUpdating ?? false) &&
        _isRuntimeSnapshotLiveForProfile(
          verifiedRuntimeProfileId: globalState.lastRuntimeProfileId,
          profileId: activeId,
          groups: allGroups,
          version: version,
        );
    final target = _computeUnambiguousStaticTarget(
      activeId: activeId,
      runtimeLive: runtimeLive,
      effectiveMode: mode,
      allGroups: allGroups,
      visibleGroups: visibleGroups,
      selectedMap: currentProfile?.selectedMap ?? const <String, String>{},
      verifiedCatalog: null,
      cachedCatalogs: cachedCatalogs,
    );
    resolver.syncActiveNode(
      profileId: target?.profileId,
      nodeName: target?.proxyName,
      endpointKey: target?.endpointKey,
      isLiveActive: target != null,
      isGlobalStaticTarget: mode == Mode.global && target != null,
      notify: notify,
    );
  }

  // Initial seed runs with notify: false so watching nodeCountryResolverProvider
  // inside build() never triggers notifyListeners() during widget build.
  syncCentralTarget(notify: false);
  resolver.seedInitialDetection(notify: false);

  ref
    ..listen(currentProfileIdProvider, (_, __) => syncCentralTarget(notify: true))
    ..listen(profilesProvider, (_, __) => syncCentralTarget(notify: true))
    ..listen<Mode>(
      patchClashConfigProvider.select((s) => s.mode),
      (previous, next) {
        if (previous == next) return;
        detectionState.notifyRoutingChanged();
        if (next == Mode.direct) {
          resolver.onProxyRunningChanged(isRunning: false);
        }
        syncCentralTarget(notify: true);
      },
    )
    ..listen(
        cachedProfileCatalogsProvider, (_, __) => syncCentralTarget(notify: true));
  if (globalState.isAppStateInitialized) {
    ref
      ..listen<bool>(
        runTimeProvider.select((state) => state != null),
        (previous, isRunning) {
          if (previous == isRunning) return;
          detectionState.notifyRoutingChanged();
          resolver.onProxyRunningChanged(isRunning: isRunning);
          syncCentralTarget(notify: true);
        },
      )
      ..listen(groupsProvider, (_, __) => syncCentralTarget(notify: true))
      ..listen(
          currentGroupsStateProvider, (_, __) => syncCentralTarget(notify: true))
      ..listen(
          requestsProvider, (_, __) => resolver.onConnectionsUpdated(notify: true));
  }

  return resolver;
});

// Read-only IO seam, shared with the existing effective configuration screen.
// Keep Core access inside the callback so disabled/unused UI cannot start it.
final nodeRuntimeReaderProvider =
    Provider<Future<Map<String, dynamic>> Function()>((ref) => () async {
          final interface = ClashCore.existingInterface;
          if (interface == null) {
            throw const CatalogBuildException('runtimeUnavailable');
          }
          final result = await interface.getConfig('fcx://runtime');
          if (!result.isSuccess || result.data is! Map) {
            throw const CatalogBuildException('runtimeUnavailable');
          }
          return Map<String, dynamic>.from(result.data as Map);
        });

// Keep the exact read future separate from AsyncValue: a request must complete
// with its original read even when Riverpod replaces the displayed future.
final Provider<NodeRuntimeRead> nodeRuntimeReadProvider =
    Provider<NodeRuntimeRead>((ref) {
  if (!ref.watch(nodeOverviewEnabledProvider)) {
    return NodeRuntimeRead((_) => Future.value());
  }
  final id = ref.watch(currentProfileIdProvider);
  final profile =
      ref.watch(profilesProvider.select((profiles) => profiles.getProfile(id)));
  ref
    ..watch(scriptStateProvider.select((state) => state.currentScript))
    ..watch(versionProvider);
  if (profile == null || profile.isUpdating) {
    return NodeRuntimeRead((_) => Future.value());
  }
  final service = ref.watch(nodeCatalogServiceProvider);
  final runtimeReader = ref.watch(nodeRuntimeReaderProvider);
  final read = NodeRuntimeRead((isCurrent) async {
    Map<String, dynamic>? latestRuntimeRaw;
    final verified = await readVerifiedNodeRuntime(
      profileId: profile.id,
      readRuntime: () async {
        final raw = await runtimeReader();
        latestRuntimeRaw = raw;
        return raw;
      },
      readProfile: () => service.load(profile),
      isCurrent: isCurrent,
    );
    if (verified != null && latestRuntimeRaw != null && isCurrent()) {
      ref
          .read(nodeCountryResolverProvider)
          .registerFromRawConfig(profile.id, latestRuntimeRaw!);
    }
    return verified;
  });
  // Revoke immediately, even before Riverpod schedules a rebuild/frame. This
  // also catches A -> B -> A and deletion/recreation with the same profile id.
  ref
    ..onDispose(read.invalidate)
    ..listen(currentProfileIdProvider, (_, __) => read.invalidate())
    ..listen(profilesProvider, (previous, next) {
      if (previous?.getProfile(id) != next.getProfile(id)) read.invalidate();
    })
    ..listen(scriptStateProvider, (previous, next) {
      if (previous?.currentScript != next.currentScript) read.invalidate();
    })
    ..listen(versionProvider, (_, __) => read.invalidate());
  return read;
});

final FutureProvider<ProfileCatalog?> verifiedNodeRuntimeProvider =
    FutureProvider<ProfileCatalog?>(
        (ref) => ref.watch(nodeRuntimeReadProvider).result);

/// Active source labels must come from the verified running configuration.
final Provider<ProfileCatalog?> activeNodeCatalogProvider =
    Provider<ProfileCatalog?>((ref) {
  final snapshot = ref.watch(verifiedNodeRuntimeProvider);
  return snapshot.isLoading ? null : snapshot.asData?.value;
});

void _logHealthFailure(String code) {
  commonPrint.log('node.health reason=$code');
}

final nodeHealthStoreProvider = ChangeNotifierProvider<NodeHealthStore>((ref) {
  final store = NodeHealthStore(
    fileProvider: () async =>
        File(p.join(await appPath.homeDirPath, 'node_health_v1.json')),
    onError: _logHealthFailure,
  );
  unawaited(
      store.load().catchError((Object _) => _logHealthFailure('loadFailed')));
  return store;
});

final nodeHealthRecorderProvider = Provider<NodeHealthRecorder>((ref) {
  // read avoids recreating the recorder (and deletion generations) on writes.
  final recorder = NodeHealthRecorder(store: ref.read(nodeHealthStoreProvider));
  ref.listen(profilesProvider, (previous, next) {
    for (final profile in previous ?? const <Profile>[]) {
      if (!next.any((entry) => entry.id == profile.id)) {
        unawaited(recorder
            .removeProfile(profile.id)
            .catchError((Object _) => _logHealthFailure('removeFailed')));
      }
    }
  });
  return recorder;
});

final nodeHealthEntriesProvider = Provider.autoDispose
    .family<Map<String, NodeHealthRecord>, String>((ref, profileId) {
  if (!ref.watch(nodeOverviewEnabledProvider)) return const {};
  final url = ref.watch(nodeOverviewTestUrlProvider);
  return ref
      .watch(nodeHealthStoreProvider)
      .readProfile(profileId, testUrl: url);
});

// Inject only the IO boundary in tests; provider invalidation stays real.
final nodeCatalogServiceFactoryProvider =
    Provider<NodeCatalogService Function()>((ref) => () => NodeCatalogService(
          readProfileConfig: (id) {
            if (ClashCore.existingInterface == null) {
              throw const CatalogBuildException('runtimeUnavailable');
            }
            return globalState.getProfileConfig(id);
          },
          evaluate: globalState.handleEvaluate,
          fileMetadata: (id) async {
            final stat = await File(await appPath.getProfilePath(id)).stat();
            return stat.type != FileSystemEntityType.file
                ? null
                : (
                    modifiedMicros: stat.modified.microsecondsSinceEpoch,
                    size: stat.size
                  );
          },
          scriptFingerprint: () {
            final script = ref.read(scriptStateProvider).currentScript;
            return '${script?.id ?? ''}|${sha256.convert(utf8.encode(script?.content ?? '')).toString().substring(0, 16)}';
          },
          prepareCatalog: (id, proxies, providers) async {
            final interface = ClashCore.existingInterface;
            if (interface == null) {
              throw const CatalogBuildException('runtimeUnavailable');
            }
            try {
              return await interface.catalogPrepare(id, proxies, providers);
            } on CatalogCoreException catch (error) {
              throw CatalogBuildException(error.reason);
            }
          },
          releaseCatalog: (id) async =>
              await ClashCore.existingInterface?.catalogRelease(id) ?? false,
          providerCachePath: (id, name, definition) async {
            final url = definition['url'];
            if (definition['type'] != 'http' || url is! String) return null;
            final uri = Uri.tryParse(url);
            if (uri == null ||
                !const {'http', 'https'}.contains(uri.scheme) ||
                uri.host.isEmpty) {
              return null;
            }
            // P1 only reports managed HTTP cache status. Arbitrary file paths
            // are outside this scope and must not block healthy inline nodes.
            return appPath.getProvidersFilePath(id, 'proxies', url);
          },
          providerResolver: CatalogProviderResolver(
            homeDirectory: () => appPath.homeDirPath,
            httpCachePath: (id, url) =>
                appPath.getProvidersFilePath(id, 'proxies', url),
            parse: (content, definition) async {
              final interface = ClashCore.existingInterface;
              if (interface == null)
                throw const CatalogBuildException('runtimeUnavailable');
              try {
                return await interface.catalogParseProvider(
                    content, definition);
              } on CatalogCoreException catch (error) {
                throw CatalogBuildException(error.reason);
              }
            },
          ),
          onError: (code) => commonPrint.log('node.catalog reason=$code'),
          onPrepared: (catalog) =>
              ref.invalidate(profileCatalogProvider(catalog.profileId)),
          onProxiesEvaluated: (profileId, proxies) => ref
              .read(nodeCountryResolverProvider)
              .registerProxyMaps(profileId, proxies),
        ));

final Provider<NodeCatalogService> nodeCatalogServiceProvider =
    Provider<NodeCatalogService>((ref) {
  final service = ref.read(nodeCatalogServiceFactoryProvider)();
  ref.listen(profilesProvider, (previous, next) {
    final cached =
        Map<String, ProfileCatalog>.of(ref.read(cachedProfileCatalogsProvider));
    for (final old in previous ?? const <Profile>[]) {
      final updated = next.getProfile(old.id);
      if (updated == null ||
          updated.url != old.url ||
          updated.lastUpdateDate != old.lastUpdateDate ||
          updated.isUpdating != old.isUpdating) {
        final updating = updated?.isUpdating ?? false;
        service.invalidate(old.id, keepCached: updating);
        if (!updating) {
          ref.read(nodeCountryResolverProvider).invalidateProfile(old.id);
        }
        if (updating && cached[old.id] != null) {
          cached[old.id] =
              cached[old.id]!.copyWith(status: ProfileCatalogStatus.updating);
        } else {
          cached.remove(old.id);
        }
      }
    }
    ref.read(cachedProfileCatalogsProvider.notifier).state = cached;
  });
  ref.listen(scriptStateProvider, (previous, next) {
    if (previous?.currentScript == next.currentScript) return;
    service.clear();
    ref.read(nodeCountryResolverProvider).clearProfiles();
    ref.read(cachedProfileCatalogsProvider.notifier).state = const {};
  });
  ref.onDispose(service.clear);
  return service;
});

// The overview and existing live entry points use the same request budget.
final nodeCatalogDelayCoordinatorProvider =
    Provider<DelayTestCoordinator>((ref) => delayTests);

final nodeCatalogTesterProvider =
    ChangeNotifierProvider.autoDispose<NodeCatalogTester>((ref) {
  final tester = NodeCatalogTester(
    service: ref.read(nodeCatalogServiceProvider),
    store: ref.read(nodeHealthStoreProvider),
    coordinator: ref.read(nodeCatalogDelayCoordinatorProvider),
    activity: uiActivity,
    isCurrentProfile: (profile) {
      final current = ref.read(profilesProvider).getProfile(profile.id);
      return current != null &&
          current.url == profile.url &&
          current.lastUpdateDate == profile.lastUpdateDate &&
          current.isUpdating == profile.isUpdating;
    },
    activeProfileId: () => ref.read(currentProfileIdProvider),
  );
  // These revoke binding ownership synchronously, before asynchronous reads or
  // writes can complete against a replaced/deleted profile or script.
  ref
    ..listen(profilesProvider, (previous, next) {
      for (final old in previous ?? const <Profile>[]) {
        final updated = next.getProfile(old.id);
        if (updated == null ||
            updated.url != old.url ||
            updated.lastUpdateDate != old.lastUpdateDate ||
            updated.isUpdating != old.isUpdating) {
          tester.profileChanged(old.id);
        }
      }
    })
    ..listen(currentProfileIdProvider, (_, __) => tester.disposeScope())
    ..listen(scriptStateProvider, (old, next) {
      if (old?.currentScript != next.currentScript) tester.disposeScope();
    });
  // versionProvider also advances on the 60-second group refresh. It is not
  // a Core/session identity, and must not cancel an explicit latency batch.
  // Real session loss is reported by the shared coordinator/Core transport.
  return tester;
});

final profileCatalogProvider = FutureProvider.autoDispose
    .family<ProfileCatalog, String>((ref, profileId) async {
  if (!ref.watch(nodeOverviewEnabledProvider)) {
    return ProfileCatalog(
        profileId: profileId,
        fingerprint: '',
        status: ProfileCatalogStatus.ready);
  }
  ref
    ..watch(profilesProvider.select((profiles) {
      final profile = profiles.getProfile(profileId);
      return (profile?.url, profile?.lastUpdateDate, profile?.isUpdating);
    }))
    ..watch(scriptStateProvider.select((state) => state.currentScript));
  final profile = ref.read(profilesProvider).getProfile(profileId);
  if (profile == null) {
    return ProfileCatalog(
        profileId: profileId,
        fingerprint: '',
        status: ProfileCatalogStatus.fileMissing);
  }
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final result = await ref.watch(nodeCatalogServiceProvider).load(profile);
  if (!disposed) {
    final cached =
        Map<String, ProfileCatalog>.of(ref.read(cachedProfileCatalogsProvider))
          ..remove(profileId)
          ..[profileId] = result;
    while (cached.length > NodeCatalogService.maxCachedCatalogs) {
      cached.remove(cached.keys.first);
    }
    ref.read(cachedProfileCatalogsProvider.notifier).state = cached;
  }
  return result;
});
