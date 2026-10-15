import 'dart:convert';

import 'package:flclashx/models/node_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> proxy(
          {String server = 'Node.Example', int port = 443}) =>
      {
        'name': 'Example',
        'type': 'vless',
        'server': server,
        'port': port,
        'password': 'secret-password-value',
        'uuid': 'secret-uuid-value',
        'private-key': 'secret-private-key-value',
        'reality-opts': {'public-key': 'secret-reality-value'},
        'sni': 'secret-sni-value',
      };

  CatalogNode node(Map<String, dynamic> value,
          {String profileId = 'profile-a'}) =>
      catalogNodeFromMap(profileId: profileId, proxy: value);

  test('v1 key vectors are fixed and do not depend on credentials or map order',
      () {
    final first = node(proxy());
    expect(first.identityKey, '101dd21aa8d877248038524558f71bb7');
    expect(first.endpointKey, '99a75a3de2ee8080bfb7453d6ac37db5');
    final reordered = Map<String, dynamic>.fromEntries(
      proxy().entries.toList().reversed,
    )..['password'] = 'other-password';
    expect(node(reordered).identityKey, first.identityKey);
    expect(node(proxy(server: 'NODE.EXAMPLE')).identityKey, first.identityKey);
    expect(node(proxy(server: 'other.example')).identityKey,
        isNot(first.identityKey));
    expect(node(proxy(port: 8443)).identityKey, isNot(first.identityKey));
    expect(node(proxy(), profileId: 'profile-b').identityKey,
        isNot(first.identityKey));
    expect(
        node(proxy(), profileId: 'profile-b').endpointKey, first.endpointKey);
  });

  test('catalog serialization and debug output only contain whitelisted fields',
      () {
    final catalog = ProfileCatalog(
      profileId: 'profile-a',
      fingerprint: 'safe-fingerprint',
      status: ProfileCatalogStatus.ready,
      nodes: [node(proxy())],
    );
    final output = '${catalog.toString()} ${jsonEncode(catalog.toJson())}';
    for (final secret in [
      'Node.Example',
      'secret-password-value',
      'secret-uuid-value',
      'secret-private-key-value',
      'secret-reality-value',
      'secret-sni-value',
    ]) {
      expect(output, isNot(contains(secret)));
    }
    expect(catalog.nodes.single.name, 'Example');
    expect(catalog.nodes.single.type, 'vless');
    expect(ProfileCatalog.fromJson(catalog.toJson()), catalog);
  });

  test('source participates in identity and unsupported chains remain visible',
      () {
    final inline = node(proxy());
    final provider = catalogNodeFromMap(
      profileId: 'profile-a',
      proxy: proxy()..['dialer-proxy'] = 'upstream',
      source: CatalogNodeSource.provider,
      providerName: 'provider-a',
      selectGroups: const ['Select'],
    );
    expect(provider.identityKey, isNot(inline.identityKey));
    expect(provider.endpointKey, inline.endpointKey);
    expect(provider.unsupported, CatalogUnsupportedReason.chainUnsupported);
    expect(provider.selectGroups, ['Select']);
    expect(
      node(proxy()..['type'] = 'wireguard').unsupported,
      CatalogUnsupportedReason.typeUnsupported,
    );
  });

  test('invalid leaf identity fails without echoing source values', () {
    expect(() => node(proxy()..['server'] = null), throwsFormatException);
    expect(() => node(proxy()..['port'] = 0), throwsFormatException);
    expect(() => node(proxy()..['name'] = 42), throwsFormatException);
  });

  test('unparsed display keys are stable, unique and never endpoint identities',
      () {
    final placeholder = unparsedCatalogNode(profileId: 'a', sourceIndex: 1);
    expect(placeholder.name, '#2');
    expect(placeholder.type, 'unknown');
    expect(placeholder.unsupported, CatalogUnsupportedReason.parseFailed);
    expect(placeholder.identityKey, startsWith('invalid:v1:'));
    expect(placeholder.endpointKey, isEmpty);
    expect(unparsedCatalogNode(profileId: 'a', sourceIndex: 1), placeholder);
    expect(unparsedCatalogNode(profileId: 'a', sourceIndex: 2).identityKey,
        isNot(placeholder.identityKey));
    expect(unparsedCatalogNode(profileId: 'b', sourceIndex: 1).identityKey,
        isNot(placeholder.identityKey));
    expect(CatalogNode.fromJson(placeholder.toJson()), placeholder);
  });
}
