import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/clash/interface.dart';
import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flclashx/common/delay_tests.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_tester.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements ClashHandlerInterface {
  @override
  Future<DelayTestResult> catalogTestDelay(
          String catalogId, int index, String url,
          {required String requestId,
          Duration timeout = const Duration(seconds: 5)}) async =>
      const DelayTestResult(42);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailableHealthStore extends NodeHealthStore {
  _UnavailableHealthStore(Future<File> Function() fileProvider)
      : super(fileProvider: fileProvider);
  bool failWrites = true;

  @override
  Future<void> flush() => failWrites
      ? Future.error(StateError('Fixture persistence failure'))
      : super.flush();
}

void main() {
  late Directory temp;
  late NodeHealthStore store;
  late DelayTestCoordinator coordinator;
  late NodeCatalogService service;
  late NodeCatalogTester tester;
  late List<String> lifecycle;
  late List<DelayTestTarget> tested;
  late Set<String> valid;
  late String? activeId;
  Future<DelayTestResult> Function(DelayTestTarget)? testOverride;
  Future<void> Function()? prepareGate;
  Map<String, dynamic> Function(String)? rawOverride;
  String? Function(List<Map<String, dynamic>>)? prepareFailure;

  Map<String, dynamic> raw(String id) => {
        'proxies': [
          {'name': 'Same', 'type': 'ss', 'server': '$id.invalid', 'port': 443},
          {
            'name': 'Other',
            'type': 'ss',
            'server': '$id-other.invalid',
            'port': 443
          },
        ],
      };
  CatalogTestSelection selection(String id, {bool one = false}) => (
        profile: Profile(id: id, autoUpdateDuration: Duration.zero),
        nodes:
            buildProfileCatalog(profileId: id, fingerprint: 'f', raw: raw(id))
                .nodes
                .take(one ? 1 : 2)
                .toList(),
      );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fcx-catalog-orchestration-');
    store = NodeHealthStore(
        fileProvider: () async => File('${temp.path}/history.json'));
    lifecycle = [];
    tested = [];
    valid = {'a', 'b', 'c', 'd', 'e'};
    activeId = 'a';
    testOverride = null;
    prepareGate = null;
    rawOverride = null;
    prepareFailure = null;
    service = NodeCatalogService(
      readProfileConfig: (id) async => rawOverride?.call(id) ?? raw(id),
      evaluate: (value) async => value,
      fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
      scriptFingerprint: () => '',
      prepareCatalog: (id, proxies, providers) async {
        lifecycle.add('prepare:$id');
        await prepareGate?.call();
        final reason = prepareFailure?.call(proxies);
        if (reason != null) throw CatalogBuildException(reason);
        return jsonEncode({
          'catalog-id': id,
          'nodes': [
            for (var index = 0; index < proxies.length; index++)
              {'index': index, 'supported': true, 'reason': ''},
          ]
        });
      },
      releaseCatalog: (id) async {
        lifecycle.add('release:$id');
        return true;
      },
    );
    coordinator = DelayTestCoordinator(
      test: (target, request, timeout) async {
        tested.add(target);
        lifecycle.add('test:${target.scope}');
        return testOverride?.call(target) ?? const DelayTestResult(42);
      },
      cancelRequest: (_) async {},
      onStarted: (_) {},
      onResult: (_, __) {},
    );
    tester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (p) => valid.contains(p.id),
        activeProfileId: () => activeId);
  });
  tearDown(() async {
    tester.dispose();
    coordinator.dispose();
    await store.flush();
    store.dispose();
    await temp.delete(recursive: true);
  });

  test('more than three profiles prepare test and release one at a time',
      () async {
    final result = await tester.testVisible([
      for (final id in ['a', 'b', 'c', 'd', 'e']) selection(id, one: true)
    ], 'https://fixture.invalid');
    expect(result.completed, 4);
    expect(result.failed, 0);
    expect(result.reason, isNull);
    expect(tested, hasLength(4));
    expect(
        tested.every((target) => target.scope != null && target.nodeIndex == 0),
        isTrue);
    for (var i = 0; i < lifecycle.length; i += 3) {
      final id = lifecycle[i].substring('prepare:'.length);
      expect(lifecycle.sublist(i, i + 3),
          ['prepare:$id', 'test:$id', 'release:$id']);
    }
  });

  test('selection only tests requested identities after a fresh preparation',
      () async {
    final selected = selection('b', one: true);
    await tester.testVisible([selected], 'https://fixture.invalid');
    expect(tested.single.name, selected.nodes.single.identityKey);
    expect(tested.single.nodeIndex, 0);
  });

  test('all profiles includes active and offscreen configurations', () async {
    final result = await tester.testAll([
      for (final id in ['a', 'b', 'c', 'd', 'e']) selection(id).profile,
    ], 'u');
    expect(result.completed, 10);
    expect(result.failed, 0);
    expect(result.untested, 0);
    expect(result.issues, isEmpty);
    expect(result.reason, isNull);
    expect(tested.map((target) => target.name).toSet(), {
      for (final id in ['a', 'b', 'c', 'd', 'e'])
        ...selection(id).nodes.map((node) => node.identityKey),
    });
    expect(
        lifecycle.where((event) => event.startsWith('release:')), hasLength(5));
  });

  test('bad configuration between healthy profiles cannot stop the batch',
      () async {
    rawOverride = (id) => id == 'b' ? {'proxies': 'malformed'} : raw(id);
    final result = await tester.testAll([
      for (final id in ['a', 'b', 'c']) selection(id).profile,
    ], 'u');
    expect(result.completed, 4);
    expect(result.reason, isNull);
    expect(result.issues.single.profileId, 'b');
    expect(result.issues.single.reason, 'parseFailed');
    expect(tested.last.name, selection('c').nodes.last.identityKey);
  });

  test('failed Core preparation cannot stop subsequent configurations',
      () async {
    prepareFailure = (proxies) =>
        proxies.first['server'] == 'b.invalid' ? 'parseFailed' : null;
    final result = await tester.testAll([
      for (final id in ['a', 'b', 'c']) selection(id).profile,
    ], 'u');
    expect(result.completed, 4);
    expect(result.untested, 2);
    expect(result.issues.single.profileId, 'b');
    expect(result.reason, isNull);
    expect(
        lifecycle.where((event) => event.startsWith('release:')), hasLength(3));
  });

  test('unsupported and malformed nodes are counted, not silently omitted',
      () async {
    rawOverride = (_) => {
          'proxies': [
            (raw('b')['proxies'] as List).first,
            {
              'name': 'Heavy',
              'type': 'tuic',
              'server': 'heavy.invalid',
              'port': 443
            },
            {'name': 'Broken', 'type': 'ss'},
          ],
        };
    final result = await tester.testAll([selection('b').profile], 'u');
    expect(result.completed, 1);
    expect(result.untested, 2);
    expect(result.issues.map((issue) => issue.reason),
        ['typeUnsupported', 'parseFailed']);
    expect(result.reason, isNull);
  });

  test('duplicate identities are explicit and cannot revoke healthy nodes',
      () async {
    final duplicate = (raw('b')['proxies'] as List).first;
    rawOverride = (_) => {
          'proxies': [duplicate, duplicate, (raw('b')['proxies'] as List).last],
        };
    final result = await tester.testAll([selection('b').profile], 'u');
    expect(result.completed, 1);
    expect(result.untested, 2);
    expect(result.issues.every((issue) => issue.reason == 'ambiguousNode'),
        isTrue);
    expect(tested.single.name, selection('b').nodes.last.identityKey);
  });

  test('all nodes beyond one Core catalog are tested in bounded chunks',
      () async {
    rawOverride = (_) => {
          'proxies': [
            for (var index = 0; index < 2001; index++)
              {
                'name': 'N$index',
                'type': 'ss',
                'server': 'fixture.invalid',
                'port': 443
              },
          ],
        };
    final result = await tester.testAll([selection('b').profile], 'u');
    expect(result.completed, 2001);
    expect(result.untested, 0);
    expect(result.issues, isEmpty);
    expect(tested.map((target) => target.scope).toSet(), hasLength(2));
    expect(
        lifecycle.where((event) => event.startsWith('release:')), hasLength(2));
  });

  test('ordinary node failure does not stop other nodes or profiles', () async {
    final broken = selection('b').nodes.first.identityKey;
    testOverride = (target) async => target.name == broken
        ? const DelayTestResult(-1, reason: 'testFailed')
        : const DelayTestResult(42);
    final result = await tester
        .testAll([selection('b').profile, selection('c').profile], 'u');
    expect(result.completed, 4);
    expect(result.failed, 1);
    expect(result.reason, isNull);
    expect(result.untested, 0);
  });

  test('catalog failure stops its requests but continues later profiles',
      () async {
    final broken = selection('b').nodes.first.identityKey;
    testOverride = (target) async => target.name == broken
        ? const DelayTestResult(-1, reason: 'catalogNotFound')
        : const DelayTestResult(42);
    final result = await tester
        .testAll([selection('b').profile, selection('c').profile], 'u');
    expect(result.reason, isNull);
    expect(tested.map((target) => target.name),
        containsAll(selection('c').nodes.map((node) => node.identityKey)));
    expect(result.issues.single.reason, 'catalogNotFound');
  });

  test('all batch cancellation during preparation releases late handles',
      () async {
    final gate = Completer<void>();
    prepareGate = () => gate.future;
    final run =
        tester.testAll([selection('b').profile, selection('c').profile], 'u');
    await Future<void>.delayed(Duration.zero);
    await tester.cancel();
    gate.complete();
    final result = await run;
    expect(result.reason, 'cancelled');
    expect(tested, isEmpty);
    expect(
        lifecycle.where((event) => event.startsWith('prepare:')), hasLength(1));
    expect(
        lifecycle.where((event) => event.startsWith('release:')), hasLength(1));
  });

  test('unavailable Core is unmeasured rather than failed node latency',
      () async {
    testOverride =
        (_) async => const DelayTestResult(-1, reason: 'coreUnavailable');
    final result = await tester.testAll([selection('b').profile], 'u');
    expect(result.reason, 'coreUnavailable');
    expect(result.completed, 0);
    expect(result.failed, 0);
    expect(result.untested, 2);
  });

  test('persistence failure is reported without stopping other profiles',
      () async {
    tester.dispose();
    store.dispose();
    final unavailable = _UnavailableHealthStore(
        () async => File('${temp.path}/unavailable-history.json'));
    store = unavailable;
    tester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (profile) => valid.contains(profile.id),
        activeProfileId: () => activeId);
    try {
      final result = await tester
          .testAll([selection('b').profile, selection('c').profile], 'u');
      expect(result.completed, 4);
      expect(result.failed, 0);
      expect(result.reason, isNull);
      expect(result.issues.map((issue) => issue.profileId), ['b', 'c']);
      expect(
          result.issues
              .every((issue) => issue.reason == 'healthStoreUnavailable'),
          isTrue);
    } finally {
      unavailable.failWrites = false;
    }
  });

  test('capacity summary belongs only to newly rejected catalog writes',
      () async {
    tester.dispose();
    coordinator.dispose();
    store.dispose();
    store = NodeHealthStore(
        fileProvider: () async => File('${temp.path}/capacity-history.json'),
        maxEntries: 1);
    final retained = selection('c').nodes.first.identityKey;
    await store.record(
        profileId: 'c', identityKey: retained, delayMs: 10, testUrl: 'u');
    await store.flush();
    rawOverride = (id) => {
          'proxies': [(raw(id)['proxies'] as List).first]
        };
    var injectUnrelatedRejection = false;
    coordinator = createDelayTestRouter(
      liveTest: (_, __, ___) async => throw StateError('Unexpected live test'),
      liveStarted: (_) => fail('Unexpected live event'),
      liveResult: (_, __) => fail('Unexpected live event'),
      catalogInterface: () {
        if (injectUnrelatedRejection) {
          unawaited(store.record(
              profileId: 'unrelated',
              identityKey: retained,
              delayMs: 99,
              testUrl: 'u'));
        }
        return _Transport();
      },
      healthStore: () => store,
      cancelRequest: (_) async {},
    );
    tester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (profile) => valid.contains(profile.id),
        activeProfileId: () => activeId);
    final result = await tester
        .testAll([selection('b').profile, selection('c').profile], 'u');
    expect(result.completed, 2);
    expect(result.failed, 0);
    expect(result.untested, 0);
    expect(result.issues.map((issue) => issue.profileId), ['b']);
    expect(result.issues.single.reason, 'healthCapacityExceeded');
    expect(result.issues.single.count, 1);
    expect(store.readProfile('b', testUrl: 'u'), isEmpty);
    expect(store.read('c', retained, testUrl: 'u')?.delayMs, 42);
    expect(store.lastErrorCode, 'capacityExceeded');

    final next = await tester.testAll([selection('c').profile], 'u');
    expect(next.completed, 1);
    expect(next.untested, 0);
    expect(next.issues, isEmpty);
    expect(store.lastErrorCode, 'capacityExceeded');
    expect(store.capacityRejectedWrites, 1);
    injectUnrelatedRejection = true;
    final unrelated = await tester.testAll([selection('c').profile], 'u');
    expect(unrelated.completed, 1);
    expect(unrelated.issues, isEmpty,
        reason: 'another entry point cannot alter this catalog summary');
    expect(store.capacityRejectedWrites, 2);
    final restored = NodeHealthStore(
        fileProvider: () async => File('${temp.path}/capacity-history.json'));
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.read('c', retained, testUrl: 'u')?.delayMs, 42);
    expect(restored.readProfile('b', testUrl: 'u'), isEmpty);
  });

  test('profile invalidation revokes results waiting for history loading',
      () async {
    tester.dispose();
    coordinator.dispose();
    store.dispose();
    final entered = Completer<void>();
    final loading = Completer<void>();
    store = NodeHealthStore(fileProvider: () async {
      entered.complete();
      await loading.future;
      return File('${temp.path}/delayed-history.json');
    });
    coordinator = createDelayTestRouter(
      liveTest: (_, __, ___) async => throw StateError('Unexpected live test'),
      liveStarted: (_) => fail('Unexpected live event'),
      liveResult: (_, __) => fail('Unexpected live event'),
      catalogInterface: () => _Transport(),
      healthStore: () => store,
      cancelRequest: (_) async {},
    );
    tester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (profile) => valid.contains(profile.id),
        activeProfileId: () => activeId);
    final run =
        tester.testAll([selection('b').profile, selection('c').profile], 'u');
    await entered.future;
    await Future<void>.delayed(Duration.zero);
    valid.remove('b');
    tester.profileChanged('b');
    loading.complete();
    final result = await run;
    expect(result.reason, isNull);
    expect(store.readProfile('b', testUrl: 'u'), isEmpty);
    expect(store.readProfile('c', testUrl: 'u'), hasLength(2));
    expect(result.issues.single.reason, 'configChanged');
  });

  test('a changed profile is skipped without cancelling the remaining batch',
      () async {
    final gate = Completer<void>();
    prepareGate = () => gate.future;
    final run =
        tester.testAll([selection('b').profile, selection('c').profile], 'u');
    await Future<void>.delayed(Duration.zero);
    valid.remove('b');
    tester.profileChanged('b');
    gate.complete();
    final result = await run;
    expect(result.reason, isNull);
    expect(result.completed, 2);
    expect(result.issues.single.reason, 'configChanged');
    expect(tested.map((target) => target.name),
        selection('c').nodes.map((node) => node.identityKey));
  });

  test('an active live batch refuses catalog preparation', () async {
    final waiting = Completer<DelayTestResult>();
    testOverride = (_) => waiting.future;
    final live = coordinator.run([const DelayTestTarget('Live', 'u')]);
    final result = await tester.testVisible([selection('b')], 'u');
    expect(result.reason, 'busy');
    expect(lifecycle.where((s) => s.startsWith('prepare:')), isEmpty);
    tester.disposeScope();
    expect(coordinator.busy, isTrue,
        reason: 'view teardown must not cancel another entry point');
    waiting.complete(const DelayTestResult(12));
    await live;
  });

  test('cancellation during prepare releases late resource without testing',
      () async {
    final gate = Completer<void>();
    prepareGate = () => gate.future;
    final future = tester.testVisible([selection('b')], 'u');
    await Future<void>.delayed(Duration.zero);
    expect(tester.busy, isTrue);
    await tester.cancel();
    gate.complete();
    final result = await future;
    expect(result.reason, 'cancelled');
    expect(tested, isEmpty);
    expect(lifecycle.map((s) => s.split(':').first), ['prepare', 'release']);
  });

  test('profile deletion while preparing cannot start a test', () async {
    final gate = Completer<void>();
    prepareGate = () => gate.future;
    final future = tester.testVisible([selection('b')], 'u');
    await Future<void>.delayed(Duration.zero);
    valid.remove('b');
    gate.complete();
    expect((await future).reason, 'configChanged');
    expect(tested, isEmpty);
    expect(lifecycle.last, startsWith('release:'));
  });

  test('disposed view cannot release a new view preparation or running batch',
      () async {
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    final request = Completer<DelayTestResult>();
    var preparations = 0;
    prepareGate = () => ++preparations == 1 ? oldGate.future : newGate.future;
    testOverride = (_) => request.future;
    final selected = selection('b', one: true);
    final oldRun = tester.testVisible([selected], 'u');
    await Future<void>.delayed(Duration.zero);
    tester.disposeScope();
    final newTester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (p) => valid.contains(p.id),
        activeProfileId: () => activeId);
    addTearDown(newTester.dispose);
    final newRun = newTester.testVisible([selected], 'u');
    await Future<void>.delayed(Duration.zero);
    expect(preparations, 2,
        reason: 'a new view must not inherit an abandoned prepare Future');
    newGate.complete();
    await Future<void>.delayed(Duration.zero);
    final newId = tested.single.scope!;
    oldGate.complete();
    expect((await oldRun).reason, 'cancelled');
    expect(coordinator.busy, isTrue);
    expect(newTester.pending('b', selected.nodes.single.identityKey), isTrue);
    expect(lifecycle, isNot(contains('release:$newId')));
    request.complete(const DelayTestResult(17));
    expect((await newRun).completed, 1);
    expect(lifecycle.where((entry) => entry == 'release:$newId'), hasLength(1));
  });

  test('live batch starting during preparation stays owned by its entry point',
      () async {
    final gate = Completer<void>();
    final request = Completer<DelayTestResult>();
    prepareGate = () => gate.future;
    testOverride = (_) => request.future;
    final catalog = tester.testVisible([selection('b')], 'u');
    await Future<void>.delayed(Duration.zero);
    final live = coordinator.run([const DelayTestTarget('Live', 'u')]);
    gate.complete();
    expect((await catalog).reason, 'busy');
    expect(tested.single.scope, isNull);
    tester.disposeScope();
    expect(coordinator.busy, isTrue);
    request.complete(const DelayTestResult(23));
    expect((await live).completed, 1);
    expect(lifecycle.last, startsWith('release:'));
  });

  test('pending state and progress belong to the running profile identity',
      () async {
    final waiting = Completer<DelayTestResult>();
    testOverride = (_) => waiting.future;
    final selected = selection('b', one: true);
    final future = tester.testVisible([selected], 'u');
    await Future<void>.delayed(Duration.zero);
    expect(tester.pending('b', selected.nodes.single.identityKey), isTrue);
    expect(tester.pending('c', selected.nodes.single.identityKey), isFalse);
    expect(tester.total, 1);
    expect(tester.completed, 0);
    waiting.complete(const DelayTestResult(9));
    expect((await future).completed, 1);
    expect(tester.busy, isFalse);
    expect(tester.pending('b', selected.nodes.single.identityKey), isFalse);
  });

  test(
      'view disposal cancels owned test and does not start subsequent profiles',
      () async {
    final waiting = Completer<DelayTestResult>();
    testOverride = (_) => waiting.future;
    final future = tester.testVisible([selection('b'), selection('c')], 'u');
    await Future<void>.delayed(Duration.zero);
    tester.disposeScope();
    final result = await future;
    expect(result.reason, 'uiInactive');
    expect(lifecycle.where((s) => s.startsWith('prepare:')), hasLength(1));
    waiting.complete(const DelayTestResult(99));
  });

  test('current-profile action uses unscoped shared coordinator requests',
      () async {
    final result =
        await tester.testCurrent([const DelayTestTarget('Live', 'u')]);
    expect(result.completed, 1);
    expect(tested.single.scope, isNull);
    expect(lifecycle.where((s) => s.startsWith('prepare:')), isEmpty);
  });

  test('current-profile delay batch lets every slow request reach its deadline',
      () {
    fakeAsync((clock) {
      testOverride = (_) => Future.delayed(const Duration(milliseconds: 4900),
          () => const DelayTestResult(4900));
      DelayBatchResult? result;
      tester.testCurrent([
        for (var index = 0; index < 70; index++)
          DelayTestTarget('Node $index', 'u'),
      ]).then((value) => result = value);
      clock.elapse(const Duration(seconds: 35));
      expect(tested, hasLength(70));
      expect(result?.completed, 70);
      expect(result?.reason, isNull);
    });
  });

  test('current-profile progress deduplicates requests without merging URLs',
      () async {
    final waiting = Completer<DelayTestResult>();
    testOverride = (_) => waiting.future;
    final run = tester.testCurrent(const [
      DelayTestTarget('Same', 'u'),
      DelayTestTarget('Same', 'u'),
      DelayTestTarget('Same', 'v'),
      DelayTestTarget('', 'u'),
    ]);
    expect(tester.total, 2);
    expect(tested.map((target) => target.url), ['u', 'v']);
    waiting.complete(const DelayTestResult(10));
    expect((await run).completed, 2);
  });

  test('service router and store persist isolated results before release',
      () async {
    tester.dispose();
    coordinator.dispose();
    var liveEvents = 0;
    coordinator = createDelayTestRouter(
      liveTest: (_, __, ___) async {
        liveEvents++;
        return const DelayTestResult(88);
      },
      liveStarted: (_) => liveEvents++,
      liveResult: (_, __) => liveEvents++,
      catalogInterface: () => _Transport(),
      healthStore: () => store,
      cancelRequest: (_) async {},
    );
    tester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (_) => true,
        activeProfileId: () => 'a');
    final selected = selection('b', one: true);
    final result =
        await tester.testVisible([selected], 'https://fixture.invalid');
    expect(result.completed, 1);
    expect(liveEvents, 0);
    expect(
        store
            .read('b', selected.nodes.single.identityKey,
                testUrl: 'https://fixture.invalid')
            ?.delayMs,
        42);
    expect(store.readProfile('a', testUrl: 'https://fixture.invalid'), isEmpty);
    expect(lifecycle.map((s) => s.split(':').first), ['prepare', 'release']);
  });

  test('collect stage reserves busy and cancellation prevents late preparation',
      () async {
    final gate = Completer<List<CatalogTestSelection>>();
    final future = tester.collectAndTest((_) => gate.future, 'u');
    expect(tester.busy, isTrue);
    expect(
        (await tester.testCurrent([const DelayTestTarget('Live', 'u')])).reason,
        'busy');
    await tester.cancel();
    gate.complete([selection('b')]);
    expect((await future).reason, 'cancelled');
    expect(lifecycle, isEmpty);
  });

  for (final stage in ['collect', 'prepare']) {
    test('hiding the window revokes pending $stage before a request starts',
        () async {
      tester.dispose();
      final activity = ValueNotifier(true);
      tester = NodeCatalogTester(
          service: service,
          store: store,
          coordinator: coordinator,
          isCurrentProfile: (_) => true,
          activeProfileId: () => 'a',
          activity: activity);
      final gate = Completer<void>();
      if (stage == 'prepare') prepareGate = () => gate.future;
      final future = stage == 'prepare'
          ? tester.testVisible([selection('b')], 'u')
          : tester.collectAndTest((_) async {
              await gate.future;
              return [selection('b')];
            }, 'u');
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.busy, isFalse);
      activity.value = false;
      activity.value = true;
      gate.complete();
      expect((await future).reason, 'cancelled');
      expect(tested, isEmpty);
      expect(lifecycle.where((s) => s.startsWith('prepare:')),
          hasLength(stage == 'prepare' ? 1 : 0));
    });
  }

  test('hidden view cannot start a new batch', () async {
    tester.dispose();
    tester = NodeCatalogTester(
        service: service,
        store: store,
        coordinator: coordinator,
        isCurrentProfile: (_) => true,
        activeProfileId: () => 'a',
        activity: ValueNotifier(false));
    expect(
        (await tester.testVisible([selection('b')], 'u')).reason, 'uiInactive');
    expect(
        (await tester.testCurrent([const DelayTestTarget('Live', 'u')])).reason,
        'uiInactive');
    expect(
        (await tester.collectAndTest((_) async => [selection('b')], 'u'))
            .reason,
        'uiInactive');
    expect(lifecycle, isEmpty);
  });
}
