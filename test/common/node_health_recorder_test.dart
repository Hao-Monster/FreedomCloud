import 'dart:io';

import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late NodeHealthStore store;
  late NodeHealthRecorder recorder;
  var now = DateTime.utc(2026, 10, 15);
  const url = 'https://probe.invalid/204';
  Map<String, dynamic> config(String server) => {
        'proxies': [
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
    await recorder.record(old, -1, reason: 'configChanged');
    expect(store.read('a', old.identityKey, testUrl: url)?.reason,
        'configChanged');
    expect(store.read('b', current.identityKey, testUrl: url), isNull);
    await recorder.record(current, 55);
    expect(store.read('a', old.identityKey, testUrl: url)?.delayMs, -1);
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
}
