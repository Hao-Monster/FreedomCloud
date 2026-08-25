import 'package:flclashx/common/windows_service_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const helperPath = r'C:\Program Files\FlClashX\FlClashHelperService.exe';
  const hashPath = r'C:\Program Files\FlClashX\allowed_core.sha256';
  const hash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('new helper installation creates and starts the service', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: false,
      helperPath: helperPath,
      allowedHashPath: hashPath,
      coreHash: hash,
    );

    expect(command, contains('sc create FlClashHelperService'));
    expect(command, isNot(contains('sc delete')));
    expect(command.indexOf(hash), lessThan(command.indexOf('sc start')));
  });

  test('existing helper is repaired in place without deleting it', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: true,
      helperPath: helperPath,
      allowedHashPath: hashPath,
      coreHash: hash,
    );

    expect(command, contains('sc config FlClashHelperService'));
    expect(command, isNot(contains('sc delete')));
    expect(command, isNot(contains('sc create')));
    expect(command.indexOf(hash), lessThan(command.indexOf('sc start')));
  });

  test('command rejects values that could escape cmd quoting', () {
    expect(
      () => buildWindowsHelperRepairCommand(
        serviceExists: false,
        helperPath: '$helperPath" & whoami',
        allowedHashPath: hashPath,
        coreHash: hash,
      ),
      throwsArgumentError,
    );
    expect(
      () => buildWindowsHelperRepairCommand(
        serviceExists: false,
        helperPath: helperPath,
        allowedHashPath: hashPath,
        coreHash: 'not-a-sha256',
      ),
      throwsArgumentError,
    );
  });

  test('service configuration must reference the current helper binary', () {
    const current =
        r'BINARY_PATH_NAME   : "C:\Program Files\FlClashX\FlClashHelperService.exe"';
    const moved =
        r'BINARY_PATH_NAME   : "D:\Old FlClashX\FlClashHelperService.exe"';

    expect(
      windowsServiceConfigReferencesHelper(current, helperPath),
      isTrue,
    );
    expect(
      windowsServiceConfigReferencesHelper(moved, helperPath),
      isFalse,
    );
  });

  test('running service detection uses the SCM state code, not locale text',
      () {
    expect(windowsServiceQueryIsRunning('STATE : 4  RUNNING'), isTrue);
    expect(windowsServiceQueryIsRunning('状态 : 4  正在运行'), isTrue);
    expect(windowsServiceQueryIsRunning('STATE : 1  STOPPED'), isFalse);
  });
}
