import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/file_logger.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

class _StabilityTestState extends GlobalState {
  _StabilityTestState(this.configsById) : super.forTesting();

  final Map<String, Map<String, dynamic>> configsById;

  @override
  Future<Map<String, dynamic>> getProfileConfig(String profileId) async {
    final source = configsById[profileId]!;
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> handleEvaluate(Map<String, dynamic> raw) async =>
      raw;
}

class _RecordingTransport extends ClashHandlerInterface {
  int setupCalls = 0;
  int changeProxyCalls = 0;
  String setupResult = '';
  String changeProxyResult = '';
  bool initState = true;

  @override
  Future<bool> get isInit async => initState;

  @override
  Future<String> setupConfig(SetupParams params) async {
    setupCalls++;
    return setupResult;
  }

  @override
  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    changeProxyCalls++;
    return changeProxyResult;
  }

  @override
  Future<String> updateConfig(
    UpdateParams updateParams, {
    String? controllerAddress,
    bool? controllerEnabled,
  }) async =>
      '';

  @override
  Future<bool> destroy() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  final originalPaths = PathProviderPlatform.instance;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('fcx-stability-tdd-');
    PathProviderPlatform.instance = _TestPaths(tempRoot.path);
    await File(p.join(tempRoot.path, geoSiteFileName))
        .writeAsBytes(const [1, 2, 3, 4]);
    await File(p.join(tempRoot.path, mmdbFileName))
        .writeAsBytes(const [1, 2, 3, 4]);
  });

  tearDownAll(() async {
    await fileLogger.dispose();
    PathProviderPlatform.instance = originalPaths;
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('Item 1: Fake-IP persistence & missing-Fake-IP sniffer recovery', () {
    test(
        'patchRawConfig enables profile.store-fake-ip and injects missing-Fake-IP sniffer when dns.enhanced-mode == fake-ip',
        () async {
      const profile = Profile(
        id: 'fake-ip-default',
        label: 'FakeIpDefault',
        autoUpdateDuration: Duration.zero,
      );
      final config = Config(
        themeProps: defaultThemeProps,
        profiles: const [profile],
        currentProfileId: profile.id,
      );
      final state = _StabilityTestState({
        profile.id: {
          'proxies': [
            {'name': 'n1', 'type': 'ss', 'server': 'a.example', 'port': 443},
          ],
          'proxy-groups': [
            {
              'name': 'PROXY',
              'type': 'select',
              'proxies': ['n1', 'DIRECT'],
            },
          ],
          'dns': {
            'enable': true,
            'enhanced-mode': 'fake-ip',
            'nameserver': ['223.5.5.5'],
          },
          'rules': ['MATCH,PROXY'],
        },
      })
        ..config = config;
      globalState.config = config;

      final patched = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: profile,
      );

      final profileMap = patched['profile'] as Map;
      expect(profileMap['store-selected'], isFalse);
      expect(profileMap['store-fake-ip'], isTrue);
      expect(
        (patched['dns'] as Map)['fake-ip-filter'],
        contains('+.msftconnecttest.com'),
      );

      final sniffer = patched['sniffer'] as Map;
      expect(sniffer['enable'], isTrue);
      expect(sniffer['force-dns-mapping'], isFalse);
      expect(sniffer['parse-pure-ip'], isTrue);
      expect(sniffer['override-destination'], isTrue);
      expect(
        sniffer['skip-dst-address'],
        containsAll(<String>[
          '127.0.0.0/8',
          '10.0.0.0/8',
          '100.64.0.0/10',
          '172.16.0.0/12',
          '192.168.0.0/16',
        ]),
      );
      final sniff = sniffer['sniff'] as Map;
      expect((sniff['TLS'] as Map)['ports'], ['443', '8443']);
      expect((sniff['HTTP'] as Map)['ports'], ['80', '8080-8880']);
      expect((sniff['QUIC'] as Map)['ports'], ['443', '8443']);
    });

    test(
        'patchRawConfig preserves explicit store-fake-ip=false, custom sniffer, and skips sniffer when not fake-ip',
        () async {
      const explicitProfile = Profile(
        id: 'explicit-sniffer',
        label: 'ExplicitSniffer',
        autoUpdateDuration: Duration.zero,
      );
      const normalDnsProfile = Profile(
        id: 'normal-dns',
        label: 'NormalDns',
        autoUpdateDuration: Duration.zero,
      );
      final config = Config(
        themeProps: defaultThemeProps,
        profiles: const [explicitProfile, normalDnsProfile],
        currentProfileId: explicitProfile.id,
      );
      final state = _StabilityTestState({
        explicitProfile.id: {
          'profile': {'store-fake-ip': false},
          'sniffer': {
            'enable': false,
            'sniff': {
              'TLS': {
                'ports': [443],
              },
            },
          },
          'dns': {
            'enable': true,
            'enhanced-mode': 'fake-ip',
            'nameserver': ['223.5.5.5'],
          },
          'rules': ['MATCH,DIRECT'],
        },
        normalDnsProfile.id: {
          'dns': {
            'enable': true,
            'enhanced-mode': 'normal',
            'nameserver': ['223.5.5.5'],
          },
          'rules': ['MATCH,DIRECT'],
        },
      })
        ..config = config;
      globalState.config = config;

      final patchedExplicit = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: explicitProfile,
      );
      expect((patchedExplicit['profile'] as Map)['store-fake-ip'], isFalse);
      expect((patchedExplicit['sniffer'] as Map)['enable'], isFalse);
      expect(
        (((patchedExplicit['sniffer'] as Map)['sniff'] as Map)['TLS']
            as Map)['ports'],
        ['443'],
      );

      final patchedNormalDns = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: normalDnsProfile,
      );
      expect(patchedNormalDns['sniffer'], isNull);
    });
  });

  group('Item 3: Safe TUN MTU 1500 & one-shot desktop gvisor -> mixed migration',
      () {
    test(
        'patchRawConfig defaults tun.mtu to 1500 when absent and preserves explicit subscription mtu',
        () async {
      const defaultMtuProfile = Profile(
        id: 'default-mtu',
        label: 'DefaultMtu',
        autoUpdateDuration: Duration.zero,
      );
      const customMtuProfile = Profile(
        id: 'custom-mtu',
        label: 'CustomMtu',
        autoUpdateDuration: Duration.zero,
      );
      final config = Config(
        themeProps: defaultThemeProps,
        profiles: const [defaultMtuProfile, customMtuProfile],
        currentProfileId: defaultMtuProfile.id,
      );
      final state = _StabilityTestState({
        defaultMtuProfile.id: {
          'rules': ['MATCH,DIRECT'],
        },
        customMtuProfile.id: {
          'tun': {'mtu': 1400},
          'rules': ['MATCH,DIRECT'],
        },
      })
        ..config = config;
      globalState.config = config;

      final patchedDefault = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: defaultMtuProfile,
      );
      expect((patchedDefault['tun'] as Map)['mtu'], 1500);

      final patchedCustom = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: customMtuProfile,
      );
      expect((patchedCustom['tun'] as Map)['mtu'], 1400);
    });

    test(
        'Config.compatibleFromJson migrates legacy desktop gvisor to mixed once while respecting subsequent manual gvisor and mobile',
        () {
      final legacyUnmigratedJson = <String, Object?>{
        'themeProps': defaultThemeProps.toJson(),
        'appSetting': <String, Object?>{
          'dashboardDefaultV2Migrated': true,
        },
        'patchClashConfig': <String, Object?>{
          'tun': <String, Object?>{
            'enable': true,
            'stack': 'gvisor',
          },
        },
      };

      // 1. Desktop legacy config without tunDesktopStackMixedMigrated -> migrated once to mixed
      final desktopMigrated = Config.compatibleFromJson(
        legacyUnmigratedJson,
        isDesktop: true,
      );
      expect(desktopMigrated.patchClashConfig.tun.stack, TunStack.mixed);
      expect(
        desktopMigrated.appSetting.tunDesktopStackMixedMigrated,
        isTrue,
      );

      // 2. User manually switches back to gvisor after migration -> preserved!
      final manualGvisor = desktopMigrated.copyWith(
        patchClashConfig: desktopMigrated.patchClashConfig.copyWith.tun(
          stack: TunStack.gvisor,
        ),
      );
      final reloadedManualGvisor = Config.compatibleFromJson(
        jsonDecode(jsonEncode(manualGvisor.toJson())) as Map<String, Object?>,
        isDesktop: true,
      );
      expect(reloadedManualGvisor.patchClashConfig.tun.stack, TunStack.gvisor);
      expect(
        reloadedManualGvisor.appSetting.tunDesktopStackMixedMigrated,
        isTrue,
      );

      // 3. Mobile (isDesktop: false) never rewrites gvisor
      final mobileLoaded = Config.compatibleFromJson(
        legacyUnmigratedJson,
        isDesktop: false,
      );
      expect(mobileLoaded.patchClashConfig.tun.stack, TunStack.gvisor);
    });
  });

  group('Item 4: Aggressive TCP keep-alive (idle=15, interval=15)', () {
    test(
        'defaultKeepAliveInterval is 15 and patchRawConfig writes both keep-alive-interval and keep-alive-idle respecting overrideNetworkSettings',
        () async {
      expect(defaultKeepAliveInterval, 15);
      expect(const ClashConfig().keepAliveInterval, 15);
      expect(
        GlobalState.forTesting().effectiveKeepAliveInterval.value,
        15,
      );

      const bareProfile = Profile(
        id: 'bare-keepalive',
        label: 'BareKeepAlive',
        autoUpdateDuration: Duration.zero,
      );
      const customProfile = Profile(
        id: 'custom-keepalive',
        label: 'CustomKeepAlive',
        autoUpdateDuration: Duration.zero,
      );
      final baseConfig = Config(
        themeProps: defaultThemeProps,
        profiles: const [bareProfile, customProfile],
        currentProfileId: bareProfile.id,
      );
      final state = _StabilityTestState({
        bareProfile.id: {
          'rules': ['MATCH,DIRECT'],
        },
        customProfile.id: {
          'keep-alive-interval': 45,
          'keep-alive-idle': 60,
          'rules': ['MATCH,DIRECT'],
        },
      })
        ..config = baseConfig;
      globalState.config = baseConfig;

      // Default bare profile -> both 15
      final patchedBare = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: bareProfile,
      );
      expect(patchedBare['keep-alive-interval'], 15);
      expect(patchedBare['keep-alive-idle'], 15);

      // Provider custom values preserved when overrideNetworkSettings == false
      final patchedCustomNoOverride = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: customProfile,
      );
      expect(patchedCustomNoOverride['keep-alive-interval'], 45);
      expect(patchedCustomNoOverride['keep-alive-idle'], 60);

      // Overridden when overrideNetworkSettings == true
      final overrideConfig = baseConfig.copyWith(
        appSetting: baseConfig.appSetting.copyWith(
          overrideNetworkSettings: true,
        ),
      );
      state.config = overrideConfig;
      globalState.config = overrideConfig;
      final patchedOverride = await state.patchRawConfig(
        patchConfig: const ClashConfig(keepAliveInterval: 20),
        profile: customProfile,
      );
      expect(patchedOverride['keep-alive-interval'], 20);
      expect(patchedOverride['keep-alive-idle'], 20);
    });
  });

  group('Item 5: Idempotent SetupParams short-circuit on silent sync', () {
    test(
        'matchesCommittedRuntimeSetup detects identical deep SetupParams, tracks changeProxy/updateConfig, and invalidates on any diff or clearRuntimeSetup',
        () async {
      final transport = _RecordingTransport();
      final core = ClashCore.forTesting(transport);
      addTearDown(() async {
        globalState.clearRuntimeSetup();
        await core.destroy();
      });

      const initialParams = SetupParams(
        config: <String, dynamic>{
          'mixed-port': 7890,
          'mode': 'rule',
          'tun': <String, dynamic>{
            'enable': true,
            'device': 'FlClashX',
            'stack': 'mixed',
            'mtu': 1500,
            'dns-hijack': <String>['any:53'],
            'auto-route': true,
            'route-address': <String>[],
          },
          'proxies': <Map<String, dynamic>>[
            {'name': 'NodeA', 'type': 'vless', 'port': 443},
            {'name': 'NodeB', 'type': 'hysteria2', 'port': 8443},
          ],
          'rule': <String>['MATCH,GLOBAL'],
        },
        selectedMap: <String, String>{'GLOBAL': 'NodeA'},
        testUrl: 'https://www.gstatic.com/generate_204',
      );

      expect(await core.setupConfig(initialParams, profileId: 'p1'), isEmpty);
      expect(transport.setupCalls, 1);

      // Freshly decoded deep clone with identical contents matches!
      final clonedIdentical = SetupParams(
        config:
            jsonDecode(jsonEncode(initialParams.config)) as Map<String, dynamic>,
        selectedMap: <String, String>{'GLOBAL': 'NodeA'},
        testUrl: 'https://www.gstatic.com/generate_204',
      );
      expect(
        globalState.matchesCommittedRuntimeSetup(
          clonedIdentical,
          profileId: 'p1',
        ),
        isTrue,
      );

      // Different profileId -> false
      expect(
        globalState.matchesCommittedRuntimeSetup(
          clonedIdentical,
          profileId: 'p2',
        ),
        isFalse,
      );

      // Different testUrl -> false
      expect(
        globalState.matchesCommittedRuntimeSetup(
          SetupParams(
            config: clonedIdentical.config,
            selectedMap: clonedIdentical.selectedMap,
            testUrl: 'https://cp.cloudflare.com/generate_204',
          ),
          profileId: 'p1',
        ),
        isFalse,
      );

      // Changed node port inside config -> false
      final mutatedConfig =
          jsonDecode(jsonEncode(initialParams.config)) as Map<String, dynamic>;
      ((mutatedConfig['proxies'] as List).first as Map)['port'] = 2053;
      expect(
        globalState.matchesCommittedRuntimeSetup(
          SetupParams(
            config: mutatedConfig,
            selectedMap: clonedIdentical.selectedMap,
            testUrl: clonedIdentical.testUrl,
          ),
          profileId: 'p1',
        ),
        isFalse,
      );

      // Live changeProxy updates committed selectedMap so subsequent silent sync with NodeB still matches!
      expect(
        await core.changeProxy(
          const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'NodeB'),
        ),
        isEmpty,
      );
      expect(
        globalState.matchesCommittedRuntimeSetup(
          SetupParams(
            config: jsonDecode(jsonEncode(initialParams.config))
                as Map<String, dynamic>,
            selectedMap: const <String, String>{'GLOBAL': 'NodeB'},
            testUrl: initialParams.testUrl,
          ),
          profileId: 'p1',
        ),
        isTrue,
      );

      // Live updateConfig updates tun.enable in committed runtime config!
      expect(
        await core.updateConfig(
          const UpdateParams(
            tun: Tun(
              enable: false,
              device: 'FlClashX',
              stack: TunStack.mixed,
              dnsHijack: ['any:53'],
              autoRoute: true,
              routeAddress: [],
            ),
            mixedPort: 7890,
            allowLan: false,
            findProcessMode: FindProcessMode.always,
            mode: Mode.rule,
            logLevel: LogLevel.info,
            ipv6: false,
            tcpConcurrent: false,
            externalController: ExternalControllerStatus.close,
            unifiedDelay: false,
          ),
        ),
        isEmpty,
      );
      expect((globalState.lastRuntimeConfig!['tun'] as Map)['enable'], isFalse);

      // clearRuntimeSetup invalidates immediately
      globalState.clearRuntimeSetup();
      expect(
        globalState.matchesCommittedRuntimeSetup(
          clonedIdentical,
          profileId: 'p1',
        ),
        isFalse,
      );
    });

    test(
        'shouldSkipUnchangedSilentSetup enforces every Windows/desktop safety invariant before skipping setupConfig',
        () {
      expect(
        shouldSkipUnchangedSilentSetup(
          skipIfUnchanged: true,
          isAndroid: false,
          isWindows: true,
          explicitTunOperation: false,
          needsWindowsCoreRestore: false,
          hasAppliedWindowsProfile: true,
          lastAppliedWindowsProfileId: 'p1',
          applyingProfileId: 'p1',
          hasActiveTunRepair: false,
          hasTunRequestFailure: false,
          isCoreInit: true,
          matchesCommittedSetup: true,
        ),
        isTrue,
      );

      // Explicit apply (skipIfUnchanged == false) never skips
      expect(
        shouldSkipUnchangedSilentSetup(
          skipIfUnchanged: false,
          isAndroid: false,
          isWindows: true,
          explicitTunOperation: false,
          needsWindowsCoreRestore: false,
          hasAppliedWindowsProfile: true,
          lastAppliedWindowsProfileId: 'p1',
          applyingProfileId: 'p1',
          hasActiveTunRepair: false,
          hasTunRequestFailure: false,
          isCoreInit: true,
          matchesCommittedSetup: true,
        ),
        isFalse,
      );

      // Android reconnect executor rebuild never skips
      expect(
        shouldSkipUnchangedSilentSetup(
          skipIfUnchanged: true,
          isAndroid: true,
          isWindows: false,
          explicitTunOperation: false,
          needsWindowsCoreRestore: false,
          hasAppliedWindowsProfile: false,
          lastAppliedWindowsProfileId: null,
          applyingProfileId: 'p1',
          hasActiveTunRepair: false,
          hasTunRequestFailure: false,
          isCoreInit: true,
          matchesCommittedSetup: true,
        ),
        isFalse,
      );

      // Initial Windows startup (!hasAppliedWindowsProfile) or Core restore or TUN repair never skips
      for (final (:restore, :applied, :repair, :failure, :coreInit, :matches)
          in [
        (
          restore: true,
          applied: true,
          repair: false,
          failure: false,
          coreInit: true,
          matches: true,
        ),
        (
          restore: false,
          applied: false,
          repair: false,
          failure: false,
          coreInit: true,
          matches: true,
        ),
        (
          restore: false,
          applied: true,
          repair: true,
          failure: false,
          coreInit: true,
          matches: true,
        ),
        (
          restore: false,
          applied: true,
          repair: false,
          failure: true,
          coreInit: true,
          matches: true,
        ),
        (
          restore: false,
          applied: true,
          repair: false,
          failure: false,
          coreInit: false,
          matches: true,
        ),
        (
          restore: false,
          applied: true,
          repair: false,
          failure: false,
          coreInit: true,
          matches: false,
        ),
      ]) {
        expect(
          shouldSkipUnchangedSilentSetup(
            skipIfUnchanged: true,
            isAndroid: false,
            isWindows: true,
            explicitTunOperation: false,
            needsWindowsCoreRestore: restore,
            hasAppliedWindowsProfile: applied,
            lastAppliedWindowsProfileId: 'p1',
            applyingProfileId: 'p1',
            hasActiveTunRepair: repair,
            hasTunRequestFailure: failure,
            isCoreInit: coreInit,
            matchesCommittedSetup: matches,
          ),
          isFalse,
        );
      }
    });
  });
}
