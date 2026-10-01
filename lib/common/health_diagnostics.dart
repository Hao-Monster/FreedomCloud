import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/clash/clash.dart';

class HealthCheckResult {
  const HealthCheckResult(this.check, this.status, this.elapsedMs);
  final String check;
  final String status;
  final int elapsedMs;
  Map<String, Object> toJson() => {'check': check, 'status': status, 'elapsedMs': elapsedMs};
}

/// Export only this closed schema. Never append exception messages, raw logs,
/// profile data or configuration values to a shareable health report.
class HealthDiagnostics {
  static bool _running = false;
  static Future<List<HealthCheckResult>> run({
    required bool hasProfile, required bool proxyRequested,
    required void Function(List<HealthCheckResult>) onProgress,
  }) async {
    if (_running) throw StateError('Health check already running');
    _running = true;
    final results = <HealthCheckResult>[];
    try {
      Future<void> check(String name, FutureOr<bool> Function() action) async {
        final watch = Stopwatch()..start();
        var status = 'failed';
        try {
          status = await Future<bool>.sync(action).timeout(const Duration(seconds: 5))
              ? 'passed' : 'failed';
        } on TimeoutException { status = 'timeout'; }
        catch (_) { status = 'unavailable'; }
        results.add(HealthCheckResult(name, status, watch.elapsedMilliseconds));
        onProgress(List.unmodifiable(results));
      }
      await check('profile_selected', () => hasProfile);
      await check('proxy_requested', () => proxyRequested);
      await check('core_initialized', () async => await clashCore.isInit);
      await check('core_memory_response', () async {
        final raw = await clashCore.clashInterface.getMemory();
        final value = int.tryParse(raw);
        return value != null && value >= 0;
      });
      await check('core_traffic_response', () async {
        final raw = await clashCore.clashInterface.getTraffic();
        final value = jsonDecode(raw);
        return value is Map && value['up'] is num && value['down'] is num;
      });
      return List.unmodifiable(results);
    } finally { _running = false; }
  }

  static Uint8List export(List<HealthCheckResult> results) => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'platform': Platform.operatingSystem,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'scope': 'local_control_plane_only',
      'checks': results.take(8).map((result) => result.toJson()).toList(),
    })));
}
