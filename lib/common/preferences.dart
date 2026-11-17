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

  static Config _persistableConfig(Config config) {
    final profiles = config.profiles;
    List<Profile>? normalized;
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].isUpdating) {
        normalized ??= List<Profile>.of(profiles, growable: false);
        normalized[i] = profiles[i].copyWith(isUpdating: false);
      }
    }
    return normalized == null ? config : config.copyWith(profiles: normalized);
  }

  static Preferences? _instance;
  final String Function(Config) _encodeConfig;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();
  Config? _lastSavedConfig;
  Config? _pendingConfig;
  Future<bool>? _activeSave;
  int _epoch = 0;

  Future<bool> get isInit async =>
      await sharedPreferencesCompleter.future != null;

  bool hasUnsavedConfig(Config config) =>
      _pendingConfig != null ||
      _lastSavedConfig != _persistableConfig(config);

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
    final readEpoch = _epoch;
    final preferences = await sharedPreferencesCompleter.future;
    final configString = preferences?.getString(configKey);
    if (configString == null) return null;
    try {
      final configMap = json.decode(configString);
      final config = Config.compatibleFromJson(configMap);
      if (readEpoch == _epoch && _pendingConfig == null) {
        _lastSavedConfig = _persistableConfig(config);
      }
      return config;
    } catch (_) {
      await preferences?.remove(configKey);
      return null;
    }
  }

  Future<bool> saveConfig(Config config) {
    final persistable = _persistableConfig(config);
    if (_activeSave == null && _lastSavedConfig == persistable) {
      return Future<bool>.value(true);
    }
    _pendingConfig = persistable;
    final saveEpoch = _epoch;
    return _activeSave ??= _drainPendingSaves(saveEpoch).whenComplete(() {
      _activeSave = null;
    });
  }

  Future<bool> _drainPendingSaves(int saveEpoch) async {
    final preferences = await sharedPreferencesCompleter.future;
    if (preferences == null) {
      if (saveEpoch == _epoch) {
        _pendingConfig = null;
      }
      return false;
    }
    var lastSaved = true;
    while (_pendingConfig != null && saveEpoch == _epoch) {
      final candidate = _pendingConfig!;
      _pendingConfig = null;
      if (_lastSavedConfig == candidate) {
        continue;
      }
      final encoded = _encodeConfig(candidate);
      final wrote = await preferences.setString(configKey, encoded);
      if (saveEpoch != _epoch) {
        return false;
      }
      lastSaved = wrote;
      if (wrote) {
        _lastSavedConfig = candidate;
      }
    }
    return saveEpoch == _epoch && lastSaved;
  }

  Future<void> clearClashConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.remove(clashConfigKey);
  }

  Future<void> clearPreferences() async {
    _epoch++;
    _lastSavedConfig = null;
    _pendingConfig = null;
    final inFlight = _activeSave;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
