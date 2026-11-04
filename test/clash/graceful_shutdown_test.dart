import 'dart:async';

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
import 'package:proxy/proxy_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}) {
  globalState.config = Config(
    themeProps: defaultThemeProps,
    profiles: const [
      Profile(
        id: 'p1',
        label: 'Test Profile',
        url: 'https://example.com/sub',
        autoUpdateDuration: Duration(hours: 24),
      ),
    ],
    currentProfileId: 'p1',
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

  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
    originalProxyPlatform = ProxyPlatform.instance;
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
      await tester.tap(find.byType(FilledButton));
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
      await tester.tap(find.byType(FilledButton));
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
}
