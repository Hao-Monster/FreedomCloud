import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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

  FileLogger._internal()
      : _logsDirOverride = null,
        _now = DateTime.now,
        _fileSizeLimit = maxFileSizeBytes,
        _fileCountLimit = maxLogFiles,
        _deleteFile = _deleteOwnedFile;
  @visibleForTesting
  FileLogger.forTesting(
    this._logsDirOverride, {
    DateTime Function()? now,
    int fileSizeLimit = maxFileSizeBytes,
    int fileCountLimit = maxLogFiles,
    Future<void> Function(File)? deleteFile,
  })  : _now = now ?? DateTime.now,
        _fileSizeLimit = fileSizeLimit,
        _fileCountLimit = fileCountLimit,
        _deleteFile = deleteFile ?? _deleteOwnedFile,
        assert(fileSizeLimit > 0, 'File size limit must be positive'),
        assert(fileCountLimit > 0, 'File count limit must be positive');
  static FileLogger? _instance;

  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxLogFiles = 7; // Includes same-day rollover files.
  static const int maxPendingMessages = 2048;
  static const int maxMessageLength = 16 * 1024;

  IOSink? _currentSink;
  String? _currentLogFilePath;
  String? _currentDate;
  int _currentBytes = 0;
  final Queue<String> _writeQueue = Queue<String>();
  int _droppedMessages = 0;
  bool _isWriting = false;
  bool _disposing = false;
  Completer<void>? _writerDone;
  bool _isBindingInitialized = false;
  Timer? _retryTimer;
  Duration _retryDelay = const Duration(seconds: 1);
  final Future<String> Function()? _logsDirOverride;
  final DateTime Function() _now;
  final int _fileSizeLimit;
  final int _fileCountLimit;
  final Future<void> Function(File) _deleteFile;

  @visibleForTesting
  int get pendingMessageCount => _writeQueue.length;

  @visibleForTesting
  bool get retryScheduled => _retryTimer != null;

  @visibleForTesting
  Future<void> get pendingWrites => _writerDone?.future ?? Future.value();

  static Future<void> _deleteOwnedFile(File file) async {
    await file.delete();
  }

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

  String _getTodayDate() => DateFormat('yyyy-MM-dd').format(_now());

  String _getLogFileName(String date, {int index = 0}) {
    if (index == 0) {
      return 'FlClashX_$date.log';
    }
    return 'FlClashX_${date}_$index.log';
  }

  Future<void> _rotateLogs(
    String keepPath, {
    required bool reserveNew,
    required int fileCapacity,
    required int currentSize,
  }) async {
    final logsDir = await _getLogsDir();
    final dir = Directory(logsDir);
    final ownedName = RegExp(r'^FlClashX_\d{4}-\d{2}-\d{2}(?:_\d+)?\.log$');

    // Get all log files
    final files = await dir
        .list()
        .where((entity) =>
            entity is File && ownedName.hasMatch(basename(entity.path)))
        .cast<File>()
        .toList();

    final stats = {for (final file in files) file.path: file.statSync()};
    files.sort(
        (a, b) => stats[a.path]!.modified.compareTo(stats[b.path]!.modified));

    // Reserve the whole current file's remaining capacity, so future buffered
    // appends stay within the total budget without scanning on every line.
    // Legacy versions could leave oversized files; count alone cannot bound it.
    final limit = _fileCountLimit - (reserveNew ? 1 : 0);
    final extraBytes = fileCapacity - currentSize;
    var retainedBytes =
        stats.values.fold<int>(0, (sum, stat) => sum + stat.size);
    while (files.length > limit ||
        retainedBytes + extraBytes > fileCapacity * _fileCountLimit) {
      final index = files.indexWhere((file) => file.path != keepPath);
      if (index == -1) {
        throw const FileSystemException('No owned log can be rotated');
      }
      final oldestFile = files.removeAt(index);
      // A failed delete prevents another file being created. The writer's
      // bounded backoff retries without growing an unbounded disk backlog.
      await _deleteFile(oldestFile);
      retainedBytes -= stats[oldestFile.path]!.size;
    }
  }

  Future<File> _getCurrentLogFile(int nextLineBytes) async {
    final today = _getTodayDate();
    final logsDir = await _getLogsDir();
    final capacity =
        nextLineBytes > _fileSizeLimit ? nextLineBytes : _fileSizeLimit;

    // If date changed, close current file and rotate
    if (_currentDate != today || _currentLogFilePath == null) {
      await _closeSink();
      _currentDate = today;
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
        await _rotateLogs(filePath,
            reserveNew: true, fileCapacity: capacity, currentSize: 0);
        _currentLogFilePath = filePath;
        _currentBytes = 0;
        break;
      }

      final fileSize = await logFile.length();
      if (fileSize == 0 || fileSize + nextLineBytes <= _fileSizeLimit) {
        await _rotateLogs(filePath,
            reserveNew: false, fileCapacity: capacity, currentSize: fileSize);
        _currentLogFilePath = filePath;
        _currentBytes = fileSize;
        break;
      }

      // File is too large, try next index
      index++;
    }

    return logFile;
  }

  Future<void> _ensureSink(int nextLineBytes) async {
    if (_currentDate != _getTodayDate()) {
      await _closeSink();
      _currentLogFilePath = null;
    }
    // Count bytes accepted by the sink, including buffered data. Checking the
    // on-disk length once per queue drain allowed one busy batch to grow far
    // beyond the file limit before its buffer was flushed.
    if (_currentBytes > 0 && _currentBytes + nextLineBytes > _fileSizeLimit) {
      await _closeSink();
    }
    if (_currentSink == null || _currentLogFilePath == null) {
      final logFile = await _getCurrentLogFile(nextLineBytes);
      _currentSink = logFile.openWrite(mode: FileMode.append);
    }
  }

  Future<void> _writeLine(String message) async {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(_now());
    final bytes = utf8.encode('[$timestamp] $message\n');
    await _ensureSink(bytes.length);
    _currentSink!.add(bytes);
    _currentBytes += bytes.length;
  }

  Future<void> _closeSink() async {
    final sink = _currentSink;
    _currentSink = null;
    if (sink != null) {
      try {
        await sink.flush();
      } finally {
        await sink.close();
      }
    }
  }

  Future<void> _processQueue() async {
    if (_disposing ||
        _isWriting ||
        _writeQueue.isEmpty ||
        _retryTimer != null) {
      return;
    }

    // Don't try to write to file if bindings aren't initialized yet
    // Messages stay in queue and will be written when bindings are ready
    if (!_checkBindingInitialized()) {
      return;
    }

    _isWriting = true;
    final writerDone = Completer<void>();
    _writerDone = writerDone;

    try {
      if (_droppedMessages > 0) {
        await _writeLine(
          '[FileLogger] dropped=$_droppedMessages messages because the write queue was full',
        );
        _droppedMessages = 0;
      }

      while (_writeQueue.isNotEmpty) {
        final message = _writeQueue.removeFirst();
        try {
          await _writeLine(message);
        } catch (_) {
          if (_writeQueue.length < maxPendingMessages) {
            _writeQueue.addFirst(message);
          } else {
            _droppedMessages++;
          }
          rethrow;
        }
      }

      await _currentSink?.flush();
      _retryDelay = const Duration(seconds: 1);
    } catch (e) {
      final code = e is FileSystemException ? e.osError?.errorCode : null;
      debugPrint(
          '[FileLogger] write/rotation failed: ${e.runtimeType} code=$code');
      try {
        await _closeSink();
      } catch (_) {
        // The failed sink is already detached; retry opens a fresh one.
      }
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
      _writerDone = null;
      writerDone.complete();
    }

    // Process remaining items if any were added during write
    if (_writeQueue.isNotEmpty) {
      unawaited(_processQueue());
    }
  }

  void log(String message) {
    if (_disposing) return;
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
    _disposing = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    try {
      await _writerDone?.future;
      await _closeSink();
    } finally {
      _retryTimer?.cancel();
      _retryTimer = null;
      _writeQueue.clear();
      _droppedMessages = 0;
      _disposing = false;
    }
  }
}

final fileLogger = FileLogger();
