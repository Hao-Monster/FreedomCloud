import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_prepare.dart';
import 'package:flclashx/common/windows_tun_startup.dart';
import 'package:flutter_test/flutter_test.dart';

// Uses the production startup, runtime and observer logic. Only the Core/OS
// boundary is simulated: no processes, sockets, adapters or real timers.
class StabilityEffects implements WindowsTunStartupEffects {
  StabilityEffects(this.runtime, {this.running = false}) {
    observer = TunStatusObserver(runtime: runtime, read: read);
  }

  final TunRuntimeController runtime;
  late final TunStatusObserver observer;
  bool running;
  String instanceId = 'core';
  bool closeFailed = false;
  int coreRestarts = 0;
  final List<String> logs = [];
  bool pendingTun = false;
  bool actualTun = false;
  int revision = 0;
  int failReads = 0;
  int transitionalReads = 0;
  bool pollFailsAfterListener = false;
  int fullApplications = 0;
  int incrementalApplications = 0;
  int reflectCalls = 0;

  Future<TunStatus> read() async {
    if (failReads > 0) {
      failReads--;
      throw const TunFailure('statusUnavailable');
    }
    if (closeFailed) {
      // The Core latched a failed close: listener gone, adapter missing.
      return TunStatus(
          instanceId: instanceId,
          revision: revision,
          state: 'failed',
          listenerActive: false,
          interfaceState: 'missing',
          privilege: 'elevated',
          requestedEnabled: false,
          errorCode: 'closeFailed');
    }
    if (transitionalReads > 0) {
      transitionalReads--;
      return TunStatus(
          instanceId: instanceId,
          revision: revision,
          state: 'starting',
          listenerActive: false,
          interfaceState: 'unknown',
          privilege: 'elevated',
          requestedEnabled: true);
    }
    return TunStatus(
        instanceId: instanceId,
        revision: revision,
        state: actualTun ? 'on' : 'off',
        listenerActive: actualTun,
        interfaceState: actualTun ? 'up' : 'missing',
        privilege: 'elevated',
        requestedEnabled: pendingTun);
  }

  @override
  bool get proxyRunning => running;
  @override
  Future<bool> hasProfile() async => true;
  @override
  Future<TunStatus?> observe() => observer.refresh(fresh: true);
  @override
  Future<bool> componentsMatch() async => true;
  @override
  bool canMigrate() => true;
  @override
  Future<bool> authorize() async => true;
  @override
  Future<bool> ensureBackend(bool Function() isCurrent) async => false;
  @override
  Future<void> initialize(bool Function() isCurrent) async {}
  @override
  Future<void> applyConfiguration(
      {required bool full, required bool Function() isCurrent}) async {
    if (full) {
      fullApplications++;
    } else {
      incrementalApplications++;
    }
    pendingTun = true;
    if (running) actualTun = true;
    revision++;
  }

  @override
  Future<bool> startListener() async {
    running = true;
    actualTun = pendingTun;
    revision++;
    if (pollFailsAfterListener) {
      // A periodic poll that was already in flight (blocked behind adapter
      // creation in older Cores) fails and invalidates the observation epoch
      // just before startup's fresh verification read is queued behind it.
      failReads = 1;
      // ignore: unawaited_futures
      observer.refresh();
    }
    return true;
  }

  @override
  Future<void> stopProxy() async {}
  @override
  Future<void> reflectRunning(bool Function() isCurrent) async {
    if (isCurrent()) reflectCalls++;
  }

  @override
  Future<void> startProxyWithoutTun() async {}
  @override
  Future<void> restartCore() async {
    coreRestarts++;
    instanceId = 'core-$coreRestarts';
    revision = 0;
    closeFailed = false;
    running = false;
    pendingTun = false;
    actualTun = false;
  }

  @override
  void log(String message) => logs.add(message);
}

Future<void> launch(TunRuntimeController runtime, StabilityEffects effects,
        {int settleAttempts = 8}) =>
    startWindowsTunOnLaunch(
        runtime: runtime,
        effects: effects,
        writeIntent: (_) {},
        settleDelay: Duration.zero,
        settleAttempts: settleAttempts);

