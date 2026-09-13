import 'dart:convert';

import 'package:flutter/foundation.dart';

const agentProtocolVersion = 1;
const agentEndpointFileName = 'flclashx-agent-v1.json';

enum AgentCommand {
  restartCore,
  stopCore,
  shutdownAgent,
  status,
  applyStrictBlock,
  clearStrictBlock,
  applyStrictPolicy,
  clearStrictPolicy,
}

enum AgentCoreState { starting, ready, stopped, failed }

enum AgentEventType { ready, coreState, commandResult, coreUnavailable }

/// Versioned strict-capture status carried by Agent events.  The Agent may
/// publish this before a platform backend is available; consumers must treat
/// every state other than [armed] as fail-closed for selected policies.
enum AgentStrictPolicyState {
  disabled,
  preparing,
  armed,
  degraded,
  blocking,
  recovering,
}

enum AgentStrictPolicyFailureReason {
  captureUnavailable,
  proxyRouteUnavailable,
  identityUnavailable,
  coreUnavailable,
  brokerUnavailable,
  recoveryExhausted,
  invalidPolicy,
}

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
    this.strictPolicyStatus = const AgentStrictPolicyStatus(
      state: AgentStrictPolicyState.disabled,
      generation: 0,
    ),
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
        strictPolicyStatus: _parseStrictPolicyStatus(envelope),
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

  /// Strict capture state reported by Agent. Missing status is treated as
  /// disabled so older Agents remain fail-closed to strict-policy consumers.
  final AgentStrictPolicyStatus strictPolicyStatus;

  static AgentStrictPolicyStatus _parseStrictPolicyStatus(
    Map<String, dynamic> envelope,
  ) {
    final raw = envelope['strictPolicy'];
    if (raw == null) {
      // Older Agents omit strictPolicy entirely.  Carry the event generation
      // into the fail-closed placeholder so a stale event cannot be rejected
      // by the cache and leave a newer armed snapshot visible after a
      // reconnect.  Invalid generations remain conservative at zero.
      final rawGeneration = envelope['generation'];
      final generation =
          rawGeneration is int && rawGeneration >= 0 ? rawGeneration : 0;
      return AgentStrictPolicyStatus(
        state: AgentStrictPolicyState.disabled,
        generation: generation,
      );
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid strict policy status');
    }
    return AgentStrictPolicyStatus.fromJson(raw);
  }
}

@immutable
class AgentStrictPolicyStatus {
  const AgentStrictPolicyStatus({
    required this.state,
    required this.generation,
    this.failureReason,
  });

  factory AgentStrictPolicyStatus.fromJson(Map<String, dynamic> json) {
    final state = AgentStrictPolicyState.values.byName(json['state'] as String);
    final rawReason = json['failureReason'];
    final reason = rawReason == null
        ? null
        : AgentStrictPolicyFailureReason.values.byName(rawReason as String);
    final generation = json['generation'];
    if (generation is! int || generation < 0) {
      throw const FormatException('Invalid strict policy generation');
    }
    return AgentStrictPolicyStatus(
      state: state,
      generation: generation,
      failureReason: reason,
    );
  }

  final AgentStrictPolicyState state;
  final int generation;
  final AgentStrictPolicyFailureReason? failureReason;

  Map<String, Object?> toJson() => {
        'state': state.name,
        'generation': generation,
        if (failureReason != null) 'failureReason': failureReason!.name,
      };

  bool get failClosed => state != AgentStrictPolicyState.armed;
}

/// Keeps the latest strict-policy status received from the Agent.
///
/// Agent events can be delivered out of order after a reconnect.  A status
/// from an older generation must never overwrite a newer status, otherwise a
/// stale `armed` event could make the UI/strategy layer believe capture is
/// healthy.  States within the same generation are accepted because capture
/// can legitimately move through preparing/degraded/recovering without a Core
/// restart.
class AgentStrictPolicyStatusCache {
  AgentStrictPolicyStatusCache({
    AgentStrictPolicyStatus initial = const AgentStrictPolicyStatus(
      state: AgentStrictPolicyState.disabled,
      generation: 0,
    ),
  }) : _value = initial;

  AgentStrictPolicyStatus _value;

  AgentStrictPolicyStatus get value => _value;

  /// Applies [next] unless it belongs to an older Agent generation.
  bool update(AgentStrictPolicyStatus next) {
    if (next.generation < _value.generation) return false;
    if (next.state == _value.state &&
        next.generation == _value.generation &&
        next.failureReason == _value.failureReason) {
      return false;
    }
    _value = next;
    return true;
  }
}

/// An Agent must not report an armed strict policy while its Core is not ready.
/// This adapter only removes an unsafe claim; it never fabricates capture
/// success and leaves all other fail-closed states unchanged.
AgentStrictPolicyStatus strictPolicyStatusForCore({
  required AgentStrictPolicyStatus status,
  required AgentCoreState coreState,
}) {
  if (coreState == AgentCoreState.ready ||
      status.state != AgentStrictPolicyState.armed) {
    return status;
  }
  return AgentStrictPolicyStatus(
    state: AgentStrictPolicyState.blocking,
    generation: status.generation,
    failureReason: AgentStrictPolicyFailureReason.coreUnavailable,
  );
}

String encodeAgentCommand({
  required String id,
  required AgentCommand command,
  String? path,
  Map<String, dynamic>? policy,
}) {
  if (path != null && (path.isEmpty || path.length > 1024)) {
    throw ArgumentError.value(path, 'path', 'must be 1-1024 characters');
  }
  return json.encode({
    '_agent': {
      'id': id,
      'command': command.name,
      if (path != null) 'path': path,
      if (policy != null) 'policy': policy,
    },
  });
}
