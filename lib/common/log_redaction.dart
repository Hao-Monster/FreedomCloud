final RegExp _logUrlPattern = RegExp(
  r'''\bhttps?://[^\s<>"']+''',
  caseSensitive: false,
);
final RegExp _logCredentialPattern = RegExp(
  r'''((?:authorization|proxy-authorization|password|passwd|secret|token|api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*)([^\s,;&]+)''',
  caseSensitive: false,
);
final RegExp _logBearerPattern = RegExp(
  r'''\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+''',
  caseSensitive: false,
);

bool _containsAsciiIgnoreCase(String haystack, String lowerNeedle) {
  final needleLen = lowerNeedle.length;
  final maxStart = haystack.length - needleLen;
  if (maxStart < 0) return false;
  final first = lowerNeedle.codeUnitAt(0);
  for (var i = 0; i <= maxStart; i++) {
    if ((haystack.codeUnitAt(i) | 0x20) != first) continue;
    var matched = true;
    for (var j = 1; j < needleLen; j++) {
      if ((haystack.codeUnitAt(i + j) | 0x20) != lowerNeedle.codeUnitAt(j)) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

bool _mayContainCredentialKeyword(String text) =>
    (text.contains(':') || text.contains('=')) &&
    (_containsAsciiIgnoreCase(text, 'token') ||
        _containsAsciiIgnoreCase(text, 'auth') ||
        _containsAsciiIgnoreCase(text, 'pass') ||
        _containsAsciiIgnoreCase(text, 'secret') ||
        _containsAsciiIgnoreCase(text, 'key'));

/// Removes credentials and remotely identifying URLs before they reach any
/// application log sink. Core and service output also passes through this
/// boundary, so call sites cannot accidentally bypass redaction.
String redactSensitiveLogData(String? text) {
  if (text == null || text.isEmpty) return text ?? '';

  var redacted = text;
  if (redacted.contains('://')) {
    redacted =
        redacted.replaceAllMapped(_logUrlPattern, (_) => '<redacted-url>');
  }
  if (_containsAsciiIgnoreCase(redacted, 'bearer') ||
      _containsAsciiIgnoreCase(redacted, 'basic')) {
    redacted = redacted.replaceAllMapped(
      _logBearerPattern,
      (_) => '<redacted-authorization>',
    );
  }
  if (_mayContainCredentialKeyword(redacted)) {
    redacted = redacted.replaceAllMapped(
      _logCredentialPattern,
      (match) => '${match.group(1)}<redacted>',
    );
  }
  return redacted;
}
