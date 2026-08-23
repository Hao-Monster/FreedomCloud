// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:io';

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
