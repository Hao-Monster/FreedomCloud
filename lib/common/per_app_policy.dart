// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/connection_diagnostics.dart';
import 'package:flclashx/common/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

const maxPerAppPolicies = 128;

enum ApplicationRoutingPolicy { inherit, proxy, direct, block }

/// Lifecycle of the platform capture owner used by strict per-application
/// routing.  This is deliberately separate from Mihomo's `find-process-mode`:
/// a strict policy is not considered active until the capture owner and the
/// forwarding route are both healthy.
enum StrictPolicyState {
  disabled,
  preparing,
  armed,
  degraded,
  blocking,
  recovering
}

enum StrictPolicyFailureReason {
  captureUnavailable,
  proxyRouteUnavailable,
  identityUnavailable,
  coreUnavailable,
  brokerUnavailable,
  recoveryExhausted,
  invalidPolicy,
}

String strictPolicyFailureCode(StrictPolicyFailureReason reason) =>
    switch (reason) {
      StrictPolicyFailureReason.captureUnavailable => 'capture_unavailable',
      StrictPolicyFailureReason.proxyRouteUnavailable =>
        'proxy_route_unavailable',
      StrictPolicyFailureReason.identityUnavailable => 'identity_unavailable',
      StrictPolicyFailureReason.coreUnavailable => 'core_unavailable',
      StrictPolicyFailureReason.brokerUnavailable => 'broker_unavailable',
      StrictPolicyFailureReason.recoveryExhausted => 'recovery_exhausted',
      StrictPolicyFailureReason.invalidPolicy => 'invalid_policy',
    };

/// Strict state transitions are intentionally explicit so a backend cannot
/// accidentally remove a block before forwarding has recovered.
bool canTransitionStrictPolicyState(
  StrictPolicyState from,
  StrictPolicyState to,
) {
  if (from == to) return true;
  return switch (from) {
    StrictPolicyState.disabled => to == StrictPolicyState.preparing,
    StrictPolicyState.preparing => to == StrictPolicyState.armed ||
        to == StrictPolicyState.degraded ||
        to == StrictPolicyState.blocking ||
        to == StrictPolicyState.disabled,
    StrictPolicyState.armed => to == StrictPolicyState.degraded ||
        to == StrictPolicyState.blocking ||
        to == StrictPolicyState.recovering ||
        to == StrictPolicyState.disabled,
    StrictPolicyState.degraded ||
    StrictPolicyState.blocking =>
      to == StrictPolicyState.recovering || to == StrictPolicyState.disabled,
    StrictPolicyState.recovering => to == StrictPolicyState.armed ||
        to == StrictPolicyState.degraded ||
        to == StrictPolicyState.blocking ||
        to == StrictPolicyState.disabled,
  };
}

enum StrictPolicyRoute { unmanaged, proxy, direct, block }

/// Result of evaluating one selected application's strict policy.
///
/// `direct` is only returned for an explicit DIRECT policy while the capture
/// owner is armed and forwarding is healthy.  A failed capture/forwarding
/// path always returns `block`; it never silently falls through to DIRECT.
@immutable
class StrictPolicyDecision {
  const StrictPolicyDecision({required this.route, this.failureReason});

  final StrictPolicyRoute route;
  final StrictPolicyFailureReason? failureReason;

  bool get isBlocking => route == StrictPolicyRoute.block;
}

StrictPolicyDecision evaluateStrictPolicy({
  required ApplicationRoutingPolicy policy,
  required StrictPolicyState state,
  required bool captureOwned,
  required bool forwardingHealthy,
  StrictPolicyFailureReason failureReason =
      StrictPolicyFailureReason.captureUnavailable,
}) {
  if (policy == ApplicationRoutingPolicy.inherit) {
    return const StrictPolicyDecision(route: StrictPolicyRoute.unmanaged);
  }
  if (state != StrictPolicyState.armed || !captureOwned || !forwardingHealthy) {
    return StrictPolicyDecision(
      route: StrictPolicyRoute.block,
      failureReason: failureReason,
    );
  }
  return StrictPolicyDecision(
    route: switch (policy) {
      ApplicationRoutingPolicy.proxy => StrictPolicyRoute.proxy,
      ApplicationRoutingPolicy.direct => StrictPolicyRoute.direct,
      ApplicationRoutingPolicy.block => StrictPolicyRoute.block,
      ApplicationRoutingPolicy.inherit => StrictPolicyRoute.unmanaged,
    },
  );
}

