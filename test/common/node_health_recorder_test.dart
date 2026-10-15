import 'dart:io';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late NodeHealthStore store;
  late NodeHealthRecorder recorder;
  var now = DateTime.utc(2026, 10, 15);
  const url = 'https://probe.invalid/204';
  Map<String, dynamic> config(String server) => {
        'proxies': <Object?>[
          {
            'name': 'same',
            'type': 'ss',
            'server': server,
            'port': 443,
            'password': 'private-fixture'
          },
        ],
      };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fcx-health-recorder-');
    now = DateTime.utc(2026, 10, 15);
    store = NodeHealthStore(
      fileProvider: () async => File('${directory.path}/health.json'),
      now: () => now,
    );
    recorder = NodeHealthRecorder(store: store, now: () => now);
  });
  tearDown(() async {
    await recorder.flush();
    store.dispose();
    await directory.delete(recursive: true);
  });

  test('start snapshot preserves profile and endpoint after runtime switches',
      () async {
    final old = recorder.capture(
        profileId: 'a', raw: config('old.invalid'), name: 'same', url: url)!;
    final current = recorder.capture(
        profileId: 'b', raw: config('new.invalid'), name: 'same', url: url)!;
    await recorder.record(old, 40);
    await recorder.record(old, -1, reason: 'configChanged');
    expect(store.read('a', old.identityKey, testUrl: url)?.delayMs, 40);
    expect(store.read('a', old.identityKey, testUrl: url)?.reason, isNull);
    expect(store.read('b', current.identityKey, testUrl: url), isNull);
    await recorder.record(current, 55);
    expect(store.read('a', old.identityKey, testUrl: url)?.delayMs, 40);
    expect(store.read('b', current.identityKey, testUrl: url)?.delayMs, 55);
  });

  test(
      'equal results update arrival time; loading and unknown groups are ignored',
      () async {
    final raw = config('fixture.invalid');
    final target =
        recorder.capture(profileId: 'a', raw: raw, name: 'same', url: url)!;
    expect(
        recorder.capture(
            profileId: 'a', raw: raw, name: 'auto-group', url: url),
        isNull);
    await recorder.record(target, 0);
    expect(store.readProfile('a', testUrl: url), isEmpty);
    await recorder.record(target, 42);
    final first = store.read('a', target.identityKey, testUrl: url)!.testedAt;
    now = now.add(const Duration(minutes: 1));
    await recorder.record(target, 42);
    expect(store.read('a', target.identityKey, testUrl: url)!.testedAt, now);
    expect(first, isNot(now));
  });

  test('deletion invalidates queued and late results without reviving history',
      () async {
    final target = recorder.capture(
        profileId: 'a',
        raw: config('fixture.invalid'),
        name: 'same',
        url: url)!;
    final pending = recorder.record(target, 42);
    final deletion = recorder.removeProfile('a');
    await Future.wait([pending, deletion]);
    await recorder.record(target, 43);
    expect(store.readProfile('a', testUrl: url), isEmpty);
  });

  test('targets and persistence contain no credential or raw endpoint',
      () async {
    final target = recorder.capture(
        profileId: 'a',
        raw: config('private.invalid'),
        name: 'same',
        url: url)!;
    await recorder.record(target, 34);
    await recorder.flush();
    final persisted =
        await File('${directory.path}/health.json').readAsString();
    for (final value in ['private-fixture', 'private.invalid', 'same', url]) {
      expect(persisted, isNot(contains(value)));
      expect(target.toString(), isNot(contains(value)));
    }
  });

  test('malformed nodes do not block healthy-node history or become targets',
      () async {
    final raw = config('healthy.invalid');
    (raw['proxies'] as List).addAll([
      {'name': 'broken', 'type': 'ss', 'password': 'secret-malformed'},
      {
        'name': 'peers-only',
        'type': 'wireguard',
        'private-key': 'secret-peer-key',
        'peers': [
          {'server': 'private-peer.invalid', 'port': 51820}
        ],
      },
      'secret-malformed-item',
    ]);
    final target =
        recorder.capture(profileId: 'a', raw: raw, name: 'same', url: url);
    expect(target, isNotNull);
    for (final name in ['broken', 'peers-only', '#4']) {
      expect(recorder.capture(profileId: 'a', raw: raw, name: name, url: url),
          isNull);
    }
    await recorder.record(target!, 63);
    await recorder.flush();
    expect(store.read('a', target.identityKey, testUrl: url)?.delayMs, 63);
    expect(store.readProfile('a', testUrl: url), hasLength(1));
    final persisted =
        await File('${directory.path}/health.json').readAsString();
    for (final secret in [
      'healthy.invalid',
      'private-peer.invalid',
      'secret-malformed',
      'secret-peer-key',
      'invalid:v1:'
    ]) {
      expect(persisted, isNot(contains(secret)));
    }
  });

  for (final brokenFirst in [false, true]) {
    test(
        'bad/good duplicate names never capture history (badFirst=$brokenFirst)',
        () {
      final raw = config('healthy.invalid');
      final broken = {'name': 'same', 'type': 'ss'};
      final proxies = raw['proxies'] as List;
      if (brokenFirst) {
        proxies.insert(0, broken);
      } else {
        proxies.add(broken);
      }
      expect(recorder.capture(profileId: 'a', raw: raw, name: 'same', url: url),
          isNull);
    });
  }

  test('redacted catalog capture shares filtering and deletion generations',
      () async {
    final raw = config('healthy.invalid');
    (raw['proxies'] as List).addAll([
      {'name': 'broken', 'type': 'ss'},
      {'name': 'ambiguous', 'type': 'ss'},
      {
        'name': 'ambiguous',
        'type': 'ss',
        'server': 'other.invalid',
        'port': 443
      },
    ]);
    final catalog =
        buildProfileCatalog(profileId: 'a', fingerprint: 'verified', raw: raw);
    final target =
        recorder.captureCatalog(catalog: catalog, name: 'same', url: url);
    expect(target, isNotNull);
    expect(target!.profileId, 'a');
    expect(recorder.captureCatalog(catalog: catalog, name: 'broken', url: url),
        isNull);
    expect(
        recorder.captureCatalog(catalog: catalog, name: 'ambiguous', url: url),
        isNull);
    expect(
        recorder.captureCatalog(
            catalog: catalog.copyWith(status: ProfileCatalogStatus.parseFailed),
            name: 'same',
            url: url),
        isNull);
    await recorder.record(target, 71);
    expect(store.read('a', target.identityKey, testUrl: url)?.delayMs, 71);
    await recorder.removeProfile('a');
    await recorder.record(target, 72);
    expect(store.readProfile('a', testUrl: url), isEmpty);
  });

  test('async runtime verification preserves the captured measurement time',
      () async {
    final arrivedAt = now;
    final target = recorder.capture(
        profileId: 'a',
        raw: config('healthy.invalid'),
        name: 'same',
        url: url)!;
    now = now.add(const Duration(minutes: 2));
    await recorder.record(target, 81, testedAt: arrivedAt);
    expect(
        store.read('a', target.identityKey, testUrl: url)!.testedAt, arrivedAt);
  });
}
