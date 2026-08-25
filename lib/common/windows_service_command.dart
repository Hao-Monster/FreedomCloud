const windowsHelperServiceName = 'FlClashHelperService';

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _unsafeCmdValuePattern = RegExp(r'["\r\n&|<>%^!]');
final _absoluteWindowsPathPattern = RegExp(r'^(?:[a-zA-Z]:\\|\\\\)');

/// Builds the elevated service repair command from values that cannot escape
/// cmd.exe quoting. The service is configured in place when it already exists;
/// deleting it on every transient health-check failure caused repeat UAC and a
/// race with the Service Control Manager.
String buildWindowsHelperRepairCommand({
  required bool serviceExists,
  required String helperPath,
  required String allowedHashPath,
  required String coreHash,
}) {
  _validateWindowsPath(helperPath, 'helperPath');
  _validateWindowsPath(allowedHashPath, 'allowedHashPath');
  if (!_sha256Pattern.hasMatch(coreHash)) {
    throw ArgumentError.value(coreHash, 'coreHash', 'must be a SHA-256 digest');
  }

  final configure = serviceExists
      ? 'sc stop $windowsHelperServiceName >nul 2>&1 & '
          'sc config $windowsHelperServiceName '
          'binPath= "$helperPath" start= auto'
      : 'sc create $windowsHelperServiceName '
          'binPath= "$helperPath" start= auto';

  return '$configure && '
      '> "$allowedHashPath" echo $coreHash && '
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
