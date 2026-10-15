import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/node_runtime_catalog.dart';
import 'package:flclashx/common/path.dart';
import 'package:flclashx/common/print.dart';
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
        ));

final nodeCatalogServiceProvider = Provider<NodeCatalogService>((ref) {
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
