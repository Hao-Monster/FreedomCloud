import 'dart:async';

import 'package:flclashx/manager/connection_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never overlaps a slow snapshot request', () async {
    final requests = <Completer<ConnectionSnapshot>>[];
    final manager = ConnectionManager(
      loadSnapshot: () {
        final request = Completer<ConnectionSnapshot>();
        requests.add(request);
        return request.future;
      },
    );
    addTearDown(manager.dispose);

    manager.setViewVisible(visible: true);
    manager.configure(running: true, refreshIntervalMs: 100);
    await _waitUntil(() => requests.length == 1);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(requests, hasLength(1));

    requests.single.complete(_snapshot());
    await _waitUntil(() => requests.length == 2);
    expect(requests, hasLength(2));
    requests.last.complete(_snapshot());
  });

  test(
      'pause keeps polling totals while freezing rows and resumes at zero speed',
      () async {
    final snapshots = <ConnectionSnapshot>[
      _snapshot(connection: _connection(upload: 100), uploadTotal: 100),
      _snapshot(connection: _connection(upload: 600), uploadTotal: 600),
      _snapshot(connection: _connection(upload: 900), uploadTotal: 900),
    ];
    var now = DateTime.utc(2026, 1, 1);
    final manager = ConnectionManager(
      loadSnapshot: () async => snapshots.removeAt(0),
      now: () => now,
    );
    addTearDown(manager.dispose);

    manager.setViewVisible(visible: true);
    manager.configure(running: true, refreshIntervalMs: 10000);
    await _waitUntil(() => manager.activeConnections.isNotEmpty);
    expect(manager.activeConnections.single.connection.upload, 100);

    manager.setPaused(paused: true);
    now = now.add(const Duration(seconds: 1));
    await manager.refresh();
    expect(manager.uploadTotal, 600);
    expect(manager.activeConnections.single.connection.upload, 100);

    now = now.add(const Duration(seconds: 1));
    manager.setPaused(paused: false);
    expect(manager.activeConnections.single.connection.upload, 600);
    expect(manager.activeConnections.single.uploadSpeed, 0);

    now = now.add(const Duration(seconds: 1));
    await manager.refresh();
    expect(manager.activeConnections.single.connection.upload, 900);
    expect(manager.activeConnections.single.uploadSpeed, 300);
  });

  test('diagnostics expose pipeline state without connection metadata',
      () async {
    final events = <String>[];
    final manager = ConnectionManager(
      loadSnapshot: () async => _snapshot(
        connection: _connection(upload: 100),
        uploadTotal: 100,
      ),
      diagnosticLog: events.add,
    );
    addTearDown(manager.dispose);

    manager.setViewVisible(visible: true);
    manager.configure(running: true, refreshIntervalMs: 10000);
    await _waitUntil(() => manager.activeConnections.isNotEmpty);

    expect(
      events,
      contains(
        contains(
          'sourceConnections=1 active=1 groups=1 paused=false',
        ),
      ),
    );
    final output = events.join('\n');
    expect(output, isNot(contains('example.com')));
    expect(output, isNot(contains('192.0.2.1')));
    expect(output, isNot(contains('203.0.113.1')));
  });

  test('diagnostics classify missing process attribution without leaking metadata',
      () async {
    final events = <String>[];
    final connection = _connection(upload: 100).copyWith(
      metadata: const Metadata(
        uid: 0,
        network: 'tcp',
        sourceIP: '',
        sourcePort: '',
        destinationIP: '',
        destinationPort: '',
        host: '',
        process: '',
        processPath: '',
        remoteDestination: '',
      ),
    );
    final manager = ConnectionManager(
      loadSnapshot: () async => _snapshot(connection: connection),
      diagnosticLog: events.add,
    );
    addTearDown(manager.dispose);

    manager.setViewVisible(visible: true);
    manager.configure(running: true, refreshIntervalMs: 10000);
    await _waitUntil(() => manager.activeConnections.isNotEmpty);

    final output = events.join('\n');
    expect(output, contains('processMetadata=full:0,processOnly:0,missing:1'));
    expect(output, isNot(contains('example.com')));
    expect(output, isNot(contains('192.0.2.1')));
  });

  test('steady polling diagnostics are throttled after the first three polls',
      () async {
    final events = <String>[];
    final manager = ConnectionManager(
      loadSnapshot: () async => _snapshot(),
      diagnosticLog: events.add,
    );
    addTearDown(manager.dispose);

    manager.setViewVisible(visible: true);
    manager.configure(running: true, refreshIntervalMs: 10000);
    await _waitUntil(
      () => events.any((event) => event.contains('manager.poll status=ok')),
    );
    for (var i = 0; i < 4; i++) {
      await manager.refresh();
    }

    final pollEvents = events
        .where((event) => event.contains('manager.poll status=ok'))
        .toList();
    expect(pollEvents, hasLength(3));
  });

  test('diagnostic errors include only the error type', () async {
    final events = <String>[];
    final manager = ConnectionManager(
      loadSnapshot: () async =>
          throw StateError('sensitive.example/path/to/application.exe'),
      diagnosticLog: events.add,
    );
    addTearDown(manager.dispose);

    manager.setViewVisible(visible: true);
    manager.configure(running: true, refreshIntervalMs: 10000);
    await _waitUntil(() => manager.error != null);

    final output = events.join('\n');
    expect(output, contains('errorType=StateError'));
    expect(output, isNot(contains('sensitive.example')));
    expect(output, isNot(contains('application.exe')));
  });

  test('hidden view performs no polling and becoming visible refreshes now',
      () async {
    var requests = 0;
    final manager = ConnectionManager(
      loadSnapshot: () async {
        requests++;
        return _snapshot();
      },
    );
    addTearDown(manager.dispose);

    manager.configure(running: true, refreshIntervalMs: 100);
    expect(manager.viewVisible, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(requests, 0);

    manager.setViewVisible(visible: true);
    expect(manager.effectiveInterval, const Duration(milliseconds: 100));
    await _waitUntil(() => requests == 1);

    manager.setViewVisible(visible: false);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(requests, 1);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not reached before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

ConnectionSnapshot _snapshot({
  Connection? connection,
  num uploadTotal = 0,
}) =>
    ConnectionSnapshot(
      downloadTotal: 0,
      uploadTotal: uploadTotal,
      memory: 0,
      connections: [if (connection != null) connection],
    );

Connection _connection({required num upload}) => Connection(
      id: 'connection',
      upload: upload,
      download: 0,
      start: DateTime.utc(2026, 1, 1),
      metadata: const Metadata(
        uid: 0,
        network: 'tcp',
        sourceIP: '192.0.2.1',
        sourcePort: '12345',
        destinationIP: '203.0.113.1',
        destinationPort: '443',
        host: 'example.com',
        process: 'browser.exe',
        remoteDestination: 'example.com:443',
      ),
      chains: const ['Proxy'],
    );
