import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flclashx/common/log_redaction.dart';
import 'package:flclashx/common/path.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';

class FileLogger {
  factory FileLogger() {
    _instance ??= FileLogger._internal();
    return _instance!;
  }

  FileLogger._internal() : _logsDirOverride = null;
  @visibleForTesting
  FileLogger.forTesting(this._logsDirOverride);
  static FileLogger? _instance;

  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxLogFiles = 7; // Keep 7 days of logs
  static const int maxPendingMessages = 2048;
  static const int maxMessageLength = 16 * 1024;

  IOSink? _currentSink;
  String? _currentLogFilePath;
  String? _currentDate;
  final Queue<String> _writeQueue = Queue<String>();
  int _droppedMessages = 0;
  bool _isWriting = false;
  bool _isBindingInitialized = false;
  Timer? _retryTimer;
  Duration _retryDelay = const Duration(seconds: 1);
  final Future<String> Function()? _logsDirOverride;

  @visibleForTesting
  int get pendingMessageCount => _writeQueue.length;

  @visibleForTesting
  bool get retryScheduled => _retryTimer != null;

  /// Check if Flutter bindings are initialized
  bool _checkBindingInitialized() {
    if (_isBindingInitialized) return true;
    
    try {
      // Try to access WidgetsBinding - this will throw if not initialized
      WidgetsBinding.instance;
      _isBindingInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _getLogsDir() async {
    final override = _logsDirOverride;
    if (override != null) return override();
    final homeDir = await appPath.homeDirPath;
    final logsDir = join(homeDir, 'logs');
    final dir = Directory(logsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return logsDir;
  }

  String _getTodayDate() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String _getLogFileName(String date, {int index = 0}) {
    if (index == 0) {
      return 'FlClashX_$date.log';
    }
    return 'FlClashX_$date\_$index.log';
  }

  Future<void> _rotateLogs() async {
    try {
      final logsDir = await _getLogsDir();
      final dir = Directory(logsDir);

      // Get all log files
      final files = await dir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // Sort by modification time (oldest first)
      files
          .sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      // Remove old files if we exceed max count
      while (files.length > maxLogFiles) {
        final oldestFile = files.removeAt(0);
        try {
          await oldestFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      // Silently fail rotation
    }
  }

  Future<File> _getCurrentLogFile() async {
    final today = _getTodayDate();
    final logsDir = await _getLogsDir();

    // If date changed, close current file and rotate
    if (_currentDate != today || _currentLogFilePath == null) {
      await _closeSink();
      _currentDate = today;
      await _rotateLogs();
    }

    // Find appropriate log file for today
    int index = 0;
    File logFile;

    while (true) {
      final fileName = _getLogFileName(today, index: index);
      final filePath = join(logsDir, fileName);
      logFile = File(filePath);

      // If file doesn't exist or is small enough, use it
      if (!await logFile.exists()) {
        _currentLogFilePath = filePath;
        break;
      }

      final fileSize = await logFile.length();
      if (fileSize < maxFileSizeBytes) {
        _currentLogFilePath = filePath;
        break;
      }

      // File is too large, try next index
      index++;
    }

    return logFile;
  }

  Future<void> _ensureSink() async {
    if (_currentSink == null || _currentLogFilePath == null) {
      final logFile = await _getCurrentLogFile();
      _currentSink = logFile.openWrite(mode: FileMode.append);
    } else {
      // Check if current file is too large
      final currentFile = File(_currentLogFilePath!);
      if (await currentFile.exists()) {
        final fileSize = await currentFile.length();
        if (fileSize >= maxFileSizeBytes) {
          await _closeSink();
          final logFile = await _getCurrentLogFile();
          _currentSink = logFile.openWrite(mode: FileMode.append);
        }
      }
    }
  }

  Future<void> _closeSink() async {
    if (_currentSink != null) {
      try {
        await _currentSink!.flush();
        await _currentSink!.close();
      } catch (_) {}
      _currentSink = null;
    }
  }

  Future<void> _processQueue() async {
    if (_isWriting || _writeQueue.isEmpty || _retryTimer != null) {
      return;
    }

    // Don't try to write to file if bindings aren't initialized yet
    // Messages stay in queue and will be written when bindings are ready
    if (!_checkBindingInitialized()) {
      return;
    }

    _isWriting = true;

    try {
      await _ensureSink();

      if (_droppedMessages > 0) {
        final timestamp =
            DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
        _currentSink?.writeln(
          '[$timestamp] [FileLogger] dropped=$_droppedMessages messages because the write queue was full',
        );
        _droppedMessages = 0;
      }

      while (_writeQueue.isNotEmpty) {
        final message = _writeQueue.removeFirst();
        final timestamp =
            DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
        _currentSink?.writeln('[$timestamp] $message');
      }

      await _currentSink?.flush();
      _retryDelay = const Duration(seconds: 1);
    } catch (e) {
      // Do not spin when the profile directory is temporarily unavailable.
      // Keep the bounded queue and retry with backoff so logging cannot consume
      // a core of CPU while the proxy is starting or the disk is unavailable.
      _retryTimer ??= Timer(_retryDelay, () {
        _retryTimer = null;
        unawaited(_processQueue());
      });
      _retryDelay = Duration(
        milliseconds: (_retryDelay.inMilliseconds * 2).clamp(1000, 30000),
      );
    } finally {
      _isWriting = false;
    }

    // Process remaining items if any were added during write
    if (_writeQueue.isNotEmpty) {
      unawaited(_processQueue());
    }
  }

  void log(String message) {
    final redactedMessage = redactSensitiveLogData(message);
    final boundedMessage = redactedMessage.length > maxMessageLength
        ? '${redactedMessage.substring(0, maxMessageLength)}…'
        : redactedMessage;
    if (_writeQueue.length >= maxPendingMessages) {
      _writeQueue.removeFirst();
      _droppedMessages++;
    }
    _writeQueue.addLast(boundedMessage);
    unawaited(_processQueue());
  }

  /// Call this method after WidgetsFlutterBinding.ensureInitialized()
  /// to flush any queued messages that were logged before bindings were ready
  void flushPendingLogs() {
    if (_writeQueue.isNotEmpty && _checkBindingInitialized()) {
      unawaited(_processQueue());
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _closeSink();
    _writeQueue.clear();
    _droppedMessages = 0;
  }
}

final fileLogger = FileLogger();
