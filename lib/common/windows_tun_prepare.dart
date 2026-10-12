import 'tun_runtime.dart';

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
  if (!await componentsMatch()) throw const TunFailure('componentsMismatch');
  if (isCurrent != null && !isCurrent()) return;
  final status = await observe();
  if (isCurrent != null && !isCurrent()) return;
  var enabled = desiredEnabled();
  if (!enabled && explicitStop()) {
    // No observation is converted to false. This is solely a user command;
    // its outcome must still be observed after sending the request.
  } else {
    if (status == null || status.observed == TunObservedState.unknown) {
      throw const TunFailure('statusUnavailable');
    }
    if (enabled &&
        !explicitOperation() &&
        failedRequest() &&
        status.observed == TunObservedState.off) enabled = false;
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
