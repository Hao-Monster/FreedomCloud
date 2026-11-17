import 'dart:async';

import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/app_localizations.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_prepare.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/views/tools/health_check_view.dart';
import 'package:flclashx/widgets/tun_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTransport extends ClashHandlerInterface {
  _RecordingTransport({required this.windows});

  final bool windows;
  ActionMethod? method;
  Duration? timeout;
  Object? timeoutResult;

  @override
  bool get startListenerCreatesWindowsTun => windows;

  @override
  Future<T> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
    FutureOr<T> Function()? onTimeout,
    T? defaultValue,
    FutureOr<String> Function(String id)? encodeMessage,
  }) async {
    this.method = method;
    this.timeout = timeout;
    timeoutResult = await onTimeout?.call();
    return true as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TunStatus _status({
  required String state,
  required bool listenerActive,
  String interfaceState = 'missing',
  bool requestedEnabled = true,
  String? errorCode,
  int revision = 1,
}) =>
    TunStatus(
      instanceId: 'core-1',
      revision: revision,
      state: state,
      listenerActive: listenerActive,
      interfaceState: interfaceState,
      privilege: 'elevated',
      requestedEnabled: requestedEnabled,
      errorCode: errorCode,
    );

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  group('Wintun adapter creation failure handling', () {
    test(
      'startListener waits for the Core terminal TUN result instead of the 30s default',
      () async {
        final transport = _RecordingTransport(windows: true);
        expect(await transport.startListener(), isTrue);
        expect(transport.method, ActionMethod.startListener);
        expect(transport.timeout, windowsStartListenerRpcTimeout);
        // One refused Wintun device takes ~15.5s; other slow adapter failures
        // keep upstream's three attempts (~47s) and the request can also wait
        // behind the Core runLock. 30s reported failure while TUN was running.
        expect(
          windowsStartListenerRpcTimeout,
          greaterThanOrEqualTo(const Duration(minutes: 2)),
        );
        expect(transport.timeoutResult, isFalse);
      },
    );

    test(
      'platforms that do not create a Wintun adapter keep the 30s listener deadline',
      () async {
        final transport = _RecordingTransport(windows: false);
        expect(await transport.startListener(), isTrue);
        expect(transport.timeout, const Duration(seconds: 30));
        expect(
          startListenerRpcTimeoutFor(isWindows: false),
          const Duration(seconds: 30),
        );
        expect(
          startListenerRpcTimeoutFor(isWindows: true),
          windowsStartListenerRpcTimeout,
        );
      },
    );

    test('startListener timing distinguishes timeout from Core rejection', () {
      const timeout = Duration(seconds: 30);
      expect(
        startListenerTimingOutcome(
          started: true,
          elapsed: Duration.zero,
          timeout: timeout,
        ),
        'started',
      );
      expect(
        startListenerTimingOutcome(
          started: false,
          elapsed: const Duration(seconds: 1),
          timeout: timeout,
        ),
        'rejected',
      );
      expect(
        startListenerTimingOutcome(
          started: false,
          elapsed: timeout,
          timeout: timeout,
        ),
        'timeout',
      );
    });

    test('health check reports a refused adapter specifically', () async {
      final l10n = await AppLocalizations.load(const Locale('zh', 'CN'));
      expect(
        HealthRunner.mapTunFailureReason('adapterCreateFailed'),
        'tunAdapterCreateFailed',
      );
      expect(HealthRunner.mapTunFailureReason('startFailed'), 'tunStartFailed');
      expect(
        healthCheckItemDetail(
          const HealthCheckResult(
            id: HealthCheckId.tunTakeover,
            status: HealthStatus.failed,
            elapsedMs: 1,
            reasonCode: 'tunAdapterCreateFailed',
          ),
          l10n,
        ),
        l10n.tunErrorAdapterCreate,
      );
    });

    test(
      'background repair does not immediately re-run a refused Wintun adapter',
      () {
        final adapterFailure = _status(
          state: 'failed',
          listenerActive: false,
          errorCode: 'adapterCreateFailed',
        );
        expect(
          isRepairableWindowsTunFailure(adapterFailure, proxyRunning: true),
          isFalse,
        );
        final reloadFailure = _status(
          state: 'failed',
          listenerActive: false,
          errorCode: 'startFailed',
        );
        expect(
          isRepairableWindowsTunFailure(reloadFailure, proxyRunning: true),
          isTrue,
        );
        expect(
          isRepairableWindowsTunFailure(reloadFailure, proxyRunning: false),
          isFalse,
        );
        expect(
          isRepairableWindowsTunFailure(
            _status(
              state: 'on',
              listenerActive: true,
              errorCode: 'interfaceMissing',
            ),
            proxyRunning: false,
          ),
          isTrue,
        );
      },
    );

    test('adapter failure is labelled specifically and cleared by a healthy TUN',
        () {
      final runtime = TunRuntimeController()..desiredEnabled = true;
      expect(
        runtime.accept(
          _status(
            state: 'failed',
            listenerActive: false,
            errorCode: 'adapterCreateFailed',
          ),
          runtime.observationEpoch,
        ),
        isTrue,
      );
      expect(runtime.failure, 'adapterCreateFailed');
      expect(
        tunStatusLabel(runtime),
        appLocalizations.tunStatusFailure(appLocalizations.tunErrorAdapterCreate),
      );
      expect(
        appLocalizations.tunErrorAdapterCreate,
        isNot(appLocalizations.tunErrorStart),
      );

      runtime.fail('adapterCreateFailed');
      expect(runtime.requestFailure, 'adapterCreateFailed');
      expect(
        runtime.accept(
          _status(
            state: 'on',
            listenerActive: true,
            interfaceState: 'up',
            revision: 2,
          ),
          runtime.observationEpoch,
        ),
        isTrue,
      );
      expect(runtime.failure, isNull);
      expect(runtime.requestFailure, isNull);
    });
  });
}
