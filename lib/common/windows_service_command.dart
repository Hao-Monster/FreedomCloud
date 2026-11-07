import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/enum/enum.dart';

const windowsHelperServiceName = 'FlClashHelperService';

/// Win32 Advapi32 routine that recovers a legacy self-locked service whose SDDL
/// stripped `DC`, `SD`, `WD`, and `WO` from `Administrators`/`SY` (making
/// `sc config`, `sc sdset`, and `sc delete` all fail with error 5).
/// An elevated administrator token still holds `SeTakeOwnershipPrivilege`:
/// enabling it permits `OpenServiceW(WRITE_OWNER)` -> setting Owner to `BA`,
/// which implicitly grants `WRITE_DAC` to restore the full-control DACL in place.
/// Reads service name and target SDDL from `FCX_SVC` / `FCX_SDDL` env vars so
/// the payload is a compile-time constant with zero string interpolation.
const _scmOwnershipUnlockScript = r'''
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FcxScmUnlock {
  [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
  [StructLayout(LayoutKind.Sequential)] struct TP { public uint Count; public LUID Luid; public uint Attr; }
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LookupPrivilegeValueW(string s, string n, out LUID l);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr t, bool d, ref TP n, int l, IntPtr p, IntPtr r);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string s, uint r, out IntPtr sd, out uint sz);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenSCManagerW(string m, string d, uint a);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenServiceW(IntPtr scm, string n, uint a);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool SetServiceObjectSecurity(IntPtr s, uint i, IntPtr sd);
  [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr h);
  public static int Run(string svc, string sddl, out string step) {
    IntPtr tok = IntPtr.Zero, scm = IntPtr.Zero, hSvc = IntPtr.Zero, oSd = IntPtr.Zero, dSd = IntPtr.Zero;
    try {
      step = "OpenProcessToken";
      if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return Marshal.GetLastWin32Error();
      LUID luid; step = "LookupPrivilegeValueW";
      if (!LookupPrivilegeValueW(null, "SeTakeOwnershipPrivilege", out luid)) return Marshal.GetLastWin32Error();
      TP tp = new TP { Count = 1, Luid = luid, Attr = 2 };
      step = "AdjustTokenPrivileges";
      if (!AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return Marshal.GetLastWin32Error();
      int adjErr = Marshal.GetLastWin32Error();
      if (adjErr != 0) return adjErr;
      uint sz; step = "ConvertOwnerSddl";
      if (!ConvertStringSecurityDescriptorToSecurityDescriptorW("O:BA", 1, out oSd, out sz)) return Marshal.GetLastWin32Error();
      step = "ConvertDaclSddl";
      if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out dSd, out sz)) return Marshal.GetLastWin32Error();
      step = "OpenSCManagerW";
      scm = OpenSCManagerW(null, null, 0x0001);
      if (scm == IntPtr.Zero) return Marshal.GetLastWin32Error();
      step = "OpenServiceW(WRITE_OWNER)";
      hSvc = OpenServiceW(scm, svc, 0x00080000);
      if (hSvc == IntPtr.Zero) return Marshal.GetLastWin32Error();
      step = "SetServiceObjectSecurity(OWNER)";
      if (!SetServiceObjectSecurity(hSvc, 1, oSd)) return Marshal.GetLastWin32Error();
      CloseServiceHandle(hSvc); hSvc = IntPtr.Zero;
      step = "OpenServiceW(WRITE_DAC)";
      hSvc = OpenServiceW(scm, svc, 0x00040000);
      if (hSvc == IntPtr.Zero) return Marshal.GetLastWin32Error();
      step = "SetServiceObjectSecurity(DACL)";
      if (!SetServiceObjectSecurity(hSvc, 4, dSd)) return Marshal.GetLastWin32Error();
      step = "ok"; return 0;
    } finally {
      if (hSvc != IntPtr.Zero) CloseServiceHandle(hSvc);
      if (scm != IntPtr.Zero) CloseServiceHandle(scm);
      if (oSd != IntPtr.Zero) LocalFree(oSd);
      if (dSd != IntPtr.Zero) LocalFree(dSd);
      if (tok != IntPtr.Zero) CloseHandle(tok);
    }
  }
}
"@
$step = ''
$rc = [FcxScmUnlock]::Run($env:FCX_SVC, $env:FCX_SDDL, [ref]$step)
Write-Output "[helper-install] scm-unlock step=$step win32=$rc"
if ($rc -ne 0) { exit 1 }
''';

