import 'package:flclashx/common/windows_service_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const helperPath = r'C:\Program Files\FlClashX\FlClashHelperService.exe';
  const corePath = r'C:\Program Files\FlClashX\FlClashCore.exe';
  const serviceDirectory = r'C:\Program Files\FlClashX Service';
  const serviceHelperPath =
      r'C:\Program Files\FlClashX Service\FlClashHelperService.exe';
  const serviceCorePath = r'C:\Program Files\FlClashX Service\FlClashCore.exe';

  test('new helper installation creates and starts the service', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: false,
      helperPath: helperPath,
      corePath: corePath,
      serviceDirectory: serviceDirectory,
      serviceHelperPath: serviceHelperPath,
      serviceCorePath: serviceCorePath,
    );

    expect(command, contains('sc create FlClashHelperService'));
    expect(command, isNot(contains('sc delete')));
    expect(command, contains('copy /b /y "$helperPath" "$serviceHelperPath"'));
    expect(command, contains('copy /b /y "$corePath" "$serviceCorePath"'));
    expect(command,
        contains('copy /b /y "C:\\Program Files\\FlClashX\\msvcp140.dll"'));
    expect(command,
        contains('copy /b /y "C:\\Program Files\\FlClashX\\vcruntime140.dll"'));
    expect(
        command, contains(r'%ProgramData%\FlClashX\logs\helper-install.log'));
    expect(command, contains('sc sdset FlClashHelperService'));
    expect(command, contains('(A;;CCLCSWRPWPLOCRRC;;;IU)'));
    expect(command, contains('sc queryex FlClashHelperService'));
    expect(command, isNot(contains('allowed_core.sha256')));
    expect(
        command.indexOf('copy /b /y'), lessThan(command.indexOf('sc create')));
  });

  test('existing helper is repaired in place without deleting it', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: true,
      helperPath: helperPath,
      corePath: corePath,
      serviceDirectory: serviceDirectory,
      serviceHelperPath: serviceHelperPath,
      serviceCorePath: serviceCorePath,
    );

    expect(command, contains('sc config FlClashHelperService'));
    expect(command, isNot(contains('sc delete')));
    expect(command, isNot(contains('sc create')));
    expect(command, contains('sc stop FlClashHelperService'));
    expect(
        command.indexOf('copy /b /y'), lessThan(command.indexOf('sc config')));
  });

  test('command rejects values that could escape cmd quoting', () {
    expect(
      () => buildWindowsHelperRepairCommand(
        serviceExists: false,
        helperPath: '$helperPath" & whoami',
        corePath: corePath,
        serviceDirectory: serviceDirectory,
        serviceHelperPath: serviceHelperPath,
        serviceCorePath: serviceCorePath,
      ),
      throwsArgumentError,
    );
    expect(
      () => buildWindowsHelperRepairCommand(
        serviceExists: false,
        helperPath: helperPath,
        corePath: corePath,
        serviceDirectory: serviceDirectory,
        serviceHelperPath: '$serviceHelperPath" & whoami',
        serviceCorePath: serviceCorePath,
      ),
      throwsArgumentError,
    );
  });

  test('service configuration must reference the current helper binary', () {
    const current =
        r'BINARY_PATH_NAME   : "C:\Program Files\FlClashX Service\FlClashHelperService.exe"';
    const moved =
        r'BINARY_PATH_NAME   : "D:\Old FlClashX\FlClashHelperService.exe"';

    expect(
      windowsServiceConfigReferencesHelper(current, serviceHelperPath),
      isTrue,
    );
    expect(
      windowsServiceConfigReferencesHelper(moved, serviceHelperPath),
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
