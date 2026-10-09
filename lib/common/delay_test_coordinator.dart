import 'dart:async';

import 'package:flutter/foundation.dart';

class DelayTestTarget {
  const DelayTestTarget(this.name, this.url);
  final String name;
  final String url;
  (String, String) get key => (name, url);
}

class DelayTestResult {
  const DelayTestResult(this.value, {this.reason});
  final int value;
  final String? reason;
}

class DelayBatchResult {
  const DelayBatchResult(
      {required this.completed, required this.failed, this.reason});
  final int completed;
  final int failed;
  final String? reason;
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
  final int concurrency;
  final int maxTargets;
  final Duration requestTimeout;
  final Duration batchTimeout;
  _DelayBatch? _batch;
  final String _session = DateTime.now().microsecondsSinceEpoch.toString();
  int _sequence = 0;
  bool _disposed = false;
  bool get busy => _batch != null;

  Future<DelayBatchResult> run(Iterable<DelayTestTarget> targets) async {
    if (_disposed) throw StateError('Delay coordinator is disposed');
    if (busy)
      return const DelayBatchResult(completed: 0, failed: 0, reason: 'busy');
    final unique = <(String, String), DelayTestTarget>{};
    for (final target in targets) {
      if (target.name.isEmpty) continue;
      unique.putIfAbsent(target.key, () => target);
      if (unique.length > maxTargets) {
        return const DelayBatchResult(
            completed: 0, failed: 0, reason: 'overloaded');
      }
    }
    if (unique.isEmpty) return const DelayBatchResult(completed: 0, failed: 0);
    final batch =
        _DelayBatch(++_sequence, unique.values.toList(growable: false));
    _batch = batch;
    notifyListeners();
    final deadline = Timer(batchTimeout, () {
      unawaited(cancel(reason: 'deadlineExceeded'));
    });
    try {
      await Future.wait(
          List.generate(batch.targets.length.clamp(1, concurrency),
              (_) => _worker(batch)),
          eagerError: true);
      return DelayBatchResult(
          completed: batch.completed,
          failed: batch.failed,
          reason: batch.reason);
    } catch (_) {
      await cancel(reason: 'clientFailure');
      rethrow;
    } finally {
      deadline.cancel();
      if (identical(_batch, batch)) _batch = null;
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
          onResult(target, result);
          if (const {
            'configChanged',
            'sessionClosed',
            'uiInactive',
            'transportFailure'
          }.contains(result.reason)) {
            batch.active.remove(id);
            await cancel(reason: result.reason!);
          }
        }
      } finally {
        timeout.cancel();
        batch.active.remove(id);
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
    super.dispose();
  }
}
