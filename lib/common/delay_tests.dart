import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';

/// Shared by the window and tray, so opening another group cannot multiply
/// the request budget. Dependencies are read only when a user starts a test.
final delayTests = DelayTestCoordinator(
  test: (target, requestId, timeout) => clashCore.getDelayResult(
    target.url,
    target.name,
    requestId: requestId,
    timeout: timeout,
  ),
  cancelRequest: (requestId) => clashCore.cancelDelayTest(requestId),
  onStarted: (target) => globalState.appController.setDelay(
    Delay(name: target.name, url: target.url, value: 0),
  ),
  onResult: (target, result) => globalState.appController.setDelay(
    Delay(name: target.name, url: target.url, value: result.value),
  ),
);

Future<void> cancelDelayTests({String reason = 'cancelled'}) =>
    delayTests.cancel(reason: reason);
