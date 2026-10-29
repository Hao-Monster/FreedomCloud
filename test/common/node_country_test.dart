import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flclashx/common/constant.dart' show maxLength;
import 'package:flclashx/common/fixed.dart';
import 'package:flclashx/common/node_country.dart';
import 'package:flclashx/common/request.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/state.dart';
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
      // Longest-keyword priority avoids substring prefix collisions (P2 #7)
      expect(inferCountryCodeFromText('印度尼西亚 01'), 'ID');
      expect(inferCountryCodeFromText('印尼 雅加达 02'), 'ID');
      expect(inferCountryCodeFromText('印度 孟买 01'), 'IN');
      expect(inferCountryCodeFromText('罗马尼亚 01'), 'RO');
      expect(inferCountryCodeFromText('意大利 罗马 01'), 'IT');
      expect(inferCountryCodeFromText('内蒙古 BGP 01'), 'CN');
      expect(inferCountryCodeFromText('蒙古 乌兰巴托 01'), 'MN');
      expect(inferCountryCodeFromText('North Korea Pyongyang'), 'KP');
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
        'invalidateProfile clears stale per-profile mappings and transient lookup misses retry immediately on next evaluation',
        () async {
      var calls = 0;
      var coreReady = false;
      final resolver = NodeCountryResolver(
        resolveServerCountry: (server) async {
          calls++;
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
      expect(calls, 1);
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'ikuuu',
          nodeName: 'Mystery Node',
        ),
        kUnknownCountryCode,
      );

      // Immediate re-evaluation (0s elapsed) once Core recovers retries cleanly (P2 #6)
      coreReady = true;
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

      expect(calls, 2);
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

    test(
        'same-name node changing server endpoint evicts stale exit country and resolves new endpoint (P2 #4)',
        () async {
      final resolver = NodeCountryResolver(
        resolveServerCountry: (server) async =>
            server == 'new.invalid' ? 'US' : 'GB',
      );
      addTearDown(resolver.dispose);

      resolver.registerProxyMaps('p1', [
        {'name': 'Node', 'type': 'ss', 'server': 'old.invalid', 'port': 443},
      ]);
      await Future<void>.delayed(Duration.zero);
      resolver.recordExitCountry(
        profileId: 'p1',
        proxyName: 'Node',
        countryCode: 'GB',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'Profile',
          nodeName: 'Node',
        ),
        'GB',
      );

      // Subscription update keeps node name 'Node' while moving server to new.invalid (US)
      resolver.registerProxyMaps('p1', [
        {'name': 'Node', 'type': 'ss', 'server': 'new.invalid', 'port': 443},
      ]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'Profile',
          nodeName: 'Node',
        ),
        'US',
      );
    });

    test(
        'rejects cross-epoch in-flight detection results and attributes multi-group exit via proven connection target (P2 #2 & #3)',
        () {
      var routingEpoch = 1;
      var completedGeneration = 0;
      int? completedRoutingEpoch;
      ConnectionOutboundTarget? observedTarget;
      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isTesting: false,
          isLoading: true,
          ipInfo: null,
        ),
      );
      addTearDown(detection.dispose);

      final resolver = NodeCountryResolver(
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: routingEpoch,
          completedGeneration: completedGeneration,
          completedRoutingEpoch: completedRoutingEpoch,
        ),
        resolveConnectionTarget: () => observedTarget,
        resolveServerCountry: (_) async => null,
      );
      addTearDown(resolver.dispose);

      // Node B is selected in epoch 2, while an older check started in epoch 1 finishes
      routingEpoch = 2;
      resolver.syncActiveNode(
        profileId: 'p1',
        nodeName: 'Node B',
        endpointKey: 'ep-b',
        isLiveActive: true,
      );
      completedGeneration = 1;
      completedRoutingEpoch = null; // mismatched epoch in DetectionState._checkIp
      detection.value = const NetworkDetectionState(
        isTesting: false,
        isLoading: false,
        ipInfo: IpInfo(ip: '198.51.100.77', countryCode: 'GB'),
      );

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'p1',
          nodeName: 'Node B',
          endpointKey: 'ep-b',
          isLiveActive: true,
          inUse: true,
        ),
        kUnknownCountryCode,
      );

      // Ambiguous multi-Selector state (_activeTarget == null), but Core Connection
      // proves 'US node' handled the exit check -> calibrates only 'US node', not 'Japan node'.
      resolver.syncActiveNode(
        profileId: null,
        nodeName: null,
        isLiveActive: false,
      );
      observedTarget = (
        profileId: 'p1',
        proxyName: 'US node',
        endpointKey: 'ep-us',
        isDirectOrReject: false,
      );
      completedGeneration = 2;
      completedRoutingEpoch = 2;
      detection.value = const NetworkDetectionState(
        isTesting: false,
        isLoading: false,
        ipInfo: IpInfo(ip: '203.0.113.55', countryCode: 'SG'),
      );

      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'p1',
          nodeName: 'US node',
          endpointKey: 'ep-us',
          isLiveActive: true,
          inUse: true,
        ),
        'SG',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'p1',
          nodeName: 'Japan node',
          endpointKey: 'ep-jp',
          isLiveActive: true,
          inUse: true,
        ),
        'JP',
      );
    });

    test(
        'shared endpointKey across distinct accounts retains own exit countries, port change evicts stale exit, and clearProfiles clears calibrations (R2 P2 #3)',
        () async {
      final resolver = NodeCountryResolver(
        resolveServerCountry: (server) async =>
            server == 'relay.invalid' ? 'US' : null,
      );
      addTearDown(resolver.dispose);

      // 1. Same host, different port evicts prior exit calibration
      final oldPort = {
        'name': 'Node',
        'type': 'ss',
        'server': 'relay.invalid',
        'port': 80,
      };
      final nextPort = {
        'name': 'Node',
        'type': 'ss',
        'server': 'relay.invalid',
        'port': 443,
      };
      resolver.registerProxyMaps('p', [oldPort]);
      await Future<void>.delayed(Duration.zero);
      resolver.recordExitCountry(
        profileId: 'p',
        proxyName: 'Node',
        countryCode: 'GB',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node',
        ),
        'GB',
      );

      resolver.registerProxyMaps('p', [nextPort]);
      await Future<void>.delayed(Duration.zero);
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node',
        ),
        'US',
      );

      // 2. Distinct SOCKS5 accounts sharing type/server/port retain independent exit countries
      final resolverShared = NodeCountryResolver(
        resolveServerCountry: (_) async => null,
      );
      addTearDown(resolverShared.dispose);
      final usMap = {
        'name': 'US account',
        'type': 'socks5',
        'server': 'relay.invalid',
        'port': 1080,
        'username': 'country-us',
      };
      final jpMap = {
        'name': 'JP account',
        'type': 'socks5',
        'server': 'relay.invalid',
        'port': 1080,
        'username': 'country-jp',
      };
      final usNode = catalogNodeFromMap(profileId: 'p', proxy: usMap);
      final jpNode = catalogNodeFromMap(profileId: 'p', proxy: jpMap);
      expect(usNode.endpointKey, jpNode.endpointKey);

      resolverShared.registerProxyMaps('p', [usMap, jpMap]);
      await Future<void>.delayed(Duration.zero);

      resolverShared.recordExitCountry(
        profileId: 'p',
        proxyName: 'US account',
        endpointKey: usNode.endpointKey,
        countryCode: 'US',
      );
      // Before JP account is calibrated, US account's calibration must not leak to JP account
      expect(
        resolverShared.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'JP account',
          endpointKey: jpNode.endpointKey,
        ),
        'JP',
      );

      resolverShared.recordExitCountry(
        profileId: 'p',
        proxyName: 'JP account',
        endpointKey: jpNode.endpointKey,
        countryCode: 'JP',
      );
      expect(
        resolverShared.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'US account',
          endpointKey: usNode.endpointKey,
        ),
        'US',
      );
      expect(
        resolverShared.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'JP account',
          endpointKey: jpNode.endpointKey,
        ),
        'JP',
      );

      // 3. clearProfiles and invalidateProfile remove exit calibrations even when endpointKey is supplied
      final nextNode = catalogNodeFromMap(profileId: 'p', proxy: nextPort);
      resolver.recordExitCountry(
        profileId: 'p',
        proxyName: 'Node',
        endpointKey: nextNode.endpointKey,
        countryCode: 'GB',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node',
          endpointKey: nextNode.endpointKey,
        ),
        'GB',
      );
      resolver
        ..clearProfiles()
        ..registerProxyMaps('p', [nextPort]);
      await Future<void>.delayed(Duration.zero);
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node',
          endpointKey: nextNode.endpointKey,
        ),
        'US',
      );
    });

    test(
        'later unrelated same-host connections never reuse an earlier IP check result (R2 P2 #2)',
        () {
      final probeStart = DateTime.utc(2026, 10, 23, 12);
      final probeDone = probeStart.add(const Duration(milliseconds: 300));
      var now = probeDone;

      Connection makeConn(String id, String leaf, DateTime at) => Connection(
            id: id,
            start: at,
            chains: [leaf, 'Balance'],
            metadata: const Metadata(
              uid: 0,
              network: 'tcp',
              sourceIP: '127.0.0.1',
              sourcePort: '12345',
              destinationIP: '203.0.113.1',
              destinationPort: '443',
              host: 'api-ipv4.ip.sb',
              process: 'FreedomCloud.exe',
              remoteDestination: '',
            ),
          );

      final connections = FixedList<Connection>(20)
        ..add(makeConn('the-ip-check', 'US node', probeStart));
      var completed = 0;
      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isLoading: true,
          isTesting: true,
          ipInfo: null,
        ),
      );
      addTearDown(detection.dispose);

      final resolver = NodeCountryResolver(
        clock: () => now,
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: 4,
          completedGeneration: completed,
          completedRoutingEpoch: 4,
        ),
        resolveServerCountry: (_) async => null,
        resolveConnectionTarget: () => resolveObservedConnectionTarget(
          activeId: 'p1',
          runtimeLive: true,
          effectiveMode: Mode.rule,
          allGroups: const [Group(name: 'Balance', type: GroupType.LoadBalance)],
          requests: connections,
          matchedHost: 'api-ipv4.ip.sb',
          checkStartedAt: probeStart,
          checkCompletedAt: probeDone,
          verifiedCatalog: null,
          cachedCatalogs: const {},
        ),
      );
      addTearDown(resolver.dispose);

      completed = 1;
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '198.51.100.10', countryCode: 'US'),
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'US node',
        ),
        'US',
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );

      // Ten minutes later an unrelated request hits the same host via Japan node
      now = probeStart.add(const Duration(minutes: 10));
      connections.add(makeConn('unrelated-later', 'Japan node', now));
      resolver.onConnectionsUpdated();
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );

      // Even if a check originally had no connection at completion time,
      // connections arriving after the 5-second grace deadline are ignored.
      final lateConnections = FixedList<Connection>(20);
      completed = 2;
      now = probeDone.add(const Duration(minutes: 20));
      final lateProbeStart = now;
      final lateProbeDone = now.add(const Duration(milliseconds: 200));
      final resolverLate = NodeCountryResolver(
        clock: () => now,
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: 4,
          completedGeneration: completed,
          completedRoutingEpoch: 4,
        ),
        resolveServerCountry: (_) async => null,
        resolveConnectionTarget: () => resolveObservedConnectionTarget(
          activeId: 'p1',
          runtimeLive: true,
          effectiveMode: Mode.rule,
          allGroups: const [Group(name: 'Balance', type: GroupType.LoadBalance)],
          requests: lateConnections,
          matchedHost: 'api-ipv4.ip.sb',
          checkStartedAt: lateProbeStart,
          checkCompletedAt: lateProbeDone,
          verifiedCatalog: null,
          cachedCatalogs: const {},
        ),
      );
      addTearDown(resolverLate.dispose);

      detection.value = const NetworkDetectionState(
        isLoading: true,
        isTesting: true,
        ipInfo: null,
      );
      completed = 3;
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '198.51.100.88', countryCode: 'DE'),
      );

      // Advance clock past the 5s grace window before any connection arrives
      now = lateProbeDone.add(const Duration(seconds: 10));
      lateConnections.add(makeConn('delayed-too-late', 'Japan node', lateProbeStart));
      resolverLate.onConnectionsUpdated();
      expect(
        resolverLate.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );
    });

    test(
        'rule-mode missing or ambiguous connection evidence never falls back to static Selector guess, and late DIRECT telemetry leaves proxy untouched (R3 P2 #1)',
        () {
      final probeStart = DateTime.utc(2026, 10, 23, 12);
      final probeDone = probeStart.add(const Duration(milliseconds: 200));
      var now = probeDone;

      Connection makeConn(String id, String leaf, DateTime at) => Connection(
            id: id,
            start: at,
            chains: [leaf, 'Primary'],
            metadata: const Metadata(
              uid: 0,
              network: 'tcp',
              sourceIP: '127.0.0.1',
              sourcePort: '12345',
              destinationIP: '203.0.113.1',
              destinationPort: '443',
              host: 'api-ipv4.ip.sb',
              process: 'FreedomCloud.exe',
              remoteDestination: '',
            ),
          );

      // 1. Late DIRECT telemetry arriving after HTTP IpInfo does not mislabel Japan node
      final directConnections = FixedList<Connection>(20);
      var completed = 0;
      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isLoading: true,
          isTesting: true,
          ipInfo: null,
        ),
      );
      addTearDown(detection.dispose);

      ConnectionEvidenceEvaluation evaluateDirect() =>
          evaluateObservedConnectionEvidence(
            activeId: 'p1',
            runtimeLive: true,
            effectiveMode: Mode.rule,
            allGroups: const [
              Group(
                name: 'Primary',
                type: GroupType.Selector,
                hidden: false,
                now: 'Japan node',
              ),
            ],
            requests: directConnections,
            matchedHost: 'api-ipv4.ip.sb',
            checkStartedAt: probeStart,
            checkCompletedAt: probeDone,
            verifiedCatalog: null,
            cachedCatalogs: const {},
          );

      final resolverDirect = NodeCountryResolver(
        clock: () => now,
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: 4,
          completedGeneration: completed,
          completedRoutingEpoch: 4,
        ),
        isDetectionProxyEligible: () => true,
        resolveServerCountry: (_) async => null,
        evaluateConnectionEvidence: evaluateDirect,
      );
      addTearDown(resolverDirect.dispose);

      // Even if a caller supplies a non-global static node, rule mode waits for telemetry
      resolverDirect.syncActiveNode(
        profileId: 'p1',
        nodeName: 'Japan node',
        isLiveActive: true,
      );
      expect(evaluateDirect().status, ConnectionEvidenceStatus.missing);

      completed = 1;
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '203.0.113.99', countryCode: 'CN'),
      );
      expect(
        resolverDirect.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );

      // Core's 4-second telemetry poll arrives with DIRECT outbound
      now = probeDone.add(const Duration(seconds: 3));
      directConnections.add(makeConn('direct-probe', 'DIRECT', probeStart));
      expect(evaluateDirect().status, ConnectionEvidenceStatus.matched);
      expect(evaluateDirect().target!.isDirectOrReject, isTrue);
      resolverDirect.onConnectionsUpdated();
      expect(
        resolverDirect.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );

      // 2. Ambiguous observed leaves reject static fallback (even under global static target)
      //    and immediately finalize so later ring-buffer eviction cannot reinterpret survivor.
      final ambigConnections = FixedList<Connection>(maxLength)
        ..add(makeConn('probe-us', 'US node', probeStart))
        ..add(makeConn('probe-jp', 'Japan node', probeStart));
      var ambigCompleted = 0;
      final ambigDetection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isLoading: true,
          isTesting: true,
          ipInfo: null,
        ),
      );
      addTearDown(ambigDetection.dispose);

      ConnectionEvidenceEvaluation evaluateAmbig() =>
          evaluateObservedConnectionEvidence(
            activeId: 'p1',
            runtimeLive: true,
            effectiveMode: Mode.rule,
            allGroups: const [
              Group(
                name: 'Primary',
                type: GroupType.Selector,
                hidden: false,
                now: 'Japan node',
              ),
            ],
            requests: ambigConnections,
            matchedHost: 'api-ipv4.ip.sb',
            checkStartedAt: probeStart,
            checkCompletedAt: probeDone,
            verifiedCatalog: null,
            cachedCatalogs: const {},
          );
      expect(evaluateAmbig().status, ConnectionEvidenceStatus.ambiguous);

      final resolverAmbig = NodeCountryResolver(
        clock: () => now,
        detectionListenable: ambigDetection,
        readDetectionMeta: () => (
          routingEpoch: 4,
          completedGeneration: ambigCompleted,
          completedRoutingEpoch: 4,
        ),
        isDetectionProxyEligible: () => true,
        resolveServerCountry: (_) async => null,
        evaluateConnectionEvidence: evaluateAmbig,
      );
      addTearDown(resolverAmbig.dispose);

      resolverAmbig.syncActiveNode(
        profileId: 'p1',
        nodeName: 'Japan node',
        isLiveActive: true,
        isGlobalStaticTarget: true,
      );
      ambigCompleted = 1;
      ambigDetection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '198.51.100.10', countryCode: 'US'),
      );
      expect(
        resolverAmbig.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );

      // Evict 'US node' leaving only 'Japan node' inside grace window: still finalized!
      for (var i = 0; i < maxLength - 1; i++) {
        ambigConnections.add(
          Connection(
            id: 'fill-$i',
            start: probeDone.add(const Duration(seconds: 2)),
            chains: const ['US node', 'Primary'],
            metadata: const Metadata(
              uid: 0,
              network: 'tcp',
              sourceIP: '127.0.0.1',
              sourcePort: '12345',
              destinationIP: '1.1.1.1',
              destinationPort: '443',
              host: 'other.example.invalid',
              process: 'FreedomCloud.exe',
              remoteDestination: '',
            ),
          ),
        );
      }
      expect(evaluateAmbig().status, ConnectionEvidenceStatus.matched);
      expect(evaluateAmbig().target?.proxyName, 'Japan node');
      resolverAmbig
        ..onConnectionsUpdated()
        ..syncActiveNode(
          profileId: 'p1',
          nodeName: 'Japan node',
          isLiveActive: true,
          isGlobalStaticTarget: true,
        );
      expect(
        resolverAmbig.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );
    });

    test(
        'syncActiveNode never replays a consumed or expired probe after FixedList evicts original connection (R3 P2 #2)',
        () {
      final started = DateTime.utc(2026, 10, 23, 12);
      final done = started.add(const Duration(milliseconds: 300));
      var now = done;
      var generation = 0;

      Connection conn(
        String id,
        String leaf,
        DateTime at, {
        String host = 'api-ipv4.ip.sb',
      }) =>
          Connection(
            id: id,
            start: at,
            chains: [leaf, 'Primary'],
            metadata: Metadata(
              uid: 0,
              network: 'tcp',
              sourceIP: '127.0.0.1',
              sourcePort: '12345',
              destinationIP: '1.1.1.1',
              destinationPort: '443',
              host: host,
              process: 'FreedomCloud.exe',
              remoteDestination: '',
            ),
          );

      const allGroups = [
        Group(
          name: 'Primary',
          type: GroupType.Selector,
          now: 'Node A',
          all: [
            Proxy(name: 'Node A', type: 'Socks5'),
            Proxy(name: 'Node B', type: 'Socks5'),
          ],
        ),
      ];
      final history = FixedList<Connection>(maxLength)
        ..add(conn('probe', 'Node A', started));

      ConnectionOutboundTarget? observed() => resolveObservedConnectionTarget(
            activeId: 'p',
            runtimeLive: true,
            effectiveMode: Mode.rule,
            allGroups: allGroups,
            requests: history,
            matchedHost: 'api-ipv4.ip.sb',
            checkStartedAt: started,
            checkCompletedAt: done,
            verifiedCatalog: null,
            cachedCatalogs: const {},
          );

      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isLoading: true,
          isTesting: true,
          ipInfo: null,
        ),
      );
      addTearDown(detection.dispose);

      final resolver = NodeCountryResolver(
        resolveServerCountry: (_) async => null,
        clock: () => now,
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: 4,
          completedGeneration: generation,
          completedRoutingEpoch: 4,
        ),
        resolveConnectionTarget: observed,
      );
      addTearDown(resolver.dispose);

      resolver.syncActiveNode(profileId: 'p', nodeName: 'Node A');
      generation = 1;
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '8.8.8.8', countryCode: 'US'),
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node A',
        ),
        'US',
      );

      // Concurrent browser request via Node B inside [started - 2s, done + 1s]
      history.add(
        conn(
          'unrelated-browser',
          'Node B',
          done.add(const Duration(milliseconds: 500)),
        ),
      );
      expect(observed(), isNull);

      // Bounded ring buffer evicts Node A, retaining Node B
      for (var i = 0; i < maxLength - 1; i++) {
        history.add(
          conn(
            'traffic-$i',
            'Node A',
            done.add(Duration(seconds: 10 + i)),
            host: 'example.invalid',
          ),
        );
      }
      now = done.add(const Duration(minutes: 10));
      expect(observed()?.proxyName, 'Node B');

      resolver
        ..onConnectionsUpdated()
        ..syncActiveNode(profileId: 'p', nodeName: 'Node A')
        ..syncActiveNode(
          profileId: 'p',
          nodeName: 'Node A',
          isGlobalStaticTarget: true,
        );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node B',
        ),
        kUnknownCountryCode,
      );
    });

    test(
        'invalidating a rule-mode profile or replacing its endpoint revokes pending probe before late telemetry arrives, without cancelling unrelated profiles (R4 P2 #1)',
        () async {
      final started = DateTime.utc(2026, 10, 24, 12);
      final done = started.add(const Duration(milliseconds: 200));
      var now = done;
      var gen = 0;
      final oldMap = {
        'name': 'Node A',
        'type': 'ss',
        'server': 'old.invalid',
        'port': 443,
      };
      final newMap = {
        'name': 'Node A',
        'type': 'ss',
        'server': 'new.invalid',
        'port': 443,
      };
      final oldNode = catalogNodeFromMap(profileId: 'p', proxy: oldMap);
      final newNode = catalogNodeFromMap(profileId: 'p', proxy: newMap);
      expect(oldNode.endpointKey, isNot(newNode.endpointKey));

      var cached = {
        'p': ProfileCatalog(
          profileId: 'p',
          fingerprint: 'old',
          status: ProfileCatalogStatus.ready,
          nodes: [oldNode],
        ),
      };
      final requests = FixedList<Connection>(150);
      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isLoading: true,
          isTesting: true,
          ipInfo: null,
        ),
      );
      addTearDown(detection.dispose);

      ConnectionEvidenceEvaluation evaluate() =>
          evaluateObservedConnectionEvidence(
            activeId: 'p',
            runtimeLive: true,
            effectiveMode: Mode.rule,
            allGroups: const [
              Group(name: 'Primary', type: GroupType.Selector, now: 'Node A'),
            ],
            requests: requests,
            matchedHost: 'api-ipv4.ip.sb',
            checkStartedAt: started,
            checkCompletedAt: done,
            verifiedCatalog: null,
            cachedCatalogs: cached,
          );

      final resolver = NodeCountryResolver(
        resolveServerCountry: (_) async => null,
        clock: () => now,
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: 1,
          completedGeneration: gen,
          completedRoutingEpoch: 1,
        ),
        readCheckCompletedAt: () => done,
        evaluateConnectionEvidence: evaluate,
      );
      addTearDown(resolver.dispose);

      resolver.registerProxyMaps('p', [oldMap]);
      gen = 1;
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '8.8.8.8', countryCode: 'US'),
      );
      expect(evaluate().status, ConnectionEvidenceStatus.missing);

      // Subscription update invalidates profile 'p' and registers replaced endpoint
      resolver
        ..invalidateProfile('p')
        ..registerProxyMaps('p', [newMap]);
      cached = {
        'p': ProfileCatalog(
          profileId: 'p',
          fingerprint: 'new',
          status: ProfileCatalogStatus.ready,
          nodes: [newNode],
        ),
      };

      now = done.add(const Duration(seconds: 2));
      requests.add(
        Connection(
          id: 'old-probe',
          start: started,
          chains: const ['Node A', 'Primary'],
          metadata: const Metadata(
            uid: 0,
            network: 'tcp',
            sourceIP: '127.0.0.1',
            sourcePort: '12345',
            destinationIP: '1.1.1.1',
            destinationPort: '443',
            host: 'api-ipv4.ip.sb',
            process: 'FreedomCloud.exe',
            remoteDestination: '',
          ),
        ),
      );
      expect(evaluate().target?.endpointKey, newNode.endpointKey);
      resolver.onConnectionsUpdated();
      expect(
        resolver.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node A',
          endpointKey: newNode.endpointKey,
        ),
        kUnknownCountryCode,
      );

      // Invalidating an unrelated inactive profile 'other' must not cancel active 'p'
      final requests2 = FixedList<Connection>(150);
      now = done;
      detection.value = const NetworkDetectionState(
        isLoading: true,
        isTesting: true,
        ipInfo: null,
      );
      gen = 2;
      final resolverUnrelated = NodeCountryResolver(
        resolveServerCountry: (_) async => null,
        clock: () => now,
        detectionListenable: detection,
        readDetectionMeta: () => (
          routingEpoch: 1,
          completedGeneration: gen,
          completedRoutingEpoch: 1,
        ),
        readCheckCompletedAt: () => done,
        evaluateConnectionEvidence: () => evaluateObservedConnectionEvidence(
          activeId: 'p',
          runtimeLive: true,
          effectiveMode: Mode.rule,
          allGroups: const [
            Group(name: 'Primary', type: GroupType.Selector, now: 'Node A'),
          ],
          requests: requests2,
          matchedHost: 'api-ipv4.ip.sb',
          checkStartedAt: started,
          checkCompletedAt: done,
          verifiedCatalog: null,
          cachedCatalogs: cached,
        ),
      );
      addTearDown(resolverUnrelated.dispose);
      resolverUnrelated.registerProxyMaps('p', [newMap]);
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '9.9.9.9', countryCode: 'SG'),
      );
      resolverUnrelated.invalidateProfile('other');
      now = done.add(const Duration(seconds: 2));
      requests2.add(
        Connection(
          id: 'p-probe',
          start: started,
          chains: const ['Node A', 'Primary'],
          metadata: const Metadata(
            uid: 0,
            network: 'tcp',
            sourceIP: '127.0.0.1',
            sourcePort: '54321',
            destinationIP: '1.1.1.1',
            destinationPort: '443',
            host: 'api-ipv4.ip.sb',
            process: 'FreedomCloud.exe',
            remoteDestination: '',
          ),
        ),
      );
      resolverUnrelated.onConnectionsUpdated();
      expect(
        resolverUnrelated.resolveCountryCode(
          profileId: 'p',
          profileLabel: null,
          nodeName: 'Node A',
          endpointKey: newNode.endpointKey,
        ),
        'SG',
      );
    });

    for (final coldAge in [
      const Duration(seconds: 1),
      const Duration(seconds: 10),
    ]) {
      test(
          'initial cold seed obeys connection evidence and 5s deadline after automatic URLTest failover at ${coldAge.inSeconds}s (R4 P2 #2)',
          () {
        final started = DateTime.utc(2026, 10, 24, 12);
        final completed = started.add(const Duration(milliseconds: 300));
        final now = completed.add(coldAge);
        final history = FixedList<Connection>(150)
          ..add(
            Connection(
              id: 'us-probe',
              start: started,
              chains: const ['US node', 'Auto', 'GLOBAL'],
              metadata: const Metadata(
                uid: 0,
                network: 'tcp',
                sourceIP: '127.0.0.1',
                sourcePort: '12345',
                destinationIP: '203.0.113.1',
                destinationPort: '443',
                host: 'api-ipv4.ip.sb',
                process: 'FreedomCloud.exe',
                remoteDestination: '',
              ),
            ),
          );
        const groups = [
          Group(name: 'GLOBAL', type: GroupType.Selector, now: 'Auto'),
          Group(name: 'Auto', type: GroupType.URLTest, now: 'Japan node'),
        ];
        ConnectionEvidenceEvaluation evidence() =>
            evaluateObservedConnectionEvidence(
              activeId: 'p',
              runtimeLive: true,
              effectiveMode: Mode.global,
              allGroups: groups,
              requests: history,
              matchedHost: 'api-ipv4.ip.sb',
              checkStartedAt: started,
              checkCompletedAt: completed,
              verifiedCatalog: null,
              cachedCatalogs: const {},
            );
        expect(evidence().status, ConnectionEvidenceStatus.matched);
        expect(evidence().target!.proxyName, 'US node');

        final detection = ValueNotifier<NetworkDetectionState>(
          const NetworkDetectionState(
            isLoading: false,
            isTesting: false,
            ipInfo: IpInfo(ip: '203.0.113.2', countryCode: 'US'),
          ),
        );
        addTearDown(detection.dispose);

        final resolver = NodeCountryResolver(
          detectionListenable: detection,
          clock: () => now,
          readDetectionMeta: () => (
            routingEpoch: 4,
            completedGeneration: 1,
            completedRoutingEpoch: 4,
          ),
          readCheckCompletedAt: () => completed,
          isDetectionProxyEligible: () => true,
          evaluateConnectionEvidence: evidence,
          resolveServerCountry: (_) async => null,
        );
        addTearDown(resolver.dispose);

        resolver
          ..syncActiveNode(
            profileId: 'p',
            nodeName: 'Japan node',
            isGlobalStaticTarget: true,
            notify: false,
          )
          ..seedInitialDetection(notify: false);
        expect(
          resolver.resolveCountryCode(
            profileId: 'p',
            profileLabel: null,
            nodeName: 'Japan node',
          ),
          'JP',
          reason:
              'cold seed must never overwrite current Japan leaf with old US probe',
        );
      });
    }

    test(
        'foreign process connections and mismatched socket sourcePorts never prove probe ownership, while Request.checkIpWithHost records exact socket sourcePort (R4 P2 #3)',
        () async {
      final start = DateTime.utc(2026, 10, 24, 12);
      final done = start.add(const Duration(milliseconds: 250));

      // 1. Foreign process (chrome.exe) to same host/window is rejected
      final connections = FixedList<Connection>(20)
        ..add(
          Connection(
            id: 'chrome-not-the-probe',
            start: start.add(const Duration(milliseconds: 100)),
            chains: const ['Japan node', 'Primary'],
            metadata: const Metadata(
              uid: 0,
              network: 'tcp',
              sourceIP: '127.0.0.1',
              sourcePort: '52777',
              destinationIP: '203.0.113.1',
              destinationPort: '443',
              host: 'api-ipv4.ip.sb',
              process: 'chrome.exe',
              processPath:
                  r'C:\Program Files\Google\Chrome\Application\chrome.exe',
              remoteDestination: '',
            ),
          ),
        );

      ConnectionEvidenceEvaluation evaluateForeign() =>
          evaluateObservedConnectionEvidence(
            activeId: 'p1',
            runtimeLive: true,
            effectiveMode: Mode.rule,
            allGroups: const [
              Group(name: 'Primary', type: GroupType.Selector),
            ],
            requests: connections,
            matchedHost: 'api-ipv4.ip.sb',
            checkStartedAt: start,
            checkCompletedAt: done,
            verifiedCatalog: null,
            cachedCatalogs: const {},
          );
      expect(evaluateForeign().status, ConnectionEvidenceStatus.missing);

      var completed = 0;
      final detection = ValueNotifier<NetworkDetectionState>(
        const NetworkDetectionState(
          isLoading: true,
          isTesting: true,
          ipInfo: null,
        ),
      );
      addTearDown(detection.dispose);
      final resolver = NodeCountryResolver(
        detectionListenable: detection,
        clock: () => done.add(const Duration(seconds: 1)),
        readCheckCompletedAt: () => done,
        readDetectionMeta: () => (
          routingEpoch: 4,
          completedGeneration: completed,
          completedRoutingEpoch: 4,
        ),
        isDetectionProxyEligible: () => true,
        evaluateConnectionEvidence: evaluateForeign,
        resolveServerCountry: (_) async => null,
      );
      addTearDown(resolver.dispose);
      completed = 1;
      detection.value = const NetworkDetectionState(
        isLoading: false,
        isTesting: false,
        ipInfo: IpInfo(ip: '203.0.113.99', countryCode: 'CN'),
      );
      expect(
        resolver.resolveCountryCode(
          profileId: 'p1',
          profileLabel: 'generic',
          nodeName: 'Japan node',
        ),
        'JP',
      );

      // 2. Same app process on a different TCP sourcePort is rejected when probeSourcePorts is bound;
      //    matching probeSourcePorts succeeds even when FindProcessMode.off leaves process empty.
      final socketConnections = FixedList<Connection>(20)
        ..add(
          Connection(
            id: 'other-in-app-socket',
            start: start.add(const Duration(milliseconds: 50)),
            chains: const ['Japan node', 'Primary'],
            metadata: const Metadata(
              uid: 0,
              network: 'tcp',
              sourceIP: '127.0.0.1',
              sourcePort: '59999',
              destinationIP: '203.0.113.1',
              destinationPort: '443',
              host: 'api-ipv4.ip.sb',
              process: 'FreedomCloud.exe',
              remoteDestination: '',
            ),
          ),
        );
      expect(
        evaluateObservedConnectionEvidence(
          activeId: 'p1',
          runtimeLive: true,
          effectiveMode: Mode.rule,
          allGroups: const [Group(name: 'Primary', type: GroupType.Selector)],
          requests: socketConnections,
          matchedHost: 'api-ipv4.ip.sb',
          checkStartedAt: start,
          checkCompletedAt: done,
          probeSourcePorts: const {'54321'},
          verifiedCatalog: null,
          cachedCatalogs: const {},
        ).status,
        ConnectionEvidenceStatus.missing,
      );

      socketConnections.add(
        Connection(
          id: 'actual-probe-find-process-off',
          start: start.add(const Duration(milliseconds: 80)),
          chains: const ['US node', 'Primary'],
          metadata: const Metadata(
            uid: 0,
            network: 'tcp',
            sourceIP: '127.0.0.1',
            sourcePort: '54321',
            destinationIP: '203.0.113.1',
            destinationPort: '443',
            host: 'api-ipv4.ip.sb',
            process: '',
            remoteDestination: '',
          ),
        ),
      );
      final socketMatched = evaluateObservedConnectionEvidence(
        activeId: 'p1',
        runtimeLive: true,
        effectiveMode: Mode.rule,
        allGroups: const [Group(name: 'Primary', type: GroupType.Selector)],
        requests: socketConnections,
        matchedHost: 'api-ipv4.ip.sb',
        checkStartedAt: start,
        checkCompletedAt: done,
        probeSourcePorts: const {'54321'},
        verifiedCatalog: null,
        cachedCatalogs: const {},
      );
      expect(socketMatched.status, ConnectionEvidenceStatus.matched);
      expect(socketMatched.target?.proxyName, 'US node');

      // 3. Real loopback TCP server verifies Request.checkIpWithHost captures exact ephemeral client port
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      int? serverObservedClientPort;
      server.listen((req) async {
        serverObservedClientPort = req.connectionInfo?.remotePort;
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({'ip': '198.51.100.42', 'country_code': 'SG'}),
        );
        await req.response.close();
      });

      final localRequest = Request(
        ipInfoSources: {
          'http://127.0.0.1:${server.port}/geoip': IpInfo.fromIpSbJson,
        },
      );
      final probeRes = await localRequest.checkIpWithHost(
        keepAliveHold: Duration.zero,
      );
      expect(probeRes.isError, isFalse);
      expect(probeRes.data, isNotNull);
      expect(probeRes.data!.ipInfo.countryCode, 'SG');
      expect(serverObservedClientPort, isNotNull);
      expect(
        probeRes.data!.sourcePorts,
        contains(serverObservedClientPort.toString()),
      );
    });

    test(
      'R5: stalled direct and CONNECT HTTPS TLS handshakes close remote sockets promptly on timeout or mid-ClientHello cancel',
      () async {
        void resetGlobalProxyState({int? proxyPort}) {
          globalState
            ..config = Config(
              themeProps: defaultThemeProps,
              patchClashConfig: ClashConfig(
                globalUa: 'FlClashX/test',
                mixedPort: proxyPort ?? 0,
              ),
            )
            ..appState = AppState(
              viewSize: Size.zero,
              version: 1,
              runTime: proxyPort == null ? null : 123,
              requests: FixedList(2),
              logs: FixedList(2),
              traffics: FixedList(2),
              totalTraffic: Traffic(),
            );
        }

        addTearDown(resetGlobalProxyState);
        resetGlobalProxyState();

        // 1. Direct HTTPS: peer accepts TCP, receives TLS ClientHello (0x16), and stalls.
        //    Timeout closes the stalled remote TCP socket promptly and falls back to HTTP.
        final stalledDirect = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(stalledDirect.close);
        final directClientHelloSeen = Completer<void>();
        final directClosed = Completer<void>();
        final directSockets = <Socket>[];
        addTearDown(() {
          for (final s in directSockets) {
            s.destroy();
          }
        });
        stalledDirect.listen((socket) {
          directSockets.add(socket);
          socket.listen(
            (data) {
              if (data.isNotEmpty &&
                  data.first == 0x16 &&
                  !directClientHelloSeen.isCompleted) {
                directClientHelloSeen.complete();
              }
            },
            onError: (_) {
              if (!directClosed.isCompleted) {
                directClosed.complete();
              }
            },
            onDone: () {
              if (!directClosed.isCompleted) {
                directClosed.complete();
              }
            },
          );
        });

        final healthyHttp = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => healthyHttp.close(force: true));
        int? healthyPort;
        healthyHttp.listen((req) async {
          healthyPort = req.connectionInfo?.remotePort;
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({'ip': '198.51.100.43', 'country_code': 'SG'}),
            );
          await req.response.close();
        });

        final directFallbackRequest = Request(
          ipInfoSources: {
            'https://127.0.0.1:${stalledDirect.port}/geoip':
                IpInfo.fromIpSbJson,
            'http://127.0.0.1:${healthyHttp.port}/geoip': IpInfo.fromIpSbJson,
          },
        );
        final directRes = await directFallbackRequest.checkIpWithHost(
          keepAliveHold: Duration.zero,
          connectTimeout: const Duration(milliseconds: 300),
        );
        await directClientHelloSeen.future.timeout(const Duration(seconds: 1));
        await directClosed.future.timeout(const Duration(seconds: 1));
        expect(directRes.isError, isFalse);
        expect(directRes.data, isNotNull);
        expect(directRes.data!.ipInfo.countryCode, 'SG');
        expect(directRes.data!.sourcePorts, {'$healthyPort'});

        // 2. Mid-ClientHello CancelToken cancellation (past RawSocket connecting phase):
        //    Wait until server actually observes ClientHello bytes + 30ms before cancelling.
        final stalledCancel = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(stalledCancel.close);
        final cancelClientHelloSeen = Completer<void>();
        final cancelClosed = Completer<void>();
        final cancelSockets = <Socket>[];
        addTearDown(() {
          for (final s in cancelSockets) {
            s.destroy();
          }
        });
        stalledCancel.listen((socket) {
          cancelSockets.add(socket);
          socket.listen(
            (data) {
              if (data.isNotEmpty &&
                  data.first == 0x16 &&
                  !cancelClientHelloSeen.isCompleted) {
                cancelClientHelloSeen.complete();
              }
            },
            onError: (_) {
              if (!cancelClosed.isCompleted) {
                cancelClosed.complete();
              }
            },
            onDone: () {
              if (!cancelClosed.isCompleted) {
                cancelClosed.complete();
              }
            },
          );
        });

        final cancelToken = CancelToken();
        final cancelRequest = Request(
          ipInfoSources: {
            'https://127.0.0.1:${stalledCancel.port}/geoip':
                IpInfo.fromIpSbJson,
          },
        );
        final pendingCancel = cancelRequest.checkIpWithHost(
          cancelToken: cancelToken,
          keepAliveHold: Duration.zero,
        );
        await cancelClientHelloSeen.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        cancelToken.cancel('cancel mid-TLS');
        final cancelRes = await pendingCancel.timeout(
          const Duration(seconds: 2),
        );
        expect(cancelRes.isError, isTrue);
        await cancelClosed.future.timeout(const Duration(seconds: 1));

        // 3. Proxied CONNECT HTTPS: tunnel establishes (200 Connection Established),
        //    upstream stalls during TLS handshake -> timeout closes proxy tunnel socket promptly.
        final stalledUpstream = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(stalledUpstream.close);
        final proxyTunnelClientHelloSeen = Completer<void>();
        final proxySockets = <Socket>[];
        addTearDown(() {
          for (final s in proxySockets) {
            s.destroy();
          }
        });
        stalledUpstream.listen((socket) {
          proxySockets.add(socket);
          socket.listen(
            (data) {
              if (data.isNotEmpty &&
                  data.first == 0x16 &&
                  !proxyTunnelClientHelloSeen.isCompleted) {
                proxyTunnelClientHelloSeen.complete();
              }
            },
            onError: (_) {},
            onDone: () {},
          );
        });

        final proxyServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => proxyServer.close(force: true));
        final proxyTunnelClosed = Completer<void>();
        int? proxiedHealthyPort;
        proxyServer.listen((req) async {
          if (req.method == 'CONNECT') {
            final peer = await req.response.detachSocket(writeHeaders: false);
            proxySockets.add(peer);
            final upstream = await Socket.connect(
              InternetAddress.loopbackIPv4,
              stalledUpstream.port,
            );
            proxySockets.add(upstream);
            peer
              ..write('HTTP/1.1 200 Connection Established\r\n\r\n')
              ..listen(
                upstream.add,
                onError: (_) {
                  upstream.destroy();
                  if (!proxyTunnelClosed.isCompleted) {
                    proxyTunnelClosed.complete();
                  }
                },
                onDone: () {
                  upstream.destroy();
                  if (!proxyTunnelClosed.isCompleted) {
                    proxyTunnelClosed.complete();
                  }
                },
              );
            upstream.listen(
              peer.add,
              onError: (_) => peer.destroy(),
              onDone: peer.destroy,
            );
            return;
          }
          proxiedHealthyPort = req.connectionInfo?.remotePort;
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({'ip': '198.51.100.44', 'country_code': 'JP'}),
            );
          await req.response.close();
        });

        resetGlobalProxyState(proxyPort: proxyServer.port);
        final proxiedRequest = Request(
          ipInfoSources: {
            'https://localhost:${stalledUpstream.port}/geoip':
                IpInfo.fromIpSbJson,
            'http://example.invalid/geoip': IpInfo.fromIpSbJson,
          },
        );
        final proxiedRes = await proxiedRequest.checkIpWithHost(
          keepAliveHold: Duration.zero,
          connectTimeout: const Duration(milliseconds: 300),
        );
        await proxyTunnelClientHelloSeen.future.timeout(
          const Duration(seconds: 1),
        );
        await proxyTunnelClosed.future.timeout(const Duration(seconds: 1));
        expect(proxiedRes.isError, isFalse);
        expect(proxiedRes.data, isNotNull);
        expect(proxiedRes.data!.ipInfo.countryCode, 'JP');
        expect(proxiedRes.data!.sourcePorts, {'$proxiedHealthyPort'});
        expect(proxiedRes.data!.routedViaClash, isTrue);
      },
    );
  });
}
