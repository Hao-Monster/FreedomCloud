import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/proxy_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/dashboard/dashboard.dart';
import 'package:flclashx/views/dashboard/widgets/network_detection.dart';
import 'package:flclashx/views/tools.dart';
import 'package:flclashx/views/tools/health_check_view.dart';
import 'package:flclashx/widgets/scaffold.dart';
import 'package:flclashx/widgets/sheet.dart';
import 'package:flclashx/widgets/tun_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _StubAppController implements AppController {
  PageLabel? navigatedTo;

  @override
  void toPage(PageLabel pageLabel) {
    navigatedTo = pageLabel;
  }

  @override
  void changeMode(Mode mode) {}

  @override
  Future<void> updateStatus(bool isStart) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestHealthEnvironment implements HealthProbeEnvironment {
  _TestHealthEnvironment({
    DateTime? initialClock,
    this.outboundDelay = const DelayTestResult(68),
    this.tunStatus,
    this.e2e = const EndToEndProbeObservation(
      exitCountryCode: 'SG',
      observedInCore: true,
      matchedLeafProxy: 'SG-01',
    ),
  }) : clock = initialClock ?? DateTime(2026, 11, 1, 14, 5, 10);

  DateTime clock;
  DelayTestResult outboundDelay;
  DelayTestResult directDelay = const DelayTestResult(26);
  TunStatus? tunStatus;
  bool systemProxyEnabled = false;
  bool tunDesiredEnabled = true;
  bool proxyStarted = true;
  int mixedPort = 7890;
  WindowsSystemProxySnapshot? windowsProxy;
  int subscriptionExpireSec = 1796000000;
  EndToEndProbeObservation? e2e;
  Completer<DelayTestResult>? outboundGate;
  int runCount = 0;

  @override
  DateTime now() => clock;

  @override
  String get platform => 'windows';

  @override
  String get appVersion => '0.4.2';

  @override
  Future<HealthConfigSnapshot> readConfigSnapshot() async {
    runCount++;
    const group = Group(
      type: GroupType.Selector,
      name: 'Proxy',
      now: 'SG-01',
      all: [
        Proxy(name: 'SG-01', type: 'Trojan'),
      ],
    );
    final profile = Profile(
      id: 'sub-main',
      label: 'FreedomCloud Pro',
      url: 'https://sub.example.com/token',
      currentGroupName: 'Proxy',
      autoUpdateDuration: const Duration(hours: 24),
      lastUpdateDate: DateTime(2026, 11, 1, 10, 0),
      subscriptionInfo: SubscriptionInfo(
        upload: 1024 * 1024 * 1024,
        download: 2 * 1024 * 1024 * 1024,
        total: 100 * 1024 * 1024 * 1024,
        expire: subscriptionExpireSec,
      ),
    );
    return HealthConfigSnapshot(
      currentProfileId: 'sub-main',
      currentProfile: profile,
      profileFileExists: true,
      profileFileBytes: 4096,
      mode: Mode.rule,
      mixedPort: mixedPort,
      testUrl: 'https://www.gstatic.com/generate_204',
      resolveGroupTestUrl: (u) => u ?? 'https://www.gstatic.com/generate_204',
      systemProxyEnabled: systemProxyEnabled,
      pacEnabled: false,
      pacUrl: null,
      tunDesiredEnabled: tunDesiredEnabled,
      tunFailureCode: tunStatus?.errorCode,
      realTunEnable: tunDesiredEnabled,
      proxyStarted: proxyStarted,
      lastRuntimeProfileId: 'sub-main',
      groupsSnapshotProfileId: 'sub-main',
      allGroups: const [group],
      visibleGroups: const [group],
      selectedMap: const {'Proxy': 'SG-01'},
    );
  }

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async =>
      const CoreLivenessObservation(
        isInit: true,
        memoryBytes: 42 * 1024 * 1024,
        trafficValid: true,
      );

  @override
  Future<TunStatus?> readTunStatus() async =>
      tunStatus ??
      const TunStatus(
        instanceId: 'core-1',
        revision: 1,
        state: 'on',
        listenerActive: true,
        interfaceState: 'up',
        privilege: 'elevated',
        requestedEnabled: true,
      );

  @override
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy() async =>
      windowsProxy ?? const WindowsSystemProxySnapshot(proxyEnabled: false);

  @override
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  }) async {
    if (proxyName == 'DIRECT') return directDelay;
    if (outboundGate != null) {
      return outboundGate!.future;
    }
    return outboundDelay;
  }

  @override
  Future<void> cancelProxyDelay(String requestId) async {}

  @override
  Future<List<InternetAddress>> lookupHost(String host) async => [
        InternetAddress(
          proxyStarted && tunDesiredEnabled ? '198.18.0.10' : '203.0.113.10',
        ),
      ];

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async =>
      e2e;
}

