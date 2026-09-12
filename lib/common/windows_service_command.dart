const windowsHelperServiceName = 'FlClashHelperService';

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

/// Builds the elevated service repair command from values that cannot escape
/// cmd.exe quoting. The service is configured in place when it already exists;
/// deleting it on every transient health-check failure caused repeat UAC and a
/// race with the Service Control Manager.
String buildWindowsHelperRepairCommand({
  required bool serviceExists,
  required String helperPath,
  required String corePath,
  required String serviceDirectory,
  required String serviceHelperPath,
  required String serviceCorePath,
}) {
  _validateWindowsPath(helperPath, 'helperPath');
  _validateWindowsPath(corePath, 'corePath');
  _validateWindowsPath(serviceDirectory, 'serviceDirectory');
  _validateWindowsPath(serviceHelperPath, 'serviceHelperPath');
  _validateWindowsPath(serviceCorePath, 'serviceCorePath');

  final sourceDirectory = helperPath.substring(0, helperPath.lastIndexOf(r'\'));
  const installLog = r'%ProgramData%\FlClashX\logs\helper-install.log';
  const logRedirect = '>> "$installLog" 2>&1';
  const logMarker = 'echo [helper-install] [%date% %time%]';
  // Keep LocalSystem and Administrators full control while allowing the
  // interactive user to query, start and stop the service without another UAC
  // prompt. Users are not granted change-config, delete, or security rights.
  const serviceSecurity =
      'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCLCSWRPWPDTLOCRRC;;;BA)'
      '(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)';
  final runtimeCopies = _msvcRuntimeFiles
      .map((name) => 'copy /b /y "$sourceDirectory\\$name" '
          '"$serviceDirectory\\$name" $logRedirect')
      .join(' && ');

  final configure = serviceExists
      ? 'sc config $windowsHelperServiceName '
          'binPath= "$serviceHelperPath" start= auto'
      : 'sc create $windowsHelperServiceName '
          'binPath= "$serviceHelperPath" start= auto';

  return 'if not exist "%ProgramData%\\FlClashX\\logs" mkdir '
      '"%ProgramData%\\FlClashX\\logs" >nul 2>&1 & '
      '$logMarker begin >> "$installLog" 2>&1 & '
      'sc stop $windowsHelperServiceName $logRedirect & '
      '$logMarker sc-stop exit=!errorlevel! >> "$installLog" 2>&1 & '
      'if not exist "$serviceDirectory" mkdir "$serviceDirectory" $logRedirect & '
      '$logMarker mkdir-service exit=!errorlevel! >> "$installLog" 2>&1 & '
      'copy /b /y "$helperPath" "$serviceHelperPath" $logRedirect & '
      '$logMarker copy-helper exit=!errorlevel! >> "$installLog" 2>&1 & '
      'copy /b /y "$corePath" "$serviceCorePath" $logRedirect & '
      '$logMarker copy-core exit=!errorlevel! >> "$installLog" 2>&1 & '
      '$runtimeCopies & '
      '$logMarker copy-runtime exit=!errorlevel! >> "$installLog" 2>&1 & '
      '$configure $logRedirect & '
      '$logMarker configure-service exit=!errorlevel! >> "$installLog" 2>&1 & '
      'sc sdset $windowsHelperServiceName "$serviceSecurity" $logRedirect & '
      '$logMarker set-service-acl exit=!errorlevel! >> "$installLog" 2>&1 & '
      'sc start $windowsHelperServiceName $logRedirect & '
      '$logMarker start-service exit=!errorlevel! >> "$installLog" 2>&1 & '
      'sc queryex $windowsHelperServiceName $logRedirect & '
      '$logMarker query-service exit=!errorlevel! >> "$installLog" 2>&1 & '
      '$logMarker end >> "$installLog" 2>&1';
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

bool windowsServiceConfigReferencesHelper(String output, String helperPath) {
  String normalize(String value) =>
      value.replaceAll('/', r'\').replaceAll(r'\\?\', '').toLowerCase();

  return normalize(output).contains(normalize(helperPath));
}

bool windowsServiceQueryIsRunning(String output) =>
    RegExp(r':\s*4(?:\s|$)').hasMatch(output);
