import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/common/node_catalog_test_plan.dart';

export 'package:flclashx/common/node_catalog_test_plan.dart';

typedef CatalogFileMetadata = ({int modifiedMicros, int size});
typedef PrepareNodeCatalog = Future<String> Function(String catalogId,
    List<Map<String, dynamic>> proxies, List<Map<String, dynamic>> providers);

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
/// [isolatedTest] applies P1 admission limits only to the file/display catalog.
/// Runtime identity verification and recording keep their existing semantics.
ProfileCatalog buildProfileCatalog({
  required String profileId,
  required String fingerprint,
  required Map<String, dynamic> raw,
  bool isolatedTest = false,
  int maxNodes = NodeCatalogService.maxProjectionNodes,
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
  for (final (sourceIndex, proxy)
      in ((rawProxies as List?) ?? const []).indexed) {
    if (proxy is Map && _nonLeafTypes.contains(proxy['type'])) continue;
    if (nodes.length >= maxNodes) {
      throw const CatalogBuildException('tooManyNodes');
    }
    if (proxy is Map) {
      try {
        final node = catalogNodeFromMap(
          profileId: profileId,
          proxy: proxy,
          selectGroups: selectGroups[proxy['name']] ?? const [],
        );
        nodes.add(isolatedTest
            ? node.copyWith(
                unsupported: catalogIsolationUnsupportedReason(proxy))
            : node);
        continue;
      } on FormatException {
        // One unsupported shape must not hide the rest of this configuration.
        // Only approved display fields are allowed into its placeholder.
      }
    }
    final name = proxy is Map ? proxy['name'] : null;
    final type = proxy is Map ? proxy['type'] : null;
    nodes.add(unparsedCatalogNode(
      profileId: profileId,
      sourceIndex: sourceIndex,
      name: name is String ? name : null,
      type: type is String ? type : null,
    ));
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
    this.prepareCatalog,
    this.releaseCatalog,
    this.providerCachePath,
    this.providerResolver,
    this.onError,
    this.onPrepared,
  });

  static const maxNodes = 2000;
  static const maxProjectionNodes = 100000;
  static const maxCachedCatalogs = 8;
  static const maxConcurrentBuilds = 2;

  final Future<Map<String, dynamic>> Function(String) readProfileConfig;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) evaluate;
  final Future<CatalogFileMetadata?> Function(String) fileMetadata;

  /// The current script id plus a hash of its content; never source text.
  final String Function() scriptFingerprint;
  final PrepareNodeCatalog? prepareCatalog;
  final CatalogProviderResolver? providerResolver;
  final Future<bool> Function(String catalogId)? releaseCatalog;
  final Future<String?> Function(String profileId, String providerName,
      Map<String, dynamic> definition)? providerCachePath;
  final void Function(String reason)? onError;
  final void Function(ProfileCatalog catalog)? onPrepared;

  final _cache = <String, ProfileCatalog>{};
  final _dirtyCache = <String>{};
  final _generations = <String, int>{};
  final _inFlight =
      <String, ({int generation, Future<ProfileCatalog> future})>{};
  final _waiting = Queue<Completer<void>>();
  var _activeBuilds = 0;
  final _prepared = <String, ProfileCatalog>{};
  final _preparing = <String, Future<ProfileCatalog>>{};
  final _allPlanProfiles = <String, int>{};
  final _allCatalogOwners = <String, void Function()>{};

  ProfileCatalog? peek(String profileId) => _cache[profileId];

  void invalidate(String profileId, {bool keepCached = false}) {
    _generations[profileId] = (_generations[profileId] ?? 0) + 1;
    _preparing.remove(profileId);
    final prepared = _prepared.remove(profileId);
    if (prepared?.coreCatalogId case final String id) {
      unawaited(_releaseCore(id));
    }
    if (keepCached && _cache.containsKey(profileId)) {
      _dirtyCache.add(profileId);
    } else {
      _cache.remove(profileId);
      _dirtyCache.remove(profileId);
    }
  }

  void clear() {
    <String>{
      ..._cache.keys,
      ..._inFlight.keys,
      ..._preparing.keys,
      ..._prepared.keys,
      ..._allPlanProfiles.keys
    }.forEach(invalidate);
  }

  /// Preparation is explicit and short lived. Raw credentials exist only in
  /// this call, never in a provider, display model or persistent health cache.
  /// Each batch prepares anew because Core can evict an idle catalog itself.
  Future<ProfileCatalog> ensurePrepared(Profile profile) {
    if (profile.isUpdating) {
      return Future.error(const CatalogBuildException('configChanged'));
    }
    final pending = _preparing[profile.id];
    if (pending != null) return pending;
    final generation = _generations[profile.id] ?? 0;
    late final Future<ProfileCatalog> future;
    future = _prepare(profile, generation).whenComplete(() {
      if (identical(_preparing[profile.id], future)) {
        _preparing.remove(profile.id);
      }
    });
    _preparing[profile.id] = future;
    return future;
  }

  Future<void> releasePrepared(String catalogId) async {
    _allCatalogOwners.remove(catalogId)?.call();
    _prepared.removeWhere((_, value) => value.coreCatalogId == catalogId);
    await _releaseCore(catalogId);
  }

  /// Revoke only the caller's still-pending preparation. A later view can
  /// immediately start a fresh generation without sharing the retired handle.
  void cancelPreparation(String profileId, Future<ProfileCatalog> expected) {
    if (!identical(_preparing[profileId], expected)) return;
    _generations[profileId] = (_generations[profileId] ?? 0) + 1;
    _preparing.remove(profileId);
  }

  Future<void> _releaseCore(String catalogId) async {
    try {
      if (await releaseCatalog?.call(catalogId) == false) {
        onError?.call('releaseFailed');
      }
    } catch (_) {
      onError?.call('releaseFailed');
    }
  }

  /// Explicit full-profile testing only. Display queries and single-node
  /// preparation never reach the resolver or initiate a provider download.
  Future<CatalogTestPlan> resolveForTestAll(Profile profile,
      {required bool Function() isCurrent}) async {
    final generation = _generations[profile.id] ?? 0;
    final metadata = await fileMetadata(profile.id);
    if (metadata == null) throw const CatalogBuildException('fileMissing');
    if (profile.isUpdating) throw const CatalogBuildException('updating');
    final script = scriptFingerprint();
    var disposed = false;
    bool current() =>
        !disposed && isCurrent() && _isCurrent(profile.id, generation);
    void check() {
      if (!current()) throw const CatalogBuildException('cancelled');
    }

    Future<void> verify() async {
      check();
      if (await fileMetadata(profile.id) != metadata ||
          scriptFingerprint() != script) {
        throw const CatalogBuildException('configChanged');
      }
      check();
    }

    final maps = <Map<String, dynamic>>[];
    final encodedNodeBytes = <int>[];
    var payloadBytes = 0;
    const maxProfilePayloadBytes = 32 * 1024 * 1024;
    final nodes = <CatalogNode>[];
    final issues = <CatalogProviderIssue>[];
    final providerCounts = <String, int>{};
    final held = <String>{};
    _allPlanProfiles[profile.id] = (_allPlanProfiles[profile.id] ?? 0) + 1;
    void dropPlan() {
      if (disposed) return;
      disposed = true;
      maps.clear();
      encodedNodeBytes.clear();
      final count = (_allPlanProfiles[profile.id] ?? 1) - 1;
      if (count <= 0) {
        _allPlanProfiles.remove(profile.id);
      } else {
        _allPlanProfiles[profile.id] = count;
      }
      for (final id in held.toList()) {
        unawaited(releasePrepared(id));
      }
      held.clear();
    }

    await _acquire();
    try {
      check();
      final raw = await evaluate(await readProfileConfig(profile.id));
      check();
      // Validate containers/groups without applying the per-Core 2000-node
      // ceiling to the complete profile; preparation partitions below.
      if (raw['proxies'] != null && raw['proxies'] is! List) {
        throw const CatalogBuildException('parseFailed');
      }
      buildProfileCatalog(
          profileId: profile.id,
          fingerprint: '',
          raw: {...raw, 'proxies': const []});
      void append(Object? value, CatalogNodeSource source, String? provider) {
        if (value is Map && _nonLeafTypes.contains(value['type'])) return;
        if (nodes.length >= maxProjectionNodes) {
          issues.add(CatalogProviderIssue(
              providerName: provider, reason: 'tooManyNodes', count: 1));
          return;
        }
        Map<String, dynamic> map;
        try {
          map = value is Map ? Map<String, dynamic>.from(value) : {};
        } catch (_) {
          map = {};
        }
        final bytes = utf8.encode(jsonEncode(map)).length;
        // The inner JSON is itself a string in Action.data. Count both
        // encodings, including escaped credentials, before retaining a node.
        final frameBytes = utf8.encode(jsonEncode(jsonEncode(map))).length - 2;
        if (payloadBytes + bytes > maxProfilePayloadBytes ||
            frameBytes > 512 * 1024 - 1024) {
          issues.add(CatalogProviderIssue(
              providerName: provider, reason: 'providerTooLarge', count: 1));
          return;
        }
        CatalogNode node;
        try {
          node = catalogNodeFromMap(
                  profileId: profile.id,
                  proxy: map,
                  source: source,
                  providerName: provider)
              .copyWith(unsupported: catalogIsolationUnsupportedReason(map));
        } on FormatException {
          node = unparsedCatalogNode(
              profileId: profile.id,
              sourceIndex: nodes.length,
              source: source,
              providerName: provider,
              name: map['name'] is String ? map['name'] as String : null,
              type: map['type'] is String ? map['type'] as String : null);
        }
        maps.add(map);
        encodedNodeBytes.add(frameBytes);
        payloadBytes += bytes;
        nodes.add(node);
      }

      for (final rawNode in (raw['proxies'] as List?) ?? const []) {
        append(rawNode, CatalogNodeSource.inline, null);
      }
      for (final entry
          in ((raw['proxy-providers'] as Map?) ?? const {}).entries) {
        check();
        final name = entry.key as String;
        if (entry.value is! Map || providerResolver == null) {
          issues.add(CatalogProviderIssue(
              providerName: name,
              reason: entry.value is Map
                  ? 'providerOptionsUnsupported'
                  : 'parseFailed'));
          providerCounts[name] = -1;
          continue;
        }
        final resolved = await providerResolver!.resolve(
            profile.id, name, Map<String, dynamic>.from(entry.value as Map),
            isCurrent: current);
        check();
        issues.addAll(resolved.issues);
        final sourceBytes = resolved.proxies.fold<int>(
            0, (sum, value) => sum + utf8.encode(jsonEncode(value)).length);
        if (payloadBytes + sourceBytes > maxProfilePayloadBytes) {
          issues.add(CatalogProviderIssue(
              providerName: name,
              reason: 'providerTooLarge',
              count: resolved.proxies.length));
          providerCounts[name] = -1;
          continue;
        }
        final before = nodes.length;
        for (final proxy in resolved.proxies) {
          append(proxy, CatalogNodeSource.provider, name);
        }
        providerCounts[name] = nodes.length - before;
      }
      await verify();
      final fingerprint = '${metadata.modifiedMicros}|${metadata.size}|$script';
      final display = ProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          status: ProfileCatalogStatus.ready,
          nodes: List.unmodifiable(nodes),
          providerNodeCounts: Map.unmodifiable(providerCounts));
      _cache.remove(profile.id);
      _cache[profile.id] = display;
      _dirtyCache.remove(profile.id);
      while (_cache.length > maxCachedCatalogs) {
        _cache.remove(_cache.keys.first);
      }
      onPrepared?.call(display);
      final chunks = <({int start, int end})>[];
      var start = 0;
      var frameBytes = 1024; // Fixed Action/catalog metadata is under 1 KiB.
      for (var i = 0; i < nodes.length; i++) {
        if (i - start >= maxNodes ||
            frameBytes + encodedNodeBytes[i] + 1 > 512 * 1024) {
          chunks.add((start: start, end: i));
          start = i;
          frameBytes = 1024;
        }
        frameBytes += encodedNodeBytes[i] + 1;
      }
      if (start < nodes.length) chunks.add((start: start, end: nodes.length));
      return CatalogTestPlan(
          nodes: nodes,
          providerIssues: issues,
          chunkCount: chunks.length,
          onDispose: dropPlan,
          prepare: (index) async {
            await verify();
            final prepare = prepareCatalog;
            if (prepare == null || releaseCatalog == null) {
              throw const CatalogBuildException('runtimeUnavailable');
            }
            final start = chunks[index].start;
            final end = chunks[index].end;
            final selected = List<CatalogNode>.from(nodes.sublist(start, end));
            final payload = maps.sublist(start, end);
            final random = Random.secure();
            final id =
                'c-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
            try {
              final response = jsonDecode(await prepare(id, payload, const []));
              await verify();
              if (response is! Map ||
                  response['catalog-id'] != id ||
                  response['nodes'] is! List ||
                  (response['nodes'] as List).length != selected.length) {
                throw const CatalogBuildException('invalidResponse');
              }
              final seen = <int>{};
              for (final row in response['nodes'] as List) {
                if (row is! Map ||
                    row['index'] is! int ||
                    row['supported'] is! bool) {
                  throw const CatalogBuildException('invalidResponse');
                }
                final i = row['index'] as int;
                if (i < 0 || i >= selected.length || !seen.add(i)) {
                  throw const CatalogBuildException('invalidResponse');
                }
                final node = selected[i];
                final supported = row['supported'] == true &&
                    node.unsupported == CatalogUnsupportedReason.none;
                selected[i] = node.copyWith(
                    coreIndex: supported ? i : null,
                    unsupported: supported
                        ? CatalogUnsupportedReason.none
                        : node.unsupported != CatalogUnsupportedReason.none
                            ? node.unsupported
                            : switch (row['reason']) {
                                'chainUnsupported' =>
                                  CatalogUnsupportedReason.chainUnsupported,
                                'typeUnsupported' =>
                                  CatalogUnsupportedReason.typeUnsupported,
                                'strictModeUnsupported' =>
                                  CatalogUnsupportedReason
                                      .strictModeUnsupported,
                                _ => CatalogUnsupportedReason.parseFailed,
                              });
              }
              await verify();
              held.add(id);
              _allCatalogOwners[id] = () => held.remove(id);
              return display.copyWith(nodes: selected, coreCatalogId: id);
            } on CatalogBuildException {
              held.remove(id);
              await _releaseCore(id);
              rethrow;
            } catch (_) {
              held.remove(id);
              await _releaseCore(id);
              throw const CatalogBuildException('prepareFailed');
            }
          });
    } on CatalogBuildException {
      dropPlan();
      rethrow;
    } catch (_) {
      dropPlan();
      throw const CatalogBuildException('parseFailed');
    } finally {
      _release();
    }
  }

  Future<ProfileCatalog> _prepare(Profile profile, int generation) async {
    final prepare = prepareCatalog;
    if (prepare == null || releaseCatalog == null) {
      throw const CatalogBuildException('runtimeUnavailable');
    }
    final random = Random.secure();
    final id =
        'c-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    var sent = false;
    await _acquire();
    try {
      final metadata = await fileMetadata(profile.id);
      if (metadata == null) {
        throw const CatalogBuildException('fileMissing');
      }
      final script = scriptFingerprint();
      final raw = await evaluate(await readProfileConfig(profile.id));
      final fingerprint = '${metadata.modifiedMicros}|${metadata.size}|$script';
      final catalog = buildProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          raw: raw,
          isolatedTest: true,
          maxNodes: maxNodes);
      final proxies = <Map<String, dynamic>>[];
      for (final proxy in (raw['proxies'] as List?) ?? const []) {
        if (proxy is Map && _nonLeafTypes.contains(proxy['type'])) continue;
        proxies.add(proxy is Map ? Map<String, dynamic>.from(proxy) : {});
      }
      final providers = <Map<String, dynamic>>[];
      for (final entry in ((raw['proxy-providers'] as Map?) ?? {}).entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final path = await providerCachePath?.call(profile.id,
            entry.key as String, Map<String, dynamic>.from(entry.value as Map));
        if (path != null) providers.add({'name': entry.key, 'path': path});
      }
      // A file/script change during evaluation must not be tested under the
      // previous display identity or survive subscription deletion.
      Future<void> verifyCurrent() async {
        final currentMetadata = await fileMetadata(profile.id);
        if (!_isCurrent(profile.id, generation) ||
            currentMetadata != metadata ||
            scriptFingerprint() != script) {
          throw const CatalogBuildException('configChanged');
        }
      }

      await verifyCurrent();
      final previous = _prepared.remove(profile.id);
      if (previous?.coreCatalogId case final String oldId) {
        await _releaseCore(oldId);
      }
      while (_prepared.length >= 3) {
        final oldest = _prepared.remove(_prepared.keys.first)!;
        await _releaseCore(oldest.coreCatalogId!);
      }
      sent = true;
      final encoded = await prepare(id, proxies, providers);
      final response = jsonDecode(encoded);
      if (response is! Map ||
          response['catalog-id'] != id ||
          response['nodes'] is! List) {
        throw const CatalogBuildException('invalidResponse');
      }
      final nodes = List<CatalogNode>.of(catalog.nodes);
      final rows = response['nodes'] as List;
      if (rows.length != nodes.length) {
        throw const CatalogBuildException('invalidResponse');
      }
      final seen = <int>{};
      for (final row in rows) {
        if (row is! Map || row['index'] is! int || row['supported'] is! bool) {
          throw const CatalogBuildException('invalidResponse');
        }
        final index = row['index'] as int;
        if (index < 0 || index >= nodes.length || !seen.add(index)) {
          throw const CatalogBuildException('invalidResponse');
        }
        final node = nodes[index];
        // Malformed placeholders have no endpoint identity and are never
        // eligible for a measurement even if a remote response says otherwise.
        final reason = switch (row['reason']) {
          'chainUnsupported' => CatalogUnsupportedReason.chainUnsupported,
          'typeUnsupported' => CatalogUnsupportedReason.typeUnsupported,
          'strictModeUnsupported' =>
            CatalogUnsupportedReason.strictModeUnsupported,
          _ => CatalogUnsupportedReason.parseFailed,
        };
        final supported = row['supported'] == true &&
            node.unsupported == CatalogUnsupportedReason.none;
        nodes[index] = node.copyWith(
            coreIndex: supported ? index : null,
            unsupported: supported
                ? CatalogUnsupportedReason.none
                : node.unsupported != CatalogUnsupportedReason.none
                    ? node.unsupported
                    : reason);
      }
      await verifyCurrent();
      final prepared = catalog.copyWith(coreCatalogId: id, nodes: nodes);
      _prepared[profile.id] = prepared;
      // Preserve newly discovered unsupported rows in the display cache. Core
      // handles and indices remain private to this short-lived preparation.
      final display = prepared.copyWith(coreCatalogId: null, nodes: [
        for (final node in nodes) node.copyWith(coreIndex: null),
      ]);
      _cache[profile.id] = display;
      _dirtyCache.remove(profile.id);
      while (_cache.length > maxCachedCatalogs) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest);
        _dirtyCache.remove(oldest);
      }
      onPrepared?.call(display);
      return prepared;
    } on CatalogBuildException {
      if (sent) await _releaseCore(id);
      rethrow;
    } catch (_) {
      if (sent) await _releaseCore(id);
      throw const CatalogBuildException('prepareFailed');
    } finally {
      _release();
    }
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
          isolatedTest: true,
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
