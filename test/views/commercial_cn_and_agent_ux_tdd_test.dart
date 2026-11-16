import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/ai_agent_diagnostics.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/signed_update.dart';
import 'package:flclashx/common/theme.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/services/subscription_notification_service.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/about.dart';
import 'package:flclashx/views/dashboard/widgets/hero_connect.dart';
import 'package:flclashx/views/proxies/overview/overview.dart';
import 'package:flclashx/views/tools/health_check_view.dart';
import 'package:flclashx/widgets/signed_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../setup.dart' as setup;

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

class _NoopClashHandler extends Fake implements ClashHandlerInterface {
  @override
  FutureOr<String> getCoreVersion() => 'v1.19.32';
}

class _NoopCatalogTester extends ChangeNotifier implements NodeCatalogTester {
  @override
  bool busy = false;
  @override
  int total = 0;
  @override
  int completed = 0;

  @override
  bool pending(String profileId, String identityKey) => false;

  @override
  Set<String> pendingIdentitySnapshot(String profileId) => const <String>{};

  @override
  Future<DelayBatchResult> testAll(List<Profile> profiles, String url) async =>
      const DelayBatchResult(completed: 0, failed: 0);

  @override
  void disposeScope() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppController extends Fake implements AppController {
  final List<PageLabel> navigatedPages = <PageLabel>[];

  @override
  void toPage(PageLabel pageLabel) {
    navigatedPages.add(pageLabel);
  }

  @override
  void changeMode(Mode mode) {}

  @override
  Future<void> updateStatus(bool isStart) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _QuotaHealthEnv implements HealthProbeEnvironment {
  _QuotaHealthEnv({
    required this.clock,
    required this.profile,
  });

  final DateTime clock;
  final Profile profile;

  @override
  DateTime now() => clock;

  @override
  String get platform => 'windows';

  @override
  String get appVersion => '1.0.0';

  @override
  Future<HealthConfigSnapshot> readConfigSnapshot() async {
    const group = Group(
      type: GroupType.Selector,
      name: 'Proxy',
      now: 'SG-01',
      all: [Proxy(name: 'SG-01', type: 'Trojan')],
    );
    return HealthConfigSnapshot(
      currentProfileId: profile.id,
      currentProfile: profile,
      profileFileExists: true,
      profileFileBytes: 1024,
      mode: Mode.rule,
      mixedPort: 7890,
      testUrl: 'https://www.google.com/generate_204',
      resolveGroupTestUrl: (u) => u ?? 'https://www.google.com/generate_204',
      systemProxyEnabled: false,
      pacEnabled: false,
      pacUrl: null,
      tunDesiredEnabled: true,
      tunFailureCode: null,
      realTunEnable: true,
      proxyStarted: true,
      lastRuntimeProfileId: profile.id,
      groupsSnapshotProfileId: profile.id,
      allGroups: const [group],
      visibleGroups: const [group],
      selectedMap: const {'Proxy': 'SG-01'},
    );
  }

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async =>
      const CoreLivenessObservation(
        isInit: true,
        memoryBytes: 32 * 1024 * 1024,
        trafficValid: true,
      );

  @override
  Future<TunStatus?> readTunStatus() async => const TunStatus(
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
      const WindowsSystemProxySnapshot(proxyEnabled: false);

  @override
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  }) async =>
      const DelayTestResult(42);

  @override
  Future<void> cancelProxyDelay(String requestId) async {}

  @override
  Future<List<InternetAddress>> lookupHost(String host) async =>
      [InternetAddress('198.18.0.2')];

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async =>
      const EndToEndProbeObservation(
        exitCountryCode: 'SG',
        observedInCore: true,
        matchedLeafProxy: 'SG-01',
      );
}

Widget _wrapTestApp({
  required Widget home,
  Locale locale = const Locale('zh', 'CN'),
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: buildFreedomNetThemeData(
          colorScheme: calibrateFreedomNetColorScheme(
            ColorScheme.fromSeed(
              seedColor: const Color(defaultPrimaryColor),
              brightness: Brightness.dark,
            ),
            seedColor: const Color(defaultPrimaryColor),
          ),
        ),
        home: Builder(
          builder: (context) {
            globalState.measure = Measure.of(context, 1.0);
            globalState.theme = CommonTheme.of(context, 1.0);
            return Scaffold(body: home);
          },
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('fcx_cn_ux_tdd_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('zh', 'CN'));
    ClashCore.instanceForTesting = ClashCore.forTesting(_NoopClashHandler());
    globalState.packageInfo = PackageInfo(
      appName: 'FreedomNet',
      packageName: 'com.follow.clashx',
      version: '1.0.0',
      buildNumber: '1',
    );
    globalState.coreVersion = 'v1.19.32';
    globalState.config = const Config(themeProps: defaultThemeProps);
    globalState.appState = AppState(
      pageLabel: PageLabel.proxies,
      viewSize: const Size(1200, 820),
      version: 1,
      requests: FixedList(maxLength),
      logs: FixedList(maxLength),
      traffics: FixedList(30),
      totalTraffic: Traffic(),
      isInit: true,
    );
  });

  tearDown(() {
    ClashCore.instanceForTesting = null;
  });

  testWidgets(
      'Task 1b: AboutView removes REMNAFAMILY / docs.rw easter egg detector',
      (tester) async {
    await tester.pumpWidget(_wrapTestApp(home: const AboutView()));
    await tester.pumpAndSettle();

    final monument = find.byKey(const ValueKey('about-brand-monument'));
    expect(monument, findsOneWidget);

    for (var i = 0; i < 12; i++) {
      await tester.tap(monument);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.text('REMNAFAMILY ONE LOVE'), findsNothing);
    expect(find.text('TRY REMNAWAVE'), findsNothing);
    expect(File('lib/views/about.dart').readAsStringSync(),
        isNot(contains('REMNAFAMILY')));
    expect(File('lib/views/about.dart').readAsStringSync(),
        isNot(contains('https://docs.rw')));
  });

  testWidgets(
      'Task 3: Zero-profile onboarding promotes login/purchase as primary FilledButton and manual import as secondary OutlinedButton',
      (tester) async {
    final controller = _FakeAppController();
    globalState.appController = controller;

    await tester.pumpWidget(
      _wrapTestApp(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          coldStartZeroProfilePromptedProvider.overrideWith((_) => true),
          nodeCatalogTesterProvider.overrideWith((_) => _NoopCatalogTester()),
        ],
        home: const NodeOverviewView(),
      ),
    );
    await tester.pumpAndSettle();

    final goPurchaseFinder =
        find.byKey(const ValueKey('overview-empty-go-purchase'));
    final addSubFinder =
        find.byKey(const ValueKey('overview-empty-add-subscription'));

    expect(goPurchaseFinder, findsOneWidget);
    expect(addSubFinder, findsOneWidget);
    expect(tester.widget<Widget>(goPurchaseFinder), isA<FilledButton>());
    expect(tester.widget<Widget>(addSubFinder), isA<OutlinedButton>());
    expect(
      find.descendant(
        of: goPurchaseFinder,
        matching: find.text('登录 / 开通自由云账号'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: addSubFinder,
        matching: find.text('手动导入订阅链接'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(goPurchaseFinder).dy,
      lessThan(tester.getTopLeft(addSubFinder).dy),
    );

    await tester.tap(goPurchaseFinder);
    await tester.pumpAndSettle();
    expect(controller.navigatedPages, [PageLabel.purchase]);
  });

  test('Task 4a: HealthRunner triggers subscriptionTrafficLow below 15% remaining (>= 85% used)',
      () async {
    final now = DateTime.utc(2026, 11, 16, 12, 0, 0);
    final profileLow14 = Profile(
      id: 'sub-low',
      label: 'Low Quota',
      url: 'https://sub.example.test/1',
      autoUpdateDuration: const Duration(hours: 24),
      lastUpdateDate: now,
      subscriptionInfo: SubscriptionInfo(
        upload: 46,
        download: 40,
        total: 100,
        expire: now.add(const Duration(days: 20)).millisecondsSinceEpoch ~/ 1000,
      ),
    );

    final lowReport = await HealthRunner(
      _QuotaHealthEnv(clock: now, profile: profileLow14),
    ).run();
    final subCheck = lowReport.checkById(HealthCheckId.subscriptionHealth)!;
    expect(subCheck.status, HealthStatus.warning);
    expect(subCheck.reasonCode, 'subscriptionTrafficLow');

    final healthyProfile = profileLow14.copyWith(
      subscriptionInfo: SubscriptionInfo(
        upload: 40,
        download: 40,
        total: 100,
        expire: now.add(const Duration(days: 20)).millisecondsSinceEpoch ~/ 1000,
      ),
    );
    final okReport = await HealthRunner(
      _QuotaHealthEnv(clock: now, profile: healthyProfile),
    ).run();
    expect(
      okReport.checkById(HealthCheckId.subscriptionHealth)?.status,
      HealthStatus.passed,
    );
  });

  test('Task 4b: SubscriptionNotificationService emits deduplicated desktop alerts for <=3d expiry and <15% quota',
      () async {
    final fixedNow = DateTime.utc(2026, 11, 16, 12, 0, 0);
    final emitted = <SubscriptionAlert>[];
    SubscriptionNotificationService.nowProvider = () => fixedNow;
    SubscriptionNotificationService.isAndroidOverride = false;
    SubscriptionNotificationService.desktopNotifierOverride = (alert) async {
      emitted.add(alert);
    };
    addTearDown(() {
      SubscriptionNotificationService.nowProvider = null;
      SubscriptionNotificationService.isAndroidOverride = null;
      SubscriptionNotificationService.desktopNotifierOverride = null;
    });

    final profile = Profile(
      id: 'sub-win-alert',
      label: '自由云测试订阅',
      url: 'https://sub.example.test/win',
      autoUpdateDuration: const Duration(hours: 24),
      subscriptionInfo: SubscriptionInfo(
        upload: 50,
        download: 38,
        total: 100,
        expire: fixedNow
                .add(const Duration(days: 2, hours: 3))
                .millisecondsSinceEpoch ~/
            1000,
      ),
    );

    await SubscriptionNotificationService.checkAndNotify(profile);
    expect(emitted.map((e) => e.kind).toSet(), {
      SubscriptionAlertKind.expiringSoon,
      SubscriptionAlertKind.trafficLow,
    });
    expect(SubscriptionNotificationService.activeAlerts.value, hasLength(2));

    // Re-running without change deduplicates toast/notifier emissions.
    await SubscriptionNotificationService.checkAndNotify(profile);
    expect(emitted, hasLength(2));

    // Perpetual plan (expire == 0) with <15% remaining still emits low-quota alert.
    const perpetualLow = Profile(
      id: 'sub-perpetual',
      label: '永久流量包',
      url: 'https://sub.example.test/perp',
      autoUpdateDuration: Duration(hours: 24),
      subscriptionInfo: SubscriptionInfo(
        upload: 90,
        download: 0,
        total: 100,
        expire: 0,
      ),
    );
    await SubscriptionNotificationService.checkAndNotify(perpetualLow);
    expect(
      emitted.where((e) => e.profileId == 'sub-perpetual').single.kind,
      SubscriptionAlertKind.trafficLow,
    );
  });

  testWidgets(
      'Task 4c: HeroConnect shows low-quota (<15%) and expiring (<=3d) alert cue with renew navigation',
      (tester) async {
    final controller = _FakeAppController();
    globalState.appController = controller;
    final now = DateTime.now();
    final lowProfile = Profile(
      id: 'hero-low',
      label: 'Hero Low',
      url: 'https://sub.example.test/hero',
      autoUpdateDuration: const Duration(hours: 24),
      subscriptionInfo: SubscriptionInfo(
        upload: 88 * 1024 * 1024 * 1024,
        download: 0,
        total: 100 * 1024 * 1024 * 1024,
        expire: now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
      ),
    );
    globalState.config = Config(
      themeProps: defaultThemeProps,
      currentProfileId: lowProfile.id,
      profiles: [lowProfile],
    );

    await tester.pumpWidget(
      _wrapTestApp(
        home: const SizedBox(
          width: 420,
          height: 680,
          child: HeroConnect(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('hero-subscription-alert-cue')),
      findsOneWidget,
    );
    final renewBtn = find.byKey(const ValueKey('hero-subscription-alert-renew'));
    expect(renewBtn, findsOneWidget);
    await tester.tap(renewBtn);
    await tester.pumpAndSettle();
    expect(controller.navigatedPages, [PageLabel.purchase]);
  });

  test(
      'Task 1c: Zashboard prefers local bundled archive, fails over across HTTPS mirrors, and surfaces CN fallback message',
      () async {
    List<int> buildZip(String html) {
      final archive = Archive()
        ..addFile(ArchiveFile.string('dist/index.html', html));
      return ZipEncoder().encode(archive);
    }

    // URL resolution deduplicates valid HTTPS mirrors and rejects insecure URLs.
    expect(
      resolveZashboardDistUrls(mirrorUrls: const [
        'http://insecure.example.com/dist.zip',
        'https://user:pass@bad.example.com/dist.zip',
        'https://cdn.freedomcloud.test/zashboard/dist.zip',
        'https://cdn.freedomcloud.test/zashboard/dist.zip',
      ]),
      [
        'https://cdn.freedomcloud.test/zashboard/dist.zip',
        zashboardDistUrl,
      ],
    );

    // 1. Local bundled archive installs with zero HTTP requests.
    final bundledRoot = await tempDir.createTemp('zash_bundled_');
    final bundledTarget = p.join(bundledRoot.path, 'ui');
    final requestsMade = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _CallbackAdapter((options) async {
        requestsMade.add(options.uri.toString());
        throw DioException(requestOptions: options, error: 'network disabled');
      });
    addTearDown(() => dio.close(force: true));

    final bundledRes = await ensureZashboardUiWithResult(
      directory: bundledTarget,
      client: dio,
      bundledArchiveLoader: () async => buildZip('<html>bundled</html>'),
    );
    expect(bundledRes.ok, isTrue);
    expect(bundledRes.source, ZashboardInstallSource.bundled);
    expect(requestsMade, isEmpty);
    expect(
      await File(p.join(bundledTarget, 'index.html')).readAsString(),
      '<html>bundled</html>',
    );

    // 2. Mirror failover succeeds when raw GitHub fails.
    final mirrorRoot = await tempDir.createTemp('zash_mirror_');
    final mirrorTarget = p.join(mirrorRoot.path, 'ui');
    const mirrorUrl = 'https://mirror.freedomcloud.test/zashboard.zip';
    final mirrorAdapter = _CallbackAdapter((options) async {
      requestsMade.add(options.uri.toString());
      if (options.uri.toString() == mirrorUrl) {
        return ResponseBody.fromBytes(buildZip('<html>mirror</html>'), 200);
      }
      throw DioException.connectionTimeout(
        requestOptions: options,
        timeout: const Duration(seconds: 1),
      );
    });
    dio.httpClientAdapter = mirrorAdapter;

    final mirrorRes = await ensureZashboardUiWithResult(
      directory: mirrorTarget,
      client: dio,
      mirrorUrls: const [mirrorUrl],
      bundledArchiveLoader: () async => null,
    );
    expect(mirrorRes.ok, isTrue);
    expect(mirrorRes.source, ZashboardInstallSource.mirror);
    expect(mirrorRes.usedUrl, mirrorUrl);
    expect(requestsMade, [mirrorUrl]);

    // 3. Total network failure returns friendly Chinese fallback message + public fallback URL helper.
    final failRoot = await tempDir.createTemp('zash_fail_');
    final failTarget = p.join(failRoot.path, 'ui');
    dio.httpClientAdapter = _CallbackAdapter((options) async {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'blocked in CN',
      );
    });
    final failRes = await ensureZashboardUiWithResult(
      directory: failTarget,
      client: dio,
      mirrorUrls: const [mirrorUrl],
      bundledArchiveLoader: () async => null,
    );
    expect(failRes.ok, isFalse);
    expect(failRes.source, ZashboardInstallSource.failed);
    expect(failRes.messageZh, zashboardChinaFallbackMessage);

    globalState.effectiveExternalController.value = '127.0.0.1:9090';
    globalState.effectiveSecret.value = 'sec';
    globalState.effectiveExternalUi.value = failTarget;
    expect(
      buildZashboardUrl(),
      'http://127.0.0.1:9090/ui/#/setup?hostname=127.0.0.1&port=9090&secret=sec&http=1',
    );
    expect(
      buildZashboardUrl(preferPublicFallback: true),
      '$publicZashboardBase/#/setup?hostname=127.0.0.1&port=9090&secret=sec&http=1',
    );
  });

  test(
      'Task 5a: AiEndpointReachabilityRunner classifies 200/401/404 reachable, 403/451 region-blocked, and timeout/TLS failures',
      () async {
    final observedDirectives = <String>[];
    final runner = AiEndpointReachabilityRunner(
      prober: (uri, {required explicitProxyDirective, required timeout}) async {
        observedDirectives.add(explicitProxyDirective);
        return switch (uri.host) {
          'generativelanguage.googleapis.com' =>
            const AiHttpProbeOutcome(statusCode: 200),
          'api.anthropic.com' => const AiHttpProbeOutcome(statusCode: 403),
          'api.openai.com' => const AiHttpProbeOutcome(
              errorCode: 'tlsHandshakeFailed',
              detail: 'handshake fail',
            ),
          _ => const AiHttpProbeOutcome(statusCode: 404),
        };
      },
    );

    final skipped = await runner.probeAll(
      proxyStarted: false,
      tunActive: false,
      mixedPort: 7890,
    );
    expect(skipped.every((e) => e.status == AiEndpointStatus.skipped), isTrue);

    final results = await runner.probeAll(
      proxyStarted: true,
      tunActive: false,
      mixedPort: 7897,
    );
    expect(observedDirectives, everyElement('PROXY 127.0.0.1:7897'));
    final byId = {for (final r in results) r.id: r};
    expect(byId[AiEndpointId.gemini]!.status, AiEndpointStatus.reachable);
    expect(byId[AiEndpointId.claude]!.status, AiEndpointStatus.regionBlocked);
    expect(
      byId[AiEndpointId.openai]!.status,
      AiEndpointStatus.tlsOrTimeoutError,
    );

    expect(
      classifyAiHttpOutcome(const AiHttpProbeOutcome(statusCode: 401)),
      AiEndpointStatus.reachable,
    );
    expect(
      classifyAiHttpOutcome(const AiHttpProbeOutcome(statusCode: 404)),
      AiEndpointStatus.reachable,
    );
    expect(
      classifyAiHttpOutcome(const AiHttpProbeOutcome(statusCode: 451)),
      AiEndpointStatus.regionBlocked,
    );
  });

  test(
      'Task 5a: CliProxyDiagnosticsRunner inspects env, git global proxy, and WSL2 gateway + allow-lan state',
      () async {
    final runnerWarn = CliProxyDiagnosticsRunner(
      envReader: () => const {
        'HTTP_PROXY': 'http://127.0.0.1:7890',
        'HTTPS_PROXY': 'http://127.0.0.1:7891', // Mismatched port
      },
      gitConfigReader: (key) async =>
          key == 'http.proxy' ? 'http://127.0.0.1:7890' : null,
      wslGatewayReader: () async => '172.24.160.1',
    );
    final warnReport = await runnerWarn.diagnose(
      mixedPort: 7890,
      proxyStarted: true,
      tunEnabled: false,
      allowLan: false,
    );
    final itemsById = {for (final i in warnReport.items) i.id: i};
    expect(itemsById['cliEnv']!.severity, CliProxyCheckSeverity.warning);
    expect(itemsById['gitProxy']!.severity, CliProxyCheckSeverity.ok);
    expect(itemsById['wsl2Gateway']!.severity, CliProxyCheckSeverity.warning);
    expect(warnReport.wslSnippet, contains('172.24.160.1:7890'));
    expect(warnReport.powershellSnippet, contains(r'$env:HTTPS_PROXY='));
    expect(warnReport.gitSnippet, contains('git config --global http.proxy'));
    expect(warnReport.combinedCopyText, contains('WSL2 NAT'));

    final okWslReport = await CliProxyDiagnosticsRunner(
      envReader: () => const {},
      gitConfigReader: (_) async => null,
      wslGatewayReader: () async => '172.24.160.1',
    ).diagnose(
      mixedPort: 7890,
      proxyStarted: true,
      tunEnabled: true,
      allowLan: true,
    );
    expect(
      okWslReport.items.singleWhere((i) => i.id == 'wsl2Gateway').severity,
      CliProxyCheckSeverity.ok,
    );
  });

  testWidgets(
      'Task 5a: HealthCheckView runs AI endpoint probes, opens CLI/Git/WSL2 dialog with copy, and fits 320px @ 2.0x without overflow',
      (tester) async {
    String? copiedClipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>;
        copiedClipboard = args['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final now = DateTime.utc(2026, 11, 16, 12, 0, 0);
    final healthyProfile = Profile(
      id: 'sub-ok',
      label: 'Healthy Profile',
      url: 'https://sub.example.test/ok',
      autoUpdateDuration: const Duration(hours: 24),
      lastUpdateDate: now,
      subscriptionInfo: SubscriptionInfo(
        upload: 10,
        download: 10,
        total: 100,
        expire: now.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
      ),
    );
    final env = _QuotaHealthEnv(clock: now, profile: healthyProfile);
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      _wrapTestApp(
        overrides: [
          healthProbeEnvironmentProvider.overrideWithValue(env),
          aiAutoProbeOnOpenProvider.overrideWithValue(false),
          aiEndpointRunnerProvider.overrideWithValue(
            AiEndpointReachabilityRunner(
              prober: (uri,
                      {required explicitProxyDirective, required timeout}) async =>
                  switch (uri.host) {
                    'generativelanguage.googleapis.com' =>
                      const AiHttpProbeOutcome(statusCode: 200),
                    'api.anthropic.com' =>
                      const AiHttpProbeOutcome(statusCode: 451),
                    _ => const AiHttpProbeOutcome(errorCode: 'timeout'),
                  },
            ),
          ),
          cliProxyDiagnosticsRunnerProvider.overrideWithValue(
            CliProxyDiagnosticsRunner(
              envReader: () => const {},
              gitConfigReader: (_) async => null,
              wslGatewayReader: () async => '172.24.160.1',
            ),
          ),
        ],
        home: const HealthCheckView(),
      ),
    );
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(const ValueKey('health-agent-ux-card'));
    await tester.scrollUntilVisible(
      cardFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(cardFinder, findsOneWidget);
    final probeBtn = find.byKey(const ValueKey('health-ai-probe-button'));
    await tester.scrollUntilVisible(
      probeBtn,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(probeBtn);
    await tester.pumpAndSettle();
    await tester.tap(probeBtn);
    await tester.pumpAndSettle();

    expect(find.text('可达 (200)'), findsOneWidget);
    expect(find.text('IP 地区受限 (451)'), findsOneWidget);
    expect(find.text('TLS / 超时失败'), findsOneWidget);

    final cliBtn = find.byKey(const ValueKey('health-open-cli-proxy-dialog'));
    await tester.scrollUntilVisible(
      cliBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(cliBtn);
    await tester.pumpAndSettle();
    await tester.tap(cliBtn);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('cli-proxy-diagnostics-dialog')),
      findsOneWidget,
    );
    final copyAllBtn = find.byKey(const ValueKey('cli-proxy-copy-all'));
    await tester.ensureVisible(copyAllBtn);
    await tester.tap(copyAllBtn);
    await tester.pumpAndSettle();

    expect(copiedClipboard, isNotNull);
    expect(copiedClipboard, contains('http://127.0.0.1:7890'));
    expect(copiedClipboard, contains('http://172.24.160.1:7890'));
    expect(copiedClipboard, contains('git config --global http.proxy'));
    expect(tester.takeException(), isNull);
  });

  test(
      'Task 5b: setup.dart buildSignedUpdateDefines supports Ed25519 manifest URL without cert SHA256 and optional Authenticode cleans temp PFX',
      () async {
    expect(setup.Build.buildSignedUpdateDefines(), isEmpty);
    expect(
      setup.Build.buildSignedUpdateDefines(
        manifestUrl: 'https://updates.example.com/latest.json',
        isMacOS: false,
      ),
      ['--dart-define=FCX_RELEASE_MANIFEST_URL=https://updates.example.com/latest.json'],
    );
    expect(
      setup.Build.buildSignedUpdateDefines(
        certSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        macosTeamId: 'TEAM123456',
        isMacOS: true,
      ),
      [
        '--dart-define=FCX_RELEASE_CERT_SHA256=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        '--dart-define=FCX_MACOS_TEAM_ID=TEAM123456',
      ],
    );
    expect(
      () => setup.Build.buildSignedUpdateDefines(
        manifestUrl: 'http://insecure.example.com/latest.json',
        isMacOS: false,
      ),
      throwsStateError,
    );

    final dummyTarget = File(p.join(tempDir.path, 'FreedomNet.exe'));
    await dummyTarget.writeAsBytes(const [0x4d, 0x5a]);

    // Unset PFX skips cleanly.
    expect(
      await setup.Build.signOptionalWindowsAuthenticode(
        dummyTarget.path,
        pfxBase64: '',
      ),
      isFalse,
    );

    // Configured PFX invokes signtool sign + verify and cleans temp PFX.
    final commands = <List<String>>[];
    String? tempPfxPath;
    final signed = await setup.Build.signOptionalWindowsAuthenticode(
      dummyTarget.path,
      pfxBase64: base64Encode(const [1, 2, 3, 4]),
      password: 'secret-pass',
      signtoolPath: r'C:\Windows\signtool.exe',
      runner: (cmd) async {
        commands.add(cmd);
        final fIdx = cmd.indexOf('/f');
        if (fIdx >= 0) {
          tempPfxPath = cmd[fIdx + 1];
          expect(File(tempPfxPath!).existsSync(), isTrue);
        }
      },
    );
    expect(signed, isTrue);
    expect(commands, hasLength(2));
    expect(commands[0], containsAllInOrder(['sign', '/fd', 'SHA256']));
    expect(commands[0], containsAllInOrder(['/p', 'secret-pass']));
    expect(commands[1], [
      r'C:\Windows\signtool.exe',
      'verify',
      '/pa',
      dummyTarget.absolute.path,
    ]);
    expect(tempPfxPath, isNotNull);
    expect(File(tempPfxPath!).existsSync(), isFalse);

    final workflowYaml =
        File('.github/workflows/build.yaml').readAsStringSync();
    expect(workflowYaml, contains('WINDOWS_CODESIGN_PFX_B64'));
    expect(workflowYaml, contains('WINDOWS_CODESIGN_PASSWORD'));
    expect(workflowYaml, contains('WINDOWS_CODESIGN_TIMESTAMP_URL'));
    expect(workflowYaml, contains('FCX_RELEASE_ED25519_PRIVATE_KEY'));
    expect(workflowYaml, contains('tool/sign_release_manifest.go'));
    expect(workflowYaml, contains('/api/v1/client/releases/files/\${version}'));
    expect(workflowYaml, contains('--verify --in ./dist/latest.json'));
    expect(
      workflowYaml.indexOf('Generate signed release manifest (latest.json)'),
      lessThan(workflowYaml.indexOf('Generate sha256')),
    );
  });

  testWidgets(
      'Task 2: autoCheckUpdate uses SignedUpdate and opens SignedUpdateDialog without github.com links or unconfigured-cert copy',
      (tester) async {
    expect(repository, 'pluralplay/FlClashX');
    final controllerSrc = File('lib/controller.dart').readAsStringSync();
    expect(controllerSrc, isNot(contains('github.com')));
    expect(controllerSrc, isNot(contains('request.checkForUpdate')));

    // Real zero-arg SignedUpdateDialog enables Ed25519 checks out-of-the-box.
    await tester.pumpWidget(
      _wrapTestApp(
        home: const SignedUpdateDialog(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ed25519'), findsWidgets);
    expect(find.textContaining('Authenticode'), findsWidgets);
    expect(find.textContaining('未配置发布证书'), findsNothing);
    expect(find.textContaining('FCX_RELEASE_CERT_SHA256'), findsNothing);
    expect(find.text('检查并准备更新'), findsOneWidget);

    // AppController.autoCheckUpdate prompts and opens SignedUpdateDialog on confirm.
    final fakeUpdater = _FakeSignedUpdate(
      result: const SignedUpdateCheckResult(
        version: '2.4.0',
        releaseNotes: '修复大陆更新通道\n优化 AI 连通性诊断',
      ),
    );
    globalState.config = const Config(
      themeProps: defaultThemeProps,
      appSetting: AppSettingProps(autoCheckUpdate: true),
    );

    final prevIsPre = globalState.isPre;
    globalState.isPre = false;
    addTearDown(() => globalState.isPre = prevIsPre);

    AppController? realController;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              globalState.measure = Measure.of(context, 1.0);
              globalState.theme = CommonTheme.of(context, 1.0);
              realController ??= AppController(context, ref);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(realController!.autoCheckUpdateWith(signedUpdater: fakeUpdater));
    await tester.pumpAndSettle();

    expect(fakeUpdater.checkedVersions, ['1.0.0']);
    expect(find.textContaining('2.4.0', findRichText: true), findsOneWidget);
    final confirmBtn = find.text('立即更新');
    expect(confirmBtn, findsOneWidget);

    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.byType(SignedUpdateDialog), findsOneWidget);
    expect(find.textContaining('发现已验证新版本 2.4.0'), findsOneWidget);
    expect(find.textContaining('修复大陆更新通道'), findsOneWidget);
  });
}

class _FakeSignedUpdate extends Fake implements SignedUpdate {
  _FakeSignedUpdate({required this.result});

  final SignedUpdateCheckResult? result;
  final List<String> checkedVersions = <String>[];

  @override
  String? get unavailable => null;

  @override
  Future<SignedUpdateCheckResult?> checkAvailableUpdate(
    String currentVersion,
  ) async {
    checkedVersions.add(currentVersion);
    return result;
  }

  @override
  Future<bool> hasRollback() async => false;

  @override
  Future<String?> lastResult() async => null;

  @override
  void cancel() {}
}

class _CallbackAdapter implements HttpClientAdapter {
  _CallbackAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _handler(options);

  @override
  void close({bool force = false}) {}
}
