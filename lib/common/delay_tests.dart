import 'dart:async';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';

/// Shared by the window and tray, so opening another group cannot multiply
/// the request budget. Dependencies are read only when a user starts a test.
final _healthTargets = <DelayTestTarget, Future<NodeHealthTarget?>>{};

/// All scoped callbacks stay in the history store. In particular a catalog's
/// hashed identity must never become a key in the active proxy delay map.
DelayTestCoordinator createDelayTestRouter({
  required RunDelayTest liveTest,
  required void Function(DelayTestTarget) liveStarted,
  required void Function(DelayTestTarget, DelayTestResult) liveResult,
  required ClashHandlerInterface? Function() catalogInterface,
  required NodeHealthStore? Function() healthStore,
  required Future<void> Function(String) cancelRequest,
}) {
  final pending = <DelayTestTarget,
      ({NodeHealthStore store, NodeCatalogHealthTarget target})>{};
  return DelayTestCoordinator(
    test: (target, requestId, timeout) {
      if (target.scope == null && target.nodeIndex == null) {
        return liveTest(target, requestId, timeout);
      }
      if (target.scope == null ||
          target.scope!.isEmpty ||
          target.nodeIndex == null ||
          target.nodeIndex! < 0) {
        return Future.value(
            const DelayTestResult(-1, reason: 'invalidParameters'));
      }
      if (!pending.containsKey(target)) {
        return Future.value(const DelayTestResult(-1, reason: 'uiInactive'));
      }
      final interface = catalogInterface();
      if (interface == null) {
        return Future.value(
            const DelayTestResult(-1, reason: 'coreUnavailable'));
      }
      return interface.catalogTestDelay(
          target.scope!, target.nodeIndex!, target.url,
          requestId: requestId, timeout: timeout);
    },
    cancelRequest: cancelRequest,
    onDisposed: () {
      for (final captured in pending.values) {
        unawaited(captured.store
            .finishCatalogTest(captured.target, -1, reason: 'uiInactive')
            .catchError((Object _) {}));
      }
      pending.clear();
    },
    onStarted: (target) {
      if (target.scope == null && target.nodeIndex == null) {
        liveStarted(target);
        return;
      }
      final scope = target.scope;
      final index = target.nodeIndex;
      if (scope == null || index == null) return;
      final store = healthStore();
      final captured = store?.beginCatalogTest(
          catalogId: scope,
          nodeIndex: index,
          identityKey: target.name,
          testUrl: target.url);
      if (store != null && captured != null) {
        pending[target] = (store: store, target: captured);
      }
    },
    onResult: (target, result) {
      if (target.scope == null && target.nodeIndex == null) {
        liveResult(target, result);
        return;
      }
      final captured = pending.remove(target);
      if (captured != null) {
        // The store reports fixed write-failure categories and tracks this
        // future for flush; a callback cannot expose filesystem/parser errors.
        unawaited(captured.store
            .finishCatalogTest(captured.target, result.value,
                reason: result.reason)
            .catchError((Object _) {}));
      }
    },
  );
}

final delayTests = createDelayTestRouter(
  liveTest: (target, requestId, timeout) => clashCore.getDelayResult(
    target.url,
    target.name,
    requestId: requestId,
    timeout: timeout,
  ),
  catalogInterface: () => ClashCore.existingInterface,
  healthStore: () => globalState.appController.catalogHealthStore,
  // A cancellation of a passive/unavailable catalog must not construct Core.
  cancelRequest: (requestId) async {
    await ClashCore.existingInterface?.cancelTestDelay(requestId);
  },
  liveStarted: (target) {
    final delay = Delay(name: target.name, url: target.url, value: 0);
    final refreshRuntime = _healthTargets.isEmpty;
    _healthTargets[target] = globalState.appController
        .captureNodeHealthTarget(delay, refreshRuntime: refreshRuntime);
    globalState.appController.setDelay(delay);
  },
  liveResult: (target, result) => globalState.appController.setDelay(
    Delay(name: target.name, url: target.url, value: result.value),
    reason: result.reason,
    healthTarget: _healthTargets.remove(target),
    capturedHealthTarget: true,
  ),
);

Future<void> cancelDelayTests({String reason = 'cancelled'}) =>
    delayTests.cancel(reason: reason);
