import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';

/// Shared by the window and tray, so opening another group cannot multiply
/// the request budget. Dependencies are read only when a user starts a test.
final _healthTargets = <DelayTestTarget, NodeHealthTarget?>{};

final delayTests = DelayTestCoordinator(
  test: (target, requestId, timeout) => clashCore.getDelayResult(
    target.url,
    target.name,
    requestId: requestId,
    timeout: timeout,
  ),
  // Keep Core lazy: constructing the coordinator during a read-only cancel
  // must not initialize the desktop service or platform path plugins.
  // ignore: unnecessary_lambdas
  cancelRequest: (requestId) => clashCore.cancelDelayTest(requestId),
  onStarted: (target) {
    final delay = Delay(name: target.name, url: target.url, value: 0);
    _healthTargets[target] =
        globalState.appController.captureNodeHealthTarget(delay);
    globalState.appController.setDelay(delay);
  },
  onResult: (target, result) => globalState.appController.setDelay(
    Delay(name: target.name, url: target.url, value: result.value),
    reason: result.reason,
    healthTarget: _healthTargets.remove(target),
    capturedHealthTarget: true,
  ),
);

Future<void> cancelDelayTests({String reason = 'cancelled'}) =>
    delayTests.cancel(reason: reason);
