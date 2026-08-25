const windowsHelperServiceName = 'FlClashHelperService';

final _unsafeCmdValuePattern = RegExp(r'["\r\n&|<>%^!]');
final _absoluteWindowsPathPattern = RegExp(r'^(?:[a-zA-Z]:\\|\\\\)');

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

  final configure = serviceExists
      ? 'sc config $windowsHelperServiceName '
          'binPath= "$serviceHelperPath" start= auto'
      : 'sc create $windowsHelperServiceName '
          'binPath= "$serviceHelperPath" start= auto';

  return 'sc stop $windowsHelperServiceName >nul 2>&1 & '
      'if not exist "$serviceDirectory" mkdir "$serviceDirectory" && '
      'copy /b /y "$helperPath" "$serviceHelperPath" >nul && '
      'copy /b /y "$corePath" "$serviceCorePath" >nul && '
      '$configure && '
      'sc start $windowsHelperServiceName';
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
