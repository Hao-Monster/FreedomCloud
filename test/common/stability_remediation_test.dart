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

Map<String, dynamic> _mihomoDefaultRawConfigJson({
  Map<String, dynamic>? overrides,
}) {
  final base = <String, dynamic>{
    'allow-lan': false,
    'bind-address': '*',
    'ipv6': true,
    'mode': 'rule',
    'unified-delay': false,
    'tcp-concurrent': false,
    'keep-alive-idle': 0,
    'keep-alive-interval': 0,
    'find-process-mode': 'strict',
    'tun': <String, dynamic>{
      'enable': false,
      'device': '',
      'stack': 'Mips',
      'dns-hijack': <String>['0.0.0.0:53'],
      'auto-route': true,
      'auto-detect-interface': true,
    },
    'profile': <String, dynamic>{
      'store-selected': true,
      'store-fake-ip': false,
    },
    'sniffer': <String, dynamic>{
      'enable': false,
      'override-destination': true,
      'force-domain': <String>[],
      'skip-domain': <String>[],
      'port-whitelist': <String>[],
      'force-dns-mapping': true,
      'parse-pure-ip': true,
      'sniff': <String, dynamic>{},
    },
    'rules': <String>['MATCH,DIRECT'],
  };
  if (overrides != null) {
    base.addAll(overrides);
  }
  return base;
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
        'patchRawConfig enables profile.store-fake-ip and injects missing-Fake-IP sniffer even over Mihomo DefaultRawConfig zero-values when dns.enhanced-mode == fake-ip',
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
        profile.id: _mihomoDefaultRawConfigJson(
          overrides: {
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
        ),
      })
        ..config = config;
      globalState.config = config;

      final patched = await state.patchRawConfig(
        patchConfig: desktopDefaultClashConfig(),
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
        'patchRawConfig preserves explicit custom sniffer and does not enable sniffer when enhanced-mode != fake-ip',
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
        explicitProfile.id: _mihomoDefaultRawConfigJson(
          overrides: {
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
          },
        ),
        normalDnsProfile.id: _mihomoDefaultRawConfigJson(
          overrides: {
            'dns': {
              'enable': true,
              'enhanced-mode': 'normal',
              'nameserver': ['223.5.5.5'],
            },
          },
        ),
      })
        ..config = config;
      globalState.config = config;

      final patchedExplicit = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: explicitProfile,
      );
      expect((patchedExplicit['profile'] as Map)['store-fake-ip'], isTrue);
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
      expect((patchedNormalDns['sniffer'] as Map)['enable'], isFalse);
    });
  });

  group(
      'Item 3: Safe TUN MTU 1500, DefaultRawConfig Mips guard & desktop gvisor recovery',
      () {
    test(
        'syncNetworkSettingsFromProvider and patchRawConfig ignore unconfigured DefaultRawConfig TunMips while preserving explicit provider stack and MTU',
        () async {
      const bareProfile = Profile(
        id: 'bare-tun',
        label: 'BareTun',
        autoUpdateDuration: Duration.zero,
      );
      const customTunProfile = Profile(
        id: 'custom-tun',
        label: 'CustomTun',
        autoUpdateDuration: Duration.zero,
      );
      final config = Config(
        themeProps: defaultThemeProps,
        profiles: const [bareProfile, customTunProfile],
        currentProfileId: bareProfile.id,
      );
      final state = _StabilityTestState({
        bareProfile.id: _mihomoDefaultRawConfigJson(
          overrides: {
            'tun': {
              'enable': false,
              'device': '',
              'stack': 'Mips',
              'mtu': 0,
            },
          },
        ),
        customTunProfile.id: _mihomoDefaultRawConfigJson(
          overrides: {
            'tun': {
              'enable': true,
              'device': 'utun9',
              'stack': 'system',
              'mtu': 1400,
            },
          },
        ),
      })
        ..config = config;
      globalState.config = config;

      final desktopPatch = desktopDefaultClashConfig();

      final syncedBare = await state.syncNetworkSettingsFromProvider(
        desktopPatch,
        profile: bareProfile,
      );
      expect(syncedBare.tun.stack, TunStack.gvisor);

      final patchedBare = await state.patchRawConfig(
        patchConfig: syncedBare,
        profile: bareProfile,
      );
      expect((patchedBare['tun'] as Map)['stack'], 'gvisor');
      expect((patchedBare['tun'] as Map)['mtu'], 1500);

      final syncedCustom = await state.syncNetworkSettingsFromProvider(
        desktopPatch,
        profile: customTunProfile,
      );
      expect(syncedCustom.tun.stack, TunStack.system);

      final patchedCustom = await state.patchRawConfig(
        patchConfig: syncedCustom,
        profile: customTunProfile,
      );
      expect((patchedCustom['tun'] as Map)['stack'], 'system');
      expect((patchedCustom['tun'] as Map)['mtu'], 1400);
    });

    test(
        'Config.compatibleFromJson defaults and restores desktop tun.stack to gvisor (including broken tunDesktopStackMixedMigrated configs) while respecting subsequent manual mixed/system and mobile',
        () {
      // 1. Fresh empty desktop JSON -> defaults to gvisor
      final freshDesktop = Config.compatibleFromJson(
        <String, Object?>{'themeProps': defaultThemeProps.toJson()},
        isDesktop: true,
      );
      expect(freshDesktop.patchClashConfig.tun.stack, TunStack.gvisor);
      expect(
        freshDesktop.appSetting.tunDesktopStackGvisorRestored,
        isTrue,
      );

      // 2. Regression config previously migrated by f329535 (tunDesktopStackMixedMigrated: true, stack: mixed) -> restored once to gvisor!
      final brokenMixedMigratedJson = <String, Object?>{
        'themeProps': defaultThemeProps.toJson(),
        'appSetting': <String, Object?>{
          'dashboardDefaultV2Migrated': true,
          'tunDesktopStackMixedMigrated': true,
        },
        'patchClashConfig': <String, Object?>{
          'tun': <String, Object?>{
            'enable': true,
            'stack': 'mixed',
          },
        },
      };
      final recoveredDesktop = Config.compatibleFromJson(
        brokenMixedMigratedJson,
        isDesktop: true,
      );
      expect(recoveredDesktop.patchClashConfig.tun.stack, TunStack.gvisor);
      expect(
        recoveredDesktop.appSetting.tunDesktopStackGvisorRestored,
        isTrue,
      );

      // 3. Explicit legacy 'system' stack is respected
      final explicitSystemDesktop = Config.compatibleFromJson(
        <String, Object?>{
          'themeProps': defaultThemeProps.toJson(),
          'patchClashConfig': <String, Object?>{
            'tun': <String, Object?>{
              'enable': true,
              'stack': 'system',
            },
          },
        },
        isDesktop: true,
      );
      expect(explicitSystemDesktop.patchClashConfig.tun.stack, TunStack.system);

      // 4a. Legacy pre-f329535 desktop config with `stack: mixed` (from older
      // `const Tun()` default without any migration marker) MUST recover once
      // to `TunStack.gvisor` and record `tunDesktopStackGvisorRestored: true`.
      final legacyMixedDesktop = Config.compatibleFromJson(
        <String, Object?>{
          'themeProps': defaultThemeProps.toJson(),
          'patchClashConfig': <String, Object?>{
            'tun': <String, Object?>{
              'enable': true,
              'stack': 'mixed',
            },
          },
        },
        isDesktop: true,
      );
      expect(legacyMixedDesktop.patchClashConfig.tun.stack, TunStack.gvisor);
      expect(
        legacyMixedDesktop.appSetting.tunDesktopStackGvisorRestored,
        isTrue,
      );

      // 5. User manually switches to mixed AFTER restoration -> preserved across reload!
      final manualMixed = recoveredDesktop.copyWith(
        patchClashConfig: recoveredDesktop.patchClashConfig.copyWith.tun(
          stack: TunStack.mixed,
        ),
      );
      final reloadedManualMixed = Config.compatibleFromJson(
        jsonDecode(jsonEncode(manualMixed.toJson())) as Map<String, Object?>,
        isDesktop: true,
      );
      expect(reloadedManualMixed.patchClashConfig.tun.stack, TunStack.mixed);
      expect(
        reloadedManualMixed.appSetting.tunDesktopStackGvisorRestored,
        isTrue,
      );

      // 6. Mobile (isDesktop: false) keeps mixed default
      final mobileFresh = Config.compatibleFromJson(
        <String, Object?>{'themeProps': defaultThemeProps.toJson()},
        isDesktop: false,
      );
      expect(mobileFresh.patchClashConfig.tun.stack, TunStack.mixed);
    });
  });

  group('Item 4: Aggressive TCP keep-alive (idle=15, interval=15)', () {
    test(
        'defaultKeepAliveInterval is 15 and patchRawConfig treats DefaultRawConfig 0 as unset while preserving positive provider values',
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
        bareProfile.id: _mihomoDefaultRawConfigJson(),
        customProfile.id: _mihomoDefaultRawConfigJson(
          overrides: {
            'keep-alive-interval': 45,
            'keep-alive-idle': 60,
          },
        ),
      })
        ..config = baseConfig;
      globalState.config = baseConfig;

      // Default bare profile (even with DefaultRawConfig 0 values) -> both 15
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
        config: jsonDecode(jsonEncode(initialParams.config))
            as Map<String, dynamic>,
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
