import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_export.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/health/health_verdict.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProbeEnvironment implements HealthProbeEnvironment {
  _FakeProbeEnvironment({
    DateTime? initialNow,
    HealthConfigSnapshot? configSnapshot,
    Map<String, DelayTestResult>? delayResults,
    this.delayCompleterByProxy,
    List<InternetAddress>? dnsAddresses,
    this.e2eObservation = const EndToEndProbeObservation(
      exitCountryCode: 'HK',
      observedInCore: true,
      matchedLeafProxy: 'HK-Node-01',
    ),
  })  : _now = initialNow ?? DateTime.utc(2026, 11, 1, 10, 0, 0),
        _configSnapshot = configSnapshot ?? _defaultHealthySnapshot(),
        _delayResults = delayResults ??
            const {
              'DIRECT': DelayTestResult(65),
              'Proxy': DelayTestResult(128),
              'GLOBAL': DelayTestResult(128),
            },
        _dnsAddresses =
            dnsAddresses ?? [InternetAddress('198.18.0.2', type: InternetAddressType.IPv4)];

  DateTime _now;
  @override
  String platform = 'windows';
  @override
  String appVersion = '0.4.2-test';
  final HealthConfigSnapshot _configSnapshot;
  CoreLivenessObservation coreLiveness = const CoreLivenessObservation(
    isInit: true,
    memoryBytes: 42 * 1024 * 1024,
    trafficValid: true,
  );
  Duration coreDelay = Duration.zero;
  Exception? coreError;
  TunStatus? tunStatus = const TunStatus(
    instanceId: 'core-1',
    revision: 3,
    state: 'on',
    listenerActive: true,
    interfaceState: 'up',
    privilege: 'elevated',
    requestedEnabled: true,
  );
  Exception? tunError;
  WindowsSystemProxySnapshot? windowsSystemProxy;
  final Map<String, DelayTestResult> _delayResults;
  Duration delayDuration = Duration.zero;
  Map<String, Completer<DelayTestResult>>? delayCompleterByProxy;
  final List<InternetAddress> _dnsAddresses;
  Exception? dnsError;
  Duration dnsDuration = Duration.zero;
  EndToEndProbeObservation? e2eObservation;
  Completer<EndToEndProbeObservation?>? e2eCompleter;

  final List<String> cancelledRequestIds = [];
  String? lastExplicitProxyDirective;
  bool e2eCancelObserved = false;

  static HealthConfigSnapshot _defaultHealthySnapshot() {
    final profile = Profile(
      id: 'prof-1',
      label: 'ceo@corp-secret.internal',
      url: 'https://secret-sub.example.org/api/v1/client/subscribe?token=abc123',
      currentGroupName: 'Proxy',
      lastUpdateDate: DateTime.utc(2026, 11, 1, 9, 30, 0),
      autoUpdateDuration: const Duration(hours: 24),
      subscriptionInfo: const SubscriptionInfo(
        upload: 1024 * 1024 * 100,
        download: 1024 * 1024 * 400,
        total: 1024 * 1024 * 1024 * 100,
        expire: 0,
      ),
      selectedMap: const {'Proxy': 'HK-VIP-SecretNode-99'},
    );
    final groups = [
      const Group(
        type: GroupType.Selector,
        name: 'Proxy',
        now: 'HK-VIP-SecretNode-99',
        all: [
          Proxy(name: 'HK-VIP-SecretNode-99', type: 'Trojan'),
          Proxy(name: 'DIRECT', type: 'Direct'),
        ],
      ),
      const Group(
        type: GroupType.Selector,
        name: 'GLOBAL',
        now: 'Proxy',
        all: [
          Proxy(name: 'Proxy', type: 'Selector'),
        ],
      ),
    ];
    return HealthConfigSnapshot(
      currentProfileId: profile.id,
      currentProfile: profile,
      profileFileExists: true,
      profileFileBytes: 4096,
      mode: Mode.rule,
      mixedPort: 7890,
      testUrl: 'https://www.gstatic.com/generate_204',
      resolveGroupTestUrl: (url) =>
          (url != null && url.isNotEmpty) ? url : 'https://www.gstatic.com/generate_204',
      systemProxyEnabled: false,
      pacEnabled: false,
      pacUrl: null,
      tunDesiredEnabled: true,
      tunFailureCode: null,
      realTunEnable: true,
      proxyStarted: true,
      lastRuntimeProfileId: profile.id,
      groupsSnapshotProfileId: profile.id,
      allGroups: groups,
      visibleGroups: [groups.first],
      selectedMap: profile.selectedMap,
    );
  }

  @override
  DateTime now() => _now;

  void advanceClock(Duration delta) {
    _now = _now.add(delta);
  }

  @override
  Future<HealthConfigSnapshot> readConfigSnapshot() async => _configSnapshot;

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async {
    if (coreDelay > Duration.zero) {
      await Future<void>.delayed(coreDelay);
    }
    if (coreError != null) throw coreError!;
    return coreLiveness;
  }

  @override
  Future<TunStatus?> readTunStatus() async {
    if (tunError != null) throw tunError!;
    return tunStatus;
  }

  @override
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy() async =>
      windowsSystemProxy;

  @override
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  }) async {
    final customCompleter = delayCompleterByProxy?[proxyName];
    if (customCompleter != null) {
      return customCompleter.future;
    }
    if (delayDuration > Duration.zero) {
      await Future<void>.delayed(delayDuration);
    }
    return _delayResults[proxyName] ?? const DelayTestResult(-1, reason: 'testFailed');
  }

  @override
  Future<void> cancelProxyDelay(String requestId) async {
    cancelledRequestIds.add(requestId);
  }

  @override
  Future<List<InternetAddress>> lookupHost(String host) async {
    if (dnsDuration > Duration.zero) {
      await Future<void>.delayed(dnsDuration);
    }
    if (dnsError != null) throw dnsError!;
    return _dnsAddresses;
  }

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async {
    lastExplicitProxyDirective = explicitProxyDirective;
    cancelToken.register(() {
      e2eCancelObserved = true;
    });
    if (e2eCompleter != null) {
      return e2eCompleter!.future;
    }
    return e2eObservation;
  }
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  group('WindowsSystemProxyProbe pure parser & evaluator', () {
    test('parses single host:port, URL-prefixed, IPv6, and per-scheme formats', () {
      final single = parseWindowsProxyServer('127.0.0.1:7890');
      expect(single['*']?.host, '127.0.0.1');
      expect(single['*']?.port, 7890);

      final prefixed = parseWindowsProxyServer('http://localhost:7890');
      expect(prefixed['*']?.host, 'localhost');
      expect(prefixed['*']?.port, 7890);

      final v6 = parseWindowsProxyServer('[::1]:7892');
      expect(v6['*']?.host, '::1');
      expect(v6['*']?.port, 7892);

      final perScheme = parseWindowsProxyServer(
        'http=127.0.0.1:7890;https=127.0.0.1:7890;socks=127.0.0.1:7891',
      );
      expect(perScheme['http']?.port, 7890);
      expect(perScheme['https']?.port, 7890);
      expect(perScheme['socks']?.port, 7891);
    });

    test('evaluates disabled preference, hijacked port, unexpected PAC, and valid PAC', () {
      final skipped = evaluateWindowsSystemProxy(
        expectedEnabled: false,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:10809',
        ),
      );
      expect(skipped.status, HealthStatus.skipped);
      expect(skipped.reasonCode, 'systemProxyDisabledByPreference');

      final hijacked = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:10809',
        ),
      );
      expect(hijacked.status, HealthStatus.failed);
      expect(hijacked.reasonCode, 'systemProxyHijacked');

      final disabledExternally = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: false,
          proxyServer: '127.0.0.1:7890',
        ),
      );
      expect(disabledExternally.status, HealthStatus.failed);
      expect(disabledExternally.reasonCode, 'systemProxyDisabledExternally');

      final residualPac = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
          autoConfigUrl: 'http://127.0.0.1:19999/pac',
        ),
      );
      expect(residualPac.status, HealthStatus.warning);
      expect(residualPac.reasonCode, 'systemProxyUnexpectedPac');

      final validHttp = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: 'http=127.0.0.1:7890;https=localhost:7890',
        ),
      );
      expect(validHttp.status, HealthStatus.passed);
      expect(validHttp.verifiedProxyDirective, 'PROXY 127.0.0.1:7890');

      final validPac = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: true,
        expectedPacUrl: 'http://127.0.0.1:7899/pac?t=1',
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: false,
          autoConfigUrl: 'http://localhost:7899/pac?t=1',
        ),
      );
      expect(validPac.status, HealthStatus.passed);
    });
  });

  group('HealthRunner 12-item checks, root-cause verdict, and privacy export', () {
    test('all-healthy run passes 11 active checks, skips disabled system proxy, and exports closed schema without sensitive strings', () async {
      final env = _FakeProbeEnvironment();
      final runner = HealthRunner(env);

      final report = await runner.run();
      expect(report.checks, hasLength(12));
      expect(report.verdict.code, 'healthy');
      expect(report.verdict.severity, HealthVerdictSeverity.healthy);
      expect(report.verdict.activeNodeName, 'HK-VIP-SecretNode-99');
      expect(report.verdict.outboundDelayMs, 128);
      expect(report.verdict.exitCountryCode, 'HK');
      expect(env.lastExplicitProxyDirective, 'DIRECT');

      expect(
        report.checkById(HealthCheckId.systemProxyTakeover)?.status,
        HealthStatus.skipped,
      );
      expect(
        report.checkById(HealthCheckId.dnsResolution)?.reasonCode,
        'dnsFakeIpActive',
      );
      expect(
        report.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.passed,
      );

      final exportedText = utf8.decode(exportHealthReport(report));
      expect(exportedText, isNot(contains('HK-VIP-SecretNode-99')));
      expect(exportedText, isNot(contains('ceo@corp-secret.internal')));
      expect(exportedText, isNot(contains('secret-sub.example.org')));
      expect(exportedText, isNot(contains('abc123')));
      expect(exportedText, isNot(contains('198.18.0.2')));

      final exportedJson = jsonDecode(exportedText) as Map<String, dynamic>;
      expect(exportedJson['schema'], 2);
      expect(exportedJson['platform'], 'windows');
      expect(exportedJson['mode'], 'rule');
      expect((exportedJson['verdict'] as Map)['code'], 'healthy');
      final checksJson = exportedJson['checks'] as List;
      expect(checksJson, hasLength(12));
      for (final item in checksJson.cast<Map<String, dynamic>>()) {
        expect(item.keys.toSet(), {'id', 'status', 'reasonCode', 'elapsedMs'});
      }

      final l10n = await AppLocalizations.load(const Locale('zh', 'CN'));
      final summary = formatHealthSummaryText(report, l10n);
      expect(summary, isNot(contains('secret-sub.example.org')));
      expect(summary, contains('连接正常'));
    });

    test('subscription expiry (seconds & ms), quota exhaustion, 3-day/90% warning, and Windows takeover A3 compatibility', () async {
      final now = DateTime.utc(2026, 11, 1, 10, 0, 0);
      final expiredSec =
          now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000;
      final base = _FakeProbeEnvironment._defaultHealthySnapshot();

      final expiredEnv = _FakeProbeEnvironment(
        initialNow: now,
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile!.copyWith(
            subscriptionInfo: SubscriptionInfo(
              upload: 0,
              download: 100,
              total: 1000,
              expire: expiredSec,
            ),
          ),
          profileFileExists: true,
          profileFileBytes: 1024,
          mode: base.mode,
          mixedPort: base.mixedPort,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          // Simulate Windows takeover where lastRuntimeProfileId is null!
          lastRuntimeProfileId: null,
          groupsSnapshotProfileId: null,
          allGroups: base.allGroups,
          visibleGroups: base.visibleGroups,
          selectedMap: base.selectedMap,
        ),
      );

      final expiredReport = await HealthRunner(expiredEnv).run();
      expect(
        expiredReport.checkById(HealthCheckId.subscriptionHealth)?.status,
        HealthStatus.failed,
      );
      expect(
        expiredReport.checkById(HealthCheckId.subscriptionHealth)?.reasonCode,
        'subscriptionExpired',
      );
      // Windows takeover (lastRuntimeProfileId == null with non-empty groups) must PASS A3!
      expect(
        expiredReport.checkById(HealthCheckId.runtimeConfigLoaded)?.status,
        HealthStatus.passed,
      );
      expect(expiredReport.verdict.code, 'subscriptionExpired');
      expect(expiredReport.verdict.primaryAction, HealthAction.openPurchase);

      // 2 days left + 92% traffic -> warning
      final soonMs = now.add(const Duration(days: 2)).millisecondsSinceEpoch;
      final warnEnv = _FakeProbeEnvironment(
        initialNow: now,
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile!.copyWith(
            subscriptionInfo: SubscriptionInfo(
              upload: 500,
              download: 420,
              total: 1000,
              expire: soonMs,
            ),
          ),
          profileFileExists: true,
          profileFileBytes: 1024,
          mode: base.mode,
          mixedPort: base.mixedPort,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: base.lastRuntimeProfileId,
          groupsSnapshotProfileId: base.groupsSnapshotProfileId,
          allGroups: base.allGroups,
          visibleGroups: base.visibleGroups,
          selectedMap: base.selectedMap,
        ),
      );
      final warnReport = await HealthRunner(warnEnv).run();
      expect(
        warnReport.checkById(HealthCheckId.subscriptionHealth)?.status,
        HealthStatus.warning,
      );
      expect(warnReport.verdict.code, 'healthyWithWarnings');
      expect(warnReport.verdict.primaryAction, HealthAction.openPurchase);
    });

    test('distinguishes local network down (D1 failed) from active proxy node failure (D1 passed, D3 failed)', () async {
      // Scenario 1: Local network down -> D1 failed AND D3 failed, verdict must blame local network, NOT proxy node!
      final offlineEnv = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(-1, reason: 'testFailed'),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: null,
      );
      final offlineReport = await HealthRunner(offlineEnv).run();
      expect(offlineReport.verdict.code, 'localNetworkDown');
      expect(offlineReport.verdict.primaryAction, isNull);
      expect(
        offlineReport.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.skipped,
      );

      // Scenario 2: D1 passed, D3 failed -> verdict blames outbound proxy node with openProxies action!
      final deadNodeEnv = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(55),
          'Proxy': DelayTestResult(-1, reason: 'deadlineExceeded'),
        },
        e2eObservation: null,
      );
      final deadNodeReport = await HealthRunner(deadNodeEnv).run();
      expect(
        deadNodeReport.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.timeout,
      );
      expect(deadNodeReport.verdict.code, 'outboundNodeFailed');
      expect(deadNodeReport.verdict.primaryAction, HealthAction.openProxies);
      expect(
        deadNodeReport.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.skipped,
      );
    });

    test('detects DNS loopback poisoning (0.0.0.0 / 127.0.0.1) and E2E traffic bypassing Core', () async {
      final bypassedEnv = _FakeProbeEnvironment(
        dnsAddresses: [InternetAddress('127.0.0.1', type: InternetAddressType.IPv4)],
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'CN',
          observedInCore: false,
        ),
      );
      final report = await HealthRunner(bypassedEnv).run();
      expect(
        report.checkById(HealthCheckId.dnsResolution)?.status,
        HealthStatus.failed,
      );
      expect(
        report.checkById(HealthCheckId.dnsResolution)?.reasonCode,
        'dnsPoisonedLoopback',
      );
      expect(
        report.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.warning,
      );
      expect(
        report.checkById(HealthCheckId.endToEndConnectivity)?.reasonCode,
        'trafficBypassedCore',
      );
      // Traffic bypass has priority 8 > DNS failed priority 9
      expect(report.verdict.code, 'trafficBypassed');
      expect(report.verdict.primaryAction, HealthAction.openTunSettings);
    });

    test('proxy stopped skips C2-C4 and D3-D4 without false runtime mismatch warning', () async {
      final base = _FakeProbeEnvironment._defaultHealthySnapshot();
      final stoppedEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 2048,
          mode: base.mode,
          mixedPort: base.mixedPort,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: false,
          proxyStarted: false,
          lastRuntimeProfileId: null,
          groupsSnapshotProfileId: null,
          allGroups: const [],
          visibleGroups: const [],
          selectedMap: const {},
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(-1, reason: 'notFound'),
        },
      );
      final report = await HealthRunner(stoppedEnv).run();
      expect(report.verdict.code, 'proxyNotStarted');
      expect(report.verdict.primaryAction, HealthAction.startProxy);
      expect(
        report.checkById(HealthCheckId.runtimeConfigLoaded)?.status,
        HealthStatus.skipped,
      );
      expect(
        report.checkById(HealthCheckId.tunTakeover)?.status,
        HealthStatus.skipped,
      );
      expect(
        report.checkById(HealthCheckId.directConnectivity)?.status,
        HealthStatus.skipped,
      );
      expect(
        report.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.skipped,
      );
    });

    test('cancellation aborts in-flight Core delay requests and single-flight rejects concurrent run', () async {
      final directCompleter = Completer<DelayTestResult>();
      final outboundCompleter = Completer<DelayTestResult>();
      final env = _FakeProbeEnvironment(
        delayCompleterByProxy: {
          'DIRECT': directCompleter,
          'Proxy': outboundCompleter,
        },
      );
      final runner = HealthRunner(env);
      final token = HealthCancellationToken();

      final firstRun = runner.run(cancelToken: token);
      final cancelledExpectation = expectLater(firstRun, throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runner.isRunning, isTrue);
      expect(runner.run, throwsStateError);

      await token.cancel();
      expect(env.cancelledRequestIds, isNotEmpty);

      directCompleter.complete(const DelayTestResult(-1, reason: 'cancelled'));
      outboundCompleter.complete(const DelayTestResult(-1, reason: 'cancelled'));
      await cancelledExpectation;
      expect(runner.isRunning, isFalse);
    });
  });

  group('computeHealthVerdict priority order', () {
    test('Core unresponsive (P1) wins over profile missing (P2) and proxy stopped (P4)', () {
      final verdict = computeHealthVerdict([
        const HealthCheckResult(
          id: HealthCheckId.profileSelected,
          status: HealthStatus.failed,
          elapsedMs: 0,
          reasonCode: 'noProfileSelected',
          action: HealthAction.openProfiles,
        ),
        const HealthCheckResult(
          id: HealthCheckId.coreResponsive,
          status: HealthStatus.timeout,
          elapsedMs: 3000,
          reasonCode: 'coreIpcTimeout',
          action: HealthAction.restartCore,
        ),
        const HealthCheckResult(
          id: HealthCheckId.proxyStarted,
          status: HealthStatus.failed,
          elapsedMs: 0,
          reasonCode: 'proxyNotStarted',
          action: HealthAction.startProxy,
        ),
      ]);
      expect(verdict.code, 'coreUnresponsive');
      expect(verdict.primaryAction, HealthAction.restartCore);
    });
  });
}
