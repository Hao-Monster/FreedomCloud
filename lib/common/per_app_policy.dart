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
  });

  final String path;
  final String name;
  final ApplicationRoutingPolicy policy;

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

  Map<String, Object> toJson() => {
        'path': path,
        'name': name,
        'policy': policy.name,
      };
}

List<String> compilePerAppPolicyRules(Iterable<PerAppPolicy> policies) =>
    policies
        .where((entry) => entry.policy != ApplicationRoutingPolicy.inherit)
        .map((entry) {
      final processPath = PerAppPolicy.validatePath(entry.path);
      final target = switch (entry.policy) {
        ApplicationRoutingPolicy.proxy => 'GLOBAL',
        ApplicationRoutingPolicy.direct => 'DIRECT',
        ApplicationRoutingPolicy.block => 'REJECT',
        ApplicationRoutingPolicy.inherit => throw StateError('unreachable'),
      };
      return 'PROCESS-PATH,$processPath,$target';
    }).toList(growable: false);

List<Object?> mergePerAppPolicyRules(
  Iterable<PerAppPolicy> policies,
  Iterable<Object?> profileRules,
) =>
    [
      ...compilePerAppPolicyRules(policies),
      ...profileRules,
    ];

List<PerAppPolicy> decodePerAppPolicies(Object? value) {
  if (value is! Map || value['version'] != 1 || value['entries'] is! List) {
    return const [];
  }
  final decoded = <PerAppPolicy>[];
  for (final raw in value['entries'] as List) {
    if (raw is! Map) continue;
    try {
      final processPath = PerAppPolicy.validatePath(raw['path'] as String);
      final policy = ApplicationRoutingPolicy.values.byName(
        raw['policy'] as String,
      );
      final rawName = raw['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : path.basename(processPath);
      decoded.add(
        PerAppPolicy(
          path: processPath,
          name: name.length > 256 ? name.substring(0, 256) : name,
          policy: policy,
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
  // UI actions can arrive back-to-back (for example, changing two process
  // policies before the first profile apply completes). Serialize mutations so
  // each update is based on the latest committed set instead of losing a
  // concurrent write.
  Future<void> _mutationTail = Future<void>.value();

  List<PerAppPolicy> get entries => List.unmodifiable(_entries.values);

  ApplicationRoutingPolicy policyFor(String processPath) =>
      _entries[_key(processPath)]?.policy ?? ApplicationRoutingPolicy.inherit;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> setPolicy({
    required String processPath,
    required String name,
    required ApplicationRoutingPolicy policy,
  }) {
    final operation = _mutationTail.then<void>(
      (_) => _setPolicy(
        processPath: processPath,
        name: name,
        policy: policy,
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
      'version': 1,
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
