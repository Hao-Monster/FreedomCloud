import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/common/process_icon_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void drain(FakeAsync clock) {
  clock.flushMicrotasks();
  clock.elapse(Duration.zero);
  clock.flushMicrotasks();
}

void main() {
  test('130 distinct keys admit one running and only 64 waiting jobs', () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      final calls = <String>[];
      final queue = ProcessIconQueue<String>(load: (key) {
        calls.add(key);
        return first.future;
      });
      final leases = [for (var i = 0; i < 130; i++) queue.acquire('$i')];
      expect(leases.whereType<ProcessIconLease<String>>(), hasLength(65));
      expect(leases.where((lease) => lease == null), hasLength(65));
      expect(queue.activeCount, 1);
      expect(queue.waitingCount, 64);
      drain(clock);
      expect(calls, ['0']);

      // Even a full queue must share an existing in-flight key.
      final duplicate = queue.acquire('0');
      expect(duplicate, isNotNull);
      expect(queue.waitingCount, 64);
      for (final lease in leases) {
        lease?.release();
      }
      duplicate!.release();
      first.complete('stale');
      drain(clock);
      expect(calls, ['0']);
      expect(queue.activeCount, 0);
      expect(queue.waitingCount, 0);
      expect(queue.cachedCount, 0);
      queue.dispose();
    });
  });

  test('only the last queued consumer cancels extraction', () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      final calls = <String>[];
      final queue = ProcessIconQueue<String>(load: (key) async {
        calls.add(key);
        return key == 'first' ? first.future : key;
      });
      queue.acquire('first');
      final a = queue.acquire('shared')!;
      final b = queue.acquire('shared')!;
      final cancelled = queue.acquire('cancelled')!;
      a.release();
      a.release();
      cancelled.release();
      expect(queue.waitingCount, 1);
      Object? bValue;
      unawaited(b.future.then((value) => bValue = value));
      first.complete('first');
      drain(clock);
      expect(calls, ['first', 'shared']);
      expect(bValue, 'shared');
      expect(queue.waitingCount, 0);
      queue.dispose();
    });
  });

  test('cancelled running work retains its slot until its actual return', () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      final calls = <String>[];
      final queue = ProcessIconQueue<String>(load: (key) async {
        calls.add(key);
        return calls.length == 1 ? first.future : key;
      });
      final old = queue.acquire('old')!;
      drain(clock);
      old.release();
      queue.acquire('new');
      drain(clock);
      expect(calls, ['old']);
      expect(queue.activeCount, 1);
      first.complete('old icon');
      drain(clock);
      expect(calls, ['old', 'new']);
      queue.acquire('old');
      drain(clock);
      expect(calls, ['old', 'new', 'old'],
          reason: 'An abandoned result must not become a cached success');
      queue.dispose();
    });
  });

  test('a new consumer can rejoin running work after the old one leaves', () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      var calls = 0;
      final queue = ProcessIconQueue<String>(load: (_) {
        calls++;
        return first.future;
      });
      final old = queue.acquire('same')!;
      drain(clock);
      old.release();
      final current = queue.acquire('same')!;
      Object? value;
      unawaited(current.future.then((result) => value = result));
      first.complete('icon');
      drain(clock);
      expect(calls, 1);
      expect(value, 'icon');
      queue.dispose();
    });
  });

  test(
      'success cache is bounded, recently used entries survive, eviction retries',
      () {
    fakeAsync((clock) {
      final calls = <String>[];
      final evicted = <String>[];
      final queue = ProcessIconQueue<String>(
        load: (key) async {
          calls.add(key);
          return key;
        },
        onEvict: evicted.add,
      );
      for (var i = 0; i < 150; i++) {
        queue.acquire('$i');
        drain(clock);
      }
      expect(queue.cachedCount, 64);
      expect(evicted, [for (var i = 0; i < 86; i++) '$i']);
      queue.acquire('86'); // Touch the oldest surviving value.
      queue.acquire('150');
      drain(clock);
      expect(evicted.last, '87');
      expect(calls, hasLength(151));
      queue.acquire('0');
      drain(clock);
      expect(calls.last, '0');
      expect(calls, hasLength(152));
      queue.dispose();
      expect(evicted, hasLength(152));
    });
  });

  test(
      'null and synchronous/asynchronous failure do not poison or negative-cache',
      () {
    fakeAsync((clock) {
      var attempts = 0;
      final queue = ProcessIconQueue<String>(load: (_) {
        attempts++;
        if (attempts == 1) return Future.value(null);
        if (attempts == 2) throw StateError('sync extraction failure');
        if (attempts == 3) return Future.error(StateError('async failure'));
        return Future.value('recovered');
      });
      final results = <String?>[];
      for (var i = 0; i < 4; i++) {
        unawaited(queue.acquire('retry')!.future.then(results.add));
        drain(clock);
      }
      expect(results, [null, null, null, 'recovered']);
      expect(attempts, 4);
      expect(queue.cachedCount, 1);
      queue.dispose();
    });
  });

  test('capacity notifications coalesce and do not retain rejected requests',
      () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      final queue = ProcessIconQueue<String>(
        load: (_) => first.future,
        maxWaiting: 2,
      );
      queue.acquire('first');
      final a = queue.acquire('a')!;
      final b = queue.acquire('b')!;
      expect(queue.acquire('rejected'), isNull);
      var notifications = 0;
      void listener() => notifications++;
      queue.addListener(listener);
      a.release();
      b.release();
      drain(clock);
      expect(notifications, 1);
      expect(queue.waitingCount, 0);
      queue.removeListener(listener);
      first.complete('first');
      drain(clock);
      expect(notifications, 1);
      expect(queue.cachedCount, 1);
      queue.dispose();
    });
  });

  test(
      'dispose settles consumers, cancels queued work and releases cached values',
      () {
    fakeAsync((clock) {
      final blocked = Completer<String?>();
      final calls = <String>[];
      final evicted = <String>[];
      final queue = ProcessIconQueue<String>(
        load: (key) async {
          calls.add(key);
          return key == 'cached' ? key : blocked.future;
        },
        onEvict: evicted.add,
      );
      queue.acquire('cached');
      drain(clock);
      final active = queue.acquire('active')!;
      final pending = queue.acquire('pending')!;
      final results = <String?>[];
      unawaited(active.future.then(results.add));
      unawaited(pending.future.then(results.add));
      drain(clock);
      queue.dispose();
      queue.dispose();
      drain(clock);
      expect(results, [null, null]);
      expect(evicted, ['cached']);
      expect(queue.waitingCount, 0);
      expect(queue.activeCount, 1);
      blocked.complete('late');
      drain(clock);
      expect(calls, ['cached', 'active']);
      expect(queue.activeCount, 0);
      expect(() => queue.acquire('after'), throwsStateError);
    });
  });
}
