import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late File file;
  final now = DateTime.utc(2026, 10, 15, 8);
  const url = 'https://probe.example/secret-token';
  const key = '0123456789abcdef0123456789abcdef';
  const secondKey = 'abcdef0123456789abcdef0123456789';

  NodeHealthStore createStore({int maxEntries = 5000}) => NodeHealthStore(
        fileProvider: () async => file,
        now: () => now,
        maxEntries: maxEntries,
      );

  Map<String, Object?> entry({
    int delay = 100,
    DateTime? at,
    String? reason,
  }) =>
      {
        'd': delay,
        't': (at ?? now).millisecondsSinceEpoch,
        'r': reason,
        'u': NodeHealthStore.hashTestUrl(url),
      };

  Future<void> snapshot(Map<String, Object?> entries, {int version = 1}) =>
      file.writeAsString(
        jsonEncode({'version': version, 'entries': entries}),
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('node-health-test-');
    file = File('${directory.path}/node_health_v1.json');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('round trips only hashed identifiers and numeric health fields',
      () async {
    expect(NodeHealthStore.hashTestUrl(url), '9b8eca88385f4b47');
    final store = createStore();
    await store.record(
      profileId: 'profile-a',
      identityKey: key,
      delayMs: 183,
      testUrl: url,
    );
    await store.flush();
    final raw = await file.readAsString();
    expect(raw, isNot(contains(url)));
    expect(raw, isNot(contains('secret-token')));
    final json = jsonDecode(raw) as Map<String, dynamic>;
    expect(json.keys, unorderedEquals(['version', 'entries']));
    expect(json['version'], 2);
    expect(json['entries']['profile-a'][key], {
      'd': 183,
      't': now.millisecondsSinceEpoch,
      'r': null,
      'u': NodeHealthStore.hashTestUrl(url),
    });
    store.dispose();
    final restored = createStore();
    await restored.load();
    expect(restored.read('profile-a', key, testUrl: url)?.delayMs, 183);
    expect(restored.read('profile-a', key, testUrl: url)?.testedAt, now);
    restored.dispose();
  });

  test('URL changes hide earlier results and profiles remain isolated',
      () async {
    final store = createStore();
    for (final profile in ['a', 'b']) {
      await store.record(
        profileId: profile,
        identityKey: key,
        delayMs: profile == 'a' ? 100 : 200,
        testUrl: url,
      );
    }
    expect(store.read('a', key, testUrl: url)?.delayMs, 100);
    expect(store.read('b', key, testUrl: url)?.delayMs, 200);
    expect(store.read('a', key, testUrl: '$url-changed'), isNull);
    expect(store.readProfile('a', testUrl: '$url-changed'), isEmpty);
    await store.flush();
    store.dispose();
  });

  test('same delay refreshes the timestamp and listeners', () async {
    final store = createStore();
    var changes = 0;
    store.addListener(() => changes++);
    await store.record(
      profileId: 'a',
      identityKey: key,
      delayMs: 123,
      testUrl: url,
      testedAt: now.subtract(const Duration(minutes: 20)),
    );
    await store.record(
      profileId: 'a',
      identityKey: key,
      delayMs: 123,
      testUrl: url,
    );
    expect(store.read('a', key, testUrl: url)?.testedAt, now);
    expect(changes, 2);
    await store.flush();
    store.dispose();
  });

  test('older completions cannot replace a newer result', () async {
    final store = createStore();
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 100, testUrl: url);
    await store.record(
      profileId: 'a',
      identityKey: key,
      delayMs: -1,
      testUrl: url,
      reason: 'testFailed',
      testedAt: now.subtract(const Duration(seconds: 1)),
    );
    expect(store.read('a', key, testUrl: url)?.delayMs, 100);
    await store.flush();
    store.dispose();
  });

  test('loading marker is ignored and failure reasons are allowlisted',
      () async {
    final store = createStore();
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 0, testUrl: url);
    expect(store.readProfile('a', testUrl: url), isEmpty);
    await store.record(
      profileId: 'a',
      identityKey: key,
      delayMs: -9,
      testUrl: url,
      reason: 'failure at https://example/credential',
    );
    expect(store.read('a', key, testUrl: url), isNull);
    await store.record(
      profileId: 'a',
      identityKey: secondKey,
      delayMs: -1,
      testUrl: url,
      reason: 'deadlineExceeded',
    );
    await store.flush();
    expect(await file.readAsString(), isNot(contains('credential')));
    expect(
        store.read('a', secondKey, testUrl: url)?.reason, 'deadlineExceeded');
    store.dispose();
  });

  const controlReasons = <String?>[
    'cancelled',
    'configChanged',
    'sessionClosed',
    'uiInactive',
    'transportFailure',
    'clientFailure',
    'overloaded',
    'notFound',
    'invalidParameters',
    'duplicateRequest',
    'busy',
    'batchDeadlineExceeded',
    'unknownFailure',
    null,
  ];

  for (final reason in controlReasons) {
    test('control failure $reason preserves prior measurement and empty state',
        () async {
      final store = createStore();
      addTearDown(store.dispose);
      final measuredAt = now.subtract(const Duration(minutes: 3));
      await store.record(
        profileId: 'a',
        identityKey: key,
        delayMs: 100,
        testUrl: url,
        testedAt: measuredAt,
      );
      await store.flush();
      final persisted = await file.readAsString();
      var changes = 0;
      store.addListener(() => changes++);
      for (final identity in [key, secondKey]) {
        await store.record(
          profileId: 'a',
          identityKey: identity,
          delayMs: -1,
          testUrl: url,
          reason: reason,
        );
      }
      final retained = store.read('a', key, testUrl: url)!;
      expect(retained.delayMs, 100);
      expect(retained.testedAt, measuredAt);
      expect(retained.reason, isNull);
      expect(store.read('a', secondKey, testUrl: url), isNull);
      expect(changes, 0);
      await store.flush();
      expect(await file.readAsString(), persisted);
    });
  }

  for (final reason in ['testFailed', 'deadlineExceeded']) {
    test('measured failure $reason replaces success and survives reopening',
        () async {
      final store = createStore();
      addTearDown(store.dispose);
      await store.record(
        profileId: 'a',
        identityKey: key,
        delayMs: 100,
        testUrl: url,
        testedAt: now.subtract(const Duration(minutes: 3)),
      );
      await store.record(
        profileId: 'a',
        identityKey: key,
        delayMs: -1,
        testUrl: url,
        reason: reason,
      );
      expect(store.read('a', key, testUrl: url)?.delayMs, -1);
      expect(store.read('a', key, testUrl: url)?.testedAt, now);
      expect(store.read('a', key, testUrl: url)?.reason, reason);
      await store.flush();
      final restored = createStore();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.read('a', key, testUrl: url)?.delayMs, -1);
      expect(restored.read('a', key, testUrl: url)?.reason, reason);
      expect(restored.read('a', key, testUrl: url)?.testedAt, now);
    });
  }

  test('v1 migration drops all ambiguous failures and preserves success',
      () async {
    final invalidReasons = [...controlReasons, 'deadlineExceeded'];
    final invalidKeys = List.generate(
        invalidReasons.length, (i) => i.toRadixString(16).padLeft(32, '0'));
    await snapshot({
      'a': {
        key: entry(delay: 123),
        secondKey: entry(delay: -1, reason: 'testFailed'),
        for (var i = 0; i < invalidKeys.length; i++)
          invalidKeys[i]: entry(delay: -1, reason: invalidReasons[i]),
      }
    });
    final store = createStore();
    addTearDown(store.dispose);
    await store.load();
    expect(store.readProfile('a', testUrl: url).keys, [key]);
    expect(store.read('a', key, testUrl: url)?.delayMs, 123);
    expect(store.read('a', secondKey, testUrl: url), isNull);
    expect(store.lastErrorCode, isNull);
    await store.flush();
    final migrated = jsonDecode(await file.readAsString()) as Map;
    expect(migrated['version'], 2);
    expect((migrated['entries']['a'] as Map).keys, [key]);
  });

  test('v2 load excludes nonmeasurement failures without losing valid peers',
      () async {
    await snapshot({
      'a': {
        key: entry(delay: -1, reason: 'deadlineExceeded'),
        secondKey: entry(delay: -1, reason: 'configChanged'),
      }
    }, version: 2);
    final store = createStore();
    addTearDown(store.dispose);
    await store.load();
    expect(store.read('a', key, testUrl: url)?.reason, 'deadlineExceeded');
    expect(store.read('a', secondKey, testUrl: url), isNull);
    expect(store.lastErrorCode, isNull);
    await store.flush();
    final persisted = jsonDecode(await file.readAsString()) as Map;
    expect((persisted['entries']['a'] as Map).keys, [key]);
  });

  test('unhashed keys are rejected before writing', () async {
    final store = createStore();
    await expectLater(
      store.record(
          profileId: 'a',
          identityKey: 'server.example',
          delayMs: 1,
          testUrl: url),
      throwsArgumentError,
    );
    expect(file.existsSync(), isFalse);
    store.dispose();
  });

  test('staleness starts strictly after ten minutes', () {
    final health = NodeHealthRecord(
      delayMs: 1,
      testedAt: now,
      testUrlHash: NodeHealthStore.hashTestUrl(url),
    );
    expect(health.isStale(now.add(const Duration(minutes: 10))), isFalse);
    expect(
        health.isStale(now.add(const Duration(minutes: 10, milliseconds: 1))),
        isTrue);
  });

  test('load drops records older than seven days and bounds total count',
      () async {
    await snapshot({
      'a': {
        key: entry(at: now.subtract(const Duration(days: 7, milliseconds: 1)))
      },
      'b': {key: entry(delay: 200, at: now.subtract(const Duration(days: 7)))},
      'c': {key: entry(delay: 300)},
    });
    final store = createStore(maxEntries: 1);
    await store.load();
    expect(store.readProfile('a', testUrl: url), isEmpty);
    expect(store.readProfile('b', testUrl: url), isEmpty);
    expect(store.read('c', key, testUrl: url)?.delayMs, 300);
    store.dispose();
  });

  test('capacity eviction uses measurement time across profiles', () async {
    final store = createStore(maxEntries: 2);
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 1, testUrl: url);
    await store.record(
      profileId: 'b',
      identityKey: key,
      delayMs: 2,
      testUrl: url,
      testedAt: now.subtract(const Duration(minutes: 2)),
    );
    await store.record(
      profileId: 'a',
      identityKey: secondKey,
      delayMs: 3,
      testUrl: url,
      testedAt: now.subtract(const Duration(minutes: 1)),
    );
    expect(store.readProfile('b', testUrl: url), isEmpty);
    expect(store.readProfile('a', testUrl: url).length, 2);
    await store.flush();
    store.dispose();
  });

  test('the seven day boundary is retained and the default cap is 5000',
      () async {
    final keys =
        List.generate(5001, (i) => i.toRadixString(16).padLeft(32, '0'));
    await snapshot({
      'a': {
        for (var i = 0; i < keys.length; i++)
          keys[i]: entry(at: now.subtract(Duration(seconds: i))),
      },
    });
    final store = createStore();
    await store.load();
    expect(store.readProfile('a', testUrl: url), hasLength(5000));
    expect(store.read('a', keys.last, testUrl: url), isNull);
    store.dispose();

    await snapshot({
      'a': {
        key: entry(at: now.subtract(const Duration(days: 7))),
        secondKey:
            entry(at: now.subtract(const Duration(days: 7, milliseconds: 1))),
      },
    });
    final boundary = createStore();
    await boundary.load();
    expect(boundary.readProfile('a', testUrl: url).keys, [key]);
    boundary.dispose();
  });

  for (final damaged in [
    '{broken',
    '{"version":99,"entries":{}}',
    '{"version":1,"entries":{"a":{"not-a-hash":{}}}}'
  ]) {
    test('damaged snapshot is quarantined and starts empty: $damaged',
        () async {
      await file.writeAsString(damaged);
      await File('${file.path}.corrupt-1').writeAsString('old');
      final unrelated = File('${directory.path}/other.corrupt-1');
      await unrelated.writeAsString('preserve');
      final store = createStore();
      await store.load();
      expect(store.readProfile('a', testUrl: url), isEmpty);
      expect(file.existsSync(), isFalse);
      final backups = await directory
          .list()
          .where((entity) => path
              .basename(entity.path)
              .startsWith('node_health_v1.json.corrupt-'))
          .toList();
      expect(backups, hasLength(1));
      expect(await File(backups.single.path).readAsString(), damaged);
      expect(await unrelated.readAsString(), 'preserve');
      store.dispose();
    });
  }

  test('writes debounce for two seconds and a later result resets the timer',
      () async {
    final store = createStore();
    await store.load();
    fakeAsync((clock) {
      unawaited(store.record(
          profileId: 'a', identityKey: key, delayMs: 100, testUrl: url));
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(milliseconds: 1500));
      expect(file.existsSync(), isFalse);
      unawaited(store.record(
          profileId: 'a', identityKey: key, delayMs: 200, testUrl: url));
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(milliseconds: 1500));
      expect(file.existsSync(), isFalse);
      expect(clock.nonPeriodicTimerCount, 1);
    });
    await store.flush();
    expect(
        (jsonDecode(await file.readAsString()) as Map)['entries']['a'][key]
            ['d'],
        200);
    store.dispose();
  });

  test('load, record, and removal retain invocation order', () async {
    await snapshot({
      'a': {key: entry()}
    });
    final gate = Completer<File>();
    final store =
        NodeHealthStore(fileProvider: () => gate.future, now: () => now);
    final recording = store.record(
        profileId: 'a', identityKey: secondKey, delayMs: 1, testUrl: url);
    final removing = store.removeProfile('a');
    gate.complete(file);
    await Future.wait([recording, removing]);
    expect(store.readProfile('a', testUrl: url), isEmpty);
    await store.flush();
    expect((jsonDecode(await file.readAsString()) as Map)['entries'], isEmpty);
    store.dispose();
  });

  test('debounced writes persist without an explicit flush call', () async {
    final store = createStore();
    final written = directory.watch().first.timeout(const Duration(seconds: 5));
    final stopwatch = Stopwatch()..start();
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 8, testUrl: url);
    await written;
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(1900));
    // Drain the already-started write before inspecting its committed snapshot.
    await store.flush();
    expect(
        (jsonDecode(await file.readAsString()) as Map)['entries']['a'][key]
            ['d'],
        8);
    store.dispose();
  });

  test('failed writes preserve the previous snapshot and allow retry',
      () async {
    final store = createStore();
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 1, testUrl: url);
    await store.flush();
    final original = await file.readAsString();
    final blockedPending = Directory('${file.path}.pending');
    await blockedPending.create();
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 2, testUrl: url);
    await expectLater(store.flush(), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), original);
    expect(store.lastErrorCode, 'writeFailed');
    await blockedPending.delete();
    await store.flush();
    expect(
        (jsonDecode(await file.readAsString()) as Map)['entries']['a'][key]
            ['d'],
        2);
    expect(store.lastErrorCode, isNull);
    store.dispose();
  });

  test('overlapping flushes preserve the latest update and profile removal',
      () async {
    final store = createStore();
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 1, testUrl: url);
    final first = store.flush();
    await store.record(
        profileId: 'b', identityKey: key, delayMs: 2, testUrl: url);
    await store.removeProfile('a');
    final second = store.flush();
    await Future.wait([first, second]);
    final restored = createStore();
    await restored.load();
    expect(restored.readProfile('a', testUrl: url), isEmpty);
    expect(restored.read('b', key, testUrl: url)?.delayMs, 2);
    expect(File('${file.path}.pending').existsSync(), isFalse);
    restored.dispose();
    store.dispose();
  });

  test('dispose cancels debounce and explicit flush can finish pending data',
      () async {
    final store = createStore();
    await store.load();
    fakeAsync((clock) {
      unawaited(store.record(
          profileId: 'a', identityKey: key, delayMs: 1, testUrl: url));
      clock.flushMicrotasks();
      expect(clock.nonPeriodicTimerCount, 1);
      store.dispose();
      expect(clock.nonPeriodicTimerCount, 0);
    });
    await store.flush();
    expect(file.existsSync(), isTrue);
  });

  test('dispose while loading rejects the pending record without a timer',
      () async {
    final gate = Completer<File>();
    final store =
        NodeHealthStore(fileProvider: () => gate.future, now: () => now);
    final recording = store.record(
        profileId: 'a', identityKey: key, delayMs: 1, testUrl: url);
    final rejected = expectLater(recording, throwsStateError);
    store.dispose();
    gate.complete(file);
    await rejected;
    await store.flush();
    expect(file.existsSync(), isFalse);
  });

  test('read failures are observable and cannot overwrite unreadable cache',
      () async {
    await Directory(file.path).create();
    final errors = <String>[];
    final store = NodeHealthStore(
        fileProvider: () async => file, onError: errors.add, now: () => now);
    await store.record(
        profileId: 'a', identityKey: key, delayMs: 1, testUrl: url);
    await expectLater(store.flush(), throwsStateError);
    expect(errors, contains('writeFailed'));
    expect(Directory(file.path).existsSync(), isTrue);
    store.dispose();
  });
}
