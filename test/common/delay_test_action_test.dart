import 'dart:async';

import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/views/proxies/delay_test_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'actual toolbar action starts, shows cancel and clears work on cancel',
      (tester) async {
    var sent = 0;
    var cancelled = 0;
    var callbacks = 0;
    final coordinator = DelayTestCoordinator(
      concurrency: 2,
      test: (_, __, ___) {
        sent++;
        return Completer<DelayTestResult>().future;
      },
      cancelRequest: (_) async {
        cancelled++;
      },
      onStarted: (_) {},
      onResult: (_, __) {
        callbacks++;
      },
    );
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DelayTestAction(
      coordinator: coordinator,
      startLabel: 'Test all delays',
      cancelLabel: 'Cancel tests',
      onStart: () async {
        await coordinator
            .run([for (var i = 0; i < 100; i++) DelayTestTarget('$i', 'url')]);
      },
    ))));
    await tester.tap(find.byTooltip('Test all delays'));
    await tester.pump();
    expect(sent, 2);
    expect(find.byTooltip('Cancel tests'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel tests'));
    await tester.pump();
    expect(cancelled, 2);
    expect(callbacks, 2);
    expect(sent, 2, reason: 'Cancellation must discard the 98 waiting entries');
    expect(find.byTooltip('Test all delays'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
