import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends ClashHandlerInterface {
  final updates = <Map<String, dynamic>>[];
  String setupResult = '';
  @override
  void sendMessage(String message) {
    final action = Action.fromJson(jsonDecode(message));
    if (action.method == ActionMethod.updateConfig) {
      updates.add(Map<String, dynamic>.from(jsonDecode(action.data as String)));
    }
    unawaited(handleResult(ActionResult(
        id: action.id,
        method: action.method,
        data: '',
        code: ResultType.success)));
  }

  @override
  Future<String> setupConfig(SetupParams params) async => setupResult;
  @override
  Future<bool> destroy() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiTransport extends _Transport {
  final active = <bool>[];
  final replies = <Completer<bool>>[];
  @override
  Future<bool> setUiActive(bool value) {
    active.add(value);
    final reply = Completer<bool>();
    replies.add(reply);
    return reply.future;
  }
}

const _params = UpdateParams(
    tun: Tun(enable: false),
    mixedPort: 7890,
    allowLan: false,
    findProcessMode: FindProcessMode.off,
    mode: Mode.rule,
    logLevel: LogLevel.info,
    ipv6: false,
    tcpConcurrent: false,
    externalController: ExternalControllerStatus.close,
    unifiedDelay: false);

void main() {
  test(
      'Core UI visibility is serialized and reasserted on an unchanged reattach',
      () => fakeAsync((clock) {
            final transport = _UiTransport();
            final core = ClashCore.forTesting(transport);
            unawaited(core.setUiActive(false));
            unawaited(core.setUiActive(true));
            clock.flushMicrotasks();
            expect(transport.active, [false]);
            transport.replies[0].complete(true);
            clock.flushMicrotasks();
            expect(transport.active, [false, true]);
            transport.replies[1].complete(true);
            clock.flushMicrotasks();
            unawaited(core.setUiActive(true));
            clock.flushMicrotasks();
            expect(transport.active, [false, true, true]);
            transport.replies[2].complete(true);
            clock.flushMicrotasks();
            unawaited(core.destroy());
            clock.flushMicrotasks();
            expect(clock.nonPeriodicTimerCount, 0);
          }));
  test(
      'unrelated updates do not change controller address, enable or authentication',
      () => fakeAsync((clock) {
            final transport = _Transport();
            unawaited(transport.updateConfig(_params));
            clock.flushMicrotasks();
            final data = transport.updates.single;
            expect(data.containsKey('external-controller'), isFalse);
            expect(data.containsKey('controller-enabled'), isFalse);
            expect(data.containsKey('secret'), isFalse);
            expect(data['mixed-port'], 7890);
            expect(clock.nonPeriodicTimerCount, 0);
          }));

  test(
      'explicit close and reopen preserve a custom profile endpoint',
      () => fakeAsync((clock) {
            final transport = _Transport();
            final profile = {
              'external-controller': '127.0.0.1:9191',
              'secret': 'synthetic-secret'
            };
            unawaited(
                transport.updateConfig(_params, controllerEnabled: false));
            unawaited(transport.updateConfig(_params,
                controllerEnabled: true,
                controllerAddress:
                    globalState.controllerAddressForEnable(profile)));
            clock.flushMicrotasks();
            expect(transport.updates[0]['controller-enabled'], isFalse);
            expect(transport.updates[0].containsKey('external-controller'),
                isFalse);
            expect(transport.updates[1]['controller-enabled'], isTrue);
            expect(
                transport.updates[1]['external-controller'], '127.0.0.1:9191');
            expect(transport.updates[1].containsKey('secret'), isFalse);
          }));

  test('reopening TLS/pipe-only profiles never adds a plaintext fallback', () {
    for (final key in [
      'external-controller-tls',
      'external-controller-unix',
      'external-controller-pipe'
    ]) {
      expect(
          globalState.controllerAddressForEnable(
              {'external-controller': '', key: 'configured-endpoint'}),
          '');
    }
    expect(globalState.controllerAddressForEnable({}), '127.0.0.1:9090');
  });

  test(
      'failed setup preserves runtime snapshot and visible controller projection',
      () async {
    final transport = _Transport();
    final core = ClashCore.forTesting(transport);
    addTearDown(core.destroy);
    const old = SetupParams(config: {
      'external-controller': '127.0.0.1:9191',
      'secret': 'old-secret',
      'proxy-groups': [
        {'name': 'old-group', 'description': 'old label'}
      ]
    }, selectedMap: {}, testUrl: 'old-url');
    const candidate = SetupParams(config: {
      'external-controller': '127.0.0.1:9292',
      'secret': 'candidate-secret',
      'proxy-groups': [
        {'name': 'new-group', 'description': 'new label'}
      ]
    }, selectedMap: {}, testUrl: 'new-url');
    await core.setupConfig(old, profileId: 'old-profile');
    transport.setupResult = 'invalid configuration';
    expect(await core.setupConfig(candidate, profileId: 'new-profile'),
        'invalid configuration');
    expect(globalState.lastRuntimeConfig, old.config);
    expect(globalState.lastRuntimeProfileId, 'old-profile');
    expect(globalState.effectiveExternalController.value, '127.0.0.1:9191');
    expect(globalState.effectiveSecret.value, 'old-secret');
    expect(globalState.groupDescriptions.value, {'old-group': 'old label'});
    transport.setupResult = '';
    await core.setupConfig(candidate, profileId: 'new-profile');
    expect(globalState.lastRuntimeProfileId, 'new-profile');
    expect(globalState.effectiveExternalController.value, '127.0.0.1:9292');
    expect(globalState.groupDescriptions.value, {'new-group': 'new label'});
  });
}
