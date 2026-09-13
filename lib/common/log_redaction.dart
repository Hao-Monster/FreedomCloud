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

/// Removes credentials and remotely identifying URLs before they reach any
/// application log sink. Core and service output also passes through this
/// boundary, so call sites cannot accidentally bypass redaction.
String redactSensitiveLogData(String? text) {
  if (text == null || text.isEmpty) return text ?? '';

  var redacted = text.replaceAllMapped(_logUrlPattern, (_) => '<redacted-url>');
  redacted = redacted.replaceAllMapped(
    _logBearerPattern,
    (_) => '<redacted-authorization>',
  );
  return redacted.replaceAllMapped(
    _logCredentialPattern,
    (match) => '${match.group(1)}<redacted>',
  );
}