void _seedTestAppState({
  Size viewSize = const Size(960, 760),
  int? runTime,
}) {
  final traffics = FixedList<Traffic>(30)..add(Traffic(up: 128, down: 512));
  const group = Group(
    type: GroupType.Selector,
    name: 'Proxy',
    now: 'SG-01',
    all: [Proxy(name: 'SG-01', type: 'Trojan')],
  );
  globalState.config = Config(
    themeProps: defaultThemeProps,
    currentProfileId: 'sub-main',
    profiles: const [
      Profile(
        id: 'sub-main',
        label: 'FreedomCloud Pro',
        url: 'https://sub.example.com/token',
        currentGroupName: 'Proxy',
        autoUpdateDuration: Duration(hours: 24),
      ),
    ],
    appSetting: defaultAppSettingProps.copyWith(
      dashboardWidgets: const [
        DashboardWidget.networkDetection,
        DashboardWidget.tunButton,
      ],
    ),
  );
  globalState.appState = AppState(
    pageLabel: PageLabel.dashboard,
    viewSize: viewSize,
    isInit: true,
    runTime: runTime,
    version: 1,
    requests: FixedList(5),
    logs: FixedList(5),
    traffics: traffics,
    totalTraffic: Traffic(up: 1024, down: 2048),
    groups: const [group],
    delayMap: const {},
  );
}

