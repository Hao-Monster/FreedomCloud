import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/controller.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends AppController {
  _Controller(super.context, super.ref);

  int applies = 0;

  @override
  Future<void> applyProfile({bool silence = false}) async {
    applies++;
  }
}

Map<String, dynamic> _config(String endpoint) => {
      'proxies': [
        {
          'name': 'same',
          'type': 'ss',
          'server': endpoint,
          'port': 443,
          'password': 'test-only-placeholder',
        },
      ],
    };

void main() {
  const profile = Profile(id: 'a', autoUpdateDuration: Duration.zero);
  const oldResult = Delay(name: 'same', url: defaultTestUrl, value: 777);
  late Directory directory;
  late NodeHealthStore store;
  late Map<String, dynamic> source;
  late Completer<Map<String, dynamic>> oldRuntime;
  late Completer<void> firstProfileRead;
  late int revision;
  late int runtimeReads;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fcx-runtime-race-');
    store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'));
    source = _config('before.invalid');
    oldRuntime = Completer<Map<String, dynamic>>();
    firstProfileRead = Completer<void>();
    revision = 1;
    runtimeReads = 0;
    globalState.config = const Config(
        themeProps: defaultThemeProps,
        profiles: [profile],
        currentProfileId: 'a');
    globalState.appState = AppState(
        viewSize: const Size(1000, 800),
        version: 1,
        requests: FixedList(1),
        logs: FixedList(1),
        traffics: FixedList(1),
        totalTraffic: Traffic());
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
  });

  tearDown(() async {
    if (!oldRuntime.isCompleted) oldRuntime.complete(source);
    await store.flush();
    globalState.lastRuntimeConfig = null;
    globalState.lastRuntimeProfileId = null;
    await directory.delete(recursive: true);
  });

  Future<(_Controller, WidgetRef)> mount(WidgetTester tester) async {
    late _Controller controller;
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          nodeOverviewEnabledProvider.overrideWithValue(true),
          nodeHealthStoreProvider.overrideWith((_) => store),
          nodeRuntimeReaderProvider.overrideWithValue(() {
            runtimeReads++;
            return runtimeReads == 1 ? oldRuntime.future : Future.value(source);
          }),
          nodeCatalogServiceFactoryProvider.overrideWithValue(() =>
              NodeCatalogService(
                  readProfileConfig: (_) async {
                    final snapshot = source;
                    if (!firstProfileRead.isCompleted) {
                      firstProfileRead.complete();
                    }
                    return snapshot;
                  },
                  evaluate: (raw) async => raw,
                  fileMetadata: (_) async =>
                      (modifiedMicros: revision, size: revision),
                  scriptFingerprint: () => '')),
        ],
        child: MaterialApp(home: Consumer(builder: (context, widgetRef, _) {
          ref = widgetRef;
          controller = _Controller(context, widgetRef);
          return const SizedBox();
        }))));
    return (controller, ref);
  }

  for (final recreate in [false, true]) {
    testWidgets(
        recreate
            ? 'delete and recreate same id rejects old pending runtime result'
            : 'same id endpoint update rejects old pending runtime result',
        (tester) async {
      final (controller, ref) = await mount(tester);
      await tester.runAsync(() async {
        final previousSource = source;
        final oldTarget = controller.captureNodeHealthTarget(oldResult);
        final oldRead = ref.read(nodeRuntimeReadProvider);
        controller.setDelay(oldResult,
            healthTarget: oldTarget, capturedHealthTarget: true);
        await firstProfileRead.future;

        source = _config('after.invalid');
        revision++;
        final replacement =
            profile.copyWith(lastUpdateDate: DateTime.utc(2026, 10, 15));
        if (recreate) {
          // No frame/microtask between deletion and recreation: an id check
          // alone cannot distinguish this new profile from the original.
          ref.read(profilesProvider.notifier).deleteProfileById('a');
          ref.read(profilesProvider.notifier).setProfile(replacement);
        } else {
          ref.read(profilesProvider.notifier).setProfile(replacement);
        }
        expect(oldRead.isCurrent, isFalse,
            reason: 'ownership must be revoked before a provider rebuild');

        final newTarget = await controller.captureNodeHealthTarget(oldResult);
        expect(newTarget, isNotNull);
        expect(runtimeReads, 2);
        final oldIdentity = buildProfileCatalog(
                profileId: 'a', fingerprint: 'test', raw: previousSource)
            .nodes
            .single
            .identityKey;
        expect(newTarget!.identityKey, isNot(oldIdentity));

        // The replacement read has succeeded before the original read returns.
        // The old request must not adopt the replacement future or generation.
        oldRuntime.complete(previousSource);
        expect(await oldTarget, isNull);
        await controller.flushNodeHealth();
        expect(store.readProfile('a', testUrl: defaultTestUrl), isEmpty);

        controller.setDelay(oldResult.copyWith(value: 23),
            healthTarget: newTarget, capturedHealthTarget: true);
        await controller.flushNodeHealth();
        final records = store.readProfile('a', testUrl: defaultTestUrl);
        expect(records.keys, [newTarget.identityKey]);
        expect(records.values.single.delayMs, 23);
        expect(store.read('a', oldIdentity, testUrl: defaultTestUrl), isNull);
        expect(controller.applies, 0);
        expect(globalState.lastRuntimeConfig, isNull);
        expect(globalState.lastRuntimeProfileId, isNull);
      });
    });
  }
}
