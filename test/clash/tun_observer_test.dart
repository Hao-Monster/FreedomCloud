import 'dart:async';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

TunStatus snapshot(String instance, {bool active = true}) => TunStatus(
    instanceId: instance,
    revision: 1,
    state: active ? 'on' : 'off',
    listenerActive: active,
    interfaceState: active ? 'up' : 'missing',
    privilege: 'elevated',
    requestedEnabled: active);

void main() {
  test(
      'fresh reads serialize and old instance reply after disconnect is discarded',
      () async {
    final runtime = TunRuntimeController();
    final firstEntered = Completer<void>();
    final old = Completer<TunStatus>();
    var calls = 0;
    final observer = TunStatusObserver(
        runtime: runtime,
        read: () async {
          calls++;
          if (calls == 1) {
            firstEntered.complete();
            return old.future;
          }
          return snapshot('new', active: false);
        });
    final original = observer.refresh();
    await firstEntered.future;
    runtime.invalidate('statusUnavailable');
    final fresh = observer.refresh(fresh: true);
    final periodic = observer.refresh();
    expect(calls, 1);
    old.complete(snapshot('old'));
    expect(await original, isNull);
    await Future.wait([fresh, periodic]);
    expect(calls, 2);
    expect(runtime.status?.instanceId, 'new');
    expect(runtime.observed, TunObservedState.off);
  });
  test('transport timeout revokes the last live observation', () async {
    final runtime = TunRuntimeController();
    runtime.accept(snapshot('one'), 0);
    final observer = TunStatusObserver(
        runtime: runtime,
        read: () async => throw TimeoutException('test transport timeout'));
    expect(await observer.refresh(), isNull);
    expect(runtime.observed, TunObservedState.unknown);
    expect(runtime.failure, 'statusUnavailable');
  });
  test('recovered observation clears stale transport failure', () async {
    final runtime = TunRuntimeController()..invalidate('statusUnavailable');
    final observer =
        TunStatusObserver(runtime: runtime, read: () async => snapshot('one'));
    await observer.refresh();
    expect(runtime.isEnabled, isTrue);
    expect(runtime.failure, isNull);
  });
}
