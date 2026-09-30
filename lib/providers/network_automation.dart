import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkAutomationSettings {
  const NetworkAutomationSettings({this.enabled = false, this.profiles = const {}});
  final bool enabled;
  // First matching transport wins; offline never stops or changes Core.
  static const priority = ['ethernet', 'wifi', 'mobile', 'bluetooth', 'other'];
  final Map<String, String> profiles;
}

class NetworkAutomationNotifier extends AsyncNotifier<NetworkAutomationSettings> {
  @override
  Future<NetworkAutomationSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('networkAutomationProfiles');
    final decoded = raw == null ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid network rules');
    final profiles = <String, String>{};
    for (final type in NetworkAutomationSettings.priority) {
      final value = decoded[type];
      if (value is String && value.isNotEmpty && value.length <= 256) profiles[type] = value;
    }
    return NetworkAutomationSettings(enabled: prefs.getBool('networkAutomationEnabled') ?? false,
        profiles: Map.unmodifiable(profiles));
  }

  Future<void> save(NetworkAutomationSettings value) async {
    if (value.profiles.keys.any((type) => !NetworkAutomationSettings.priority.contains(type)) ||
        value.profiles.values.any((id) => id.isEmpty || id.length > 256)) {
      throw ArgumentError('Invalid network rules');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('networkAutomationProfiles', jsonEncode(value.profiles)) ||
        !await prefs.setBool('networkAutomationEnabled', value.enabled)) {
      throw StateError('Cannot persist network automation');
    }
    state = AsyncData(NetworkAutomationSettings(enabled: value.enabled,
        profiles: Map.unmodifiable(value.profiles)));
  }
}

final networkAutomationProvider = AsyncNotifierProvider<NetworkAutomationNotifier,
    NetworkAutomationSettings>(NetworkAutomationNotifier.new);
