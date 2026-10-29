import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:intl/intl.dart';

export 'package:flclashx/common/delay_tests.dart';

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
    ProxyCardType.oneline => 16 + measure.bodyMediumHeight + 4,
  };
}

Iterable<DelayTestTarget> _targets(
    Iterable<Proxy> proxies, String? testUrl) sync* {
  final appController = globalState.appController;
  for (final proxy in proxies) {
    final state = appController.getProxyCardState(proxy.name);
    if (state.proxyName.isEmpty) continue;
    yield DelayTestTarget(
      state.proxyName,
      state.testUrl.getSafeValue(appController.getRealTestUrl(testUrl)),
    );
  }
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) =>
    _runDelayTests(_targets([proxy], testUrl));

Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) =>
    _runDelayTests(_targets(proxies, testUrl));

Future<void> delayTestGroups(Iterable<Group> groups) => _runDelayTests(
      groups.expand((group) => _targets(group.all, group.testUrl)),
    );

Future<void> _runDelayTests(Iterable<DelayTestTarget> targets) async {
  final result = await delayTests.run(targets);
  if (result.reason == 'busy') {
    globalState
        .showNotifier('${appLocalizations.delay}: ${appLocalizations.running}');
    return;
  }
  globalState.appController.addSortNum();
  final message = switch (result.reason) {
    'overloaded' => Intl.message('Too many proxies. Test a smaller group.',
        name: 'delayTooManyProxies'),
    'deadlineExceeded' || 'batchDeadlineExceeded' => Intl.message(
        'Delay test timed out. Remaining tests were cancelled.',
        name: 'delayBatchTimedOut'),
    'cancelled' => '${appLocalizations.delay}: ${appLocalizations.cancel}',
    'transportFailure' || 'sessionClosed' => Intl.message(
        'Delay test stopped because the core disconnected.',
        name: 'delayCoreDisconnected'),
    _ => null,
  };
  if (message != null) globalState.showNotifier(message);
}
