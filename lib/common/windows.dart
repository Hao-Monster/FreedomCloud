import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/windows_service_command.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:path/path.dart';
import 'package:win32/win32.dart';

/// ShellExecute returns an HINSTANCE-like value. Values 0..32 are documented
/// failure codes; any value above 32 means the elevated process was launched.
bool windowsShellExecuteSucceeded(int result) => result > 32;

typedef WindowsShellExecuteNative = Int32 Function(
  Pointer<Utf16> hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  Int32 nShowCmd,
);

typedef WindowsShellExecuteDart = int Function(
  Pointer<Utf16> hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  int nShowCmd,
);

bool runWindowsShellExecute({
  required String command,
  required String arguments,
  required WindowsShellExecuteDart Function() resolveShellExecute,
  Allocator allocator = calloc,
  String operation = 'runas',
}) {
  final result = using((arena) {
    final commandPtr = command.toNativeUtf16(allocator: arena);
    final argumentsPtr = arguments.toNativeUtf16(allocator: arena);
    final operationPtr = operation.toNativeUtf16(allocator: arena);
    final shellExecute = resolveShellExecute();
    return shellExecute(
      nullptr,
      operationPtr,
      commandPtr,
      argumentsPtr,
      nullptr,
      0,
    );
  }, allocator);

  commonPrint.log("windows runas: $command $arguments resultCode:$result");
  return windowsShellExecuteSucceeded(result);
}

class Windows {
  factory Windows() {
    _instance ??= Windows._internal();
    return _instance!;
  }

  Windows._internal() {
    _shell32 = DynamicLibrary.open('shell32.dll');
  }
  static Windows? _instance;
  late DynamicLibrary _shell32;

  DynamicLibrary? _dnsapi;
  int Function()? _dnsFlushResolverCache;

  /// Flushes the Windows DNS Client resolver cache in-process (<1ms, zero
  /// subprocess or console flash) so Fake-IP (198.18.0.0/16) entries cached
  /// while TUN was active cannot blackhole direct connections after TUN stops.
  bool tryFlushDnsResolverCache() {
    try {
      final flush = _dnsFlushResolverCache ??= (_dnsapi ??=
              DynamicLibrary.open('dnsapi.dll'))
          .lookupFunction<Int32 Function(), int Function()>(
        'DnsFlushResolverCache',
      );
      return flush() != 0;
    } catch (_) {
      return false;
    }
  }

  bool? tryReadThemeDark(String valueName) {
    try {
      return using((arena) {
        final keyPath =
            r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
                .toNativeUtf16(allocator: arena);
        final valueNamePtr = valueName.toNativeUtf16(allocator: arena);
        final phkResult = arena<HKEY>();

        var result =
            RegOpenKeyEx(HKEY_CURRENT_USER, keyPath, 0, KEY_READ, phkResult);
        if (result != ERROR_SUCCESS) return null;

        final hKey = phkResult.value;
        final data = arena<DWORD>();
        final dataSize = arena<DWORD>();
        dataSize.value = sizeOf<DWORD>();

        result = RegQueryValueEx(
            hKey, valueNamePtr, nullptr, nullptr, data.cast(), dataSize);
        RegCloseKey(hKey);
        if (result != ERROR_SUCCESS) return null;

        return data.value == 0;
      });
    } catch (_) {
      return null;
    }
  }

  bool _readThemeValue(String valueName) => tryReadThemeDark(valueName) ?? false;

  bool isDarkMode() => _readThemeValue('AppsUseLightTheme');

  bool isSystemDarkMode() => _readThemeValue('SystemUsesLightTheme');

