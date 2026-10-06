import 'dart:async';
import 'package:flclashx/clash/agent_lifecycle.dart';
import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final state in [AgentCoreState.failed, AgentCoreState.stopped]) {
    test('attach to $state is read-only; explicit recovery restores ready',
        () async {
      var current = state;
      var restarts = 0;
      Future<bool> recover(bool explicit) => reconcileAgentCore(
            state: () => current,
            waitReady: () async {
              expect(current, AgentCoreState.ready);
            },
            restart: () async {
              restarts++;
              current = AgentCoreState.ready;
              return true;
            },
            explicitRecovery: explicit,
          );
      expect(await recover(false), isFalse);
      expect(restarts, 0);
      expect(current, state);
      expect(await recover(true), isTrue);
      expect(restarts, 1);
      expect(current, AgentCoreState.ready);
    });
  }
  test('a timed out cold start never issues a second implicit restart',
      () async {
    var restarts = 0;
    expect(
        await reconcileAgentCore(
          state: () => AgentCoreState.starting,
          waitReady: () => Future.error(TimeoutException('not ready')),
          restart: () async {
            restarts++;
            return true;
          },
          explicitRecovery: false,
        ),
        isFalse);
    expect(restarts, 0);
  });
  test('recovery failure is not a successful connection', () async {
    expect(
        await reconcileAgentCore(
          state: () => AgentCoreState.failed,
          waitReady: () async => fail('a rejected restart cannot become ready'),
          restart: () async => false,
          explicitRecovery: true,
        ),
        isFalse);
  });
  test('migration drains active reconnect and cancels queued old retries',
      () async {
    final coordinator = AgentConnectionCoordinator();
    final entered = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];
    final reconnect = coordinator.connect(() async {
      calls.add('attach-start');
      entered.complete();
      await release.future;
      calls.add('attach-end');
      return true;
    }, recovery: true);
    await entered.future;
    final stale = coordinator.connect(() async {
      calls.add('stale');
      return true;
    }, recovery: true);
    final migration = coordinator.replace(() async {
      calls.add('replace');
      return true;
    });
    release.complete();
    expect(await reconnect, isTrue);
    expect(await stale, isFalse);
    expect(await migration, isTrue);
    expect(calls, ['attach-start', 'attach-end', 'replace']);
  });
}
