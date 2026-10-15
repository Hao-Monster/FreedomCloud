import 'dart:async';
import 'dart:collection';

import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';

typedef CatalogFileMetadata = ({int modifiedMicros, int size});

/// A reason code, deliberately excluding parser/source text and credentials.
class CatalogBuildException implements Exception {
  const CatalogBuildException(this.reason);

  final String reason;

  @override
  String toString() => 'CatalogBuildException($reason)';
}

const _nonLeafTypes = {
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
  'compatible',
};

/// Pure projection shared by file catalogs and the already-applied live config.
/// Provider definitions are not read: P0 only exposes their names as unknown.
ProfileCatalog buildProfileCatalog({
  required String profileId,
  required String fingerprint,
  required Map<String, dynamic> raw,
}) {
  final rawProxies = raw['proxies'];
  final rawGroups = raw['proxy-groups'];
  final rawProviders = raw['proxy-providers'];
  if ((rawProxies != null && rawProxies is! List) ||
      (rawGroups != null && rawGroups is! List) ||
      (rawProviders != null && rawProviders is! Map)) {
    throw const CatalogBuildException('parseFailed');
  }

  final selectGroups = <String, List<String>>{};
  for (final group in (rawGroups as List?) ?? const []) {
    if (group is! Map) {
      throw const CatalogBuildException('parseFailed');
    }
    if (group['type'] != 'select') continue;
    final name = group['name'];
    final proxies = group['proxies'];
    if (name is! String || (proxies != null && proxies is! List)) {
      throw const CatalogBuildException('parseFailed');
    }
    for (final proxyName in (proxies as List?) ?? const []) {
      if (proxyName is! String) {
        throw const CatalogBuildException('parseFailed');
      }
      final groups = selectGroups.putIfAbsent(proxyName, () => []);
      if (!groups.contains(name)) groups.add(name);
    }
  }

  final nodes = <CatalogNode>[];
  for (final proxy in (rawProxies as List?) ?? const []) {
    if (proxy is! Map) {
      throw const CatalogBuildException('parseFailed');
    }
    if (_nonLeafTypes.contains(proxy['type'])) continue;
    if (nodes.length >= NodeCatalogService.maxNodes) {
      throw const CatalogBuildException('tooManyNodes');
    }
    try {
      nodes.add(catalogNodeFromMap(
        profileId: profileId,
        proxy: proxy,
        selectGroups: selectGroups[proxy['name']] ?? const [],
      ));
    } on FormatException {
      throw const CatalogBuildException('parseFailed');
    }
  }

  final providers = <String, int>{};
  for (final name in (rawProviders as Map?)?.keys ?? const []) {
    if (name is! String) {
      throw const CatalogBuildException('parseFailed');
    }
    providers[name] = -1;
  }
  return ProfileCatalog(
    profileId: profileId,
    fingerprint: fingerprint,
    status: ProfileCatalogStatus.ready,
    nodes: List<CatalogNode>.unmodifiable(nodes),
    providerNodeCounts: Map<String, int>.unmodifiable(providers),
  );
}

/// Builds read-only summaries through the existing config/script pipeline.
/// Its dependencies deliberately offer no apply, download, or service actions.
class NodeCatalogService {
  NodeCatalogService({
    required this.readProfileConfig,
    required this.evaluate,
    required this.fileMetadata,
    required this.scriptFingerprint,
  });

  static const maxNodes = 2000;
  static const maxCachedCatalogs = 8;
  static const maxConcurrentBuilds = 2;

  final Future<Map<String, dynamic>> Function(String) readProfileConfig;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) evaluate;
  final Future<CatalogFileMetadata?> Function(String) fileMetadata;

  /// The current script id plus a hash of its content; never source text.
  final String Function() scriptFingerprint;

  final _cache = <String, ProfileCatalog>{};
  final _dirtyCache = <String>{};
  final _generations = <String, int>{};
  final _inFlight =
      <String, ({int generation, Future<ProfileCatalog> future})>{};
  final _waiting = Queue<Completer<void>>();
  var _activeBuilds = 0;

  ProfileCatalog? peek(String profileId) => _cache[profileId];

  void invalidate(String profileId, {bool keepCached = false}) {
    _generations[profileId] = (_generations[profileId] ?? 0) + 1;
    if (keepCached && _cache.containsKey(profileId)) {
      _dirtyCache.add(profileId);
    } else {
      _cache.remove(profileId);
      _dirtyCache.remove(profileId);
    }
  }

  void clear() {
    <String>{..._cache.keys, ..._inFlight.keys}.forEach(invalidate);
  }

  Future<ProfileCatalog> load(Profile profile) {
    final generation = _generations[profile.id] ?? 0;
    final pending = _inFlight[profile.id];
    if (pending != null && pending.generation == generation) {
      return pending.future;
    }
    late final Future<ProfileCatalog> future;
    future = _load(profile, generation).whenComplete(() {
      if (identical(_inFlight[profile.id]?.future, future)) {
        _inFlight.remove(profile.id);
      }
    });
    _inFlight[profile.id] = (generation: generation, future: future);
    return future;
  }

  Future<ProfileCatalog> _load(Profile profile, int generation) async {
    var fingerprint = '';
    try {
      final metadata = await fileMetadata(profile.id);
      if (metadata == null) {
        if (_isCurrent(profile.id, generation)) _cache.remove(profile.id);
        return ProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          status: ProfileCatalogStatus.fileMissing,
        );
      }
      final cached = _cache[profile.id];
      if (profile.isUpdating) {
        return (cached ??
                ProfileCatalog(
                  profileId: profile.id,
                  fingerprint: fingerprint,
                  status: ProfileCatalogStatus.updating,
                ))
            .copyWith(status: ProfileCatalogStatus.updating);
      }
      fingerprint =
          '${metadata.modifiedMicros}|${metadata.size}|${scriptFingerprint()}';
      if (cached?.fingerprint == fingerprint &&
          !_dirtyCache.contains(profile.id)) {
        _cache
          ..remove(profile.id)
          ..[profile.id] = cached!;
        return cached;
      }

      await _acquire();
      try {
        final raw = await readProfileConfig(profile.id);
        final evaluated = await evaluate(raw);
        final catalog = buildProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          raw: evaluated,
        );
        if (_isCurrent(profile.id, generation)) {
          _dirtyCache.remove(profile.id);
          _cache
            ..remove(profile.id)
            ..[profile.id] = catalog;
          if (_cache.length > maxCachedCatalogs) {
            final oldest = _cache.keys.first;
            _cache.remove(oldest);
            _dirtyCache.remove(oldest);
          }
        }
        return catalog;
      } finally {
        _release();
      }
    } catch (error) {
      if (_isCurrent(profile.id, generation)) _cache.remove(profile.id);
      return ProfileCatalog(
        profileId: profile.id,
        fingerprint: fingerprint,
        status: ProfileCatalogStatus.parseFailed,
        // Even a URL-stripped exception can contain servers or credentials.
        errorSummary:
            error is CatalogBuildException && error.reason == 'tooManyNodes'
                ? 'tooManyNodes'
                : 'parseFailed',
      );
    }
  }

  bool _isCurrent(String id, int generation) =>
      (_generations[id] ?? 0) == generation;

  Future<void> _acquire() async {
    if (_activeBuilds < maxConcurrentBuilds) {
      _activeBuilds++;
      return;
    }
    final ready = Completer<void>();
    _waiting.add(ready);
    await ready.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _activeBuilds--;
    } else {
      _waiting.removeFirst().complete();
    }
  }
}