  void enableDarkModeForApp() {
    try {
      final isDark = isDarkMode();

      try {
        final kernel32 = DynamicLibrary.open('kernel32.dll');
        final moduleName = 'uxtheme.dll'.toNativeUtf16();

        final getProcAddressFunc = kernel32.lookupFunction<
            IntPtr Function(IntPtr hModule, Pointer<Utf8> lpProcName),
            int Function(
                int hModule, Pointer<Utf8> lpProcName)>('GetProcAddress');

        final getModuleHandleFunc = kernel32.lookupFunction<
            IntPtr Function(Pointer<Utf16> lpModuleName),
            int Function(Pointer<Utf16> lpModuleName)>('GetModuleHandleW');

        final uxthemeHandle = getModuleHandleFunc(moduleName);
        calloc.free(moduleName);

        if (uxthemeHandle != 0) {
          final ordinal135 = Pointer<Utf8>.fromAddress(135);
          final setPreferredAppModePtr =
              getProcAddressFunc(uxthemeHandle, ordinal135);

          if (setPreferredAppModePtr != 0) {
            final setPreferredAppMode =
                Pointer<NativeFunction<Int32 Function(Int32)>>.fromAddress(
                        setPreferredAppModePtr)
                    .asFunction<int Function(int)>();
            setPreferredAppMode(isDark ? 1 : 0);
          } else {
            final ordinal133 = Pointer<Utf8>.fromAddress(133);
            final allowDarkModePtr =
                getProcAddressFunc(uxthemeHandle, ordinal133);

            if (allowDarkModePtr != 0) {
              final allowDarkModeForApp =
                  Pointer<NativeFunction<Int32 Function(Int32)>>.fromAddress(
                          allowDarkModePtr)
                      .asFunction<int Function(int)>();
              allowDarkModeForApp(isDark ? 1 : 0);
            }
          }

          // Ordinal 136 = FlushMenuThemes
          final ordinal136 = Pointer<Utf8>.fromAddress(136);
          final flushMenuThemesPtr =
              getProcAddressFunc(uxthemeHandle, ordinal136);

          if (flushMenuThemesPtr != 0) {
            final flushMenuThemes =
                Pointer<NativeFunction<Void Function()>>.fromAddress(
                        flushMenuThemesPtr)
                    .asFunction<void Function()>();
            flushMenuThemes();
          }
        }
      } catch (_) {
        // FFI call may fail on unsupported Windows versions
      }
    } catch (_) {
      // FFI call may fail on unsupported Windows versions
    }
  }

  bool runas(String command, String arguments) => runWindowsShellExecute(
        command: command,
        arguments: arguments,
        resolveShellExecute: () => _shell32.lookupFunction<
            WindowsShellExecuteNative,
            WindowsShellExecuteDart>('ShellExecuteW'),
      );

  static const int _scManagerConnect = 0x0001;
  static const int _serviceQueryConfig = 0x0001;
  static const int _serviceQueryStatus = 0x0004;
  static const int _readControl = 0x00020000;
  static const int _daclSecurityInformation = 0x00000004;
  static const int _sddlRevision1 = 1;

  DynamicLibrary? _advapi32;
  DynamicLibrary? _kernel32;

  int Function(
    int hService,
    int dwSecurityInformation,
    Pointer<Uint8> lpSecurityDescriptor,
    int cbBufSize,
    Pointer<Uint32> pcbBytesNeeded,
  )? _queryServiceObjectSecurity;

  int Function(
    Pointer<Uint8> securityDescriptor,
    int requestedStringSdRevision,
    int securityInformation,
    Pointer<Pointer<Utf16>> stringSecurityDescriptor,
    Pointer<Uint32> stringSecurityDescriptorLen,
  )? _convertSdToStringSd;

  int Function(Pointer<NativeType> hMem)? _localFree;

