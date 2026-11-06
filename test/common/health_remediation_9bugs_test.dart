import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/health/health_verdict.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/proxy_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/tools/health_check_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttpOverrides extends HttpOverrides {}

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

class _ScenarioEnvironment implements HealthProbeEnvironment {
  _ScenarioEnvironment({
    required this.snapshot,
    this.tunStatus = const TunStatus(
      instanceId: 'core-1',
      revision: 1,
      state: 'on',
      listenerActive: true,
      interfaceState: 'up',
      privilege: 'elevated',
      requestedEnabled: true,
    ),
    this.windowsProxy,
    this.onDelayProbe,
    this.onLookupHost,
  });

  final HealthConfigSnapshot snapshot;
  TunStatus? tunStatus;
  WindowsSystemProxySnapshot? windowsProxy;
  Future<DelayTestResult> Function(String proxyName, String testUrl)?
      onDelayProbe;
  Future<List<InternetAddress>> Function(String host)? onLookupHost;
  EndToEndProbeObservation? e2e = const EndToEndProbeObservation(
    exitCountryCode: 'HK',
    observedInCore: true,
    matchedLeafProxy: 'HK-01',
  );
  String? lastExplicitProxyDirective;
  final List<String> queriedDnsHosts = [];
  final List<(String proxyName, String testUrl)> delayProbes = [];

  @override
  DateTime now() => DateTime.utc(2026, 11, 6, 1, 30, 0);

  @override
  String get platform => 'windows';

  @override
  String get appVersion => '0.4.2-test';

  @override
  Future<HealthConfigSnapshot> readConfigSnapshot() async => snapshot;

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async =>
      const CoreLivenessObservation(
        isInit: true,
        memoryBytes: 64 * 1024 * 1024,
        trafficValid: true,
      );

  @override
  Future<TunStatus?> readTunStatus() async => tunStatus;

  @override
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy() async =>
      windowsProxy;

  @override
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  }) async {
    delayProbes.add((proxyName, testUrl));
    if (onDelayProbe != null) {
      return onDelayProbe!(proxyName, testUrl);
    }
    return const DelayTestResult(45);
  }

  @override
  Future<void> cancelProxyDelay(String requestId) async {}

  @override
  Future<List<InternetAddress>> lookupHost(String host) async {
    queriedDnsHosts.add(host);
    if (onLookupHost != null) {
      return onLookupHost!(host);
    }
    return [InternetAddress('198.18.0.10')];
  }

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async {
    lastExplicitProxyDirective = explicitProxyDirective;
    return e2e;
  }
}

