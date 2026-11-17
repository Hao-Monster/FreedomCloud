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

({bool hasUrlScheme, bool hasAssignment, bool hasAuthSchemeCandidate})
    _scanSensitiveCandidates(String text) {
  var hasUrlScheme = false;
  var hasAssignment = false;
  var hasAuthSchemeCandidate = false;
  final len = text.length;
  for (var i = 0; i < len; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x3A /* ':' */) {
      hasAssignment = true;
      if (!hasUrlScheme &&
          i + 2 < len &&
          text.codeUnitAt(i + 1) == 0x2F &&
          text.codeUnitAt(i + 2) == 0x2F) {
        hasUrlScheme = true;
      }
    } else if (c == 0x3D /* '=' */) {
      hasAssignment = true;
    } else if (!hasAuthSchemeCandidate && (c | 0x20) == 0x62 /* 'b' */) {
      if (i + 5 < len) {
        final next = text.codeUnitAt(i + 1) | 0x20;
        if (next == 0x65 /* 'e' -> bearer */ ||
            next == 0x61 /* 'a' -> basic */) {
          hasAuthSchemeCandidate = true;
        }
      }
    }
    if (hasUrlScheme && hasAssignment && hasAuthSchemeCandidate) {
      break;
    }
  }
  return (
    hasUrlScheme: hasUrlScheme,
    hasAssignment: hasAssignment,
    hasAuthSchemeCandidate: hasAuthSchemeCandidate,
  );
}

bool _mayContainCredentialKeyword(String text) =>
    _containsAsciiIgnoreCase(text, 'token') ||
    _containsAsciiIgnoreCase(text, 'auth') ||
    _containsAsciiIgnoreCase(text, 'pass') ||
    _containsAsciiIgnoreCase(text, 'secret') ||
    _containsAsciiIgnoreCase(text, 'key');

/// Removes credentials and remotely identifying URLs before they reach any
/// application log sink. Core and service output also passes through this
/// boundary, so call sites cannot accidentally bypass redaction.
String redactSensitiveLogData(String? text) {
  if (text == null || text.isEmpty) return text ?? '';

  final candidates = _scanSensitiveCandidates(text);
  if (!candidates.hasUrlScheme &&
      !candidates.hasAssignment &&
      !candidates.hasAuthSchemeCandidate) {
    return text;
  }

  var redacted = text;
  if (candidates.hasUrlScheme) {
    redacted =
        redacted.replaceAllMapped(_logUrlPattern, (_) => '<redacted-url>');
  }
  if (candidates.hasAuthSchemeCandidate &&
      (_containsAsciiIgnoreCase(redacted, 'bearer') ||
          _containsAsciiIgnoreCase(redacted, 'basic'))) {
    redacted = redacted.replaceAllMapped(
      _logBearerPattern,
      (_) => '<redacted-authorization>',
    );
  }
  if (candidates.hasAssignment && _mayContainCredentialKeyword(redacted)) {
    redacted = redacted.replaceAllMapped(
      _logCredentialPattern,
      (match) => '${match.group(1)}<redacted>',
    );
  }
  return redacted;
}
