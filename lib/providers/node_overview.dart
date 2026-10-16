import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/node_runtime_catalog.dart';
import 'package:flclashx/common/path.dart';
import 'package:flclashx/common/print.dart';
import 'package:flclashx/common/ui_activity.dart';
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
final nodeRuntimeReadProvider = Provider<NodeRuntimeRead>((ref) {
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
  final read = NodeRuntimeRead((isCurrent) => readVerifiedNodeRuntime(
      profileId: profile.id,
      readRuntime: runtimeReader,
      readProfile: () => service.load(profile),
      isCurrent: isCurrent));
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

final verifiedNodeRuntimeProvider = FutureProvider<ProfileCatalog?>(
    (ref) => ref.watch(nodeRuntimeReadProvider).result);

/// Active source labels must come from the verified running configuration.
final activeNodeCatalogProvider = Provider<ProfileCatalog?>((ref) {
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
