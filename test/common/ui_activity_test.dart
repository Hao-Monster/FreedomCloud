import 'package:fake_async/fake_async.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/manager/connection_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop focus loss remains active but minimize and hidden do not', () {
    final activity = UiActivity();
    addTearDown(activity.dispose);
    activity.setLifecycle(AppLifecycleState.inactive);
    expect(activity.value, isTrue);
    activity.setMinimized(true);
    expect(activity.value, isFalse);
    activity.setLifecycle(AppLifecycleState.resumed);
    expect(activity.value, isFalse);
    activity.setMinimized(false);
    expect(activity.value, isTrue);
    activity.setVisible(false);
    expect(activity.value, isFalse);
    activity.setLifecycle(AppLifecycleState.resumed);
    expect(activity.value, isFalse);
    activity.setVisible(true);
    expect(activity.value, isTrue);
    activity.setLifecycle(AppLifecycleState.hidden);
    expect(activity.value, isFalse);
    activity.setLifecycle(AppLifecycleState.resumed);
    expect(activity.value, isTrue);
  });

  test(
      'Android inactive pauses samples and redundant signals do not repeat effects',
      () {
    final activity = UiActivity(inactiveIsHidden: true);
    addTearDown(activity.dispose);
    var changes = 0;
    activity.addListener(() => changes++);
    activity.setLifecycle(AppLifecycleState.inactive);
    activity.setLifecycle(AppLifecycleState.paused);
    activity.setVisible(false);
    expect(activity.value, isFalse);
    expect(changes, 1);
    activity.setLifecycle(AppLifecycleState.resumed);
    expect(activity.value, isFalse);
    activity.setVisible(true);
    expect(changes, 2);
  });

  test(
      'connection page samples stop when minimized and refresh upon restore',
      () => fakeAsync((clock) {
            final activity = UiActivity();
            var requests = 0;
            final manager = ConnectionManager(
              loadSnapshot: () async {
                requests++;
                return const ConnectionSnapshot(
                    downloadTotal: 0,
                    uploadTotal: 0,
                    memory: 0,
                    connections: []);
              },
              diagnosticLog: (_) {},
            );
            activity.addListener(
                () => manager.setViewVisible(visible: activity.value));
            manager.setViewVisible(visible: activity.value);
            manager.configure(running: true, refreshIntervalMs: 100);
            clock.elapse(Duration.zero);
            expect(requests, 1);
            activity.setMinimized(true);
            clock.elapse(const Duration(seconds: 3));
            expect(requests, 1);
            expect(manager.running, isTrue);
            activity.setMinimized(false);
            clock.elapse(Duration.zero);
            expect(requests, 2);
            activity.setVisible(false);
            clock.elapse(const Duration(seconds: 3));
            expect(requests, 2);
            manager.dispose();
            activity.dispose();
          }));
}
