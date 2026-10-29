import 'dart:async';
import 'dart:convert';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = Profile(id: 'a', autoUpdateDuration: Duration.zero);
  late NodeCatalogService service;
  late List<String> released;
  late List<String> sent;
  late Map<String, dynamic> raw;
  late CatalogFileMetadata? metadata;
  late String script;
  Future<String> Function(
          String, List<Map<String, dynamic>>, List<Map<String, dynamic>>)?
      prepareOverride;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? evaluateOverride;

  String response(String id, List<Map<String, dynamic>> proxies) => jsonEncode({
        'catalog-id': id,
        'nodes': [
          for (final (index, proxy) in proxies.indexed)
            {
              'index': index,
              'name': proxy['name'],
              'supported': true,
              'reason': ''
            },
        ],
      });

  setUp(() {
    released = [];
    sent = [];
    metadata = (modifiedMicros: 1, size: 100);
    script = 'script-1';
    prepareOverride = null;
    evaluateOverride = null;
    raw = {
      'proxies': [
        {'name': 'DIRECT', 'type': 'direct'},
        {
          'name': 'Same',
          'type': 'ss',
          'server': 'private.invalid',
          'port': 443,
          'password': 'credential'
        },
        {
          'name': 'Same',
          'type': 'ss',
          'server': 'other.invalid',
          'port': 443,
          'password': 'credential-2'
        },
      ],
      'proxy-providers': {
        'cached': {'type': 'http', 'url': 'https://secret.invalid/token'},
      },
    };
    service = NodeCatalogService(
      readProfileConfig: (_) async => raw,
      evaluate: (value) => evaluateOverride?.call(value) ?? Future.value(value),
      fileMetadata: (_) async => metadata,
      scriptFingerprint: () => script,
      providerCachePath: (id, name, definition) async =>
          '/home/profiles/providers/$id/proxies/hash',
      prepareCatalog: (id, proxies, providers) async {
        sent.add(id);
        expect(proxies, hasLength(2));
        expect(proxies.first['password'], 'credential');
        expect(providers.single, {
          'name': 'cached',
          'path': '/home/profiles/providers/a/proxies/hash'
        });
        return prepareOverride?.call(id, proxies, providers) ??
            response(id, proxies);
      },
      releaseCatalog: (id) async {
        released.add(id);
        return true;
      },
    );
  });

  test('explicit preparation sends credentials only to Core and keeps indices',
      () async {
    await service.load(profile);
    expect(sent, isEmpty,
        reason: 'passive catalog loads cannot prepare adapters');
    final result = await service.ensurePrepared(profile);
    expect(result.coreCatalogId, matches(RegExp(r'^c-[A-Za-z0-9-]{8,64}$')));
    expect(result.nodes.map((node) => node.coreIndex), [0, 1]);
    expect(result.nodes.map((node) => node.identityKey).toSet(), hasLength(2));
    final output = '${jsonEncode(result.toJson())} $result';
    for (final secret in ['credential', 'private.invalid', 'secret.invalid']) {
      expect(output, isNot(contains(secret)));
    }
    await service.releasePrepared(result.coreCatalogId!);
    expect(released, [result.coreCatalogId]);
  });

  test('passive load preflights isolated protocols without preparing Core',
      () async {
    raw['proxies'] = [
      for (final (index, options) in <Map<String, dynamic>>[
        {'type': 'vless'},
        {'type': 'tuic'},
        {'type': 'ss', 'plugin': 'kcptun'},
        {'type': 'hysteria2', 'realm-opts': {}},
        {'type': 'ss', 'dialer_proxy': 'upstream'},
        {
          'type': 'ss',
          'SMUX': {'enabled': false}
        },
      ].indexed)
        {
          'name': 'Node $index',
          'server': 'fixture.invalid',
          'port': 443,
          ...options
        },
    ];
    final catalog = await service.load(profile);
    expect(sent, isEmpty);
    expect(catalog.nodes.map((node) => node.unsupported), [
      CatalogUnsupportedReason.none,
      CatalogUnsupportedReason.typeUnsupported,
      CatalogUnsupportedReason.typeUnsupported,
      CatalogUnsupportedReason.typeUnsupported,
      CatalogUnsupportedReason.chainUnsupported,
      CatalogUnsupportedReason.typeUnsupported,
    ]);
    expect(catalog.nodes.every((node) => node.coreIndex == null), isTrue);
  });

  test('fresh batches do not reuse Core catalogs after independent eviction',
      () async {
    final first = await service.ensurePrepared(profile);
    final second = await service.ensurePrepared(profile);
    expect(first.coreCatalogId, isNot(second.coreCatalogId));
    expect(released, [first.coreCatalogId]);
    expect(sent, hasLength(2));
  });

  test('same profile in-flight preparation is coalesced', () async {
    final wait = Completer<String>();
    late String id;
    prepareOverride = (catalogId, proxies, providers) {
      id = catalogId;
      return wait.future;
    };
    final first = service.ensurePrepared(profile);
    expect(service.ensurePrepared(profile), same(first));
    await Future<void>.delayed(Duration.zero);
    wait.complete(response(id, [{}, {}]));
    await first;
    expect(sent, hasLength(1));
  });

  test('invalidated in-flight response is released and never published',
      () async {
    final wait = Completer<String>();
    late String id;
    prepareOverride = (catalogId, proxies, providers) {
      id = catalogId;
      return wait.future;
    };
    final pending = service.ensurePrepared(profile);
    final checked = expectLater(
        pending,
        throwsA(isA<CatalogBuildException>()
            .having((e) => e.reason, 'reason', 'configChanged')));
    await Future<void>.delayed(Duration.zero);
    service.invalidate(profile.id);
    wait.complete(response(id, [{}, {}]));
    await checked;
    expect(released, [id]);
  });

  for (final change in ['file', 'script', 'delete']) {
    test('rejects $change changes during evaluation before sending to Core',
        () async {
      evaluateOverride = (value) async {
        switch (change) {
          case 'file':
            metadata = (modifiedMicros: 2, size: 101);
          case 'script':
            script = 'script-2';
          case 'delete':
            metadata = null;
        }
        return value;
      };
      await expectLater(
          service.ensurePrepared(profile),
          throwsA(isA<CatalogBuildException>()
              .having((e) => e.reason, 'reason', 'configChanged')));
      expect(sent, isEmpty);
    });
  }

  test('updating and missing profiles never invoke Core prepare', () async {
    await expectLater(
        service.ensurePrepared(profile.copyWith(isUpdating: true)),
        throwsA(isA<CatalogBuildException>()));
    metadata = null;
    await expectLater(
        service.ensurePrepared(profile), throwsA(isA<CatalogBuildException>()));
    expect(sent, isEmpty);
  });

  test('Core unsupported and malformed results cannot acquire test indices',
      () async {
    prepareOverride = (id, proxies, providers) async => jsonEncode({
          'catalog-id': id,
          'nodes': [
            {'index': 0, 'supported': false, 'reason': 'chainUnsupported'},
            {
              'index': 1,
              'supported': false,
              'reason': 'private error credential'
            },
          ],
        });
    final result = await service.ensurePrepared(profile);
    expect(result.nodes.map((node) => node.coreIndex), everyElement(isNull));
    expect(result.nodes.map((node) => node.unsupported), [
      CatalogUnsupportedReason.chainUnsupported,
      CatalogUnsupportedReason.parseFailed
    ]);
    expect(result.toString(), isNot(contains('credential')));
  });

  for (final bad in [
    'bad-json',
    'wrong-id',
    'duplicate-index',
    'missing-node'
  ]) {
    test('invalid $bad response is rejected and released', () async {
      prepareOverride = (id, proxies, providers) async => switch (bad) {
            'bad-json' => 'credential private.invalid',
            'wrong-id' => response('other', proxies),
            'duplicate-index' => jsonEncode({
                'catalog-id': id,
                'nodes': [
                  {'index': 0, 'supported': true},
                  {'index': 0, 'supported': true}
                ]
              }),
            _ => response(id, []),
          };
      await expectLater(service.ensurePrepared(profile),
          throwsA(isA<CatalogBuildException>()));
      expect(released, sent);
    });
  }

  test('Core failure reasons stay fixed and cleanup is attempted', () async {
    prepareOverride = (id, proxies, providers) async =>
        throw const CatalogBuildException('strictModeUnsupported');
    await expectLater(
        service.ensurePrepared(profile),
        throwsA(isA<CatalogBuildException>()
            .having((e) => e.reason, 'reason', 'strictModeUnsupported')));
    expect(released, sent);
  });

  test('clear releases prepared catalogs', () async {
    final prepared = await service.ensurePrepared(profile);
    service.clear();
    await Future<void>.delayed(Duration.zero);
    expect(released, [prepared.coreCatalogId]);
  });
}
