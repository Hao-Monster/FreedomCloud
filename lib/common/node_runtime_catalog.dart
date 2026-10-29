import 'dart:async';

import 'package:flclashx/models/node_catalog.dart';
import 'package:flutter/foundation.dart';

import 'node_catalog_service.dart';

/// Revocable configuration ownership, shared across fresh batch reads. Callers
/// keep their exact Future; refreshing must not revoke an earlier pending read.
class NodeRuntimeRead {
  NodeRuntimeRead(this._read);
  final Future<ProfileCatalog?> Function(bool Function()) _read;
  Future<ProfileCatalog?>? _result;
  Future<ProfileCatalog?> get result => _result ??= _read(() => isCurrent);
  bool _current = true;
  bool get isCurrent => _current;
  void refresh() => _result = null;
  void invalidate() => _current = false;
}

/// Only the whitelisted projection survives this read. A profile selection is
/// not proof of ownership: compare names and endpoints with the applied Core.
Future<ProfileCatalog?> readVerifiedNodeRuntime({
  required String profileId,
  required Future<Map<String, dynamic>> Function() readRuntime,
  required Future<ProfileCatalog> Function() readProfile,
  required bool Function() isCurrent,
  Duration timeout = const Duration(seconds: 3),
}) async {
  Future<ProfileCatalog?> read() async {
    if (!isCurrent()) return null;
    // Start both reads together; neither dependency can apply/download config.
    final profileFuture = readProfile();
    final runtimeFuture = readRuntime();
    final values = await Future.wait<Object>([profileFuture, runtimeFuture]);
    if (!isCurrent()) return null;
    final profile = values[0] as ProfileCatalog;
    if (profile.status != ProfileCatalogStatus.ready) return null;
    final runtime = buildProfileCatalog(
        profileId: profileId,
        fingerprint: 'verified-runtime',
        raw: values[1] as Map<String, dynamic>);
    // Unidentifiable nodes have no history identity. Their presence must not
    // prevent other nodes from being verified, but extras/duplicates/renames in
    // the identifiable set must fail closed (including swapped endpoints).
    // The runtime snapshot attests inline definitions only. An explicit all-
    // profile test may have expanded provider caches in the display catalog;
    // those endpoints are not evidence of the running provider generation.
    List<String> identities(ProfileCatalog catalog) => catalog.nodes
        .where((node) =>
            node.source == CatalogNodeSource.inline &&
            node.unsupported != CatalogUnsupportedReason.parseFailed)
        .map((node) => node.identityKey)
        .toList()
      ..sort();
    final actual = identities(runtime);
    if (actual.isEmpty || !listEquals(actual, identities(profile))) return null;
    return runtime;
  }

  try {
    return await read().timeout(timeout);
  } catch (_) {
    // Parser/transport errors can contain credentials. A failed read does not
    // justify setup, reconnect, fallback identity guesses, or raw error logs.
    return null;
  }
}
