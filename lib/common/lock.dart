import 'dart:io';

import 'package:flclashx/common/common.dart';

class SingleInstanceLock {
  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  SingleInstanceLock._internal();
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;
  bool _acquired = false;

  Future<bool> acquire() async {
    if (_acquired && _accessFile != null) {
      return true;
    }
    try {
      final lockFilePath = await appPath.lockFilePath;
      final lockFile = File(lockFilePath);
      await lockFile.create(recursive: true);
      _accessFile = await lockFile.open(mode: FileMode.write);
      await _accessFile?.lock();
      _acquired = true;
      return true;
    } catch (_) {
      return false;
    }
  }
}

final singleInstanceLock = SingleInstanceLock();
