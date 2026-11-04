import 'dart:io';

import 'package:flclashx/common/windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test(
    'SCM FFI queries running system service and missing service without spawning sc.exe',
    () {
      if (!Platform.isWindows) return;
      final win = Windows();

      final eventLog = win.tryQueryServiceSnapshot('EventLog');
      expect(eventLog, isNotNull);
      expect(eventLog!.exists, isTrue);
      expect(eventLog.state, SERVICE_RUNNING);
      expect(eventLog.binaryPathName, isNotNull);
      expect(eventLog.binaryPathName!.toLowerCase(), contains('svchost'));

      final missing = win.tryQueryServiceSnapshot(
        'FlClashX_Missing_Service_Probe_88421',
      );
      expect(missing, isNotNull);
      expect(missing!.exists, isFalse);
      expect(missing.state, isNull);
    },
  );
}
