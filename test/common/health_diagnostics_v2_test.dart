import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_export.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/health/health_verdict.dart';
import 'package:flclashx/common/request.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/views/tools/health_check_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProbeEnvironment
    implements HealthProbeEnvironment, CoreFailedProbeTelemetry {
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
    this.e2eObservationByDirective,
    this.lastFailedProbeObservedInCore = false,
    this.onTestProxyDelay,
  })  : _now = initialNow ?? DateTime.utc(2026, 11, 1, 10, 0, 0),
        _configSnapshot = configSnapshot ?? _defaultHealthySnapshot(),
        _delayResults = delayResults ??
            const {
              'DIRECT': DelayTestResult(65),
              'Proxy': DelayTestResult(128),
              'GLOBAL': DelayTestResult(128),
            },
        _dnsAddresses = dnsAddresses ??
            [InternetAddress('198.18.0.2', type: InternetAddressType.IPv4)];

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
  final Map<String, EndToEndProbeObservation?>? e2eObservationByDirective;
  @override
  bool lastFailedProbeObservedInCore;
  Completer<EndToEndProbeObservation?>? e2eCompleter;

  final List<String> cancelledRequestIds = [];
  final List<String> recordedOutboundTestUrls = [];
  final List<Duration> recordedOutboundTimeouts = [];
  DelayTestResult Function(String proxyName, String testUrl, int callIndex)?
      onTestProxyDelay;
  Future<DelayTestResult> Function(
    String proxyName,
    String testUrl,
    int callIndex,
    Duration timeout,
  )? onTestProxyDelayWithTimeout;
  int _outboundDelayCallCount = 0;
  String? lastExplicitProxyDirective;
  final List<String?> explicitProxyDirectives = [];
  bool e2eCancelObserved = false;

  static HealthConfigSnapshot _defaultHealthySnapshot() {
    final profile = Profile(
      id: 'prof-1',
      label: 'ceo@corp-secret.internal',
      url:
          'https://secret-sub.example.org/api/v1/client/subscribe?token=abc123',
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
      resolveGroupTestUrl: (url) => (url != null && url.isNotEmpty)
          ? url
          : 'https://www.gstatic.com/generate_204',
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
    if (proxyName != 'DIRECT') {
      recordedOutboundTestUrls.add(testUrl);
      recordedOutboundTimeouts.add(timeout);
    }
    if (onTestProxyDelayWithTimeout != null) {
      final callIndex =
          proxyName == 'DIRECT' ? 0 : _outboundDelayCallCount++;
      return onTestProxyDelayWithTimeout!(proxyName, testUrl, callIndex, timeout);
    }
    if (onTestProxyDelay != null) {
      final callIndex =
          proxyName == 'DIRECT' ? 0 : _outboundDelayCallCount++;
      return onTestProxyDelay!(proxyName, testUrl, callIndex);
    }
    final customCompleter = delayCompleterByProxy?[proxyName];
    if (customCompleter != null) {
      return customCompleter.future;
    }
    if (delayDuration > Duration.zero) {
      await Future<void>.delayed(delayDuration);
    }
    return _delayResults[proxyName] ??
        const DelayTestResult(-1, reason: 'testFailed');
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
    explicitProxyDirectives.add(explicitProxyDirective);
    cancelToken.register(() {
      e2eCancelObserved = true;
    });
    if (e2eCompleter != null) {
      return e2eCompleter!.future;
    }
    if (e2eObservationByDirective != null &&
        e2eObservationByDirective!.containsKey(explicitProxyDirective)) {
      return e2eObservationByDirective![explicitProxyDirective];
    }
    return e2eObservation;
  }
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  group('WindowsSystemProxyProbe pure parser & evaluator', () {
    test('parses single host:port, URL-prefixed, IPv6, and per-scheme formats',
        () {
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

    test(
        'evaluates disabled preference, hijacked port, unexpected PAC, and valid PAC',
        () {
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

  group('HealthRunner 12-item checks, root-cause verdict, and privacy export',
      () {
    test(
        'all-healthy run passes 11 active checks, skips disabled system proxy, and exports closed schema without sensitive strings',
        () async {
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

    test(
        'subscription expiry (seconds & ms), quota exhaustion, 3-day/90% warning, and Windows takeover A3 compatibility',
        () async {
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

    test(
        'distinguishes local network down (D1 failed) from active proxy node failure (D1 passed, D3 failed)',
        () async {
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
        HealthStatus.failed,
      );
    });

    test(
        'detects DNS loopback poisoning (0.0.0.0 / 127.0.0.1) and E2E traffic bypassing Core',
        () async {
      final bypassedEnv = _FakeProbeEnvironment(
        dnsAddresses: [
          InternetAddress('127.0.0.1', type: InternetAddressType.IPv4)
        ],
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

    test(
        'proxy stopped skips C2-C4 and D3-D4 without false runtime mismatch warning',
        () async {
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

    test(
        'cancellation aborts in-flight Core delay requests and single-flight rejects concurrent run',
        () async {
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
      outboundCompleter
          .complete(const DelayTestResult(-1, reason: 'cancelled'));
      await cancelledExpectation;
      expect(runner.isRunning, isFalse);
    });
  });

  group('computeHealthVerdict priority order', () {
    test(
        'Core unresponsive (P1) wins over profile missing (P2) and proxy stopped (P4)',
        () {
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

  group('Code Review regressions (CR-HC01, CR-HC02, CR-HC05, CR-HC08)', () {
    test(
        'CR-HC01: Request.checkIpWithHost holds custom-resolved DIRECT socket for telemetry even when tunRuntime.isEnabled is false, fires onSocketConnected, and verified loopback system proxy does not false-warn trafficBypassedCore when stream already closed',
        () async {
      final serverSocketClosed = Completer<void>();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((socket) {
        var responded = false;
        socket.listen(
          (chunk) {
            if (!responded) {
              responded = true;
              const body = '{"ip":"1.2.3.4","country":"SG"}';
              const rawResponse = 'HTTP/1.1 200 OK\r\n'
                  'Content-Type: application/json\r\n'
                  'Content-Length: ${body.length}\r\n'
                  'Connection: keep-alive\r\n'
                  '\r\n'
                  '$body';
              socket.add(utf8.encode(rawResponse));
            }
          },
          onDone: () {
            if (!serverSocketClosed.isCompleted) {
              serverSocketClosed.complete();
            }
            socket.destroy();
          },
          onError: (_) {
            if (!serverSocketClosed.isCompleted) {
              serverSocketClosed.complete();
            }
          },
        );
      });

      Set<String>? connectedPorts;
      final probeReq = Request(
        ipInfoSources: {
          'http://127.0.0.1:${server.port}/json': IpInfo.fromIpInfoIoJson,
        },
      );
      final cancelToken = CancelToken();
      final res = await probeReq.checkIpWithHost(
        cancelToken: cancelToken,
        keepAliveHold: const Duration(seconds: 2),
        forceHoldSocket: true,
        proxyResolver: (_) => 'DIRECT',
        onSocketConnected: (ports) {
          connectedPorts = ports;
        },
      );
      expect(res.data?.ipInfo.countryCode, 'SG');
      expect(connectedPorts, isNotNull);
      expect(connectedPorts, isNotEmpty);
      expect(res.data?.sourcePorts, equals(connectedPorts));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Must still be held open for Core connection snapshot until cancelToken cancels!
      expect(serverSocketClosed.isCompleted, isFalse);
      cancelToken.cancel('done');
      await serverSocketClosed.future.timeout(const Duration(seconds: 1));

      // Pure helper verification: loopback proxy directive vs DIRECT when connections empty
      final now = DateTime.now();
      final loopbackFallback = resolveEndToEndCoreObservation(
        explicitProxyDirective: 'PROXY 127.0.0.1:7890',
        sourcePorts: {'54321'},
        probeHost: 'ipinfo.io',
        minStart: now.subtract(const Duration(seconds: 2)),
        maxStart: now.add(const Duration(seconds: 2)),
        connections: const [],
        groupNames: const {'Proxy', 'GLOBAL'},
      );
      expect(loopbackFallback.observedInCore, isTrue);

      final tunBypass = resolveEndToEndCoreObservation(
        explicitProxyDirective: 'DIRECT',
        sourcePorts: {'54321'},
        probeHost: 'ipinfo.io',
        minStart: now.subtract(const Duration(seconds: 2)),
        maxStart: now.add(const Duration(seconds: 2)),
        connections: const [],
        groupNames: const {'Proxy', 'GLOBAL'},
      );
      expect(tunBypass.observedInCore, isFalse);

      // Also verify system proxy mode in HealthRunner where upstream closed TCP stream before getConnections() snapshot:
      final base = _FakeProbeEnvironment._defaultHealthySnapshot();
      final sysProxyOnlyEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 4096,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: true,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: false,
          tunFailureCode: null,
          realTunEnable: false,
          proxyStarted: true,
          lastRuntimeProfileId: base.lastRuntimeProfileId,
          groupsSnapshotProfileId: base.groupsSnapshotProfileId,
          allGroups: base.allGroups,
          visibleGroups: base.visibleGroups,
          selectedMap: base.selectedMap,
        ),
        dnsAddresses: [
          InternetAddress('203.0.113.10', type: InternetAddressType.IPv4),
        ],
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'SG',
          observedInCore: false,
        ),
      )
        ..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'off',
          listenerActive: false,
          interfaceState: 'down',
          privilege: 'elevated',
          requestedEnabled: false,
        )
        ..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
        );

      final report = await HealthRunner(sysProxyOnlyEnv).run();
      expect(
          sysProxyOnlyEnv.lastExplicitProxyDirective, 'PROXY 127.0.0.1:7890');
      expect(
        report.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.passed,
      );
      expect(report.verdict.code, 'healthy');

      // A healthy TUN listener does not prove that this process's direct socket
      // is captured. D4 must try DIRECT first, then report a system-proxy
      // fallback as a warning instead of turning it into a healthy result.
      final tunAndSysProxyEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 4096,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: true,
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
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'SG',
          observedInCore: false,
        ),
        e2eObservationByDirective: const {
          'DIRECT': null,
          'PROXY 127.0.0.1:7890': EndToEndProbeObservation(
            exitCountryCode: 'SG',
            observedInCore: false,
          ),
        },
      )
        ..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        )
        ..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
        );
      final tunAndSysProxyReport = await HealthRunner(tunAndSysProxyEnv).run();
      final zhL10n = await AppLocalizations.load(const Locale('zh', 'CN'));
      expect(
        tunAndSysProxyEnv.explicitProxyDirectives,
        ['DIRECT', 'PROXY 127.0.0.1:7890'],
      );
      final fallbackD4 = tunAndSysProxyReport.checkById(
        HealthCheckId.endToEndConnectivity,
      )!;
      expect(fallbackD4.status, HealthStatus.warning);
      expect(fallbackD4.reasonCode, 'tunBypassedSystemProxyOk');
      expect(fallbackD4.localDetail, isNull);
      expect(fallbackD4.exitCountryCode, 'SG');
      expect(tunAndSysProxyReport.verdict.code, 'tunBypassedSystemProxyOk');
      expect(tunAndSysProxyReport.verdict.exitCountryCode, 'SG');
      final localizedFallbackDetail = healthCheckItemDetail(fallbackD4, zhL10n);
      expect(localizedFallbackDetail, isNot(contains('TUN path failed')));
      expect(localizedFallbackDetail, contains('SG'));
      expect(
        healthVerdictHeadline(tunAndSysProxyReport.verdict, zhL10n),
        isNot(equals(zhL10n.healthVerdictWarningsTitle)),
      );

      // When TUN already captured the socket in Core (`lastFailedProbeObservedInCore == true`)
      // and the upstream node failed, D4 must NOT run a redundant second timeout
      // over `PROXY 127.0.0.1:7890`.
      final tunCapturedUpstreamDeadEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 4096,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: true,
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
        e2eObservationByDirective: const {
          'DIRECT': null,
          'PROXY 127.0.0.1:7890': null,
        },
        lastFailedProbeObservedInCore: true,
      )
        ..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        )
        ..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
        );
      final upstreamDeadReport =
          await HealthRunner(tunCapturedUpstreamDeadEnv).run();
      expect(tunCapturedUpstreamDeadEnv.explicitProxyDirectives, ['DIRECT']);
      final upstreamDeadD4 = upstreamDeadReport.checkById(
        HealthCheckId.endToEndConnectivity,
      )!;
      expect(upstreamDeadD4.status, HealthStatus.failed);
      expect(upstreamDeadD4.reasonCode, 'e2eAllSourcesFailed');
      expect(upstreamDeadD4.localDetail, isNull);

      // When DIRECT leaks outside Core (`CN`, observedInCore: false) and System
      // Proxy fallback fails (`null`), report-level exitCountryCode must remain
      // null instead of misattributing the physical ISP country to the node.
      final leakedDirectEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 4096,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: true,
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
        e2eObservationByDirective: const {
          'DIRECT': EndToEndProbeObservation(
            exitCountryCode: 'CN',
            observedInCore: false,
          ),
          'PROXY 127.0.0.1:7890': null,
        },
      )
        ..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: true,
        )
        ..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
        );
      final leakedReport = await HealthRunner(leakedDirectEnv).run();
      final leakedD4 = leakedReport.checkById(
        HealthCheckId.endToEndConnectivity,
      )!;
      expect(leakedD4.status, HealthStatus.warning);
      expect(leakedD4.reasonCode, 'trafficBypassedCore');
      expect(leakedD4.localDetail, isNull);
      expect(leakedReport.verdict.exitCountryCode, isNull);
    });

    test(
        'CR-HC02: unexpected PAC reasonCode maps to PAC copy, missing https= scheme warns partial, and PAC mode detects manual proxy hijack / external PAC',
        () async {
      final l10n = await AppLocalizations.load(const Locale('zh', 'CN'));

      // 1. Residual PAC reasonCode mapping in UI copy
      final residual = evaluateWindowsSystemProxy(
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
      final residualItem = HealthCheckResult(
        id: HealthCheckId.systemProxyTakeover,
        status: residual.status,
        elapsedMs: 1,
        reasonCode: residual.reasonCode,
        localDetail: residual.localDetail,
      );
      expect(
        healthCheckItemDetail(residualItem, l10n),
        contains(l10n.healthDetailSysProxyUnexpectedPac),
      );

      // 2. Per-scheme http= without https= must warn instead of passing
      final httpOnly = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: false,
        expectedPacUrl: null,
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: 'http=127.0.0.1:7890',
        ),
      );
      expect(httpOnly.status, HealthStatus.warning);
      expect(httpOnly.reasonCode, 'systemProxyPartialScheme');
      expect(httpOnly.verifiedProxyDirective, isNull);

      // 3. PAC mode with hijacked manual ProxyServer enabled
      final pacHijacked = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: true,
        expectedPacUrl: 'http://127.0.0.1:7899/pac',
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:10809',
          autoConfigUrl: 'http://127.0.0.1:7899/pac',
        ),
      );
      expect(pacHijacked.status, HealthStatus.warning);
      expect(pacHijacked.reasonCode, 'systemProxyHijacked');

      // 4. External remote PAC URL must not claim PAC 127.0.0.1 or fake loopback directive
      final externalPac = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: true,
        expectedPacUrl: 'https://pac.corp.example/proxy.pac',
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: false,
          autoConfigUrl: 'https://pac.corp.example/proxy.pac',
        ),
      );
      expect(externalPac.status, HealthStatus.passed);
      expect(externalPac.localDetail, isNot(contains('127.0.0.1')));
      expect(externalPac.verifiedProxyDirective, isNull);
    });

    test(
        'CR-HC05: flclashx-serverinfo selects active group, Core realNow wins over stale selectedMap, and cyclic groups fail cleanly',
        () async {
      final base = _FakeProbeEnvironment._defaultHealthySnapshot();
      final encodedGroup = 'base64:${base64.encode(utf8.encode('VIP-Entry'))}';
      final groups = [
        const Group(
          type: GroupType.Selector,
          name: 'OtherGroup',
          now: 'Dead-Node',
          all: [Proxy(name: 'Dead-Node', type: 'Trojan')],
        ),
        const Group(
          type: GroupType.Selector,
          name: 'VIP-Entry',
          now: 'JP-Live-Core-01',
          all: [
            Proxy(name: 'JP-Live-Core-01', type: 'Trojan'),
            Proxy(name: 'JP-Stale-Saved', type: 'Trojan'),
          ],
        ),
      ];
      final serverInfoEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: Profile(
            id: 'prof-1',
            label: 'VIP',
            url: 'https://sub.example.org/s',
            currentGroupName: null,
            providerHeaders: {'flclashx-serverinfo': encodedGroup},
            autoUpdateDuration: const Duration(hours: 24),
            lastUpdateDate: DateTime.utc(2026, 11, 1, 9, 0),
          ),
          profileFileExists: true,
          profileFileBytes: 2048,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: 'prof-1',
          groupsSnapshotProfileId: 'prof-1',
          allGroups: groups,
          visibleGroups: groups,
          selectedMap: const {'VIP-Entry': 'JP-Stale-Saved'},
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(30),
          'VIP-Entry': DelayTestResult(88),
        },
      );
      final report = await HealthRunner(serverInfoEnv).run();
      expect(
        report.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.passed,
      );
      expect(report.verdict.activeNodeName, 'JP-Live-Core-01');

      // Cyclic group loop A -> B -> A must fail cleanly instead of returning group name
      final cyclicGroups = [
        const Group(
          type: GroupType.Selector,
          name: 'LoopA',
          now: 'LoopB',
          all: [Proxy(name: 'LoopB', type: 'Selector')],
        ),
        const Group(
          type: GroupType.Selector,
          name: 'LoopB',
          now: 'LoopA',
          all: [Proxy(name: 'LoopA', type: 'Selector')],
        ),
      ];
      final cyclicEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: 'prof-1',
          currentProfile:
              base.currentProfile!.copyWith(currentGroupName: 'LoopA'),
          profileFileExists: true,
          profileFileBytes: 2048,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: 'prof-1',
          groupsSnapshotProfileId: 'prof-1',
          allGroups: cyclicGroups,
          visibleGroups: cyclicGroups,
          selectedMap: const {'LoopA': 'LoopB', 'LoopB': 'LoopA'},
        ),
      );
      final cyclicReport = await HealthRunner(cyclicEnv).run();
      final cyclicD3 =
          cyclicReport.checkById(HealthCheckId.outboundConnectivity)!;
      expect(cyclicD3.status, HealthStatus.failed);
      expect(cyclicD3.reasonCode, 'outboundGroupLoop');
    });

    test(
        'CR-HC08: HealthCheckController close-and-immediate-reopen awaits dying cancelled run and completes fresh run',
        () async {
      final gate1 = Completer<DelayTestResult>();
      final env = _FakeProbeEnvironment(
        delayCompleterByProxy: {'Proxy': gate1},
      );
      final controller = HealthCheckController(HealthRunner(env));
      addTearDown(controller.dispose);

      // Start Run #1 and let it enter Phase 2 (blocked on gate1)
      final run1Future = controller.startOrAttach();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isRunning, isTrue);

      // Simulate sheet dispose: unawaited cancelActive(), then immediate reopen!
      unawaited(controller.cancelActive());
      env.delayCompleterByProxy = null;

      final run2Future = controller.startOrAttach();
      // Release gate1 after reopen already called startOrAttach()
      gate1.complete(const DelayTestResult(100));

      final run1Report = await run1Future;
      final run2Report = await run2Future;
      expect(run1Report, isNull);
      expect(run2Report, isNotNull);
      expect(run2Report?.verdict.code, 'healthy');
      expect(controller.lastReport?.verdict.code, 'healthy');
    });
  });

  group(
      'Code Review Round 2 regressions (CR2-HC01, CR2-HC03, CR2-HC04, CR2-HC05)',
      () {
    test(
        'CR2-HC01: LoadBalance, Relay, and unprobed URLTest groups (now == "") pass D3 via group delay test while empty groups still fail',
        () async {
      final base = _FakeProbeEnvironment._defaultHealthySnapshot();
      final lbGroups = [
        const Group(
          type: GroupType.Selector,
          name: 'Proxy',
          now: 'LB-Pool',
          all: [Proxy(name: 'LB-Pool', type: 'LoadBalance')],
        ),
        const Group(
          type: GroupType.LoadBalance,
          name: 'LB-Pool',
          now: '',
          all: [
            Proxy(name: 'SG-01', type: 'Trojan'),
            Proxy(name: 'SG-02', type: 'Trojan'),
          ],
        ),
      ];
      final lbEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: 'prof-1',
          currentProfile:
              base.currentProfile!.copyWith(currentGroupName: 'Proxy'),
          profileFileExists: true,
          profileFileBytes: 2048,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: 'prof-1',
          groupsSnapshotProfileId: 'prof-1',
          allGroups: lbGroups,
          visibleGroups: lbGroups,
          selectedMap: const {'Proxy': 'LB-Pool'},
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(25),
          'Proxy': DelayTestResult(72),
        },
      );
      final lbReport = await HealthRunner(lbEnv).run();
      final lbD3 = lbReport.checkById(HealthCheckId.outboundConnectivity)!;
      expect(lbD3.status, HealthStatus.passed);
      expect(lbD3.nodeName, 'LB-Pool');
      expect(lbReport.verdict.code, 'healthy');

      // Unprobed lazy URLTest group (now == "", all non-empty) as top-level group
      final lazyUrlTestGroups = [
        const Group(
          type: GroupType.URLTest,
          name: 'Auto',
          now: '',
          all: [Proxy(name: 'JP-01', type: 'Trojan')],
        ),
      ];
      final lazyEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: 'prof-1',
          currentProfile:
              base.currentProfile!.copyWith(currentGroupName: 'Auto'),
          profileFileExists: true,
          profileFileBytes: 2048,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: 'prof-1',
          groupsSnapshotProfileId: 'prof-1',
          allGroups: lazyUrlTestGroups,
          visibleGroups: lazyUrlTestGroups,
          selectedMap: const {},
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(25),
          'Auto': DelayTestResult(64),
        },
      );
      final lazyReport = await HealthRunner(lazyEnv).run();
      expect(
        lazyReport.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.passed,
      );

      // Empty group (now == "", all: []) must still fail cleanly
      final emptyGroups = [
        const Group(
          type: GroupType.LoadBalance,
          name: 'EmptyLB',
          now: '',
          all: [],
        ),
      ];
      final emptyEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: 'prof-1',
          currentProfile:
              base.currentProfile!.copyWith(currentGroupName: 'EmptyLB'),
          profileFileExists: true,
          profileFileBytes: 2048,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: true,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: 'prof-1',
          groupsSnapshotProfileId: 'prof-1',
          allGroups: emptyGroups,
          visibleGroups: emptyGroups,
          selectedMap: const {},
        ),
      );
      final emptyReport = await HealthRunner(emptyEnv).run();
      expect(
        emptyReport.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.failed,
      );
    });

    test(
        'CR2-HC03: single-channel C2/C3 warnings propagate to C4 partialTakeover, http=-only system proxy warns trafficBypassed in D4, and residual active TUN when desired off warns tunCloseFailed',
        () async {
      final base = _FakeProbeEnvironment._defaultHealthySnapshot();

      // 1. Windows System-Proxy-Only with http=127.0.0.1:7890 (missing https=)
      final httpOnlyEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 4096,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: true,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: false,
          tunFailureCode: null,
          realTunEnable: false,
          proxyStarted: true,
          lastRuntimeProfileId: base.lastRuntimeProfileId,
          groupsSnapshotProfileId: base.groupsSnapshotProfileId,
          allGroups: base.allGroups,
          visibleGroups: base.visibleGroups,
          selectedMap: base.selectedMap,
        ),
        dnsAddresses: [
          InternetAddress('203.0.113.10', type: InternetAddressType.IPv4),
        ],
      )
        ..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 1,
          state: 'off',
          listenerActive: false,
          interfaceState: 'down',
          privilege: 'elevated',
          requestedEnabled: false,
        )
        ..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: 'http=127.0.0.1:7890',
        );

      final httpOnlyReport = await HealthRunner(httpOnlyEnv).run();
      expect(
        httpOnlyReport.checkById(HealthCheckId.systemProxyTakeover)?.status,
        HealthStatus.warning,
      );
      expect(
        httpOnlyReport.checkById(HealthCheckId.trafficTakeover)?.status,
        HealthStatus.warning,
      );
      expect(
        httpOnlyReport.checkById(HealthCheckId.trafficTakeover)?.reasonCode,
        'partialTakeover',
      );
      expect(
        httpOnlyReport.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.warning,
      );
      expect(
        httpOnlyReport
            .checkById(HealthCheckId.endToEndConnectivity)
            ?.reasonCode,
        'trafficBypassedCore',
      );
      expect(httpOnlyReport.verdict.code, 'trafficBypassed');
      expect(
        httpOnlyReport.verdict.primaryAction,
        HealthAction.openNetworkSettings,
      );

      // 2. Windows tunDesiredEnabled == false while TUN adapter is still stuck 'on' (with systemProxy disabled)
      final stuckTunEnv = _FakeProbeEnvironment(
        configSnapshot: HealthConfigSnapshot(
          currentProfileId: base.currentProfileId,
          currentProfile: base.currentProfile,
          profileFileExists: true,
          profileFileBytes: 4096,
          mode: Mode.rule,
          mixedPort: 7890,
          testUrl: base.testUrl,
          resolveGroupTestUrl: base.resolveGroupTestUrl,
          systemProxyEnabled: false,
          pacEnabled: false,
          pacUrl: null,
          tunDesiredEnabled: false,
          tunFailureCode: null,
          realTunEnable: true,
          proxyStarted: true,
          lastRuntimeProfileId: base.lastRuntimeProfileId,
          groupsSnapshotProfileId: base.groupsSnapshotProfileId,
          allGroups: base.allGroups,
          visibleGroups: base.visibleGroups,
          selectedMap: base.selectedMap,
        ),
      )..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 2,
          state: 'on',
          listenerActive: true,
          interfaceState: 'up',
          privilege: 'elevated',
          requestedEnabled: false,
        );

      final stuckTunReport = await HealthRunner(stuckTunEnv).run();
      expect(
        stuckTunReport.checkById(HealthCheckId.tunTakeover)?.status,
        HealthStatus.warning,
      );
      expect(
        stuckTunReport.checkById(HealthCheckId.tunTakeover)?.reasonCode,
        'tunCloseFailed',
      );
      expect(
        stuckTunReport.checkById(HealthCheckId.trafficTakeover)?.status,
        HealthStatus.warning,
      );
      expect(
        stuckTunReport.checkById(HealthCheckId.trafficTakeover)?.reasonCode,
        'partialTakeover',
      );
    });

    test(
        'CR2-HC04: Request.checkIpWithHost fires active-tunnel snapshot after request/TLS ClientHello reaches upstream (ignoring CONNECT 200 header)',
        () async {
      // 1. Plain HTTP with Connection: close -> fires second snapshot after server parsed request and before checkIpWithHost returns
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var serverParsedRequest = false;
      var clientCheckReturned = false;
      final plainCallbacksAfterRequest = <bool>[];

      server.listen((socket) {
        var responded = false;
        socket.listen((chunk) {
          if (!responded &&
              utf8.decode(chunk, allowMalformed: true).contains('\r\n\r\n')) {
            responded = true;
            serverParsedRequest = true;
            const body = '{"ip":"9.9.9.9","country":"JP"}';
            const rawResponse = 'HTTP/1.1 200 OK\r\n'
                'Content-Type: application/json\r\n'
                'Content-Length: ${body.length}\r\n'
                'Connection: close\r\n'
                '\r\n'
                '$body';
            socket.add(utf8.encode(rawResponse));
            unawaited(socket.flush().then((_) => socket.close()));
          }
        });
      });

      final probeReq = Request(
        ipInfoSources: {
          'http://127.0.0.1:${server.port}/json': IpInfo.fromIpInfoIoJson,
        },
      );
      final cancelToken = CancelToken();
      final res = await probeReq.checkIpWithHost(
        cancelToken: cancelToken,
        keepAliveHold: const Duration(milliseconds: 500),
        forceHoldSocket: true,
        proxyResolver: (_) => 'DIRECT',
        onSocketConnected: (ports) {
          if (ports.isNotEmpty) {
            plainCallbacksAfterRequest
                .add(serverParsedRequest && !clientCheckReturned);
          }
        },
      );
      clientCheckReturned = true;
      cancelToken.cancel('done');
      expect(res.data?.ipInfo.countryCode, 'JP');
      expect(plainCallbacksAfterRequest, equals([false, true]));

      // 2. Proxied HTTPS CONNECT tunnel -> must NOT fire on CONNECT 200 header, and MUST fire once post-CONNECT tunnel bytes arrive after TLS ClientHello
      final proxyServer =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxyServer.close);

      var connectParsed = false;
      var tlsClientHelloSeen = false;
      var callbackCountAfterConnectBeforeHello = 0;
      var callbackFiredAfterTlsClientHello = false;
      var totalConnectCallbacks = 0;

      proxyServer.listen((socket) {
        var stage = 0;
        socket.listen((chunk) {
          if (stage == 0 &&
              utf8.decode(chunk, allowMalformed: true).contains('\r\n\r\n')) {
            stage = 1;
            connectParsed = true;
            socket.add(
              utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
            );
          } else if (stage == 1 && chunk.isNotEmpty) {
            // Client sent TLS ClientHello (0x16 ...) through established CONNECT tunnel
            stage = 2;
            tlsClientHelloSeen = true;
            // Reply with a minimal alert/bytes to trigger inbound post-CONNECT payload hook, then close
            socket.add(const <int>[0x15, 0x03, 0x03, 0x00, 0x02, 0x02, 0x28]);
            unawaited(socket.flush().then((_) => socket.close()));
          }
        });
      });

      final httpsProxyReq = Request(
        ipInfoSources: {
          'https://example.invalid/json': IpInfo.fromIpInfoIoJson,
        },
      );
      await httpsProxyReq.checkIpWithHost(
        connectTimeout: const Duration(seconds: 2),
        keepAliveHold: const Duration(milliseconds: 200),
        forceHoldSocket: true,
        proxyResolver: (_) => 'PROXY 127.0.0.1:${proxyServer.port}',
        onSocketConnected: (_) {
          totalConnectCallbacks++;
          if (connectParsed && !tlsClientHelloSeen) {
            callbackCountAfterConnectBeforeHello++;
          }
          if (connectParsed && tlsClientHelloSeen) {
            callbackFiredAfterTlsClientHello = true;
          }
        },
      );

      expect(totalConnectCallbacks, 2);
      expect(callbackCountAfterConnectBeforeHello, 0);
      expect(callbackFiredAfterTlsClientHello, isTrue);
    });

    test(
        'CR2-HC05: PAC manual proxy hijack strips credentials and never renders empty () when ProxyServer is blank',
        () async {
      final l10n = await AppLocalizations.load(const Locale('zh', 'CN'));

      final blankManual = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: true,
        expectedPacUrl: 'http://127.0.0.1:7899/pac',
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '',
          autoConfigUrl: 'http://127.0.0.1:7899/pac',
        ),
      );
      expect(blankManual.status, HealthStatus.warning);
      expect(blankManual.localDetail, isNull);
      final blankDetail = healthCheckItemDetail(
        HealthCheckResult(
          id: HealthCheckId.systemProxyTakeover,
          status: blankManual.status,
          elapsedMs: 1,
          reasonCode: blankManual.reasonCode,
          localDetail: blankManual.localDetail,
        ),
        l10n,
      );
      expect(blankDetail, isNot(contains('()')));

      final credManual = evaluateWindowsSystemProxy(
        expectedEnabled: true,
        expectedPort: 7890,
        expectedPacEnabled: true,
        expectedPacUrl: 'http://127.0.0.1:7899/pac',
        snapshot: const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: 'http://secretUser:secretPass@127.0.0.1:10809',
          autoConfigUrl: 'http://127.0.0.1:7899/pac',
        ),
      );
      expect(credManual.status, HealthStatus.warning);
      expect(credManual.localDetail, '127.0.0.1:10809');
      expect(credManual.localDetail, isNot(contains('secretUser')));
      expect(credManual.localDetail, isNot(contains('secretPass')));
    });
  });

  group('Outbound false-negative resilience & E2E cross-validation', () {
    test('transient testFailed on D3 recovers on immediate retry of primary URL',
        () async {
      final env = _FakeProbeEnvironment(
        onTestProxyDelay: (proxyName, testUrl, callIndex) {
          if (proxyName == 'DIRECT') return const DelayTestResult(52);
          if (callIndex == 0) {
            return const DelayTestResult(-1, reason: 'testFailed');
          }
          return const DelayTestResult(357);
        },
      );
      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;
      expect(d3.status, HealthStatus.passed);
      expect(d3.reasonCode, 'ok');
      expect(d3.delayMs, 357);
      expect(report.verdict.code, 'healthy');
      expect(env.recordedOutboundTestUrls, [
        'https://www.gstatic.com/generate_204',
        'https://www.gstatic.com/generate_204',
      ]);
    });

    test('primary URL testFailed twice falls back to secondary 204 URL and passes',
        () async {
      final env = _FakeProbeEnvironment(
        onTestProxyDelay: (proxyName, testUrl, callIndex) {
          if (proxyName == 'DIRECT') return const DelayTestResult(48);
          if (testUrl == 'https://cp.cloudflare.com/generate_204') {
            return const DelayTestResult(412);
          }
          return const DelayTestResult(-1, reason: 'testFailed');
        },
      );
      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;
      expect(d3.status, HealthStatus.passed);
      expect(d3.reasonCode, 'ok');
      expect(d3.delayMs, 412);
      expect(report.verdict.code, 'healthy');
      expect(env.recordedOutboundTestUrls, [
        'https://www.gstatic.com/generate_204',
        'https://www.gstatic.com/generate_204',
        'https://cp.cloudflare.com/generate_204',
      ]);
    });

    test('D3 latency threshold aligns with kLatencyFastMaxMs (2000 ms)',
        () async {
      for (final ms in [357, 2000]) {
        final fastEnv = _FakeProbeEnvironment(
          delayResults: {
            'DIRECT': const DelayTestResult(45),
            'Proxy': DelayTestResult(ms),
          },
        );
        final report = await HealthRunner(fastEnv).run();
        final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;
        expect(d3.status, HealthStatus.passed);
        expect(d3.reasonCode, 'ok');
        expect(report.verdict.code, 'healthy');
      }

      final slowEnv = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(45),
          'Proxy': DelayTestResult(2001),
        },
      );
      final slowReport = await HealthRunner(slowEnv).run();
      final slowD3 = slowReport.checkById(HealthCheckId.outboundConnectivity)!;
      expect(slowD3.status, HealthStatus.warning);
      expect(slowD3.reasonCode, 'outboundVerySlow');
      expect(slowReport.verdict.code, 'healthyWithWarnings');
    });

    test(
        'when all D3 probes fail but D1 passes, D4 runs and real proxy E2E rescues verdict from outboundNodeFailed',
        () async {
      final env = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(62),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'US',
          observedInCore: true,
          matchedLeafProxy: 'HK-VIP-SecretNode-99',
        ),
      );
      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;
      final d4 = report.checkById(HealthCheckId.endToEndConnectivity)!;
      expect(d4.status, HealthStatus.passed);
      expect(d4.reasonCode, 'ok');
      expect(d3.status, HealthStatus.warning);
      expect(d3.reasonCode, 'outboundProbeFallbackOk');
      expect(report.verdict.code, 'healthyWithWarnings');
      expect(report.verdict.code, isNot('outboundNodeFailed'));
      expect(report.verdict.exitCountryCode, 'US');
      expect(report.verdict.activeNodeName, 'HK-VIP-SecretNode-99');
    });

    test(
        'guards against false rescue when D4 routes DIRECT by rule or bypasses Core',
        () async {
      final directRuleEnv = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(60),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'CN',
          observedInCore: true,
          matchedLeafProxy: 'DIRECT',
        ),
      );
      final directRuleReport = await HealthRunner(directRuleEnv).run();
      expect(
        directRuleReport.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.failed,
      );
      expect(directRuleReport.verdict.code, 'outboundNodeFailed');

      final bypassedEnv = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(60),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'CN',
          observedInCore: false,
        ),
      );
      final bypassedReport = await HealthRunner(bypassedEnv).run();
      expect(
        bypassedReport.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.failed,
      );
      expect(bypassedReport.verdict.code, 'outboundNodeFailed');
    });

    test(
        'computeHealthVerdict returns healthyWithWarnings when raw D3 failed but D4 E2E ok',
        () {
      final checks = [
        const HealthCheckResult(
          id: HealthCheckId.profileSelected,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'ok',
        ),
        const HealthCheckResult(
          id: HealthCheckId.subscriptionHealth,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'ok',
        ),
        const HealthCheckResult(
          id: HealthCheckId.runtimeConfigLoaded,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'ok',
        ),
        const HealthCheckResult(
          id: HealthCheckId.coreResponsive,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'ok',
        ),
        const HealthCheckResult(
          id: HealthCheckId.proxyStarted,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'ok',
        ),
        const HealthCheckResult(
          id: HealthCheckId.tunTakeover,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'tunReadyElevated',
        ),
        const HealthCheckResult(
          id: HealthCheckId.systemProxyTakeover,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'systemProxyDisabledByPreference',
        ),
        const HealthCheckResult(
          id: HealthCheckId.trafficTakeover,
          status: HealthStatus.passed,
          elapsedMs: 1,
          reasonCode: 'takeoverTun',
        ),
        const HealthCheckResult(
          id: HealthCheckId.directConnectivity,
          status: HealthStatus.passed,
          elapsedMs: 40,
          reasonCode: 'ok',
          delayMs: 40,
        ),
        const HealthCheckResult(
          id: HealthCheckId.dnsResolution,
          status: HealthStatus.passed,
          elapsedMs: 5,
          reasonCode: 'dnsFakeIpActive',
        ),
        const HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.failed,
          elapsedMs: 481,
          reasonCode: 'outboundFailed',
          nodeName: 'Node-A',
        ),
        const HealthCheckResult(
          id: HealthCheckId.endToEndConnectivity,
          status: HealthStatus.passed,
          elapsedMs: 320,
          reasonCode: 'ok',
          exitCountryCode: 'US',
          nodeName: 'Node-A',
        ),
      ];
      final verdict = computeHealthVerdict(
        checks,
        mode: Mode.rule,
        activeNodeName: 'Node-A',
        directDelayMs: 40,
        exitCountryCode: 'US',
      );
      expect(verdict.code, 'healthyWithWarnings');
      expect(verdict.severity, HealthVerdictSeverity.warning);
      expect(verdict.primaryAction, isNull);
    });
  });

  group('CR-HC-R3: Outbound false-negative Code Review remediations', () {
    HealthConfigSnapshot snapshotWithGroups({
      required List<Group> groups,
      required String currentGroupName,
      required Map<String, String> selectedMap,
      String testUrl = 'https://cp.cloudflare.com/generate_204',
      bool tunDesiredEnabled = true,
      bool realTunEnable = true,
      bool systemProxyEnabled = false,
    }) {
      final profile = Profile(
        id: 'prof-cr',
        label: 'Test Profile',
        url: 'https://sub.example.invalid/token',
        currentGroupName: currentGroupName,
        lastUpdateDate: DateTime.utc(2026, 11, 1, 9, 30, 0),
        autoUpdateDuration: const Duration(hours: 24),
        selectedMap: selectedMap,
      );
      return HealthConfigSnapshot(
        currentProfileId: profile.id,
        currentProfile: profile,
        profileFileExists: true,
        profileFileBytes: 4096,
        mode: Mode.rule,
        mixedPort: 7890,
        testUrl: testUrl,
        resolveGroupTestUrl: (url) =>
            (url != null && url.isNotEmpty) ? url : testUrl,
        systemProxyEnabled: systemProxyEnabled,
        pacEnabled: false,
        pacUrl: null,
        tunDesiredEnabled: tunDesiredEnabled,
        tunFailureCode: null,
        realTunEnable: realTunEnable,
        proxyStarted: true,
        lastRuntimeProfileId: profile.id,
        groupsSnapshotProfileId: profile.id,
        allGroups: groups,
        visibleGroups: groups,
        selectedMap: profile.selectedMap,
      );
    }

    test(
        'P1-#1: DIRECT E2E observation under tunBypassedSystemProxyOk never rescues failed D3 outbound node',
        () async {
      final env = _FakeProbeEnvironment(
        configSnapshot: snapshotWithGroups(
          currentGroupName: 'Proxy',
          selectedMap: const {'Proxy': 'HK-VIP-SecretNode-99'},
          systemProxyEnabled: true,
          groups: const [
            Group(
              type: GroupType.Selector,
              name: 'Proxy',
              now: 'HK-VIP-SecretNode-99',
              all: [Proxy(name: 'HK-VIP-SecretNode-99', type: 'Trojan')],
            ),
          ],
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(55),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservationByDirective: const {
          'DIRECT': EndToEndProbeObservation(
            exitCountryCode: 'CN',
            observedInCore: false,
          ),
          'http://127.0.0.1:7890': EndToEndProbeObservation(
            exitCountryCode: 'CN',
            observedInCore: true,
            matchedLeafProxy: 'DIRECT',
          ),
        },
      )..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
          autoConfigUrl: null,
        );

      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;
      final d4 = report.checkById(HealthCheckId.endToEndConnectivity)!;

      expect(d4.status, HealthStatus.warning);
      expect(d4.reasonCode, 'tunBypassedSystemProxyOk');
      expect(d3.status, HealthStatus.failed);
      expect(report.verdict.code, 'outboundNodeFailed');
      expect(report.verdict.severity, HealthVerdictSeverity.failed);
    });

    test(
        'P1-#1: unattributed loopback fallback (matchedLeafProxy == null) preserves null nodeName and never rescues failed D3',
        () async {
      final env = _FakeProbeEnvironment(
        configSnapshot: snapshotWithGroups(
          currentGroupName: 'Proxy',
          selectedMap: const {'Proxy': 'HK-VIP-SecretNode-99'},
          tunDesiredEnabled: false,
          realTunEnable: false,
          systemProxyEnabled: true,
          groups: const [
            Group(
              type: GroupType.Selector,
              name: 'Proxy',
              now: 'HK-VIP-SecretNode-99',
              all: [Proxy(name: 'HK-VIP-SecretNode-99', type: 'Trojan')],
            ),
          ],
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(45),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'US',
          observedInCore: false,
          matchedLeafProxy: null,
        ),
      )
        ..tunStatus = const TunStatus(
          instanceId: 'core-1',
          revision: 3,
          state: 'off',
          listenerActive: false,
          interfaceState: 'absent',
          privilege: 'user',
          requestedEnabled: false,
        )
        ..windowsSystemProxy = const WindowsSystemProxySnapshot(
          proxyEnabled: true,
          proxyServer: '127.0.0.1:7890',
          autoConfigUrl: null,
        );

      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;
      final d4 = report.checkById(HealthCheckId.endToEndConnectivity)!;

      expect(d4.status, HealthStatus.passed);
      expect(d4.reasonCode, 'ok');
      expect(d4.nodeName, isNull);
      expect(d3.status, HealthStatus.failed);
      expect(report.verdict.code, 'outboundNodeFailed');
      expect(report.verdict.severity, HealthVerdictSeverity.failed);
    });

    test(
        'P1-#2: pinned Selector group must NOT be rescued when a different split-group node served E2E',
        () async {
      final env = _FakeProbeEnvironment(
        configSnapshot: snapshotWithGroups(
          currentGroupName: 'Proxy',
          selectedMap: const {'Proxy': 'HK-Pinned-01'},
          groups: const [
            Group(
              type: GroupType.Selector,
              name: 'Proxy',
              now: 'HK-Pinned-01',
              all: [
                Proxy(name: 'HK-Pinned-01', type: 'Trojan'),
                Proxy(name: 'SG-Alt-02', type: 'Trojan'),
              ],
            ),
            Group(
              type: GroupType.Selector,
              name: 'Streaming',
              now: 'US-Split-03',
              all: [Proxy(name: 'US-Split-03', type: 'Trojan')],
            ),
          ],
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(48),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'US',
          observedInCore: true,
          matchedLeafProxy: 'US-Split-03',
        ),
      );

      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;

      expect(d3.status, HealthStatus.failed);
      expect(report.verdict.code, 'outboundNodeFailed');
      expect(report.verdict.activeNodeName, 'HK-Pinned-01');
    });

    test(
        'P1-#2: dynamic URLTest group failover E2E rescues failed D3 and updates attributed nodeName',
        () async {
      final env = _FakeProbeEnvironment(
        configSnapshot: snapshotWithGroups(
          currentGroupName: 'Proxy',
          selectedMap: const {'Proxy': 'Auto'},
          groups: const [
            Group(
              type: GroupType.Selector,
              name: 'Proxy',
              now: 'Auto',
              all: [Proxy(name: 'Auto', type: 'URLTest')],
            ),
            Group(
              type: GroupType.URLTest,
              name: 'Auto',
              now: 'HK-Down-01',
              all: [
                Proxy(name: 'HK-Down-01', type: 'Trojan'),
                Proxy(name: 'SG-Failover-02', type: 'Trojan'),
              ],
            ),
          ],
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(48),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'SG',
          observedInCore: true,
          matchedLeafProxy: 'SG-Failover-02',
        ),
      );

      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;

      expect(d3.status, HealthStatus.warning);
      expect(d3.reasonCode, 'outboundProbeFallbackOk');
      expect(d3.nodeName, 'SG-Failover-02');
      expect(report.verdict.code, 'healthyWithWarnings');
      expect(report.verdict.activeNodeName, 'SG-Failover-02');
      expect(report.verdict.exitCountryCode, 'SG');
    });

    test(
        'P2-#3: onProgress never emits transient outboundConnectivity=failed while live D4 is still running',
        () async {
      final env = _FakeProbeEnvironment(
        delayResults: const {
          'DIRECT': DelayTestResult(50),
          'Proxy': DelayTestResult(-1, reason: 'testFailed'),
        },
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'HK',
          observedInCore: true,
          matchedLeafProxy: 'HK-VIP-SecretNode-99',
        ),
      )..e2eCompleter = Completer<EndToEndProbeObservation?>();

      final outboundStatusTimeline = <HealthStatus>[];
      final runFuture = HealthRunner(env).run(
        onProgress: (snapshot) {
          final d3 = snapshot[HealthCheckId.outboundConnectivity];
          if (d3 != null) {
            outboundStatusTimeline.add(d3.status);
          }
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        outboundStatusTimeline,
        isNot(contains(HealthStatus.failed)),
      );
      expect(outboundStatusTimeline.last, HealthStatus.running);

      env.e2eCompleter!.complete(
        const EndToEndProbeObservation(
          exitCountryCode: 'HK',
          observedInCore: true,
          matchedLeafProxy: 'HK-VIP-SecretNode-99',
        ),
      );

      final report = await runFuture;
      expect(
        outboundStatusTimeline,
        isNot(contains(HealthStatus.failed)),
      );
      expect(
        report.checkById(HealthCheckId.outboundConnectivity)!.status,
        HealthStatus.warning,
      );
    });

    test(
        'P2-#4: fallback probe prefers non-Cloudflare endpoint when primary testUrl is Cloudflare',
        () async {
      final env = _FakeProbeEnvironment(
        configSnapshot: snapshotWithGroups(
          currentGroupName: 'Proxy',
          selectedMap: const {'Proxy': 'HK-VIP-SecretNode-99'},
          testUrl: 'https://cp.cloudflare.com/generate_204',
          groups: const [
            Group(
              type: GroupType.Selector,
              name: 'Proxy',
              now: 'HK-VIP-SecretNode-99',
              all: [Proxy(name: 'HK-VIP-SecretNode-99', type: 'Trojan')],
            ),
          ],
        ),
        delayResults: const {
          'DIRECT': DelayTestResult(40),
        },
        onTestProxyDelay: (proxyName, testUrl, callIndex) {
          if (proxyName == 'DIRECT') return const DelayTestResult(40);
          if (testUrl.contains('cloudflare.com')) {
            return const DelayTestResult(-1, reason: 'testFailed');
          }
          return const DelayTestResult(165);
        },
      );

      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;

      expect(d3.status, HealthStatus.passed);
      expect(d3.delayMs, 165);
      expect(env.recordedOutboundTestUrls, hasLength(3));
      expect(
        Uri.parse(env.recordedOutboundTestUrls.last).host,
        isNot('cp.cloudflare.com'),
      );
    });

    test(
        'P2-#4: D3 retry loop clamps timeouts and skips remaining retries within 6500ms budget',
        () async {
      final env = _FakeProbeEnvironment(
        delayResults: const {'DIRECT': DelayTestResult(30)},
        e2eObservation: const EndToEndProbeObservation(
          exitCountryCode: 'HK',
          observedInCore: true,
          matchedLeafProxy: 'HK-VIP-SecretNode-99',
        ),
      )..onTestProxyDelayWithTimeout =
          (proxyName, testUrl, callIndex, timeout) async {
        if (proxyName == 'DIRECT') return const DelayTestResult(30);
        if (callIndex == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 3000));
          return const DelayTestResult(-1, reason: 'timeout');
        }
        await Future<void>.delayed(const Duration(milliseconds: 2600));
        return const DelayTestResult(-1, reason: 'timeout');
      };

      final report = await HealthRunner(env).run();
      final d3 = report.checkById(HealthCheckId.outboundConnectivity)!;

      expect(d3.status, HealthStatus.warning);
      // Primary + at most 1 retry because elapsed (~5600ms) leaves < 1200ms budget
      expect(env.recordedOutboundTestUrls.length, lessThanOrEqualTo(2));
      expect(env.recordedOutboundTimeouts.length, 2);
      expect(
        env.recordedOutboundTimeouts[1].inMilliseconds,
        lessThanOrEqualTo(3500),
      );
    });

    test(
        'P1-#1 & P1-#2: computeHealthVerdict refuses E2E rescue when leaf is DIRECT, null, or mismatched',
        () {
      List<HealthCheckResult> checksForE2e({
        required String reasonCode,
        String? e2eNode,
        HealthStatus e2eStatus = HealthStatus.passed,
      }) =>
          [
            const HealthCheckResult(
              id: HealthCheckId.directConnectivity,
              status: HealthStatus.passed,
              elapsedMs: 40,
              reasonCode: 'ok',
              delayMs: 40,
            ),
            const HealthCheckResult(
              id: HealthCheckId.outboundConnectivity,
              status: HealthStatus.failed,
              elapsedMs: 480,
              reasonCode: 'outboundFailed',
              nodeName: 'Node-A',
            ),
            HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: e2eStatus,
              elapsedMs: 300,
              reasonCode: reasonCode,
              nodeName: e2eNode,
            ),
          ];

      for (final unverified in [
        checksForE2e(
          reasonCode: 'tunBypassedSystemProxyOk',
          e2eNode: 'DIRECT',
          e2eStatus: HealthStatus.warning,
        ),
        checksForE2e(reasonCode: 'ok', e2eNode: null),
        checksForE2e(reasonCode: 'ok', e2eNode: 'Node-B'),
      ]) {
        final verdict = computeHealthVerdict(
          unverified,
          mode: Mode.rule,
          activeNodeName: 'Node-A',
        );
        expect(verdict.code, 'outboundNodeFailed');
        expect(verdict.severity, HealthVerdictSeverity.failed);
      }
    });
  });
}
