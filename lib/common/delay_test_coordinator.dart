import 'dart:async';

import 'package:flutter/foundation.dart';

class DelayTestTarget {
  const DelayTestTarget(this.name, this.url, {this.scope, this.nodeIndex});
  final String name;
  final String url;
  final String? scope;
  final int? nodeIndex;
  (String, String, String) get key => (scope ?? '', name, url);
}

class DelayTestResult {
  const DelayTestResult(this.value, {this.reason});
  final int value;
  final String? reason;
}

/// Fixed reason codes only; parser, transport and filesystem text must never
/// escape through the batch summary.
class DelayBatchIssue {
  const DelayBatchIssue(
      {required this.profileId, required this.reason, this.count = 0});
  final String profileId;
  final String reason;
  final int count;
}

class DelayBatchResult {
  const DelayBatchResult(
      {required this.completed,
      required this.failed,
      this.reason,
      this.untested = 0,
      this.issues = const []});
  final int completed;
  final int failed;
  final String? reason;
  final int untested;
  final List<DelayBatchIssue> issues;
}

typedef RunDelayTest = Future<DelayTestResult> Function(
    DelayTestTarget target, String requestId, Duration timeout);

class _DelayBatch {
  _DelayBatch(this.id, this.targets);
  final int id;
  final List<DelayTestTarget> targets;
  final cancelled = Completer<void>();
  final active = <String, DelayTestTarget>{};
  int next = 0;
  int completed = 0;
  int failed = 0;
  int untested = 0;
  String? reason;
}

/// One budget shared by single-node, group, all-groups and tray entry points.
/// Waiting entries are data, not already-started Futures. Cancellation severs UI
/// result ownership immediately and asks Core to end every active request.
class DelayTestCoordinator extends ChangeNotifier {
  DelayTestCoordinator({
    required this.test,
    required this.cancelRequest,
    required this.onStarted,
    required this.onResult,
    this.onDisposed,
    this.concurrency = 10,
    this.maxTargets = 10000,
    this.requestTimeout = const Duration(seconds: 5),
    this.batchTimeout = const Duration(seconds: 30),
  })  : assert(concurrency > 0, 'Concurrency must be positive'),
        assert(maxTargets > 0, 'Target budget must be positive'),
        assert(
            requestTimeout > Duration.zero, 'Request timeout must be positive'),
        assert(batchTimeout > Duration.zero, 'Batch timeout must be positive');

  final RunDelayTest test;
  final Future<void> Function(String requestId) cancelRequest;
  final void Function(DelayTestTarget target) onStarted;
  final void Function(DelayTestTarget target, DelayTestResult result) onResult;
  final VoidCallback? onDisposed;
  final int concurrency;
  final int maxTargets;
  final Duration requestTimeout;
  final Duration batchTimeout;
  _DelayBatch? _batch;
  final String _session = DateTime.now().microsecondsSinceEpoch.toString();
  int _sequence = 0;
  bool _disposed = false;
  int _lastTotal = 0;
  int _lastCompleted = 0;
  bool get busy => _batch != null;
  int? get activeBatchId => _batch?.id;
  int get total => _batch?.targets.length ?? _lastTotal;
  int get completed => _batch?.completed ?? _lastCompleted;
  List<DelayTestTarget> get activeTargets =>
      List.unmodifiable(_batch?.active.values ?? const <DelayTestTarget>[]);