  String? _tryQueryServiceDaclSddl(
    int scm,
    Pointer<Utf16> serviceNamePtr,
    Arena arena,
  ) {
    final secService = OpenService(scm, serviceNamePtr, _readControl);
    if (secService == 0) return null;
    try {
      final advapi = _advapi32 ??= DynamicLibrary.open('advapi32.dll');
      final querySecurity = _queryServiceObjectSecurity ??= advapi
          .lookupFunction<
              Int32 Function(
                IntPtr hService,
                Uint32 dwSecurityInformation,
                Pointer<Uint8> lpSecurityDescriptor,
                Uint32 cbBufSize,
                Pointer<Uint32> pcbBytesNeeded,
              ),
              int Function(
                int hService,
                int dwSecurityInformation,
                Pointer<Uint8> lpSecurityDescriptor,
                int cbBufSize,
                Pointer<Uint32> pcbBytesNeeded,
              )>('QueryServiceObjectSecurity');
      final convertSd = _convertSdToStringSd ??= advapi.lookupFunction<
          Int32 Function(
            Pointer<Uint8> securityDescriptor,
            Uint32 requestedStringSdRevision,
            Uint32 securityInformation,
            Pointer<Pointer<Utf16>> stringSecurityDescriptor,
            Pointer<Uint32> stringSecurityDescriptorLen,
          ),
          int Function(
            Pointer<Uint8> securityDescriptor,
            int requestedStringSdRevision,
            int securityInformation,
            Pointer<Pointer<Utf16>> stringSecurityDescriptor,
            Pointer<Uint32> stringSecurityDescriptorLen,
          )>('ConvertSecurityDescriptorToStringSecurityDescriptorW');
      final freeLocal = _localFree ??=
          (_kernel32 ??= DynamicLibrary.open('kernel32.dll')).lookupFunction<
              IntPtr Function(Pointer<NativeType> hMem),
              int Function(Pointer<NativeType> hMem)>('LocalFree');

      final probeBuf = arena<Uint8>(4);
      final bytesNeeded = arena<Uint32>();
      querySecurity(
        secService,
        _daclSecurityInformation,
        probeBuf,
        0,
        bytesNeeded,
      );
      final needed = bytesNeeded.value;
      if (needed == 0 || needed > 65536) return null;

      final sdBuffer = arena<Uint8>(needed);
      if (querySecurity(
            secService,
            _daclSecurityInformation,
            sdBuffer,
            needed,
            bytesNeeded,
          ) ==
          0) {
        return null;
      }

      final outStringPtr = arena<Pointer<Utf16>>();
      if (convertSd(
            sdBuffer,
            _sddlRevision1,
            _daclSecurityInformation,
            outStringPtr,
            nullptr,
          ) ==
          0) {
        return null;
      }
      final sddlPtr = outStringPtr.value;
      if (sddlPtr == nullptr) return null;
      try {
        return sddlPtr.toDartString();
      } finally {
        freeLocal(sddlPtr);
      }
    } catch (_) {
      return null;
    } finally {
      CloseServiceHandle(secService);
    }
  }

