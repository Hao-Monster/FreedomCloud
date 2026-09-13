import 'package:flclashx/enum/enum.dart';

typedef AdminAuthorizationOperation = Future<AuthorizeCode> Function();

/// Coordinates privileged authorization attempts for a single app session.
///
/// Configuration updates can arrive concurrently (for example, a profile
/// apply and a network-setting update).  Keeping the operation here makes
/// those callers share one elevation attempt instead of showing multiple UAC
/// prompts.  A failed attempt is latched until [clearFailure] is called by an
/// explicit retry boundary (the controller uses disabling TUN for that).
class AdminAuthorizationGate {
  Future<AuthorizeCode>? _inFlight;
  bool _failed = false;
  int _generation = 0;

  bool get isFailureLatched => _failed;

  /// Clears a previous failure so the next request may ask for authorization.
  ///
  /// Incrementing the generation prevents an older in-flight request from
  /// re-latching a failure after the user has explicitly requested a retry.
  void clearFailure() {
    _generation++;
    _failed = false;
  }

  Future<AuthorizeCode> request(AdminAuthorizationOperation operation) {
    final pending = _inFlight;
    if (pending != null) return pending;
    if (_failed) return Future.value(AuthorizeCode.error);

    final generation = _generation;
    final future = _run(operation, generation);
    _inFlight = future;
    // Attach cleanup handlers without creating an unobserved error future.
    // The original future is returned to the caller, which owns error
    // handling; this side-effect must never report the same error twice.
    future.then<void>(
      (_) => _clearInFlight(future),
      onError: (Object _, StackTrace __) => _clearInFlight(future),
    );
    return future;
  }

  void _clearInFlight(Future<AuthorizeCode> future) {
    if (identical(_inFlight, future)) {
      _inFlight = null;
    }
  }

  Future<AuthorizeCode> _run(
    AdminAuthorizationOperation operation,
    int generation,
  ) async {
    try {
      final result = await operation();
      if (result == AuthorizeCode.error && generation == _generation) {
        _failed = true;
      }
      return result;
    } catch (_) {
      if (generation == _generation) {
        _failed = true;
      }
      rethrow;
    }
  }
}
