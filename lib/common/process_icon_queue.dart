import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// One consumer of an icon job. Releasing a lease never interrupts native work;
/// it only removes this consumer and cancels work that has not started.
class ProcessIconLease<V extends Object> {
  ProcessIconLease._();

  final _result = Completer<V?>();
  VoidCallback? _release;

  Future<V?> get future => _result.future;

  void release() {
    final release = _release;
    _release = null;
    release?.call();
    _complete(null);
  }

  void _complete(V? value) {
    _release = null;
    if (!_result.isCompleted) _result.complete(value);
  }
}

class _IconJob<V extends Object> {
  _IconJob(this.key, this.source);

  final String key;
  final String source;
  final consumers = <ProcessIconLease<V>>{};
}

/// A bounded, keyed icon loader. Listeners are notified when admission may be
/// possible; rejected requests are not retained in another waiting queue.
class ProcessIconQueue<V extends Object> extends ChangeNotifier {
  ProcessIconQueue({
    required Future<V?> Function(String source) load,
    this.maxWaiting = 64,
    this.maxCached = 64,
    this.negativeCacheTtl = Duration.zero,
    DateTime Function()? now,
    void Function(V value)? onEvict,
  })  : assert(maxWaiting >= 0, 'Waiting capacity must not be negative'),
        assert(maxCached > 0, 'Cache capacity must be positive'),
        assert(!negativeCacheTtl.isNegative,
            'Negative cache TTL must not be negative'),
        _load = load,
        _now = now ?? DateTime.now,
        _onEvict = onEvict;

  static const _maxNegativeCached = 128;

  final int maxWaiting;
  final int maxCached;
  final Duration negativeCacheTtl;
  final Future<V?> Function(String source) _load;
  final DateTime Function() _now;
  final void Function(V value)? _onEvict;
  final _jobs = <String, _IconJob<V>>{};
  final _waiting = ListQueue<_IconJob<V>>();
  final _cache = <String, V>{};
  final _negativeCache = <String, DateTime>{};
  _IconJob<V>? _active;
  bool _notificationScheduled = false;
  bool _disposed = false;

  int get waitingCount => _waiting.length;
  int get activeCount => _active == null ? 0 : 1;
  int get cachedCount => _cache.length;

  void clearNegativeCache() {
    _negativeCache.clear();
  }

  /// Null means retry later, not a negative icon result. The caller owns any
  /// capacity listener and must remove it when no longer interested.
  ProcessIconLease<V>? acquire(String key, {String? source}) {
    if (_disposed) throw StateError('Process icon queue is disposed');
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return ProcessIconLease<V>._().._complete(cached);
    }
    if (negativeCacheTtl > Duration.zero) {
      final expiresAt = _negativeCache[key];
      if (expiresAt != null) {
        if (_now().isBefore(expiresAt)) {
          return ProcessIconLease<V>._().._complete(null);
        }
        _negativeCache.remove(key);
      }
    }
    final existing = _jobs[key];
    if (existing != null) return _attach(existing);
    if (_active != null && _waiting.length >= maxWaiting) return null;

    final job = _IconJob<V>(key, source ?? key);
    _jobs[key] = job;
    final lease = _attach(job);
    if (_active == null) {
      _start(job);
    } else {
      _waiting.addLast(job);
    }
    return lease;
  }

  ProcessIconLease<V> _attach(_IconJob<V> job) {
    final lease = ProcessIconLease<V>._();
    job.consumers.add(lease);
    lease._release = () {
      job.consumers.remove(lease);
      if (job.consumers.isEmpty && !identical(_active, job)) {
        _waiting.remove(job);
        if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
        _notifyCapacity();
      }
    };
    return lease;
  }

  void _start(_IconJob<V> job) {
    // Reserve the slot synchronously, but never enter Win32 during widget build.
    _active = job;
    scheduleMicrotask(() => unawaited(_run(job)));
  }

  Future<void> _run(_IconJob<V> job) async {
    V? value;
    var attempted = false;
    var failed = false;
    try {
      if (!_disposed && job.consumers.isNotEmpty) {
        attempted = true;
        value = await _load(job.source);
      }
    } catch (_) {
      failed = true;
      // Icon lookup is best effort. A failure belongs to this attempt and must
      // neither poison the queue nor become a permanent negative cache entry.
    } finally {
      _jobs.remove(job.key);
      if (!_disposed && job.consumers.isNotEmpty) {
        if (value != null) {
          _negativeCache.remove(job.key);
          _cache[job.key] = value;
          if (_cache.length > maxCached) {
            final oldest = _cache.remove(_cache.keys.first)!;
            _onEvict?.call(oldest);
          }
        } else if (attempted && !failed && negativeCacheTtl > Duration.zero) {
          _negativeCache.remove(job.key);
          if (_negativeCache.length >= _maxNegativeCached) {
            _negativeCache.remove(_negativeCache.keys.first);
          }
          _negativeCache[job.key] = _now().add(negativeCacheTtl);
        }
      }
      for (final lease in job.consumers) {
        lease._complete(value);
      }
      job.consumers.clear();

      // Yield between native extractions. Keep the slot until actual work has
      // returned; cancellation must not start overlapping Win32/codec work.
      await Future<void>.delayed(Duration.zero);
      _active = null;
      if (!_disposed) {
        if (_waiting.isNotEmpty) _start(_waiting.removeFirst());
        _notifyCapacity();
      }
    }
  }

  void _notifyCapacity() {
    if (_disposed || _notificationScheduled) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _jobs.values) {
      for (final lease in job.consumers) {
        lease._complete(null);
      }
      job.consumers.clear();
    }
    _jobs.clear();
    _waiting.clear();
    for (final value in _cache.values) {
      _onEvict?.call(value);
    }
    _cache.clear();
    _negativeCache.clear();
    super.dispose();
  }
}