/// GZip+Base64 keeps the elevated cmd.exe line ~3.8 KB (well below cmd.exe's
/// 8191-char hard limit, which raw UTF-16LE -EncodedCommand would exceed).
final String _gzippedScmOwnershipUnlock = base64.encode(
  gzip.encode(utf8.encode(_scmOwnershipUnlockScript)),
);

final String _encodedScmUnlockBootstrap = _encodePowerShellUtf16LeBase64(
  r'$s=New-Object IO.StreamReader((New-Object IO.Compression.GZipStream('
  r'[IO.MemoryStream][Convert]::FromBase64String($env:FCX_Z),'
  r'[IO.Compression.CompressionMode]::Decompress)),[Text.Encoding]::UTF8);'
  r'&([scriptblock]::Create($s.ReadToEnd()))',
);

String _encodePowerShellUtf16LeBase64(String script) {
  final bytes = Uint8List(script.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < script.length; i++) {
    view.setUint16(i * 2, script.codeUnitAt(i), Endian.little);
  }
  return base64.encode(bytes);
}

final _unsafeCmdValuePattern = RegExp(r'["\r\n&|<>%^!]');
final _absoluteWindowsPathPattern = RegExp(r'^(?:[a-zA-Z]:\\|\\\\)');
const _msvcRuntimeFiles = [
  'concrt140.dll',
  'msvcp140.dll',
  'msvcp140_1.dll',
  'msvcp140_2.dll',
  'msvcp140_atomic_wait.dll',
  'msvcp140_codecvt_ids.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'vcruntime140_threads.dll',
];

const windowsHelperDefaultLogDirectory = r'%ProgramData%\FlClashX\logs';

