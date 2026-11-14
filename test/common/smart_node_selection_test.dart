import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaultUrl = 'https://www.google.com/generate_204';

  group('injectManagedSmartProxyGroups', () {
    test(
        'synthesizes hidden url-test smart groups for selector and GLOBAL, filters informational fake nodes, appends smart option without altering default index-0, and stays idempotent',
        () {
      final rawConfig = <String, dynamic>{
        'proxies': [
          {
            'name': '剩余流量：99.5 GB',
            'type': 'ss',
            'server': 'info.example.com',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'p',
          },
          {
            'name': '套餐到期：2027-01-01',
            'type': 'ss',
            'server': 'exp.example.com',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'p',
          },
          {
            'name': '香港 01',
            'type': 'vless',
            'server': 'hk1.example.com',
            'port': 443,
            'uuid': 'u-hk-1',
          },
          {
            'name': '美国 01',
            'type': 'vless',
            'server': 'us1.example.com',
            'port': 443,
            'uuid': 'u-us-1',
          },
        ],
        'proxy-groups': [
          {
            'name': '🚀 节点选择',
            'type': 'select',
            'proxies': [
              '⚡ 自动选择',
              'DIRECT',
              '剩余流量：99.5 GB',
              '套餐到期：2027-01-01',
              '香港 01',
              '美国 01',
            ],
          },
          {
            'name': '⚡ 自动选择',
            'type': 'url-test',
            'proxies': ['香港 01', '美国 01'],
          },
          {
            'name': '🛑 广告拦截',
            'type': 'select',
            'proxies': ['REJECT', 'DIRECT'],
          },
        ],
      };

      final catalogBefore = buildProfileCatalog(
        profileId: 'p1',
        fingerprint: 'fp1',
        raw: rawConfig,
      );

      injectManagedSmartProxyGroups(rawConfig, defaultTestUrl: defaultUrl);
      // Calling a second time must be strictly idempotent.
      injectManagedSmartProxyGroups(rawConfig, defaultTestUrl: defaultUrl);

      final groups = (rawConfig['proxy-groups'] as List).cast<Map>();
      final smartSelectorName = managedSmartGroupNameFor('🚀 节点选择');
      final smartGlobalName = managedSmartGroupNameFor('GLOBAL');

      expect(isManagedSmartGroupName(smartSelectorName), isTrue);
      expect(isManagedSmartGroupName(smartGlobalName), isTrue);
      expect(isManagedSmartGroupName('🚀 节点选择'), isFalse);

      // Index 0 of 🚀 节点选择 remains untouched for existing profiles with empty selectedMap,
      // while smartSelectorName is appended once at the end.
      final mainSelect =
          groups.singleWhere((g) => g['name'] == '🚀 节点选择');
      final mainProxies = (mainSelect['proxies'] as List).cast<String>();
      expect(mainProxies.first, '⚡ 自动选择');
      expect(mainProxies.where((p) => p == smartSelectorName), hasLength(1));
      expect(mainProxies.last, smartSelectorName);

      // Pure policy group 🛑 广告拦截 ([REJECT, DIRECT]) must NOT get a smart group.
      expect(
        groups.any(
          (g) => g['name'] == managedSmartGroupNameFor('🛑 广告拦截'),
        ),
        isFalse,
      );

      // Synthesized hidden url-test group contains ONLY real non-informational leaves!
      final smartSelectGroup =
          groups.singleWhere((g) => g['name'] == smartSelectorName);
      expect(smartSelectGroup['type'], 'url-test');
      expect(smartSelectGroup['hidden'], isTrue);
      expect(smartSelectGroup['url'], defaultUrl);
      expect(smartSelectGroup['interval'], kManagedSmartTestIntervalSec);
      expect(smartSelectGroup['tolerance'], kManagedSmartToleranceMs);
      expect(smartSelectGroup['lazy'], isFalse);
      expect(smartSelectGroup['proxies'], ['香港 01', '美国 01']);

      // GLOBAL smart group is also synthesized so Mode.global supports smart selection.
      final smartGlobalGroup =
          groups.singleWhere((g) => g['name'] == smartGlobalName);
      expect(smartGlobalGroup['type'], 'url-test');
      expect(smartGlobalGroup['hidden'], isTrue);
      expect(smartGlobalGroup['proxies'], ['香港 01', '美国 01']);

      // Runtime catalog identity & selectGroups projection remain 100% identical!
      final catalogAfter = buildProfileCatalog(
        profileId: 'p1',
        fingerprint: 'fp1',
        raw: rawConfig,
      );
      expect(
        catalogAfter.nodes
            .map((n) => (n.identityKey, n.selectGroups.join('|')))
            .toList(),
        catalogBefore.nodes
            .map((n) => (n.identityKey, n.selectGroups.join('|')))
            .toList(),
      );
    });

    test(
        'supports provider-backed (use), include-all, sub-group-only selectors, and explicit GLOBAL override',
        () {
      final rawConfig = <String, dynamic>{
        'proxies': [
          {
            'name': 'HK Sub 1',
            'type': 'ss',
            'server': 'hk.example.com',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'p',
          },
          {
            'name': 'US Sub 1',
            'type': 'ss',
            'server': 'us.example.com',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'p',
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
            'proxies': ['HK Group', 'US Group'],
            'use': ['airport-feed'],
            'exclude-filter': '倍率.*[3-9]',
          },
          {
            'name': 'HK Group',
            'type': 'url-test',
            'proxies': ['HK Sub 1'],
          },
          {
            'name': 'US Group',
            'type': 'url-test',
            'proxies': ['US Sub 1'],
          },
          {
            'name': 'GLOBAL',
            'type': 'select',
            'flclashx-override': true,
            'proxies': ['Proxy', 'DIRECT'],
          },
        ],
      };

      injectManagedSmartProxyGroups(rawConfig, defaultTestUrl: defaultUrl);

      final groups = (rawConfig['proxy-groups'] as List).cast<Map>();
      final smartProxy = groups
          .singleWhere((g) => g['name'] == managedSmartGroupNameFor('Proxy'));
      expect(smartProxy['proxies'], ['HK Sub 1', 'US Sub 1']);
      expect(smartProxy['use'], ['airport-feed']);
      expect(
        smartProxy['exclude-filter'] as String,
        allOf(contains('倍率.*[3-9]'), contains('剩余流量')),
      );

      final explicitGlobal = groups.singleWhere((g) => g['name'] == 'GLOBAL');
      expect(
        explicitGlobal['proxies'],
        contains(managedSmartGroupNameFor('GLOBAL')),
      );

      // Verify _SelectGroupIndex in buildProfileCatalog accepts the combined regex!
      expect(
        () => buildProfileCatalog(
          profileId: 'p2',
          fingerprint: 'fp2',
          raw: rawConfig,
        ),
        returnsNormally,
      );
    });

    test(
        'falls back to real leaves when 100% of leaves match informational names so Mihomo never receives an empty group',
        () {
      final rawConfig = <String, dynamic>{
        'proxies': [
          {
            'name': '官网备用节点',
            'type': 'ss',
            'server': '1.2.3.4',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'p',
          },
        ],
        'proxy-groups': [
          {
            'name': 'Proxy',
            'type': 'select',
            'proxies': ['官网备用节点'],
          },
        ],
      };

      injectManagedSmartProxyGroups(rawConfig, defaultTestUrl: defaultUrl);

      final groups = (rawConfig['proxy-groups'] as List).cast<Map>();
      final smartProxy = groups
          .singleWhere((g) => g['name'] == managedSmartGroupNameFor('Proxy'));
      expect(smartProxy['proxies'], ['官网备用节点']);
    });
  });

  group('selection mode persistence & effective selectedMap', () {
    test(
        'legacy existing profiles keep manual mode & untouched selectedMap, while new or smart-marked profiles bind selector + GLOBAL to smart groups',
        () {
      final patchedConfig = <String, dynamic>{
        'proxies': [
          {
            'name': '香港 01',
            'type': 'ss',
            'server': 'hk.example.com',
            'port': 443,
            'cipher': 'aes-128-gcm',
            'password': 'p',
          },
        ],
        'proxy-groups': [
          {
            'name': 'Proxy',
            'type': 'select',
            'proxies': ['香港 01'],
          },
        ],
      };
      injectManagedSmartProxyGroups(patchedConfig, defaultTestUrl: defaultUrl);

      const legacyFixedProfile = Profile(
        id: 'legacy-fixed',
        label: '老订阅固定IP',
        autoUpdateDuration: Duration.zero,
        selectedMap: {'Proxy': '香港 01'},
      );
      expect(
        resolveProfileSelectionMode(legacyFixedProfile),
        NodeSelectionMode.manual,
      );
      expect(
        buildEffectiveSelectedMapForProfile(
          profile: legacyFixedProfile,
          patchedRawConfig: patchedConfig,
        ),
        {'Proxy': '香港 01'},
      );

      const legacyEmptyProfile = Profile(
        id: 'legacy-empty',
        label: '老订阅默认',
        autoUpdateDuration: Duration.zero,
      );
      expect(
        resolveProfileSelectionMode(legacyEmptyProfile),
        NodeSelectionMode.manual,
      );
      expect(
        buildEffectiveSelectedMapForProfile(
          profile: legacyEmptyProfile,
          patchedRawConfig: patchedConfig,
        ),
        isEmpty,
      );

      final newSmartProfile = markProfileSelectionMode(
        const Profile(
          id: 'new-sub',
          label: '新导入订阅',
          autoUpdateDuration: Duration.zero,
        ),
        NodeSelectionMode.smart,
      );
      expect(
        resolveProfileSelectionMode(newSmartProfile),
        NodeSelectionMode.smart,
      );
      expect(
        buildEffectiveSelectedMapForProfile(
          profile: newSmartProfile,
          patchedRawConfig: patchedConfig,
        ),
        {
          'Proxy': managedSmartGroupNameFor('Proxy'),
          'GLOBAL': managedSmartGroupNameFor('GLOBAL'),
        },
      );

      // Switching back to manual locks the concrete node and strips smart group targets.
      final lockedManual = markProfileSelectionMode(
        newSmartProfile,
        NodeSelectionMode.manual,
        targetGroup: 'Proxy',
        manualNodeName: '香港 01',
      );
      expect(
        resolveProfileSelectionMode(lockedManual),
        NodeSelectionMode.manual,
      );
      expect(lockedManual.selectedMap['Proxy'], '香港 01');
      expect(
        lockedManual.selectedMap.values.any(isManagedSmartGroupName),
        isFalse,
      );

      // Subscription refresh via mergeUpdatedProfileSnapshot preserves smartSelectionModeMarker!
      final refreshed = mergeUpdatedProfileSnapshot(
        base: newSmartProfile,
        fetched: newSmartProfile.copyWith(
          providerHeaders: const {'announce': 'hello'},
        ),
        latest: newSmartProfile,
      );
      expect(refreshed, isNotNull);
      expect(
        resolveProfileSelectionMode(refreshed),
        NodeSelectionMode.smart,
      );
    });

    test('resolveSmartActiveLeafName resolves nested url-test now leaf cleanly',
        () {
      final smartName = managedSmartGroupNameFor('Proxy');
      final allGroups = [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          now: smartName,
          hidden: false,
          all: [
            Proxy(name: smartName, type: 'URLTest'),
            const Proxy(name: '美国AGK-Reality-Vision', type: 'VLESS'),
          ],
        ),
        Group(
          name: smartName,
          type: GroupType.URLTest,
          now: '美国AGK-Reality-Vision',
          hidden: true,
          all: const [
            Proxy(name: '美国AGK-Reality-Vision', type: 'VLESS'),
          ],
        ),
      ];

      expect(
        resolveSmartActiveLeafName(
          selectorGroupName: 'Proxy',
          allGroups: allGroups,
          selectedMap: {'Proxy': smartName},
        ),
        '美国AGK-Reality-Vision',
      );
    });
  });
}
