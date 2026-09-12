// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/common/file_logger.dart';
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
  static const _maxPendingEvents = 512;
  static const _maxEventChars = 2048;

  final Queue<String> _pendingEvents = Queue<String>();
  Future<void>? _writerFuture;
  bool _isWriting = false;
  int _droppedEvents = 0;

  void log(String event) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final singleLine = event.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final boundedEvent = singleLine.length > _maxEventChars
        ? '${singleLine.substring(0, _maxEventChars)}…'
        : singleLine;
    if (_pendingEvents.length >= _maxPendingEvents) {
      _pendingEvents.removeFirst();
      _droppedEvents++;
    }
    _pendingEvents.addLast(boundedEvent);
    _startWriter();
  }

  /// Returns only the privacy-safe connection pipeline log. It intentionally
  /// excludes profiles, hosts, process paths and the general application log.
  Future<Uint8List> exportBytes() async {
    while (_writerFuture != null) {
      await _writerFuture;
    }
    try {
      final homeDir = await appPath.homeDirPath;
      final file = File(join(homeDir, 'logs', fileName));
      if (await file.exists()) return file.readAsBytes();
    } catch (_) {
      // Export remains useful even when the diagnostic directory is missing.
    }
    return Uint8List.fromList(utf8.encode('build=$buildId\nno-events\n'));
  }

  void _startWriter() {
    if (_isWriting || (_pendingEvents.isEmpty && _droppedEvents == 0)) {
      return;
    }
    _isWriting = true;
    final writer = _processQueue();
    _writerFuture = writer;
    unawaited(writer.whenComplete(() {
      if (identical(_writerFuture, writer)) {
        _writerFuture = null;
      }
    }));
  }

  Future<void> _processQueue() async {
    try {
      while (_pendingEvents.isNotEmpty || _droppedEvents > 0) {
        if (_droppedEvents > 0) {
          final dropped = _droppedEvents;
          _droppedEvents = 0;
          await _write(
            'dropped=$dropped events because the diagnostic queue was full',
          );
        }
        if (_pendingEvents.isNotEmpty) {
          await _write(_pendingEvents.removeFirst());
        }
      }
    } finally {
      _isWriting = false;
      _startWriter();
    }
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
    } catch (error) {
      // Diagnostics must never affect proxy operation or UI responsiveness.
      fileLogger.log(
        '[ConnectionDiagnostics] write failed: ${error.runtimeType}',
      );
    }
  }
}

final connectionDiagnostics = ConnectionDiagnostics._();
