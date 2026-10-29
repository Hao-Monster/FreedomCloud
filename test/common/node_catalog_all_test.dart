import 'dart:async';
import 'dart:convert';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = Profile(id: 'fixture', autoUpdateDuration: Duration.zero);
  Map<String, dynamic> node(int i) => {
        'name': 'Node $i',
        'type': 'ss',
        'server': 'fixture.invalid',
        'port': 443,
        'password': 'PRIVATE'
      };
  final released = <String>[];

  test('profile payload budget preserves inline and earlier providers',
      () async {
    final resolver = CatalogProviderResolver(
        homeDirectory: () async => '',
        httpCachePath: (_, __) async => '',
        parse: (_, definition) async => jsonEncode({
              'proxies': [
                for (var i = 0; i < 200; i++)
                  {
                    ...node(1),
                    'name': '${definition['label']} $i',
                    'password': 'x' * (35 * 1024),
                  }
              ],
              'rejected': 0
            }));
    final svc = NodeCatalogService(
        readProfileConfig: (_) async => {
              'proxies': [node(0)],
              'proxy-providers': {
                for (var i = 0; i < 5; i++)
                  'p$i': {'type': 'inline', 'label': 'Provider $i'}
              },
            },
        evaluate: (raw) async => raw,
        fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
        scriptFingerprint: () => '',
        providerResolver: resolver);
    final plan = await svc.resolveForTestAll(profile, isCurrent: () => true);
    expect(plan.nodes, hasLength(801));
    expect(plan.nodes.first.name, 'Node 0');
    expect(plan.providerIssues.single.reason, 'providerTooLarge');
    expect(plan.providerIssues.single.providerName, 'p4');
    expect(plan.providerIssues.single.count, 200);
    plan.dispose();
  });
  NodeCatalogService service(List<Map<String, dynamic>> nodes) =>
      NodeCatalogService(
        readProfileConfig: (_) async => {'proxies': nodes},
        evaluate: (raw) async => raw,
        fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
        scriptFingerprint: () => '',
        prepareCatalog: (id, raw, providers) async => jsonEncode({
          'catalog-id': id,
          'nodes': [
            for (var i = 0; i < raw.length; i++) {'index': i, 'supported': true}
          ]
        }),
        releaseCatalog: (id) async {
          released.add(id);
          return true;
        },
      );

  test('all plan partitions over 2000 nodes and preserves every identity',
      () async {
    final svc = service(List.generate(2001, node));
    final plan = await svc.resolveForTestAll(profile, isCurrent: () => true);
    expect(plan.nodes, hasLength(2001));
    expect(plan.chunkCount, 2);
    final first = await plan.prepareChunk(0);
    expect(first.nodes, hasLength(2000));
    await svc.releasePrepared(first.coreCatalogId!);
    final last = await plan.prepareChunk(1);
    expect(last.nodes.single.identityKey, plan.nodes.last.identityKey);
    expect(last.nodes.single.coreIndex, 0);
    plan.dispose();
    expect(released, contains(last.coreCatalogId));
    await expectLater(
        plan.prepareChunk(0), throwsA(isA<CatalogBuildException>()));
  });

  test('all plan keeps unsupported slots explicit and revokes changed input',
      () async {
    var current = true;
    final svc = service([
      node(0),
      {...node(1), 'type': 'tuic'},
      {'name': 'Invalid'}
    ]);
    final plan = await svc.resolveForTestAll(profile, isCurrent: () => current);
    expect(plan.nodes[1].unsupported, CatalogUnsupportedReason.typeUnsupported);
    expect(plan.nodes[2].unsupported, CatalogUnsupportedReason.parseFailed);
    current = false;
    await expectLater(
        plan.prepareChunk(0), throwsA(isA<CatalogBuildException>()));
    plan.dispose();
  });

  test('prepare partitions actual escaped bytes and reports a huge node',
      () async {
    final payloads = <String>[];
    final svc = NodeCatalogService(
      readProfileConfig: (_) async => {
        'proxies': [
          for (var i = 0; i < 30; i++) {...node(i), 'password': '"' * 20000},
          {...node(31), 'password': 'x' * (600 * 1024)},
        ]
      },
      evaluate: (raw) async => raw,
      fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
      scriptFingerprint: () => '',
      prepareCatalog: (id, raw, providers) async {
        payloads.add(jsonEncode(jsonEncode(
            {'catalog-id': id, 'proxies': raw, 'providers': providers})));
        return jsonEncode({
          'catalog-id': id,
          'nodes': [
            for (var i = 0; i < raw.length; i++) {'index': i, 'supported': true}
          ]
        });
      },
      releaseCatalog: (_) async => true,
    );
    final plan = await svc.resolveForTestAll(profile, isCurrent: () => true);
    expect(plan.nodes, hasLength(30));
    expect(plan.providerIssues.single.reason, 'providerTooLarge');
    expect(plan.providerIssues.single.count, 1);
    expect(plan.chunkCount, greaterThan(1));
    var measured = 0;
    for (var i = 0; i < plan.chunkCount; i++) {
      final prepared = await plan.prepareChunk(i);
      measured += prepared.nodes.length;
      await svc.releasePrepared(prepared.coreCatalogId!);
    }
    expect(measured, 30);
    expect(payloads.every((p) => utf8.encode(p).length <= 512 * 1024), isTrue);
    plan.dispose();
  });

  test('disposed plan releases late prepare even when caller stays current',
      () async {
    final pending = Completer<String>();
    final started = Completer<String>();
    final releases = <String>[];
    final svc = NodeCatalogService(
      readProfileConfig: (_) async => {
        'proxies': [node(0)]
      },
      evaluate: (raw) async => raw,
      fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
      scriptFingerprint: () => '',
      prepareCatalog: (id, raw, providers) {
        started.complete(id);
        return pending.future;
      },
      releaseCatalog: (id) async {
        releases.add(id);
        return true;
      },
    );
    final plan = await svc.resolveForTestAll(profile, isCurrent: () => true);
    final prepared = plan.prepareChunk(0);
    final assertion = expectLater(
        prepared,
        throwsA(isA<CatalogBuildException>()
            .having((e) => e.reason, 'reason', 'cancelled')));
    final id = await started.future;
    plan.dispose();
    pending.complete(jsonEncode({
      'catalog-id': id,
      'nodes': [
        {'index': 0, 'supported': true}
      ]
    }));
    await assertion;
    expect(releases, [id]);
  });

  test('one failed provider retains inline and later provider identities',
      () async {
    final resolver = CatalogProviderResolver(
        homeDirectory: () async => '',
        httpCachePath: (_, __) async => '',
        parse: (_, definition) async {
          if (definition['label'] == 'bad')
            throw const CatalogBuildException('parseFailed');
          return jsonEncode({
            'proxies': [node(1)],
            'rejected': 1
          });
        });
    final svc = NodeCatalogService(
        readProfileConfig: (_) async => {
              'proxies': [node(0)],
              'proxy-providers': {
                'first': {'type': 'inline', 'label': 'bad'},
                'second': {'type': 'inline', 'label': 'good'}
              }
            },
        evaluate: (raw) async => raw,
        fileMetadata: (_) async => (modifiedMicros: 1, size: 2),
        scriptFingerprint: () => '',
        providerResolver: resolver);
    final plan = await svc.resolveForTestAll(profile, isCurrent: () => true);
    expect(plan.nodes, hasLength(2));
    expect(plan.nodes.last.source, CatalogNodeSource.provider);
    expect(plan.nodes.last.providerName, 'second');
    expect(plan.providerIssues.map((i) => i.providerName), ['first', 'second']);
    expect(plan.providerIssues.map((i) => i.count), [0, 1]);
    plan.dispose();
  });
}
