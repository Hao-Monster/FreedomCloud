import 'dart:io';

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

  test('existing helper attempts in-place repair first and only recreates on access denied', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: true,
      helperPath: helperPath,
      corePath: corePath,
      serviceDirectory: serviceDirectory,
      serviceHelperPath: serviceHelperPath,
      serviceCorePath: serviceCorePath,
    );

    expect(command, contains('sc config FlClashHelperService'));
    expect(command, contains('if !fcx_cfg! equ 5 (set fcx_recreate=1)'));
    expect(command,
        contains('if !fcx_cfg! equ 0 if !fcx_acl! equ 5 (set fcx_recreate=1)'));
    expect(command, contains('if !fcx_recreate! equ 1'));
    expect(
      command.indexOf('sc config FlClashHelperService'),
      lessThan(command.indexOf('sc delete FlClashHelperService')),
    );
    expect(
      command.indexOf('sc delete FlClashHelperService'),
      lessThan(command.indexOf('sc create FlClashHelperService')),
    );
    // net stop waits for STOPPED so the running helper binary can be replaced.
    expect(command, contains('net stop FlClashHelperService'));
    expect(
        command.indexOf('net stop'), lessThan(command.indexOf('copy /b /y')));
    expect(
        command.indexOf('copy /b /y'), lessThan(command.indexOf('sc config')));
  });

  test('IF statements cannot swallow the rest of the repair chain', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: true,
      helperPath: helperPath,
      corePath: corePath,
      serviceDirectory: serviceDirectory,
      serviceHelperPath: serviceHelperPath,
      serviceCorePath: serviceCorePath,
    );

    // `if <cond> cmd & rest` makes `rest` part of the IF body in cmd.exe.
    // Every IF must be closed by a parenthesis before the next `&`.
    final ifStatements = RegExp(r'if not exist[^&]*&').allMatches(command);
    expect(ifStatements, isNotEmpty);
    for (final match in ifStatements) {
      final start = match.start;
      expect(command[start - 1], '(', reason: match.group(0));
      expect(match.group(0), contains(')'), reason: match.group(0));
    }
  });

  test('administrators keep full control of the service object', () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: true,
      helperPath: helperPath,
      corePath: corePath,
      serviceDirectory: serviceDirectory,
      serviceHelperPath: serviceHelperPath,
      serviceCorePath: serviceCorePath,
    );

    expect(command, contains('(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)'));
    expect(command, contains('(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)'));
    // Interactive users still cannot reconfigure, delete or re-ACL it.
    expect(command, contains('(A;;CCLCSWRPWPLOCRRC;;;IU)'));
  });

  test('rejects an unsafe service name or log directory', () {
    expect(
      () => buildWindowsHelperRepairCommand(
        serviceExists: true,
        helperPath: helperPath,
        corePath: corePath,
        serviceDirectory: serviceDirectory,
        serviceHelperPath: serviceHelperPath,
        serviceCorePath: serviceCorePath,
        serviceName: 'x & whoami',
      ),
      throwsArgumentError,
    );
    expect(
      () => buildWindowsHelperRepairCommand(
        serviceExists: true,
        helperPath: helperPath,
        corePath: corePath,
        serviceDirectory: serviceDirectory,
        serviceHelperPath: serviceHelperPath,
        serviceCorePath: serviceCorePath,
        logDirectory: r'C:\logs" & whoami',
      ),
      throwsArgumentError,
    );
  });

  test(
    'repair still copies binaries when its directories already exist',
    () async {
      final root = await Directory.systemTemp.createTemp('flclash-repair-');
      addTearDown(() => root.delete(recursive: true));
      final source = Directory('${root.path}\\source')..createSync();
      final service = Directory('${root.path}\\service')..createSync();
      final logs = Directory('${root.path}\\logs')..createSync();
      File('${source.path}\\FlClashHelperService.exe').writeAsStringSync('new');
      File('${source.path}\\FlClashCore.exe').writeAsStringSync('core');
      File('${service.path}\\FlClashHelperService.exe').writeAsStringSync('old');

      final command = buildWindowsHelperRepairCommand(
        serviceExists: true,
        helperPath: '${source.path}\\FlClashHelperService.exe',
        corePath: '${source.path}\\FlClashCore.exe',
        serviceDirectory: service.path,
        serviceHelperPath: '${service.path}\\FlClashHelperService.exe',
        serviceCorePath: '${service.path}\\FlClashCore.exe',
        // Never touch a real service from a unit test.
        serviceName: 'FlClashRepairTestNoSuchService',
        logDirectory: logs.path,
      );
      // Same lpParameters string as Windows.installService passes to
      // ShellExecuteW (minus the runas verb). It travels through an
      // environment variable because Dart's argv quoting would escape the
      // embedded quotes differently from ShellExecute.
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          [
            r'$p = Start-Process -FilePath cmd.exe',
            r'-ArgumentList $env:FLCLASH_REPAIR_ARGS',
            r'-WindowStyle Hidden -Wait -PassThru; exit $p.ExitCode',
          ].join(' '),
        ],
        environment: {
          'FLCLASH_REPAIR_ARGS': '/d /v:on /s /c "$command"',
        },
      );

      expect(result.stderr.toString().trim(), isEmpty);
      expect(
        File('${service.path}\\FlClashHelperService.exe').readAsStringSync(),
        'new',
      );
      expect(
        File('${service.path}\\FlClashCore.exe').readAsStringSync(),
        'core',
      );
      final log = File('${logs.path}\\helper-install.log').readAsStringSync();
      expect(log, contains('begin'));
      expect(log, contains('copy-helper exit=0'));
      expect(log, isNot(contains('recreate-delete')));
      expect(log, contains('end'));
    },
    skip: Platform.isWindows ? false : 'requires cmd.exe',
  );

  test(
    'self-locked service SDDL (exit=5) triggers delete-and-recreate fallback while exit=0 stays in place',
    () async {
      final root = await Directory.systemTemp.createTemp('flclash-sddl-heal-');
      addTearDown(() => root.delete(recursive: true));
      final bin = Directory('${root.path}\\mockbin')..createSync();
      final source = Directory('${root.path}\\source')..createSync();
      final service = Directory('${root.path}\\service')..createSync();
      final logs = Directory('${root.path}\\logs')..createSync();
      final scTrace = File('${root.path}\\sc-calls.txt');

      File('${source.path}\\FlClashHelperService.exe').writeAsStringSync('new');
      File('${source.path}\\FlClashCore.exe').writeAsStringSync('core');
      File('${bin.path}\\net.cmd').writeAsStringSync('@exit /b 0\r\n');
      File('${bin.path}\\sc.cmd').writeAsStringSync(
        '@echo %1>>"${scTrace.path}"\r\n'
        '@if /i "%1"=="config" exit /b %MOCK_SC_CONFIG_EXIT%\r\n'
        '@if /i "%1"=="sdset" (\r\n'
        '  if not exist "${root.path}\\recreated.flag" exit /b %MOCK_SC_SDSET_EXIT%\r\n'
        '  exit /b 0\r\n'
        ')\r\n'
        '@if /i "%1"=="create" (\r\n'
        '  echo ok>"${root.path}\\recreated.flag"\r\n'
        '  exit /b 0\r\n'
        ')\r\n'
        '@exit /b 0\r\n',
      );

      final command = buildWindowsHelperRepairCommand(
        serviceExists: true,
        helperPath: '${source.path}\\FlClashHelperService.exe',
        corePath: '${source.path}\\FlClashCore.exe',
        serviceDirectory: service.path,
        serviceHelperPath: '${service.path}\\FlClashHelperService.exe',
        serviceCorePath: '${service.path}\\FlClashCore.exe',
        serviceName: 'FlClashRepairMockService',
        logDirectory: logs.path,
      );

      Future<void> runMockRepair({
        required String configExit,
        required String sdsetExit,
      }) async {
        if (scTrace.existsSync()) scTrace.deleteSync();
        final recreated = File('${root.path}\\recreated.flag');
        if (recreated.existsSync()) recreated.deleteSync();
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            [
              r'$p = Start-Process -FilePath cmd.exe',
              r'-ArgumentList $env:FLCLASH_REPAIR_ARGS',
              r'-WindowStyle Hidden -Wait -PassThru; exit $p.ExitCode',
            ].join(' '),
          ],
          environment: {
            'PATH': '${bin.path};${Platform.environment['PATH'] ?? ''}',
            'MOCK_SC_CONFIG_EXIT': configExit,
            'MOCK_SC_SDSET_EXIT': sdsetExit,
            'FLCLASH_REPAIR_ARGS': '/d /v:on /s /c "$command"',
          },
        );
        expect(result.stderr.toString().trim(), isEmpty);
      }

      await runMockRepair(configExit: '0', sdsetExit: '0');
      final healthyCalls = scTrace
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(healthyCalls, ['config', 'sdset', 'start', 'queryex']);

      await runMockRepair(configExit: '5', sdsetExit: '5');
      final lockedCalls = scTrace
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(
        lockedCalls,
        ['config', 'sdset', 'delete', 'create', 'sdset', 'start', 'queryex'],
      );
    },
    skip: Platform.isWindows ? false : 'requires cmd.exe',
  );

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

  test('SCM state parser is locale independent and handles pending states', () {
    expect(windowsServiceQueryStateCode('STATE : 1  STOPPED'), 1);
    expect(windowsServiceQueryStateCode('状态 : 3  STOP_PENDING'), 3);
    expect(windowsServiceQueryStateCode('STATE : 4  RUNNING'), 4);
    expect(windowsServiceQueryStateCode('unrelated output'), isNull);
  });

  test('already-stopped SCM error is treated as an idempotent stop', () {
    expect(
      windowsServiceStopAlreadyStopped('[SC] ControlService FAILED 1062'),
      isTrue,
    );
    expect(windowsServiceStopAlreadyStopped('error 5 access denied'), isFalse);
  });
}
