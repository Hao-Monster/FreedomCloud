import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/file_logger.dart';
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
  _State(this.read) : super.forTesting();
  final Future<Map<String, dynamic>> Function(String id) read;
  @override
  Future<Map<String, dynamic>> getProfileConfig(String profileId) =>
      read(profileId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = Profile(
      id: 'profile-a',
      autoUpdateDuration: Duration.zero,
      selectedMap: {'group-a': 'node-a'});
  const second = Profile(
      id: 'profile-b',
      autoUpdateDuration: Duration.zero,
      selectedMap: {'group-b': 'node-b'});
  const initial = Config(
      themeProps: defaultThemeProps,
      profiles: [first, second],
      currentProfileId: 'profile-a');
  late Directory root;
  final originalPaths = PathProviderPlatform.instance;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('flclashx-config-snapshot-');
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDownAll(() async {
    await fileLogger.dispose();
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  for (final switchBeforeConstruction in [false, true]) {
    test(
        'setup binds config and selectedMap to captured profile (switchBefore=$switchBeforeConstruction)',
        () async {
      final reply = Completer<Map<String, dynamic>>();
      final requested = <String>[];
      final state = _State((id) {
        requested.add(id);
        return reply.future;
      });
      globalState.config = initial;
      state.config = initial;
      void switchProfile() {
        globalState.config = initial.copyWith(currentProfileId: second.id);
        state.config = globalState.config;
      }

      if (switchBeforeConstruction) switchProfile();
      final pending =
          state.getSetupParams(pathConfig: const ClashConfig(), profile: first);
      if (!switchBeforeConstruction) switchProfile();
      reply.complete({'profile-marker': first.id, 'rules': <String>[]});
      final result = await pending;
      expect(requested, [first.id]);
      expect(result.config['profile-marker'], first.id);
      expect(result.selectedMap, first.selectedMap);
      expect(globalState.config.currentProfileId, second.id);
      expect(state.lastRuntimeConfig, isNull,
          reason: 'constructing a candidate must not commit applied state');
    });
  }
}
