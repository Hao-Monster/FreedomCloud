import 'dart:async';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_runtime_catalog.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> node(String name, String server) => {
        'name': name,
        'type': 'ss',
        'server': server,
        'port': 443,
        'password': 'private-fixture',
      };
  late Map<String, dynamic> source;
  setUp(() => source = {
        'proxies': [node('One', 'a.invalid'), node('Two', 'b.invalid')]
      });

  Future<ProfileCatalog?> verify(Map<String, dynamic> runtime,
          {bool Function()? current}) =>
      readVerifiedNodeRuntime(
          profileId: 'profile-a',
          readRuntime: () async => runtime,
          readProfile: () async => buildProfileCatalog(
              profileId: 'profile-a', fingerprint: 'file', raw: source),
          isCurrent: current ?? () => true);

  test(
      'reattachment verifies identical names and endpoints without a UI setup snapshot',
      () async {
    final runtime = {
      'proxies': [node('Two', 'b.invalid'), node('One', 'a.invalid')]
    };
    final catalog = await verify(runtime);
    expect(catalog, isNotNull);
    expect(catalog!.nodes.map((node) => node.name), ['Two', 'One']);
    expect(catalog.toString(), isNot(contains('private-fixture')));
    expect(catalog.toString(), isNot(contains('a.invalid')));
  });

  test('same endpoint set with swapped names cannot attest request identity',
      () async {
    expect(
        await verify({
          'proxies': [node('Two', 'a.invalid'), node('One', 'b.invalid')]
        }),
        isNull);
  });

  test('runtime verification includes nodes beyond one Core catalog chunk',
      () async {
    source = {
      'proxies': List.generate(
          2001, (index) => node('Node $index', 'n$index.invalid')),
    };
    final catalog = await verify(source);
    expect(catalog, isNotNull);
    expect(catalog!.nodes, hasLength(2001));
    final expected = catalogNodeFromMap(
        profileId: 'profile-a', proxy: node('Node 2000', 'n2000.invalid'));
    expect(catalog.nodes.last.identityKey, expected.identityKey);
    final changed = {
      'proxies': [
        ...(source['proxies'] as List).take(2000),
        node('Node 2000', 'changed.invalid'),
      ],
    };
    expect(await verify(changed), isNull);
  });

  test('expanded provider cache cannot revoke verified inline runtime nodes',
      () async {
    final file = buildProfileCatalog(
        profileId: 'profile-a', fingerprint: 'file', raw: source);
    final expanded = file.copyWith(nodes: [
      ...file.nodes,
      catalogNodeFromMap(
          profileId: 'profile-a',
          proxy: node('Provider node', 'provider.invalid'),
          source: CatalogNodeSource.provider,
          providerName: 'Subscription'),
    ]);
    final result = await readVerifiedNodeRuntime(
        profileId: 'profile-a',
        readRuntime: () async => source,
        readProfile: () async => expanded,
        isCurrent: () => true);
    expect(result?.nodes.map((node) => node.name), ['One', 'Two']);
    expect(result!.nodes.every((node) => node.source == CatalogNodeSource.inline),
        isTrue, reason: 'cached provider endpoints are not runtime proof');
    expect(
        await readVerifiedNodeRuntime(
            profileId: 'profile-a',
            readRuntime: () async => {
              'proxies': [node('One', 'changed.invalid'), node('Two', 'b.invalid')],
            },
            readProfile: () async => expanded,
            isCurrent: () => true),
        isNull);
  });

  test('missing extra and changed endpoints are rejected', () async {
    for (final nodes in [
      [node('One', 'a.invalid')],
      [
        node('One', 'a.invalid'),
        node('Two', 'b.invalid'),
        node('Extra', 'c.invalid')
      ],
      [node('One', 'a.invalid'), node('Two', 'changed.invalid')],
    ]) {
      expect(await verify({'proxies': nodes}), isNull);
    }
  });

  test('duplicates cannot pass set-only comparison', () async {
    expect(
        await verify({
          'proxies': [
            node('One', 'a.invalid'),
            node('One', 'a.invalid'),
            node('Two', 'b.invalid')
          ]
        }),
        isNull);
  });

  test(
      'unidentifiable nodes remain visible but do not block identifiable siblings',
      () async {
    source = {
      'proxies': [
        node('One', 'a.invalid'),
        {'name': 'WG', 'type': 'wireguard', 'peers': []}
      ]
    };
    final catalog = await verify(source);
    expect(catalog!.nodes, hasLength(2));
    expect(
        catalog.nodes.last.unsupported, CatalogUnsupportedReason.parseFailed);
  });

  test('empty or wholly unknown catalogs do not establish ownership', () async {
    source = {'proxies': []};
    expect(await verify(source), isNull);
  });

  test('selection change while either read is pending discards the old result',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    var current = true;
    final result = readVerifiedNodeRuntime(
        profileId: 'profile-a',
        readRuntime: () => pending.future,
        readProfile: () async => buildProfileCatalog(
            profileId: 'profile-a', fingerprint: '', raw: source),
        isCurrent: () => current);
    current = false;
    pending.complete(source);
    expect(await result, isNull);
  });

  test('read failure and timeout fail closed with no raw error propagation',
      () async {
    final catalog = buildProfileCatalog(
        profileId: 'profile-a', fingerprint: '', raw: source);
    final error = await readVerifiedNodeRuntime(
        profileId: 'profile-a',
        readRuntime: () async => throw StateError('private-fixture'),
        readProfile: () async => catalog,
        isCurrent: () => true);
    expect(error, isNull);
    final stalled = Completer<Map<String, dynamic>>();
    final timeout = await readVerifiedNodeRuntime(
        profileId: 'profile-a',
        readRuntime: () => stalled.future,
        readProfile: () async => catalog,
        isCurrent: () => true,
        timeout: const Duration(milliseconds: 5));
    expect(timeout, isNull);
    stalled.complete(source);
  });

  test('missing or updating source cannot attest running nodes', () async {
    for (final status in [
      ProfileCatalogStatus.fileMissing,
      ProfileCatalogStatus.updating
    ]) {
      expect(
          await readVerifiedNodeRuntime(
              profileId: 'profile-a',
              readRuntime: () async => source,
              readProfile: () async => ProfileCatalog(
                  profileId: 'profile-a', fingerprint: '', status: status),
              isCurrent: () => true),
          isNull);
    }
  });
}
