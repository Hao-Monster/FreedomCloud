import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_startup.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/clash_config_update_listener.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/tun_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class StartupEffects implements WindowsTunStartupEffects {
  final calls = <String>[];
  bool running = false;
  bool enabled = false;
  bool elevated = false;
  bool profile = true;
  bool authorized = true;
  bool listenerSucceeds = true;
  bool configurationSucceeds = true;
  bool initializationSucceeds = true;
  bool proveOn = true;
  int backgroundConfigurations = 0;
  void Function()? duringMatch;
  String? pauseAt;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> record(String call) async {
    calls.add(call);
    if (pauseAt == call && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
  }

  @override
  bool get proxyRunning => running;
  @override
  Future<bool> hasProfile() async {
    await record('profile');
    return profile;
  }

  @override
  Future<TunStatus?> observe() async {
    await record('observe');
    return TunStatus(
        instanceId: 'core',
        revision: calls.length,
        state: enabled && proveOn ? 'on' : 'off',
        listenerActive: enabled && proveOn,
        interfaceState: enabled ? 'up' : 'missing',
        privilege: elevated ? 'elevated' : 'unprivileged',
        requestedEnabled: enabled);
  }

  @override
  Future<bool> componentsMatch() async {
    await record('match');
    duringMatch?.call();
    return true;
  }

  @override
  bool canMigrate() => true;
  @override
  Future<bool> authorize() async {
    await record('authorize');
    return authorized;
  }

  @override
  Future<bool> ensureBackend(bool Function() isCurrent) async {
    await record('backend');
    elevated = true;
    return true;
  }

  @override
  Future<void> initialize(bool Function() isCurrent) async {
    await record('initialize');
    if (!initializationSucceeds) throw const TunFailure('configurationFailed');
    if (isCurrent()) calls.add('initialized');
  }

  @override
  Future<void> applyConfiguration(
      {required bool full, required bool Function() isCurrent}) async {
    await record(full ? 'configure' : 'incremental');
    if (!isCurrent()) return;
    if (!configurationSucceeds) throw const TunFailure('configurationFailed');
    if (running) enabled = true;
  }

  @override
  Future<bool> startListener() async {
    await record('listener');
    if (listenerSucceeds) {
      running = true;
      enabled = true;
    }
    return listenerSucceeds;
  }

  @override
  Future<void> stopProxy() async {
    await record('stop-proxy');
    running = false;
    enabled = false;
  }

  @override
  Future<void> reflectRunning(bool Function() isCurrent) async {
    if (isCurrent()) await record('reflect');
  }

  @override
  Future<void> startProxyWithoutTun() async {
    await record('proxy-only');
    running = true;
  }

  final logs = <String>[];
  @override
  void log(String message) => logs.add(message);
}

Future<AppController> controllerFixture(
    WidgetTester tester, StartupEffects effects, TunRuntimeController runtime,
    {bool savedAutoRun = false, bool savedTun = true}) async {
  globalState.config = Config(
      themeProps: defaultThemeProps,
      appSetting: AppSettingProps(autoRun: savedAutoRun),
      patchClashConfig: ClashConfig(tun: Tun(enable: savedTun)));
  AppController? controller;
  await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: ClashConfigUpdateListener(
              runtime: runtime,
              isWindows: true,
              onConfigChanged: () {
                effects.backgroundConfigurations++;
              },
              child: Consumer(
                builder: (context, ref, _) {
                  controller ??= AppController(context, ref,
                      windowsStartupEffects: effects,
                      tunRuntimeController: runtime);
                  return Material(
                      child: AnimatedBuilder(
                          animation: runtime,
                          builder: (_, __) => TunStatusSwitch(
                              runtime: runtime,
                              onChanged: controller!.setTunEnabled)));
                },
              )))));
  return controller!;
}

