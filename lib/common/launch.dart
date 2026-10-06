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
      appPath: Platform.resolvedExecutable,
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
      if (await isEnable == isAutoLaunch) return true;
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
