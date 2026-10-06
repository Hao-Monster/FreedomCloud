import 'dart:async';

import 'package:flutter/foundation.dart';

enum TunObservedState { unknown, off, on }

enum TunOperation { idle, enabling, disabling }

class TunFailure implements Exception {
  const TunFailure(this.code);
  final String code;
  @override
  String toString() => 'TUN: $code';
}

/// A bounded, credential-free observation of the current Core's listener.
/// Neither the persisted preference nor an accepted configuration is evidence
/// that the operating system created the interface.
class TunStatus {
  const TunStatus(
      {required this.instanceId,
      required this.revision,
      required this.state,
      required this.listenerActive,
      required this.interfaceState,
      required this.privilege,
      required this.requestedEnabled,
      this.errorCode});

  factory TunStatus.fromJson(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['coreInstanceId'] is! String ||
        (value['coreInstanceId'] as String).isEmpty ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0 ||
        value['observedAt'] is! int ||
        value['requestedEnabled'] is! bool ||
        value['listenerActive'] is! bool ||
        !const ['off', 'starting', 'on', 'failed', 'unknown']
            .contains(value['state']) ||
        !const ['up', 'down', 'missing', 'unknown', 'notApplicable']
            .contains(value['interfaceState']) ||
        !const ['elevated', 'unprivileged', 'unknown']
            .contains(value['privilege'])) {
      throw const TunFailure('invalidStatus');
    }
    return TunStatus(
        instanceId: value['coreInstanceId'] as String,
        revision: value['revision'] as int,
        state: value['state'] as String,
        listenerActive: value['listenerActive'] as bool,
        interfaceState: value['interfaceState'] as String,
        privilege: value['privilege'] as String,
        requestedEnabled: value['requestedEnabled'] as bool,
        errorCode:
            value['errorCode'] is String ? value['errorCode'] as String : null);
  }

  final String instanceId;
  final int revision;
  final String state;
  final bool listenerActive;
  final String interfaceState;
  final String privilege;
  final bool requestedEnabled;
  final String? errorCode;

  TunObservedState get observed {
    // A failed close may leave a live listener. Never turn the switch off just
    // because the operation reported an error.
    if (listenerActive &&
        interfaceState == 'up' &&
        (state == 'on' || errorCode == 'closeFailed')) {
      return TunObservedState.on;
    }
    if (!listenerActive &&
        errorCode != 'closeFailed' &&
        (state == 'off' || state == 'failed')) {
      return TunObservedState.off;
    }
    return TunObservedState.unknown;
  }
}

/// One process-local owner for Windows TUN intent, observations and operations.
/// All configuration writers use [serialize], including background refreshes.
class TunRuntimeController extends ChangeNotifier {
  TunStatus? _status;
  TunStatus? get status => _status;
  TunObservedState get observed =>
      _status?.observed ?? TunObservedState.unknown;
  bool get isEnabled => observed == TunObservedState.on;
  bool desiredEnabled = false;
  TunOperation operation = TunOperation.idle;
  String? failure;
  bool get busy => operation != TunOperation.idle;
  int _observationEpoch = 0;
  int _intent = 0;
  int get intentRevision => _intent;
  Future<void> _queue = Future.value();
  bool _closing = false;
  bool get closing => _closing;
  int get observationEpoch => _observationEpoch;
  bool isCurrentIntent(int intent) => !_closing && intent == _intent;

  /// A proxy stop cancels pending enabling work without changing the saved
  /// TUN preference. The stop itself still runs through the shared queue.
  void cancelPendingIntent() {
    ++_intent;
    operation = TunOperation.idle;
    notifyListeners();
  }

  void invalidate([String? reason]) {
    _observationEpoch++;
    _status = null;
    if (reason != null) failure = reason;
    notifyListeners();
  }

  bool accept(TunStatus value, int epoch) {
    if (epoch != _observationEpoch) return false;
    final previous = _status;
    if (previous != null &&
        previous.instanceId == value.instanceId &&
        value.revision < previous.revision) return false;
    _status = value;
    if (value.errorCode != null) {
      failure = value.errorCode;
    } else if (failure == 'statusUnavailable' ||
        failure == 'invalidStatus' ||
        (value.observed == TunObservedState.on &&
            const [
              'permissionDenied',
              'authorizationRequired',
              'startFailed',
              'interfaceDown',
              'interfaceMissing',
              'interfaceUnknown'
            ].contains(failure))) {
      failure = null;
    }
    notifyListeners();
    return true;
  }

  void fail(String reason) {
    failure = reason;
    notifyListeners();
  }

  Future<void> serialize(Future<void> Function() operation) {
    if (_closing) return Future.value();
    final next = _queue.then((_) async {
      if (!_closing) await operation();
    });
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> request(bool enabled, Future<void> Function(int intent) apply,
      {void Function(bool enabled)? writeIntent}) {
    if (_closing) return Future.value();
    final intent = ++_intent;
    desiredEnabled = enabled;
    operation = enabled ? TunOperation.enabling : TunOperation.disabling;
    failure = null;
    notifyListeners();
    // Riverpod listeners can run synchronously here. They must observe busy
    // before the preference changes, or they schedule a second config apply.
    writeIntent?.call(enabled);
    return serialize(() async {
      if (!isCurrentIntent(intent)) return;
      try {
        await apply(intent);
        if (isCurrentIntent(intent) &&
            _status?.errorCode == null &&
            observed ==
                (enabled ? TunObservedState.on : TunObservedState.off)) {
          failure = null;
        }
      } on TunFailure catch (error) {
        if (isCurrentIntent(intent)) failure = error.code;
      } catch (_) {
        if (isCurrentIntent(intent)) failure = 'operationFailed';
      } finally {
        if (isCurrentIntent(intent)) {
          operation = TunOperation.idle;
          notifyListeners();
        }
      }
    });
  }

  /// Revoke pending intents before waiting for an in-flight migration. A UAC
  /// reply arriving later cannot re-enable TUN after UI teardown has begun.
  Future<void> quiesce(Future<void> Function() teardown) {
    _closing = true;
    ++_intent;
    invalidate();
    final next = _queue.then((_) => teardown());
    _queue = next.catchError((Object _) {});
    return next;
  }
}

final tunRuntime = TunRuntimeController();

/// Serializes fresh reads as well as coalescing periodic reads. A response from
/// a pre-disconnect epoch can never restore an old Core's enabled claim.
class TunStatusObserver {
  TunStatusObserver(
      {required this.runtime, required this.read, this.onObserved});
  final TunRuntimeController runtime;
  final Future<TunStatus> Function() read;
  final void Function()? onObserved;
  Future<void> _queue = Future.value();
  Future<TunStatus?>? _latest;

  Future<TunStatus?> refresh({bool fresh = false}) {
    if (!fresh && _latest != null) return _latest!;
    final result = _queue.then((_) async {
      final epoch = runtime.observationEpoch;
      try {
        final value = await read();
        return runtime.accept(value, epoch) ? value : null;
      } catch (_) {
        if (epoch == runtime.observationEpoch)
          runtime.invalidate('statusUnavailable');
        return null;
      } finally {
        onObserved?.call();
      }
    });
    _queue = result.then<void>((_) {});
    _latest = result;
    unawaited(result.then<void>((_) {
      if (identical(_latest, result)) _latest = null;
    }));
    return result;
  }
}
