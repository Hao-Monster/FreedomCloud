import 'dart:io';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/common/per_app_policy.dart';
import 'package:path/path.dart' as path;

/// Builds the JSON contract consumed by the Agent strict-policy command.
///
/// The identity map must contain values returned by
/// [ClashService.inspectStrictIdentity].  Callers cannot provide digests or
/// child identities directly; this helper only serializes trusted responses.
Map<String, dynamic> buildStrictPolicyBundle({
  required Iterable<PerAppPolicy> entries,
  required Map<String, StrictIdentityResolution> identities,
  required int revision,
}) {
  if (revision <= 0) {
    throw ArgumentError.value(revision, 'revision', 'must be positive');
  }
  final policyEntries = <Map<String, dynamic>>[];
  for (final entry in entries) {
    if (entry.policy == ApplicationRoutingPolicy.inherit) continue;
    final identity = identities[_strictPathKey(entry.path)];
    if (identity == null) {
      throw StateError('strict identity evidence is unavailable');
    }
    final action = entry.policy == ApplicationRoutingPolicy.block
        ? 'block'
        : entry.policy == ApplicationRoutingPolicy.proxy
            ? 'proxy'
            : 'direct';
    // DIRECT is not a strict-contract action.  Treating it as proxy would be
    // an unsafe policy change, so reject it and keep the caller fail-closed.
    if (action == 'direct') {
      throw StateError('strict mode does not support direct application policy');
    }
    final identityJson = <String, dynamic>{
      'identityId': identity.identityId,
      'canonicalPath': identity.canonicalPath,
      'wfpAppIdSha256': identity.wfpAppIdSha256,
      'publisherCertificateSha256': identity.publisherCertificateSha256,
      'verifiedChildren': const <Map<String, dynamic>>[],
    };
    policyEntries.add({
      'identity': identityJson,
      'action': action,
      if (action == 'proxy')
        'targetGroup': PerAppPolicy.validateTargetGroup(
          entry.targetGroup ?? 'GLOBAL',
        ),
    });
  }
  if (policyEntries.isEmpty) {
    throw StateError('strict policy must contain at least one application');
  }
  return {
    'protocol': 2,
    'revision': revision,
    'entries': policyEntries,
  };
}

String _strictPathKey(String value) {
  final normalized = path.normalize(value.trim());
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

/// Reuses cached identity evidence only when it corresponds to the same
/// canonical path returned by Helper.  This prevents a path replacement from
/// silently reusing stale evidence after an executable is updated.
bool strictIdentityMatchesPath(
  PerAppPolicy entry,
  StrictIdentityResolution identity,
) =>
    _strictPathKey(entry.path) == _strictPathKey(identity.canonicalPath);
