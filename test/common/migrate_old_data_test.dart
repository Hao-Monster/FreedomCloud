import 'dart:async';
import 'dart:convert';

import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/preferences.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'FlClashX',
      packageName: 'com.follow.clashx',
      version: '0.4.2',
      buildNumber: '2026071801',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    await preferences.clearPreferences();
    preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
      ..complete(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.clearPreferences();
    preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
      ..complete(await SharedPreferences.getInstance());
  });

  test(
    'GlobalState.init updates in-memory config.patchClashConfig on first-run legacy clash_config migration',
    () async {
      const legacyClash = ClashConfig(
        mixedPort: 17890,
        mode: Mode.global,
        logLevel: LogLevel.debug,
      );
      final store = _ControlledSharedPreferences(
        initialValues: <String, String>{
          clashConfigKey: json.encode(legacyClash),
        },
      );
      preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
        ..complete(store);

      final isolatedState = GlobalState.forTesting();
      await isolatedState.init();

      expect(isolatedState.config.patchClashConfig.mixedPort, 17890);
      expect(isolatedState.config.patchClashConfig.mode, Mode.global);
      expect(isolatedState.config.patchClashConfig.logLevel, LogLevel.debug);
      expect(store.getString(clashConfigKey), isNull);

      final persisted = Config.compatibleFromJson(
        json.decode(store.getString(configKey)!) as Map<String, Object?>,
      );
      expect(persisted.patchClashConfig.mixedPort, 17890);
      expect(persisted.patchClashConfig.mode, Mode.global);
    },
  );

  test(
    'GlobalState.migrateOldData updates this.config and awaits saveConfig before clearClashConfig',
    () async {
      const legacyClash = ClashConfig(
        mixedPort: 18890,
        allowLan: true,
      );
      final saveGate = Completer<bool>();
      final removeGate = Completer<bool>();
      addTearDown(() {
        if (!saveGate.isCompleted) {
          saveGate.complete(false);
        }
        if (!removeGate.isCompleted) {
          removeGate.complete(false);
        }
      });
      final store = _ControlledSharedPreferences(
        initialValues: <String, String>{
          clashConfigKey: json.encode(legacyClash),
        },
        onSetString: (key, _) =>
            key == configKey ? saveGate.future : Future<bool>.value(true),
        onRemove: (key) =>
            key == clashConfigKey ? removeGate.future : Future<bool>.value(true),
      );
      preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
        ..complete(store);

      const baseConfig = Config(
        themeProps: defaultThemeProps,
        currentProfileId: 'profile-1',
      );
      final state = GlobalState.forTesting()..config = baseConfig;

      var migrationReturned = false;
      final migrationFuture = state.migrateOldData(state.config).then((_) {
        migrationReturned = true;
      });

      await pumpEventQueue();
      expect(state.config.patchClashConfig.mixedPort, 18890);
      expect(state.config.patchClashConfig.allowLan, isTrue);
      expect(state.config.currentProfileId, 'profile-1');
      expect(store.operations, equals(<String>['set:$configKey']));
      expect(migrationReturned, isFalse);

      saveGate.complete(true);
      await pumpEventQueue();
      expect(
        store.operations,
        equals(<String>['set:$configKey', 'remove:$clashConfigKey']),
      );
      expect(migrationReturned, isFalse);

      removeGate.complete(true);
      await migrationFuture;
      expect(migrationReturned, isTrue);
      expect(store.getString(clashConfigKey), isNull);
    },
  );

  test(
    'GlobalState.migrateOldData retains legacy clash_config on disk if saveConfig fails',
    () async {
      const legacyClash = ClashConfig(mixedPort: 19890);
      final store = _ControlledSharedPreferences(
        initialValues: <String, String>{
          clashConfigKey: json.encode(legacyClash),
        },
        onSetString: (_, __) async => false,
      );
      preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
        ..complete(store);

      const baseConfig = Config(themeProps: defaultThemeProps);
      final state = GlobalState.forTesting()..config = baseConfig;

      await state.migrateOldData(state.config);

      expect(state.config.patchClashConfig.mixedPort, 19890);
      expect(store.operations, equals(<String>['set:$configKey']));
      expect(store.getString(clashConfigKey), isNotNull);
    },
  );

  test(
    'GlobalState.migrateOldData is a no-op when legacy clash_config is absent',
    () async {
      final store = _ControlledSharedPreferences();
      preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
        ..complete(store);

      const baseConfig = Config(
        themeProps: defaultThemeProps,
        currentProfileId: 'keep-me',
      );
      final state = GlobalState.forTesting()..config = baseConfig;

      await state.migrateOldData(state.config);

      expect(state.config, equals(baseConfig));
      expect(store.operations, isEmpty);
    },
  );
}

class _ControlledSharedPreferences extends Fake implements SharedPreferences {
  _ControlledSharedPreferences({
    Map<String, String>? initialValues,
    this.onSetString,
    this.onRemove,
  }) : _values = Map<String, String>.from(initialValues ?? const {});

  final Map<String, String> _values;
  final List<String> operations = <String>[];
  final Future<bool> Function(String key, String value)? onSetString;
  final Future<bool> Function(String key)? onRemove;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    operations.add('set:$key');
    final wrote = await (onSetString?.call(key, value) ?? Future.value(true));
    if (wrote) {
      _values[key] = value;
    }
    return wrote;
  }

  @override
  Future<bool> remove(String key) async {
    operations.add('remove:$key');
    final removed = await (onRemove?.call(key) ?? Future.value(true));
    if (removed) {
      _values.remove(key);
    }
    return removed;
  }

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }
}
