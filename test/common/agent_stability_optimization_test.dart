import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flclashx/application.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/health/health_verdict.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

class _FakeHealthEnv implements HealthProbeEnvironment {
  _FakeHealthEnv({
    required this.snapshot,
    this.delayResults = const {
      'DIRECT': DelayTestResult(30),
      'Proxy': DelayTestResult(120),
    },
    this.e2eObservation,
  });

  final HealthConfigSnapshot snapshot;
  final Map<String, DelayTestResult> delayResults;
  final EndToEndProbeObservation? e2eObservation;

  @override
  DateTime now() => DateTime.utc(2026, 11, 15, 14, 0, 0);

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
  Future<WindowsSystemProxySnapshot?> readWindowsSystemProxy() async => null;

  @override
  Future<DelayTestResult> testProxyDelay({
    required String proxyName,
    required String testUrl,
    required String requestId,
    required Duration timeout,
  }) async =>
      delayResults[proxyName] ?? const DelayTestResult(-1, reason: 'testFailed');

  @override
  Future<void> cancelProxyDelay(String requestId) async {}

  @override
  Future<List<InternetAddress>> lookupHost(String host) async =>
      [InternetAddress('198.18.0.10')];

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async =>
      e2eObservation;
}

class _AdaptiveFakeHealthEnv extends _FakeHealthEnv
    implements AdaptiveEndToEndProbeEnvironment {
  _AdaptiveFakeHealthEnv({
    required super.snapshot,
    super.delayResults,
    required this.onProbeWithBudget,
  });

  final Future<EndToEndProbeObservation?> Function({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
    required Duration connectTimeout,
    required Duration attemptTimeout,
  }) onProbeWithBudget;

  bool legacyProbeCalled = false;

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async {
    legacyProbeCalled = true;
    return super.probeEndToEnd(
      cancelToken: cancelToken,
      explicitProxyDirective: explicitProxyDirective,
    );
  }

  @override
  Future<EndToEndProbeObservation?> probeEndToEndWithBudget({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
    required Duration connectTimeout,
    required Duration attemptTimeout,
  }) =>
      onProbeWithBudget(
        cancelToken: cancelToken,
        explicitProxyDirective: explicitProxyDirective,
        connectTimeout: connectTimeout,
        attemptTimeout: attemptTimeout,
      );
}

HealthConfigSnapshot _buildSnapshot() {
  final profile = Profile(
    id: 'prof-stability',
    label: 'Stability Test',
    url: 'https://sub.example.invalid/token',
    currentGroupName: 'Proxy',
    lastUpdateDate: DateTime.utc(2026, 11, 15, 12, 0, 0),
    autoUpdateDuration: const Duration(hours: 24),
    subscriptionInfo: const SubscriptionInfo(
      upload: 1024,
      download: 2048,
      total: 1024 * 1024 * 1024,
      expire: 0,
    ),
    selectedMap: const {'Proxy': 'HK-01'},
  );
  const groups = [
    Group(
      type: GroupType.Selector,
      name: 'Proxy',
      now: 'HK-01',
      all: [Proxy(name: 'HK-01', type: 'Trojan')],
    ),
  ];
  return HealthConfigSnapshot(
    currentProfileId: profile.id,
    currentProfile: profile,
    profileFileExists: true,
    profileFileBytes: 1024,
    mode: Mode.rule,
    mixedPort: 7890,
    testUrl: 'https://www.gstatic.com/generate_204',
    resolveGroupTestUrl: (u) =>
        (u != null && u.isNotEmpty) ? u : 'https://www.gstatic.com/generate_204',
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
    visibleGroups: groups,
    selectedMap: profile.selectedMap,
  );
}

