import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/core.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = '0123456789abcdef0123456789abcdef';
const _url = 'https://test.invalid/secret-token';
ProfileCatalog _catalog(String profile, String scope, {int index = 0}) =>
    ProfileCatalog(
        profileId: profile,
        fingerprint: 'f',
        status: ProfileCatalogStatus.ready,
        coreCatalogId: scope,
        nodes: [
          CatalogNode(
              identityKey: _key,
              endpointKey: _key,
              name: 'same-name',
              type: 'ss',
              source: CatalogNodeSource.inline,
              coreIndex: index)
        ]);

class _CatalogCore extends ClashHandlerInterface {
  final calls = <(String, int, String)>[];
  DelayTestResult result = const DelayTestResult(120);
  Completer<DelayTestResult>? pending;
  @override
  Future<DelayTestResult> catalogTestDelay(
      String catalogId, int index, String url,
      {required String requestId,
      Duration timeout = const Duration(seconds: 5)}) async {
    calls.add((catalogId, index, requestId));
    if (pending != null) return pending!.future;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late NodeHealthStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('catalog-delay-test-');
    store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'));
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  test(
      'catalog scope separates deduplication and reports real progress',
      () => fakeAsync((clock) {
            final replies = <Completer<DelayTestResult>>[];
            final coordinator = DelayTestCoordinator(
                concurrency: 1,
                test: (_, __, ___) {
                  final reply = Completer<DelayTestResult>();
                  replies.add(reply);
                  return reply.future;
                },
                cancelRequest: (_) async {},
                onStarted: (_) {},
                onResult: (_, __) {});
            const a = DelayTestTarget('same', 'url', scope: 'a', nodeIndex: 0);
            const b = DelayTestTarget('same', 'url', scope: 'b', nodeIndex: 0);
            unawaited(coordinator.run([a, a, b]));
            clock.flushMicrotasks();
            final batchId = coordinator.activeBatchId;
            expect(batchId, isNotNull);
            expect(coordinator.total, 2);
            expect(coordinator.completed, 0);
            expect(coordinator.activeTargets, [a]);
            replies.first.complete(const DelayTestResult(11));
            clock.flushMicrotasks();
            expect(coordinator.completed, 1);
            expect(coordinator.activeTargets, [b]);
            replies.last.complete(const DelayTestResult(12));
            clock.flushMicrotasks();
            expect(coordinator.completed, 2);
            expect(coordinator.total, 2);
            expect(coordinator.activeBatchId, isNull);
            expect(coordinator.activeTargets, isEmpty);
            coordinator.dispose();
          }));

  test(
      'per-run batch timeout overrides default without changing later live budget',
      () => fakeAsync((clock) {
            final coordinator = DelayTestCoordinator(
                requestTimeout: const Duration(seconds: 60),
                test: (_, __, ___) => Completer<DelayTestResult>().future,
                cancelRequest: (_) async {},
                onStarted: (_) {},
                onResult: (_, __) {});
            DelayBatchResult? result;
            unawaited(coordinator.run([const DelayTestTarget('a', 'url')],
                batchTimeout: const Duration(
                    seconds: 40)).then((value) => result = value));
            clock.elapse(const Duration(seconds: 31));
            expect(coordinator.busy, isTrue);
            clock.elapse(const Duration(seconds: 9));
            expect(result!.reason, 'batchDeadlineExceeded');
            unawaited(coordinator.run([const DelayTestTarget('a', 'url')]));
            clock.elapse(const Duration(seconds: 30));
            expect(coordinator.busy, isFalse);
            coordinator.dispose();
          }));

  test(
      'binding validates index and identity, pending is ephemeral, result owns profile',
      () async {
    store.bindCatalog(_catalog('a', 'scope'));
    expect(
        store.beginCatalogTest(
            catalogId: 'scope', nodeIndex: 3, identityKey: _key, testUrl: _url),
        isNull);
    expect(
        store.beginCatalogTest(
            catalogId: 'scope',
            nodeIndex: 0,
            identityKey: 'bad',
            testUrl: _url),
        isNull);
    final target = store.beginCatalogTest(
        catalogId: 'scope', nodeIndex: 0, identityKey: _key, testUrl: _url)!;
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isTrue);
    expect(
        store.isCatalogPending('scope', _key, testUrl: 'different'), isFalse);
    await store.finishCatalogTest(target, 120);
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    expect(store.read('a', _key, testUrl: _url)!.delayMs, 120);
    expect(store.read('b', _key, testUrl: _url), isNull);
    await store.flush();
    final persisted =
        await File('${directory.path}/health.json').readAsString();
    for (final secret in ['scope', 'same-name', 'secret-token', 'pending']) {
      expect(persisted, isNot(contains(secret)));
    }
  });