String applicationRoutingPolicyLabel(ApplicationRoutingPolicy policy) =>
    switch (policy) {
      ApplicationRoutingPolicy.inherit => 'INHERIT',
      ApplicationRoutingPolicy.proxy => 'PROXY',
      ApplicationRoutingPolicy.direct => 'DIRECT',
      ApplicationRoutingPolicy.block => 'BLOCK',
    };

/// Returns application policies matching a user-entered search query.
///
/// Matching is intentionally case-insensitive and covers both the friendly
/// executable name and its canonical path.  Keeping this operation pure makes
/// the settings UI cheap to rebuild and gives imports/other clients the same
/// filtering semantics without mutating the persisted store.
List<PerAppPolicy> filterPerAppPolicies(
  Iterable<PerAppPolicy> policies,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return List.unmodifiable(policies);
  return List.unmodifiable(
    policies.where((entry) {
      return entry.name.toLowerCase().contains(normalizedQuery) ||
          entry.path.toLowerCase().contains(normalizedQuery) ||
          applicationRoutingPolicyLabel(entry.policy)
              .toLowerCase()
              .contains(normalizedQuery);
    }),
  );
}

@immutable
class PerAppPolicy {
  const PerAppPolicy({
    required this.path,
    required this.name,
    required this.policy,
    this.targetGroup,
  });

  final String path;
  final String name;
  final ApplicationRoutingPolicy policy;
  /// Proxy group selected for an explicit PROXY policy.  A null value is
  /// treated as GLOBAL for backwards-compatible v1 snapshots and callers.
  final String? targetGroup;

  static String validatePath(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 1024 ||
        normalized.contains(',') ||
        normalized.contains('\r') ||
        normalized.contains('\n')) {
      throw ArgumentError.value(
        value,
        'path',
        'must be a non-empty process path without commas or line breaks',
      );
    }
    return normalized;
  }

  static String validateTargetGroup(String value) {
    final normalized = value.trim();
    if (!isValidTargetGroup(normalized)) {
      throw ArgumentError.value(
        value,
        'targetGroup',
        'must be a non-empty policy group without commas or line breaks',
      );
    }
    return normalized;
  }

  static bool isValidTargetGroup(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty &&
        normalized.length <= 256 &&
        !normalized.contains(',') &&
        !normalized.contains('\r') &&
        !normalized.contains('\n');
  }

  Map<String, Object> toJson() => {
        'path': path,
        'name': name,
        'policy': policy.name,
        if (policy == ApplicationRoutingPolicy.proxy)
          'targetGroup': validateTargetGroup(targetGroup ?? 'GLOBAL'),
      };
}

List<String> compilePerAppPolicyRules(
  Iterable<PerAppPolicy> policies, {
  Set<String>? availableTargetGroups,
  ValueChanged<String>? onUnavailableTarget,
}) =>
    policies
        .where((entry) => entry.policy != ApplicationRoutingPolicy.inherit)
        .map((entry) {
      final processPath = PerAppPolicy.validatePath(entry.path);
      var target = switch (entry.policy) {
        ApplicationRoutingPolicy.proxy =>
          PerAppPolicy.validateTargetGroup(entry.targetGroup ?? 'GLOBAL'),
        ApplicationRoutingPolicy.direct => 'DIRECT',
        ApplicationRoutingPolicy.block => 'REJECT',
        ApplicationRoutingPolicy.inherit => throw StateError('unreachable'),
      };
      if (entry.policy == ApplicationRoutingPolicy.proxy &&
          availableTargetGroups != null &&
          !availableTargetGroups.contains(target)) {
        onUnavailableTarget?.call(target);
        // Keep Core startup safe: an unavailable explicit proxy group must
        // fail closed rather than aborting the entire config transaction or
        // silently falling back to ordinary domain/IP routing.
        target = 'REJECT';
      }
      return 'PROCESS-PATH,$processPath,$target';
    }).toList(growable: false);

