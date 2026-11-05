import 'package:flclashx/common/per_app_policy.dart';
import 'package:flclashx/common/rule_compiler.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBareRuleProfile', () {
    test('detects empty rules and single catch-all MATCH/FINAL profiles as bare', () {
      expect(isBareRuleProfile(const []), isTrue);
      expect(isBareRuleProfile(const ['MATCH,PROXY']), isTrue);
      expect(isBareRuleProfile(const ['  match,🚀 节点选择  ']), isTrue);
      expect(isBareRuleProfile(const ['FINAL,Proxy']), isTrue);
    });

    test('detects profiles with only private LAN/loopback rules + MATCH as bare', () {
      expect(
        isBareRuleProfile(const [
          'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
          'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
          'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
          'GEOSITE,private,DIRECT',
          'GEOIP,private,DIRECT,no-resolve',
          'DOMAIN,localhost,DIRECT',
          'DOMAIN-SUFFIX,local,DIRECT',
          'MATCH,PROXY',
        ]),
        isTrue,
      );
    });

    test('treats profiles with public domain/GeoSite/GeoIP or active RULE-SET as non-bare', () {
      expect(
        isBareRuleProfile(const [
          'GEOSITE,cn,DIRECT',
          'MATCH,PROXY',
        ]),
        isFalse,
      );
      expect(
        isBareRuleProfile(const [
          'DOMAIN-SUFFIX,baidu.com,DIRECT',
          'MATCH,PROXY',
        ]),
        isFalse,
      );
      expect(
        isBareRuleProfile(
          const [
            'RULE-SET,direct_list,DIRECT',
            'MATCH,PROXY',
          ],
          ruleProviders: const {
            'direct_list': {'type': 'http'},
          },
        ),
        isFalse,
      );
    });
  });

  group('resolvePrimaryProxyTarget', () {
    test('prefers valid proxy group referenced by terminal MATCH rule', () {
      final target = resolvePrimaryProxyTarget(
        proxyGroups: const [
          {'name': 'Auto', 'type': 'url-test'},
          {'name': '🚀 节点选择', 'type': 'select'},
        ],
        rawRules: const ['MATCH,🚀 节点选择'],
      );
      expect(target, '🚀 节点选择');
    });

    test('falls back to canonical PROXY or first visible group when MATCH is absent or DIRECT', () {
      expect(
        resolvePrimaryProxyTarget(
          proxyGroups: const [
            {'name': 'HiddenGroup', 'type': 'url-test', 'hidden': true},
            {'name': '节点总览', 'type': 'select'},
          ],
          rawRules: const ['MATCH,DIRECT'],
        ),
        '节点总览',
      );

      expect(
        resolvePrimaryProxyTarget(
          proxyGroups: const [
            {'name': 'Streaming', 'type': 'select'},
            {'name': 'PROXY', 'type': 'select'},
          ],
          rawRules: const [],
        ),
        'PROXY',
      );

      expect(
        resolvePrimaryProxyTarget(
          proxyGroups: const [],
          proxies: const [
            {'name': 'VLESS-Tokyo-01', 'type': 'vless'},
          ],
          rawRules: const ['MATCH,VLESS-Tokyo-01'],
        ),
        'VLESS-Tokyo-01',
      );

      expect(
        resolvePrimaryProxyTarget(
          proxyGroups: const [],
          rawRules: const [],
        ),
        'GLOBAL',
      );
    });
  });

  group('compileEffectiveRules', () {
    test('automatically injects Fake-IP-safe CN/private split rules on bare MATCH,PROXY profile', () {
      final result = compileEffectiveRules(
        rawProfileRules: const ['MATCH,PROXY'],
        proxyGroups: const [
          {'name': 'PROXY', 'type': 'select'},
        ],
        localSplitMode: LocalSplitMode.auto,
        routeMode: RouteMode.config,
        isDesktop: true,
        hasGeoSite: true,
        hasGeoIp: true,
      );

      expect(result.localSplitActivated, isTrue);
      expect(result.primaryProxyTarget, 'PROXY');
      expect(result.rules.last, 'MATCH,PROXY');

      final idxPrivateCidr =
          result.rules.indexOf('IP-CIDR,192.168.0.0/16,DIRECT,no-resolve');
      final idxGeositePrivate =
          result.rules.indexOf('GEOSITE,private,DIRECT');
      final idxGeositeCn = result.rules.indexOf('GEOSITE,cn,DIRECT');
      final idxGeositeNonCn =
          result.rules.indexOf('GEOSITE,geolocation-!cn,PROXY');
      final idxGeoipCn = result.rules.indexOf('GEOIP,CN,DIRECT');
      final idxMatch = result.rules.indexOf('MATCH,PROXY');

      expect(idxPrivateCidr, greaterThanOrEqualTo(0));
      expect(idxGeositePrivate, greaterThan(idxPrivateCidr));
      expect(idxGeositeCn, greaterThan(idxGeositePrivate));
      expect(
        idxGeositeNonCn,
        greaterThan(idxGeositeCn),
        reason: 'Known foreign domains must route to proxy before GEOIP,CN triggers local DNS',
      );
      expect(idxGeoipCn, greaterThan(idxGeositeNonCn));
      expect(idxMatch, greaterThan(idxGeoipCn));
      expect(
        result.rules.any((r) => r.contains('198.18.')),
        isFalse,
        reason: 'Fake-IP 198.18.0.0/16 must never be bypassed DIRECT',
      );
    });

    test('synthesizes terminal MATCH rule when bare profile has empty rules list', () {
      final result = compileEffectiveRules(
        rawProfileRules: const [],
        proxyGroups: const [
          {'name': '🚀 节点选择', 'type': 'select'},
        ],
        localSplitMode: LocalSplitMode.auto,
        routeMode: RouteMode.config,
        isDesktop: true,
        hasGeoSite: true,
        hasGeoIp: true,
      );

      expect(result.localSplitActivated, isTrue);
      expect(result.rules, contains('GEOSITE,cn,DIRECT'));
      expect(result.rules, contains('GEOSITE,geolocation-!cn,🚀 节点选择'));
      expect(result.rules.last, 'MATCH,🚀 节点选择');
    });

    test('leaves full subscription rules untouched in LocalSplitMode.auto', () {
      const providerRules = [
        'DOMAIN-SUFFIX,openai.com,AI',
        'GEOSITE,cn,DIRECT',
        'GEOIP,CN,DIRECT',
        'MATCH,🚀 节点选择',
      ];
      final result = compileEffectiveRules(
        rawProfileRules: providerRules,
        proxyGroups: const [
          {'name': 'AI', 'type': 'select'},
          {'name': '🚀 节点选择', 'type': 'select'},
        ],
        localSplitMode: LocalSplitMode.auto,
        routeMode: RouteMode.config,
        isDesktop: false,
        hasGeoSite: true,
        hasGeoIp: true,
      );

      expect(result.localSplitActivated, isFalse);
      expect(result.rules, providerRules);
    });

    test('enforces 5-layer precedence and adapts DEFAULT_PROXY / missing group across profiles', () {
      final globalOverride = OverrideData(
        enable: true,
        rule: OverrideRule(
          type: OverrideRuleType.added,
          addedRules: [
            Rule.value('DOMAIN-SUFFIX,claude.ai,$semanticDefaultProxyTarget'),
            Rule.value('DOMAIN-SUFFIX,huggingface.co,LegacyGroupNotInProfileB'),
            Rule.value('DOMAIN-SUFFIX,internal.cn,DIRECT'),
          ],
        ),
      );
      final profileOverride = OverrideData(
        enable: true,
        rule: OverrideRule(
          type: OverrideRuleType.added,
          addedRules: [
            Rule.value('DOMAIN-SUFFIX,special-profile-only.com,DIRECT'),
          ],
        ),
      );
      const perApp = [
        PerAppPolicy(
          path: r'C:\Program Files\Tencent\Weixin\Weixin.exe',
          name: 'Weixin.exe',
          policy: ApplicationRoutingPolicy.direct,
        ),
      ];

      final compiledForProfileB = compileEffectiveRules(
        rawProfileRules: const ['MATCH,🚀 节点选择'],
        proxyGroups: const [
          {'name': '🚀 节点选择', 'type': 'select'},
        ],
        perAppPolicies: perApp,
        globalOverrideData: globalOverride,
        profileOverrideData: profileOverride,
        localSplitMode: LocalSplitMode.auto,
        routeMode: RouteMode.config,
        isDesktop: true,
        hasGeoSite: true,
        hasGeoIp: true,
      );

      expect(
        compiledForProfileB.rules[0],
        r'PROCESS-PATH,C:\Program Files\Tencent\Weixin\Weixin.exe,DIRECT',
      );
      expect(
        compiledForProfileB.rules[1],
        'DOMAIN-SUFFIX,special-profile-only.com,DIRECT',
      );
      expect(
        compiledForProfileB.rules[2],
        'DOMAIN-SUFFIX,claude.ai,🚀 节点选择',
      );
      expect(
        compiledForProfileB.rules[3],
        'DOMAIN-SUFFIX,huggingface.co,🚀 节点选择',
      );
      expect(
        compiledForProfileB.rules[4],
        'DOMAIN-SUFFIX,internal.cn,DIRECT',
      );
      expect(compiledForProfileB.rules, contains('GEOSITE,cn,DIRECT'));
      expect(compiledForProfileB.rules.last, 'MATCH,🚀 节点选择');
    });

    test('gracefully degrades to built-in domestic suffixes when GeoData files are unavailable', () {
      final result = compileEffectiveRules(
        rawProfileRules: const ['MATCH,PROXY'],
        proxyGroups: const [
          {'name': 'PROXY', 'type': 'select'},
        ],
        localSplitMode: LocalSplitMode.auto,
        routeMode: RouteMode.config,
        isDesktop: true,
        hasGeoSite: false,
        hasGeoIp: false,
      );

      expect(result.localSplitActivated, isTrue);
      expect(result.rules.any((r) => r.startsWith('GEOSITE,')), isFalse);
      expect(result.rules.any((r) => r.startsWith('GEOIP,')), isFalse);
      expect(result.rules, contains('DOMAIN-SUFFIX,cn,DIRECT'));
      expect(result.rules, contains('DOMAIN-SUFFIX,baidu.com,DIRECT'));
      expect(result.rules, contains('DOMAIN-SUFFIX,bdstatic.com,DIRECT'));
      expect(result.rules.last, 'MATCH,PROXY');
    });
  });
}
