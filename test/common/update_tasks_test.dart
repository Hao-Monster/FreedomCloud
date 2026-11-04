import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'traffic poll stop/start has one in-flight cycle and stop cannot revive',
      () => fakeAsync((clock) {
            globalState.stopUpdateTasks();
            final old = Completer<void>();
            var requests = 0;
            Future<void> sample() =>
                ++requests == 1 ? old.future : Future.value();
            unawaited(globalState.startUpdateTasks([sample]));
            globalState.stopUpdateTasks();
            unawaited(globalState.startUpdateTasks([sample]));
            final overlap = requests;
            old.complete();
            clock.flushMicrotasks();
            final afterRestart = requests;
            globalState.stopUpdateTasks();
            clock.elapse(const Duration(seconds: 12));
            final afterStop = requests;
            globalState.stopUpdateTasks();
            globalState.tasks = [];
            expect(overlap, 1);
            expect(afterRestart, 2);
            expect(afterStop, 2);
          }));

  test(
      'repeated start during sampling is coalesced and failures do not kill future ticks',
      () => fakeAsync((clock) {
            globalState.stopUpdateTasks();
            final first = Completer<void>();
            var requests = 0;
            Future<void> sample() {
              requests++;
              if (requests == 1) return first.future;
              if (requests == 2)
                return Future.error(StateError('synthetic sample failure'));
              return Future.value();
            }

            for (var i = 0; i < 5; i++) {
              unawaited(globalState.startUpdateTasks([sample]));
            }
            final beforeReply = requests;
            first.complete();
            clock.flushMicrotasks();
            clock.elapse(const Duration(seconds: 6));
            final afterTick = requests;
            globalState.stopUpdateTasks();
            globalState.tasks = [];
            expect(beforeReply, 1);
            expect(afterTick, 3);
          }));

  test(
      'stopping during first task skips the rest of that cycle',
      () => fakeAsync((clock) {
            globalState.stopUpdateTasks();
            final first = Completer<void>();
            var secondCalls = 0;
            unawaited(globalState
                .startUpdateTasks([() => first.future, () => secondCalls++]));
            globalState.stopUpdateTasks();
            first.complete();
            clock.flushMicrotasks();
            globalState.tasks = [];
            expect(secondCalls, 0);
          }));

  test(
      'groupsUpdateTimer re-arms immediately from 180s to 60s when UI returns to foreground',
      () => fakeAsync((clock) {
            globalState.stopGroupsUpdateTask();
            uiActivity.setMinimized(true);
            expect(uiActivity.value, isFalse);

            globalState.startGroupsUpdateTask();
            final hiddenTimer = globalState.groupsUpdateTimer;
            expect(hiddenTimer, isNotNull);

            clock.elapse(const Duration(seconds: 10));
            uiActivity.setMinimized(false);
            expect(uiActivity.value, isTrue);

            // Re-invoking startGroupsUpdateTask on foreground transition must
            // replace the remaining 170s background timer with a 60s timer,
            // while repeated calls at the same cadence remain idempotent.
            globalState.startGroupsUpdateTask();
            final foregroundTimer = globalState.groupsUpdateTimer;
            expect(foregroundTimer, isNotNull);
            expect(identical(foregroundTimer, hiddenTimer), isFalse);

            globalState.startGroupsUpdateTask();
            expect(identical(globalState.groupsUpdateTimer, foregroundTimer), isTrue);

            clock.elapse(const Duration(seconds: 60));
            expect(globalState.groupsUpdateTimer, isNotNull);
            expect(identical(globalState.groupsUpdateTimer, foregroundTimer), isFalse);

            globalState.stopGroupsUpdateTask();
          }));
}