Widget _wrapWithApp({
  required Widget child,
  required HealthProbeEnvironment env,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1.0,
  Size viewSize = const Size(960, 760),
  bool withCommonScaffold = false,
  bool? newDashboardOverride,
}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        healthProbeEnvironmentProvider.overrideWithValue(env),
        tunRuntimeProvider.overrideWith((ref) => TunRuntimeController()),
        if (newDashboardOverride != null)
          newDashboardEnabledProvider.overrideWithValue(newDashboardOverride),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: viewSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Builder(
            builder: (context) {
              globalState.measure = Measure.of(context, textScale);
              globalState.theme = CommonTheme.of(context, textScale);
              if (withCommonScaffold) {
                return CommonScaffold(
                  title: 'FreedomCloud',
                  body: child,
                );
              }
              return Scaffold(body: child);
            },
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('flclashx_health_test_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String? lastClipboardText;

  setUp(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
    globalState.appController = _StubAppController();
    lastClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>;
        lastClipboardText = args['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'HealthCheckView renders 12 items, non-flashing recheck updates timestamp, and copies redacted summary',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final env = _TestHealthEnvironment(
      initialClock: DateTime(2026, 11, 1, 14, 5, 10),
    );
    _seedTestAppState();

    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        viewSize: const Size(460, 900),
        child: const HealthCheckView(type: SheetType.page),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('health-verdict-card')), findsOneWidget);
    expect(find.text('连接正常'), findsOneWidget);
    expect(find.textContaining('14:05:10'), findsOneWidget);

    for (final id in HealthCheckId.values) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('health-row-${id.name}')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(ValueKey('health-row-${id.name}')), findsOneWidget);
    }

    // Copy summary and assert node/profile/IP privacy
    await tester.tap(find.byKey(const ValueKey('health-copy-button')));
    await tester.pumpAndSettle();
    expect(lastClipboardText, isNotNull);
    expect(lastClipboardText, contains('连接正常'));
    expect(lastClipboardText, isNot(contains('SG-01')));
    expect(lastClipboardText, isNot(contains('FreedomCloud Pro')));
    ScaffoldMessenger.of(tester.element(find.byType(HealthCheckView)))
        .clearSnackBars();
    await tester.pumpAndSettle();

    // Trigger re-check with a gated Phase 2 outbound probe to verify non-flashing rows
    final gate = Completer<DelayTestResult>();
    env
      ..clock = DateTime(2026, 11, 1, 14, 9, 45)
      ..outboundGate = gate
      ..e2e = null;

    await tester.tap(find.byKey(const ValueKey('health-recheck-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // While Phase 2 is in-flight, button switches to Cancel and previous node detail remains visible (not blanked out)
    expect(find.text('取消检查'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-row-outboundConnectivity')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('SG-01 · 68 ms'), findsOneWidget);

    // Complete gated outbound probe with failure -> verdict & timestamp update cleanly
    gate.complete(const DelayTestResult(-1, reason: 'deadlineExceeded'));
    env.outboundGate = null;
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-verdict-card')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('14:09:45'), findsOneWidget);
    expect(find.text('本机网络正常，但当前节点无法连通外网'), findsOneWidget);
  });

  testWidgets('failure verdict and row action buttons invoke expected HealthAction',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final env = _TestHealthEnvironment(
      outboundDelay: const DelayTestResult(-1, reason: 'error'),
      e2e: null,
    );
    _seedTestAppState();

    final triggered = <HealthAction>[];
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        viewSize: const Size(460, 900),
        child: HealthCheckView(
          type: SheetType.page,
          onAction: triggered.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('health-verdict-action-button')));
    await tester.pump();
    expect(triggered, [HealthAction.openProxies]);

    final rowActionFinder =
        find.byKey(const ValueKey('health-row-action-outboundConnectivity'));
    await tester.scrollUntilVisible(
      rowActionFinder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(rowActionFinder);
    await tester.pump();
    expect(triggered, [HealthAction.openProxies, HealthAction.openProxies]);
  });

  testWidgets(
      'Entry points in classic Dashboard, HeroConnect, ToolsView, NetworkDetection timeout, and TunStatusSwitch failure all open HealthCheckView',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final env = _TestHealthEnvironment();

    // 1. Classic Dashboard top bar + NetworkDetection timeout shortcut (and legacy 18px icon removed)
    _seedTestAppState();
    detectionState.state.value = const NetworkDetectionState(
      isLoading: false,
      isTesting: false,
      ipInfo: null,
    );
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        withCommonScaffold: true,
        newDashboardOverride: false,
        child: const DashboardView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.health_and_safety_outlined), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard-health-check-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('network-detection-diagnose-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('dashboard-health-check-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-verdict-card')), findsOneWidget);

    // Close side sheet
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    // 2. HeroConnect Dashboard top bar + HeroConnect IP failed '诊断' shortcut
    _seedTestAppState(runTime: 5000);
    detectionState.state.value = const NetworkDetectionState(
      isLoading: false,
      isTesting: false,
      ipInfo: null,
    );
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        withCommonScaffold: true,
        newDashboardOverride: true,
        child: const DashboardView(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('dashboard-health-check-action')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('hero-diagnose-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hero-diagnose-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-verdict-card')), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    // 3. ToolsView entry point opens HealthCheckView
    _seedTestAppState();
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        child: const ToolsView(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final toolsItem = find.byKey(const ValueKey('tools-health-check-item'));
    await tester.dragUntilVisible(
      toolsItem,
      find.byType(ListView),
      const Offset(0, -160),
    );
    await tester.pump();
    expect(toolsItem, findsOneWidget);
    await tester.tap(toolsItem);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-verdict-card')), findsOneWidget);

    // 4. TunStatusSwitch contextual diagnose button only when failure != null
    final runtime = TunRuntimeController();
    var diagnoseTapped = false;
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        child: StatefulBuilder(
          builder: (context, _) => ListenableBuilder(
            listenable: runtime,
            builder: (_, __) => TunStatusSwitch(
              runtime: runtime,
              onChanged: (_) {},
              onDiagnose: () => diagnoseTapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('tun-diagnose-button')), findsNothing);

    runtime.accept(
      const TunStatus(
        instanceId: 'one',
        revision: 1,
        state: 'failed',
        listenerActive: false,
        interfaceState: 'missing',
        privilege: 'unprivileged',
        requestedEnabled: true,
        errorCode: 'permissionDenied',
      ),
      0,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('tun-diagnose-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tun-diagnose-button')));
    expect(diagnoseTapped, isTrue);

    // Flush preexisting _CoreStatusItem 30s IPC timeout timer mounted by ToolsView
    await tester.pump(const Duration(seconds: 31));
  });

  for (final locale in const [Locale('zh', 'CN'), Locale('ru')]) {
    testWidgets(
        '320px @ 2.0x textScale (${locale.toLanguageTag()}) renders all 12 items and failure actions without overflow',
        (tester) async {
      await AppLocalizations.load(locale);
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final env = _TestHealthEnvironment(
        outboundDelay: const DelayTestResult(650),
        tunStatus: const TunStatus(
          instanceId: 'one',
          revision: 1,
          state: 'failed',
          listenerActive: false,
          interfaceState: 'missing',
          privilege: 'unprivileged',
          requestedEnabled: true,
          errorCode: 'permissionDenied',
        ),
      );
      _seedTestAppState(viewSize: const Size(320, 760));

      await tester.pumpWidget(
        _wrapWithApp(
          env: env,
          locale: locale,
          textScale: 2.0,
          viewSize: const Size(320, 760),
          child: const HealthCheckView(type: SheetType.page),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final id in HealthCheckId.values) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('health-row-${id.name}')),
          140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
      'CR-HC03: stacked sheets pop back to root on page actions, and openNetworkSettings replaces HealthCheckView without clobbering CommonScaffold.actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final stubCtrl = _StubAppController();
    globalState.appController = stubCtrl;
    _seedTestAppState();

    // 1. Stacked sheet -> HealthCheckView -> openPurchase must pop BOTH sheets
    final expiredEnv = _TestHealthEnvironment(
      initialClock: DateTime.utc(2026, 11, 1, 14, 0, 0),
    )..subscriptionExpireSec =
        DateTime.utc(2026, 11, 1, 10, 0, 0).millisecondsSinceEpoch ~/ 1000;

    await tester.pumpWidget(
      _wrapWithApp(
        env: expiredEnv,
        withCommonScaffold: true,
        newDashboardOverride: false,
        child: const DashboardView(),
      ),
    );
    await tester.pumpAndSettle();

    // Open an intermediate sheet first (simulating TUNButton sheet), then openHealthCheck on top
    final dashContext = tester.element(find.byType(DashboardView));
    unawaited(
      showSheet<void>(
        context: dashContext,
        builder: (innerCtx, type) => AdaptiveSheetScaffold(
          type: type,
          title: 'Intermediate Sheet',
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-hc-from-sheet'),
              onPressed: () => openHealthCheck(innerCtx),
              child: const Text('Diagnose'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Intermediate Sheet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-hc-from-sheet')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-verdict-card')), findsOneWidget);

    // Tap primary action (openPurchase) -> BOTH HealthCheckView AND Intermediate Sheet must be popped!
    await tester.tap(find.byKey(const ValueKey('health-verdict-action-button')));
    await tester.pumpAndSettle();
    expect(stubCtrl.navigatedTo, PageLabel.purchase);
    expect(find.byType(HealthCheckView), findsNothing);
    expect(find.text('Intermediate Sheet'), findsNothing);

    // 2. openNetworkSettings must NOT overwrite CommonScaffold.actions on DashboardView, and must pop HealthCheckView
    final sysProxyInvalidPortEnv = _TestHealthEnvironment()
      ..systemProxyEnabled = true
      ..mixedPort = 0
      ..tunDesiredEnabled = false
      ..tunStatus = const TunStatus(
        instanceId: 'core-1',
        revision: 1,
        state: 'off',
        listenerActive: false,
        interfaceState: 'down',
        privilege: 'elevated',
        requestedEnabled: false,
      )
      ..windowsProxy = const WindowsSystemProxySnapshot(
        proxyEnabled: true,
        proxyServer: '127.0.0.1:10809',
      );

    await tester.pumpWidget(
      _wrapWithApp(
        env: sysProxyInvalidPortEnv,
        withCommonScaffold: true,
        newDashboardOverride: false,
        child: const DashboardView(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dashboard-health-check-action')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('dashboard-health-check-action')));
    await tester.pumpAndSettle();

    // Verdict is systemProxyInvalidPort -> primary action is openNetworkSettings
    await tester.tap(find.byKey(const ValueKey('health-verdict-action-button')));
    await tester.pumpAndSettle();

    // HealthCheckView must have been replaced (not stacked behind Network sheet),
    // and Dashboard's CommonScaffold action must STILL be present!
    expect(find.byType(HealthCheckView), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard-health-check-action')),
      findsOneWidget,
    );
  });

  testWidgets(
      'CR-HC04 & CR-HC07: narrow 150px NetworkDetection @ 2.0x ru has no overflow, HeroConnect diagnose hit height >= 28px, dark mode pills have high luminance, and warning verdict shows node subtitle',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 1. CR-HC04a: NetworkDetection inside narrow 150px card @ 2.0x ru
    await AppLocalizations.load(const Locale('ru'));
    _seedTestAppState(viewSize: const Size(320, 760));
    detectionState.state.value = const NetworkDetectionState(
      isLoading: false,
      isTesting: false,
      ipInfo: null,
    );
    final env = _TestHealthEnvironment();
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        locale: const Locale('ru'),
        textScale: 2.0,
        viewSize: const Size(320, 760),
        child: const Center(
          child: SizedBox(
            width: 150,
            height: 130,
            child: NetworkDetection(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 2. CR-HC04b: HeroConnect diagnose button height >= 28px
    await AppLocalizations.load(const Locale('zh', 'CN'));
    _seedTestAppState(runTime: 5000);
    detectionState.state.value = const NetworkDetectionState(
      isLoading: false,
      isTesting: false,
      ipInfo: null,
    );
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        withCommonScaffold: true,
        newDashboardOverride: true,
        child: const DashboardView(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final heroBtnRect =
        tester.getRect(find.byKey(const ValueKey('hero-diagnose-button')));
    expect(heroBtnRect.height, greaterThanOrEqualTo(28.0));

    // 3. CR-HC07: Dark mode pill luminance > 0.35 & healthyWithWarnings shows node subtitle
    final warnEnv = _TestHealthEnvironment(
      initialClock: DateTime.utc(2026, 11, 1, 10, 0, 0),
    )..subscriptionExpireSec =
        DateTime.utc(2026, 11, 3, 0, 0, 0).millisecondsSinceEpoch ~/ 1000;

    await tester.pumpWidget(
      _wrapWithApp(
        env: warnEnv,
        viewSize: const Size(460, 900),
        child: const HealthCheckView(type: SheetType.page),
      ),
    );
    await tester.pumpAndSettle();

    // Subtitle with active node + delay must appear on healthyWithWarnings!
    expect(find.textContaining('节点 SG-01 · 出站 68 ms'), findsOneWidget);

    final passedText = tester.widget<Text>(find.text('通过').first);
    final warningText = tester.widget<Text>(find.text('警告').first);
    expect(passedText.style!.color!.computeLuminance(), greaterThan(0.35));
    expect(warningText.style!.color!.computeLuminance(), greaterThan(0.35));
  });

  testWidgets(
      'CR2-HC02: first-run cancel clears running spinners/headline, and reopening SideSheet during 200ms exit animation does not cancel the newly opened check',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Part A: First-run cancel (_lastReport == null) must NOT leave spinning indicators or "正在逐层检测连接链路…"
    final firstCancelGate = Completer<DelayTestResult>();
    final cancelEnv = _TestHealthEnvironment()..outboundGate = firstCancelGate;
    _seedTestAppState();

    await tester.pumpWidget(
      _wrapWithApp(
        env: cancelEnv,
        viewSize: const Size(460, 900),
        child: const HealthCheckView(type: SheetType.page),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('取消检查'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('health-recheck-button')));
    firstCancelGate.complete(const DelayTestResult(-1, reason: 'cancelled'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('检查中'), findsNothing);
    expect(find.text('正在逐层检测连接链路…'), findsNothing);

    // Part B: Reopen SideSheet at t=50ms while previous SideSheet's 200ms reverse animation is still mounted
    final reopenEnv = _TestHealthEnvironment(
      initialClock: DateTime(2026, 11, 1, 15, 0, 0),
    );
    _seedTestAppState();
    await tester.pumpWidget(
      _wrapWithApp(
        env: reopenEnv,
        withCommonScaffold: true,
        newDashboardOverride: false,
        child: const DashboardView(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Sheet #1 and let Run #1 complete
    await tester.tap(find.byKey(const ValueKey('dashboard-health-check-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining('15:00:00'), findsOneWidget);

    // Prepare Run #2 with gated Phase 2 + updated clock
    final run2Gate = Completer<DelayTestResult>();
    reopenEnv
      ..clock = DateTime(2026, 11, 1, 15, 5, 30)
      ..outboundGate = run2Gate
      ..e2e = null;

    // Close Sheet #1 at t=0ms (starts 200ms reverse transition; Sheet #1 is NOT disposed yet!)
    await tester.tap(find.byType(CloseButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Reopen Sheet #2 at t=50ms while Sheet #1 is still animating out!
    await tester.tap(
      find.byKey(const ValueKey('dashboard-health-check-action')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Advance past 200ms so Sheet #1 finishes its exit animation and runs dispose()!
    await tester.pump(const Duration(milliseconds: 250));

    // Sheet #2's Run #2 MUST still be active (button says '取消检查'), NOT killed by Sheet #1's dispose()!
    expect(find.text('取消检查'), findsOneWidget);

    // Complete Run #2 and verify Sheet #2 receives the fresh 15:05:30 report!
    run2Gate.complete(const DelayTestResult(-1, reason: 'deadlineExceeded'));
    reopenEnv.outboundGate = null;
    await tester.pumpAndSettle();

    expect(find.textContaining('15:05:30'), findsOneWidget);
    expect(find.text('本机网络正常，但当前节点无法连通外网'), findsOneWidget);
  });

  testWidgets(
      'Bug 4 & Bug 9b: 420px SideSheet bottom buttons never truncate with ellipsis, and async verdict actions ignore rapid double-taps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var startProxyCount = 0;
    final startProxyGate = Completer<void>();
    final slowCtrl = _SlowStartAppController(
      onStartProxy: () {
        startProxyCount++;
        return startProxyGate.future;
      },
    );
    globalState.appController = slowCtrl;

    final env = _TestHealthEnvironment()..proxyStarted = false;
    _seedTestAppState();

    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        viewSize: const Size(420, 900),
        child: const HealthCheckView(type: SheetType.sideSheet),
      ),
    );
    await tester.pumpAndSettle();

    // Bug 4: At 420px SideSheet width, "复制摘要" and "导出脱敏报告" must NOT truncate to "复..." / "导..."!
    final copyTextFinder = find.descendant(
      of: find.byKey(const ValueKey('health-copy-button')),
      matching: find.byType(RichText),
    );
    final exportTextFinder = find.descendant(
      of: find.byKey(const ValueKey('health-export-button')),
      matching: find.byType(RichText),
    );
    final copyParagraph = tester.renderObject(copyTextFinder.last) as dynamic;
    final exportParagraph =
        tester.renderObject(exportTextFinder.last) as dynamic;
    expect(copyParagraph.didExceedMaxLines, isFalse);
    expect(exportParagraph.didExceedMaxLines, isFalse);

    // Bug 9b: Rapid double-tap on async startProxy action must invoke updateStatus(true) only ONCE!
    final actionBtn = find.byKey(const ValueKey('health-verdict-action-button'));
    await tester.tap(actionBtn);
    await tester.pump();
    await tester.tap(actionBtn, warnIfMissed: false);
    await tester.pump();

    expect(startProxyCount, 1);

    env.proxyStarted = true;
    startProxyGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'CR-3a: clicking reapplySystemProxy while check is still in-flight in Phase 2 cancels stale run and settles to healthy post-repair report',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(460, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final originalPlatform = ProxyPlatform.instance;
    final outboundGate = Completer<DelayTestResult>();
    final env = _TestHealthEnvironment(
      initialClock: DateTime(2026, 11, 6, 11, 30, 0),
      tunStatus: const TunStatus(
        instanceId: 'core-1',
        revision: 1,
        state: 'off',
        listenerActive: false,
        interfaceState: 'missing',
        privilege: 'none',
        requestedEnabled: false,
      ),
    )
      ..outboundGate = outboundGate
      ..tunDesiredEnabled = false
      ..systemProxyEnabled = true
      ..windowsProxy = const WindowsSystemProxySnapshot(
        proxyEnabled: true,
        proxyServer: '127.0.0.1:7890',
        autoConfigUrl: null,
      );

    var restoreArmed = false;
    ProxyPlatform.instance = _RestoringProxyPlatform(
      onStartProxy: (port) {
        if (!restoreArmed) return;
        env
          ..windowsProxy = WindowsSystemProxySnapshot(
            proxyEnabled: true,
            proxyServer: '127.0.0.1:$port',
            autoConfigUrl: null,
          )
          ..outboundGate = null
          ..clock = DateTime(2026, 11, 6, 11, 30, 5);
      },
    );
    addTearDown(() => ProxyPlatform.instance = originalPlatform);

    _seedTestAppState(runTime: 5000);
    globalState.config = globalState.config.copyWith(
      networkProps: const NetworkProps(systemProxy: true),
      patchClashConfig: defaultClashConfig.copyWith(mixedPort: 7890),
    );
    globalState.lastRuntimeProfileId = 'sub-main';
    globalState.lastRuntimeConfig = <String, dynamic>{'mixed-port': 7890};
    addTearDown(globalState.clearRuntimeSetup);

    final showView = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        viewSize: const Size(460, 900),
        child: ProxyManager(
          child: ValueListenableBuilder<bool>(
            valueListenable: showView,
            builder: (_, visible, __) => visible
                ? const HealthCheckView(type: SheetType.sideSheet)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Simulate external hijack AFTER ProxyManager already cached its signature!
    env.windowsProxy = const WindowsSystemProxySnapshot(
      proxyEnabled: true,
      proxyServer: '127.0.0.1:10809',
      autoConfigUrl: null,
    );
    restoreArmed = true;
    showView.value = true;

    // Let Phase 1 complete (C3 fails with systemProxyHijacked) while Phase 2 is still blocked on outboundGate!
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('取消检查'), findsOneWidget);
    final reapplyBtn = find.descendant(
      of: find.byKey(const ValueKey('health-row-systemProxyTakeover')),
      matching: find.text('一键恢复系统代理'),
    );
    await tester.scrollUntilVisible(
      reapplyBtn,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(reapplyBtn, findsOneWidget);

    // Click "一键恢复系统代理" while Run #1 is still in Phase 2!
    await tester.tap(reapplyBtn);
    await tester.pump();
    if (!outboundGate.isCompleted) {
      outboundGate.complete(const DelayTestResult(42));
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-verdict-card')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('连接正常'), findsOneWidget);
    expect(find.textContaining('11:30:05'), findsOneWidget);
  });

  testWidgets(
      'when D3 URLTest fails but D4 E2E probe succeeds via proxy, UI shows warning instead of false outbound failure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final env = _TestHealthEnvironment(
      outboundDelay: const DelayTestResult(-1, reason: 'testFailed'),
    );
    _seedTestAppState();

    await tester.pumpWidget(
      _wrapWithApp(
        env: env,
        viewSize: const Size(460, 900),
        child: const HealthCheckView(type: SheetType.page),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本机网络正常，但当前节点无法连通外网'), findsNothing);
    expect(find.text('连接可用，但存在需关注的告警项'), findsOneWidget);
    expect(find.textContaining('SG-01'), findsWidgets);
    expect(find.textContaining('SG'), findsWidgets);

    final outboundRow = find.byKey(const ValueKey('health-row-outboundConnectivity'));
    await tester.scrollUntilVisible(
      outboundRow,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('测速地址受限，但端到端实测已连通'), findsOneWidget);

    final e2eRow = find.byKey(const ValueKey('health-row-endToEndConnectivity'));
    await tester.scrollUntilVisible(
      e2eRow,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('已验证经过代理'), findsOneWidget);
  });
}

class _RestoringProxyPlatform extends ProxyPlatform {
  _RestoringProxyPlatform({required this.onStartProxy});
  final void Function(int port) onStartProxy;

  @override
  Future<bool?> startProxy(int port, List<String> bypassDomain) async {
    onStartProxy(port);
    return true;
  }

  @override
  Future<bool?> stopProxy() async => true;

  @override
  Future<bool?> startPac(String url) async => true;
}

class _SlowStartAppController extends _StubAppController {
  _SlowStartAppController({required this.onStartProxy});
  final Future<void> Function() onStartProxy;

  @override
  Future<void> updateStatus(bool isStart) => onStartProxy();
}
