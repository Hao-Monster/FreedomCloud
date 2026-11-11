import 'dart:async';
import 'dart:convert';

import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/preferences.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saveConfig skips JSON encoding and disk writes when Config is unchanged', () async {
    var encodeCount = 0;
    final prefs = Preferences.forTesting(
      store: SharedPreferences.getInstance(),
      encodeConfig: (config) {
        encodeCount++;
        return json.encode(config);
      },
    );

    const initial = Config(themeProps: defaultThemeProps);
    expect(prefs.hasUnsavedConfig(initial), isTrue);

    expect(await prefs.saveConfig(initial), isTrue);
    expect(encodeCount, 1);
    expect(prefs.hasUnsavedConfig(initial), isFalse);

    // Repeated saves of an identical or structurally equal Config are O(1) no-ops.
    const equalCopy = Config(themeProps: defaultThemeProps);
    expect(prefs.hasUnsavedConfig(equalCopy), isFalse);
    expect(await prefs.saveConfig(equalCopy), isTrue);
    expect(await prefs.saveConfig(initial), isTrue);
    expect(encodeCount, 1);

    // Mutating a field marks it dirty and writes once.
    final updated = initial.copyWith(overrideDns: true);
    expect(prefs.hasUnsavedConfig(updated), isTrue);
    expect(await prefs.saveConfig(updated), isTrue);
    expect(encodeCount, 2);
    expect(prefs.hasUnsavedConfig(updated), isFalse);
  });

  test('getConfig seeds lastSavedConfig so immediate saveConfig is a no-op', () async {
    const seeded = Config(
      themeProps: defaultThemeProps,
      overrideDns: true,
    );
    SharedPreferences.setMockInitialValues({
      configKey: json.encode(seeded),
    });

    var encodeCount = 0;
    final prefs = Preferences.forTesting(
      store: SharedPreferences.getInstance(),
      encodeConfig: (config) {
        encodeCount++;
        return json.encode(config);
      },
    );

    final loaded = await prefs.getConfig();
    expect(loaded, equals(seeded));
    expect(prefs.hasUnsavedConfig(loaded!), isFalse);
    expect(await prefs.saveConfig(loaded), isTrue);
    expect(encodeCount, 0);
  });

  test('concurrent saveConfig burst coalesces while store initializes', () async {
    final storeGate = Completer<SharedPreferences?>();
    var encodeCount = 0;
    final prefs = Preferences.forTesting(
      store: storeGate.future,
      encodeConfig: (config) {
        encodeCount++;
        return json.encode(config);
      },
    );

    const c1 = Config(themeProps: defaultThemeProps, currentProfileId: 'p1');
    const c2 = Config(themeProps: defaultThemeProps, currentProfileId: 'p2');
    const c3 = Config(themeProps: defaultThemeProps, currentProfileId: 'p3');

    final f1 = prefs.saveConfig(c1);
    final f2 = prefs.saveConfig(c2);
    final f3 = prefs.saveConfig(c3);

    storeGate.complete(await SharedPreferences.getInstance());
    final results = await Future.wait([f1, f2, f3]);
    expect(results, everyElement(isTrue));
    // Only the latest superseded snapshot is serialized once the store opens.
    expect(encodeCount, 1);

    final sp = await SharedPreferences.getInstance();
    final persisted = Config.compatibleFromJson(
      json.decode(sp.getString(configKey)!) as Map<String, Object?>,
    );
    expect(persisted.currentProfileId, 'p3');
  });

  test('clearPreferences invalidates and linearizes an in-flight saveConfig write',
      () async {
    final store = _SuspendingSharedPreferences();
    var encodeCount = 0;
    final prefs = Preferences.forTesting(
      store: Future<SharedPreferences?>.value(store),
      encodeConfig: (config) {
        encodeCount++;
        return json.encode(config);
      },
    );

    const c1 = Config(themeProps: defaultThemeProps, currentProfileId: 'in-flight');
    final saveFuture = prefs.saveConfig(c1);
    await store.writeEntered.future;

    final clearFuture = prefs.clearPreferences();
    store.allowWriteToFinish.complete(true);
    await Future.wait([saveFuture, clearFuture]);

    // Neither the backing store nor in-memory _lastSavedConfig may retain c1!
    expect(store.getString(configKey), isNull);
    expect(prefs.hasUnsavedConfig(c1), isTrue);

    expect(await prefs.saveConfig(c1), isTrue);
    expect(encodeCount, 2);
    expect(store.getString(configKey), isNotNull);
  });

  test('transient Profile.isUpdating toggles neither mark Config unsaved nor write disk',
      () async {
    var encodeCount = 0;
    final prefs = Preferences.forTesting(
      store: SharedPreferences.getInstance(),
      encodeConfig: (config) {
        encodeCount++;
        return json.encode(config);
      },
    );

    const p1 = Profile(
      id: 'p1',
      url: 'https://sub.example.com/p1',
      autoUpdateDuration: Duration(hours: 24),
    );
    const initial = Config(
      themeProps: defaultThemeProps,
      profiles: [p1],
      currentProfileId: 'p1',
    );
    expect(await prefs.saveConfig(initial), isTrue);
    expect(encodeCount, 1);
    expect(prefs.hasUnsavedConfig(initial), isFalse);

    // Setting transient isUpdating=true must not mark Config dirty or write disk.
    final updating = initial.copyWith(
      profiles: [p1.copyWith(isUpdating: true)],
    );
    expect(prefs.hasUnsavedConfig(updating), isFalse);
    expect(await prefs.saveConfig(updating), isTrue);
    expect(encodeCount, 1);

    // Rolling back isUpdating=false after a failed fetch must also remain clean.
    final rolledBack = initial.copyWith(
      profiles: [p1.copyWith(isUpdating: false)],
    );
    expect(prefs.hasUnsavedConfig(rolledBack), isFalse);
    expect(await prefs.saveConfig(rolledBack), isTrue);
    expect(encodeCount, 1);

    // Persisted changes made while isUpdating=true still write once, and the
    // subsequent isUpdating=false transition stays a no-op.
    final dirtyWhileUpdating = updating.copyWith(overrideDns: true);
    expect(prefs.hasUnsavedConfig(dirtyWhileUpdating), isTrue);
    expect(await prefs.saveConfig(dirtyWhileUpdating), isTrue);
    expect(encodeCount, 2);

    final cleanAfterRollback = rolledBack.copyWith(overrideDns: true);
    expect(prefs.hasUnsavedConfig(cleanAfterRollback), isFalse);
    expect(await prefs.saveConfig(cleanAfterRollback), isTrue);
    expect(encodeCount, 2);
  });
}

class _SuspendingSharedPreferences extends Fake implements SharedPreferences {
  final Map<String, String> _values = {};
  final Completer<void> writeEntered = Completer<void>();
  final Completer<bool> allowWriteToFinish = Completer<bool>();
  bool _suspendedOnce = false;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (!_suspendedOnce) {
      _suspendedOnce = true;
      writeEntered.complete();
      final ok = await allowWriteToFinish.future;
      if (ok) {
        _values[key] = value;
      }
      return ok;
    }
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> clear() async {
    _values.clear();
    return true;
  }
}
