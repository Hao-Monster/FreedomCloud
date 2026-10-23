import 'dart:io';

import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeIsoCountryCode & inferCountryCodeFromText', () {
    test('extracts country code from regional indicator flag emoji', () {
      expect(inferCountryCodeFromText('🇺🇸 US Node 01'), 'US');
      expect(inferCountryCodeFromText('🇬🇧 英国 IEPL'), 'GB');
      expect(inferCountryCodeFromText('🇯🇵 Tokyo 01'), 'JP');
      expect(normalizeIsoCountryCode('UK'), 'GB');
    });

    test('infers country code from Chinese and English country/city names', () {
      expect(inferCountryCodeFromText('香港 BGP 01'), 'HK');
      expect(inferCountryCodeFromText('台湾 彰化 Hinet'), 'TW');
      expect(inferCountryCodeFromText('新加坡 狮城高速'), 'SG');
      expect(inferCountryCodeFromText('日本 东京 IPLC'), 'JP');
      expect(inferCountryCodeFromText('韩国 首尔 KT'), 'KR');
      expect(inferCountryCodeFromText('美国 洛杉矶 CN2'), 'US');
      expect(inferCountryCodeFromText('伦敦 专线 01'), 'GB');
      expect(inferCountryCodeFromText('London Premium 02'), 'GB');
      expect(inferCountryCodeFromText('Frankfurt Germany'), 'DE');
    });

    test('infers country code from uppercase ISO and airport codes', () {
      expect(inferCountryCodeFromText('[HKG] V1-Node-01'), 'HK');
      expect(inferCountryCodeFromText('NRT-02 Gaming'), 'JP');
      expect(inferCountryCodeFromText('LAX-US-01'), 'US');
      expect(inferCountryCodeFromText('LHR-01'), 'GB');
      expect(inferCountryCodeFromText('SIN-BGP-03'), 'SG');
    });

    test('returns null for unrecognized generic text', () {
      expect(inferCountryCodeFromText('Alpha node'), isNull);
      expect(inferCountryCodeFromText('剩余流量：128 GB'), isNull);
      expect(inferCountryCodeFromText('到期时间：2027-01-01'), isNull);
    });
  });

  group('NodeCountryResolver 3-tier pipeline', () {
    test(
        'resolves via Tier 3 (node name -> profile label fallback -> OTHER) when no server or exit IP is present',
        () {
      final resolver = NodeCountryResolver(
        resolveServerCountry: (_) async => null,
      );
      addTearDown(resolver.dispose);

      // Node name has country
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: '🇯🇵 日本 东京 01',
        ),
        'JP',
      );

      // Node name is generic, falls back to profile label ("伦敦" -> GB)
      expect(
        resolver.resolveCountryCode(
          profileId: 'p2',
          profileLabel: '伦敦',
          nodeName: 'VIP Line 01',
        ),
        'GB',
      );

      // Both node name and profile label are generic -> OTHER
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'VIP Line 01',
        ),
        kUnknownCountryCode,
      );
    });

    test(
        'resolves via Tier 2 (offline GeoIP server lookup) and overrides Tier 3 name inference',
        () async {
      final resolver = NodeCountryResolver(
        resolveServerCountry: (server) async {
          if (server == 'jp.node.internal') return 'JP';
          if (server == '1.2.3.4') return 'SG';
          return null;
        },
      );
      addTearDown(resolver.dispose);

      var notifications = 0;
      resolver
        ..addListener(() => notifications++)
        ..registerProxyMaps('p1', [
          {
            'name': 'Generic Node A',
            'type': 'ss',
            'server': 'jp.node.internal',
            'port': 443,
          },
          {
            'name': '🇺🇸 Mislabelled Node B',
            'type': 'vmess',
            'server': '1.2.3.4',
            'port': 443,
          },
        ]);

      // Wait for async server resolution queue to complete
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, greaterThan(0));
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Generic Node A',
        ),
        'JP',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: '🇺🇸 Mislabelled Node B',
        ),
        'SG',
      );
    });

    test(
        'resolves via Tier 1 (live exit IP detection) for active in-use node and guards against stale IP during node switch',
        () {
      final now = DateTime.utc(2026, 10, 22, 12);
      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isTesting: false,
          isLoading: false,
          ipInfo: IpInfo(ip: '203.0.113.10', countryCode: 'GB'),
        ),
      );
      addTearDown(detection.dispose);

      final resolver = NodeCountryResolver(
        detectionListenable: detection,
        resolveServerCountry: (_) async => null,
        clock: () => now,
      );
      addTearDown(resolver.dispose);

      // Sync active in-use node
      resolver.syncActiveNode(
        profileId: 'p1',
        nodeName: 'Relay Node 1',
        endpointKey: 'ep-1',
        isLiveActive: true,
      );

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Relay Node 1',
          endpointKey: 'ep-1',
          isLiveActive: true,
          inUse: true,
        ),
        'GB',
      );

      // Cached exit IP calibration persists even after switching to another node
      resolver
        ..markSwitchingNode()
        ..syncActiveNode(
          profileId: 'p1',
          nodeName: 'Relay Node 2',
          endpointKey: 'ep-2',
          isLiveActive: true,
        );

      // During the switch guard window (<1.5s) with the old IP still in detection,
      // Relay Node 2 must NOT inherit Relay Node 1's stale GB exit IP.
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Relay Node 2',
          endpointKey: 'ep-2',
          isLiveActive: true,
          inUse: true,
        ),
        kUnknownCountryCode,
      );

      // Relay Node 1 still remembers its calibrated GB country
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Relay Node 1',
          endpointKey: 'ep-1',
          isLiveActive: true,
          inUse: false,
        ),
        'GB',
      );

      // Once a new detection result arrives (isTesting: true -> false with new IP),
      // Relay Node 2 is calibrated to the new exit country.
      detection
        ..value = const NetworkDetectionState(
          isTesting: true,
          isLoading: true,
          ipInfo: null,
        )
        ..value = const NetworkDetectionState(
          isTesting: false,
          isLoading: false,
          ipInfo: IpInfo(ip: '198.51.100.20', countryCode: 'US'),
        );

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Relay Node 2',
          endpointKey: 'ep-2',
          isLiveActive: true,
          inUse: true,
        ),
        'US',
      );
    });
  });

  group('Formatting & Sorting', () {
    test('formats badges and chips in Chinese and English and sorts by count',
        () {
      expect(
        formatNodeCountryBadge('US', locale: const Locale('zh', 'CN')),
        '🇺🇸 美国',
      );
      expect(
        formatNodeCountryChipLabel('US', 5, locale: const Locale('zh', 'CN')),
        '🇺🇸 美国 (5)',
      );
      expect(
        formatNodeCountryChipLabel(
          kUnknownCountryCode,
          2,
          locale: const Locale('zh', 'CN'),
        ),
        '🌐 其他 (2)',
      );
      expect(
        formatNodeCountryChipLabel('GB', 3, locale: const Locale('en')),
        '🇬🇧 United Kingdom (3)',
      );

      final counts = {'GB': 2, kUnknownCountryCode: 9, 'US': 5, 'HK': 5};
      final sorted = sortCountryCodes(counts.keys, counts);
      // HK and US have count 5 (HK has higher priority than US), GB has 2, OTHER is always last
      expect(sorted, ['HK', 'US', 'GB', kUnknownCountryCode]);
    });
  });

  group('isPublicRoutableIp & cache invalidation hardening', () {
    test(
        'rejects TUN Fake-IP (198.18.0.0/15, fc00::/7), RFC1918, CGNAT, and bogon IPs while allowing public unicast IPs',
        () {
      for (final nonPublic in <String>[
        '0.0.0.0',
        '10.0.0.1',
        '100.64.0.1',
        '100.127.255.254',
        '127.0.0.1',
        '169.254.10.20',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.1',
        '198.18.0.42',
        '198.19.255.254',
        '198.51.100.10',
        '203.0.113.5',
        '224.0.0.1',
        '255.255.255.255',
        '::',
        '::1',
        'fc00::1234',
        'fd12:3456:789a::1',
        'fe80::1',
        'ff02::1',
        '2001:db8::1',
        '::ffff:198.18.0.5',
      ]) {
        expect(
          isPublicRoutableIp(InternetAddress(nonPublic)),
          isFalse,
          reason: 'Expected $nonPublic to be rejected as non-public',
        );
      }

      for (final publicIp in <String>[
        '1.1.1.1',
        '8.8.8.8',
        '100.63.255.254',
        '100.128.0.1',
        '172.15.255.254',
        '172.32.0.1',
        '198.17.255.254',
        '198.20.0.1',
        '2606:4700:4700::1111',
        '2001:4860:4860::8888',
        '::ffff:8.8.8.8',
      ]) {
        expect(
          isPublicRoutableIp(InternetAddress(publicIp)),
          isTrue,
          reason: 'Expected $publicIp to be accepted as public routable',
        );
      }
    });

    test(
        'domestic CN transit server yields to destination country in node/profile name',
        () async {
      final resolver = NodeCountryResolver(
        resolveServerCountry: (server) async =>
            server == 'gz-entry.transit.net' ? 'CN' : null,
      );
      addTearDown(resolver.dispose);

      resolver.registerProxyMaps('p1', [
        {
          'name': '广港 IEPL 01',
          'type': 'ss',
          'server': 'gz-entry.transit.net',
          'port': 443,
        },
        {
          'name': 'VIP 专线 02',
          'type': 'ss',
          'server': 'gz-entry.transit.net',
          'port': 444,
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: '广港 IEPL 01',
        ),
        'HK',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: '伦敦',
          nodeName: 'VIP 专线 02',
        ),
        'GB',
      );
    });

    test(
        'invalidateProfile clears stale per-profile mappings and transient lookup misses retry after cooldown',
        () async {
      var now = DateTime.utc(2026, 10, 23, 10);
      var coreReady = false;
      final resolver = NodeCountryResolver(
        clock: () => now,
        resolveServerCountry: (server) async {
          if (!coreReady) return null;
          if (server == 'sg.example.org') return 'SG';
          return null;
        },
      );
      addTearDown(resolver.dispose);

      // First registration before Core is ready -> null (transient miss)
      resolver.registerProxyMaps('p1', [
        {
          'name': 'Mystery Node',
          'type': 'ss',
          'server': '[SG.EXAMPLE.ORG]',
          'port': 443,
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Mystery Node',
        ),
        kUnknownCountryCode,
      );

      // Advance past 60s cooldown and mark Core ready -> retries cleanly and resolves SG
      coreReady = true;
      now = now.add(const Duration(seconds: 61));
      resolver.registerProxyMaps('p1', [
        {
          'name': 'Mystery Node',
          'type': 'ss',
          'server': 'sg.example.org',
          'port': 443,
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Mystery Node',
        ),
        'SG',
      );

      // Record exit calibration for p1 and p2, then invalidate p1 only
      resolver
        ..recordExitCountry(
          profileId: 'p1',
          proxyName: 'Mystery Node',
          countryCode: 'US',
        )
        ..recordExitCountry(
          profileId: 'p2',
          proxyName: 'Keep Node',
          countryCode: 'DE',
        )
        ..invalidateProfile('p1');

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Mystery Node',
        ),
        kUnknownCountryCode,
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p2',
          profileLabel: 'other',
          nodeName: 'Keep Node',
        ),
        'DE',
      );
    });
  });
}
