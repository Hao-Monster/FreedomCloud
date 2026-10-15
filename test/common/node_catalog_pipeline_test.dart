import 'dart:io';

import 'package:flclashx/common/file_logger.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _State extends GlobalState {
  _State({required this.transform}) : super.forTesting();
  final bool transform;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> getProfileConfig(String profileId) async {
    calls.add('read:$profileId');
    return {
      'proxies': [
        {'name': 'Original', 'type': 'ss', 'server': 'x.example', 'port': 443},
        {'name': 'DIRECT', 'type': 'direct'},
      ],
      'proxy-groups': [
        {
          'name': 'Select',
          'type': 'select',
          'proxies': ['Original']
        },
      ],
      'rules': <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> handleEvaluate(Map<String, dynamic> raw) async {
    calls.add('evaluate');
    if (!transform) return raw;
    raw['proxies'] = [
      {'name': 'Script', 'type': 'vless', 'server': 'y.example', 'port': 8443},
      {'name': 'REJECT', 'type': 'reject'},
    ];
    raw['proxy-groups'] = [
      {
        'name': 'Select',
        'type': 'select',
        'proxies': ['Script']
      },
    ];
    return raw;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profile = Profile(id: 'a', autoUpdateDuration: Duration.zero);
  const initial = Config(
    themeProps: defaultThemeProps,
    profiles: [profile],
    currentProfileId: 'a',
  );
  late Directory root;
  final originalPaths = PathProviderPlatform.instance;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('flclashx-catalog-pipeline-');
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDownAll(() async {
    await fileLogger.dispose();
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  for (final transform in [false, true]) {
    test('catalog matches patched runtime leaves (script transform=$transform)',
        () async {
      final state = _State(transform: transform)..config = initial;
      globalState.config = initial;
      final service = NodeCatalogService(
        readProfileConfig: state.getProfileConfig,
        evaluate: state.handleEvaluate,
        fileMetadata: (id) async => (modifiedMicros: 1, size: 1),
        scriptFingerprint: () => '$transform',
      );
      final catalog = await service.load(profile);
      expect(state.calls, ['read:a', 'evaluate']);
      final patched = await state.patchRawConfig(
        patchConfig: const ClashConfig(),
        profile: profile,
      );
      final runtimeCatalog = buildProfileCatalog(
        profileId: profile.id,
        fingerprint: catalog.fingerprint,
        raw: patched,
      );
      expect(catalog.nodes, runtimeCatalog.nodes);
      expect(catalog.nodes.map((node) => node.name),
          [if (transform) 'Script' else 'Original']);
      expect(state.calls, ['read:a', 'evaluate', 'read:a', 'evaluate']);
      expect(state.lastRuntimeConfig, isNull,
          reason: 'constructing summaries must not apply a runtime config');
    });
  }
}
