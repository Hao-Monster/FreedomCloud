import 'dart:async';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> status(
        {String state = 'on',
        bool listener = true,
        String interface = 'up',
        int revision = 1,
        String? error}) =>
    {
      'schemaVersion': 1,
      'coreInstanceId': 'core-1',
      'revision': revision,
      'observedAt': 1,
      'requestedEnabled': true,
      'state': state,
      'listenerActive': listener,
      'interfaceState': interface,
      'privilege': 'elevated',
      'errorCode': error,
    };

void main() {
  test('accepted preference without listener never means on', () {
    expect(
        TunStatus.fromJson(status(state: 'failed', listener: false)).observed,
        TunObservedState.off);
    expect(TunStatus.fromJson(status(interface: 'missing')).observed,
        TunObservedState.unknown);
  });
  test('failed close retains observed active listener', () {
    expect(
        TunStatus.fromJson(status(state: 'failed', error: 'closeFailed'))
            .observed,
        TunObservedState.on);
  });
  test('failed close without a live reference remains unknown', () {
    expect(
        TunStatus.fromJson(
                status(state: 'failed', listener: false, error: 'closeFailed'))
            .observed,
        TunObservedState.unknown);
  });
  test('unknown and unsupported payloads never default to off', () {
    expect(() => TunStatus.fromJson({}), throwsA(isA<TunFailure>()));
    expect(TunRuntimeController().observed, TunObservedState.unknown);
  });
  test('transport invalidation rejects an outstanding successful reply', () {
    final runtime = TunRuntimeController();
    final epoch = runtime.observationEpoch;
    runtime.invalidate('transportUnavailable');
    expect(runtime.accept(TunStatus.fromJson(status()), epoch), isFalse);
    expect(runtime.isEnabled, isFalse);
  });
  test('older revision cannot replace current Core evidence', () {
    final runtime = TunRuntimeController();
    runtime.accept(TunStatus.fromJson(status(revision: 2)), 0);
    expect(
        runtime.accept(
            TunStatus.fromJson(
                status(revision: 1, state: 'off', listener: false)),
            0),
        isFalse);
    expect(runtime.isEnabled, isTrue);
  });
  test('last intent wins and operations do not overlap', () async {
    final runtime = TunRuntimeController();
    final entered = Completer<void>();
    final release = Completer<void>();
    final applied = <bool>[];
    final first = runtime.request(true, (intent) async {
      entered.complete();
      await release.future;
      if (runtime.isCurrentIntent(intent)) applied.add(true);
    });
    await entered.future;
    final last = runtime.request(false, (_) async {
      applied.add(false);
    });
    release.complete();
    await Future.wait([first, last]);
    expect(applied, [false]);
    expect(runtime.busy, isFalse);
    expect(runtime.desiredEnabled, isFalse);
  });
  test('failed request is explicitly retryable', () async {
    final runtime = TunRuntimeController();
    await runtime.request(true, (_) async {
      throw const TunFailure('permissionDenied');
    });
    expect(runtime.failure, 'permissionDenied');
    await runtime.request(true, (_) async {});
    expect(runtime.failure, isNull);
  });
  test('successful explicit close clears a preceding start failure', () async {
    final runtime = TunRuntimeController();
    await runtime.request(false, (_) async {
      runtime.accept(
          TunStatus.fromJson(
              status(state: 'failed', listener: false, error: 'startFailed')),
          runtime.observationEpoch);
      runtime.accept(
          TunStatus.fromJson(
              status(state: 'off', listener: false, revision: 2)),
          runtime.observationEpoch);
    });
    expect(runtime.observed, TunObservedState.off);
    expect(runtime.failure, isNull);
  });
  test('teardown revokes pending authorization and drains before closing',
      () async {
    final runtime = TunRuntimeController();
    final authorized = Completer<void>();
    final entered = Completer<void>();
    final calls = <String>[];
    final pending = runtime.request(true, (intent) async {
      entered.complete();
      await authorized.future;
      if (runtime.isCurrentIntent(intent)) calls.add('enable');
    });
    await entered.future;
    final queuedConfig = runtime.serialize(() async {
      calls.add('config');
    });
    final closing = runtime.quiesce(() async {
      calls.add('close');
    });
    await runtime.request(true, (_) async {
      calls.add('late-enable');
    }, writeIntent: (_) {
      calls.add('late-intent');
    });
    authorized.complete();
    await Future.wait([pending, queuedConfig, closing]);
    expect(calls, ['close']);
    expect(runtime.closing, isTrue);
  });
}
