import 'dart:async';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/connection_diagnostics.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/foundation.dart';

typedef ConnectionSnapshotLoader = Future<ConnectionSnapshot> Function();
typedef CloseConnectionCallback = Future<bool> Function(String id);
typedef CloseConnectionsCallback = Future<bool> Function();
typedef ConnectionDiagnosticLogger = void Function(String event);

Future<ConnectionSnapshot> _defaultLoadSnapshot() =>
    clashCore.getConnectionsSnapshot();

Future<bool> _defaultCloseConnection(String id) =>
    clashCore.closeConnectionAndWait(id);

Future<bool> _defaultCloseConnections() => clashCore.closeConnectionsAndWait();

class ConnectionManager extends ChangeNotifier {
  ConnectionManager({
    ConnectionTracker? tracker,
    ConnectionSnapshotLoader? loadSnapshot,
    CloseConnectionCallback? closeConnection,
    CloseConnectionsCallback? closeConnections,
    ConnectionDiagnosticLogger? diagnosticLog,
    DateTime Function()? now,
  })  : _tracker = tracker ?? ConnectionTracker(),
        _loadSnapshot = loadSnapshot ?? _defaultLoadSnapshot,
        _closeConnection = closeConnection ?? _defaultCloseConnection,
        _closeConnections = closeConnections ?? _defaultCloseConnections,
        _diagnosticLog = diagnosticLog ?? connectionDiagnostics.log,
        _now = now ?? DateTime.now;

  final ConnectionTracker _tracker;
  final ConnectionSnapshotLoader _loadSnapshot;
  final CloseConnectionCallback _closeConnection;
  final CloseConnectionsCallback _closeConnections;
  final ConnectionDiagnosticLogger _diagnosticLog;
  final DateTime Function() _now;
  Timer? _timer;
  ConnectionSnapshot? _pausedSnapshot;
  Duration _interval = const Duration(milliseconds: 500);
  bool _running = false;
  bool _paused = false;
  bool _polling = false;
  bool _disposed = false;
  bool _loading = false;
  int _generation = 0;
  Object? _error;
  DateTime? _lastUpdatedAt;
  num _downloadTotal = 0;
  num _uploadTotal = 0;
  num _memory = 0;
  int _pollCount = 0;
  bool? _lastSnapshotWasEmpty;
  DateTime? _lastDiagnosticAt;
  String? _lastErrorType;

  bool get running => _running;
  bool get paused => _paused;
  bool get loading => _loading;
  Object? get error => _error;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  Duration get interval => _interval;
  num get downloadTotal => _downloadTotal;
  num get uploadTotal => _uploadTotal;
  num get memory => _memory;
  List<TrackedConnection> get activeConnections => _tracker.activeConnections;
  List<TrackedConnection> get closedConnections => _tracker.closedConnections;
  List<ProcessConnectionGroup> get processGroups => _tracker.processGroups;

  void configure({required bool running, required int refreshIntervalMs}) {
    final nextInterval = Duration(
      milliseconds: refreshIntervalMs.clamp(100, 10000),
    );
    final intervalChanged = nextInterval != _interval;
    final runningChanged = running != _running;
    _interval = nextInterval;
    if (runningChanged || intervalChanged) {
      _diagnosticLog(
        '[ConnectionsDiag] manager.configure '
        'running=$running runningChanged=$runningChanged '
        'intervalMs=${nextInterval.inMilliseconds}',
      );
    }
    if (runningChanged) {
      _setRunning(running);
    } else if (running && intervalChanged) {
      _schedule(const Duration(milliseconds: 1));
    }
  }

