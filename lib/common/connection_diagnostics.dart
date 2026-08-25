// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/common/path.dart';
import 'package:path/path.dart';

/// Privacy-safe, low-volume diagnostics for the connections pipeline.
///
/// Callers must only pass counters, booleans, durations and error type names.
/// Connection metadata, configuration values and filesystem paths never belong
/// in this log because users may share it when reporting a problem.
class ConnectionDiagnostics {
  ConnectionDiagnostics._();

  static const fileName = 'connections_diagnostic.log';
  static const buildId = 'connections-diag-20260824-1';
  static const _maxBytes = 1024 * 1024;

  Future<void> _pendingWrite = Future<void>.value();

  void log(String event) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final singleLine = event.replaceAll(RegExp(r'[\r\n]+'), ' ');
    _pendingWrite = _pendingWrite.then((_) => _write(singleLine));
  }

  /// Returns only the privacy-safe connection pipeline log. It intentionally
  /// excludes profiles, hosts, process paths and the general application log.
  Future<Uint8List> exportBytes() async {
    await _pendingWrite;
    try {
      final homeDir = await appPath.homeDirPath;
      final file = File(join(homeDir, 'logs', fileName));
      if (await file.exists()) return file.readAsBytes();
    } catch (_) {
      // Export remains useful even when the diagnostic directory is missing.
    }
    return Uint8List.fromList(utf8.encode('build=$buildId\nno-events\n'));
  }

  Future<void> _write(String event) async {
    try {
      final homeDir = await appPath.homeDirPath;
      final logDir = Directory(join(homeDir, 'logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final file = File(join(logDir.path, fileName));
      if (await file.exists() && await file.length() >= _maxBytes) {
        await file.writeAsString('', flush: true);
      }
      await file.writeAsString(
        '[${DateTime.now().toIso8601String()}] $event\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Diagnostics must never affect proxy operation or UI responsiveness.
    }
  }
}

final connectionDiagnostics = ConnectionDiagnostics._();
