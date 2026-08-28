import 'dart:convert';

const agentProtocolVersion = 1;
const agentEndpointFileName = 'flclashx-agent-v1.json';

enum AgentCommand { restartCore, stopCore, shutdownAgent, status }

enum AgentCoreState { starting, ready, stopped, failed }

enum AgentEventType { ready, coreState, commandResult, coreUnavailable }

class AgentEndpoint {
  const AgentEndpoint({
    required this.port,
    required this.token,
    required this.pid,
  });

  factory AgentEndpoint.fromJson(Map<String, dynamic> json) {
    final protocol = json['protocol'];
    final port = json['port'];
    final token = json['token'];
    final pid = json['pid'];
    if (protocol != agentProtocolVersion ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        token is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token) ||
        pid is! int ||
        pid < 1) {
      throw const FormatException('Invalid FlClashAgent endpoint');
    }
    return AgentEndpoint(port: port, token: token.toLowerCase(), pid: pid);
  }

  final int port;
  final String token;
  final int pid;
}

class AgentEvent {
  const AgentEvent({
    required this.type,
    required this.coreState,
    required this.generation,
    this.id,
    this.ok,
    this.proxyRunning,
    this.privilegedBackend,
  });

  static AgentEvent? tryParse(Map<String, dynamic> json) {
    final envelope = json['_agent'];
    if (envelope is! Map<String, dynamic>) return null;
    try {
      final type = AgentEventType.values.byName(envelope['type'] as String);
      final state = AgentCoreState.values.byName(
        envelope['coreState'] as String? ?? AgentCoreState.failed.name,
      );
      return AgentEvent(
        type: type,
        coreState: state,
        generation: envelope['generation'] as int? ?? 0,
        id: envelope['id'] as String?,
        ok: envelope['ok'] as bool?,
        proxyRunning: envelope['proxyRunning'] as bool?,
        privilegedBackend: envelope['privilegedBackend'] as bool?,
      );
    } catch (_) {
      return null;
    }
  }

  final AgentEventType type;
  final AgentCoreState coreState;
  final int generation;
  final String? id;
  final bool? ok;
  final bool? proxyRunning;
  final bool? privilegedBackend;
}

String encodeAgentCommand({
  required String id,
  required AgentCommand command,
}) =>
    json.encode({
      '_agent': {
        'id': id,
        'command': command.name,
      },
    });
