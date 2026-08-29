import 'dart:convert';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        'strictState': 'blocking',
        'strictReason': 'missingCapability',
        'strictRevision': 9,
        'strictFilterGeneration': 4,
      },
    });
    expect(event, isNotNull);
    expect(event!.type, AgentEventType.ready);
    expect(event.coreState, AgentCoreState.ready);
    expect(event.generation, 3);
    expect(event.proxyRunning, isTrue);
    expect(event.privilegedBackend, isTrue);
    expect(event.strictState, AgentStrictState.blocking);
    expect(event.strictReason, AgentStrictReason.missingCapability);
    expect(event.strictRevision, 9);
    expect(event.strictFilterGeneration, 4);
    final undecided = AgentEvent.tryParse({
      '_agent': {
        'type': 'ready',
        'coreState': 'ready',
        'generation': 1,
        'proxyRunning': null,
      },
    });
    expect(undecided?.proxyRunning, isNull);
    expect(undecided?.strictState, AgentStrictState.disabled);
    expect(undecided?.strictReason, AgentStrictReason.none);
    expect(AgentEvent.tryParse({'method': 'getIsInit'}), isNull);
  });
}