void main() {
  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });
  test('fresh install defaults TUN preference to enabled', () {
    expect(const Config(themeProps: defaultThemeProps).patchClashConfig.tun.enable,
        isTrue);
    expect(Tun.safeFormJson(null).enable, isTrue);
    expect(Tun.fromJson(const {}).enable, isTrue);
  });

  for (final autoRun in [false, true]) {
    testWidgets(
        'controller launch enables proxy and TUN with saved autoRun=$autoRun,tun=true',
        (tester) async {
      final effects = StartupEffects();
      final runtime = TunRuntimeController();
      final controller = await controllerFixture(tester, effects, runtime,
          savedAutoRun: autoRun, savedTun: true);
      await controller.initializeRuntime();
      expect(
          effects.calls,
          containsAllInOrder([
            'profile',
            'authorize',
            'backend',
            'initialize',
            'configure',
            'listener',
            'reflect'
          ]));
      expect(effects.running, isTrue);
      expect(runtime.observed, TunObservedState.on);
      expect(globalState.config.patchClashConfig.tun.enable, isTrue);
      expect(effects.logs.last, contains('TUN observed=on'));
      expect(effects.backgroundConfigurations, 0);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ClashConfigUpdateListener)));
      container
          .read(patchClashConfigProvider.notifier)
          .updateState((s) => s.copyWith(mode: Mode.global));
      await tester.pump();
      expect(effects.backgroundConfigurations, 1,
          reason:
              'the actual manager listener is live, not replaced by a test copy');
    });

    testWidgets(
        'saved TUN off is respected: proxy only, no UAC, autoRun=$autoRun',
        (tester) async {
      final effects = StartupEffects();
      final runtime = TunRuntimeController();
      final controller = await controllerFixture(tester, effects, runtime,
          savedAutoRun: autoRun, savedTun: false);
      await controller.initializeRuntime();
      expect(effects.calls, ['proxy-only']);
      expect(effects.running, isTrue);
      expect(effects.enabled, isFalse);
      expect(runtime.isEnabled, isFalse);
      expect(globalState.config.patchClashConfig.tun.enable, isFalse,
          reason: 'an existing user preference must not be overwritten');
      expect(effects.logs.single, contains('saved TUN preference is off'));
      await tester.pump();
      expect(effects.backgroundConfigurations, 0);
    });
  }

  testWidgets('manager ownership preserves mixed and later external changes',
      (tester) async {
    final effects = StartupEffects();
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.initializeRuntime();
    await tester.pump();
    expect(effects.backgroundConfigurations, 0);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(ClashConfigUpdateListener)));
    final notifier = container.read(patchClashConfigProvider.notifier)
      ..updateState(
          (s) => s.copyWith(mode: Mode.global, tun: s.tun.copyWith(enable: false)));
    await tester.pump();
    expect(effects.backgroundConfigurations, 1);
    notifier.updateState((s) => s.copyWith(tun: s.tun.copyWith(enable: true)));
    await tester.pump();
    expect(effects.backgroundConfigurations, 2);
    notifier.updateState((s) => s.copyWith(tun: s.tun.copyWith(enable: false)));
    await tester.pump();
    expect(effects.backgroundConfigurations, 3);
  });

  testWidgets('initialization failure prevents configuration and listener',
      (tester) async {
    final effects = StartupEffects()..initializationSucceeds = false;
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.initializeRuntime();
    expect(runtime.failure, 'configurationFailed');
    expect(effects.calls, contains('initialize'));
    expect(effects.calls, isNot(contains('configure')));
    expect(effects.calls, isNot(contains('listener')));
    expect(effects.calls, isNot(contains('reflect')));
    expect(effects.running, isFalse);
  });

  testWidgets(
      'actual proxy stop revokes startup authorization before queued effects',
      (tester) async {
    final effects = StartupEffects()..pauseAt = 'authorize';
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    final launch = controller.initializeRuntime();
    await effects.entered.future;
    final stop = controller.updateStatus(false);
    effects.release.complete();
    await Future.wait([launch, stop]);
    expect(effects.calls, contains('stop-proxy'));
    expect(effects.calls, isNot(contains('backend')));
    expect(effects.calls, isNot(contains('listener')));
    expect(effects.running, isFalse);
    expect(runtime.observed, TunObservedState.off);
    expect(runtime.desiredEnabled, isTrue,
        reason: 'proxy stop preserves the separate TUN preference');
    await controller.initializeRuntime();
    expect(effects.calls.where((c) => c == 'authorize').length, 1);
  });

  testWidgets(
      'duplicate launch and same-session manual off do not auto-enable again',
      (tester) async {
    final effects = StartupEffects();
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    final first = controller.initializeRuntime();
    expect(identical(first, controller.initializeRuntime()), isTrue);
    await first;
    await runtime.request(false, (_) async {
      effects.enabled = false;
    });
    await controller.initializeRuntime();
    expect(effects.calls.where((c) => c == 'listener').length, 1);
    expect(runtime.desiredEnabled, isFalse);
    expect(effects.enabled, isFalse);
  });

  testWidgets(
      'already running observed on adopts without local profile or writes',
      (tester) async {
    final effects = StartupEffects()
      ..running = true
      ..enabled = true
      ..elevated = true
      ..profile = false;
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.initializeRuntime();
    expect(effects.calls, ['observe', 'match', 'reflect']);
    expect(runtime.isEnabled, isTrue);
    await tester.pump();
    expect(effects.backgroundConfigurations, 0);
  });

  testWidgets('missing profile never prompts or changes backend',
      (tester) async {
    final effects = StartupEffects()..profile = false;
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.initializeRuntime();
    expect(runtime.failure, 'profileRequired');
    expect(effects.calls, ['observe', 'match', 'profile']);
    expect(effects.backgroundConfigurations, 0);
  });

  testWidgets(
      'disconnect while matching components cannot adopt an old on snapshot',
      (tester) async {
    final effects = StartupEffects()
      ..running = true
      ..enabled = true
      ..elevated = true;
    final runtime = TunRuntimeController();
    effects.duringMatch = () => runtime.invalidate('statusUnavailable');
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.initializeRuntime();
    expect(runtime.observed, TunObservedState.unknown);
    expect(runtime.failure, 'statusUnavailable');
    expect(effects.calls, isNot(contains('reflect')));
    expect(effects.calls, isNot(contains('listener')));
  });

  testWidgets(
      'cancelled launch retries through the existing TUN switch without proxy click',
      (tester) async {
    final effects = StartupEffects()..authorized = false;
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.initializeRuntime();
    await controller.initializeRuntime();
    expect(effects.calls.where((c) => c == 'authorize').length, 1);
    expect(runtime.failure, 'permissionDenied');
    expect(effects.running, isFalse);
    expect(effects.calls, isNot(contains('backend')));
    effects.authorized = true;
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(effects.calls.where((c) => c == 'authorize').length, 2);
    expect(effects.running, isTrue);
    expect(runtime.observed, TunObservedState.on);
    expect(runtime.failure, isNull);
    expect(effects.backgroundConfigurations, 0);
  });

  testWidgets(
      'running proxy re-enables TUN incrementally without replacing flows',
      (tester) async {
    final effects = StartupEffects()
      ..running = true
      ..elevated = true;
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    await controller.setTunEnabled(true);
    expect(effects.calls, contains('incremental'));
    expect(effects.calls, isNot(contains('configure')));
    expect(effects.calls, isNot(contains('listener')));
    expect(effects.calls, isNot(contains('authorize')));
    expect(runtime.isEnabled, isTrue);
  });

  for (final phase in [
    'profile',
    'authorize',
    'initialize',
    'configure',
    'listener'
  ]) {
    testWidgets('new disable during $phase prevents later launch effects',
        (tester) async {
      final effects = StartupEffects()..pauseAt = phase;
      // Exercise normal initialization cancellation separately from committed
      // migration restoration, which deliberately finishes required init.
      if (phase == 'initialize') effects.elevated = true;
      final runtime = TunRuntimeController();
      final controller = await controllerFixture(tester, effects, runtime);
      final launch = controller.initializeRuntime();
      await effects.entered.future;
      final off = runtime.request(false, (_) async {
        effects.enabled = false;
      });
      effects.release.complete();
      await Future.wait([launch, off]);
      expect(effects.calls, isNot(contains('reflect')));
      if (phase != 'listener') {
        expect(effects.calls, isNot(contains('listener')));
      }
      if (phase == 'initialize') {
        expect(effects.calls, isNot(contains('initialized')));
      }
      expect(runtime.desiredEnabled, isFalse);
    });
  }

  testWidgets('exit during committed migration restores only necessary init',
      (tester) async {
    final effects = StartupEffects()..pauseAt = 'backend';
    final runtime = TunRuntimeController();
    final controller = await controllerFixture(tester, effects, runtime);
    final launch = controller.initializeRuntime();
    await effects.entered.future;
    final exit = runtime.quiesce(() async {
      effects.calls.add('exit');
    });
    effects.release.complete();
    await Future.wait([launch, exit]);
    expect(effects.calls,
        containsAllInOrder(['backend', 'initialize', 'initialized', 'exit']));
    expect(effects.calls, isNot(contains('configure')));
    expect(effects.calls, isNot(contains('listener')));
    expect(effects.calls, isNot(contains('reflect')));
  });

  for (final failure in ['configuration', 'listener', 'observation']) {
    testWidgets('$failure failure cannot report a connected startup',
        (tester) async {
      final effects = StartupEffects()
        ..configurationSucceeds = failure != 'configuration'
        ..listenerSucceeds = failure != 'listener'
        ..proveOn = failure != 'observation';
      final runtime = TunRuntimeController();
      final controller = await controllerFixture(tester, effects, runtime);
      await controller.initializeRuntime();
      expect(runtime.failure,
          failure == 'configuration' ? 'configurationFailed' : 'startFailed');
      expect(runtime.isEnabled, isFalse);
      expect(effects.calls, isNot(contains('reflect')));
      if (failure == 'configuration') {
        expect(effects.calls, isNot(contains('listener')));
      }
    });
  }

  test(
      'local profile preflight rejects missing, unreadable, invalid UTF8 and empty files',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('tun-startup-profile-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/profile.yaml');
    expect(await isReadableWindowsStartupProfile(null), isFalse);
    expect(await isReadableWindowsStartupProfile(file.path), isFalse);
    expect(await isReadableWindowsStartupProfile(directory.path), isFalse);
    await file.writeAsString(' \n');
    expect(await isReadableWindowsStartupProfile(file.path), isFalse);
    await file.writeAsBytes([0xff]);
    expect(await isReadableWindowsStartupProfile(file.path), isFalse);
    await file.writeAsString('mode: rule\n');
    expect(await isReadableWindowsStartupProfile(file.path), isTrue);
  });
}
