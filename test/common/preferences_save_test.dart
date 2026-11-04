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
}
