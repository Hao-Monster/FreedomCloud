import 'dart:convert';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('endpoint and Agent events carry the same non-secret instance identity', () {
    final instance = 'a' * 64;
    final endpoint = AgentEndpoint.fromJson({'protocol': 1, 'port': 4455,
      'pid': 42, 'token': 'b' * 64, 'agentInstanceId': instance});
    final event = AgentEvent.tryParse({'_agent': {'type': 'ready',
      'coreState': 'ready', 'generation': 3, 'agentInstanceId': instance,
      'agentPid': 42, 'agentExecutable': r'C:\preview\FlClashAgent.exe',
      'coreExecutable': r'C:\protected\FlClashCore.exe', 'backendSource': 'helper'}});
    expect(endpoint.instanceId, instance);
    expect(event?.agentInstanceId, endpoint.instanceId);
    expect(event?.agentPid, endpoint.pid);
    expect(event?.backendSource, 'helper');
    expect(event?.coreExecutable, r'C:\protected\FlClashCore.exe');
    expect(() => AgentEndpoint.fromJson({'protocol': 1, 'port': 4455,
      'pid': 42, 'token': 'b' * 64, 'agentInstanceId': 'invalid'}), throwsFormatException);
  });
  test('strict policy status round-trips and fails closed before armed', () {
    const status = AgentStrictPolicyStatus(
      state: AgentStrictPolicyState.blocking,
      generation: 4,
      failureReason: AgentStrictPolicyFailureReason.brokerUnavailable,
    );
    final decoded = AgentStrictPolicyStatus.fromJson(status.toJson());
    expect(decoded.state, AgentStrictPolicyState.blocking);
    expect(decoded.generation, 4);
    expect(decoded.failureReason,
        AgentStrictPolicyFailureReason.brokerUnavailable);
    expect(decoded.failClosed, isTrue);

    const armed = AgentStrictPolicyStatus(
      state: AgentStrictPolicyState.armed,
      generation: 5,
    );
    expect(
        AgentStrictPolicyStatus.fromJson(armed.toJson()).failClosed, isFalse);
  });

  test('strict policy status rejects unknown state, reason and generation', () {
    expect(
      () => AgentStrictPolicyStatus.fromJson({
        'state': 'unknown',
        'generation': 1,
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => AgentStrictPolicyStatus.fromJson({
        'state': 'blocking',
        'failureReason': 'unknown',
        'generation': 1,
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => AgentStrictPolicyStatus.fromJson({
        'state': 'blocking',
        'generation': -1,
      }),
      throwsFormatException,
    );
  });

  test(
      'strict status cache rejects stale generations but accepts same-generation transitions',
      () {
    final cache = AgentStrictPolicyStatusCache(
      initial: const AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.preparing,
        generation: 4,
      ),
    );
    expect(
      cache.update(const AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.armed,
        generation: 3,
      )),
      isFalse,
    );
    expect(cache.value.state, AgentStrictPolicyState.preparing);
    expect(
      cache.update(const AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.armed,
        generation: 4,
      )),
      isTrue,
    );
    expect(cache.value.state, AgentStrictPolicyState.armed);
    expect(
      cache.update(const AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.armed,
        generation: 4,
      )),
      isFalse,
    );
  });

  test('core adapter removes unsafe armed status when Core is unavailable', () {
    const armed = AgentStrictPolicyStatus(
      state: AgentStrictPolicyState.armed,
      generation: 8,
    );
    final blocked = strictPolicyStatusForCore(
      status: armed,
      coreState: AgentCoreState.stopped,
    );
    expect(blocked.state, AgentStrictPolicyState.blocking);
    expect(
        blocked.failureReason, AgentStrictPolicyFailureReason.coreUnavailable);
    expect(blocked.failClosed, isTrue);

    const preparing = AgentStrictPolicyStatus(
      state: AgentStrictPolicyState.preparing,
      generation: 8,
    );
    expect(
      strictPolicyStatusForCore(
        status: preparing,
        coreState: AgentCoreState.failed,
      ),
      same(preparing),
    );
  });

  test(
      'missing strict status inherits event generation for fail-closed reconnects',
      () {
    final event = AgentEvent.tryParse({
      '_agent': {
        'type': 'ready',
        'coreState': 'ready',
        'generation': 9,
      },
    });
    expect(event, isNotNull);
    expect(event!.strictPolicyStatus.state, AgentStrictPolicyState.disabled);
    expect(event.strictPolicyStatus.generation, 9);

    final cache = AgentStrictPolicyStatusCache(
      initial: const AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.armed,
        generation: 8,
      ),
    );
    expect(cache.update(event.strictPolicyStatus), isTrue);
    expect(cache.value.state, AgentStrictPolicyState.disabled);
    expect(cache.value.generation, 9);
  });

  test('endpoint requires v1, a loopback port and a 256-bit token', () {
    final endpoint = AgentEndpoint.fromJson({
      'protocol': 1,
      'port': 49152,
      'token': 'a' * 64,
      'pid': 42,
    });
    expect(endpoint.port, 49152);
    expect(endpoint.pid, 42);

    expect(
      () => AgentEndpoint.fromJson({
        'protocol': 2,
        'port': 49152,
        'token': 'a' * 64,
        'pid': 42,
      }),
      throwsFormatException,
    );
    expect(
      () => AgentEndpoint.fromJson({
        'protocol': 1,
        'port': 0,
        'token': 'not-a-token',
        'pid': 42,
      }),
      throwsFormatException,
    );
  });

  test('control messages stay namespaced from Core actions', () {
    final line = encodeAgentCommand(
      id: 'control-1',
      command: AgentCommand.restartCore,
    );
    final value = json.decode(line) as Map<String, dynamic>;
    expect(value.keys, ['_agent']);
    expect(value['_agent']['id'], 'control-1');
    expect(value['_agent']['command'], 'restartCore');
  });

  test('strict control messages carry a bounded executable target', () {
    final line = encodeAgentCommand(
      id: 'control-2',
      command: AgentCommand.applyStrictBlock,
      path: r'C:\Apps\edge.exe',
    );
    final value = json.decode(line) as Map<String, dynamic>;
    expect(value['_agent']['command'], 'applyStrictBlock');
    expect(value['_agent']['path'], r'C:\Apps\edge.exe');
    expect(
      () => encodeAgentCommand(
        id: 'control-3',
        command: AgentCommand.clearStrictBlock,
        path: 'x' * 1025,
      ),
      throwsArgumentError,
    );
  });

  group('cached proxyRunning across real Agent envelopes', () {
    const instance =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    AgentEvent parse(Map<String, dynamic> agent) => AgentEvent.tryParse({
          '_agent': {'agentInstanceId': instance, ...agent}
        })!;

    // Shapes copied from services/agent/src/runtime.rs.
    final strictStatus = parse({
      'type': 'coreState', 'protocol': 1, 'coreState': 'ready',
      'generation': 2, 'privilegedBackend': true,
      'strictPolicy': {'state': 'disabled', 'generation': 1},
    });
    final identityResult = parse({
      'type': 'commandResult', 'id': 'agent-7', 'ok': true,
      'coreState': 'ready', 'generation': 2,
      'strictPolicy': {'state': 'disabled', 'generation': 1},
    });
    final coreStateUndecided = parse({
      'type': 'coreState', 'protocol': 1, 'coreState': 'ready',
      'generation': 2, 'proxyRunning': null, 'privilegedBackend': true,
    });

    test('envelopes without the key keep the same Core listener state', () {
      expect(strictStatus.proxyRunningReported, isFalse);
      expect(identityResult.proxyRunningReported, isFalse);
      // startListener() acknowledged true for this Core, then strict status
      // and an identity check arrive.
      var cached =
          mergeAgentProxyRunning(strictStatus, cached: true, sameReadyCore: true);
      cached =
          mergeAgentProxyRunning(identityResult, cached: cached, sameReadyCore: true);
      expect(cached, isTrue);
      expect(
          mergeAgentProxyRunning(identityResult, cached: false, sameReadyCore: true),
          isFalse);
    });

    test('an explicit null still means no listener decision', () {
      expect(coreStateUndecided.proxyRunningReported, isTrue);
      expect(
          mergeAgentProxyRunning(coreStateUndecided, cached: true, sameReadyCore: true),
          isNull);
    });

    test('a different or non-ready Core never inherits the cache', () {
      expect(
          mergeAgentProxyRunning(identityResult, cached: true, sameReadyCore: false),
          isNull);
      final unavailable = parse({
        'type': 'coreUnavailable', 'protocol': 1, 'generation': 2,
        'id': 'x', 'coreState': 'failed',
      });
      expect(mergeAgentProxyRunning(unavailable, cached: true, sameReadyCore: true),
          isNull);
    });
  });

  test('agent events expose readiness without pretending to be Core results',
      () {
    final event = AgentEvent.tryParse({
      '_agent': {
        'type': 'ready',
        'protocol': 1,
        'coreState': 'ready',
        'generation': 3,
        'proxyRunning': true,
        'privilegedBackend': true,
      },
    });
    expect(event, isNotNull);
    expect(event!.type, AgentEventType.ready);
    expect(event.coreState, AgentCoreState.ready);
    expect(event.generation, 3);
    expect(event.proxyRunning, isTrue);
    expect(event.privilegedBackend, isTrue);
    expect(event.strictPolicyStatus.state, AgentStrictPolicyState.disabled);
    expect(event.strictPolicyStatus.failClosed, isTrue);
    expect(event.strictPolicyStatus.generation, 3);
    final strictEvent = AgentEvent.tryParse({
      '_agent': {
        'type': 'coreState',
        'coreState': 'ready',
        'generation': 4,
        'strictPolicy': {
          'state': 'blocking',
          'generation': 9,
          'failureReason': 'captureUnavailable',
        },
      },
    });
    expect(
        strictEvent?.strictPolicyStatus.state, AgentStrictPolicyState.blocking);
    expect(strictEvent?.strictPolicyStatus.failClosed, isTrue);
    final undecided = AgentEvent.tryParse({
      '_agent': {
        'type': 'ready',
        'coreState': 'ready',
        'generation': 1,
        'proxyRunning': null,
      },
    });
    expect(undecided?.proxyRunning, isNull);
    expect(AgentEvent.tryParse({'method': 'getIsInit'}), isNull);
  });
}
