import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'default budget starts ten of 1000 targets and dispose cancels all active work',
      () => fakeAsync((clock) {
            var calls = 0;
            var cancelled = 0;
            var updates = 0;
            final coordinator = DelayTestCoordinator(
              test: (_, __, ___) {
                calls++;
                return Completer<DelayTestResult>().future;
              },
              cancelRequest: (_) async {
                cancelled++;
              },
              onStarted: (_) {},
              onResult: (_, __) {
                updates++;
              },
            );
            unawaited(coordinator.run(
                [for (var i = 0; i < 1000; i++) DelayTestTarget('$i', 'url')]));
            clock.flushMicrotasks();
            expect(calls, 10);
            coordinator.dispose();
            clock.flushMicrotasks();
            expect(cancelled, 10);
            expect(updates, 0);
            expect(coordinator.busy, isFalse);
            expect(clock.nonPeriodicTimerCount, 0);
          }));

  test(
      'Core invalidation discards queued work and does not duplicate the result',
      () => fakeAsync((clock) {
            var calls = 0;
            final applied = <String>[];
            final coordinator = DelayTestCoordinator(
              concurrency: 1,
              test: (_, __, ___) async {
                calls++;
                return const DelayTestResult(-1, reason: 'configChanged');
              },
              cancelRequest: (_) async {},
              onStarted: (_) {},
              onResult: (target, __) => applied.add(target.name),
            );
            DelayBatchResult? summary;
            coordinator.run([
              const DelayTestTarget('a', 'url'),
              const DelayTestTarget('b', 'url')
            ]).then((value) => summary = value);
            clock.flushMicrotasks();
            expect(calls, 1);
            expect(applied, ['a']);
            expect(summary!.reason, 'configChanged');
            expect(clock.nonPeriodicTimerCount, 0);
            coordinator.dispose();
          }));

  test(
      'callback failure cancels other workers and releases timers promptly',
      () => fakeAsync((clock) {
            var cancelled = 0;
            final coordinator = DelayTestCoordinator(
              concurrency: 2,
              test: (_, __, ___) => Completer<DelayTestResult>().future,
              cancelRequest: (_) async {
                cancelled++;
              },
              onStarted: (target) {
                if (target.name == 'bad')
                  throw StateError('synthetic callback failure');
              },
              onResult: (_, __) {},
            );
            Object? failure;
            coordinator.run([
              const DelayTestTarget('bad', 'url'),
              const DelayTestTarget('pending', 'url')
            ]).then<void>((_) {}, onError: (Object error) {
              failure = error;
            });
            clock.flushMicrotasks();
            expect(failure, isA<StateError>());
            expect(cancelled, 1);
            expect(coordinator.busy, isFalse);
            expect(clock.nonPeriodicTimerCount, 0);
            coordinator.dispose();
          }));

  test(
      'one worker budget spans groups and deduplicates node plus URL',
      () => fakeAsync((clock) {
            final pending = <Completer<DelayTestResult>>[];
            final visited = <(String, String)>[];
            var active = 0;
            var peak = 0;
            var applied = 0;
            final coordinator = DelayTestCoordinator(
              concurrency: 3,
              test: (target, id, timeout) {
                visited.add(target.key);
                active++;
                if (active > peak) peak = active;
                final result = Completer<DelayTestResult>();
                pending.add(result);
                return result.future.whenComplete(() => active--);
              },
              cancelRequest: (_) async {},
              onStarted: (_) {},
              onResult: (_, __) => applied++,
            );
            final targets = [
              for (var i = 0; i < 120; i++)
                DelayTestTarget('node-$i', 'https://test.invalid/a'),
              for (var i = 0; i < 40; i++)
                DelayTestTarget('node-$i', 'https://test.invalid/a'),
              const DelayTestTarget('node-0', 'https://test.invalid/b'),
              const DelayTestTarget('', 'https://test.invalid/a'),
            ];
            DelayBatchResult? summary;
            coordinator.run(targets).then((value) => summary = value);
            clock.flushMicrotasks();
            expect(pending.length, 3);
            while (pending.any((value) => !value.isCompleted)) {
              pending
                  .firstWhere((value) => !value.isCompleted)
                  .complete(const DelayTestResult(10));
              clock.flushMicrotasks();
            }
            expect(visited.length, 121);
            expect(visited.toSet().length, 121);
            expect(peak, 3);
            expect(applied, 121);
            expect(summary!.completed, 121);
            expect(coordinator.busy, isFalse);
            expect(clock.nonPeriodicTimerCount, 0);
            coordinator.dispose();
          }));

  test(
      'busy click is rejected and cancellation prevents stale success after new batch',
      () => fakeAsync((clock) {
            final replies = <Completer<DelayTestResult>>[];
            final cancelled = <String>[];
            final values = <int>[];
            final coordinator = DelayTestCoordinator(
              concurrency: 1,
              test: (_, __, ___) {
                final result = Completer<DelayTestResult>();
                replies.add(result);
                return result.future;
              },
              cancelRequest: (id) async => cancelled.add(id),
              onStarted: (_) {},
              onResult: (_, result) => values.add(result.value),
            );
            const target = DelayTestTarget('node', 'https://test.invalid');
            unawaited(coordinator.run([target]));
            DelayBatchResult? duplicate;
            coordinator.run([target]).then((value) => duplicate = value);
            clock.flushMicrotasks();
            expect(duplicate!.reason, 'busy');
            expect(replies.length, 1);
            unawaited(coordinator.cancel());
            clock.flushMicrotasks();
            expect(cancelled.length, 1);
            expect(coordinator.busy, isFalse);
            expect(clock.nonPeriodicTimerCount, 0);
            unawaited(coordinator.run([target]));
            clock.flushMicrotasks();
            replies.last.complete(const DelayTestResult(20));
            clock.flushMicrotasks();
            replies.first.complete(const DelayTestResult(999));
            clock.flushMicrotasks();
            expect(values, [-1, 20]);
            coordinator.dispose();
          }));

  test(
      'batch deadline includes waiting entries and requests remote cancellation',
      () => fakeAsync((clock) {
            var calls = 0;
            final cancelled = <String>[];
            final results = <DelayTestResult>[];
            final coordinator = DelayTestCoordinator(
              concurrency: 1,
              requestTimeout: const Duration(seconds: 5),
              batchTimeout: const Duration(milliseconds: 20),
              test: (_, __, ___) {
                calls++;
                return Completer<DelayTestResult>().future;
              },
              cancelRequest: (id) async => cancelled.add(id),
              onStarted: (_) {},
              onResult: (_, result) => results.add(result),
            );
            DelayBatchResult? summary;
            coordinator
                .run(List.generate(1000,
                    (i) => DelayTestTarget('node$i', 'https://test.invalid')))
                .then((value) => summary = value);
            clock.elapse(const Duration(milliseconds: 20));
            expect(calls, 1);
            expect(cancelled.length, 1);
            expect(summary!.reason, 'batchDeadlineExceeded');
            expect(results.single.reason, 'batchDeadlineExceeded');
            expect(results.single.value, -1);
            expect(clock.nonPeriodicTimerCount, 0);
            coordinator.dispose();
          }));

  test(
      'per-request timeout cancels Core work and worker continues to next entry',
      () => fakeAsync((clock) {
            var calls = 0;
            var cancelled = 0;
            final values = <int>[];
            final reasons = <String?>[];
            final coordinator = DelayTestCoordinator(
              concurrency: 1,
              requestTimeout: const Duration(milliseconds: 10),
              test: (_, __, ___) => ++calls == 1
                  ? Completer<DelayTestResult>().future
                  : Future.value(const DelayTestResult(15)),
              cancelRequest: (_) async => cancelled++,
              onStarted: (_) {},
              onResult: (_, result) {
                values.add(result.value);
                reasons.add(result.reason);
              },
            );
            unawaited(coordinator.run([
              const DelayTestTarget('a', 'url'),
              const DelayTestTarget('b', 'url')
            ]));
            clock.elapse(const Duration(milliseconds: 10));
            expect(calls, 2);
            expect(cancelled, 1);
            expect(values, [-1, 15]);
            expect(reasons, ['deadlineExceeded', null]);
            expect(coordinator.busy, isFalse);
            coordinator.dispose();
          }));

  test(
      'target budget rejects before starting and empty batch does no work',
      () => fakeAsync((clock) {
            var calls = 0;
            final coordinator = DelayTestCoordinator(
              maxTargets: 2,
              test: (_, __, ___) async {
                calls++;
                return const DelayTestResult(10);
              },
              cancelRequest: (_) async {},
              onStarted: (_) {},
              onResult: (_, __) {},
            );
            DelayBatchResult? tooLarge;
            coordinator.run([
              for (var i = 0; i < 3; i++) DelayTestTarget('$i', 'url')
            ]).then((value) => tooLarge = value);
            unawaited(coordinator.run([]));
            clock.flushMicrotasks();
            expect(tooLarge!.reason, 'overloaded');
            expect(calls, 0);
            expect(coordinator.busy, isFalse);
            coordinator.dispose();
          }));
}
