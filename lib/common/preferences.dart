import 'dart:async';
import 'dart:convert';

import 'package:flclashx/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constant.dart';

class Preferences {
  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Preferences._internal() : _encodeConfig = _defaultEncodeConfig {
    unawaited(
      SharedPreferences.getInstance()
          .then((value) => sharedPreferencesCompleter.complete(value))
          .onError((_, __) => sharedPreferencesCompleter.complete(null)),
    );
  }

  @visibleForTesting
  Preferences.forTesting({
    required Future<SharedPreferences?> store,
    String Function(Config)? encodeConfig,
  }) : _encodeConfig = encodeConfig ?? _defaultEncodeConfig {
    unawaited(
      store
          .then((value) => sharedPreferencesCompleter.complete(value))
          .onError((_, __) => sharedPreferencesCompleter.complete(null)),
    );
  }

  static String _defaultEncodeConfig(Config config) => json.encode(config);

  static Preferences? _instance;
  final String Function(Config) _encodeConfig;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();
  Config? _lastSavedConfig;
  Config? _pendingConfig;
  Future<bool>? _activeSave;

  Future<bool> get isInit async =>
      await sharedPreferencesCompleter.future != null;

  bool hasUnsavedConfig(Config config) =>
      _pendingConfig != null || _lastSavedConfig != config;

  Future<ClashConfig?> getClashConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    final clashConfigString = preferences?.getString(clashConfigKey);
    if (clashConfigString == null) return null;
    try {
      final clashConfigMap = json.decode(clashConfigString);
      return ClashConfig.fromJson(clashConfigMap);
    } catch (_) {
      await preferences?.remove(clashConfigKey);
      return null;
    }
  }

  Future<Config?> getConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    final configString = preferences?.getString(configKey);
    if (configString == null) return null;
    try {
      final configMap = json.decode(configString);
      final config = Config.compatibleFromJson(configMap);
      _lastSavedConfig = config;
      return config;
    } catch (_) {
      await preferences?.remove(configKey);
      return null;
    }
  }

  Future<bool> saveConfig(Config config) {
    if (_activeSave == null && _lastSavedConfig == config) {
      return Future<bool>.value(true);
    }
    _pendingConfig = config;
    return _activeSave ??= _drainPendingSaves().whenComplete(() {
      _activeSave = null;
    });
  }

  Future<bool> _drainPendingSaves() async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences == null) {
      _pendingConfig = null;
      return false;
    }
    var lastSaved = true;
    while (_pendingConfig != null) {
      final candidate = _pendingConfig!;
      _pendingConfig = null;
      if (_lastSavedConfig == candidate) {
        continue;
      }
      final encoded = _encodeConfig(candidate);
      lastSaved = await preferences.setString(configKey, encoded);
      if (lastSaved) {
        _lastSavedConfig = candidate;
      }
    }
    return lastSaved;
  }

  Future<void> clearClashConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.remove(clashConfigKey);
  }

  Future<void> clearPreferences() async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    _lastSavedConfig = null;
    _pendingConfig = null;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