HealthConfigSnapshot _buildSnapshot({
  String profileId = '1793860000001',
  Profile? profile,
  bool profileFileExists = true,
  int profileFileBytes = 693,
  Mode mode = Mode.rule,
  int mixedPort = 7890,
  String testUrl = 'https://www.gstatic.com/generate_204',
  bool systemProxyEnabled = false,
  bool pacEnabled = false,
  String? pacUrl,
  bool tunDesiredEnabled = true,
  bool realTunEnable = true,
  bool proxyStarted = true,
  List<Group>? allGroups,
  List<Group>? visibleGroups,
  Map<String, String> selectedMap = const {},
  String? primaryRuleTargetGroup,
}) {
  final defaultGroups = allGroups ??
      const [
        Group(
          type: GroupType.Selector,
          name: 'Proxy',
          now: 'HK-01',
          all: [Proxy(name: 'HK-01', type: 'Trojan')],
        ),
        Group(
          type: GroupType.Selector,
          name: 'GLOBAL',
          now: 'Proxy',
          all: [Proxy(name: 'Proxy', type: 'Selector')],
        ),
      ];
  final defaultProfile = profile ??
      Profile(
        id: profileId,
        label: '俊雄',
        url: 'https://sub.example.com/api/v1/client/subscribe?token=redacted',
        currentGroupName: 'Proxy',
        autoUpdateDuration: const Duration(hours: 12),
        lastUpdateDate: DateTime.utc(2026, 11, 5, 19, 36),
        subscriptionInfo: const SubscriptionInfo(
          upload: 22 * 1024 * 1024 * 1024,
          download: 20 * 1024 * 1024 * 1024,
          total: 500 * 1024 * 1024 * 1024,
          expire: 0,
        ),
      );
  return HealthConfigSnapshot(
    currentProfileId: profileId,
    currentProfile: defaultProfile,
    profileFileExists: profileFileExists,
    profileFileBytes: profileFileBytes,
    mode: mode,
    mixedPort: mixedPort,
    testUrl: testUrl,
    resolveGroupTestUrl: (u) => (u != null && u.isNotEmpty) ? u : testUrl,
    systemProxyEnabled: systemProxyEnabled,
    pacEnabled: pacEnabled,
    pacUrl: pacUrl,
    tunDesiredEnabled: tunDesiredEnabled,
    tunFailureCode: null,
    realTunEnable: realTunEnable,
    proxyStarted: proxyStarted,
    lastRuntimeProfileId: profileId,
    groupsSnapshotProfileId: profileId,
    allGroups: defaultGroups,
    visibleGroups: visibleGroups ?? [defaultGroups.first],
    selectedMap: selectedMap,
    primaryRuleTargetGroup: primaryRuleTargetGroup,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('fcx_hc_9bugs_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Bug 1: DefaultHealthProbeEnvironment.readConfigSnapshot real ProviderContainer closure safety', () {
    test('reads real non-empty profile YAML without Isolate unsendable Ref crash', () async {
      const profileId = '1793861234567';
      final profilePath = await appPath.getProfilePath(profileId);
      final profileFile = File(profilePath);
      await profileFile.parent.create(recursive: true);
      final yamlBytes = utf8.encode(
        'mixed-port: 7890\nmode: rule\nproxies:\n  - {name: HK-01, type: socks5, server: 127.0.0.1, port: 1080}\n'
        'proxy-groups:\n  - {name: Proxy, type: select, proxies: [HK-01]}\nrules:\n  - MATCH,Proxy\n',
      );
      await profileFile.writeAsBytes(yamlBytes, flush: true);

      const group = Group(
        type: GroupType.Selector,
        name: 'Proxy',
        now: 'HK-01',
        all: [Proxy(name: 'HK-01', type: 'Socks5')],
      );
      final profile = Profile(
        id: profileId,
        label: '俊雄',
        url: 'https://sub.example.com/s',
        currentGroupName: 'Proxy',
        autoUpdateDuration: const Duration(hours: 12),
        lastUpdateDate: DateTime.utc(2026, 11, 5, 19, 36),
        subscriptionInfo: const SubscriptionInfo(
          upload: 1024,
          download: 2048,
          total: 100 * 1024 * 1024,
          expire: 0,
        ),
      );

      globalState.config = Config(
        themeProps: defaultThemeProps,
        currentProfileId: profileId,
        profiles: [profile],
      );
      globalState.appState = AppState(
        pageLabel: PageLabel.dashboard,
        viewSize: const Size(960, 760),
        isInit: true,
        runTime: 10000,
        version: 1,
        requests: FixedList(10),
        logs: FixedList(10),
        traffics: FixedList(10),
        totalTraffic: Traffic(),
        groups: const [group],
        delayMap: const {},
      );
      globalState.lastRuntimeProfileId = profileId;
      globalState.lastRuntimeConfig = <String, dynamic>{
        'mixed-port': 7890,
        'rules': <String>['MATCH,Proxy'],
        'proxy-groups': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Proxy', 'type': 'select'},
        ],
      };

      final container = ProviderContainer(
        overrides: [
          tunRuntimeProvider.overrideWith((ref) => TunRuntimeController()),
        ],
      );
      addTearDown(container.dispose);

      final env = container.read(healthProbeEnvironmentProvider);
      final snap = await env.readConfigSnapshot();

      expect(snap.profileFileExists, isTrue);
      expect(snap.profileFileBytes, yamlBytes.length);
      expect(snap.resolveGroupTestUrl(null), isNotEmpty);
      expect(snap.primaryRuleTargetGroup, 'Proxy');
    });
  });

  group('Bug 2: D1 Mainland China captive-portal probe & Verdict non-contradiction', () {
    test('D1 probes domestic/global captive portal instead of blocked gstatic testUrl, and falls back when primary captive portal fails', () async {
      final env = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          testUrl: 'https://www.gstatic.com/generate_204',
        ),
        onDelayProbe: (proxyName, url) async {
          if (proxyName == 'DIRECT') {
            if (url.contains('gstatic.com')) {
              return const DelayTestResult(-1, reason: 'deadlineExceeded');
            }
            if (url.contains('hicloud.com')) {
              return const DelayTestResult(-1, reason: 'testFailed');
            }
            return const DelayTestResult(24);
          }
          return const DelayTestResult(86);
        },
      );

      final report = await HealthRunner(env).run();
      final d1 = report.checkById(HealthCheckId.directConnectivity)!;
      expect(d1.status, HealthStatus.passed);
      expect(d1.delayMs, 24);
      expect(
        env.delayProbes.where(
          (p) => p.$1 == 'DIRECT' && p.$2.contains('gstatic.com'),
        ),
        isEmpty,
      );
      expect(report.verdict.code, 'healthy');
    });

    test('computeHealthVerdict never claims localNetworkDown when D3 or D4 proves physical uplink is working', () {
      final verdict = computeHealthVerdict(
        const [
          HealthCheckResult(
            id: HealthCheckId.profileSelected,
            status: HealthStatus.passed,
            elapsedMs: 1,
            reasonCode: 'ok',
          ),
          HealthCheckResult(
            id: HealthCheckId.subscriptionHealth,
            status: HealthStatus.passed,
            elapsedMs: 0,
            reasonCode: 'ok',
          ),
          HealthCheckResult(
            id: HealthCheckId.runtimeConfigLoaded,
            status: HealthStatus.passed,
            elapsedMs: 0,
            reasonCode: 'ok',
          ),
          HealthCheckResult(
            id: HealthCheckId.coreResponsive,
            status: HealthStatus.passed,
            elapsedMs: 12,
            reasonCode: 'ok',
          ),
          HealthCheckResult(
            id: HealthCheckId.proxyStarted,
            status: HealthStatus.passed,
            elapsedMs: 0,
            reasonCode: 'ok',
          ),
          HealthCheckResult(
            id: HealthCheckId.tunTakeover,
            status: HealthStatus.passed,
            elapsedMs: 20,
            reasonCode: 'tunReadyElevated',
          ),
          HealthCheckResult(
            id: HealthCheckId.systemProxyTakeover,
            status: HealthStatus.skipped,
            elapsedMs: 0,
            reasonCode: 'systemProxyDisabledByPreference',
          ),
          HealthCheckResult(
            id: HealthCheckId.trafficTakeover,
            status: HealthStatus.passed,
            elapsedMs: 0,
            reasonCode: 'takeoverTun',
          ),
          HealthCheckResult(
            id: HealthCheckId.directConnectivity,
            status: HealthStatus.timeout,
            elapsedMs: 4400,
            reasonCode: 'directTimeout',
          ),
          HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.passed,
            elapsedMs: 2,
            reasonCode: 'dnsFakeIpActive',
          ),
          HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.passed,
            elapsedMs: 95,
            reasonCode: 'ok',
            nodeName: 'HK-01',
            delayMs: 95,
          ),
          HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.passed,
            elapsedMs: 310,
            reasonCode: 'ok',
            exitCountryCode: 'HK',
          ),
        ],
        activeNodeName: 'HK-01',
        outboundDelayMs: 95,
        exitCountryCode: 'HK',
      );

      expect(verdict.code, isNot('localNetworkDown'));
      expect(verdict.code, 'healthyWithWarnings');
      expect(verdict.severity, HealthVerdictSeverity.warning);
      expect(verdict.activeNodeName, 'HK-01');
      expect(verdict.outboundDelayMs, 95);
    });
  });

  group('Bug 3: System Proxy hijack detail, distinct error copy, forceReapply action, and inactive PAC flag', () {
    test('3a & 3b & 3d: manual hijack reports mismatched port detail, 5 error codes map to distinct messages, and inactive autoConfigActive=false does not warn', () async {
      final l10n = await AppLocalizations.load(const Locale('zh', 'CN'));

      final hijackSingle = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:10808',
        ),
      );
      expect(hijackSingle.status, HealthStatus.failed);
      expect(hijackSingle.reasonCode, 'systemProxyHijacked');
      expect(hijackSingle.localDetail, '127.0.0.1:10808');

      final hijackPerScheme = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: 'http=127.0.0.1:10808;https=127.0.0.1:7890',
        ),
      );
      expect(hijackPerScheme.localDetail, '127.0.0.1:10808');

      // 3b: 5 distinct error strings
      final messages = <String>{
        for (final code in const [
          'systemProxyReadFailed',
          'systemProxyInvalidPort',
          'systemProxyNotApplied',
          'systemProxyDisabledExternally',
          'systemProxyHijacked',
        ])
          healthCheckItemDetail(
            HealthCheckResult(
              id: HealthCheckId.systemProxyTakeover,
              status: HealthStatus.failed,
              elapsedMs: 5,
              reasonCode: code,
              localDetail: code == 'systemProxyHijacked' ? '127.0.0.1:10808' : null,
            ),
            l10n,
          ),
      };
      expect(messages, hasLength(5));
      expect(messages.any((m) => m.contains('127.0.0.1:10808')), isTrue);

      // 3d: Inactive stale AutoConfigURL in registry when DefaultConnectionSettings PAC bit (0x04) is off
      final inactivePac = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
          autoConfigUrl: 'http://127.0.0.1:19999/pac',
          autoConfigActive: false,
        ),
      );
      expect(inactivePac.status, HealthStatus.passed);
      expect(inactivePac.reasonCode, 'ok');
    });

    testWidgets('3c: hijacked C3 emits reapplySystemProxy action and SystemProxyCoordinator.forceReapply re-writes OS proxy despite cached signature', (tester) async {
      final env = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          tunDesiredEnabled: false,
          realTunEnable: false,
          systemProxyEnabled: true,
          mixedPort: 7890,
        ),
        tunStatus: const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'off',
          listenerActive: false,
          interfaceState: 'down',
          privilege: 'elevated',
          requestedEnabled: false,
        ),
        windowsProxy: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:10808',
        ),
      );
      final report = await HealthRunner(env).run();
      expect(
        report.checkById(HealthCheckId.systemProxyTakeover)?.action,
        HealthAction.reapplySystemProxy,
      );
      expect(report.verdict.primaryAction, HealthAction.reapplySystemProxy);

      // Verify SystemProxyCoordinator.forceReapply bypasses _lastApplied cache
      final startProxyCalls = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('proxy'), (call) async {
        if (call.method == 'StartProxy') {
          final args = call.arguments as Map<dynamic, dynamic>;
          startProxyCalls.add(args['port'] as int);
          return true;
        }
        if (call.method == 'StopProxy' || call.method == 'StartPac') {
          return true;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('proxy'), null);
      });

      globalState.config = Config(
        themeProps: defaultThemeProps,
        networkProps: const NetworkProps(systemProxy: true),
        patchClashConfig: defaultClashConfig.copyWith(mixedPort: 7890),
      );
      globalState.appState = AppState(
        pageLabel: PageLabel.dashboard,
        viewSize: const Size(960, 760),
        isInit: true,
        runTime: 5000,
        version: 1,
        requests: FixedList(5),
        logs: FixedList(5),
        traffics: FixedList(5),
        totalTraffic: Traffic(),
        groups: const [],
        delayMap: const {},
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProxyManager(child: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(startProxyCalls, [7890]);

      // External app hijacked registry without changing Riverpod state -> forceReapply MUST rewrite 7890!
      final reapplied = await systemProxyCoordinator.forceReapply();
      expect(reapplied, isTrue);
      expect(startProxyCalls, [7890, 7890]);
    });
  });

  group('Bug 5: D3 _selectActiveGroup ignores last-viewed AdBlock/Direct tabs and stale GLOBAL in Rule mode', () {
    test('uses primaryRuleTargetGroup (or non-utility selector group) instead of AdBlock REJECT tab or stale GLOBAL', () async {
      const groups = [
        Group(
          type: GroupType.Selector,
          name: '🛑 广告拦截',
          now: 'REJECT',
          all: [
            Proxy(name: 'REJECT', type: 'Reject'),
            Proxy(name: 'DIRECT', type: 'Direct'),
          ],
        ),
        Group(
          type: GroupType.Selector,
          name: '🚀 节点选择',
          now: 'SG-IEPL-01',
          all: [
            Proxy(name: 'SG-IEPL-01', type: 'Trojan'),
            Proxy(name: 'DIRECT', type: 'Direct'),
          ],
        ),
        Group(
          type: GroupType.Selector,
          name: 'GLOBAL',
          now: 'DIRECT',
          all: [
            Proxy(name: 'DIRECT', type: 'Direct'),
            Proxy(name: '🚀 节点选择', type: 'Selector'),
          ],
        ),
      ];

      // Case A: User last clicked '🛑 广告拦截' tab, primaryRuleTargetGroup from MATCH is '🚀 节点选择'
      final adTabEnv = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          profile: Profile(
            id: 'p1',
            label: 'Test',
            url: 'https://sub.example.com/1',
            currentGroupName: '🛑 广告拦截',
            autoUpdateDuration: const Duration(hours: 12),
            lastUpdateDate: DateTime.utc(2026, 11, 5),
          ),
          allGroups: groups,
          visibleGroups: [groups[0], groups[1]],
          primaryRuleTargetGroup: '🚀 节点选择',
        ),
      );
      final adReport = await HealthRunner(adTabEnv).run();
      final d3A = adReport.checkById(HealthCheckId.outboundConnectivity)!;
      expect(d3A.status, HealthStatus.passed);
      expect(d3A.nodeName, 'SG-IEPL-01');

      // Case B: Takeover without primaryRuleTargetGroup, currentGroupName is stale 'GLOBAL' (or '🛑 广告拦截')
      final takeoverEnv = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          profile: Profile(
            id: 'p1',
            label: 'Test',
            url: 'https://sub.example.com/1',
            currentGroupName: 'GLOBAL',
            autoUpdateDuration: const Duration(hours: 12),
            lastUpdateDate: DateTime.utc(2026, 11, 5),
          ),
          allGroups: groups,
          visibleGroups: [groups[0], groups[1]],
          primaryRuleTargetGroup: null,
        ),
      );
      final takeoverReport = await HealthRunner(takeoverEnv).run();
      final d3B = takeoverReport.checkById(HealthCheckId.outboundConnectivity)!;
      expect(d3B.status, HealthStatus.passed);
      expect(d3B.nodeName, 'SG-IEPL-01');
    });
  });

  group('Bug 6: D2 DNS probe avoids GFW-poisoned host in System-Proxy-Only mode and flags stale Fake-IP when TUN is inactive', () {
    test('System-Proxy-Only mode does not query gstatic.com via OS DNS, and stale 198.18.x.x fails when TUN/Proxy is off', () async {
      // 6a: System-Proxy-Only in Mainland China -> www.gstatic.com returns poisoned 127.0.0.1 on OS DNS
      final sysProxyChinaEnv = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          tunDesiredEnabled: false,
          realTunEnable: false,
          systemProxyEnabled: true,
          mixedPort: 7890,
        ),
        tunStatus: const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'off',
          listenerActive: false,
          interfaceState: 'down',
          privilege: 'elevated',
          requestedEnabled: false,
        ),
        windowsProxy: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
        ),
        onLookupHost: (host) async {
          if (host.contains('gstatic.com')) {
            return [InternetAddress('127.0.0.1')];
          }
          return [InternetAddress('203.0.113.25')];
        },
      );
      final sysProxyReport = await HealthRunner(sysProxyChinaEnv).run();
      final d2Sys = sysProxyReport.checkById(HealthCheckId.dnsResolution)!;
      expect(d2Sys.status, HealthStatus.passed);
      expect(sysProxyChinaEnv.queriedDnsHosts, isNot(contains('www.gstatic.com')));

      // 6b: Proxy stopped (or TUN inactive) while Windows DNS cache still returns stale Fake-IP 198.18.0.2
      final staleFakeIpEnv = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          proxyStarted: false,
          tunDesiredEnabled: true,
          realTunEnable: false,
        ),
        onLookupHost: (_) async => [InternetAddress('198.18.0.2')],
      );
      final staleReport = await HealthRunner(staleFakeIpEnv).run();
      final d2Stale = staleReport.checkById(HealthCheckId.dnsResolution)!;
      expect(d2Stale.status, HealthStatus.failed);
      expect(d2Stale.reasonCode, 'dnsStaleFakeIp');
    });
  });

  group('Bug 7: Zombie closeFailed adapter (listenerActive=false) is not treated as active TUN takeover', () {
    test('warns tunCloseFailed in C2, uses verified System Proxy in D4 when System Proxy is ON, and fails C4 when System Proxy is OFF', () async {
      // Zombie handle with System Proxy ON -> D4 must use PROXY 127.0.0.1:7890, NOT DIRECT!
      final zombieWithSysProxy = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          tunDesiredEnabled: false,
          realTunEnable: false,
          systemProxyEnabled: true,
          mixedPort: 7890,
        ),
        tunStatus: const TunStatus(
          instanceId: 'core-1',
          revision: 2,
          state: 'off',
          listenerActive: false,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: false,
          errorCode: 'closeFailed',
        ),
        windowsProxy: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
        ),
        onLookupHost: (_) async => [InternetAddress('203.0.113.25')],
      );

      final reportWithSys = await HealthRunner(zombieWithSysProxy).run();
      expect(
        reportWithSys.checkById(HealthCheckId.tunTakeover)?.reasonCode,
        'tunCloseFailed',
      );
      expect(
        zombieWithSysProxy.lastExplicitProxyDirective,
        'PROXY 127.0.0.1:7890',
      );

      // Zombie handle with System Proxy OFF -> NO listener is capturing traffic -> C4 must FAIL!
      final zombieNoTakeover = _ScenarioEnvironment(
        snapshot: _buildSnapshot(
          tunDesiredEnabled: false,
          realTunEnable: false,
          systemProxyEnabled: false,
          mixedPort: 7890,
        ),
        tunStatus: const TunStatus(
          instanceId: 'core-1',
          revision: 2,
          state: 'off',
          listenerActive: false,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: false,
          errorCode: 'closeFailed',
        ),
        onLookupHost: (_) async => [InternetAddress('203.0.113.25')],
      );
      final reportNoTakeover = await HealthRunner(zombieNoTakeover).run();
      expect(
        reportNoTakeover.checkById(HealthCheckId.trafficTakeover)?.status,
        HealthStatus.failed,
      );
      expect(reportNoTakeover.verdict.code, 'takeoverFailed');
    });
  });

  group('Bug 8 & Bug 9a: E2E attemptTimeout failover + closed DIRECT connection observation + effective mixedPort', () {
    test('resolveEffectiveMixedPort prioritizes runtime mixed-port (including 0) when profile matches', () {
      expect(
        resolveEffectiveMixedPort(
          configuredMixedPort: 7890,
          lastRuntimeConfig: const {'mixed-port': 7897},
          lastRuntimeProfileId: 'prof-1',
          currentProfileId: 'prof-1',
        ),
        7897,
      );
      expect(
        resolveEffectiveMixedPort(
          configuredMixedPort: 7890,
          lastRuntimeConfig: const {'mixed-port': 0},
          lastRuntimeProfileId: 'prof-1',
          currentProfileId: 'prof-1',
        ),
        0,
      );
      expect(
        resolveEffectiveMixedPort(
          configuredMixedPort: 7890,
          lastRuntimeConfig: const {'mixed-port': 7897},
          lastRuntimeProfileId: 'other-prof',
          currentProfileId: 'prof-1',
        ),
        7890,
      );
    });

    test('8a & 8b: probeEndToEnd aborts header-trickling primary source via attemptTimeout, fails over to secondary source, and observes closed DIRECT rule connection from requestsProvider', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final trickleServer =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final fastServer =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(trickleServer.close);
        addTearDown(fastServer.close);

        final trickleTimers = <Timer>[];
        addTearDown(() {
          for (final t in trickleTimers) {
            t.cancel();
          }
        });

        // Primary source trickles header lines every 800ms so idle/receiveTimeout never triggers
        trickleServer.listen((socket) {
          socket.add(utf8.encode('HTTP/1.1 200 OK\r\n'));
          trickleTimers.add(
            Timer.periodic(const Duration(milliseconds: 800), (timer) {
              try {
                socket.add(utf8.encode('X-Trickle: 1\r\n'));
              } catch (_) {
                timer.cancel();
              }
            }),
          );
        });

        int? observedClientPort;
        fastServer.listen((socket) {
          observedClientPort = socket.remotePort;
          socket.listen((chunk) {
            if (utf8.decode(chunk, allowMalformed: true).contains('\r\n\r\n')) {
              // Simulate Go Core recording this short-lived DIRECT connection in requestsProvider
              final conn = Connection(
                id: 'conn-direct-1',
                start: DateTime.now(),
                chains: const ['DIRECT'],
                metadata: Metadata(
                  uid: 0,
                  network: 'tcp',
                  type: 'HTTP',
                  sourceIP: '127.0.0.1',
                  destinationIP: '127.0.0.1',
                  sourcePort: '${socket.remotePort}',
                  destinationPort: '${fastServer.port}',
                  host: '127.0.0.1',
                  process: 'FlClashX.exe',
                  remoteDestination: '127.0.0.1',
                ),
              );
              globalState.appState = globalState.appState.copyWith(
                requests: FixedList<Connection>(10)..add(conn),
              );
              const body = '{"ip":"114.114.114.114","country":"CN"}';
              const resp = 'HTTP/1.1 200 OK\r\n'
                  'Content-Type: application/json\r\n'
                  'Content-Length: ${body.length}\r\n'
                  'Connection: close\r\n\r\n'
                  '$body';
              socket.add(utf8.encode(resp));
              unawaited(socket.flush().then((_) => socket.close()));
            }
          });
        });

        globalState.config = const Config(themeProps: defaultThemeProps);
        globalState.appState = AppState(
          pageLabel: PageLabel.dashboard,
          viewSize: const Size(960, 760),
          isInit: true,
          runTime: 5000,
          version: 1,
          requests: FixedList(10),
          logs: FixedList(10),
          traffics: FixedList(10),
          totalTraffic: Traffic(),
          groups: const [
            Group(
              type: GroupType.Selector,
              name: 'Proxy',
              now: 'HK-01',
              all: [Proxy(name: 'HK-01', type: 'Trojan')],
            ),
          ],
          delayMap: const {},
        );

        final customReq = Request(
          ipInfoSources: {
            'http://127.0.0.1:${trickleServer.port}/slow': IpInfo.fromIpSbJson,
            'http://127.0.0.1:${fastServer.port}/fast': IpInfo.fromIpInfoIoJson,
          },
        );

        final container = ProviderContainer(
          overrides: [
            tunRuntimeProvider.overrideWith((ref) => TunRuntimeController()),
            healthProbeEnvironmentProvider.overrideWith(
              (ref) =>
                  DefaultHealthProbeEnvironment(ref, probeRequest: customReq),
            ),
          ],
        );
        addTearDown(container.dispose);

        final env = container.read(healthProbeEnvironmentProvider);
        final cancelToken = HealthCancellationToken();
        final obs = await env
            .probeEndToEnd(
              cancelToken: cancelToken,
              explicitProxyDirective: 'DIRECT',
            )
            .timeout(const Duration(seconds: 6));

        expect(observedClientPort, isNotNull);
        expect(obs, isNotNull);
        expect(obs!.exitCountryCode, 'CN');
        expect(obs.observedInCore, isTrue);
        expect(obs.matchedLeafProxy, 'DIRECT');
      }, _RealHttpOverrides());
    });
  });
}
