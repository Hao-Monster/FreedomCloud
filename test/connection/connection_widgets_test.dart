import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/views/connection/item.dart';
import 'package:flclashx/views/connection/table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('process card keeps name, counts and rates visible',
      (tester) async {
    await AppLocalizations.delegate.load(const Locale('en'));
    final item = _tracked(id: 'browser', process: 'browser.exe');
    final group = ProcessConnectionGroup(
      key: r'C:\Browser\browser.exe',
      name: 'browser.exe',
      processPath: r'C:\Browser\browser.exe',
      activeConnections: [item],
      closedConnections: const [],
      upload: 1024,
      download: 2048,
      uploadSpeed: 512,
      downloadSpeed: 1024,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ProcessConnectionCard(
              group: group,
              showIcon: false,
              useApplicationName: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('browser.exe'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('/s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('table builds only visible rows for large connection sets',
      (tester) async {
    await AppLocalizations.delegate.load(const Locale('en'));
    final items = List.generate(
      200,
      (index) => _tracked(id: '$index', process: 'process-$index.exe'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 420,
            child: ConnectionTable(
              items: items,
              columns: const ['process', 'host', 'uploadSpeed'],
              columnWidths: const {},
              onColumnWidthsChanged: (_) {},
              onTap: (_) {},
              onClose: (_) {},
            ),
          ),
        ),
      ),
    );

    final renderedProcesses = find.byWidgetPredicate(
      (widget) =>
          widget is Text && (widget.data?.startsWith('process-') ?? false),
    );
    expect(renderedProcesses, findsWidgets);
    expect(renderedProcesses.evaluate().length, lessThan(items.length));
    expect(tester.takeException(), isNull);
  });
}

TrackedConnection _tracked({required String id, required String process}) =>
    TrackedConnection(
      connection: Connection(
        id: id,
        upload: 1024,
        download: 2048,
        start: DateTime.utc(2026, 1, 1),
        metadata: Metadata(
          uid: 0,
          network: 'tcp',
          sourceIP: '192.0.2.1',
          sourcePort: '12345',
          destinationIP: '203.0.113.1',
          destinationPort: '443',
          host: 'example.com',
          process: process,
          processPath: 'C:\\Apps\\$process',
          remoteDestination: 'example.com:443',
        ),
        chains: const ['Proxy'],
      ),
      isActive: true,
      uploadSpeed: 512,
      downloadSpeed: 1024,
    );
