import 'package:flclashx/models/common.dart';
import 'package:flclashx/models/connection_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connection filtering', () {
    final item = _tracked(
      process: 'msedge.exe',
      processPath: r'C:\Program Files\Microsoft\Edge\msedge.exe',
      host: 'login.example.com',
      sniffHost: 'sniff.example.net',
      destinationIP: '203.0.113.20',
      remoteDestination: 'cdn.example.org:443',
      sourceIP: '192.0.2.5',
      chains: const ['Proxy A'],
      rule: 'DOMAIN-SUFFIX',
      rulePayload: 'example.com',
    );

    test('matches every user-visible field case-insensitively', () {
      for (final query in [
        'MSEDGE',
        r'microsoft\edge',
        'LOGIN.EXAMPLE',
        'sniff.example',
        '203.0.113.20',
        'cdn.example.org',
        '192.0.2.5',
        'proxy a',
        'domain-suffix',
        'EXAMPLE.COM',
      ]) {
        expect(filterTrackedConnections([item], query), [item], reason: query);
      }
      expect(filterTrackedConnections([item], 'does-not-exist'), isEmpty);
    });

    test('matches resolved application names without mutating connection data',
        () {
      expect(
        filterTrackedConnections(
          [item],
          'Microsoft Edge',
          applicationNameForPath: (_) => 'Microsoft Edge',
        ),
        [item],
      );
    });
  });

  group('connection sorting', () {
    final older = _tracked(
      id: 'older',
      startedAt: DateTime.utc(2026, 1, 1),
      upload: 50,
      download: 500,
      uploadSpeed: 5,
      downloadSpeed: 50,
      process: 'z.exe',
    );
    final newer = _tracked(
      id: 'newer',
      startedAt: DateTime.utc(2026, 1, 2),
      upload: 100,
      download: 100,
      uploadSpeed: 10,
      downloadSpeed: 10,
      process: 'a.exe',
    );

    test('supports all Koala list sort modes and both directions', () {
      final items = [older, newer];
      expect(_ids(sortTrackedConnections(items, ConnectionSort.time)),
          ['newer', 'older']);
      expect(_ids(sortTrackedConnections(items, ConnectionSort.upload)),
          ['newer', 'older']);
      expect(_ids(sortTrackedConnections(items, ConnectionSort.download)),
          ['older', 'newer']);
      expect(_ids(sortTrackedConnections(items, ConnectionSort.uploadSpeed)),
          ['newer', 'older']);
      expect(_ids(sortTrackedConnections(items, ConnectionSort.downloadSpeed)),
          ['older', 'newer']);
      expect(_ids(sortTrackedConnections(items, ConnectionSort.process)),
          ['newer', 'older']);
      expect(
        _ids(
          sortTrackedConnections(
            items,
            ConnectionSort.time,
            direction: ConnectionSortDirection.ascending,
          ),
        ),
        ['older', 'newer'],
      );
    });

    test('does not mutate the manager-owned input list', () {
      final input = [older, newer];
      sortTrackedConnections(input, ConnectionSort.process);
      expect(_ids(input), ['older', 'newer']);
    });
  });
}

List<String> _ids(List<TrackedConnection> items) =>
    items.map((item) => item.connection.id).toList();

TrackedConnection _tracked({
  String id = 'connection',
  DateTime? startedAt,
  num upload = 0,
  num download = 0,
  double uploadSpeed = 0,
  double downloadSpeed = 0,
  String process = '',
  String processPath = '',
  String host = '',
  String sniffHost = '',
  String destinationIP = '',
  String remoteDestination = '',
  String sourceIP = '',
  List<String> chains = const [],
  String rule = '',
  String rulePayload = '',
}) {
  return TrackedConnection(
    connection: Connection(
      id: id,
      upload: upload,
      download: download,
      start: startedAt ?? DateTime.utc(2026, 1, 1),
      metadata: Metadata(
        uid: 0,
        network: 'tcp',
        sourceIP: sourceIP,
        sourcePort: '12345',
        destinationIP: destinationIP,
        destinationPort: '443',
        host: host,
        sniffHost: sniffHost,
        process: process,
        processPath: processPath,
        remoteDestination: remoteDestination,
      ),
      chains: chains,
      rule: rule,
      rulePayload: rulePayload,
    ),
    isActive: true,
    uploadSpeed: uploadSpeed,
    downloadSpeed: downloadSpeed,
  );
}
