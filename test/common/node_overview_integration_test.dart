import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The real profile-change entry clears live data; replace only the external
// apply boundary, so the test never creates Core/Agent/TUN connections.
class _Controller extends AppController {
  _Controller(super.context, super.ref);
  int applies = 0;
  @override
  Future<void> applyProfile({bool silence = false}) async {
    applies++;
  }
}

void main() {
  const a = Profile(id: 'a', autoUpdateDuration: Duration.zero);
  const b = Profile(id: 'b', autoUpdateDuration: Duration.zero);
  const delay = Delay(name: 'same', url: defaultTestUrl, value: 42);
  late Directory directory;
  late NodeHealthStore store;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('fcx-overview-integration-');
    store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'));
    globalState.config = const Config(
        themeProps: defaultThemeProps, profiles: [a, b], currentProfileId: 'a');
    globalState.appState = AppState(
        viewSize: const Size(1000, 800),
        version: 1,
        requests: FixedList(1),
        logs: FixedList(1),
        traffics: FixedList(1),
        totalTraffic: Traffic());
    globalState.lastRuntimeProfileId = 'a';
    globalState.lastRuntimeConfig = {
      'proxies': [
        {
          'name': 'same',
          'type': 'ss',
          'server': 'test.invalid',
          'port': 443,
          'password': 'secret-fixture'
        },
      ]
    };
  });
  tearDown(() async {
    await store.flush();
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    await directory.delete(recursive: true);
  });

  Future<(_Controller, WidgetRef)> mount(WidgetTester tester,
      {bool enabled = true}) async {
    late _Controller controller;
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(enabled),
          nodeHealthStoreProvider.overrideWith((_) => store),
        ],
        child: MaterialApp(home: Consumer(builder: (context, widgetRef, _) {
          ref = widgetRef;
          controller = _Controller(context, widgetRef);
          return const SizedBox();
        }))));
    return (controller, ref);
  }

  testWidgets(
      'real handleChangeProfile clears live data while preserving captured history',
      (tester) async {
    final (controller, ref) = await mount(tester);
    await tester.runAsync(() async {
      final target = controller.captureNodeHealthTarget(delay)!;
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await ref.read(nodeHealthRecorderProvider).flush();
      expect(
          store.read('a', target.identityKey, testUrl: defaultTestUrl)?.delayMs,
          42);
      ref.read(currentProfileIdProvider.notifier).value = 'b';
      controller.handleChangeProfile();
      expect(controller.applies, 1);
      expect(ref.read(delayDataSourceProvider), isEmpty);
      expect(
          store.read('a', target.identityKey, testUrl: defaultTestUrl)?.delayMs,
          42);
      // Cancellation arriving after a switch retains its request's captured key.
      controller.setDelay(delay.copyWith(value: -1),
          reason: 'configChanged',
          healthTarget: target,
          capturedHealthTarget: true);
      await ref.read(nodeHealthRecorderProvider).flush();
      expect(store.readProfile('b', testUrl: defaultTestUrl), isEmpty);
      expect(
          store.read('a', target.identityKey, testUrl: defaultTestUrl)?.reason,
          'configChanged');
      expect(controller.captureNodeHealthTarget(delay), isNull,
          reason: 'selected B and still-applied A must not be mixed');
    });
  });

  testWidgets(
      'feature disabled preserves live setDelay without starting history services',
      (tester) async {
    final (controller, ref) = await mount(tester, enabled: false);
    controller.setDelay(delay);
    expect(ref.read(delayDataSourceProvider)[defaultTestUrl]?['same'], 42);
    expect(controller.captureNodeHealthTarget(delay), isNull);
    expect(ref.exists(nodeHealthRecorderProvider), isFalse);
    expect(ref.exists(nodeCatalogServiceProvider), isFalse);
    expect(
        await tester
            .runAsync(() => File('${directory.path}/health.json').exists()),
        isFalse);
  });

  testWidgets(
      'unscoped late broadcast updates live UI but never new-profile history',
      (tester) async {
    final (controller, ref) = await mount(tester);
    ref.read(currentProfileIdProvider.notifier).value = 'b';
    globalState.lastRuntimeProfileId = 'b';
    controller.setDelay(delay);
    expect(ref.read(delayDataSourceProvider)[defaultTestUrl]?['same'], 42);
    expect(ref.exists(nodeHealthRecorderProvider), isFalse);
    expect(store.readProfile('b', testUrl: defaultTestUrl), isEmpty);
  });

  testWidgets(
      'reattached Core without a verified runtime snapshot cannot invent history',
      (tester) async {
    final (controller, ref) = await mount(tester);
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    final target = controller.captureNodeHealthTarget(delay);
    expect(target, isNull);
    controller.setDelay(delay,
        healthTarget: target, capturedHealthTarget: true);
    expect(ref.read(delayDataSourceProvider)[defaultTestUrl]?['same'], 42);
    expect(ref.exists(nodeHealthRecorderProvider), isFalse);
  });

  testWidgets(
      'profile deletion clears persisted history and rejects late captured result',
      (tester) async {
    final (controller, ref) = await mount(tester);
    await tester.runAsync(() async {
      final target = controller.captureNodeHealthTarget(delay)!;
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await ref.read(nodeHealthRecorderProvider).flush();
      ref.read(profilesProvider.notifier).deleteProfileById('a');
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await ref.read(nodeHealthRecorderProvider).flush();
      expect(store.readProfile('a', testUrl: defaultTestUrl), isEmpty);
    });
  });
}
