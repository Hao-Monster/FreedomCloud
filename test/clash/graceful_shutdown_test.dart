import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_startup.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/proxy_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/widgets/quick_options.dart';
import 'package:flclashx/views/dashboard/widgets/start_button.dart';
import 'package:flclashx/widgets/tun_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:proxy/proxy_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String> getApplicationSupportPath() async => root;
  @override
  Future<String> getTemporaryPath() async => root;
  @override
  Future<String> getDownloadsPath() async => root;
}

class _RecordingProxyPlatform extends ProxyPlatform {
  _RecordingProxyPlatform(this.events);
  final List<String> events;

  @override
  Future<bool?> startProxy(int port, List<String> bypassDomain) async {
    events.add('plugin:startProxy:$port');
    return true;
  }

  @override
  Future<bool?> stopProxy() async {
    events.add('plugin:stopProxy');
    return true;
  }

  @override
  Future<bool?> startPac(String url) async {
    events.add('plugin:startPac:$url');
    return true;
  }
}

class _GracefulStopEffects implements WindowsTunStartupEffects {
  _GracefulStopEffects(this.events);

  final List<String> events;
  bool running = true;
  int revision = 1;
  String instanceId = 'core-initial';
  bool failStopWithCloseFailed = false;
  bool keepCloseFailedAfterRestart = false;
  Object? throwOnStopProxy;
  Completer<void>? pauseStopProxy;
  VoidCallback? onStopProxyCompleted;

  @override
  bool get proxyRunning => running;

  @override
  Future<bool> hasProfile() async => true;

  @override
  Future<TunStatus?> observe() async {
    events.add('core:observe:$instanceId');
    final isCloseFailed = !running && failStopWithCloseFailed;
    return TunStatus(
      instanceId: instanceId,
      revision: ++revision,
      state: running ? 'on' : (isCloseFailed ? 'failed' : 'off'),
      listenerActive: running || isCloseFailed,
      interfaceState: (running || isCloseFailed) ? 'up' : 'missing',
      privilege: 'elevated',
      requestedEnabled: running,
      errorCode: isCloseFailed ? 'closeFailed' : null,
    );
  }

  @override
  Future<void> stopProxy() async {
    events.add('core:stopProxy');
    if (pauseStopProxy != null) {
      await pauseStopProxy!.future;
    }
    if (throwOnStopProxy != null) {
      Error.throwWithStackTrace(throwOnStopProxy!, StackTrace.current);
    }
    running = false;
    globalState.startTime = null;
    onStopProxyCompleted?.call();
  }

  @override
  Future<void> applyConfiguration({
    required bool full,
    required bool Function() isCurrent,
  }) async {
    events.add('core:applyConfig:full=$full');
    running = false;
  }

  @override
  Future<void> restartCore() async {
    events.add('core:restartCore');
    instanceId = 'core-reclaimed';
    running = false;
    if (!keepCloseFailedAfterRestart) {
      failStopWithCloseFailed = false;
    }
  }

  @override
  Future<void> initialize(bool Function() isCurrent) async {
    events.add('core:initialize');
  }

