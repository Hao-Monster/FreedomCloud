import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

class Protocol {
  factory Protocol() {
    _instance ??= Protocol._internal();
    return _instance!;
  }

  Protocol._internal();
  static Protocol? _instance;

  void register(String scheme) {
    final protocolRegKey = 'Software\\Classes\\$scheme';
    const protocolCmdRegKey = r'shell\open\command';
    final expectedCmd = '"${Platform.resolvedExecutable}" "%1"';

    final regKey = Registry.currentUser.createKey(protocolRegKey);
    try {
      if (regKey.getStringValue('URL Protocol') != '') {
        regKey.createValue(const RegistryValue.string('URL Protocol', ''));
      }
      final cmdKey = regKey.createKey(protocolCmdRegKey);
      try {
        if (cmdKey.getStringValue('') != expectedCmd) {
          cmdKey.createValue(RegistryValue.string('', expectedCmd));
        }
      } finally {
        cmdKey.close();
      }
    } finally {
      regKey.close();
    }
  }
}

final protocol = Protocol();