  test(
      'release, clear, same-id rebind and deletion revoke already captured results',
      () async {
    for (final action in ['release', 'clear', 'rebind', 'delete']) {
      store.bindCatalog(_catalog('a', 'scope'));
      final target = store.beginCatalogTest(
          catalogId: 'scope', nodeIndex: 0, identityKey: _key, testUrl: _url)!;
      switch (action) {
        case 'release':
          store.unbindCatalog('scope');
        case 'clear':
          store.clearCatalogBindings();
        case 'rebind':
          store.bindCatalog(_catalog('b', 'scope'));
        case 'delete':
          await store.removeProfile('a');
      }
      await store.finishCatalogTest(target, 999);
      expect(store.read('a', _key, testUrl: _url), isNull, reason: action);
      expect(store.read('b', _key, testUrl: _url), isNull, reason: action);
      expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    }
  });

  test(
      'loading race cannot resurrect deleted profile and flush drains catalog writes',
      () async {
    final fileReady = Completer<File>();
    final delayed = NodeHealthStore(fileProvider: () => fileReady.future);
    addTearDown(delayed.dispose);
    delayed.bindCatalog(_catalog('a', 'scope'));
    final target = delayed.beginCatalogTest(
        catalogId: 'scope', nodeIndex: 0, identityKey: _key, testUrl: _url)!;
    final write = delayed.finishCatalogTest(target, 77);
    final deletion = delayed.removeProfile('a');
    fileReady.complete(File('${directory.path}/delayed.json'));
    await Future.wait([write, deletion, delayed.flush()]);
    expect(delayed.read('a', _key, testUrl: _url), isNull);
    delayed.bindCatalog(_catalog('a', 'new'));
    final latest = delayed.beginCatalogTest(
        catalogId: 'new', nodeIndex: 0, identityKey: _key, testUrl: _url)!;
    unawaited(delayed.finishCatalogTest(latest, 88));
    await delayed.flush();
    final restored = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/delayed.json'));
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.read('a', _key, testUrl: _url)!.delayMs, 88);
  });

  test('catalog route never calls live callbacks and does not create singleton',
      () async {
    store.bindCatalog(_catalog('a', 'scope'));
    final core = _CatalogCore();
    var liveTests = 0, liveStarts = 0, liveResults = 0;
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async {
          liveTests++;
          return const DelayTestResult(9);
        },
        liveStarted: (_) => liveStarts++,
        liveResult: (_, __) => liveResults++,
        catalogInterface: () => core,
        healthStore: () => store,
        cancelRequest: (_) async {});
    addTearDown(coordinator.dispose);
    await coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    await store.awaitCatalogWrites();
    expect(core.calls.single.$1, 'scope');
    expect(store.read('a', _key, testUrl: _url)!.delayMs, 120);
    expect([liveTests, liveStarts, liveResults], [0, 0, 0]);
    expect(ClashCore.existingInterface, isNull);
    await coordinator.run([const DelayTestTarget('live', 'url')]);
    expect([liveTests, liveStarts, liveResults], [1, 1, 1]);
  });

  test('catalog capacity rejection retains history and completes pending state',
      () async {
    store.dispose();
    store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'),
        maxEntries: 1);
    await store.record(
        profileId: 'old', identityKey: _key, delayMs: 10, testUrl: _url);
    store.bindCatalog(_catalog('new', 'scope'));
    final core = _CatalogCore();
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async => throw StateError('live route'),
        liveStarted: (_) => fail('live start'),
        liveResult: (_, __) => fail('live result'),
        catalogInterface: () => core,
        healthStore: () => store,
        cancelRequest: (_) async {});
    addTearDown(coordinator.dispose);
    await coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    await store.awaitCatalogWrites();
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    expect(store.lastErrorCode, 'capacityExceeded');
    expect(store.read('old', _key, testUrl: _url)?.delayMs, 10);
    expect(store.read('new', _key, testUrl: _url), isNull);
    await store.flush();
    expect(store.lastErrorCode, 'capacityExceeded');
    final restored = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'));
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.read('old', _key, testUrl: _url)?.delayMs, 10);
    expect(restored.read('new', _key, testUrl: _url), isNull);
  });

  test(
      'control failures and unavailable Core preserve prior actual measurement',
      () async {
    store.bindCatalog(_catalog('a', 'scope'));
    await store.record(
        profileId: 'a', identityKey: _key, delayMs: 10, testUrl: _url);
    final core = _CatalogCore();
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async => throw StateError('live route'),
        liveStarted: (_) => fail('live start'),
        liveResult: (_, __) => fail('live result'),
        catalogInterface: () => core,
        healthStore: () => store,
        cancelRequest: (_) async {});
    addTearDown(coordinator.dispose);
    for (final reason in [
      'cancelled',
      'batchDeadlineExceeded',
      'configChanged',
      'uiInactive',
      'sessionClosed',
      'overloaded',
      'transportFailure',
      'clientFailure',
      'catalogNotFound',
      'unknown'
    ]) {
      core.result = DelayTestResult(-1, reason: reason);
      await coordinator.run(
          [const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
      await store.awaitCatalogWrites();
      expect(store.read('a', _key, testUrl: _url)!.delayMs, 10, reason: reason);
      expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    }
    core.result = const DelayTestResult(-1, reason: 'testFailed');
    await coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    await store.awaitCatalogWrites();
    expect(store.read('a', _key, testUrl: _url)!.delayMs, -1);
  });

  test(
      'no Core, disabled feature and malformed scoped target never enter live route',
      () async {
    store.bindCatalog(_catalog('a', 'scope'));
    final core = _CatalogCore();
    ClashHandlerInterface? available;
    NodeHealthStore? enabled = store;
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async => throw StateError('live route'),
        liveStarted: (_) => fail('live start'),
        liveResult: (_, __) => fail('live result'),
        catalogInterface: () => available,
        healthStore: () => enabled,
        cancelRequest: (_) async {});
    addTearDown(coordinator.dispose);
    var result = await coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    expect(result.failed, 1);
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    available = core;
    enabled = null;
    result = await coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    expect(result.reason, 'uiInactive');
    enabled = store;
    await coordinator.run([
      const DelayTestTarget(_key, _url, nodeIndex: 0),
      const DelayTestTarget(_key, _url, scope: 'scope')
    ]);
    expect(core.calls, isEmpty);
    expect(store.read('a', _key, testUrl: _url), isNull);
    expect(ClashCore.existingInterface, isNull);
  });

  test(
      'catalog cancel removes pending and delayed success cannot overwrite history',
      () async {
    store.bindCatalog(_catalog('a', 'scope'));
    await store.record(
        profileId: 'a', identityKey: _key, delayMs: 10, testUrl: _url);
    final core = _CatalogCore()..pending = Completer<DelayTestResult>();
    var cancellations = 0;
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async => throw StateError('live route'),
        liveStarted: (_) => fail('live start'),
        liveResult: (_, __) => fail('live result'),
        catalogInterface: () => core,
        healthStore: () => store,
        cancelRequest: (_) async {
          cancellations++;
        });
    addTearDown(coordinator.dispose);
    final batch = coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isTrue);
    await coordinator.cancel();
    await batch;
    expect(cancellations, 1);
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    core.pending!.complete(const DelayTestResult(999));
    await Future<void>.value();
    await store.awaitCatalogWrites();
    expect(store.read('a', _key, testUrl: _url)!.delayMs, 10);
  });

  test('disposing a routed coordinator clears catalog pending without a result',
      () async {
    store.bindCatalog(_catalog('a', 'scope'));
    final core = _CatalogCore()..pending = Completer<DelayTestResult>();
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async => throw StateError('live route'),
        liveStarted: (_) => fail('live start'),
        liveResult: (_, __) => fail('live result'),
        catalogInterface: () => core,
        healthStore: () => store,
        cancelRequest: (_) async {});
    final batch = coordinator
        .run([const DelayTestTarget(_key, _url, scope: 'scope', nodeIndex: 0)]);
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isTrue);
    coordinator.dispose();
    await batch;
    expect(store.isCatalogPending('scope', _key, testUrl: _url), isFalse);
    core.pending!.complete(const DelayTestResult(99));
    await Future<void>.value();
    expect(store.read('a', _key, testUrl: _url), isNull);
  });

  test(
      'missing catalog stops queued requests and exposes the fixed batch reason',
      () async {
    final nodes = [
      for (var i = 0; i < 20; i++)
        _catalog('a', 'scope').nodes.single.copyWith(
            identityKey: i.toRadixString(16).padLeft(32, '0'), coreIndex: i)
    ];
    store.bindCatalog(_catalog('a', 'scope').copyWith(nodes: nodes));
    final core = _CatalogCore()
      ..result = const DelayTestResult(-1, reason: 'catalogNotFound');
    final coordinator = createDelayTestRouter(
        liveTest: (_, __, ___) async => throw StateError('live route'),
        liveStarted: (_) => fail('live start'),
        liveResult: (_, __) => fail('live result'),
        catalogInterface: () => core,
        healthStore: () => store,
        cancelRequest: (_) async {});
    addTearDown(coordinator.dispose);
    final result = await coordinator.run([
      for (final node in nodes)
        DelayTestTarget(node.identityKey, _url,
            scope: 'scope', nodeIndex: node.coreIndex)
    ]);
    expect(result.reason, 'catalogNotFound');
    expect(core.calls.length, 10,
        reason: 'Only the already-started worker budget may reach Core');
    await store.awaitCatalogWrites();
    expect(store.readProfile('a', testUrl: _url), isEmpty);
    for (final node in nodes) {
      expect(store.isCatalogPending('scope', node.identityKey, testUrl: _url),
          isFalse);
    }
  });
}
