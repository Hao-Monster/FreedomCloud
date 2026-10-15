import 'dart:async';
import 'dart:convert';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile(String id, {bool updating = false}) => Profile(
      id: id,
      autoUpdateDuration: Duration.zero,
      isUpdating: updating,
    );

Map<String, dynamic> _config([String name = 'Node']) => {
      'proxies': [
        {'name': name, 'type': 'ss', 'server': 'private.example', 'port': 443},
        {'name': 'DIRECT', 'type': 'direct'},
        {'name': 'REJECT', 'type': 'reject'},
        {'name': 'DROP', 'type': 'reject-drop'},
        {'name': 'PASS', 'type': 'pass'},
        {'name': 'DNS', 'type': 'dns'},
        {'name': 'COMPATIBLE', 'type': 'compatible'},
      ],
      'proxy-groups': [
        {
          'name': 'First',
          'type': 'select',
          'proxies': [name]
        },
        {
          'name': 'Auto',
          'type': 'url-test',
          'proxies': [name]
        },
        {
          'name': 'Second',
          'type': 'select',
          'proxies': [name]
        },
      ],
      'proxy-providers': {
        'Provider': {'type': 'http', 'url': 'https://private.example/token'},
      },
    };

void main() {
  late int reads;
  late int evaluations;
  late ({int modifiedMicros, int size})? metadata;
  late String script;
  late NodeCatalogService service;

  setUp(() {
    reads = 0;
    evaluations = 0;
    metadata = (modifiedMicros: 100, size: 200);
    script = 'script-id|safe-hash';
    service = NodeCatalogService(
      readProfileConfig: (id) async {
        reads++;
        return _config();
      },
      evaluate: (raw) async {
        evaluations++;
        return raw;
      },
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
  });

  test(
      'uses read then evaluate, keeps leaves, select order and unknown providers',
      () async {
    final catalog = await service.load(_profile('a'));
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes.map((node) => node.name), ['Node']);
    expect(catalog.nodes.single.selectGroups, ['First', 'Second']);
    expect(catalog.providerNodeCounts, {'Provider': -1});
    expect(catalog.fingerprint, '100|200|script-id|safe-hash');
    expect(reads, 1);
    expect(evaluations, 1);
  });

  test('script output determines the catalog nodes', () async {
    service = NodeCatalogService(
      readProfileConfig: (id) async => _config('Before'),
      evaluate: (raw) async {
        expect((raw['proxies'] as List).first['name'], 'Before');
        return _config('After');
      },
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    expect((await service.load(_profile('a'))).nodes.single.name, 'After');
  });

  test('script bridge maps with dynamic keys keep the same safe projection',
      () {
    final raw = _config();
    raw['proxies'] = [
      <dynamic, dynamic>{
        'name': 'Script',
        'type': 'ss',
        'server': 'private.example',
        'port': '443',
        'password': 'secret',
      },
    ];
    final catalog = buildProfileCatalog(
      profileId: 'a',
      fingerprint: 'f',
      raw: raw,
    );
    expect(catalog.nodes.single.name, 'Script');
    expect(catalog.toString(), isNot(contains('private.example')));
    expect(catalog.toString(), isNot(contains('secret')));
  });

  test(
      'file missing does not parse; updating reuses old catalog without parsing',
      () async {
    metadata = null;
    expect((await service.load(_profile('a'))).status,
        ProfileCatalogStatus.fileMissing);
    expect(reads, 0);
    metadata = (modifiedMicros: 100, size: 200);
    expect((await service.load(_profile('a', updating: true))).status,
        ProfileCatalogStatus.updating);
    expect(reads, 0);
    final cached = await service.load(_profile('a'));
    final updating = await service.load(_profile('a', updating: true));
    expect(updating.status, ProfileCatalogStatus.updating);
    expect(updating.nodes, cached.nodes);
    expect(reads, 1);
  });

  test('metadata, script and explicit invalidation rebuild the catalog',
      () async {
    final first = await service.load(_profile('a'));
    expect(await service.load(_profile('a')), same(first));
    expect(reads, 1);
    metadata = (modifiedMicros: 101, size: 200);
    await service.load(_profile('a'));
    metadata = (modifiedMicros: 101, size: 201);
    await service.load(_profile('a'));
    script = 'other-script|other-hash';
    await service.load(_profile('a'));
    service.invalidate('a');
    expect(service.peek('a'), isNull);
    await service.load(_profile('a'));
    expect(reads, 5);
    service.clear();
    expect(service.peek('a'), isNull);
  });

  test(
      'updating retains an invalidated snapshot but never makes it a ready hit',
      () async {
    final first = await service.load(_profile('a'));
    service.invalidate('a', keepCached: true);
    expect(service.peek('a'), same(first));
    final updating = await service.load(_profile('a', updating: true));
    expect(updating.status, ProfileCatalogStatus.updating);
    expect(updating.nodes, first.nodes);
    expect(reads, 1);
    final refreshed = await service.load(_profile('a'));
    expect(refreshed.status, ProfileCatalogStatus.ready);
    expect(reads, 2);
    expect(await service.load(_profile('a')), same(refreshed));
    expect(reads, 2);
  });

  test('LRU keeps at most eight catalogs and hits refresh recency', () async {
    for (var i = 0; i < 8; i++) {
      await service.load(_profile('$i'));
    }
    await service.load(_profile('0'));
    await service.load(_profile('8'));
    expect(service.peek('0'), isNotNull);
    expect(service.peek('1'), isNull);
    expect(service.peek('8'), isNotNull);
    expect(reads, 9);
  });

  test('same-profile loads share a future and all builds are limited to two',
      () async {
    final pendingReads = <String, Completer<Map<String, dynamic>>>{};
    var active = 0;
    var maximum = 0;
    service = NodeCatalogService(
      readProfileConfig: (id) async {
        active++;
        if (active > maximum) maximum = active;
        final pending = Completer<Map<String, dynamic>>();
        pendingReads[id] = pending;
        final raw = await pending.future;
        active--;
        return raw;
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final first = service.load(_profile('a'));
    expect(service.load(_profile('a')), same(first));
    final second = service.load(_profile('b'));
    final third = service.load(_profile('c'));
    await Future<void>.delayed(Duration.zero);
    expect(pendingReads.keys, ['a', 'b']);
    pendingReads['a']!.complete(_config());
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(pendingReads.keys, ['a', 'b', 'c']);
    pendingReads['b']!.complete(_config());
    pendingReads['c']!.complete(_config());
    await Future.wait([second, third]);
    expect(maximum, 2);
  });

  test('invalidating an in-flight build prevents it from overwriting a new one',
      () async {
    final oldRead = Completer<Map<String, dynamic>>();
    service = NodeCatalogService(
      readProfileConfig: (id) {
        reads++;
        return reads == 1 ? oldRead.future : Future.value(_config('New'));
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final first = service.load(_profile('a'));
    await Future<void>.delayed(Duration.zero);
    service.invalidate('a');
    final current = await service.load(_profile('a'));
    expect(current.nodes.single.name, 'New');
    oldRead.complete(_config('Old'));
    await first;
    expect(service.peek('a')!.nodes.single.name, 'New');
  });

  test(
      'errors never expose parser secrets; malformed lists are not empty success',
      () async {
    for (final raw in [
      null,
      {'proxies': 'not-a-list'},
      {'proxy-groups': 'not-a-list'},
      {
        'proxy-providers': ['not-a-map']
      },
    ]) {
      service = NodeCatalogService(
        readProfileConfig: (id) async {
          if (raw == null) {
            throw StateError(
                'password secret-value private.example https://x/token');
          }
          return raw;
        },
        evaluate: (raw) async => raw,
        fileMetadata: (id) async => metadata,
        scriptFingerprint: () => script,
      );
      final catalog = await service.load(_profile('a'));
      expect(catalog.status, ProfileCatalogStatus.parseFailed);
      expect(catalog.errorSummary, 'parseFailed');
      expect(catalog.toString(), isNot(contains('secret-value')));
      expect(catalog.toString(), isNot(contains('private.example')));
    }
  });

  test('one malformed leaf preserves healthy leaves with a safe placeholder',
      () async {
    final raw = _config();
    (raw['proxies'] as List).insert(1, {
      'name': 'Broken',
      'type': 'ss',
      'server': 'private-broken.example',
      'password': 'secret-broken-password',
    });
    service = NodeCatalogService(
      readProfileConfig: (id) async => raw,
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final catalog = await service.load(_profile('a'));
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes.map((node) => node.name), ['Node', 'Broken']);
    expect(catalog.nodes.first.unsupported, CatalogUnsupportedReason.none);
    expect(catalog.nodes.first.selectGroups, ['First', 'Second']);
    final broken = catalog.nodes.last;
    expect(broken.unsupported, CatalogUnsupportedReason.parseFailed);
    expect(broken.identityKey, startsWith('invalid:v1:'));
    expect(broken.identityKey, isNot(matches(RegExp(r'^[a-f0-9]{32}$'))));
    expect(broken.endpointKey, isEmpty);
    expect(broken.selectGroups, isEmpty);
    final output = '${catalog.toString()} ${jsonEncode(catalog.toJson())}';
    expect(output, isNot(contains('private-broken.example')));
    expect(output, isNot(contains('secret-broken-password')));
  });

  test('peers-only WireGuard and malformed items stay visible without secrets',
      () {
    final raw = <String, dynamic>{
      'proxies': [
        {'name': 'Healthy', 'type': 'ss', 'server': 'ok.invalid', 'port': 443},
        {
          'name': 'Peers-only',
          'type': 'wireguard',
          'private-key': 'secret-private-key',
          'peers': [
            {
              'server': 'private-peer.invalid',
              'port': 51820,
              'public-key': 'secret-peer-key'
            }
          ],
        },
        'secret-malformed-value',
        {
          'name': 42,
          'type': ['secret-type-value'],
          'uuid': 'secret-uuid'
        },
        {'name': 'No endpoint', 'type': 'ss'},
      ],
    };
    ProfileCatalog parse() =>
        buildProfileCatalog(profileId: 'a', fingerprint: 'f', raw: raw);
    final catalog = parse();
    expect(catalog.status, ProfileCatalogStatus.ready);
    expect(catalog.nodes.map((node) => node.name),
        ['Healthy', 'Peers-only', '#3', '#4', 'No endpoint']);
    expect(catalog.nodes.skip(1).map((node) => node.unsupported),
        everyElement(CatalogUnsupportedReason.parseFailed));
    expect(catalog.nodes.skip(1).map((node) => node.endpointKey),
        everyElement(isEmpty));
    expect(catalog.nodes.map((node) => node.identityKey).toSet(), hasLength(5));
    expect(parse().nodes, catalog.nodes);
    final output = '${catalog.toString()} ${jsonEncode(catalog.toJson())}';
    for (final secret in [
      'secret-private-key',
      'private-peer.invalid',
      'secret-peer-key',
      'secret-malformed-value',
      'secret-type-value',
      'secret-uuid',
      'ok.invalid',
    ]) {
      expect(output, isNot(contains(secret)));
    }
    expect(catalog.nodes[2].type, 'unknown');
    expect(catalog.nodes[3].type, 'unknown');
  });

  test('malformed placeholders count toward the same 2000-node limit', () {
    final raw = <String, dynamic>{'proxies': List.filled(2000, null)};
    final catalog =
        buildProfileCatalog(profileId: 'a', fingerprint: 'f', raw: raw);
    expect(catalog.nodes, hasLength(2000));
    expect(
        catalog.nodes.map((node) => node.identityKey).toSet(), hasLength(2000));
    raw['proxies'] = List.filled(2001, null);
    expect(
        () => buildProfileCatalog(profileId: 'a', fingerprint: 'f', raw: raw),
        throwsA(isA<CatalogBuildException>()
            .having((error) => error.reason, 'reason', 'tooManyNodes')));
  });

  test('more than 2000 leaves is an explicit failure rather than truncation',
      () async {
    service = NodeCatalogService(
      readProfileConfig: (id) async => {
        'proxies': List.generate(
          2001,
          (i) => {'name': 'N$i', 'type': 'ss', 'server': 'x', 'port': 443},
        ),
      },
      evaluate: (raw) async => raw,
      fileMetadata: (id) async => metadata,
      scriptFingerprint: () => script,
    );
    final catalog = await service.load(_profile('a'));
    expect(catalog.status, ProfileCatalogStatus.parseFailed);
    expect(catalog.errorSummary, 'tooManyNodes');
    expect(catalog.nodes, isEmpty);
  });
}
