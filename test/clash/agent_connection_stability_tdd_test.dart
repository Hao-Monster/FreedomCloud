import 'dart:async';
import 'dart:io';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _SurgicalChangeProxyTransport extends ClashHandlerInterface {
  final List<ChangeProxyParams> changeProxyCalls = <ChangeProxyParams>[];
  int closeConnectionsCalls = 0;
  String changeProxyReturnValue = '';

  @override
  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    changeProxyCalls.add(changeProxyParams);
    return changeProxyReturnValue;
  }

  @override
  Future<bool> closeConnections() async {
    closeConnectionsCalls++;
    return true;
  }

  @override
  Future<bool> destroy() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ChangeProxyParams serialization & backward compatibility', () {
    test(
        'defaults closeConnections to false and serializes close-connections in JSON',
        () {
      const legacyStyle = ChangeProxyParams(
        groupName: 'Proxy',
        proxyName: 'HK-01',
      );
      expect(legacyStyle.closeConnections, isFalse);
      expect(legacyStyle.toJson(), {
        'group-name': 'Proxy',
        'proxy-name': 'HK-01',
        'close-connections': false,
      });

      const surgicalClose = ChangeProxyParams(
        groupName: 'Proxy',
        proxyName: 'SG-02',
        closeConnections: true,
      );
      expect(surgicalClose.closeConnections, isTrue);
      expect(surgicalClose.toJson(), {
        'group-name': 'Proxy',
        'proxy-name': 'SG-02',
        'close-connections': true,
      });

      final fromLegacyJson = ChangeProxyParams.fromJson(const {
        'group-name': 'GLOBAL',
        'proxy-name': 'JP-01',
      });
      expect(fromLegacyJson, const ChangeProxyParams(
        groupName: 'GLOBAL',
        proxyName: 'JP-01',
      ));
      expect(fromLegacyJson.closeConnections, isFalse);

      final fromExplicitJson = ChangeProxyParams.fromJson(const {
        'group-name': 'GLOBAL',
        'proxy-name': 'JP-01',
        'close-connections': true,
      });
      expect(fromExplicitJson.closeConnections, isTrue);
      expect(fromExplicitJson, isNot(equals(fromLegacyJson)));
      expect(
        legacyStyle.copyWith(closeConnections: true),
        const ChangeProxyParams(
          groupName: 'Proxy',
          proxyName: 'HK-01',
          closeConnections: true,
        ),
      );
    });
  });

  group('performSurgicalChangeProxy & AppController.changeProxy', () {
    test(
        'performSurgicalChangeProxy forwards closeConnections flag without calling global closeConnections()',
        () async {
      final transport = _SurgicalChangeProxyTransport();
      final core = ClashCore.forTesting(transport);
      addTearDown(() async {
        globalState.clearRuntimeSetup();
        await core.destroy();
      });

      final resFalse = await performSurgicalChangeProxy(
        core: core,
        groupName: 'Proxy',
        proxyName: 'HK-01',
        closeConnections: false,
      );
      expect(resFalse, isEmpty);
      expect(transport.changeProxyCalls, hasLength(1));
      expect(
        transport.changeProxyCalls.last,
        const ChangeProxyParams(
          groupName: 'Proxy',
          proxyName: 'HK-01',
          closeConnections: false,
        ),
      );
      expect(transport.closeConnectionsCalls, 0);

      final resTrue = await performSurgicalChangeProxy(
        core: core,
        groupName: 'Proxy',
        proxyName: 'SG-01',
        closeConnections: true,
      );
      expect(resTrue, isEmpty);
      expect(transport.changeProxyCalls, hasLength(2));
      expect(
        transport.changeProxyCalls.last,
        const ChangeProxyParams(
          groupName: 'Proxy',
          proxyName: 'SG-01',
          closeConnections: true,
        ),
      );
      // Crucial: global closeConnections() must NEVER be triggered after changeProxy.
      expect(transport.closeConnectionsCalls, 0);
    });

    testWidgets(
        'AppController.changeProxy passes appSettingProvider.closeConnections via ChangeProxyParams without global closeConnections()',
        (tester) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('fcx_surgical_change_proxy_'),
      );
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(tempDir!.path);

      globalState.appState = AppState(
        version: 0,
        viewSize: Size.zero,
        requests: FixedList(10),
        logs: FixedList(10),
        traffics: FixedList(10),
        totalTraffic: Traffic(),
      );

      final transport = _SurgicalChangeProxyTransport();
      final previousInterface = clashCore.clashInterface;
      clashCore.clashInterface = transport;
      addTearDown(() async {
        debouncer.cancel(FunctionTag.addCheckIpNum);
        clashCore.clashInterface = previousInterface;
        PathProviderPlatform.instance = originalPaths;
        globalState.clearRuntimeSetup();
        await tester.runAsync(() => tempDir.delete(recursive: true));
      });

      const profile = Profile(
        id: 'p-surgical',
        label: 'Surgical Test Profile',
        url: 'https://sub.example.com/feed',
        autoUpdateDuration: Duration(hours: 24),
      );
      globalState.config = Config(
        themeProps: defaultThemeProps,
        profiles: [profile],
        currentProfileId: profile.id,
      );

      AppController? controller;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                controller ??= AppController(context, ref);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );

      container.read(appSettingProvider.notifier).updateState(
            (state) => state.copyWith(closeConnections: true),
          );
      await controller!.changeProxy(
        groupName: 'Proxy',
        proxyName: 'US-01',
      );
      expect(transport.changeProxyCalls.last.closeConnections, isTrue);
      expect(transport.closeConnectionsCalls, 0);

      container.read(appSettingProvider.notifier).updateState(
            (state) => state.copyWith(closeConnections: false),
          );
      await controller!.changeProxy(
        groupName: 'Proxy',
        proxyName: 'JP-01',
      );
      expect(transport.changeProxyCalls.last.closeConnections, isFalse);
      expect(transport.closeConnectionsCalls, 0);

      debouncer.cancel(FunctionTag.addCheckIpNum);
    });
  });

  group('Smart node selection long-stream tuning', () {
    test(
        'sets tolerance=150ms, timeout=5000ms, max-failed-times=2 on both selector and GLOBAL smart groups',
        () {
      expect(kManagedSmartToleranceMs, 150);
      expect(kManagedSmartTestTimeoutMs, 5000);
      expect(kManagedSmartMaxFailedTimes, 2);

      final rawConfig = <String, dynamic>{
        'proxies': [
          {
            'name': 'HK-01',
            'type': 'vless',
            'server': 'hk1.example.com',
            'port': 443,
            'uuid': 'u-hk-1',
          },
          {
            'name': 'SG-01',
            'type': 'vless',
            'server': 'sg1.example.com',
            'port': 443,
            'uuid': 'u-sg-1',
          },
        ],
        'proxy-groups': [
          {
            'name': 'Proxy',
            'type': 'select',
            'proxies': ['HK-01', 'SG-01'],
          },
        ],
      };

      injectManagedSmartProxyGroups(
        rawConfig,
        defaultTestUrl: 'https://www.google.com/generate_204',
      );

      final groups = (rawConfig['proxy-groups'] as List).cast<Map>();
      final selectorSmart = groups.singleWhere(
        (g) => g['name'] == managedSmartGroupNameFor('Proxy'),
      );
      final globalSmart = groups.singleWhere(
        (g) => g['name'] == managedSmartGroupNameFor('GLOBAL'),
      );

      for (final group in [selectorSmart, globalSmart]) {
        expect(group['tolerance'], 150);
        expect(group['timeout'], 5000);
        expect(group['max-failed-times'], 2);
      }
    });
  });

  group('Dynamic traffic badge stripping & node reconciliation boundaries', () {
    test('stripDynamicTrafficBadge strips byte-unit badges and preserves normal indices & multipliers',
        () {
      expect(
        stripDynamicTrafficBadge('443-新加坡01|📊227.33GB'),
        '443-新加坡01',
      );
      expect(
        stripDynamicTrafficBadge('香港01 | 剩余 128.4 GB'),
        '香港01',
      );
      expect(
        stripDynamicTrafficBadge('日本01 [99.5GiB]'),
        '日本01',
      );
      expect(
        stripDynamicTrafficBadge('美国01 (流量 50MB)'),
        '美国01',
      );
      expect(
        stripDynamicTrafficBadge('狮城01 / remaining 12.5 TB'),
        '狮城01',
      );
      expect(
        stripDynamicTrafficBadge('台湾01、left: 512kib'),
        '台湾01',
      );
      expect(
        stripDynamicTrafficBadge('韩国01（余量 100mib）'),
        '韩国01',
      );
      expect(
        stripDynamicTrafficBadge('英国01 【可用 2.5PiB】'),
        '英国01',
      );
      expect(
        stripDynamicTrafficBadge('德国01 - 📊 900B'),
        '德国01',
      );
      expect(
        stripDynamicTrafficBadge('香港01 | 10/100GB'),
        '香港01',
      );
      expect(
        stripDynamicTrafficBadge('香港01 | 10.5GB/200GB'),
        '香港01',
      );
      expect(
        stripDynamicTrafficBadge('香港01 | 剩余流量: 128.4 GB'),
        '香港01',
      );
      expect(
        stripDynamicTrafficBadge('狮城01 / remaining traffic 12.5 TB'),
        '狮城01',
      );
      expect(
        stripDynamicTrafficBadge('香港01 | 已用流量 10GB / 剩余 90GB'),
        '香港01',
      );

      // Must NOT strip regular node indices, multipliers, bandwidths, dates, or empty stems.
      expect(stripDynamicTrafficBadge('香港 01'), isNull);
      expect(stripDynamicTrafficBadge('香港01 2x'), isNull);
      expect(stripDynamicTrafficBadge('香港01 0.5X'), isNull);
      expect(stripDynamicTrafficBadge('香港01 | 2x'), isNull);
      expect(stripDynamicTrafficBadge('香港01 [100Mbps]'), isNull);
      expect(stripDynamicTrafficBadge('香港01 | 10/100Mbps'), isNull);
      expect(stripDynamicTrafficBadge('香港01 | 2026/01/01'), isNull);
      expect(stripDynamicTrafficBadge('HK-10GB'), isNull);
      expect(stripDynamicTrafficBadge('|📊227.33GB'), isNull);
      expect(stripDynamicTrafficBadge('[99.5GiB]'), isNull);
      expect(stripDynamicTrafficBadge(''), isNull);

      expect(
        reconcileDynamicTrafficNodeName(
          '香港01 | 5/100GB',
          const ['香港01 | 10/100GB', '香港01 | 10/100GB'],
        ),
        '香港01 | 10/100GB',
      );
      expect(
        reconcileDynamicTrafficNodeName('香港01 ', const ['香港01']),
        '香港01 ',
      );
    });

    test(
        'buildEffectiveSelectedMapForProfile aligns dynamic traffic suffix updates without touching smart groups, ambiguity, multipliers, or provider misses',
        () {
      final patchedConfig = <String, dynamic>{
        'proxies': [
          {
            'name': '443-新加坡01|📊190.12GB',
            'type': 'vless',
            'server': 'sg.example.com',
            'port': 443,
            'uuid': 'u-sg',
          },
          {
            'name': '香港01 | 剩余 80.5 GB',
            'type': 'vless',
            'server': 'hk.example.com',
            'port': 443,
            'uuid': 'u-hk',
          },
          {
            'name': '香港02 2x',
            'type': 'vless',
            'server': 'hk2.example.com',
            'port': 443,
            'uuid': 'u-hk2',
          },
          {
            'name': '日本01 | 50GB',
            'type': 'vless',
            'server': 'jp1.example.com',
            'port': 443,
            'uuid': 'u-jp1',
          },
          {
            'name': '日本01 [50GB]',
            'type': 'vless',
            'server': 'jp2.example.com',
            'port': 443,
            'uuid': 'u-jp2',
          },
        ],
        'proxy-providers': {
          'airport-feed': {
            'type': 'http',
            'url': 'https://sub.example.com/provider',
          },
        },
        'proxy-groups': [
          {
            'name': 'Proxy',
            'type': 'select',
            'proxies': [
              '443-新加坡01|📊190.12GB',
              '香港01 | 剩余 80.5 GB',
              '香港02 2x',
            ],
          },
          {
            'name': 'AmbiguousGroup',
            'type': 'select',
            'proxies': ['日本01 | 50GB', '日本01 [50GB]'],
          },
          {
            'name': 'MultiplierGroup',
            'type': 'select',
            'proxies': ['香港02 2x'],
          },
          {
            'name': 'ProviderGroup',
            'type': 'select',
            'use': ['airport-feed'],
            'proxies': ['DIRECT'],
          },
        ],
      };

      const manualProfile = Profile(
        id: 'p-manual',
        label: 'Manual Fixed',
        autoUpdateDuration: Duration.zero,
        selectedMap: {
          'Proxy': '443-新加坡01|📊227.33GB',
          'AmbiguousGroup': '日本01 | 99GB',
          'MultiplierGroup': '香港02 1x',
          'ProviderGroup': '美国01 (流量 50MB)',
        },
      );

      final effectiveManual = buildEffectiveSelectedMapForProfile(
        profile: manualProfile,
        patchedRawConfig: patchedConfig,
      );
      expect(effectiveManual['Proxy'], '443-新加坡01|📊190.12GB');
      // Ambiguous multi-candidate match keeps original selection.
      expect(effectiveManual['AmbiguousGroup'], '日本01 | 99GB');
      // Multiplier must NOT align across 1x -> 2x.
      expect(effectiveManual['MultiplierGroup'], '香港02 1x');
      // Provider-backed group inline miss preserves value for Go Core runtime alignment.
      expect(effectiveManual['ProviderGroup'], '美国01 (流量 50MB)');

      // Smart mode keeps smart group entries untouched while still aligning secondary manual groups.
      injectManagedSmartProxyGroups(
        patchedConfig,
        defaultTestUrl: 'https://www.google.com/generate_204',
      );
      final smartProfile = markProfileSelectionMode(
        const Profile(
          id: 'p-smart',
          label: 'Smart Mode',
          autoUpdateDuration: Duration.zero,
          selectedMap: {
            'Proxy': '香港01',
            'MultiplierGroup': '香港01',
          },
        ),
        NodeSelectionMode.smart,
        targetGroup: 'Proxy',
      );
      // Swap MultiplierGroup in smartProfile's selectedMap to test secondary non-smart group alignment.
      final smartProfileWithSecondary = smartProfile.copyWith(
        selectedMap: {
          ...smartProfile.selectedMap,
          'AmbiguousGroup': '日本01 | 99GB',
        },
        providerHeaders: {
          ...smartProfile.providerHeaders,
        },
      );
      final patchedSmartConfig = <String, dynamic>{
        ...patchedConfig,
        'proxy-groups': [
          ...(patchedConfig['proxy-groups'] as List),
          {
            'name': 'SecondarySelect',
            'type': 'select',
            'proxies': ['香港01 | 剩余 80.5 GB'],
          },
        ],
      };
      final effectiveSmart = buildEffectiveSelectedMapForProfile(
        profile: smartProfileWithSecondary.copyWith(
          selectedMap: {
            ...smartProfileWithSecondary.selectedMap,
            'SecondarySelect': '香港01 | 剩余 128.4 GB',
          },
        ),
        patchedRawConfig: patchedSmartConfig,
      );
      expect(effectiveSmart['Proxy'], managedSmartGroupNameFor('Proxy'));
      expect(effectiveSmart['GLOBAL'], managedSmartGroupNameFor('GLOBAL'));
      expect(effectiveSmart['SecondarySelect'], '香港01 | 剩余 80.5 GB');
      expect(effectiveSmart['AmbiguousGroup'], '日本01 | 99GB');
    });
  });
}
