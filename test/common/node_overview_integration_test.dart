import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_recorder.dart';
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
  late Map<String, dynamic> source;
  Future<Map<String, dynamic>> Function()? runtimeReader;

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
    source = {
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
    globalState.lastRuntimeConfig = source;
    runtimeReader = null;
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
          nodeRuntimeReaderProvider.overrideWithValue(
              () => runtimeReader?.call() ?? Future.value(source)),
          nodeCatalogServiceFactoryProvider.overrideWithValue(() =>
              NodeCatalogService(
                  readProfileConfig: (id) async =>
                      id == 'a' ? source : {'proxies': []},
                  evaluate: (raw) async => raw,
                  fileMetadata: (_) async => (modifiedMicros: 1, size: 1),
                  scriptFingerprint: () => '')),
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
      final target = (await controller.captureNodeHealthTarget(delay))!;
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await controller.flushNodeHealth();
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
      await controller.flushNodeHealth();
      expect(store.readProfile('b', testUrl: defaultTestUrl), isEmpty);
      expect(
          store.read('a', target.identityKey, testUrl: defaultTestUrl)?.delayMs,
          42);
      expect(await controller.captureNodeHealthTarget(delay), isNull,
          reason: 'selected B and still-applied A must not be mixed');
    });
  });

  testWidgets(
      'feature disabled preserves live setDelay without starting history services',
      (tester) async {
    final (controller, ref) = await mount(tester, enabled: false);
    controller.setDelay(delay);
    expect(ref.read(delayDataSourceProvider)[defaultTestUrl]?['same'], 42);
    expect(await controller.captureNodeHealthTarget(delay), isNull);
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
      'reattached Core can record from matching read-only runtime without setup',
      (tester) async {
    final (controller, ref) = await mount(tester);
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    await tester.runAsync(() async {
      final target = controller.captureNodeHealthTarget(delay);
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await controller.flushNodeHealth();
      expect(ref.read(delayDataSourceProvider)[defaultTestUrl]?['same'], 42);
      expect(
          store.readProfile('a', testUrl: defaultTestUrl).values.single.delayMs,
          42);
      expect(globalState.lastRuntimeConfig, isNull);
      expect(globalState.lastRuntimeProfileId, isNull);
      expect(controller.applies, 0);
    });
  });

  testWidgets(
      'profile deletion clears persisted history and rejects late captured result',
      (tester) async {
    final (controller, ref) = await mount(tester);
    await tester.runAsync(() async {
      final target = (await controller.captureNodeHealthTarget(delay))!;
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await controller.flushNodeHealth();
      ref.read(profilesProvider.notifier).deleteProfileById('a');
      controller.setDelay(delay,
          healthTarget: target, capturedHealthTarget: true);
      await controller.flushNodeHealth();
      expect(store.readProfile('a', testUrl: defaultTestUrl), isEmpty);
    });
  });

  testWidgets('profile switch during runtime read rejects late verification',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    runtimeReader = () => pending.future;
    final (controller, ref) = await mount(tester);
    await tester.runAsync(() async {
      final target = controller.captureNodeHealthTarget(delay);
      ref.read(currentProfileIdProvider.notifier).value = 'b';
      pending.complete(source);
      expect(await target, isNull);
      expect(ref.exists(nodeHealthRecorderProvider), isFalse);
      expect(controller.applies, 0);
    });
  });

  testWidgets(
      'mismatch or failure never copies disk config into runtime globals',
      (tester) async {
    runtimeReader = () async => {'proxies': []};
    final (controller, ref) = await mount(tester);
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    await tester.runAsync(() async {
      expect(await controller.captureNodeHealthTarget(delay), isNull);
      runtimeReader = () async => throw StateError('private-fixture');
      expect(
          await controller.captureNodeHealthTarget(delay, refreshRuntime: true),
          isNull);
      expect(ref.exists(nodeHealthRecorderProvider), isFalse);
      expect(globalState.lastRuntimeConfig, isNull);
      expect(globalState.lastRuntimeProfileId, isNull);
      expect(controller.applies, 0);
    });
  });

  testWidgets(
      'concurrent captures share one read and new batch refreshes runtime',
      (tester) async {
    var reads = 0;
    runtimeReader = () async {
      reads++;
      return source;
    };
    final (controller, _) = await mount(tester);
    await tester.runAsync(() async {
      final results = await Future.wait([
        controller.captureNodeHealthTarget(delay, refreshRuntime: true),
        controller.captureNodeHealthTarget(delay),
      ]);
      expect(results.every((entry) => entry != null), isTrue);
      expect(reads, 1);
      runtimeReader = () async {
        reads++;
        return {'proxies': []};
      };
      expect(
          await controller.captureNodeHealthTarget(delay, refreshRuntime: true),
          isNull);
      expect(reads, 2);
    });
  });

  testWidgets(
      'actual coordinator callbacks retain good history on cancellation',
      (tester) async {
    final (controller, _) = await mount(tester);
    globalState.appController = controller;
    await tester.runAsync(() async {
      const request = DelayTestTarget('same', defaultTestUrl);
      delayTests.onStarted(request);
      delayTests.onResult(request, const DelayTestResult(42));
      await controller.flushNodeHealth();
      expect(
          store.readProfile('a', testUrl: defaultTestUrl).values.single.delayMs,
          42);
      delayTests.onStarted(request);
      delayTests.onResult(
          request, const DelayTestResult(-1, reason: 'cancelled'));
      await controller.flushNodeHealth();
      expect(
          store.readProfile('a', testUrl: defaultTestUrl).values.single.delayMs,
          42);
      expect(controller.applies, 0);
    });
  });

  for (final changeProfile in [false, true]) {
    testWidgets(
        changeProfile
            ? 'profile change rejects both pending batch verifications'
            : 'new batch preserves an earlier pending verification',
        (tester) async {
      (source['proxies'] as List).add({
        'name': 'other',
        'type': 'ss',
        'server': 'other.invalid',
        'port': 443,
      });
      final firstRuntime = Completer<Map<String, dynamic>>();
      final secondRuntime = Completer<Map<String, dynamic>>();
      var reads = 0;
      runtimeReader =
          () => ++reads == 1 ? firstRuntime.future : secondRuntime.future;
      final (controller, ref) = await mount(tester);
      globalState.appController = controller;
      await tester.runAsync(() async {
        const first = DelayTestTarget('same', defaultTestUrl);
        const second = DelayTestTarget('other', defaultTestUrl);
        delayTests.onStarted(first);
        delayTests.onResult(first, const DelayTestResult(42));
        delayTests.onStarted(second);
        delayTests.onResult(second, const DelayTestResult(23));
        expect(reads, 2);
        if (changeProfile) {
          ref.read(currentProfileIdProvider.notifier).value = 'b';
        }
        secondRuntime.complete(source);
        firstRuntime.complete(source);
        await controller.flushNodeHealth();
        final entries = store.readProfile('a', testUrl: defaultTestUrl);
        if (changeProfile) {
          expect(entries, isEmpty);
        } else {
          final catalog = buildProfileCatalog(
              profileId: 'a', fingerprint: 'test', raw: source);
          expect(entries.length, 2);
          expect(entries[catalog.nodes[0].identityKey]?.delayMs, 42);
          expect(entries[catalog.nodes[1].identityKey]?.delayMs, 23);
        }
        expect(controller.applies, 0);
      });
    });
  }

  testWidgets('flush drains captures added while an earlier result is pending',
      (tester) async {
    final (controller, _) = await mount(tester);
    await tester.runAsync(() async {
      final target = (await controller.captureNodeHealthTarget(delay))!;
      final first = Completer<NodeHealthTarget?>();
      final second = Completer<NodeHealthTarget?>();
      controller.setDelay(delay,
          healthTarget: first.future, capturedHealthTarget: true);
      var flushed = false;
      final flush = controller.flushNodeHealth().then((_) => flushed = true);
      controller.setDelay(delay.copyWith(value: 43),
          healthTarget: second.future, capturedHealthTarget: true);
      first.complete(target);
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isFalse);
      second.complete(target);
      await flush;
      expect(
          store.readProfile('a', testUrl: defaultTestUrl).values.single.delayMs,
          43);
    });
  });
}