  void setPaused({required bool paused}) {
    if (_paused == paused) return;
    _paused = paused;
    _diagnosticLog(
      '[ConnectionsDiag] manager.pause paused=$paused '
      'active=${_tracker.activeConnections.length}',
    );
    if (!paused && _pausedSnapshot != null) {
      _tracker.ingest(
        _pausedSnapshot!,
        sampledAt: _now(),
        calculateSpeed: false,
      );
      _pausedSnapshot = null;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    _diagnosticLog(
      '[ConnectionsDiag] manager.manualRefresh '
      'running=$_running polling=$_polling',
    );
    if (!_running || _polling) return;
    _timer?.cancel();
    await _poll(_generation);
  }

  Future<void> closeConnection(String id) async {
    await _closeConnection(id);
    await refresh();
  }

  Future<void> closeConnections([Iterable<String>? ids]) async {
    if (ids == null) {
      await _closeConnections();
    } else {
      final uniqueIds = ids.toSet().toList(growable: false);
      const batchSize = 16;
      for (var offset = 0; offset < uniqueIds.length; offset += batchSize) {
        final end = (offset + batchSize).clamp(0, uniqueIds.length);
        await Future.wait(
          uniqueIds.sublist(offset, end).map(_closeConnection),
        );
      }
    }
    await refresh();
  }

  void clearClosed() {
    _tracker.clearClosed();
    notifyListeners();
  }

  void removeClosed(String id) {
    _tracker.removeClosed(id);
    notifyListeners();
  }

  void _setRunning(bool value) {
    if (_running == value) return;
    _running = value;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pausedSnapshot = null;
    _diagnosticLog(
      '[ConnectionsDiag] manager.running value=$value '
      'generation=$_generation activeBefore=${_tracker.activeConnections.length}',
    );
    if (value) {
      _loading = _tracker.activeConnections.isEmpty;
      _schedule(Duration.zero);
    } else {
      _loading = false;
      _error = null;
      _tracker.markAllClosed(closedAt: _now());
      notifyListeners();
    }
  }

  void _schedule(Duration delay) {
    if (!_running || _disposed) return;
    _timer?.cancel();
    final generation = _generation;
    _timer = Timer(delay, () => unawaited(_poll(generation)));
  }

  Future<void> _poll(int generation) async {
    if (!_running || _disposed || generation != _generation || _polling) return;
    _polling = true;
    final pollNumber = ++_pollCount;
    final stopwatch = Stopwatch()..start();
    try {
      final snapshot = await _loadSnapshot();
      if (!_running || _disposed || generation != _generation) return;
      final sampledAt = _now();
      _downloadTotal = snapshot.downloadTotal;
      _uploadTotal = snapshot.uploadTotal;
      _memory = snapshot.memory;
      if (_paused) {
        _pausedSnapshot = snapshot;
      } else {
        _tracker.ingest(snapshot, sampledAt: sampledAt);
      }
      _lastUpdatedAt = sampledAt;
      _loading = false;
      _error = null;
      _lastErrorType = null;
      _logSuccessfulPoll(
        pollNumber: pollNumber,
        snapshot: snapshot,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      notifyListeners();
    } catch (error) {
      if (!_running || _disposed || generation != _generation) return;
      _loading = false;
      _error = error;
      _logFailedPoll(
        pollNumber: pollNumber,
        errorType: error.runtimeType.toString(),
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      notifyListeners();
    } finally {
      _polling = false;
      if (_running && !_disposed && generation == _generation) {
        _schedule(_interval);
      }
    }
  }

  void _logSuccessfulPoll({
    required int pollNumber,
    required ConnectionSnapshot snapshot,
    required int elapsedMilliseconds,
  }) {
    final now = DateTime.now();
    final isEmpty = snapshot.connections.isEmpty;
    final shouldLog = pollNumber <= 3 ||
        _lastSnapshotWasEmpty != isEmpty ||
        _lastDiagnosticAt == null ||
        now.difference(_lastDiagnosticAt!) >= const Duration(seconds: 30);
    _lastSnapshotWasEmpty = isEmpty;
    if (!shouldLog) return;
    _lastDiagnosticAt = now;
    _diagnosticLog(
      '[ConnectionsDiag] manager.poll status=ok poll=$pollNumber '
      'durationMs=$elapsedMilliseconds sourceConnections=${snapshot.connections.length} '
      'active=${_tracker.activeConnections.length} '
      'groups=${_tracker.processGroups.length} paused=$_paused',
    );
  }

  void _logFailedPoll({
    required int pollNumber,
    required String errorType,
    required int elapsedMilliseconds,
  }) {
    final now = DateTime.now();
    final shouldLog = pollNumber <= 3 ||
        _lastErrorType != errorType ||
        _lastDiagnosticAt == null ||
        now.difference(_lastDiagnosticAt!) >= const Duration(seconds: 30);
    _lastErrorType = errorType;
    if (!shouldLog) return;
    _lastDiagnosticAt = now;
    _diagnosticLog(
      '[ConnectionsDiag] manager.poll status=error poll=$pollNumber '
      'durationMs=$elapsedMilliseconds errorType=$errorType',
    );
  }

  @override
  void dispose() {
    _diagnosticLog(
      '[ConnectionsDiag] manager.dispose running=$_running '
      'polls=$_pollCount active=${_tracker.activeConnections.length}',
    );
    _disposed = true;
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

final connectionManager = ConnectionManager();