void main() {
  test('a failed concurrent poll does not discard an accepted fresh read',
      () async {
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    final effects = StabilityEffects(runtime)..pollFailsAfterListener = true;
    // Single attempt isolates the epoch handling from the settle retry.
    await launch(runtime, effects, settleAttempts: 1);
    expect(effects.actualTun, isTrue);
    expect(runtime.observed, TunObservedState.on);
    expect(runtime.failure, isNull);
    expect(effects.reflectCalls, 1);
  });

  test('transitional final reads settle instead of failing startup', () async {
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    // The first three verification reads still report creation in progress.
    final slow = _SlowCreation(runtime, transitional: 3);
    await launch(runtime, slow);
    expect(runtime.observed, TunObservedState.on);
    expect(runtime.failure, isNull);
    expect(slow.reflectCalls, 1);
  });

  test('settle window is bounded and reports the last real reason', () async {
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    final slow = _SlowCreation(runtime, transitional: 100);
    await launch(runtime, slow, settleAttempts: 4);
    expect(runtime.isEnabled, isFalse);
    expect(runtime.failure, 'startFailed');
    expect(slow.reflectCalls, 0);
  });

  test('definite off after start fails immediately without retries', () async {
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    final effects = _NeverOn(runtime);
    await launch(runtime, effects);
    expect(runtime.failure, 'startFailed');
    expect(effects.finalReads, 1);
  });

  test('a latched closeFailed Core is restarted and fully re-applied',
      () async {
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    // The proxy is still running, so without the restart this would take the
    // incremental path against a Core that can no longer open TUN.
    final effects = StabilityEffects(runtime, running: true)
      ..closeFailed = true;
    await launch(runtime, effects);
    expect(effects.coreRestarts, 1);
    expect(effects.fullApplications, 1);
    expect(effects.incrementalApplications, 0);
    expect(runtime.observed, TunObservedState.on);
    expect(runtime.status?.instanceId, 'core-1');
    expect(runtime.failure, isNull);
    expect(effects.reflectCalls, 1);
  });

  test('a healthy running Core is not restarted', () async {
    final runtime = TunRuntimeController();
    addTearDown(runtime.dispose);
    final effects = StabilityEffects(runtime, running: true);
    await launch(runtime, effects);
    expect(effects.coreRestarts, 0);
    expect(effects.incrementalApplications, 1);
    expect(effects.fullApplications, 0);
    expect(runtime.observed, TunObservedState.on);
  });

  group('vanished adapter on an elevated Core', () {
    const vanished = TunStatus(
        instanceId: 'core',
        revision: 3,
        state: 'failed',
        listenerActive: true,
        interfaceState: 'missing',
        privilege: 'elevated',
        requestedEnabled: true,
        errorCode: 'interfaceMissing');

    Future<bool?> applyWith({required bool explicit, String privilege = 'elevated'}) async {
      bool? applied;
      final status = TunStatus(
          instanceId: vanished.instanceId,
          revision: vanished.revision,
          state: vanished.state,
          listenerActive: vanished.listenerActive,
          interfaceState: vanished.interfaceState,
          privilege: privilege,
          requestedEnabled: vanished.requestedEnabled,
          errorCode: vanished.errorCode);
      expect(status.observed, TunObservedState.unknown);
      await applyWindowsTunConfiguration(
        componentsMatch: () async => true,
        observe: () async => status,
        desiredEnabled: () => true,
        explicitStop: () => false,
        explicitOperation: () => explicit,
        failedRequest: () => false,
        reportFailure: (_) {},
        invalidate: () {},
        apply: (enabled) async {
          applied = enabled;
          return '';
        },
      );
      return applied;
    }

    test('an explicit enable re-applies to rebuild the adapter', () async {
      expect(await applyWith(explicit: true), isTrue);
    });

    test('a background refresh never acts on the unknown observation',
        () async {
      await expectLater(applyWith(explicit: false),
          throwsA(isA<TunFailure>()
              .having((e) => e.code, 'code', 'statusUnavailable')));
    });

    test('an unprivileged Core is not treated as repairable', () async {
      await expectLater(applyWith(explicit: true, privilege: 'unprivileged'),
          throwsA(isA<TunFailure>()
              .having((e) => e.code, 'code', 'statusUnavailable')));
    });
  });

  group('observation failures are not request failures', () {
    test('poll invalidation keeps background TUN configuration enabled',
        () async {
      final runtime = TunRuntimeController()..desiredEnabled = true;
      addTearDown(runtime.dispose);
      runtime
        ..invalidate('statusUnavailable')
        ..fail('statusUnavailable');
      expect(runtime.failure, 'statusUnavailable');
      expect(runtime.requestFailure, isNull);
      bool? applied;
      await applyWindowsTunConfiguration(
        componentsMatch: () async => true,
        observe: () async => const TunStatus(
            instanceId: 'core',
            revision: 1,
            state: 'off',
            listenerActive: false,
            interfaceState: 'missing',
            privilege: 'elevated',
            requestedEnabled: true),
        desiredEnabled: () => true,
        explicitStop: () => false,
        explicitOperation: () => runtime.busy,
        failedRequest: () => runtime.requestFailure != null,
        reportFailure: runtime.fail,
        invalidate: runtime.invalidate,
        apply: (enabled) async {
          applied = enabled;
          return '';
        },
      );
      expect(applied, isTrue,
          reason: 'a timed-out status poll is not a failed user request');
    });

    test('a failed request still blocks background re-enable', () async {
      final runtime = TunRuntimeController();
      addTearDown(runtime.dispose);
      await runtime.request(true, (_) async {
        throw const TunFailure('permissionDenied');
      });
      expect(runtime.requestFailure, 'permissionDenied');
      runtime.fail('statusUnavailable');
      expect(runtime.requestFailure, 'permissionDenied',
          reason: 'observation noise must not erase a real request failure');
    });

    test('a matching observation clears the request failure', () {
      final runtime = TunRuntimeController()..desiredEnabled = true;
      addTearDown(runtime.dispose);
      runtime.fail('authorizationRequired');
      expect(runtime.requestFailure, 'authorizationRequired');
      runtime.accept(
          const TunStatus(
              instanceId: 'core',
              revision: 1,
              state: 'on',
              listenerActive: true,
              interfaceState: 'up',
              privilege: 'elevated',
              requestedEnabled: true),
          runtime.observationEpoch);
      expect(runtime.requestFailure, isNull);
    });
  });
}

class _SlowCreation extends StabilityEffects {
  _SlowCreation(super.runtime, {required this.transitional});
  final int transitional;

  @override
  Future<bool> startListener() async {
    final started = await super.startListener();
    transitionalReads = transitional;
    return started;
  }
}

class _NeverOn extends StabilityEffects {
  _NeverOn(super.runtime);
  bool listening = false;
  int finalReads = 0;

  @override
  Future<bool> startListener() async {
    running = true;
    listening = true;
    revision++;
    return true;
  }

  @override
  Future<TunStatus> read() async {
    if (listening) finalReads++;
    return TunStatus(
        instanceId: 'core',
        revision: revision,
        state: 'off',
        listenerActive: false,
        interfaceState: 'missing',
        privilege: 'elevated',
        requestedEnabled: true);
  }
}
