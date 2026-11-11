import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flclashx/application.dart';
import 'package:flclashx/common/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows adapter notifications keep existing Core connections', () {
    for (final results in [
      [ConnectivityResult.ethernet],
      [ConnectivityResult.ethernet, ConnectivityResult.vpn],
      [ConnectivityResult.none],
      [ConnectivityResult.wifi],
    ]) {
      expect(
        shouldCloseConnectionsOnNetworkChange(results, isWindows: true),
        isFalse,
      );
    }
  });

  test('other platforms retain the existing VPN guard', () {
    expect(
      shouldCloseConnectionsOnNetworkChange(
        [ConnectivityResult.wifi],
        isWindows: false,
      ),
      isTrue,
    );
    expect(
      shouldCloseConnectionsOnNetworkChange(
        [ConnectivityResult.wifi, ConnectivityResult.vpn],
        isWindows: false,
      ),
      isFalse,
    );
  });

  test('selectPreferredPhysicalLocalIp ignores TUN and link-local addresses', () {
    expect(
      selectPreferredPhysicalLocalIp([
        (
          name: 'FlClashX',
          addresses: [
            InternetAddress('198.18.0.1'),
            InternetAddress('fdfe:dcba:9876::1'),
          ],
        ),
        (
          name: 'WLAN',
          addresses: [
            InternetAddress('169.254.22.11'),
            InternetAddress('fe80::abcd'),
          ],
        ),
      ]),
      isEmpty,
    );

    expect(
      selectPreferredPhysicalLocalIp([
        (
          name: 'FlClashX',
          addresses: [InternetAddress('198.18.0.1')],
        ),
        (
          name: '以太网',
          addresses: [InternetAddress('192.168.1.50')],
        ),
      ]),
      '192.168.1.50',
    );
  });

  test('Windows coordinator ignores VPN adapter noise on unchanged physical IP', () async {
    var resets = 0;
    var closes = 0;
    String? latestIp;
    final coordinator = NetworkChangeCoordinator(
      isWindows: true,
      readLocalIp: () async => '172.23.104.177',
      resetConnections: () => resets++,
      closeConnections: () => closes++,
      onLocalIpChanged: (ip) => latestIp = ip,
      probeDelays: const [Duration.zero],
    );

    await coordinator.handleConnectivityChanged(
      [ConnectivityResult.wifi, ConnectivityResult.vpn],
    );
    await coordinator.handleConnectivityChanged(
      [ConnectivityResult.wifi],
    );
    await coordinator.handleConnectivityChanged(
      [ConnectivityResult.wifi, ConnectivityResult.vpn],
    );

    expect(resets, 0);
    expect(closes, 0);
    expect(latestIp, '172.23.104.177');
    coordinator.dispose();
  });

  test('Windows coordinator resets Core when WiFi hotspot switch changes LAN IP after DHCP delay', () async {
    var resets = 0;
    var closes = 0;
    final observedIps = <String?>[];
    final scriptedIps = <String>[
      '172.20.10.2', // initial WiFi (APhone19)
      '', // mid-switch DHCP pending on iPhone15ProMax
      '172.23.104.177', // DHCP completed on iPhone15ProMax
      '172.23.104.177', // subsequent NCSI notification on same hotspot
    ];
    var cursor = 0;

    final coordinator = NetworkChangeCoordinator(
      isWindows: true,
      readLocalIp: () async =>
          scriptedIps[cursor < scriptedIps.length ? cursor++ : scriptedIps.length - 1],
      resetConnections: () => resets++,
      closeConnections: () => closes++,
      onLocalIpChanged: observedIps.add,
      probeDelays: const [
        Duration.zero,
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ],
    );

    // 1. App startup baseline on APhone19: no reset.
    await coordinator.handleConnectivityChanged([ConnectivityResult.wifi]);
    expect(resets, 0);

    // 2. Switch to iPhone15ProMax: first probe sees empty IP during DHCP, second sees 172.23.104.177 -> 1 reset.
    await coordinator.handleConnectivityChanged([ConnectivityResult.wifi]);
    expect(resets, 1);
    expect(closes, 0);
    expect(observedIps.last, '172.23.104.177');

    // 3. Follow-up adapter notification with unchanged 172.23.104.177 -> no duplicate reset.
    await coordinator.handleConnectivityChanged(
      [ConnectivityResult.wifi, ConnectivityResult.vpn],
    );
    expect(resets, 1);
    coordinator.dispose();
  });

  test('Windows coordinator resets Core on offline-to-online recovery and medium switch', () async {
    var resets = 0;
    var currentIp = '172.23.104.177';
    final coordinator = NetworkChangeCoordinator(
      isWindows: true,
      readLocalIp: () async => currentIp,
      resetConnections: () => resets++,
      closeConnections: () {},
      probeDelays: const [Duration.zero],
    );

    await coordinator.handleConnectivityChanged([ConnectivityResult.wifi]);
    expect(resets, 0);

    // WiFi drops completely.
    currentIp = '';
    await coordinator.handleConnectivityChanged([ConnectivityResult.none]);
    expect(resets, 0);

    // WiFi reconnects to same hotspot IP -> must reset once on reconnect.
    currentIp = '172.23.104.177';
    await coordinator.handleConnectivityChanged([ConnectivityResult.wifi]);
    expect(resets, 1);

    // Plugging in Ethernet switches physical transport -> must reset.
    currentIp = '192.168.1.50';
    await coordinator.handleConnectivityChanged([ConnectivityResult.ethernet]);
    expect(resets, 2);
    coordinator.dispose();
  });
}
