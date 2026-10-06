import 'dart:async';
import 'package:flclashx/common/tun_config_update.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_prepare.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const initialParams = UpdateParams(
    tun: Tun(enable: false),
    mixedPort: 7890,
    allowLan: false,
    findProcessMode: FindProcessMode.always,
    mode: Mode.rule,
    logLevel: LogLevel.error,
    ipv6: true,
    tcpConcurrent: true,
    externalController: ExternalControllerStatus.close,
    unifiedDelay: true);

void main() {
  test(
      'synchronous provider intent listener cannot apply after authorization cancellation',
      () async {
    final params = StateProvider<UpdateParams>((ref) => initialParams);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final runtime = TunRuntimeController();
    var configCalls = 0;
    var authorizationCalls = 0;
    var listenerCalls = 0;
    container.listen(params, (previous, next) {
      listenerCalls++;
      if (shouldScheduleClashConfigUpdate(previous, next,
          explicitWindowsTunOperation: runtime.busy)) {
        unawaited(runtime.serialize(() async {
          configCalls++;
        }));
      }
    });
    await runtime.request(true, (_) async {
      await prepareWindowsTunBackend(
        observe: () async => const TunStatus(
            instanceId: 'one',
            revision: 1,
            state: 'off',
            listenerActive: false,
            interfaceState: 'missing',
            privilege: 'unprivileged',
            requestedEnabled: false),
        componentsMatch: () async => true,
        canMigrate: () => true,
        authorize: () async {
          authorizationCalls++;
          return false;
        },
        ensureBackend: () async {
          fail('backend must not migrate');
        },
        initialize: () async {
          fail('Core must not initialize');
        },
        isCurrent: () => true,
      );
      configCalls++;
    }, writeIntent: (enabled) {
      container.read(params.notifier).state =
          initialParams.copyWith.tun(enable: enabled);
    });
    await runtime.serialize(() async {});
    expect(listenerCalls, 1);
    expect(authorizationCalls, 1);
    expect(configCalls, 0);
    expect(container.read(params).tun.enable, isTrue);
    expect(runtime.failure, 'permissionDenied');
  });
  test('an independent mode change is not lost while TUN is preparing', () {
    expect(
        shouldScheduleClashConfigUpdate(
            initialParams, initialParams.copyWith(mode: Mode.global),
            explicitWindowsTunOperation: true),
        isTrue);
    expect(
        shouldScheduleClashConfigUpdate(
            initialParams, initialParams.copyWith.tun(enable: true),
            explicitWindowsTunOperation: false),
        isTrue);
  });
  for (final explicit in [false, true]) {
    test(
        'unknown observation ${explicit ? 'allows explicit disable' : 'blocks background config'}',
        () async {
      final applied = <bool>[];
      final operation = applyWindowsTunConfiguration(
        componentsMatch: () async => true,
        observe: () async => null,
        desiredEnabled: () => false,
        explicitStop: () => explicit,
        explicitOperation: () => explicit,
        failedRequest: () => false,
        reportFailure: (_) {},
        invalidate: () {},
        apply: (enabled) async {
          applied.add(enabled);
          return '';
        },
      );
      if (explicit) {
        await operation;
        expect(applied, [false]);
      } else {
        await expectLater(operation, throwsA(isA<TunFailure>()));
        expect(applied, isEmpty);
      }
    });
  }
}
