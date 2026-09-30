import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PacSettings {
  const PacSettings({this.enabled = false, this.url = ''});
  final bool enabled;
  final String url;

  static bool validUrl(String value) {
    final uri = Uri.tryParse(value);
    return value.length <= 2048 && !value.contains(RegExp(r'[\x00-\x20]')) &&
        uri != null && ['https', 'http'].contains(uri.scheme) &&
        uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }
}

class PacSettingsNotifier extends AsyncNotifier<PacSettings> {
  @override
  Future<PacSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('systemPacUrl') ?? '';
    return PacSettings(enabled: (prefs.getBool('systemPacEnabled') ?? false) &&
        PacSettings.validUrl(url), url: url);
  }

  Future<void> save(PacSettings value) async {
    if (value.enabled && !PacSettings.validUrl(value.url)) {
      throw ArgumentError('请输入有效的 HTTP 或 HTTPS PAC 地址');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('systemPacUrl', value.url) ||
        !await prefs.setBool('systemPacEnabled', value.enabled)) {
      throw StateError('无法保存 PAC 设置');
    }
    state = AsyncData(value);
  }
}

final pacSettingsProvider = AsyncNotifierProvider<PacSettingsNotifier, PacSettings>(
    PacSettingsNotifier.new);