  @override
  void log(String message) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WidgetToggleController implements AppController {
  int updateStatusCalls = 0;
  bool? lastRequestedStart;
  Completer<void>? pendingToggle;
  ProviderContainer? container;

  @override
  Future<void> updateStatus(bool isStart) async {
    updateStatusCalls++;
    lastRequestedStart = isStart;
    if (pendingToggle != null) {
      await pendingToggle!.future;
    }
    container?.read(runTimeProvider.notifier).value = isStart ? 1000 : null;
  }

  @override
  Future<void> setTunEnabled(bool enabled) async {
    container?.read(patchClashConfigProvider.notifier).updateState(
          (state) => state.copyWith.tun(enable: enabled),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void _seedBaseState({
  bool running = true,
  bool tunEnabled = true,
  bool systemProxy = true,
  int mixedPort = 7890,
  bool hasProfile = true,
}) {
  globalState.config = Config(
    themeProps: defaultThemeProps,
    profiles: hasProfile
        ? const [
            Profile(
              id: 'p1',
              label: 'Test Profile',
              url: 'https://example.com/sub',
              autoUpdateDuration: Duration(hours: 24),
            ),
          ]
        : const [],
    currentProfileId: hasProfile ? 'p1' : null,
    networkProps: NetworkProps(systemProxy: systemProxy),
    patchClashConfig: defaultClashConfig.copyWith(
      mixedPort: mixedPort,
      tun: defaultClashConfig.tun.copyWith(enable: tunEnabled),
    ),
  );
  globalState.appState = AppState(
    isInit: true,
    runTime: running ? 120000 : null,
    viewSize: const Size(960, 720),
    version: 1,
    requests: FixedList(5),
    logs: FixedList(5),
    traffics: FixedList(5),
    totalTraffic: Traffic(),
  );
  globalState.startTime =
      running ? DateTime.now().subtract(const Duration(minutes: 2)) : null;
}

Widget _wrapMaterial({
  required Widget child,
  required ProviderContainer container,
}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) {
            globalState.measure = Measure.of(context, 1.0);
            globalState.theme = CommonTheme.of(context, 1.0);
            return Scaffold(body: child);
          },
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProxyPlatform originalProxyPlatform;
  late PathProviderPlatform originalPaths;
  late Directory testRootDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    originalPaths = PathProviderPlatform.instance;
    testRootDir = Directory.systemTemp.createTempSync('fcx_graceful_stop_');
    PathProviderPlatform.instance = _TestPaths(testRootDir.path);
    await AppLocalizations.load(const Locale('zh', 'CN'));
    originalProxyPlatform = ProxyPlatform.instance;
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (testRootDir.existsSync()) {
      try {
        testRootDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProxyPlatform.instance = originalProxyPlatform;
  });

  tearDown(() {
    ProxyPlatform.instance = originalProxyPlatform;
    debouncer.cancel(FunctionTag.updateStatus);
    globalState.stopUpdateTasks();
    globalState.startTime = null;
  });

  testWidgets(
    'GS-02 & GS-03: updateStatus(false) disarms System Proxy BEFORE Core stop, avoids duplicate WinInet calls, and flushes Fake-IP DNS cache after TUN closes',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final events = <String>[];
      ProxyPlatform.instance = _RecordingProxyPlatform(events);

      final runtime = TunRuntimeController()..desiredEnabled = true;
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        ),
        runtime.observationEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      final effects = _GracefulStopEffects(events)
        ..onStopProxyCompleted = () {
          container.read(runTimeProvider.notifier).value = null;
        };

      AppController? controller;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: ProxyManager(
            child: Consumer(
              builder: (context, ref, _) {
                controller ??= AppController(
                  context,
                  ref,
                  windowsStartupEffects: effects,
                  tunRuntimeController: runtime,
                  tunSettleDelay: Duration.zero,
                  flushSystemDnsCache: () async {
                    events.add('os:flushDnsCache');
                  },
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(events, contains('plugin:startProxy:7890'));
      events.clear();

      await controller!.updateStatus(false);
      await tester.pumpAndSettle();

      final pluginStopIdx = events.indexOf('plugin:stopProxy');
      final coreStopIdx = events.indexOf('core:stopProxy');
      final dnsFlushIdx = events.indexOf('os:flushDnsCache');
      expect(pluginStopIdx, greaterThanOrEqualTo(0),
          reason: 'System proxy must be explicitly disarmed on stop');
      expect(coreStopIdx, greaterThanOrEqualTo(0));
      expect(dnsFlushIdx, greaterThanOrEqualTo(0),
          reason: 'System DNS cache must be flushed after Fake-IP TUN teardown');
      expect(
        pluginStopIdx,
        lessThan(coreStopIdx),
        reason:
            'System proxy MUST disarm while Core MixedPort is still alive to prevent ERR_PROXY_CONNECTION_FAILED blackhole',
      );
      expect(
        coreStopIdx,
        lessThan(dnsFlushIdx),
        reason: 'Fake-IP DNS flush must occur after Core TUN listener stops',
      );
      expect(
        events.where((e) => e == 'plugin:stopProxy').length,
        1,
        reason:
            'runTimeProvider -> null must hit O(1) signature dedup and not fire a second WinInet broadcast',
      );
    },
  );

  testWidgets(
    'GS-03: setTunEnabled(false) also flushes Fake-IP DNS cache once Wintun settles off',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final events = <String>[];
      final runtime = TunRuntimeController()..desiredEnabled = true;
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        ),
        runtime.observationEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      final effects = _GracefulStopEffects(events);
      AppController? controller;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              controller ??= AppController(
                context,
                ref,
                windowsStartupEffects: effects,
                tunRuntimeController: runtime,
                tunSettleDelay: Duration.zero,
                flushSystemDnsCache: () async {
                  events.add('os:flushDnsCache');
                },
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      await controller!.setTunEnabled(false);
      await tester.pumpAndSettle();

      expect(runtime.observed, TunObservedState.off);
      expect(events, contains('os:flushDnsCache'));
    },
  );

  testWidgets(
    'GS-05: updateStatus(false) reports TunOperation.disabling ("正在关闭...") during teardown and reclaims stuck Wintun via UAC-free restartCore on closeFailed',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true);
      final events = <String>[];
      final stopGate = Completer<void>();

      final runtime = TunRuntimeController()..desiredEnabled = true;
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        ),
        runtime.observationEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      final effects = _GracefulStopEffects(events)
        ..pauseStopProxy = stopGate
        ..failStopWithCloseFailed = true
        ..onStopProxyCompleted = () {
          container.read(runTimeProvider.notifier).value = null;
        };

      AppController? controller;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              controller ??= AppController(
                context,
                ref,
                windowsStartupEffects: effects,
                tunRuntimeController: runtime,
                tunSettleDelay: Duration.zero,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      final stopFuture = controller!.updateStatus(false);
      await tester.pump();

      expect(runtime.operation, TunOperation.disabling);
      expect(tunStatusLabel(runtime), appLocalizations.tunStatusStopping);

      stopGate.complete();
      await stopFuture;
      await tester.pumpAndSettle();

      expect(events, contains('core:restartCore'));
      expect(events, contains('core:initialize'));
      expect(runtime.operation, TunOperation.idle);
      expect(runtime.observed, TunObservedState.off);
      expect(runtime.failure, isNull);
    },
  );

  testWidgets(
    'GS-06: StartButton dispatches updateStatus(false) at 0ms without 400ms debounce, renders stopping transition, and TUNButton + SystemProxyButton reflect honest stopped state',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final runtime = TunRuntimeController()..desiredEnabled = true;
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        ),
        runtime.observationEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      final pendingToggle = Completer<void>();
      final fakeController = _WidgetToggleController()
        ..container = container
        ..pendingToggle = pendingToggle;
      globalState.appController = fakeController;

      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: const Column(
            children: [
              TUNButton(),
              SystemProxyButton(),
              StartButton(),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text(appLocalizations.tunStatusOn), findsNWidgets(2));

      // Tap StartButton -> MUST invoke updateStatus(false) immediately at 0ms (no 400ms debounce!).
      final toggleFinder = find.byKey(const ValueKey('dashboard-proxy-toggle'));
      await tester.tap(toggleFinder);
      await tester.pump();

      expect(
        fakeController.updateStatusCalls,
        1,
        reason:
            'StartButton must dispatch updateStatus(false) immediately without 400ms debounce',
      );
      expect(fakeController.lastRequestedStart, isFalse);
      expect(find.text(appLocalizations.tunStatusStopping), findsOneWidget);

      // Duplicate tap while stopping must be ignored.
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(fakeController.updateStatusCalls, 1);

      // Simulate TUN teardown completing and proxy stopping.
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 2,
          state: 'off',
          listenerActive: false,
          interfaceState: 'missing',
          privilege: 'elevated',
          requestedEnabled: false,
        ),
        runtime.observationEpoch,
      );
      pendingToggle.complete();
      await tester.pumpAndSettle();

      // Both TUNButton and SystemProxyButton must show "等待代理启动" and unchecked Switches!
      expect(
        find.text(appLocalizations.tunStatusWaiting),
        findsNWidgets(2),
        reason:
            'Both TUNButton and SystemProxyButton must reactively show "等待代理启动" when proxy stops',
      );
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.every((s) => !s.value), isTrue,
          reason:
              'Neither TUN switch nor SystemProxy switch may remain checked while proxy is stopped');
    },
  );

  testWidgets(
    'CR-GS-01: updateStatus(false) throwing before clearing runTimeProvider automatically re-arms System Proxy via lease reconcile',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final events = <String>[];
      ProxyPlatform.instance = _RecordingProxyPlatform(events);

      final runtime = TunRuntimeController()..desiredEnabled = true;
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        ),
        runtime.observationEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      final effects = _GracefulStopEffects(events)
        ..throwOnStopProxy = StateError('simulated stopProxy failure');

      AppController? controller;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: ProxyManager(
            child: Consumer(
              builder: (context, ref, _) {
                controller ??= AppController(
                  context,
                  ref,
                  windowsStartupEffects: effects,
                  tunRuntimeController: runtime,
                  tunSettleDelay: Duration.zero,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events, contains('plugin:startProxy:7890'));
      events.clear();

      await expectLater(controller!.updateStatus(false), throwsStateError);
      await tester.pumpAndSettle();

      final stopIdx = events.indexOf('plugin:stopProxy');
      final rearmIdx = events.lastIndexOf('plugin:startProxy:7890');
      expect(stopIdx, greaterThanOrEqualTo(0));
      expect(
        rearmIdx,
        greaterThan(stopIdx),
        reason:
            'Because stopProxy failed while proxy is still running (runTimeProvider != null), SystemProxyCoordinator must re-arm System Proxy upon releasing the disarm lease',
      );
    },
  );

  testWidgets(
    'CR-GS-02a: StartButton ignores <500ms accidental double-click during start, then allows >=500ms tap to cancel a hung start',
    (tester) async {
      _seedBaseState(running: false, tunEnabled: true, systemProxy: true);
      final events = <String>[];
      final hangGate = Completer<void>();

      final runtime = TunRuntimeController()..desiredEnabled = true;
      // Hold serialize lock so updateStatus(true) enters pending state without touching native FFI.
      final holdFuture = runtime.serialize(() => hangGate.future);

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      final effects = _GracefulStopEffects(events)
        ..running = false
        ..onStopProxyCompleted = () {
          container.read(runTimeProvider.notifier).value = null;
        };

      AppController? controller;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              controller ??= AppController(
                context,
                ref,
                windowsStartupEffects: effects,
                tunRuntimeController: runtime,
                tunSettleDelay: Duration.zero,
              );
              globalState.appController = controller!;
              return const StartButton();
            },
          ),
        ),
      );
      await tester.pump();

      // Tap 1: initiates Start -> pending == true ("正在开启...").
      final toggleFinder = find.byKey(const ValueKey('dashboard-proxy-toggle'));
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(container.read(statusSwitchPendingProvider), isTrue);
      expect(find.text(appLocalizations.tunStatusStarting), findsOneWidget);

      // Tap 2 at 120ms (<500ms accidental double-click window): MUST be ignored!
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(
        container.read(statusSwitchPendingProvider),
        isTrue,
        reason:
            'Accidental double-click within 500ms of Start must NOT cancel the in-flight Start',
      );

      // Advance past 500ms (total 560ms >= 500ms): Tap 3 MUST cancel the hung Start!
      await tester.pump(const Duration(milliseconds: 440));
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(
        container.read(statusSwitchPendingProvider),
        isFalse,
        reason:
            'Tapping StartButton after >=500ms while still starting must dispatch updateStatus(false) to abort the hung Start',
      );
      expect(find.text(appLocalizations.tunStatusStopping), findsOneWidget);

      // Release serialize queue and settle cleanly.
      hangGate.complete();
      await holdFuture;
      await tester.pumpAndSettle();
      expect(container.read(statusSwitchPendingProvider), isNull);
    },
  );

  testWidgets(
    'CR-GS-02b: concurrent updateStatus(true) queued while updateStatus(false) is tearing down does not trigger spurious _repairVanishedAdapter',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final events = <String>[];
      final stopGate = Completer<void>();

      final runtime = TunRuntimeController()..desiredEnabled = true;
      runtime.accept(
        const TunStatus(
          instanceId: 'core-initial',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        ),
        runtime.observationEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      var returnMissingWhileStopping = false;
      final effects = _GracefulStopEffects(events)..pauseStopProxy = stopGate;

      AppController? controller;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              controller ??= AppController(
                context,
                ref,
                windowsStartupEffects: _InterceptObserveEffects(
                  effects,
                  () => returnMissingWhileStopping
                      ? const TunStatus(
                          instanceId: 'core-initial',
                          revision: 99,
                          state: 'degraded',
                          listenerActive: true,
                          interfaceState: 'missing',
                          privilege: 'elevated',
                          requestedEnabled: true,
                          errorCode: 'interfaceMissing',
                        )
                      : null,
                ),
                tunRuntimeController: runtime,
                tunSettleDelay: Duration.zero,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      // Mark runtime initialized via a no-op observe check.
      await controller!.refreshWindowsTunStatus(fresh: true);

      // Begin stop (paused inside stopProxy), then enqueue Start (which clears _pendingWindowsProxyStop)
      // followed by a final Stop so Start itself won't touch FFI when stopGate releases.
      final stop1 = controller!.updateStatus(false);
      await tester.pump();
      final queuedStart = controller!.updateStatus(true);
      returnMissingWhileStopping = true;
      await controller!.refreshWindowsTunStatus(fresh: true);
      returnMissingWhileStopping = false;
      final stop2 = controller!.updateStatus(false);

      stopGate.complete();
      await Future.wait([stop1, queuedStart, stop2]);
      await tester.pumpAndSettle();

      expect(
        events.where((e) => e.startsWith('core:applyConfig')),
        isEmpty,
        reason:
            '_applyingWindowsConfigDepth must guard !isStart teardown so background observations never trigger _repairVanishedAdapter mid-stop',
      );
    },
  );

  testWidgets(
    'CR-GS-05: SystemProxyButton disables Switch when mixedPort == 0, skips updateStatus(true) without profile, and StartButton keeps active green palette throughout stopping',
    (tester) async {
      // Case 1: mixedPort == 0 -> Switch must be disabled (onChanged == null).
      _seedBaseState(
        running: false,
        tunEnabled: false,
        systemProxy: false,
        mixedPort: 0,
      );
      final container1 = ProviderContainer();
      addTearDown(container1.dispose);
      final fakeController1 = _WidgetToggleController()..container = container1;
      globalState.appController = fakeController1;

      await tester.pumpWidget(
        _wrapMaterial(
          container: container1,
          child: const SystemProxyButton(),
        ),
      );
      await tester.pump();
      final disabledSwitch = tester.widget<Switch>(find.byType(Switch));
      expect(
        disabledSwitch.onChanged,
        isNull,
        reason: 'SystemProxyButton Switch must be disabled when mixedPort <= 0',
      );

      // Case 2: mixedPort == 7890 but hasProfile == false -> toggling Switch updates preference ONLY and does NOT call updateStatus(true).
      _seedBaseState(
        running: false,
        tunEnabled: false,
        systemProxy: false,
        mixedPort: 7890,
        hasProfile: false,
      );
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final fakeController2 = _WidgetToggleController()..container = container2;
      globalState.appController = fakeController2;

      await tester.pumpWidget(
        _wrapMaterial(
          container: container2,
          child: const SystemProxyButton(),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(container2.read(networkSettingProvider).systemProxy, isTrue);
      expect(
        fakeController2.updateStatusCalls,
        0,
        reason:
            'SystemProxyButton must not invoke updateStatus(true) when no profile is selected',
      );

      // Case 3: StartButton keeps active green palette while statusSwitchPendingProvider == false even after runTimeProvider clears to null.
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final container3 = ProviderContainer();
      addTearDown(container3.dispose);
      final fakeController3 = _WidgetToggleController()..container = container3;
      globalState.appController = fakeController3;

      container3.read(statusSwitchPendingProvider.notifier).state = false;
      container3.read(runTimeProvider.notifier).value = null;

      await tester.pumpWidget(
        _wrapMaterial(
          container: container3,
          child: const StartButton(),
        ),
      );
      await tester.pump();

      final surface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('dashboard-floating-proxy-dock-surface')),
      );
      final decoration = surface.decoration as BoxDecoration;
      final expectedBgColor = Color.alphaBlend(
        kLatencyFastColor.withValues(alpha: 0.14),
        const Color(0xFF111826).withValues(alpha: 0.96),
      );
      expect(
        decoration.color,
        expectedBgColor,
        reason:
            'StartButton must retain active green palette throughout "正在关闭..." without flashing grey mid-teardown',
      );
      expect(
        (decoration.border! as Border).top.color,
        kLatencyFastColor.withValues(alpha: 0.48),
      );
      expect(find.text(appLocalizations.tunStatusStopping), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'CR-GS-04: handleExit skips stopListener 3s wait when Agent Core is already stopped without re-arming System Proxy, and handleClear disarms System Proxy + flushes DNS',
    (tester) async {
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      final events = <String>[];
      ProxyPlatform.instance = _RecordingProxyPlatform(events);

      final runtime = TunRuntimeController()..desiredEnabled = true;
      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime),
        ],
      );
      addTearDown(container.dispose);

      var stopListenerCalled = false;
      final effects = _GracefulStopEffects(events);

      AppController? controller;
      var agentCoreReady = false;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container,
          child: ProxyManager(
            child: Consumer(
              builder: (context, ref, _) {
                controller ??= AppController(
                  context,
                  ref,
                  windowsStartupEffects: effects,
                  tunRuntimeController: runtime,
                  tunSettleDelay: Duration.zero,
                  flushSystemDnsCache: () async {
                    events.add('os:flushDnsCache');
                  },
                  shutdownEffects: AppShutdownEffects(
                    usesAgent: () => true,
                    agentCoreReady: () => agentCoreReady,
                    stopListener: () async {
                      stopListenerCalled = true;
                      events.add('core:stopListener');
                      if (!agentCoreReady) {
                        // Would hang forever if called while Agent Core is not ready!
                        await Completer<void>().future;
                      }
                    },
                    stopVpn: () async {
                      events.add('os:stopVpn');
                    },
                    shutdownCore: () async {
                      events.add('core:shutdown');
                    },
                    destroyService: () async {
                      events.add('service:destroy');
                    },
                    detachService: () async {},
                    exitApp: () async {
                      events.add('app:exit');
                    },
                    clearLocalState: () async {
                      events.add('local:clear');
                    },
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.clear();

      // Part A: handleExit when usesAgent && !agentCoreReady must NOT call stopListener
      // (avoiding 3s timeout) and must NOT re-arm System Proxy after releasing lease.
      final exitFuture = controller!.handleExit();
      await tester.pump(const Duration(seconds: 3));
      await exitFuture;
      await tester.pumpAndSettle();

      expect(stopListenerCalled, isFalse);
      expect(events, contains('plugin:stopProxy'));
      expect(events, contains('os:flushDnsCache'));
      expect(events, contains('app:exit'));
      expect(
        events.where((e) => e.startsWith('plugin:startProxy')),
        isEmpty,
        reason: 'System proxy must NEVER re-arm during terminal handleExit',
      );

      // Part B: handleClear on a fresh controller with agentCoreReady == true disarms
      // System Proxy, stops listeners, flushes DNS cache, and shuts down Core cleanly.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _seedBaseState(running: true, tunEnabled: true, systemProxy: true);
      events.clear();
      agentCoreReady = true;
      final runtime2 = TunRuntimeController()..desiredEnabled = true;
      final container2 = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => runtime2),
        ],
      );
      addTearDown(container2.dispose);

      AppController? controller2;
      await tester.pumpWidget(
        _wrapMaterial(
          container: container2,
          child: ProxyManager(
            child: Consumer(
              builder: (context, ref, _) {
                controller2 ??= AppController(
                  context,
                  ref,
                  windowsStartupEffects: effects,
                  tunRuntimeController: runtime2,
                  tunSettleDelay: Duration.zero,
                  flushSystemDnsCache: () async {
                    events.add('os:flushDnsCache');
                  },
                  shutdownEffects: AppShutdownEffects(
                    usesAgent: () => true,
                    agentCoreReady: () => true,
                    stopListener: () async {
                      events.add('core:stopListener');
                    },
                    stopVpn: () async {
                      events.add('os:stopVpn');
                    },
                    shutdownCore: () async {
                      events.add('core:shutdown');
                    },
                    destroyService: () async {},
                    detachService: () async {},
                    exitApp: () async {
                      events.add('app:exit');
                    },
                    clearLocalState: () async {
                      events.add('local:clear');
                    },
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.clear();

      final clearFuture = controller2!.handleClear();
      await tester.pump(const Duration(milliseconds: 600));
      await clearFuture;
      await tester.pumpAndSettle();

      final proxyStopIdx = events.indexOf('plugin:stopProxy');
      final stopListenerIdx = events.indexOf('core:stopListener');
      final dnsFlushIdx = events.indexOf('os:flushDnsCache');
      final shutdownIdx = events.indexOf('core:shutdown');
      final clearLocalIdx = events.indexOf('local:clear');
      expect(proxyStopIdx, greaterThanOrEqualTo(0));
      expect(stopListenerIdx, greaterThan(proxyStopIdx));
      expect(dnsFlushIdx, greaterThan(stopListenerIdx));
      expect(shutdownIdx, greaterThan(dnsFlushIdx));
      expect(clearLocalIdx, greaterThan(shutdownIdx));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}

class _InterceptObserveEffects extends _GracefulStopEffects {
  _InterceptObserveEffects(this._inner, this._overrideObserve)
      : super(_inner.events);

  final _GracefulStopEffects _inner;
  final TunStatus? Function() _overrideObserve;

  @override
  bool get proxyRunning => _inner.proxyRunning;

  @override
  Future<TunStatus?> observe() async {
    final custom = _overrideObserve();
    if (custom != null) return custom;
    return _inner.observe();
  }

  @override
  Future<void> stopProxy() => _inner.stopProxy();

  @override
  Future<void> applyConfiguration({
    required bool full,
    required bool Function() isCurrent,
  }) =>
      _inner.applyConfiguration(full: full, isCurrent: isCurrent);

  @override
  Future<void> restartCore() => _inner.restartCore();

  @override
  Future<void> initialize(bool Function() isCurrent) =>
      _inner.initialize(isCurrent);
}
