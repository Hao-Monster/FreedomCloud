import 'dart:io';

import 'package:flutter/foundation.dart';

import 'tun_runtime.dart';
import 'windows_tun_prepare.dart';

/// The existing platform/configuration boundaries used by a Windows launch.
/// Implementations must not acquire the TUN operation queue again.
abstract interface class WindowsTunStartupEffects {
  bool get proxyRunning;
  Future<bool> hasProfile();
  Future<TunStatus?> observe();
  Future<bool> componentsMatch();
  bool canMigrate();
  Future<bool> authorize();
  Future<bool> ensureBackend(bool Function() isCurrent);
  Future<void> initialize(bool Function() isCurrent);
  Future<void> applyConfiguration(
      {required bool full, required bool Function() isCurrent});
  Future<bool> startListener();
  Future<void> stopProxy();
  Future<void> reflectRunning(bool Function() isCurrent);

  /// Launch path for a saved TUN-off preference: start (or adopt) the proxy
  /// without enabling TUN and without requesting privileges.
  Future<void> startProxyWithoutTun();

  /// Startup diagnostics (TUN outcome / degradation reason).
  void log(String message);
}

Future<void> startWindowsTunOnLaunch({
  required TunRuntimeController runtime,
  required WindowsTunStartupEffects effects,
  required ValueChanged<bool> writeIntent,
  Duration settleDelay = const Duration(milliseconds: 500),
  int settleAttempts = 8,
}) =>
    runtime.request(true, (intent) async {
      bool current() => runtime.isCurrentIntent(intent);
      Future<TunStatus?> observe() async {
        final epoch = runtime.observationEpoch;
        final status = await effects.observe();
        if (status == null) return null;
        // The observer accepts fresh reads under its own epoch. An unrelated
        // poll that failed while this read was queued may have advanced the
        // epoch first; the result is still current if the runtime holds it.
        final accepted = runtime.status;
        if (accepted != null &&
            accepted.instanceId == status.instanceId &&
            accepted.revision == status.revision) {
          return status;
        }
        if (epoch != runtime.observationEpoch) return null;
        if (current() && !runtime.accept(status, epoch)) return null;
        return status;
      }

      Future<void> reflectObserved(TunStatus status) {
        final epoch = runtime.observationEpoch;
        return effects.reflectRunning(() =>
            current() &&
            epoch == runtime.observationEpoch &&
            runtime.isEnabled &&
            runtime.status?.instanceId == status.instanceId);
      }

      final initial = await observe();
      if (!current()) return;
      final initialEpoch = runtime.observationEpoch;
      final matching = await effects.componentsMatch();
      if (!current()) return;
      if (initialEpoch != runtime.observationEpoch ||
          (initial != null &&
              (runtime.status?.instanceId != initial.instanceId ||
                  runtime.status?.revision != initial.revision))) {
        throw const TunFailure('statusUnavailable');
      }
      if (matching &&
          initial?.observed == TunObservedState.on &&
          effects.proxyRunning) {
        await reflectObserved(initial!);
        return;
      }
      final hasProfile = await effects.hasProfile();
      if (!current()) return;
      if (!hasProfile) throw const TunFailure('profileRequired');

      final wasRunning = effects.proxyRunning;
      var initialized = false;
      final replaced = await prepareWindowsTunBackend(
        observe: observe,
        componentsMatch: effects.componentsMatch,
        canMigrate: effects.canMigrate,
        authorize: effects.authorize,
        ensureBackend: () => effects.ensureBackend(current),
        initialize: () async {
          // A committed backend replacement must at least finish initialization,
          // even when a stop/exit supersedes this launch while migration is pending.
          await effects.initialize(() => true);
          initialized = true;
        },
        isCurrent: current,
      );
      if (!current()) return;
      final full = replaced || !wasRunning;
      if (full && !initialized) {
        await effects.initialize(current);
        if (!current()) return;
      }
      await effects.applyConfiguration(full: full, isCurrent: current);
      if (!current()) return;
      if (full) {
        final started = await effects.startListener();
        if (!current()) return;
        if (!started) throw const TunFailure('startFailed');
      }
      // Adapter creation and interface publication are asynchronous at the OS
      // level. Retry only unavailable/transitional reads within a short bound;
      // a definite off/failed observation still fails immediately.
      TunStatus? observed;
      for (var attempt = 0;; attempt++) {
        observed = await observe();
        if (!current()) return;
        if (observed != null &&
            observed.observed != TunObservedState.unknown) {
          break;
        }
        if (attempt + 1 >= settleAttempts) break;
        if (settleDelay > Duration.zero) await Future.delayed(settleDelay);
        if (!current()) return;
      }
      if (observed == null) throw const TunFailure('statusUnavailable');
      if (observed.observed != TunObservedState.on) {
        throw TunFailure(observed.errorCode ?? 'startFailed');
      }
      await reflectObserved(observed);
    }, writeIntent: writeIntent);

/// Validate only what can be checked locally before prompting for privileges.
/// YAML semantics and script output still require Core configuration acceptance.
Future<bool> isReadableWindowsStartupProfile(String? path) async {
  if (path == null) return false;
  try {
    final content = await File(path).readAsString();
    return content.trim().isNotEmpty;
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
}
