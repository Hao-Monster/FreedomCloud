import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/windows_service_command.dart';
import 'package:flclashx/enum/enum.dart';
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
    expect(command, contains('(set "fcx_p=$serviceHelperPath")'));
    expect(command, contains(r'binPath= "\"!fcx_p!\""'));
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

  test(
      'existing helper attempts in-place repair first and unlocks ownership/DACL on access denied',
      () {
    final command = buildWindowsHelperRepairCommand(
      serviceExists: true,
      helperPath: helperPath,
      corePath: corePath,
      serviceDirectory: serviceDirectory,
      serviceHelperPath: serviceHelperPath,
      serviceCorePath: serviceCorePath,
    );

    expect(command, contains('sc config FlClashHelperService'));
    expect(command, contains('(set "fcx_p=$serviceHelperPath")'));
    expect(command, contains(r'binPath= "\"!fcx_p!\""'));
    // Legacy locked SDDL strips SD (DELETE) from BA/SY, so `sc delete` fails
    // with exit=5 too. Self-healing must take ownership + rewrite DACL in place.
    expect(command, isNot(contains('sc delete')));
    expect(command, contains('if !fcx_cfg! equ 5 (set fcx_need_unlock=1)'));
    expect(command, contains('if !fcx_acl! equ 5 (set fcx_need_unlock=1)'));
    expect(command, contains('if !fcx_need_unlock! equ 1'));
    expect(command, contains('-EncodedCommand '));
    // Must stay safely under cmd.exe's 8191-character command-line ceiling.
    expect(command.length, lessThan(7500));
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
    'self-locked service SDDL (exit=5) unlocks ownership/DACL in place while exit=0 skips PowerShell',
    () async {
      final root = await Directory.systemTemp.createTemp('flclash-sddl-heal-');
      addTearDown(() => root.delete(recursive: true));
      final bin = Directory('${root.path}\\mockbin')..createSync();
      final source = Directory('${root.path}\\source')..createSync();
      final logs = Directory('${root.path}\\logs')..createSync();
      final scTrace = File('${root.path}\\sc-calls.txt');
      final psTrace = File('${root.path}\\ps-calls.txt');

      File('${source.path}\\FlClashHelperService.exe').writeAsStringSync('new');
      File('${source.path}\\FlClashCore.exe').writeAsStringSync('core');
      File('${bin.path}\\net.cmd').writeAsStringSync('@exit /b 0\r\n');
      File('${bin.path}\\powershell.cmd').writeAsStringSync(
        '@echo svc=%FCX_SVC%>>"${psTrace.path}"\r\n'
        '@echo sddl=%FCX_SDDL%>>"${psTrace.path}"\r\n'
        '@echo ok>"${root.path}\\unlocked.flag"\r\n'
        '@exit /b 0\r\n',
      );
      File('${bin.path}\\sc.cmd').writeAsStringSync(
        '@echo %*>>"${scTrace.path}"\r\n'
        '@if /i "%1"=="config" (\r\n'
        '  if not exist "${root.path}\\unlocked.flag" exit /b %MOCK_SC_CONFIG_EXIT%\r\n'
        '  exit /b 0\r\n'
        ')\r\n'
        '@if /i "%1"=="sdset" (\r\n'
        '  if not exist "${root.path}\\unlocked.flag" exit /b %MOCK_SC_SDSET_EXIT%\r\n'
        '  exit /b 0\r\n'
        ')\r\n'
        '@exit /b 0\r\n',
      );

      final serviceX86 =
          Directory('${root.path}\\Program Files (x86)\\FlClashX Service')
            ..createSync(recursive: true);
      final expectedServiceHelper = '${serviceX86.path}\\FlClashHelperService.exe';
      final command = buildWindowsHelperRepairCommand(
        serviceExists: true,
        helperPath: '${source.path}\\FlClashHelperService.exe',
        corePath: '${source.path}\\FlClashCore.exe',
        serviceDirectory: serviceX86.path,
        serviceHelperPath: expectedServiceHelper,
        serviceCorePath: '${serviceX86.path}\\FlClashCore.exe',
        serviceName: 'FlClashRepairMockService',
        logDirectory: logs.path,
      );

      Future<void> runMockRepair({
        required String configExit,
        required String sdsetExit,
      }) async {
        for (final file in [
          scTrace,
          psTrace,
          File('${root.path}\\unlocked.flag'),
          File('${logs.path}\\helper-install.log'),
        ]) {
          if (file.existsSync()) file.deleteSync();
        }
        const systemPowerShell =
            r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';
        final result = await Process.run(
          systemPowerShell,
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
      final healthyLines = scTrace
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(
        healthyLines.map((line) => line.split(' ').first).toList(),
        ['config', 'sdset', 'start', 'queryex'],
      );
      expect(healthyLines.first, contains('binPath= "\\"$expectedServiceHelper\\""'));
      expect(psTrace.existsSync(), isFalse);

      await runMockRepair(configExit: '5', sdsetExit: '5');
      final lockedLines = scTrace
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(
        lockedLines.map((line) => line.split(' ').first).toList(),
        ['config', 'sdset', 'config', 'sdset', 'start', 'queryex'],
      );
      expect(lockedLines[0], contains('binPath= "\\"$expectedServiceHelper\\""'));
      expect(lockedLines[2], contains('binPath= "\\"$expectedServiceHelper\\""'));
      expect(psTrace.existsSync(), isTrue);
      final psInput = psTrace.readAsStringSync();
      expect(psInput, contains('svc=FlClashRepairMockService'));
      expect(psInput, contains('(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)'));
      final installLog =
          File('${logs.path}\\helper-install.log').readAsStringSync();
      expect(installLog, contains('unlock-service-acl exit=0'));
      expect(installLog, contains('reconfigure-service exit=0'));
      expect(installLog, contains('reapply-service-acl exit=0'));
    },
    skip: Platform.isWindows ? false : 'requires cmd.exe',
  );

  test(
    'embedded SDDL ownership unlock script compiles in PowerShell and rejects non-existent service cleanly',
    () async {
      final command = buildWindowsHelperRepairCommand(
        serviceExists: true,
        helperPath: helperPath,
        corePath: corePath,
        serviceDirectory: serviceDirectory,
        serviceHelperPath: serviceHelperPath,
        serviceCorePath: serviceCorePath,
        serviceName: 'FlClashRepairTestNoSuchService',
      );
      final gzMatch =
          RegExp(r'set "FCX_Z=([A-Za-z0-9+/=]+)"').firstMatch(command);
      final encodedMatch =
          RegExp(r'-EncodedCommand\s+([A-Za-z0-9+/=]+)').firstMatch(command);
      expect(gzMatch, isNotNull);
      expect(encodedMatch, isNotNull);
      final gzPayload = gzMatch!.group(1)!;
      final encoded = encodedMatch!.group(1)!;
      final decodedScript = utf8.decode(gzip.decode(base64.decode(gzPayload)));
      expect(decodedScript, contains('SeTakeOwnershipPrivilege'));
      expect(decodedScript, contains('SetServiceObjectSecurity'));
      expect(decodedScript, isNot(contains('FlClashRepairTestNoSuchService')));

      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
        environment: {
          'FCX_Z': gzPayload,
          'FCX_SVC': 'FlClashRepairTestNoSuchService',
          'FCX_SDDL': 'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)'
              '(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)'
              '(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)',
        },
      );
      final combined = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNonZero);
      // 1060 = ERROR_SERVICE_DOES_NOT_EXIST or 1300 = ERROR_NOT_ALL_ASSIGNED
      // when running unprivileged in unit tests — proves clean C# compilation,
      // SDDL parsing, and Win32 P/Invoke execution without touching real SCM.
      expect(combined, matches(RegExp(r'win32=(1060|1300|5)\b')));
    },
    skip: Platform.isWindows ? false : 'requires powershell.exe',
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
    expect(
      windowsServiceConfigReferencesHelper(
        r'BINARY_PATH_NAME   : C:\Program Files\FlClashX Service\FlClashHelperService.exe',
        serviceHelperPath,
      ),
      isFalse,
      reason: 'Unquoted path containing spaces must trigger UAC self-heal',
    );
    expect(
      windowsServiceConfigReferencesHelper(
        r'BINARY_PATH_NAME   : "C:\Program Files\FlClashX Service\FlClashHelperService.exe.bak"',
        serviceHelperPath,
      ),
      isFalse,
    );
    expect(
      windowsServiceConfigReferencesHelper(
        r'BINARY_PATH_NAME   : "D:\Wrapper\svc.exe" "C:\Program Files\FlClashX Service\FlClashHelperService.exe"',
        serviceHelperPath,
      ),
      isFalse,
    );
    expect(
      windowsServiceConfigReferencesHelper(
        r'BINARY_PATH_NAME   : "C:\Program Files\FlClashX Service\FlClashHelperService.exe" --unexpected',
        serviceHelperPath,
      ),
      isFalse,
    );
    expect(
      windowsServiceConfigReferencesHelper(
        r'二进制路径名称        : "\\?\c:/program files/flclashx service/flclashhelperservice.exe"',
        serviceHelperPath,
      ),
      isTrue,
    );
    expect(
      windowsServiceBinaryPathMatchesHelper(
        r'C:\FlClashX\FlClashHelperService.exe',
        r'C:\FlClashX\FlClashHelperService.exe',
      ),
      isTrue,
    );
  });

  test('SDDL admin repair validator detects self-locked BA/LA DACLs and accepts unlocked DACLs', () {
    const lockedBa =
        'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCLCSWRPWPDTLOCRRC;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)';
    const lockedLaOnly =
        'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;LA)(A;;CCLCSWRPLOCRRC;;;IU)(A;;CCLCSWRPLOCRRC;;;SU)';
    const explicitDenyBa =
        'D:(D;;DC;;;BA)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)';
    const unlockedHealthy =
        'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)';
    const genericAllBa = 'D:(A;;GA;;;SY)(A;;GA;;;BA)';
    const hexServiceAllAccessBa = 'D:(A;;0xf01ff;;;SY)(A;;0xf01ff;;;BA)';

    expect(windowsServiceSddlAllowsAdminRepair(lockedBa), isFalse);
    expect(windowsServiceSddlAllowsAdminRepair(lockedLaOnly), isFalse);
    expect(windowsServiceSddlAllowsAdminRepair(explicitDenyBa), isFalse);
    expect(windowsServiceSddlAllowsAdminRepair(''), isFalse);
    expect(windowsServiceSddlAllowsAdminRepair(unlockedHealthy), isTrue);
    expect(windowsServiceSddlAllowsAdminRepair(genericAllBa), isTrue);
    expect(windowsServiceSddlAllowsAdminRepair(hexServiceAllAccessBa), isTrue);
  });

  test('evaluateWindowsHelperServiceHealth downgrades unquoted space binPath or self-locked SDDL to presence', () async {
    const unlockedHealthy =
        'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)';
    const lockedBa =
        'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCLCSWRPWPDTLOCRRC;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)';

    expect(
      await evaluateWindowsHelperServiceHealth(
        exists: false,
        isRunning: false,
        rawBinaryPathName: null,
        daclSddl: null,
        expectedHelperPath: serviceHelperPath,
        pingHelper: () async => true,
      ),
      WindowsHelperServiceStatus.none,
    );

    expect(
      await evaluateWindowsHelperServiceHealth(
        exists: true,
        isRunning: true,
        rawBinaryPathName: serviceHelperPath, // unquoted with spaces
        daclSddl: unlockedHealthy,
        expectedHelperPath: serviceHelperPath,
        pingHelper: () async => true,
      ),
      WindowsHelperServiceStatus.presence,
    );

    expect(
      await evaluateWindowsHelperServiceHealth(
        exists: true,
        isRunning: true,
        rawBinaryPathName: '"$serviceHelperPath"',
        daclSddl: lockedBa,
        expectedHelperPath: serviceHelperPath,
        pingHelper: () async => true,
      ),
      WindowsHelperServiceStatus.presence,
    );

    expect(
      await evaluateWindowsHelperServiceHealth(
        exists: true,
        isRunning: true,
        rawBinaryPathName: '"$serviceHelperPath"',
        daclSddl: null,
        expectedHelperPath: serviceHelperPath,
        pingHelper: () async => true,
      ),
      WindowsHelperServiceStatus.presence,
    );

    expect(
      await evaluateWindowsHelperServiceHealth(
        exists: true,
        isRunning: true,
        rawBinaryPathName: '"$serviceHelperPath"',
        daclSddl: unlockedHealthy,
        expectedHelperPath: serviceHelperPath,
        pingHelper: () async => true,
      ),
      WindowsHelperServiceStatus.running,
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
