import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/node_health_recorder.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/common/node_runtime_catalog.dart';
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

  CatalogNode isolatedNode(Map<String, dynamic> value) => buildProfileCatalog(
        profileId: 'profile-a',
        fingerprint: 'fixture',
        raw: {
          'proxies': [value],
        },
        isolatedTest: true,
      ).nodes.single;

  test('isolated first projection admits exactly the Core protocol allowlist',
      () {
    for (final type in [
      'ss',
      'ssr',
      'socks5',
      'http',
      'vmess',
      'vless',
      'trojan',
      'hysteria2',
      'ssh',
    ]) {
      expect(isolatedNode(proxy()..['type'] = type).unsupported,
          CatalogUnsupportedReason.none,
          reason: type);
    }
    for (final type in [
      'tuic',
      'snell',
      'anytls',
      'hysteria',
      'wireguard',
      'amneziawg',
      'tailscale',
      'mieru',
      'future-protocol',
      'SS',
      'Vless',
      ' vless ',
    ]) {
      expect(isolatedNode(proxy()..['type'] = type).unsupported,
          CatalogUnsupportedReason.typeUnsupported,
          reason: type);
    }
  });

  test('isolated chains recognize decoder aliases and precede other exclusions',
      () {
    for (final key in [
      'dialer-proxy',
      'dialer_proxy',
      'Dialer-Proxy',
      'DIALER_PROXY'
    ]) {
      for (final value in <Object?>[null, '', 'private-upstream']) {
        final raw = proxy()
          ..['type'] = 'tuic'
          ..['SMUX'] = {'enabled': true}
          ..[key] = value;
        expect(isolatedNode(raw).unsupported,
            CatalogUnsupportedReason.chainUnsupported,
            reason: key);
      }
    }
  });

  test('isolated smux declarations are rejected even when empty or disabled',
      () {
    for (final key in ['smux', 'SMUX', 'SmUx']) {
      for (final value in <Object?>[
        null,
        false,
        <String, dynamic>{},
        {'enabled': false}
      ]) {
        expect(isolatedNode(proxy()..[key] = value).unsupported,
            CatalogUnsupportedReason.typeUnsupported,
            reason: key);
      }
    }
  });

  test('isolated Shadowsocks rejects only the retained kcptun plugin', () {
    for (final key in ['plugin', 'PLUGIN', 'Plugin']) {
      for (final plugin in ['kcptun', 'KCPTUN', 'KcpTun']) {
        expect(
            isolatedNode(proxy()
                  ..['type'] = 'ss'
                  ..[key] = plugin)
                .unsupported,
            CatalogUnsupportedReason.typeUnsupported);
      }
    }
    for (final plugin in [
      'obfs',
      'v2ray-plugin',
      'gost-plugin',
      'shadow-tls'
    ]) {
      expect(
          isolatedNode(proxy()
                ..['type'] = 'ss'
                ..['plugin'] = plugin)
              .unsupported,
          CatalogUnsupportedReason.none);
    }
    expect(isolatedNode(proxy()..['plugin'] = 'kcptun').unsupported,
        CatalogUnsupportedReason.none);
  });

  test('isolated Hysteria2 realm declarations recognize all decoder aliases',
      () {
    for (final key in [
      'realm-opts',
      'realm_opts',
      'Realm-Opts',
      'REALM_OPTS'
    ]) {
      for (final value in <Object?>[null, false, <String, dynamic>{}]) {
        expect(
            isolatedNode(proxy()
                  ..['type'] = 'hysteria2'
                  ..[key] = value)
                .unsupported,
            CatalogUnsupportedReason.typeUnsupported,
            reason: key);
      }
      expect(isolatedNode(proxy()..[key] = {}).unsupported,
          CatalogUnsupportedReason.none);
    }
  });

  test('isolated exclusions preserve identity and retain no transport secrets',
      () {
    final raw = proxy()
      ..['type'] = 'ss'
      ..['PLUGIN'] = 'KcPtUn'
      ..['plugin-opts'] = {'key': 'private-plugin-key'};
    final ordinary = node(raw);
    final isolated = isolatedNode(raw);
    expect(isolated.unsupported, CatalogUnsupportedReason.typeUnsupported);
    expect(ordinary.unsupported, CatalogUnsupportedReason.none);
    expect(isolated.identityKey, ordinary.identityKey);
    expect(isolated.endpointKey, ordinary.endpointKey);
    final output = '${isolated.toString()} ${jsonEncode(isolated.toJson())}';
    for (final secret in [
      'private-plugin-key',
      'Node.Example',
      'KcPtUn',
      'secret-password-value',
      'secret-uuid-value'
    ]) {
      expect(output, isNot(contains(secret)));
    }
  });

  test('isolated preflight leaves malformed identities as nonpersistent rows',
      () {
    final malformed = isolatedNode(proxy()
      ..['type'] = 'tuic'
      ..remove('server'));
    expect(malformed.unsupported, CatalogUnsupportedReason.parseFailed);
    expect(malformed.identityKey, startsWith('invalid:v1:'));
    expect(malformed.endpointKey, isEmpty);
  });

  test(
      'catalog restrictions do not change active runtime verification or history',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('fcx-live-protocol-');
    final store = NodeHealthStore(
        fileProvider: () async => File('${directory.path}/health.json'));
    final recorder = NodeHealthRecorder(store: store);
    addTearDown(() async {
      await recorder.flush();
      store.dispose();
      await directory.delete(recursive: true);
    });
    final raws = [
      for (final type in ['tuic', 'snell', 'anytls', 'hysteria'])
        proxy()..['type'] = type,
      proxy()..['SMUX'] = {'enabled': true},
      proxy()..['dialer_proxy'] = 'private-chain',
      proxy()
        ..['type'] = 'ss'
        ..['plugin'] = 'kcptun',
      proxy()
        ..['type'] = 'hysteria2'
        ..['realm_opts'] = {},
    ];
    const url = 'https://probe.invalid/204';
    for (final (index, rawNode) in raws.indexed) {
      final raw = <String, dynamic>{
        'proxies': [rawNode]
      };
      final isolated = buildProfileCatalog(
          profileId: 'profile-a',
          fingerprint: 'file',
          raw: raw,
          isolatedTest: true);
      expect(isolated.nodes.single.unsupported,
          isNot(CatalogUnsupportedReason.none));
      final runtime = await readVerifiedNodeRuntime(
          profileId: 'profile-a',
          readRuntime: () async => raw,
          readProfile: () async => isolated,
          isCurrent: () => true);
      expect(runtime, isNotNull);
      expect(runtime!.nodes.single.unsupported, CatalogUnsupportedReason.none);
      final rawTarget = recorder.capture(
          profileId: 'profile-a', raw: raw, name: 'Example', url: url);
      final verifiedTarget =
          recorder.captureCatalog(catalog: runtime, name: 'Example', url: url);
      expect(rawTarget, isNotNull);
      expect(verifiedTarget, isNotNull);
      expect(rawTarget!.identityKey, isolated.nodes.single.identityKey);
      expect(verifiedTarget!.identityKey, rawTarget.identityKey);
      await recorder.record(verifiedTarget, 40 + index);
      expect(
          store.read('profile-a', rawTarget.identityKey, testUrl: url)?.delayMs,
          40 + index);
    }
  });
}
