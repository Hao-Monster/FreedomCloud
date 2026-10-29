import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

class _Measurements implements ClashHandlerInterface {
  final reachedRefresh = Completer<void>();
  final continueMeasurements = Completer<void>();
  int calls = 0;

  @override
  Future<DelayTestResult> catalogTestDelay(
      String catalogId, int index, String url,
      {required String requestId,
      Duration timeout = const Duration(seconds: 5)}) async {
    calls++;
    if (calls == 55) reachedRefresh.complete();
    if (calls >= 55) await continueMeasurements.future;
    return const DelayTestResult(42);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected product call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Match the reported profile sizes without retaining any user definitions.
  const sizes = [3, 1, 24, 20, 12, 20, 24, 20, 5, 1, 0, 6, 24, 1, 7, 2];
  final profiles = [
    for (var i = 0; i < sizes.length; i++)
      Profile(id: 'fixture-$i', autoUpdateDuration: Duration.zero),
  ];

  for (final change in ['refresh', 'profile', 'script']) {
    for (final refreshDuring in ['preparation', 'measurement']) {
      test('$change during $refreshDuring respects batch ownership', () async {
        final directory = await Directory.systemTemp.createTemp('fcx-refresh-');
        final store = NodeHealthStore(
            fileProvider: () async => File('${directory.path}/health.json'));
        final transport = _Measurements();
        final coordinator = createDelayTestRouter(
            liveTest: (_, __, ___) => throw StateError('Unexpected live test'),
            liveStarted: (_) => throw StateError('Unexpected live result'),
            liveResult: (_, __) => throw StateError('Unexpected live result'),
            catalogInterface: () => transport,
            healthStore: () => store,
            cancelRequest: (_) async {});
        final reachedPrepare = Completer<void>();
        final continuePrepare = Completer<void>();
        final reads = <String>[];
        final releases = <String>[];
        globalState.config = Config(
            themeProps: defaultThemeProps,
            profiles: profiles,
            currentProfileId: profiles.first.id);
        globalState.appState = AppState(
            viewSize: const Size(1200, 900),
            version: 1,
            requests: FixedList(1),
            logs: FixedList(1),
            traffics: FixedList(1),
            totalTraffic: Traffic());
        final container = ProviderContainer(overrides: [
          nodeHealthStoreProvider.overrideWith((ref) => store),
          nodeCatalogDelayCoordinatorProvider.overrideWithValue(coordinator),
          nodeCatalogServiceFactoryProvider
              .overrideWithValue(() => NodeCatalogService(
                  readProfileConfig: (id) async {
                    reads.add(id);
                    if (reads.length == 1) {
                      reachedPrepare.complete();
                      await continuePrepare.future;
                    }
                    final size = sizes[profiles.indexWhere((p) => p.id == id)];
                    return {
                      'proxies': [
                        for (var i = 0; i < size; i++)
                          {
                            'name': 'node-$i',
                            'type': 'socks5',
                            'server': 'fixture.invalid',
                            'port': 1080
                          },
                      ],
                    };
                  },
                  evaluate: (raw) async => raw,
                  fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
                  scriptFingerprint: () => '',
                  prepareCatalog: (id, nodes, _) async => jsonEncode({
                        'catalog-id': id,
                        'nodes': [
                          for (var i = 0; i < nodes.length; i++)
                            {'index': i, 'supported': true},
                        ],
                      }),
                  releaseCatalog: (id) async {
                    releases.add(id);
                    return true;
                  })),
        ]);
        final subscription =
            container.listen(nodeCatalogTesterProvider, (_, __) {});
        void changeState() {
          switch (change) {
            case 'refresh':
              container.read(versionProvider.notifier).value =
                  container.read(versionProvider) + 1;
            case 'profile':
              container.read(currentProfileIdProvider.notifier).value =
                  profiles.last.id;
            case 'script':
              container.read(scriptStateProvider.notifier).value =
                  const ScriptProps(currentId: 'new-script', scripts: [
                Script(id: 'new-script', label: 'fixture', content: ''),
              ]);
          }
        }

        try {
          final tester = container.read(nodeCatalogTesterProvider);
          final run = tester.testAll(profiles, 'https://fixture.invalid/delay');
          await reachedPrepare.future;
          if (refreshDuring == 'preparation') {
            changeState();
          }
          continuePrepare.complete();
          if (refreshDuring == 'measurement') {
            await transport.reachedRefresh.future;
            changeState();
          }
          transport.continueMeasurements.complete();
          final result = await run;
          if (change != 'refresh') {
            expect(result.reason, isIn(['cancelled', 'uiInactive']));
            expect(reads.length, lessThan(profiles.length));
            expect(transport.calls, lessThan(170));
            return;
          }
          expect(result.reason, isNull);
          expect(result.completed, 170);
          expect(result.failed, 0);
          expect(result.untested, 0);
          expect(result.issues, isEmpty);
          expect(reads, profiles.map((p) => p.id));
          expect(transport.calls, 170);
          expect(releases.toSet(), hasLength(15));
          for (var i = 0; i < sizes.length; i++) {
            expect(
                store.readProfile(profiles[i].id,
                    testUrl: 'https://fixture.invalid/delay'),
                hasLength(sizes[i]));
          }
        } finally {
          subscription.close();
          container.dispose();
          coordinator.dispose();
          await directory.delete(recursive: true);
        }
      });
    }
  }
}