  ({bool exists, int? state, String? binaryPathName, String? daclSddl})?
      tryQueryServiceSnapshot(
    String serviceName, {
    bool includeConfig = true,
    bool includeDaclSddl = false,
  }) {
    try {
      return using((arena) {
        final scm = OpenSCManager(nullptr, nullptr, _scManagerConnect);
        if (scm == 0) return null;
        try {
          final namePtr = serviceName.toNativeUtf16(allocator: arena);
          final desiredAccess = includeConfig
              ? (_serviceQueryStatus | _serviceQueryConfig)
              : _serviceQueryStatus;
          final service = OpenService(scm, namePtr, desiredAccess);
          if (service == 0) {
            if (!serviceName.contains(r'\') && !serviceName.contains('/')) {
              final regKeyPath =
                  'SYSTEM\\CurrentControlSet\\Services\\$serviceName'
                      .toNativeUtf16(allocator: arena);
              final phkResult = arena<HKEY>();
              final regStatus = RegOpenKeyEx(
                HKEY_LOCAL_MACHINE,
                regKeyPath,
                0,
                KEY_READ,
                phkResult,
              );
              if (regStatus == ERROR_FILE_NOT_FOUND) {
                return (
                  exists: false,
                  state: null,
                  binaryPathName: null,
                  daclSddl: null,
                );
              }
              if (regStatus == ERROR_SUCCESS) {
                RegCloseKey(phkResult.value);
              }
            }
            return null;
          }
          try {
            final statusPtr = arena<SERVICE_STATUS>();
            if (QueryServiceStatus(service, statusPtr) == 0) {
              return null;
            }
            final state = statusPtr.ref.dwCurrentState;
            final daclSddl = includeDaclSddl
                ? _tryQueryServiceDaclSddl(scm, namePtr, arena)
                : null;
            if (!includeConfig) {
              return (
                exists: true,
                state: state,
                binaryPathName: null,
                daclSddl: daclSddl,
              );
            }
            final bytesNeeded = arena<Uint32>();
            QueryServiceConfig(service, nullptr, 0, bytesNeeded);
            final needed = bytesNeeded.value;
            if (needed == 0 || needed > 65536) {
              return null;
            }
            final configBuffer = arena<Uint8>(needed);
            final configPtr = configBuffer.cast<QUERY_SERVICE_CONFIG>();
            if (QueryServiceConfig(service, configPtr, needed, bytesNeeded) ==
                0) {
              return null;
            }
            final binaryPtr = configPtr.ref.lpBinaryPathName;
            final binaryPath =
                binaryPtr == nullptr ? '' : binaryPtr.toDartString();
            return (
              exists: true,
              state: state,
              binaryPathName: binaryPath,
              daclSddl: daclSddl,
            );
          } finally {
            CloseServiceHandle(service);
          }
        } finally {
          CloseServiceHandle(scm);
        }
      });
    } catch (_) {
      return null;
    }
  }

  Future<WindowsHelperServiceStatus> checkService() async {
    final snapshot = tryQueryServiceSnapshot(
      appHelperService,
      includeDaclSddl: true,
    );
    if (snapshot != null) {
      return evaluateWindowsHelperServiceHealth(
        exists: snapshot.exists,
        isRunning: snapshot.state == SERVICE_RUNNING,
        rawBinaryPathName: snapshot.binaryPathName ?? '',
        daclSddl: snapshot.daclSddl,
        expectedHelperPath: appPath.windowsServiceHelperPath,
        pingHelper: request.pingHelper,
      );
    }

    final result = await Process.run('sc', ['query', appHelperService]);
    if (result.exitCode != 0) {
      return WindowsHelperServiceStatus.none;
    }
    final configuration = await Process.run('sc', ['qc', appHelperService]);
    final sdshow = await Process.run('sc', ['sdshow', appHelperService]);
    return evaluateWindowsHelperServiceHealth(
      exists: true,
      isRunning: windowsServiceQueryIsRunning(result.stdout.toString()),
      qcOutput:
          configuration.exitCode == 0 ? configuration.stdout.toString() : '',
      daclSddl: sdshow.exitCode == 0 ? sdshow.stdout.toString() : null,
      expectedHelperPath: appPath.windowsServiceHelperPath,
      pingHelper: request.pingHelper,
    );
  }

  /// Install the helper service (requires UAC elevation).
  /// This should only be called when the service is not installed.
  /// After installation, sets security descriptor to allow non-admin users
  /// to start/stop the service without UAC.
  Future<bool> installService() async {
    final status = await checkService();

    if (status == WindowsHelperServiceStatus.running) {
      return true;
    }

    final command = buildWindowsHelperRepairCommand(
      serviceExists: status != WindowsHelperServiceStatus.none,
      helperPath: appPath.helperPath,
      corePath: appPath.corePath,
      serviceDirectory: appPath.windowsServiceDirectory,
      serviceHelperPath: appPath.windowsServiceHelperPath,
      serviceCorePath: appPath.windowsServiceCorePath,
    );
    // Delayed expansion lets the elevated command log the real ERRORLEVEL
    // after each copy/SCM operation instead of only ShellExecuteW's launch
    // result.
    final launched = runas('cmd.exe', '/d /v:on /s /c "$command"');
    if (!launched) return false;

    // ShellExecute returns after the elevated process launches, not after the
    // service reaches RUNNING. Report success only after the helper responds
    // with the hash of the actual core on disk. The repair waits for the old
    // service to stop and copies the Core before restarting it, so allow a
    // bounded window well beyond the old 4.5 s.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await checkService() == WindowsHelperServiceStatus.running) {
        return true;
      }
    }
    commonPrint.log('helper install/repair timed out before becoming healthy');
    return false;
  }

  /// Try to start an existing service without UAC.
  /// Returns true if the service was started successfully or is already running.
  /// Returns false if the service is not installed or failed to start.
  Future<bool> tryStartExistingService() async {
    final status = await checkService();

    if (status == WindowsHelperServiceStatus.running) {
      return true;
    }

    if (status == WindowsHelperServiceStatus.none) {
      return false;
    }

    // Service exists but not running - try to start it without elevation
    final result = await Process.run('sc', ['start', appHelperService]);
    final output = '${result.stdout}\n${result.stderr}';
    // 1056 means a concurrent caller won the start race. Treat it as a
    // success candidate and verify the service endpoint below instead of
    // falling through to installService (which would show another UAC prompt).
    if (result.exitCode != 0 && !RegExp(r'\b1056\b').hasMatch(output)) {
      return false;
    }
    if (!await _waitForServiceState(running: true)) return false;
    return await checkService() == WindowsHelperServiceStatus.running;
  }

  /// Register the service - will request UAC only if service is not installed.
  /// If the service is already installed, it will try to start it without UAC.
  Future<bool> registerService() async {
    // First, try to start existing service without UAC
    if (await tryStartExistingService()) {
      return true;
    }

    // Service not installed or couldn't start - need to install with UAC
    return installService();
  }

  Future<bool> startService() async {
    final status = await checkService();
    if (status == WindowsHelperServiceStatus.running) return true;
    if (status == WindowsHelperServiceStatus.none) return false;

    final result = await Process.run('sc', ['start', appHelperService]);
    final output = '${result.stdout}\n${result.stderr}';
    // 1056 means the service is already running (a concurrent start won).
    // In either case, wait for the actual SCM state rather than trusting the
    // command exit code, which can precede service initialization.
    if (result.exitCode != 0 && !RegExp(r'\b1056\b').hasMatch(output)) {
      return false;
    }
    return _waitForServiceState(running: true);
  }

  Future<bool> stopService() async {
    final status = await checkService();
    if (status == WindowsHelperServiceStatus.none) return true;

    final result = await Process.run('sc', ['stop', appHelperService]);
    final output = '${result.stdout}\n${result.stderr}';
    // 1062 means it was already stopped; shutdown is idempotent.
    if (result.exitCode != 0 && !windowsServiceStopAlreadyStopped(output)) {
      return false;
    }
    return _waitForServiceState(running: false);
  }

  Future<bool> _waitForServiceState({required bool running}) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final snapshot =
          tryQueryServiceSnapshot(appHelperService, includeConfig: false);
      if (snapshot != null) {
        if (!snapshot.exists) return !running;
        final state = snapshot.state;
        if (running && state == SERVICE_RUNNING) return true;
        if (!running &&
            state != SERVICE_RUNNING &&
            state != SERVICE_STOP_PENDING) {
          return true;
        }
      } else {
        final result = await Process.run('sc', ['query', appHelperService]);
        if (result.exitCode != 0) return !running;
        final state = windowsServiceQueryStateCode(result.stdout.toString());
        if (running && state == 4) return true;
        if (!running && state != 4 && state != 3) return true;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> registerTask(String appName) async {
    final taskXml = '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Triggers>
    <LogonTrigger/>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${Platform.resolvedExecutable}"</Command>
    </Exec>
  </Actions>
</Task>''';
    final taskPath = join(await appPath.tempPath, "task.xml");
    await File(taskPath).create(recursive: true);
    await File(taskPath)
        .writeAsBytes(taskXml.encodeUtf16LeWithBom, flush: true);
    final commandLine = [
      '/Create',
      '/TN',
      appName,
      '/XML',
      "%s",
      '/F',
    ].join(" ");
    return runas(
      'schtasks',
      commandLine.replaceFirst("%s", taskPath),
    );
  }
}

final windows = Platform.isWindows ? Windows() : null;