/// PROCESS-PATH rules require Mihomo to resolve the originating process even
/// when the connection page is in classic (non-process) mode.
bool perAppPoliciesRequireProcessLookup(Iterable<PerAppPolicy> policies) =>
    policies.any((entry) => entry.policy != ApplicationRoutingPolicy.inherit);

List<Object?> mergePerAppPolicyRules(
  Iterable<PerAppPolicy> policies,
  Iterable<Object?> profileRules, {
  Set<String>? availableTargetGroups,
  ValueChanged<String>? onUnavailableTarget,
}) =>
    [
      ...compilePerAppPolicyRules(
        policies,
        availableTargetGroups: availableTargetGroups,
        onUnavailableTarget: onUnavailableTarget,
      ),
      ...profileRules,
    ];

List<PerAppPolicy> decodePerAppPolicies(Object? value) {
  if (value is! Map ||
      (value['version'] != 1 && value['version'] != 2) ||
      value['entries'] is! List) {
    return const [];
  }
  final version = value['version'] as int;
  // Keep the last occurrence for a canonical path.  This makes imports and
  // upgrades deterministic even when an older build wrote duplicate entries
  // with different casing on Windows.
  final decodedByPath = <String, PerAppPolicy>{};
  for (final raw in value['entries'] as List) {
    if (raw is! Map) continue;
    try {
      final processPath = PerAppPolicy.validatePath(raw['path'] as String);
      final policy = ApplicationRoutingPolicy.values.byName(
        raw['policy'] as String,
      );
      final targetGroup = policy == ApplicationRoutingPolicy.proxy
          ? version == 1
              ? 'GLOBAL'
              : PerAppPolicy.validateTargetGroup(raw['targetGroup'] as String)
          : null;
      final rawName = raw['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : path.basename(processPath);
      final entry = PerAppPolicy(
        path: processPath,
        name: name.length > 256 ? name.substring(0, 256) : name,
        policy: policy,
        targetGroup: targetGroup,
      );
      final key = Platform.isWindows
          ? path.normalize(processPath).toLowerCase()
          : path.normalize(processPath);
      decodedByPath[key] = entry;
    } catch (_) {
      // A malformed entry must not disable all valid application policies.
    }
  }
  final decoded = decodedByPath.values.toList(growable: false);
  return decoded.length <= maxPerAppPolicies
      ? List.unmodifiable(decoded)
      : List.unmodifiable(decoded.sublist(decoded.length - maxPerAppPolicies));
}

/// Returns safe proxy-group choices for the per-application settings UI while
/// preserving declaration order and rejecting values that could alter the
/// comma-delimited Mihomo rule syntax.
List<String> availablePerAppTargetGroups(Iterable<String> declaredGroups) {
  final groups = <String>['GLOBAL'];
  for (final value in declaredGroups) {
    if (!PerAppPolicy.isValidTargetGroup(value)) continue;
    final group = value.trim();
    if (!groups.contains(group)) groups.add(group);
  }
  return List.unmodifiable(groups);
}

bool _isValidPolicySnapshot(Object? value) =>
    value is Map &&
    (value['version'] == 1 || value['version'] == 2) &&
    value['entries'] is List;

class PerAppPolicyStore extends ChangeNotifier {
  static const _fileName = 'per_app_policies.json';

  final Map<String, PerAppPolicy> _entries = {};
  Future<void>? _loading;
  // UI actions can arrive back-to-back (for example, changing two process
  // policies before the first profile apply completes). Serialize mutations so
  // each update is based on the latest committed set instead of losing a
  // concurrent write.
  Future<void> _mutationTail = Future<void>.value();

  List<PerAppPolicy> get entries => List.unmodifiable(_entries.values);

  ApplicationRoutingPolicy policyFor(String processPath) =>
      _entries[_key(processPath)]?.policy ?? ApplicationRoutingPolicy.inherit;

  PerAppPolicy? entryFor(String processPath) => _entries[_key(processPath)];

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> setPolicy({
    required String processPath,
    required String name,
    required ApplicationRoutingPolicy policy,
    String? targetGroup,
  }) {
    final operation = _mutationTail.then<void>(
      (_) => _setPolicy(
        processPath: processPath,
        name: name,
        policy: policy,
        targetGroup: targetGroup,
      ),
    );
    // Keep the queue usable after a failed write while preserving the error
    // for the caller that initiated this operation.
    _mutationTail = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> _setPolicy({
    required String processPath,
    required String name,
    required ApplicationRoutingPolicy policy,
    String? targetGroup,
  }) async {
    await ensureLoaded();
    final validatedPath = PerAppPolicy.validatePath(processPath);
    final next = Map<String, PerAppPolicy>.of(_entries);
    final key = _key(validatedPath);
    next.remove(key);
    if (policy != ApplicationRoutingPolicy.inherit) {
      final candidateName =
          name.trim().isEmpty ? path.basename(validatedPath) : name.trim();
      next[key] = PerAppPolicy(
        path: validatedPath,
        name: candidateName.length > 256
            ? candidateName.substring(0, 256)
            : candidateName,
        policy: policy,
        targetGroup: policy == ApplicationRoutingPolicy.proxy
            ? PerAppPolicy.validateTargetGroup(targetGroup ?? 'GLOBAL')
            : null,
      );
      while (next.length > maxPerAppPolicies) {
        next.remove(next.keys.first);
      }
    }
    await _persist(next.values);
    _entries
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  Future<void> _load() async {
    final file = await _policyFile();
    final backup = File('${file.path}.backup');
    try {
      // A process crash can occur after the previous file was moved to the
      // backup but before the pending file was renamed into place. Recover the
      // last known-good snapshot before decoding instead of silently starting
      // with an empty policy set.
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (!_isValidPolicySnapshot(raw)) {
        throw const FormatException('invalid policy snapshot');
      }
      final decoded = decodePerAppPolicies(raw);
      _entries
        ..clear()
        ..addEntries(decoded.map((entry) => MapEntry(_key(entry.path), entry)));
      connectionDiagnostics.log(
        '[ConnectionsDiag] perApp.load status=ok count=${_entries.length}',
      );
    } catch (error) {
      // If the primary file is truncated or malformed, recover the last
      // known-good backup rather than silently disabling every app rule.
      if (await backup.exists()) {
        try {
          final backupRaw = jsonDecode(await backup.readAsString());
          if (_isValidPolicySnapshot(backupRaw)) {
            final decoded = decodePerAppPolicies(backupRaw);
            await file.writeAsString(await backup.readAsString(), flush: true);
            _entries
              ..clear()
              ..addEntries(
                decoded.map((entry) => MapEntry(_key(entry.path), entry)),
              );
            connectionDiagnostics.log(
              '[ConnectionsDiag] perApp.load status=recovered '
              'count=${_entries.length}',
            );
            return;
          }
        } catch (_) {
          // Preserve the original error type in diagnostics below.
        }
      }
      connectionDiagnostics.log(
        '[ConnectionsDiag] perApp.load status=error '
        'errorType=${error.runtimeType}',
      );
    }
  }

  Future<void> _persist(Iterable<PerAppPolicy> entries) async {
    final file = await _policyFile();
    await file.parent.create(recursive: true);
    final content = jsonEncode({
      'version': 2,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    });
    final pending = File('${file.path}.pending');
    await pending.writeAsString(content, flush: true);
    final backup = File('${file.path}.backup');
    var movedOriginal = false;
    try {
      // Dart's rename does not replace an existing file on Windows. Keep the
      // old snapshot until the new one is in place so a failed write cannot
      // erase the user's policies.
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) {
        await file.rename(backup.path);
        movedOriginal = true;
      }
      await pending.rename(file.path);
      if (movedOriginal && await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      // Best-effort cleanup and rollback. Preserve the original error for the
      // caller so the UI can report that the policy was not applied.
      if (await pending.exists()) {
        await pending.delete();
      }
      if (movedOriginal && !await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<File> _policyFile() async =>
      File(path.join(await appPath.homeDirPath, _fileName));

  String _key(String value) {
    final normalized = path.normalize(value.trim());
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

final perAppPolicyStore = PerAppPolicyStore();
