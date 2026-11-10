import 'tun_runtime.dart';

/// Background adapter repair is limited to states an immediate incremental
/// rebuild (or a UAC-free Core restart) can plausibly fix: a live listener
/// whose interface vanished, a reload that failed while recreating the
/// listener, or a latched close failure. `adapterCreateFailed` is excluded:
/// Windows refused the Wintun device after Wintun's own arrival wait, and
/// re-running it at once only queues further ~15s+ TUN cycles behind the Core
/// run lock. The user retries explicitly from the TUN switch.
bool isRepairableWindowsTunFailure(
  TunStatus status, {
  required bool proxyRunning,
}) {
  if (status.privilege != 'elevated') return false;
  if (status.listenerActive) {
    return status.errorCode == 'interfaceMissing' ||
        status.errorCode == 'interfaceDown';
  }
  if (!proxyRunning) return false;
  if (status.state != 'failed') return false;
  return (status.requestedEnabled && status.errorCode == 'startFailed') ||
      status.errorCode == 'closeFailed';
}

/// The authorization result only says that the Helper is available. Reconcile
/// the actual backend even when authorization itself required no prompt.
Future<bool> prepareWindowsTunBackend({
  required Future<TunStatus?> Function() observe,
  required Future<bool> Function() componentsMatch,
  required bool Function() canMigrate,
  required Future<bool> Function() authorize,
  required Future<bool> Function() ensureBackend,
  required Future<void> Function() initialize,
  required bool Function() isCurrent,
}) async {
  final initial = await observe();
  final matching = await componentsMatch();
  if (!isCurrent()) return false;
  if (initial?.privilege == 'elevated' && matching) return false;
  if (!canMigrate()) throw const TunFailure('legacyAgent');
  final authorized = await authorize();
  if (!isCurrent()) return false;
  if (!authorized) throw const TunFailure('permissionDenied');
  final replaced = await ensureBackend();
  // Once a Core has been replaced, restore its initialization before allowing
  // the next queued intent to run, even if this enable intent was superseded.
  if (replaced) await initialize();
  final status = await observe();
  if (status?.privilege != 'elevated')
    throw const TunFailure('permissionDenied');
  return replaced;
}

/// Both full-profile and incremental updates pass this same effect boundary.
/// Observation failure permits only an explicit, bounded disable attempt.
Future<void> applyWindowsTunConfiguration({
  required Future<bool> Function() componentsMatch,
  required Future<TunStatus?> Function() observe,
  required bool Function() desiredEnabled,
  required bool Function() explicitStop,
  required bool Function() explicitOperation,
  required bool Function() failedRequest,
  required void Function(String code) reportFailure,
  required void Function() invalidate,
  required Future<String> Function(bool enable) apply,
  bool Function()? isCurrent,
}) async {
  final isExplicitStop = explicitStop();
  final isExplicitOperation = explicitOperation();
  if (!await componentsMatch()) throw const TunFailure('componentsMismatch');
  if (isCurrent != null && !isCurrent()) return;
  final status = await observe();
  if (isCurrent != null && !isCurrent()) return;
  var enabled = desiredEnabled();
  if (!enabled && isExplicitStop) {
    // No observation is converted to false. This is solely a user command;
    // its outcome must still be observed after sending the request.
  } else {
    if (status == null) throw const TunFailure('statusUnavailable');
    // A Core that answered with an indeterminate listener (adapter missing or
    // down, transition) may be repaired by an explicit user enable: the
    // identical-config reload then rebuilds the adapter. Background refreshes
    // still never act on an unknown observation.
    final downgradeFailedAdapter = enabled &&
        !isExplicitOperation &&
        failedRequest() &&
        status.observed != TunObservedState.on;
    final explicitRepair = enabled &&
        isExplicitOperation &&
        status.privilege == 'elevated';
    if (status.observed == TunObservedState.unknown &&
        !explicitRepair &&
        !downgradeFailedAdapter) {
      throw const TunFailure('statusUnavailable');
    }
    if (downgradeFailedAdapter) enabled = false;
    if (enabled && status.privilege != 'elevated') {
      if (status.observed != TunObservedState.off)
        throw const TunFailure('permissionDenied');
      reportFailure('authorizationRequired');
      enabled = false;
    }
  }
  invalidate();
  final message = await apply(enabled);
  if (isCurrent != null && !isCurrent()) return;
  await observe();
  if (message.isNotEmpty) throw const TunFailure('configurationFailed');
}
