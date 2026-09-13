import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/views/connection/item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('sorts process cards by configured aggregate traffic', () {
    final groups = [
      _group('alpha.exe', upload: 10, download: 20),
      _group('beta.exe', upload: 100, download: 5),
    ];

    expect(
      sortProcessConnectionGroups(
        groups,
        ConnectionSort.upload,
        direction: ConnectionSortDirection.descending,
      ).map((group) => group.name),
      ['beta.exe', 'alpha.exe'],
    );
  });

  test('sorts process cards alphabetically in process mode', () {
    final groups = [_group('zeta.exe'), _group('Alpha.exe')];

    expect(
      sortProcessConnectionGroups(groups, ConnectionSort.process)
          .map((group) => group.name),
      ['Alpha.exe', 'zeta.exe'],
    );
  });

  test('time sorting uses the newest connection in each group', () {
    final groups = [
      _group('older.exe', start: DateTime.utc(2026, 1, 1)),
      _group('newer.exe', start: DateTime.utc(2026, 1, 2)),
    ];

    expect(
      sortProcessConnectionGroups(groups, ConnectionSort.time)
          .map((group) => group.name),
      ['newer.exe', 'older.exe'],
    );
  });
}

ProcessConnectionGroup _group(
  String name, {
  num upload = 0,
  num download = 0,
  DateTime? start,
}) {
  final connection = Connection(
    id: name,
    upload: upload,
    download: download,
    start: start ?? DateTime.utc(2026, 1, 1),
    metadata: Metadata(
      uid: 0,
      network: 'tcp',
      sourceIP: '192.0.2.1',
      sourcePort: '1000',
      destinationIP: '203.0.113.1',
      destinationPort: '443',
      host: 'example.com',
      process: name,
      processPath: 'C:\\Apps\\$name',
      remoteDestination: 'example.com:443',
    ),
    chains: const [],
  );
  final item = TrackedConnection(
    connection: connection,
    isActive: true,
    uploadSpeed: 0,
    downloadSpeed: 0,
  );
  return ProcessConnectionGroup(
    key: name,
    name: name,
    processPath: connection.metadata.processPath,
    activeConnections: [item],
    closedConnections: const [],
    upload: upload,
    download: download,
    uploadSpeed: 0,
    downloadSpeed: 0,
  );
}
