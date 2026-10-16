import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/common/path.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String> getApplicationSupportPath() async => root;
  @override
  Future<String> getTemporaryPath() async => root;
  @override
  Future<String> getDownloadsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalPaths = PathProviderPlatform.instance;
  late Directory root;
  late ProviderContainer container;
  late NodeCatalogService production;
  const profile = Profile(id: 'a', autoUpdateDuration: Duration.zero);
  final unmanaged = <String, Map<String, dynamic>>{
    'file': {'type': 'file', 'path': './providers/local.yaml'},
    'custom': {'type': 'custom', 'path': '/outside/private.yaml'},
    'missing-url': {'type': 'http', 'path': './providers/local.yaml'},
    'empty-url': {'type': 'http', 'url': ''},
    'blank-url': {'type': 'http', 'url': '   '},
    'relative-url': {'type': 'http', 'url': 'providers/cache.yaml'},
    'file-url': {'type': 'http', 'url': 'file:///private/cache.yaml'},
    'hostless-url': {'type': 'http', 'url': 'https:///cache.yaml'},
    'invalid-url': {'type': 'http', 'url': 'https://[bad'},
  };

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('fcx-catalog-provider-paths-');
    PathProviderPlatform.instance = _Paths(root.path);
    container = ProviderContainer();
    production = container.read(nodeCatalogServiceFactoryProvider)();
  });
  tearDownAll(() async {
    production.clear();
    container.dispose();
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  for (final entry in unmanaged.entries) {
    test('production mapping omits ${entry.key} provider', () async {
      expect(
          await production.providerCachePath!(
              profile.id, entry.key, entry.value),
          isNull);
    });
  }

  for (final scheme in ['http', 'https']) {
    test('production maps $scheme URL to managed hash, ignoring custom path',
        () async {
      final url = '$scheme://fixture.invalid/subscription?token=fixture';
      final result = await production.providerCachePath!(profile.id, 'remote', {
        'type': 'http',
        'url': url,
        'path': '../custom/cache.yaml',
      });
      expect(result,
          await appPath.getProvidersFilePath(profile.id, 'proxies', url));
      expect(
          p.isWithin(p.join(root.path, 'profiles', 'providers', 'a', 'proxies'),
              result!),
          isTrue);
      expect(result, isNot(contains('fixture')));
      expect(await root.list(recursive: true).toList(), isEmpty,
          reason: 'Mapping does not read/download/create provider caches');
    });
  }

  for (final includeManaged in [false, true]) {
    test('mixed providers retain inline prepare (managed=$includeManaged)',
        () async {
      final service = NodeCatalogService(
        readProfileConfig: (_) async => {
          'proxies': [
            {
              'name': 'Inline',
              'type': 'ss',
              'server': 'fixture.invalid',
              'port': 443
            }
          ],
          'proxy-providers': {
            ...unmanaged,
            if (includeManaged)
              'managed': {
                'type': 'http',
                'url': 'https://fixture.invalid/cache',
                'path': '../outside.yaml'
              },
          },
        },
        evaluate: (raw) async => raw,
        fileMetadata: (_) async => (modifiedMicros: 1, size: 100),
        scriptFingerprint: () => '',
        providerCachePath: production.providerCachePath,
        prepareCatalog: (id, proxies, providers) async {
          expect(proxies.single['name'], 'Inline');
          expect(providers.map((entry) => entry['name']),
              includeManaged ? ['managed'] : isEmpty);
          for (final entry in providers) {
            expect(
                p.isWithin(
                    p.join(root.path, 'profiles', 'providers', 'a', 'proxies'),
                    entry['path'] as String),
                isTrue);
          }
          return jsonEncode({
            'catalog-id': id,
            'nodes': [
              {'index': 0, 'name': 'Inline', 'supported': true, 'reason': ''}
            ]
          });
        },
        releaseCatalog: (_) async => true,
      );
      addTearDown(service.clear);
      final prepared = await service.ensurePrepared(profile);
      expect(prepared.status, ProfileCatalogStatus.ready);
      expect(prepared.nodes.single.coreIndex, 0);
      expect(prepared.nodes.single.unsupported, CatalogUnsupportedReason.none);
    });
  }
}
