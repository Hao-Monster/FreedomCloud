import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/health/health_environment.dart';
import 'package:flclashx/common/health/health_models.dart';
import 'package:flclashx/common/health/health_runner.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_system_proxy_probe.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubProbeEnvironment implements HealthProbeEnvironment {
  _StubProbeEnvironment({required this.testUrl});

  final String testUrl;
  final List<String> queriedDnsHosts = <String>[];
  final List<String> testedOutboundUrls = <String>[];

  @override
  DateTime now() => DateTime.utc(2026, 11, 14, 10, 30);

  @override
  String get platform => 'windows';

  @override
  String get appVersion => '2.0.0-test';

  @override
  Future<HealthConfigSnapshot> readConfigSnapshot() async {
    const profile = Profile(
      id: 'p1',
      label: 'Test',
      url: 'https://panel.example.com/sub',
      autoUpdateDuration: Duration(hours: 24),
    );
    const groups = <Group>[
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
    return HealthConfigSnapshot(
      currentProfileId: profile.id,
      currentProfile: profile,
      profileFileExists: true,
      profileFileBytes: 1024,
      mode: Mode.rule,
      mixedPort: 7890,
      testUrl: testUrl,
      resolveGroupTestUrl: (url) =>
          (url != null && url.isNotEmpty) ? url : testUrl,
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
      selectedMap: const {'Proxy': 'HK-01', 'GLOBAL': 'Proxy'},
    );
  }

  @override
  Future<CoreLivenessObservation> checkCoreLiveness() async =>
      const CoreLivenessObservation(
        isInit: true,
        memoryBytes: 64 * 1024 * 1024,
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
  }) async {
    if (proxyName == 'DIRECT') {
      return const DelayTestResult(25);
    }
    testedOutboundUrls.add(testUrl);
    if (testUrl == 'https://cp.cloudflare.com/generate_204') {
      return const DelayTestResult(88);
    }
    return const DelayTestResult(-1, reason: 'testFailed');
  }

  @override
  Future<void> cancelProxyDelay(String requestId) async {}

  @override
  Future<List<InternetAddress>> lookupHost(String host) async {
    queriedDnsHosts.add(host);
    return <InternetAddress>[InternetAddress('198.18.0.10')];
  }

  @override
  Future<EndToEndProbeObservation?> probeEndToEnd({
    required HealthCancellationToken cancelToken,
    required String? explicitProxyDirective,
  }) async =>
      const EndToEndProbeObservation(
        exitCountryCode: 'US',
        observedInCore: true,
        matchedLeafProxy: 'HK-01',
      );
}

void main() {
  test(
      'U01: defaultTestUrl and fresh Config/AppSettingProps use https://www.google.com/generate_204',
      () {
    expect(defaultTestUrl, 'https://www.google.com/generate_204');
    const settings = AppSettingProps();
    const config = Config(themeProps: defaultThemeProps);
    expect(settings.testUrl, 'https://www.google.com/generate_204');
    expect(settings.defaultTestUrlGoogleMigrated, isTrue);
    expect(config.appSetting.testUrl, 'https://www.google.com/generate_204');
    expect(config.appSetting.defaultTestUrlGoogleMigrated, isTrue);
    expect(
      config.appSetting.toJson()['defaultTestUrlGoogleMigrated'],
      isTrue,
    );
  });

  test(
      'U02: Config.compatibleFromJson migrates legacy/empty testUrl once while preserving custom and post-migration edits',
      () {
    final legacyDefault = Config.compatibleFromJson(<String, Object?>{
      'appSetting': <String, Object?>{
        'testUrl': 'https://www.gstatic.com/generate_204',
      },
    });
    expect(
      legacyDefault.appSetting.testUrl,
      'https://www.google.com/generate_204',
    );
    expect(legacyDefault.appSetting.defaultTestUrlGoogleMigrated, isTrue);
    expect(
      legacyDefault.appSetting.toJson()['defaultTestUrlGoogleMigrated'],
      isTrue,
    );

    final blankTestUrl = Config.compatibleFromJson(<String, Object?>{
      'appSetting': <String, Object?>{'testUrl': '   '},
    });
    expect(
      blankTestUrl.appSetting.testUrl,
      'https://www.google.com/generate_204',
    );
    expect(blankTestUrl.appSetting.defaultTestUrlGoogleMigrated, isTrue);

    final corruptTestUrl = Config.compatibleFromJson(<String, Object?>{
      'appSetting': <String, Object?>{'testUrl': 123},
    });
    expect(
      corruptTestUrl.appSetting.testUrl,
      'https://www.google.com/generate_204',
    );
    expect(corruptTestUrl.appSetting.defaultTestUrlGoogleMigrated, isTrue);

    final customPreserved = Config.compatibleFromJson(<String, Object?>{
      'appSetting': <String, Object?>{
        'testUrl': 'https://cp.cloudflare.com/generate_204',
      },
    });
    expect(
      customPreserved.appSetting.testUrl,
      'https://cp.cloudflare.com/generate_204',
    );
    expect(customPreserved.appSetting.defaultTestUrlGoogleMigrated, isTrue);

    final editedBackAfterMigration = Config.compatibleFromJson(
      jsonDecode(
        jsonEncode(
          legacyDefault.copyWith.appSetting(
            testUrl: 'https://www.gstatic.com/generate_204',
          ),
        ),
      ) as Map<String, dynamic>,
    );
    expect(
      editedBackAfterMigration.appSetting.testUrl,
      'https://www.gstatic.com/generate_204',
    );
  });

  test(
      'U03: injectManagedSmartProxyGroups falls back to https://www.google.com/generate_204 when defaultTestUrl is empty',
      () {
    final rawConfig = <String, dynamic>{
      'proxies': [
        {
          'name': 'HK-01',
          'type': 'vless',
          'server': 'hk.example.com',
          'port': 443,
          'uuid': 'u-1',
        },
        {
          'name': 'JP-01',
          'type': 'vless',
          'server': 'jp.example.com',
          'port': 443,
          'uuid': 'u-2',
        },
      ],
      'proxy-groups': [
        {
          'name': 'Proxy',
          'type': 'select',
          'proxies': ['HK-01', 'JP-01'],
        },
      ],
    };

    injectManagedSmartProxyGroups(rawConfig, defaultTestUrl: '   ');

    final groups = (rawConfig['proxy-groups'] as List).cast<Map>();
    final smartUrlTest = groups.firstWhere(
      (g) => g['name'] == managedSmartGroupNameFor('Proxy'),
    );
    expect(smartUrlTest['url'], 'https://www.google.com/generate_204');
  });

  test(
      'U04: HealthRunner D2 TUN DNS fallback resolves www.google.com for IP testUrl and D3 falls back to non-Google probe',
      () async {
    final env = _StubProbeEnvironment(
      testUrl: 'http://1.1.1.1/generate_204',
    );
    final report = await HealthRunner(env).run();
    final d2 = report.checkById(HealthCheckId.dnsResolution)!;
    expect(d2.status, HealthStatus.passed);
    expect(env.queriedDnsHosts, ['www.google.com']);

    final googleEnv = _StubProbeEnvironment(
      testUrl: 'https://www.google.com/generate_204',
    );
    final googleReport = await HealthRunner(googleEnv).run();
    final d3 = googleReport.checkById(HealthCheckId.outboundConnectivity)!;
    expect(d3.status, HealthStatus.passed);
    expect(googleEnv.testedOutboundUrls, [
      'https://www.google.com/generate_204',
      'https://www.google.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ]);
  });
}
