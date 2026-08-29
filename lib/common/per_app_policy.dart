// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/connection_diagnostics.dart';
import 'package:flclashx/common/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

const maxPerAppPolicies = 128;

enum ApplicationRoutingPolicy { inherit, proxy, direct, block }

String applicationRoutingPolicyLabel(ApplicationRoutingPolicy policy) =>
    switch (policy) {
      ApplicationRoutingPolicy.inherit => 'INHERIT',
      ApplicationRoutingPolicy.proxy => 'PROXY',
      ApplicationRoutingPolicy.direct => 'DIRECT',
      ApplicationRoutingPolicy.block => 'BLOCK',
    };

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
        target = 'REJECT';
      }
      return 'PROCESS-PATH,$processPath,$target';
    }).toList(growable: false);

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

List<String> availablePerAppTargetGroups(Iterable<String> declaredGroups) {
  final groups = <String>['GLOBAL'];
  for (final value in declaredGroups) {
    if (!PerAppPolicy.isValidTargetGroup(value)) continue;
    final group = value.trim();
    if (!groups.contains(group)) groups.add(group);
  }
  return List.unmodifiable(groups);
}

List<PerAppPolicy> decodePerAppPolicies(Object? value) {
  if (value is! Map ||
      (value['version'] != 1 && value['version'] != 2) ||
      value['entries'] is! List) {
    return const [];
  }
  final version = value['version'] as int;
  final decoded = <PerAppPolicy>[];
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
      decoded.add(
        PerAppPolicy(
          path: processPath,
          name: name.length > 256 ? name.substring(0, 256) : name,
          policy: policy,
          targetGroup: targetGroup,
        ),
      );
    } catch (_) {
      // A malformed entry must not disable all valid application policies.
    }
  }
  return decoded.length <= maxPerAppPolicies
      ? List.unmodifiable(decoded)
      : List.unmodifiable(decoded.sublist(decoded.length - maxPerAppPolicies));
}

class PerAppPolicyStore extends ChangeNotifier {
  static const _fileName = 'per_app_policies.json';

  final Map<String, PerAppPolicy> _entries = {};
  Future<void>? _loading;

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
  }) async {
    await ensureLoaded();
    final validatedPath = PerAppPolicy.validatePath(processPath);
    final next = Map<String, PerAppPolicy>.of(_entries);
    final key = _key(validatedPath);
    next.remove(key);
    if (policy != ApplicationRoutingPolicy.inherit) {
      final candidateName =
          name.trim().isEmpty ? path.basename(validatedPath) : name.trim();
      final validatedTarget = policy == ApplicationRoutingPolicy.proxy
          ? PerAppPolicy.validateTargetGroup(targetGroup ?? 'GLOBAL')
          : null;
      next[key] = PerAppPolicy(
        path: validatedPath,
        name: candidateName.length > 256
            ? candidateName.substring(0, 256)
            : candidateName,
        policy: policy,
        targetGroup: validatedTarget,
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
    try {
      final file = await _policyFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      final decoded = decodePerAppPolicies(raw);
      _entries
        ..clear()
        ..addEntries(decoded.map((entry) => MapEntry(_key(entry.path), entry)));
      connectionDiagnostics.log(
        '[ConnectionsDiag] perApp.load status=ok count=${_entries.length}',
      );
    } catch (error) {
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
    if (await file.exists()) await file.delete();
    await pending.rename(file.path);
  }

  Future<File> _policyFile() async =>
      File(path.join(await appPath.homeDirPath, _fileName));

  String _key(String value) {
    final normalized = path.normalize(value.trim());
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

final perAppPolicyStore = PerAppPolicyStore();
