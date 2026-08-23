import 'dart:convert';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/models/common.dart';
import 'package:flclashx/models/connection_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worker decoder preserves the complete Mihomo connection payload',
      () async {
    final decoder = ConnectionSnapshotDecoder();
    addTearDown(decoder.dispose);

    final snapshot = await decoder.decode(
      jsonEncode({
        'downloadTotal': 200,
        'uploadTotal': 100,
        'memory': 300,
        'connections': [
          {
            'id': 'full',
            'upload': 10,
            'download': 20,
            'start': '2026-01-01T00:00:00.000Z',
            'chains': ['Proxy'],
            'rule': 'DOMAIN-SUFFIX',
            'rulePayload': 'example.com',
            'metadata': {
              'uid': 1000,
              'network': 'tcp',
              'type': 'TUN',
              'sourceIP': '192.0.2.1',
              'sourcePort': '12345',
              'destinationIP': '203.0.113.1',
              'destinationPort': '443',
              'sourceGeoIP': ['PRIVATE'],
              'destinationGeoIP': ['US'],
              'sourceIPASN': 'AS0',
              'destinationIPASN': 'AS64496',
              'inboundIP': '127.0.0.1',
              'inboundPort': '7890',
              'inboundName': 'TUN',
              'inboundUser': 'user',
              'host': 'example.com',
              'sniffHost': 'sniff.example.com',
              'dnsMode': 'normal',
              'process': 'browser.exe',
              'processPath': r'C:\Apps\browser.exe',
              'specialProxy': '',
              'specialRules': '',
              'remoteDestination': 'example.com:443',
              'dscp': 0,
            },
          },
        ],
      }),
    );

    expect(snapshot.uploadTotal, 100);
    expect(snapshot.connections.single.metadata.processPath,
        r'C:\Apps\browser.exe');
    expect(snapshot.connections.single.metadata.sniffHost, 'sniff.example.com');
    expect(snapshot.connections.single.rulePayload, 'example.com');
  });

  group('ConnectionTracker sampling', () {
    test('normalizes byte deltas by the actual sampling interval', () {
      final tracker = ConnectionTracker();
      final startedAt = DateTime.utc(2026, 1, 1);

      tracker.ingest(
        _snapshot(_connection(id: 'edge', upload: 100, download: 200)),
        sampledAt: startedAt,
      );
      expect(tracker.activeConnections.single.uploadSpeed, 0);
      expect(tracker.activeConnections.single.downloadSpeed, 0);

      tracker.ingest(
        _snapshot(_connection(id: 'edge', upload: 600, download: 1200)),
        sampledAt: startedAt.add(const Duration(milliseconds: 500)),
      );

      expect(tracker.activeConnections.single.uploadSpeed, 1000);
      expect(tracker.activeConnections.single.downloadSpeed, 2000);
    });

    test('clamps counter resets instead of reporting negative rates', () {
      final tracker = ConnectionTracker();
      final startedAt = DateTime.utc(2026, 1, 1);

      tracker.ingest(
        _snapshot(_connection(id: 'reset', upload: 500, download: 800)),
        sampledAt: startedAt,
      );
      tracker.ingest(
        _snapshot(_connection(id: 'reset', upload: 10, download: 20)),
        sampledAt: startedAt.add(const Duration(seconds: 1)),
      );

      expect(tracker.activeConnections.single.uploadSpeed, 0);
      expect(tracker.activeConnections.single.downloadSpeed, 0);
    });

    test('moves disappeared connections to history once with final counters',
        () {
      final tracker = ConnectionTracker();
      final startedAt = DateTime.utc(2026, 1, 1);

      tracker.ingest(
        _snapshot(_connection(id: 'closed', upload: 321, download: 654)),
        sampledAt: startedAt,
      );
      tracker.ingest(_snapshot(),
          sampledAt: startedAt.add(const Duration(seconds: 1)));
      tracker.ingest(_snapshot(),
          sampledAt: startedAt.add(const Duration(seconds: 2)));

      expect(tracker.activeConnections, isEmpty);
      expect(tracker.closedConnections, hasLength(1));
      expect(tracker.closedConnections.single.connection.upload, 321);
      expect(tracker.closedConnections.single.connection.download, 654);
      expect(tracker.closedConnections.single.isActive, isFalse);
    });

    test('retains only the newest configured number of closed connections', () {
      final tracker = ConnectionTracker(maxClosed: 3);
      final startedAt = DateTime.utc(2026, 1, 1);

      for (var index = 0; index < 5; index++) {
        tracker.ingest(
          _snapshot(_connection(id: 'connection-$index')),
          sampledAt: startedAt.add(Duration(seconds: index * 2)),
        );
        tracker.ingest(
          _snapshot(),
          sampledAt: startedAt.add(Duration(seconds: index * 2 + 1)),
        );
      }

      expect(
        tracker.closedConnections.map((item) => item.connection.id),
        ['connection-2', 'connection-3', 'connection-4'],
      );
    });
  });

  group('ConnectionTracker process aggregation', () {
    test('groups once by path and aggregates counts, totals and rates', () {
      final tracker = ConnectionTracker();
      final startedAt = DateTime.utc(2026, 1, 1);
      const path = r'C:\Program Files\Browser\browser.exe';

      tracker.ingest(
        _snapshot(
          _connection(id: 'a', process: 'browser.exe', processPath: path),
          _connection(id: 'b', process: 'browser.exe', processPath: path),
        ),
        sampledAt: startedAt,
      );
      tracker.ingest(
        _snapshot(
          _connection(
            id: 'a',
            upload: 1000,
            download: 500,
            process: 'browser.exe',
            processPath: path,
          ),
          _connection(
            id: 'b',
            upload: 2000,
            download: 1500,
            process: 'browser.exe',
            processPath: path,
          ),
        ),
        sampledAt: startedAt.add(const Duration(seconds: 1)),
      );

      final group = tracker.processGroups.single;
      expect(group.key, path);
      expect(group.name, 'browser.exe');
      expect(group.activeCount, 2);
      expect(group.closedCount, 0);
      expect(group.upload, 3000);
      expect(group.download, 2000);
      expect(group.uploadSpeed, 3000);
      expect(group.downloadSpeed, 2000);
    });

    test('falls back to process then source IP and labels inner traffic', () {
      final tracker = ConnectionTracker();
      final sampledAt = DateTime.utc(2026, 1, 1);

      tracker.ingest(
        _snapshot(
          _connection(id: 'process', process: 'helper.exe'),
          _connection(id: 'source', sourceIP: '192.0.2.10'),
          _connection(id: 'inner', connectionType: 'Inner'),
        ),
        sampledAt: sampledAt,
      );

      expect(
        tracker.processGroups.map((group) => group.key),
        containsAll(['helper.exe', '192.0.2.10', 'mihomo']),
      );
      expect(
        tracker.processGroups.firstWhere((group) => group.key == 'mihomo').name,
        'mihomo',
      );
    });
  });
}

ConnectionSnapshot _snapshot([
  Connection? first,
  Connection? second,
  Connection? third,
]) {
  return ConnectionSnapshot(
    downloadTotal: 0,
    uploadTotal: 0,
    memory: 0,
    connections: [
      if (first != null) first,
      if (second != null) second,
      if (third != null) third,
    ],
  );
}

Connection _connection({
  required String id,
  num upload = 0,
  num download = 0,
  String process = '',
  String processPath = '',
  String sourceIP = '',
  String connectionType = '',
}) {
  return Connection(
    id: id,
    upload: upload,
    download: download,
    start: DateTime.utc(2026, 1, 1),
    metadata: Metadata(
      uid: 0,
      network: 'tcp',
      sourceIP: sourceIP,
      sourcePort: '12345',
      destinationIP: '203.0.113.10',
      destinationPort: '443',
      host: 'example.com',
      process: process,
      processPath: processPath,
      type: connectionType,
      remoteDestination: 'example.com:443',
    ),
    chains: const ['Proxy'],
  );
}
