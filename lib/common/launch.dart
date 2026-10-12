import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'constant.dart';
import 'print.dart';
import 'system.dart';

class AutoLaunch {

  factory AutoLaunch() {
    _instance ??= AutoLaunch._internal();
    return _instance!;
  }

  AutoLaunch._internal() {
    launchAtStartup.setup(
      appName: appName,
      // The Windows Run value is used verbatim as a command line; quote it so
      // install paths containing spaces (Program Files) are unambiguous.
      appPath: Platform.isWindows
          ? '"${Platform.resolvedExecutable}"'
          : Platform.resolvedExecutable,
    );
  }
  static AutoLaunch? _instance;

  Future<bool> get isEnable async => launchAtStartup.isEnabled();

  Future<bool> enable() async => launchAtStartup.enable();

  Future<bool> disable() async => launchAtStartup.disable();

  Future<bool> updateStatus(bool isAutoLaunch) async {
    if (kDebugMode) {
      return true;
    }
    try {
      // disable() is idempotent; always run it so a legacy entry that no longer
      // matches isEnabled (e.g. the former unquoted path) is still removed.
      if (isAutoLaunch && await isEnable) return true;
      final applied = isAutoLaunch ? await enable() : await disable();
      if (!applied) {
        commonPrint.log('autoLaunch: failed to set enabled=$isAutoLaunch');
      }
      return applied;
    } catch (e) {
      commonPrint.log('autoLaunch: failed to set enabled=$isAutoLaunch: $e');
      return false;
    }
  }
}

final autoLaunch = system.isDesktop ? AutoLaunch() : null;
