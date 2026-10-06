import 'dart:async';

import 'agent_protocol.dart';

/// Transport reconnects and backend replacement share one owner. Replacement
/// invalidates queued recovery attempts before waiting for an active attach.
class AgentConnectionCoordinator {
  Future<void> _queue = Future.value();
  int _epoch = 0;
  int get epoch => _epoch;
  bool _replacing = false;

  Future<bool> connect(Future<bool> Function() action,
      {bool recovery = false}) {
    final epoch = _epoch;
    final next = _queue.then((_) async {
      if (recovery && (_replacing || epoch != _epoch)) return false;
      return action();
    });
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<T> replace<T>(Future<T> Function() action) {
    ++_epoch;
    _replacing = true;
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next.whenComplete(() {
      _replacing = false;
    });
  }
}

/// Attaching is read-only even when a Core is failed/stopped. Only an explicit
/// recovery request may restart it, and the new ready event remains required.
Future<bool> reconcileAgentCore({
  required AgentCoreState Function() state,
  required Future<void> Function() waitReady,
  required Future<bool> Function() restart,
  required bool explicitRecovery,
}) async {
  if (state() == AgentCoreState.ready) return true;
  if (state() == AgentCoreState.starting) {
    try {
      await waitReady();
      return state() == AgentCoreState.ready;
    } catch (_) {
      if (!explicitRecovery) return false;
    }
  }
  if (!explicitRecovery || !await restart()) return false;
  try {
    await waitReady();
    return state() == AgentCoreState.ready;
  } catch (_) {
    return false;
  }
}
