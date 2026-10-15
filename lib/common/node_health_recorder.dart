import 'package:flclashx/models/node_catalog.dart';

import 'node_catalog_service.dart';
import 'node_health_store.dart';

/// A request owns these hashes even when the active configuration changes.
class NodeHealthTarget {
  const NodeHealthTarget._(
      this.profileId, this.identityKey, this.testUrl, this.generation);
  final String profileId;
  final String identityKey;
  final String testUrl;
  final int generation;
}

/// Captures the *applied* configuration, never a later subscription file.
/// Weak keys do not keep retired raw configurations/credentials alive.
class NodeHealthRecorder {
  NodeHealthRecorder({required this.store, DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final NodeHealthStore store;
  final DateTime Function() _now;
  final _identities = Expando<Map<String, Map<String, String>>>();
  final _catalogIdentities = Expando<Map<String, String>>();
  final _generations = <String, int>{};
  Future<void> _pending = Future<void>.value();

  NodeHealthTarget? capture({
    required String profileId,
    required Map<String, dynamic> raw,
    required String name,
    required String url,
  }) {
    final profiles = _identities[raw] ??= {};
    var identities = profiles[profileId];
    if (identities == null) {
      final catalog = buildProfileCatalog(
          profileId: profileId, fingerprint: 'runtime', raw: raw);
      identities = _identitiesForCatalog(catalog);
      profiles[profileId] = identities;
    }
    final key = identities[name];
    if (key == null) return null;
    return NodeHealthTarget._(
        profileId, key, url, _generations[profileId] ?? 0);
  }

  /// Accepts a verified, already-redacted runtime catalog without retaining its
  /// source configuration. Callers establish runtime ownership before capture.
  NodeHealthTarget? captureCatalog({
    required ProfileCatalog catalog,
    required String name,
    required String url,
  }) {
    if (catalog.status != ProfileCatalogStatus.ready) return null;
    final identities =
        _catalogIdentities[catalog] ??= _identitiesForCatalog(catalog);
    final key = identities[name];
    if (key == null) return null;
    return NodeHealthTarget._(
        catalog.profileId, key, url, _generations[catalog.profileId] ?? 0);
  }

  Map<String, String> _identitiesForCatalog(ProfileCatalog catalog) {
    final identities = <String, String>{};
    final seen = <String>{};
    final ambiguous = <String>{};
    for (final node in catalog.nodes) {
      // Bad/good duplicates are still ambiguous, in either source order.
      if (!seen.add(node.name)) ambiguous.add(node.name);
      if (node.unsupported == CatalogUnsupportedReason.parseFailed) continue;
      identities[node.name] = node.identityKey;
    }
    ambiguous.forEach(identities.remove);
    return identities;
  }

  Future<void> record(NodeHealthTarget target, int value,
      {String? reason, DateTime? testedAt}) {
    if (value == 0) return Future<void>.value();
    final arrivedAt = testedAt ?? _now();
    return _serialize(() async {
      if (target.generation != (_generations[target.profileId] ?? 0)) return;
      await store.record(
        profileId: target.profileId,
        identityKey: target.identityKey,
        delayMs: value,
        testUrl: target.testUrl,
        reason: reason,
        testedAt: arrivedAt,
      );
    });
  }

  Future<void> removeProfile(String profileId) {
    _generations[profileId] = (_generations[profileId] ?? 0) + 1;
    return _serialize(() => store.removeProfile(profileId));
  }

  Future<void> flush() => _serialize(store.flush);

  Future<void> _serialize(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    // The returned future reports failure; later writes may still recover.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