/// Builds the elevated service repair command from values that cannot escape
/// cmd.exe quoting. The service is configured in place when it already exists;
/// deleting it on every transient health-check failure caused repeat UAC and a
/// race with the Service Control Manager.
///
/// [serviceName] and [logDirectory] exist only so tests can execute the real
/// command against a non-existent service and a temporary directory.
String buildWindowsHelperRepairCommand({
  required bool serviceExists,
  required String helperPath,
  required String corePath,
  required String serviceDirectory,
  required String serviceHelperPath,
  required String serviceCorePath,
  String serviceName = windowsHelperServiceName,
  String logDirectory = windowsHelperDefaultLogDirectory,
}) {
  _validateWindowsPath(helperPath, 'helperPath');
  _validateWindowsPath(corePath, 'corePath');
  _validateWindowsPath(serviceDirectory, 'serviceDirectory');
  _validateWindowsPath(serviceHelperPath, 'serviceHelperPath');
  _validateWindowsPath(serviceCorePath, 'serviceCorePath');
  if (logDirectory != windowsHelperDefaultLogDirectory) {
    _validateWindowsPath(logDirectory, 'logDirectory');
  }
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(serviceName)) {
    throw ArgumentError.value(serviceName, 'serviceName', 'invalid name');
  }

  final sourceDirectory = helperPath.substring(0, helperPath.lastIndexOf(r'\'));
  final installLog = '$logDirectory\\helper-install.log';
  // Store log path and helper binary path in cmd variables so 26 redirects and
  // `(x86)` parentheses never bloat the 8191-char cmd.exe limit or break `(...)`.
  const logRedirect = '>> "!fcx_l!" 2>&1';
  const logMarker = 'echo [helper-install] [%date% %time%]';
  // Keep LocalSystem and Administrators full control (including change-config,
  // delete and security rights, so a later elevated repair can still run
  // `sc config`/`sc sdset`) while allowing the interactive user to query,
  // start and stop the service without another UAC prompt. Users are not
  // granted change-config, delete, or security rights.
  const serviceSecurity =
      'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)'
      '(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)'
      '(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)';
  final runtimeCopies = _msvcRuntimeFiles
      .map((name) => 'copy /b /y "$sourceDirectory\\$name" '
          '"$serviceDirectory\\$name" $logRedirect')
      .join(' && ');

  // Escape inner quotes (`"\"!fcx_p!\""`) so sc.exe's MSVCRT argv parser
  // preserves surrounding quotes in SCM BINARY_PATH_NAME while delayed
  // expansion hides any `(x86)` parentheses from cmd.exe's `(...)` parser.
  const quotedHelperBinPath = r'"\"!fcx_p!\""';
  final configureAndAcl = serviceExists
      ? 'sc config $serviceName '
          'binPath= $quotedHelperBinPath start= auto $logRedirect & '
          '(set fcx_cfg=!errorlevel!) & '
          '$logMarker configure-service exit=!fcx_cfg! $logRedirect & '
          'sc sdset $serviceName "$serviceSecurity" $logRedirect & '
          '(set fcx_acl=!errorlevel!) & '
          '$logMarker set-service-acl exit=!fcx_acl! $logRedirect & '
          '(set fcx_need_unlock=0) & '
          '(if !fcx_cfg! equ 5 (set fcx_need_unlock=1)) & '
          '(if !fcx_acl! equ 5 (set fcx_need_unlock=1)) & '
          '(if !fcx_need_unlock! equ 1 '
          '(set "FCX_SVC=$serviceName") & '
          '(set "FCX_SDDL=$serviceSecurity") & '
          '(set "FCX_Z=$_gzippedScmOwnershipUnlock") & '
          'powershell -NoProfile -NonInteractive -EncodedCommand '
          '$_encodedScmUnlockBootstrap $logRedirect & '
          '(set fcx_unlock=!errorlevel!) & '
          '$logMarker unlock-service-acl exit=!fcx_unlock! $logRedirect & '
          'sc config $serviceName binPath= $quotedHelperBinPath start= auto '
          '$logRedirect & '
          '$logMarker reconfigure-service exit=!errorlevel! $logRedirect & '
          'sc sdset $serviceName "$serviceSecurity" $logRedirect & '
          '$logMarker reapply-service-acl exit=!errorlevel! $logRedirect)'
      : 'sc create $serviceName '
          'binPath= $quotedHelperBinPath start= auto $logRedirect & '
          '$logMarker configure-service exit=!errorlevel! $logRedirect & '
          'sc sdset $serviceName "$serviceSecurity" $logRedirect & '
          '$logMarker set-service-acl exit=!errorlevel! $logRedirect';

  // cmd.exe treats everything after `if <cond> <command>` on the same line,
  // including `& next`, as the IF body. Unparenthesized, an existing log or
  // service directory silently skipped the entire repair after UAC consent.
  // `net stop` waits for the service to stop so its binaries can be replaced.
  return '(if not exist "$logDirectory" mkdir "$logDirectory") >nul 2>&1 & '
      '(set "fcx_l=$installLog") & '
      '(set "fcx_p=$serviceHelperPath") & '
      '$logMarker begin >> "$installLog" 2>&1 & '
      'net stop $serviceName $logRedirect & '
      '$logMarker service-stop exit=!errorlevel! $logRedirect & '
      '(if not exist "$serviceDirectory" mkdir "$serviceDirectory") '
      '$logRedirect & '
      '$logMarker mkdir-service exit=!errorlevel! $logRedirect & '
      'copy /b /y "$helperPath" "$serviceHelperPath" $logRedirect & '
      '$logMarker copy-helper exit=!errorlevel! $logRedirect & '
      'copy /b /y "$corePath" "$serviceCorePath" $logRedirect & '
      '$logMarker copy-core exit=!errorlevel! $logRedirect & '
      '$runtimeCopies & '
      '$logMarker copy-runtime exit=!errorlevel! $logRedirect & '
      '$configureAndAcl & '
      'sc start $serviceName $logRedirect & '
      '$logMarker start-service exit=!errorlevel! $logRedirect & '
      'sc queryex $serviceName $logRedirect & '
      '$logMarker query-service exit=!errorlevel! $logRedirect & '
      '$logMarker end $logRedirect';
}

void _validateWindowsPath(String value, String name) {
  if (!_absoluteWindowsPathPattern.hasMatch(value) ||
      _unsafeCmdValuePattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be an absolute Windows path without cmd metacharacters',
    );
  }
}