List<HealthCheckResult> _baseHealthyChecks({
  required HealthCheckResult d3,
  required HealthCheckResult d4,
  HealthCheckResult? d2,
}) =>
    [
      const HealthCheckResult(
        id: HealthCheckId.profileSelected,
        status: HealthStatus.passed,
        elapsedMs: 1,
        reasonCode: 'ok',
      ),
      const HealthCheckResult(
        id: HealthCheckId.subscriptionHealth,
        status: HealthStatus.passed,
        elapsedMs: 0,
        reasonCode: 'ok',
      ),
      const HealthCheckResult(
        id: HealthCheckId.runtimeConfigLoaded,
        status: HealthStatus.passed,
        elapsedMs: 0,
        reasonCode: 'ok',
      ),
      const HealthCheckResult(
        id: HealthCheckId.coreResponsive,
        status: HealthStatus.passed,
        elapsedMs: 10,
        reasonCode: 'ok',
      ),
      const HealthCheckResult(
        id: HealthCheckId.proxyStarted,
        status: HealthStatus.passed,
        elapsedMs: 0,
        reasonCode: 'ok',
      ),
      const HealthCheckResult(
        id: HealthCheckId.tunTakeover,
        status: HealthStatus.passed,
        elapsedMs: 15,
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
        elapsedMs: 0,
        reasonCode: 'takeoverTun',
      ),
      const HealthCheckResult(
        id: HealthCheckId.directConnectivity,
        status: HealthStatus.passed,
        elapsedMs: 25,
        reasonCode: 'ok',
        delayMs: 25,
      ),
      d2 ??
          const HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.passed,
            elapsedMs: 4,
            reasonCode: 'dnsFakeIpActive',
          ),
      d3,
      d4,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('fcx_agent_stability_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Fix 2A: Virtual/VPN/container interface isolation', () {
    test('selectPreferredPhysicalLocalIp returns empty when only virtual/WSL/VMnet/VPN/container adapters are UP', () {
      final result = selectPreferredPhysicalLocalIp([
        (name: 'vEthernet (WSL)', addresses: [InternetAddress('192.168.224.1')]),
        (name: 'vEthernet (Hyper-V Default Switch)', addresses: [InternetAddress('172.25.0.1')]),
        (name: 'VMware Network Adapter VMnet1', addresses: [InternetAddress('192.168.56.1')]),
        (name: 'VMnet8', addresses: [InternetAddress('192.168.188.1')]),
        (name: 'VirtualBox Host-Only Network', addresses: [InternetAddress('192.168.99.1')]),
        (name: 'vboxnet0', addresses: [InternetAddress('192.168.57.1')]),
        (name: 'Tailscale', addresses: [InternetAddress('100.64.0.1')]),
        (name: 'ZeroTier One [123456]', addresses: [InternetAddress('10.147.20.1')]),
        (name: 'WireGuard Tunnel', addresses: [InternetAddress('10.0.0.2')]),
        (name: 'TAP-Windows Adapter V9', addresses: [InternetAddress('10.8.0.2')]),
        (name: 'Loopback Pseudo-Interface 1', addresses: [InternetAddress('127.0.0.2')]),
        (name: 'docker0', addresses: [InternetAddress('172.17.0.1')]),
        (name: 'podman-machine-default', addresses: [InternetAddress('10.88.0.1')]),
      ]);
      expect(result, isEmpty);
    });

    test('selectPreferredPhysicalLocalIp preserves real physical adapters alongside virtual adapters', () {
      for (final adapter in [
        (name: 'Ethernet', ip: '192.168.10.11'),
        (name: 'WLAN', ip: '192.168.10.12'),
        (name: 'Wi-Fi', ip: '192.168.10.13'),
        (name: '以太网', ip: '192.168.10.14'),
        (name: 'usb0', ip: '192.168.42.129'),
      ]) {
        final selected = selectPreferredPhysicalLocalIp([
          (name: 'vEthernet (WSL)', addresses: [InternetAddress('192.168.224.1')]),
          (name: 'VMnet8', addresses: [InternetAddress('192.168.188.1')]),
          (name: adapter.name, addresses: [InternetAddress(adapter.ip)]),
        ]);
        expect(selected, adapter.ip, reason: 'Adapter ${adapter.name} must not be filtered');
      }
    });
  });

  group('Fix 2B: NetworkChangeCoordinator offline detection & slow DHCP backoff', () {
    test('does not reset when IP stays empty under WSL/VMnet UP, marks offline, and resets on recovery even with identical LAN IP', () async {
      var resets = 0;
      var closes = 0;
      var currentIp = '192.168.1.100';
      final coordinator = NetworkChangeCoordinator(
        isWindows: true,
        readLocalIp: () async => currentIp,
        resetConnections: () => resets++,
        closeConnections: () => closes++,
        probeDelays: const [Duration.zero, Duration.zero],
      );

      // Baseline on Home Wi-Fi + WSL
      await coordinator.handleConnectivityChanged([
        ConnectivityResult.wifi,
        ConnectivityResult.ethernet,
      ]);
      expect(resets, 0);

      // Wi-Fi drops; WSL keeps reporting [ConnectivityResult.ethernet], but physical IP is now ''
      currentIp = '';
      await coordinator.handleConnectivityChanged([ConnectivityResult.ethernet]);
      expect(resets, 0, reason: 'Must never reset connections while still offline (ip.isEmpty)');
      expect(closes, 0);

      // User reconnects to Office Wi-Fi which assigns the SAME subnet IP 192.168.1.100
      currentIp = '192.168.1.100';
      await coordinator.handleConnectivityChanged([
        ConnectivityResult.wifi,
        ConnectivityResult.ethernet,
      ]);
      expect(resets, 1, reason: 'Must recognize recovery from _wasOffline even with same IP');
      coordinator.dispose();
    });

    test('default probeDelays covers slow Wi-Fi DHCP [250ms, 1000ms, 2500ms, 4500ms, 7000ms] while fast steady-state returns immediately', () async {
      final coordinator = NetworkChangeCoordinator(
        isWindows: true,
        readLocalIp: () async => '192.168.1.50',
        resetConnections: () {},
        closeConnections: () {},
      );
      expect(
        coordinator.probeDelays,
        const [
          Duration(milliseconds: 250),
          Duration(milliseconds: 1000),
          Duration(milliseconds: 2500),
          Duration(milliseconds: 4500),
          Duration(milliseconds: 7000),
        ],
      );

      final watch = Stopwatch()..start();
      await coordinator.handleConnectivityChanged([ConnectivityResult.wifi]);
      await coordinator.handleConnectivityChanged([ConnectivityResult.wifi, ConnectivityResult.vpn]);
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(1500));
      coordinator.dispose();
    });
  });

  group('Fix 3: Health verdict when D3 passes and D4 fails', () {
    test('computeHealthVerdict returns healthyWithWarnings instead of endToEndFailed when D3 passed and D4 timed out / failed (not rejected by rule)', () {
      final verdict = computeHealthVerdict(
        _baseHealthyChecks(
          d3: const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.passed,
            elapsedMs: 140,
            reasonCode: 'ok',
            nodeName: 'HK-01',
            delayMs: 140,
          ),
          d4: const HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.timeout,
            elapsedMs: 13400,
            reasonCode: 'e2eTimeout',
            action: HealthAction.openProxies,
          ),
        ),
        mode: Mode.rule,
        activeNodeName: 'HK-01',
        outboundDelayMs: 140,
        directDelayMs: 25,
      );

      expect(verdict.code, 'healthyWithWarnings');
      expect(verdict.severity, HealthVerdictSeverity.warning);
      expect(verdict.primaryCheckId, HealthCheckId.endToEndConnectivity);
      expect(verdict.primaryAction, HealthAction.openProxies);
      expect(verdict.activeNodeName, 'HK-01');
      expect(verdict.outboundDelayMs, 140);
      expect(verdict.directDelayMs, 25);
    });

    test('computeHealthVerdict keeps endToEndFailed when e2eRejectedByRule or D3 did not prove proxy outbound', () {
      final rejectedVerdict = computeHealthVerdict(
        _baseHealthyChecks(
          d3: const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.passed,
            elapsedMs: 120,
            reasonCode: 'ok',
            nodeName: 'HK-01',
            delayMs: 120,
          ),
          d4: const HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.failed,
            elapsedMs: 300,
            reasonCode: 'e2eRejectedByRule',
            action: HealthAction.openProxies,
          ),
        ),
        activeNodeName: 'HK-01',
        outboundDelayMs: 120,
      );
      expect(rejectedVerdict.code, 'endToEndFailed');
      expect(rejectedVerdict.severity, HealthVerdictSeverity.failed);

      for (final unverifiedD3 in const [
        HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.warning,
          elapsedMs: 10,
          reasonCode: 'outboundSelectedDirect',
          nodeName: 'DIRECT',
        ),
        HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.warning,
          elapsedMs: 10,
          reasonCode: 'coreDelayBusy',
          nodeName: 'HK-01',
        ),
        HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.skipped,
          elapsedMs: 0,
          reasonCode: 'directModeActive',
        ),
      ]) {
        final verdict = computeHealthVerdict(
          _baseHealthyChecks(
            d3: unverifiedD3,
            d4: const HealthCheckResult(
              id: HealthCheckId.endToEndConnectivity,
              status: HealthStatus.failed,
              elapsedMs: 4000,
              reasonCode: 'e2eAllSourcesFailed',
              action: HealthAction.openProxies,
            ),
          ),
          activeNodeName: unverifiedD3.nodeName,
        );
        expect(verdict.code, 'endToEndFailed');
        expect(verdict.severity, HealthVerdictSeverity.failed);
      }
    });

    test('HealthRunner end-to-end failure with passing D3 produces healthyWithWarnings verdict', () async {
      final env = _FakeHealthEnv(
        snapshot: _buildSnapshot(),
        delayResults: const {
          'DIRECT': DelayTestResult(30),
          'Proxy': DelayTestResult(120),
        },
        e2eObservation: null,
      );
      final report = await HealthRunner(env).run();
      expect(
        report.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.passed,
      );
      expect(
        report.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.failed,
      );
      expect(report.verdict.code, 'healthyWithWarnings');
      expect(report.verdict.severity, HealthVerdictSeverity.warning);
      expect(
        report.verdict.primaryCheckId,
        HealthCheckId.endToEndConnectivity,
      );
    });
  });

  group('Fix 3: Request receiveTimeout respects attemptTimeout', () {
    test('DefaultHealthProbeEnvironment + Request succeeds when server responds after 3300ms under adaptive budget', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final slowServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(slowServer.close);

        slowServer.listen((socket) {
          socket.listen((chunk) {
            if (utf8.decode(chunk, allowMalformed: true).contains('\r\n\r\n')) {
              Timer(const Duration(milliseconds: 3300), () {
                const body = '{"ip":"203.0.113.8","country":"JP"}';
                const resp = 'HTTP/1.1 200 OK\r\n'
                    'Content-Type: application/json\r\n'
                    'Content-Length: ${body.length}\r\n'
                    'Connection: close\r\n\r\n'
                    '$body';
                try {
                  socket.add(utf8.encode(resp));
                  unawaited(socket.flush().then((_) => socket.close()));
                } catch (_) {}
              });
            }
          });
        });

        final customReq = Request(
          ipInfoSources: {
            'http://127.0.0.1:${slowServer.port}/ip': IpInfo.fromIpInfoIoJson,
          },
        );
        final res = await customReq.checkIpWithHost(
          connectTimeout: const Duration(milliseconds: 5000),
          attemptTimeout: const Duration(milliseconds: 5500),
          keepAliveHold: Duration.zero,
          proxyResolver: (_) => 'DIRECT',
        );
        expect(res.isError, isFalse);
        expect(res.data?.ipInfo.countryCode, 'JP');
      }, _RealHttpOverrides());
    });

    test('DefaultHealthProbeEnvironment keeps 2800/3200ms default in probeEndToEnd while probeEndToEndWithBudget honors custom budget', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final slowServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(slowServer.close);

        slowServer.listen((socket) {
          socket.listen((chunk) {
            if (utf8.decode(chunk, allowMalformed: true).contains('\r\n\r\n')) {
              Timer(const Duration(milliseconds: 3400), () {
                const body = '{"ip":"203.0.113.9","country":"JP"}';
                const resp = 'HTTP/1.1 200 OK\r\n'
                    'Content-Type: application/json\r\n'
                    'Content-Length: ${body.length}\r\n'
                    'Connection: close\r\n\r\n'
                    '$body';
                try {
                  socket.add(utf8.encode(resp));
                  unawaited(socket.flush().then((_) => socket.close()));
                } catch (_) {}
              });
            }
          });
        });

        final prevAppState =
            globalState.isAppStateInitialized ? globalState.appState : null;
        addTearDown(() {
          if (prevAppState != null) globalState.appState = prevAppState;
        });
        globalState.appState = AppState(
          isInit: true,
          viewSize: Size.zero,
          requests: FixedList(10),
          version: 0,
          logs: FixedList(10),
          traffics: FixedList(10),
          totalTraffic: Traffic(),
        );

        final customReq = Request(
          ipInfoSources: {
            'http://127.0.0.1:${slowServer.port}/ip': IpInfo.fromIpInfoIoJson,
          },
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final env = container.read(
          Provider((ref) => DefaultHealthProbeEnvironment(ref, probeRequest: customReq)),
        );

        final watch = Stopwatch()..start();
        final legacyObs = await env.probeEndToEnd(
          cancelToken: HealthCancellationToken(),
          explicitProxyDirective: 'DIRECT',
        );
        watch.stop();
        expect(legacyObs, isNull);
        expect(watch.elapsedMilliseconds, lessThan(4800));

        final adaptiveObs = await env.probeEndToEndWithBudget(
          cancelToken: HealthCancellationToken(),
          explicitProxyDirective: 'DIRECT',
          connectTimeout: const Duration(milliseconds: 5000),
          attemptTimeout: const Duration(milliseconds: 6000),
        );
        expect(adaptiveObs, isNotNull);
        expect(adaptiveObs?.exitCountryCode, 'JP');
        expect(adaptiveObs?.observedInCore, isFalse);
      }, _RealHttpOverrides());
    });
  });

  group('Fix 2A extended: isVirtualOrTunnelInterfaceName unit checks', () {
    test('matches all virtual, hypervisor, VPN, container and legacy tunnel interface keywords case-insensitively', () {
      for (final name in const [
        'vEthernet (WSL)',
        'WSL',
        'HYPER-V Default Switch',
        'VMware Network Adapter VMnet1',
        'VMnet8',
        'vboxnet0',
        'VirtualBox Host-Only Ethernet Adapter',
        'Tailscale',
        'ZeroTier One [a1b2c3]',
        'WireGuard Tunnel',
        'TAP-Windows Adapter V9',
        'Loopback Pseudo-Interface 1',
        'docker0',
        'podman-machine-default',
        '  FlClash TUN  ',
        'mihomo',
        'wintun0',
        'Clash',
        'utun4',
        'tun0',
        'tun12',
      ]) {
        expect(
          isVirtualOrTunnelInterfaceName(name),
          isTrue,
          reason: '$name should be classified as virtual/tunnel',
        );
      }
      expect(isVirtualOrTunnelInterfaceName('   '), isFalse);
    });

    test('preserves real physical, USB, and cellular interface names', () {
      for (final name in const [
        'Ethernet',
        'Ethernet 2',
        'WLAN',
        'Wi-Fi',
        '以太网',
        '本地连接',
        'usb0',
        'eth0',
        'en0',
        'pdp_ip0',
        'rmnet_data0',
      ]) {
        expect(
          isVirtualOrTunnelInterfaceName(name),
          isFalse,
          reason: '$name must NOT be filtered as virtual/tunnel',
        );
      }
    });
  });

  group('Fix 2B extended: onRecovered, seedInitialBaseline, and DetectionState refresh', () {
    test('onRecovered fires asynchronously on offline and WSL-only recovery and transport changes, never on baseline/offline/noise', () async {
      var resets = 0;
      var recoveredEvents = 0;
      final completed = Completer<void>();
      var currentIp = '192.168.10.20';

      final coordinator = NetworkChangeCoordinator(
        isWindows: true,
        readLocalIp: () async => currentIp,
        resetConnections: () => resets++,
        closeConnections: () {},
        onRecovered: () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          recoveredEvents++;
          if (recoveredEvents == 2 && !completed.isCompleted) {
            completed.complete();
          }
        },
        probeDelays: const [Duration.zero, Duration.zero],
      );

      await coordinator.seedInitialBaseline([ConnectivityResult.wifi]);
      expect(resets, 0);
      expect(recoveredEvents, 0);

      // VPN noise does not trigger recovery
      await coordinator.handleConnectivityChanged([
        ConnectivityResult.wifi,
        ConnectivityResult.vpn,
      ]);
      expect(recoveredEvents, 0);

      // Full disconnect ([none]) -> does not trigger recovery
      currentIp = '';
      await coordinator.handleConnectivityChanged([ConnectivityResult.none]);
      expect(resets, 0);
      expect(recoveredEvents, 0);

      // Reconnect with same IP -> resets + invokes onRecovered (#1)
      currentIp = '192.168.10.20';
      await coordinator.handleConnectivityChanged([ConnectivityResult.wifi]);
      expect(resets, 1);
      expect(recoveredEvents, 1);

      // Drop to WSL-only ethernet (ip.isEmpty) -> still offline, no recovery
      currentIp = '';
      await coordinator.handleConnectivityChanged([ConnectivityResult.ethernet]);
      expect(resets, 1);
      expect(recoveredEvents, 1);

      // Recover via cellular/Wi-Fi with new IP -> resets + invokes onRecovered (#2)
      currentIp = '10.20.30.40';
      await coordinator.handleConnectivityChanged([ConnectivityResult.mobile]);
      await completed.future.timeout(const Duration(seconds: 2));
      expect(resets, 2);
      expect(recoveredEvents, 2);

      coordinator.dispose();
    });

    test('seedInitialBaseline offline start marks offline so first real IP triggers reset and onRecovered', () async {
      var resets = 0;
      var recovered = 0;
      var currentIp = '';

      final coordinator = NetworkChangeCoordinator(
        isWindows: true,
        readLocalIp: () async => currentIp,
        resetConnections: () => resets++,
        closeConnections: () {},
        onRecovered: () => recovered++,
        probeDelays: const [Duration.zero],
      );

      await coordinator.seedInitialBaseline([ConnectivityResult.ethernet]);
      expect(resets, 0);
      expect(recovered, 0);

      currentIp = '192.168.2.15';
      await coordinator.handleConnectivityChanged([
        ConnectivityResult.wifi,
        ConnectivityResult.ethernet,
      ]);
      expect(resets, 1);
      expect(recovered, 1);
      coordinator.dispose();
    });

    test('DetectionState notifyRoutingChanged + startCheck supersedes an in-flight stale probe', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        var requestCount = 0;
        final firstRequestReceived = Completer<void>();
        final heldSockets = <Socket>[];
        addTearDown(() async {
          for (final s in heldSockets) {
            try {
              await s.close();
            } catch (_) {}
          }
        });

        server.listen((socket) {
          socket.listen((chunk) {
            if (!utf8.decode(chunk, allowMalformed: true).contains('\r\n\r\n')) {
              return;
            }
            requestCount++;
            if (requestCount == 1) {
              heldSockets.add(socket);
              if (!firstRequestReceived.isCompleted) {
                firstRequestReceived.complete();
              }
              return;
            }
            const body = '{"ip":"198.51.100.2","country":"US"}';
            const resp = 'HTTP/1.1 200 OK\r\n'
                'Content-Type: application/json\r\n'
                'Content-Length: ${body.length}\r\n'
                'Connection: close\r\n\r\n'
                '$body';
            try {
              socket.add(utf8.encode(resp));
              unawaited(socket.flush().then((_) => socket.close()));
            } catch (_) {}
          });
        });

        final prevAppState =
            globalState.isAppStateInitialized ? globalState.appState : null;
        final prevConfig =
            globalState.isConfigInitialized ? globalState.config : null;
        addTearDown(() {
          if (prevAppState != null) globalState.appState = prevAppState;
          if (prevConfig != null) globalState.config = prevConfig;
        });

        globalState.appState = AppState(
          isInit: true,
          viewSize: Size.zero,
          requests: FixedList(10),
          version: 0,
          logs: FixedList(10),
          traffics: FixedList(10),
          totalTraffic: Traffic(),
        );
        globalState.config = const Config(themeProps: defaultThemeProps);

        final customReq = Request(
          ipInfoSources: {
            'http://127.0.0.1:${server.port}/ip': IpInfo.fromIpInfoIoJson,
          },
        );
        final detection = DetectionState.forTesting(customReq)
          ..startCheck();
        await firstRequestReceived.future.timeout(const Duration(seconds: 2));

        // Matches ApplicationState.onRecovered callback wiring:
        void simulateRecoveryCallback() {
          detection
            ..notifyRoutingChanged()
            ..startCheck();
        }

        simulateRecoveryCallback();

        final completer = Completer<IpInfo?>();
        void listener() {
          final v = detection.state.value;
          if (!v.isTesting && v.ipInfo != null && !completer.isCompleted) {
            completer.complete(v.ipInfo);
          }
        }

        detection.state.addListener(listener);
        listener();
        addTearDown(() => detection.state.removeListener(listener));

        final result = await completer.future.timeout(const Duration(seconds: 5));
        expect(result?.countryCode, 'US');
        expect(requestCount, 2);
      }, _RealHttpOverrides());
    });
  });

  group('Fix 3 extended: Adaptive E2E budget, HealthRunner wiring, cancellation, and DNS precedence', () {
    test('computeEndToEndProbeBudget computes bounded adaptive connect/attempt/overall timeouts', () {
      final defaultBudget = computeEndToEndProbeBudget();
      expect(defaultBudget.connectTimeout, const Duration(milliseconds: 4500));
      expect(defaultBudget.attemptTimeout, const Duration(milliseconds: 5700));
      expect(defaultBudget.overallTimeout, const Duration(milliseconds: 13400));

      final fastBudget = computeEndToEndProbeBudget(
        outboundResult: const HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.passed,
          elapsedMs: 140,
          reasonCode: 'ok',
          delayMs: 140,
        ),
      );
      expect(fastBudget.connectTimeout, const Duration(milliseconds: 4500));
      expect(fastBudget.attemptTimeout, const Duration(milliseconds: 5700));
      expect(fastBudget.overallTimeout, const Duration(milliseconds: 13400));

      final slowBudget = computeEndToEndProbeBudget(
        outboundResult: const HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.passed,
          elapsedMs: 3900,
          reasonCode: 'ok',
          delayMs: 4200,
        ),
      );
      expect(slowBudget.connectTimeout, const Duration(milliseconds: 5700));
      expect(slowBudget.attemptTimeout, const Duration(milliseconds: 6900));
      expect(slowBudget.overallTimeout, const Duration(milliseconds: 15800));

      final clampedBudget = computeEndToEndProbeBudget(
        outboundResult: const HealthCheckResult(
          id: HealthCheckId.outboundConnectivity,
          status: HealthStatus.warning,
          elapsedMs: 6500,
          reasonCode: 'highOutboundDelay',
          delayMs: 5000,
        ),
      );
      expect(clampedBudget.connectTimeout, const Duration(milliseconds: 7500));
      expect(clampedBudget.attemptTimeout, const Duration(milliseconds: 8700));
      expect(clampedBudget.overallTimeout, const Duration(milliseconds: 19400));
    });

    test('HealthRunner passes adaptive budget to AdaptiveEndToEndProbeEnvironment instead of legacy probeEndToEnd', () async {
      Duration? capturedConnect;
      Duration? capturedAttempt;
      final env = _AdaptiveFakeHealthEnv(
        snapshot: _buildSnapshot(),
        delayResults: const {
          'DIRECT': DelayTestResult(30),
          'Proxy': DelayTestResult(4200),
        },
        onProbeWithBudget: ({
          required cancelToken,
          required explicitProxyDirective,
          required connectTimeout,
          required attemptTimeout,
        }) async {
          capturedConnect = connectTimeout;
          capturedAttempt = attemptTimeout;
          return const EndToEndProbeObservation(
            exitCountryCode: 'JP',
            observedInCore: true,
            matchedLeafProxy: 'HK-01',
          );
        },
      );

      final report = await HealthRunner(env).run();
      expect(env.legacyProbeCalled, isFalse);
      expect(capturedConnect, const Duration(milliseconds: 5700));
      expect(capturedAttempt, const Duration(milliseconds: 6900));
      expect(
        report.checkById(HealthCheckId.endToEndConnectivity)?.status,
        HealthStatus.passed,
      );
      expect(
        report.checkById(HealthCheckId.outboundConnectivity)?.status,
        HealthStatus.warning,
      );
      expect(report.verdict.code, 'healthyWithWarnings');
      expect(
        report.verdict.primaryCheckId,
        HealthCheckId.outboundConnectivity,
      );
    });

    test('HealthRunner cancels hanging adaptive E2E probe immediately without waiting overallTimeout', () async {
      final token = HealthCancellationToken();
      final started = Completer<void>();
      final env = _AdaptiveFakeHealthEnv(
        snapshot: _buildSnapshot(),
        delayResults: const {
          'DIRECT': DelayTestResult(30),
          'Proxy': DelayTestResult(120),
        },
        onProbeWithBudget: ({
          required cancelToken,
          required explicitProxyDirective,
          required connectTimeout,
          required attemptTimeout,
        }) async {
          if (!started.isCompleted) started.complete();
          await Future<void>.delayed(const Duration(seconds: 20));
          return null;
        },
      );

      final watch = Stopwatch()..start();
      final future = HealthRunner(env).run(cancelToken: token);
      final assertion = expectLater(future, throwsStateError);
      await started.future.timeout(const Duration(seconds: 2));
      await token.cancel();

      await assertion;
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('computeHealthVerdict lets D2 dnsResolution failure take precedence over healthyWithWarnings', () {
      final verdict = computeHealthVerdict(
        _baseHealthyChecks(
          d2: const HealthCheckResult(
            id: HealthCheckId.dnsResolution,
            status: HealthStatus.failed,
            elapsedMs: 120,
            reasonCode: 'dnsResolutionFailed',
            action: HealthAction.openDnsSettings,
          ),
          d3: const HealthCheckResult(
            id: HealthCheckId.outboundConnectivity,
            status: HealthStatus.passed,
            elapsedMs: 140,
            reasonCode: 'ok',
            nodeName: 'HK-01',
            delayMs: 140,
          ),
          d4: const HealthCheckResult(
            id: HealthCheckId.endToEndConnectivity,
            status: HealthStatus.timeout,
            elapsedMs: 13400,
            reasonCode: 'e2eTimeout',
            action: HealthAction.openProxies,
          ),
        ),
        activeNodeName: 'HK-01',
        outboundDelayMs: 140,
      );

      expect(verdict.code, 'dnsFailed');
      expect(verdict.severity, HealthVerdictSeverity.failed);
      expect(verdict.primaryCheckId, HealthCheckId.dnsResolution);
    });
  });
}