  Future<DelayBatchResult> run(Iterable<DelayTestTarget> targets,
      {Duration? batchTimeout}) async {
    if (_disposed) throw StateError('Delay coordinator is disposed');
    if (busy)
      return const DelayBatchResult(completed: 0, failed: 0, reason: 'busy');
    final deadlineDuration = batchTimeout ?? this.batchTimeout;
    if (deadlineDuration <= Duration.zero) {
      throw ArgumentError('Batch timeout must be positive');
    }
    final unique = <(String, String, String), DelayTestTarget>{};
    for (final target in targets) {
      if (target.name.isEmpty) continue;
      unique.putIfAbsent(target.key, () => target);
      if (unique.length > maxTargets) {
        return const DelayBatchResult(
            completed: 0, failed: 0, reason: 'overloaded');
      }
    }
    if (unique.isEmpty) {
      _lastTotal = 0;
      _lastCompleted = 0;
      return const DelayBatchResult(completed: 0, failed: 0);
    }
    final batch =
        _DelayBatch(++_sequence, unique.values.toList(growable: false));
    _batch = batch;
    notifyListeners();
    final deadline = Timer(deadlineDuration, () {
      // The batch budget may expire before an individual request's deadline.
      // Do not turn that scheduling decision into a failed node measurement.
      unawaited(cancel(reason: 'batchDeadlineExceeded'));
    });
    try {
      await Future.wait(
          List.generate(batch.targets.length.clamp(1, concurrency),
              (_) => _worker(batch)),
          eagerError: true);
      return DelayBatchResult(
          completed: batch.completed,
          failed: batch.failed,
          untested: batch.untested,
          reason: batch.reason);
    } catch (_) {
      await cancel(reason: 'clientFailure');
      rethrow;
    } finally {
      deadline.cancel();
      if (identical(_batch, batch)) {
        _lastTotal = batch.targets.length;
        _lastCompleted = batch.completed;
        _batch = null;
      }
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _worker(_DelayBatch batch) async {
    while (!batch.cancelled.isCompleted && batch.next < batch.targets.length) {
      final index = batch.next++;
      final target = batch.targets[index];
      final id = 'delay-$_session-${batch.id}-$index';
      batch.active[id] = target;
      final completion = Completer<DelayTestResult>();
      final timeout = Timer(requestTimeout, () {
        if (!completion.isCompleted) {
          completion
              .complete(const DelayTestResult(-1, reason: 'deadlineExceeded'));
          unawaited(_cancelRemote(id));
        }
      });
      try {
        onStarted(target);
        if (!_disposed) notifyListeners();
        if (batch.cancelled.isCompleted || _disposed) continue;
        unawaited(
            Future<DelayTestResult>.sync(() => test(target, id, requestTimeout))
                .then<void>(
          (result) {
            if (!completion.isCompleted) completion.complete(result);
          },
          onError: (Object _) {
            if (!completion.isCompleted)
              completion.complete(
                  const DelayTestResult(-1, reason: 'transportFailure'));
          },
        ));
        final result = await Future.any([
          completion.future,
          batch.cancelled.future
              .then((_) => const DelayTestResult(-1, reason: 'cancelled')),
        ]);
        if (identical(_batch, batch) &&
            !batch.cancelled.isCompleted &&
            !_disposed) {
          batch.completed++;
          if (result.value < 0) batch.failed++;
          if (target.scope != null &&
              result.value < 0 &&
              !const {'testFailed', 'deadlineExceeded'}
                  .contains(result.reason)) {
            batch.untested++;
          }
          onResult(target, result);
          if (const {
                'configChanged',
                'sessionClosed',
                'uiInactive',
                'transportFailure'
              }.contains(result.reason) ||
              (target.scope != null &&
                  const {
                    'catalogNotFound',
                    'coreUnavailable',
                    'strictModeUnsupported',
                    'overloaded',
                    'invalidParameters',
                    'invalidResponse',
                    'duplicateRequest',
                    'clientFailure',
                    'unknown',
                  }.contains(result.reason))) {
            batch.active.remove(id);
            await cancel(reason: result.reason!);
          }
        }
      } finally {
        timeout.cancel();
        batch.active.remove(id);
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _cancelRemote(String id) async {
    try {
      await cancelRequest(id).timeout(const Duration(seconds: 1));
    } catch (_) {
      // Local result ownership is already revoked. Core also enforces its own
      // deadline, including queued work, if the transport is unavailable.
    }
  }

  Future<void> cancel({String reason = 'cancelled'}) async {
    final batch = _batch;
    if (batch == null || batch.cancelled.isCompleted) return;
    batch.reason = reason;
    final active = Map<String, DelayTestTarget>.of(batch.active);
    batch.cancelled.complete();
    try {
      if (!_disposed) {
        for (final target in active.values) {
          onResult(target, DelayTestResult(-1, reason: reason));
        }
      }
    } finally {
      await Future.wait(active.keys.map(_cancelRemote));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    try {
      onDisposed?.call();
    } finally {
      super.dispose();
    }
  }
}