String _normalizeWindowsComparablePath(String value) {
  var normalized = value.trim().replaceAll('/', r'\');
  if (normalized.toLowerCase().startsWith(r'\\?\unc\')) {
    normalized = r'\\' + normalized.substring(8);
  } else if (normalized.startsWith(r'\\?\')) {
    normalized = normalized.substring(4);
  }
  if (normalized.startsWith(r'\\')) {
    normalized =
        r'\\' + normalized.substring(2).replaceAll(RegExp(r'\\+'), r'\');
  } else {
    normalized = normalized.replaceAll(RegExp(r'\\+'), r'\');
  }
  return normalized.toLowerCase();
}

/// Validates that SCM's raw `BINARY_PATH_NAME` value points to the exact
/// helper executable without extra arguments, suffix collisions, or unquoted
/// whitespace paths (which require one-time UAC self-heal to quote `binPath`).
bool windowsServiceBinaryPathMatchesHelper(
  String rawBinaryPathName,
  String helperPath,
) {
  final trimmed = rawBinaryPathName.trim();
  if (trimmed.isEmpty) return false;
  final normalizedExpected = _normalizeWindowsComparablePath(helperPath);
  if (normalizedExpected.isEmpty) return false;

  if (trimmed.startsWith('"')) {
    final closingQuote = trimmed.indexOf('"', 1);
    if (closingQuote < 0) return false;
    if (trimmed.substring(closingQuote + 1).trim().isNotEmpty) {
      return false;
    }
    final executable = trimmed.substring(1, closingQuote);
    return _normalizeWindowsComparablePath(executable) == normalizedExpected;
  }

  if (RegExp(r'\s').hasMatch(trimmed)) {
    return false;
  }
  return _normalizeWindowsComparablePath(trimmed) == normalizedExpected;
}

bool windowsServiceConfigReferencesHelper(String output, String helperPath) {
  final lines = const LineSplitter().convert(output);
  final englishMatch = RegExp(
    r'^\s*BINARY_PATH_NAME\s*:\s*(.*)$',
    caseSensitive: false,
  );
  for (final line in lines) {
    final match = englishMatch.firstMatch(line);
    if (match != null) {
      return windowsServiceBinaryPathMatchesHelper(
        match.group(1) ?? '',
        helperPath,
      );
    }
  }

  final localizedPathLine = RegExp(
    r'^[^:\r\n]+:\s*("?(?:\\\\\?\\)?[a-zA-Z]:[\\/].*|"?\\\\[^?].*)$',
  );
  for (final line in lines) {
    final match = localizedPathLine.firstMatch(line);
    if (match != null) {
      return windowsServiceBinaryPathMatchesHelper(
        match.group(1) ?? '',
        helperPath,
      );
    }
  }
  return false;
}

const int _sddlCapChangeConfig = 1 << 0;
const int _sddlCapWriteDac = 1 << 1;
const int _sddlCapDelete = 1 << 2;
const int _sddlCapRequiredMask =
    _sddlCapChangeConfig | _sddlCapWriteDac | _sddlCapDelete;

int _parseSddlRepairRightsMask(String rawRights) {
  final rights = rawRights.trim().toUpperCase();
  if (rights.isEmpty) return 0;
  if (rights.startsWith('0X')) {
    final bitmask = int.tryParse(rights.substring(2), radix: 16) ?? 0;
    if ((bitmask & 0x10000000) != 0) {
      return _sddlCapRequiredMask;
    }
    var granted = 0;
    if ((bitmask & 0x00000002) != 0) granted |= _sddlCapChangeConfig;
    if ((bitmask & 0x00040000) != 0) granted |= _sddlCapWriteDac;
    if ((bitmask & 0x00010000) != 0) granted |= _sddlCapDelete;
    return granted;
  }

  var granted = 0;
  for (var i = 0; i + 2 <= rights.length; i += 2) {
    switch (rights.substring(i, i + 2)) {
      case 'GA':
        return _sddlCapRequiredMask;
      case 'DC':
        granted |= _sddlCapChangeConfig;
      case 'WD':
        granted |= _sddlCapWriteDac;
      case 'SD':
        granted |= _sddlCapDelete;
    }
  }
  return granted;
}

/// Checks that the service DACL grants Built-in Administrators (`BA` /
/// `S-1-5-32-544`) `SERVICE_CHANGE_CONFIG` (`DC`), `WRITE_DAC` (`WD`), and
/// `DELETE` (`SD`) without a conflicting Deny ACE. Legacy self-locked SDDLs
/// return `false` so `checkService()` downgrades to `presence` for self-heal.
bool windowsServiceSddlAllowsAdminRepair(String sddl) {
  final trimmed = sddl.trim();
  final daclIndex = trimmed.toUpperCase().indexOf('D:');
  if (daclIndex < 0) return false;
  var daclSection = trimmed.substring(daclIndex + 2);
  final saclMatch = RegExp(r'(?:^|\))S:', caseSensitive: false)
      .firstMatch(daclSection);
  if (saclMatch != null) {
    final cut = daclSection[saclMatch.start] == ')'
        ? saclMatch.start + 1
        : saclMatch.start;
    daclSection = daclSection.substring(0, cut);
  }

  var granted = 0;
  for (final aceMatch in RegExp(r'\(([^)]*)\)').allMatches(daclSection)) {
    final parts = (aceMatch.group(1) ?? '').split(';');
    if (parts.length != 6) continue;
    final trustee = parts[5].trim().toUpperCase();
    if (trustee != 'BA' && trustee != 'S-1-5-32-544') continue;
    final aceType = parts[0].trim().toUpperCase();
    final mask = _parseSddlRepairRightsMask(parts[2]);
    if (aceType == 'D' && (mask & _sddlCapRequiredMask) != 0) {
      return false;
    }
    if (aceType == 'A') {
      granted |= mask;
    }
  }
  return (granted & _sddlCapRequiredMask) == _sddlCapRequiredMask;
}

Future<WindowsHelperServiceStatus> evaluateWindowsHelperServiceHealth({
  required bool exists,
  required bool isRunning,
  String? rawBinaryPathName,
  String? qcOutput,
  required String? daclSddl,
  required String expectedHelperPath,
  required Future<bool> Function() pingHelper,
}) async {
  if (!exists) {
    return WindowsHelperServiceStatus.none;
  }
  final pathValid = rawBinaryPathName != null
      ? windowsServiceBinaryPathMatchesHelper(
          rawBinaryPathName,
          expectedHelperPath,
        )
      : (qcOutput != null &&
          windowsServiceConfigReferencesHelper(qcOutput, expectedHelperPath));
  if (!pathValid) {
    return WindowsHelperServiceStatus.presence;
  }
  if (daclSddl == null || !windowsServiceSddlAllowsAdminRepair(daclSddl)) {
    return WindowsHelperServiceStatus.presence;
  }
  if (isRunning && await pingHelper()) {
    return WindowsHelperServiceStatus.running;
  }
  return WindowsHelperServiceStatus.presence;
}

bool windowsServiceQueryIsRunning(String output) =>
    RegExp(r':\s*4(?:\s|$)').hasMatch(output);

/// Parses the locale-independent numeric SCM state from `sc query` output.
/// Windows emits the same numeric state codes even when labels are localized.
int? windowsServiceQueryStateCode(String output) {
  final match = RegExp(r':\s*([1-7])(?:\s|$)').firstMatch(output);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// SCM reports 1062 when stopping a service that is already stopped. Treat it
/// as an idempotent success so repeated UI shutdowns do not show an error.
bool windowsServiceStopAlreadyStopped(String output) =>
    RegExp(r'\b1062\b').hasMatch(output);
