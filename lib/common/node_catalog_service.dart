import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/common/node_catalog_provider_resolver.dart';
import 'package:flclashx/common/node_catalog_test_plan.dart';

export 'package:flclashx/common/node_catalog_test_plan.dart';

typedef CatalogFileMetadata = ({int modifiedMicros, int size});
typedef PrepareNodeCatalog = Future<String> Function(String catalogId,
    List<Map<String, dynamic>> proxies, List<Map<String, dynamic>> providers);

/// A reason code, deliberately excluding parser/source text and credentials.
class CatalogBuildException implements Exception {
  const CatalogBuildException(this.reason);

  final String reason;

  @override
  String toString() => 'CatalogBuildException($reason)';
}

const _nonLeafTypes = {
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
  'compatible',
};

String? _canonicalAdapterType(String? rawType) {
  final normalized = rawType?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  return switch (normalized) {
    'ss' => 'shadowsocks',
    'ssr' => 'shadowsocksr',
    'gost-relay' => 'gostrelay',
    'reject-drop' => 'rejectdrop',
    'pass-rule' => 'passrule',
    'url-test' => 'urltest',
    'load-balance' => 'loadbalance',
    'select' => 'selector',
    _ => normalized,
  };
}

typedef _RegexFlags = ({bool ignoreCase, bool multiLine, bool dotAll});

final _inlineFlagOnlyPattern = RegExp(r'^\(\?([imsIMS+-]+)\)');
final _inlineFlagGroupPattern = RegExp(r'^\(\?([imsIMS+-]+):');
final _namedCaptureGroupPattern = RegExp(r'^\(\?<([A-Za-z_][A-Za-z0-9_]*)>');
final _quantifierBracePattern = RegExp(r'^\{\d+(?:,\d*)?\}');

const _regexp2SpaceChars =
    r'\t-\r \x85\xA0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000';
const _regexp2SpaceClass = '[$_regexp2SpaceChars]';
const _regexp2NonSpaceClass = '[^$_regexp2SpaceChars]';

_RegexFlags _applyInlineFlags(_RegexFlags current, String spec) {
  var ignoreCase = current.ignoreCase;
  var multiLine = current.multiLine;
  var dotAll = current.dotAll;
  var enable = true;
  for (var i = 0; i < spec.length; i++) {
    switch (spec[i]) {
      case '-':
        enable = false;
      case '+':
        enable = true;
      case 'i' || 'I':
        ignoreCase = enable;
      case 'm' || 'M':
        multiLine = enable;
      case 's' || 'S':
        dotAll = enable;
    }
  }
  return (ignoreCase: ignoreCase, multiLine: multiLine, dotAll: dotAll);
}

bool _isAsciiLower(int rune) => rune >= 0x61 && rune <= 0x7A;
bool _isAsciiUpper(int rune) => rune >= 0x41 && rune <= 0x5A;
bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;
bool _isSurrogate(int rune) => rune >= 0xD800 && rune <= 0xDFFF;

({int rune, int nextIndex})? _readRawRune(String input, int index) {
  if (index >= input.length) return null;
  final first = input.codeUnitAt(index);
  if ((first & 0xFC00) == 0xD800) {
    if (index + 1 >= input.length) return null;
    final second = input.codeUnitAt(index + 1);
    if ((second & 0xFC00) != 0xDC00) return null;
    final rune = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
    return (rune: rune, nextIndex: index + 2);
  }
  if ((first & 0xFC00) == 0xDC00) return null;
  return (rune: first, nextIndex: index + 1);
}

bool _isWordRune(int rune) {
  if (_isAsciiLower(rune) ||
      _isAsciiUpper(rune) ||
      _isAsciiDigit(rune) ||
      rune == 0x5F ||
      _runeInRanges(_goCaseTables.wordRanges, rune)) {
    return true;
  }
  final ch = String.fromCharCode(rune);
  return ch.toLowerCase() != ch.toUpperCase();
}

int? _parseHexDigits(String input) {
  if (input.isEmpty || input.length > 6) return null;
  var value = 0;
  for (var i = 0; i < input.length; i++) {
    final code = input.codeUnitAt(i);
    final digit = switch (code) {
      >= 0x30 && <= 0x39 => code - 0x30,
      >= 0x41 && <= 0x46 => code - 0x41 + 10,
      >= 0x61 && <= 0x66 => code - 0x61 + 10,
      _ => -1,
    };
    if (digit < 0) return null;
    value = (value * 16) + digit;
  }
  if (value > 0x10FFFF || _isSurrogate(value)) return null;
  return value;
}

({int rune, int nextIndex})? _readCharEscapeRune(
  String rawPattern,
  int backslashIndex, {
  required bool inCharClass,
}) {
  if (backslashIndex + 1 >= rawPattern.length) return null;
  final ch = rawPattern[backslashIndex + 1];
  switch (ch) {
    case 'a':
      return (rune: 0x07, nextIndex: backslashIndex + 2);
    case 'b' when inCharClass:
      return (rune: 0x08, nextIndex: backslashIndex + 2);
    case 'e':
      return (rune: 0x1B, nextIndex: backslashIndex + 2);
    case 'f':
      return (rune: 0x0C, nextIndex: backslashIndex + 2);
    case 'n':
      return (rune: 0x0A, nextIndex: backslashIndex + 2);
    case 'r':
      return (rune: 0x0D, nextIndex: backslashIndex + 2);
    case 't':
      return (rune: 0x09, nextIndex: backslashIndex + 2);
    case 'v':
      return (rune: 0x0B, nextIndex: backslashIndex + 2);
    case '0':
      if (backslashIndex + 2 < rawPattern.length) {
        final nextCode = rawPattern.codeUnitAt(backslashIndex + 2);
        if (nextCode >= 0x30 && nextCode <= 0x37) return null;
      }
      return (rune: 0x00, nextIndex: backslashIndex + 2);
    case 'x':
      if (backslashIndex + 2 < rawPattern.length &&
          rawPattern[backslashIndex + 2] == '{') {
        final close = rawPattern.indexOf('}', backslashIndex + 3);
        if (close == -1) return null;
        final parsed = _parseHexDigits(
          rawPattern.substring(backslashIndex + 3, close),
        );
        if (parsed == null) return null;
        return (rune: parsed, nextIndex: close + 1);
      }
      if (backslashIndex + 4 > rawPattern.length) return null;
      final parsed = _parseHexDigits(
        rawPattern.substring(backslashIndex + 2, backslashIndex + 4),
      );
      if (parsed == null) return null;
      return (rune: parsed, nextIndex: backslashIndex + 4);
    case 'u':
      if (backslashIndex + 6 > rawPattern.length) return null;
      final parsed = _parseHexDigits(
        rawPattern.substring(backslashIndex + 2, backslashIndex + 6),
      );
      if (parsed == null) return null;
      return (rune: parsed, nextIndex: backslashIndex + 6);
    default:
      final raw = _readRawRune(rawPattern, backslashIndex + 1);
      if (raw == null || _isWordRune(raw.rune)) return null;
      return raw;
  }
}

String _escapeOutsideRune(int rune) {
  if (rune < 0x20 || rune == 0x7F) {
    return r'\x' + rune.toRadixString(16).padLeft(2, '0');
  }
  if (rune > 0xFFFF) {
    return String.fromCharCode(rune);
  }
  final ch = String.fromCharCode(rune);
  if (r'\^$.|?*+()[]{}'.contains(ch)) {
    return '\\$ch';
  }
  return ch;
}

String _escapeCharClassRune(int rune) {
  if (rune < 0x20 || rune == 0x7F) {
    return r'\x' + rune.toRadixString(16).padLeft(2, '0');
  }
  if (rune > 0xFFFF) {
    return String.fromCharCode(rune);
  }
  final ch = String.fromCharCode(rune);
  if (r'\^-[]'.contains(ch)) {
    return '\\$ch';
  }
  return ch;
}

sealed class _ClassToken {
  const _ClassToken();
}

class _ClassChar extends _ClassToken {
  const _ClassChar(this.rune, {this.escapedDash = false});
  final int rune;
  final bool escapedDash;
}

class _ClassShorthand extends _ClassToken {
  const _ClassShorthand(this.expansion, {this.negated = false});
  final String expansion;
  final bool negated;
}

({
  _ClassToken token,
  int nextIndex,
})? _readClassToken(String rawPattern, int index) {
  if (index >= rawPattern.length) return null;
  final ch = rawPattern[index];
  if (ch == '[') {
    // Reject .NET character class subtraction ([a-z-[b]]) and nested classes.
    return null;
  }
  if (ch != r'\') {
    final raw = _readRawRune(rawPattern, index);
    if (raw == null) return null;
    return (token: _ClassChar(raw.rune), nextIndex: raw.nextIndex);
  }
  if (index + 1 >= rawPattern.length) return null;
  final next = rawPattern[index + 1];
  switch (next) {
    case 'w':
      return (
        token: _ClassShorthand(_goCaseTables.wordChars),
        nextIndex: index + 2,
      );
    case 'd':
      return (
        token: _ClassShorthand(_goCaseTables.digitChars),
        nextIndex: index + 2,
      );
    case 'D':
      return (
        token: _ClassShorthand(_goCaseTables.nonDigitChars, negated: true),
        nextIndex: index + 2,
      );
    case 's':
      return (
        token: const _ClassShorthand(_regexp2SpaceChars),
        nextIndex: index + 2,
      );
    case 'W' || 'S':
      // Negated multi-range shorthands inside [...] fail closed.
      return null;
    default:
      final escaped = _readCharEscapeRune(rawPattern, index, inCharClass: true);
      if (escaped == null) return null;
      return (
        token: _ClassChar(escaped.rune, escapedDash: next == '-'),
        nextIndex: escaped.nextIndex,
      );
  }
}

// Go 15.0.0 unicode.Nd (64 ranges, delta-encoded as [gapFromPrevHi, lengthMinus1, ...]).
const _goDigitRangeDeltas = <int>[
  48, 9, 1575, 9, 135, 9, 199, 9, 413, 9, 119, 9,
  119, 9, 119, 9, 119, 9, 119, 9, 119, 9, 119, 9,
  119, 9, 119, 9, 97, 9, 119, 9, 71, 9, 279, 9,
  71, 9, 1863, 9, 39, 9, 301, 9, 129, 9, 167, 9,
  7, 9, 183, 9, 87, 9, 135, 9, 7, 9, 35271, 9,
  679, 9, 39, 9, 199, 9, 23, 9, 87, 9, 407, 9,
  21271, 9, 1415, 9, 2183, 9, 813, 9, 129, 9, 61, 9,
  145, 9, 279, 9, 343, 9, 119, 9, 375, 9, 103, 9,
  103, 9, 423, 9, 103, 9, 759, 9, 247, 9, 71, 9,
  423, 9, 19207, 9, 87, 9, 135, 9, 27765, 49, 2369, 9,
  423, 9, 503, 9, 1111, 9, 4759, 9,
];

// Go 15.0.0 regexp2 word class (L, Mn, Nd, Pc, U+200C, U+200D; 869 ranges).
const _goWordRangeDeltas = <int>[
  48, 9, 8, 25, 5, 0, 2, 25, 48, 0, 11, 0,
  5, 0, 6, 22, 2, 30, 2, 457, 5, 11, 15, 4,
  8, 0, 2, 0, 18, 116, 2, 1, 3, 3, 2, 0,
  7, 0, 2, 2, 2, 0, 2, 19, 2, 82, 2, 138,
  2, 4, 3, 165, 2, 37, 3, 0, 7, 40, 9, 44,
  2, 0, 2, 1, 2, 1, 2, 0, 9, 26, 5, 3,
  30, 10, 6, 73, 5, 101, 2, 7, 3, 9, 2, 18,
  3, 0, 17, 58, 3, 100, 15, 53, 5, 0, 3, 0,
  3, 45, 19, 27, 5, 10, 6, 23, 2, 5, 10, 73,
  2, 31, 2, 54, 2, 1, 4, 7, 5, 0, 3, 19,
  3, 9, 2, 16, 4, 7, 3, 1, 3, 21, 2, 6,
  2, 0, 4, 3, 3, 1, 4, 3, 9, 1, 14, 1,
  2, 4, 3, 11, 11, 0, 2, 0, 3, 1, 3, 5,
  5, 1, 3, 21, 2, 6, 2, 1, 2, 1, 2, 1,
  3, 0, 5, 1, 5, 1, 3, 2, 4, 0, 8, 3,
  2, 0, 8, 15, 12, 1, 3, 8, 2, 2, 2, 21,
  2, 6, 2, 1, 2, 4, 3, 1, 4, 4, 2, 1,
  5, 0, 3, 0, 16, 3, 3, 9, 10, 6, 2, 0,
  4, 7, 3, 1, 3, 21, 2, 6, 2, 1, 2, 4,
  3, 1, 2, 0, 2, 3, 9, 0, 8, 1, 6, 1,
  2, 4, 3, 9, 2, 0, 17, 1, 2, 5, 4, 2,
  2, 3, 4, 1, 2, 0, 2, 1, 4, 1, 4, 2,
  4, 11, 7, 0, 13, 0, 3, 0, 22, 9, 17, 0,
  4, 8, 2, 2, 2, 22, 2, 15, 3, 4, 6, 2,
  2, 3, 8, 1, 2, 2, 3, 0, 3, 3, 3, 9,
  17, 1, 4, 7, 2, 2, 2, 22, 2, 9, 2, 4,
  3, 1, 2, 0, 7, 0, 6, 1, 16, 1, 2, 3,
  3, 9, 2, 1, 14, 1, 3, 8, 2, 2, 2, 43,
  4, 3, 9, 1, 6, 2, 9, 4, 3, 9, 11, 5,
  2, 0, 4, 17, 4, 23, 2, 8, 2, 0, 3, 6,
  4, 0, 8, 2, 2, 0, 16, 9, 18, 57, 6, 14,
  2, 9, 40, 1, 2, 0, 2, 4, 2, 23, 2, 0,
  2, 22, 3, 4, 2, 0, 2, 6, 2, 9, 3, 3,
  33, 0, 24, 1, 7, 9, 12, 0, 2, 0, 2, 0,
  7, 7, 2, 35, 5, 13, 2, 4, 2, 17, 2, 35,
  10, 0, 58, 42, 3, 3, 2, 5, 2, 1, 3, 12,
  7, 5, 3, 9, 4, 1, 8, 20, 3, 1, 7, 1,
  2, 9, 4, 0, 3, 37, 2, 0, 6, 0, 3, 42,
  2, 332, 2, 3, 3, 6, 2, 0, 2, 3, 3, 40,
  2, 3, 3, 32, 2, 3, 3, 6, 2, 0, 2, 3,
  3, 14, 2, 56, 2, 3, 3, 66, 3, 2, 33, 15,
  17, 85, 3, 5, 4, 619, 3, 16, 2, 25, 6, 74,
  7, 7, 8, 20, 11, 20, 13, 19, 13, 12, 2, 2,
  2, 1, 13, 53, 2, 6, 9, 0, 3, 10, 4, 0,
  5, 1, 3, 9, 34, 2, 2, 10, 7, 88, 8, 42,
  6, 69, 11, 30, 2, 2, 5, 1, 10, 0, 7, 2,
  11, 39, 3, 4, 12, 43, 5, 25, 7, 9, 39, 24,
  3, 0, 5, 52, 2, 0, 2, 6, 2, 0, 2, 0,
  3, 7, 7, 9, 3, 10, 7, 9, 14, 0, 9, 13,
  2, 15, 50, 3, 2, 47, 2, 4, 2, 0, 6, 0,
  3, 7, 4, 9, 18, 8, 13, 1, 2, 29, 2, 3,
  3, 1, 2, 59, 2, 1, 4, 0, 2, 2, 15, 35,
  9, 7, 3, 1, 9, 9, 4, 48, 3, 8, 8, 42,
  3, 2, 17, 2, 2, 12, 2, 20, 2, 2, 6, 533,
  3, 5, 3, 37, 3, 5, 3, 7, 2, 0, 2, 0,
  2, 0, 2, 30, 3, 52, 2, 6, 2, 0, 4, 2,
  2, 6, 4, 3, 3, 5, 5, 12, 6, 2, 2, 6,
  16, 1, 50, 1, 20, 0, 29, 0, 14, 0, 17, 12,
  52, 12, 5, 0, 4, 11, 18, 0, 5, 0, 3, 9,
  2, 0, 4, 4, 7, 0, 2, 0, 2, 0, 2, 3,
  2, 10, 3, 3, 6, 4, 5, 0, 53, 1, 2684, 228,
  7, 8, 13, 37, 2, 0, 6, 0, 3, 55, 8, 0,
  16, 23, 10, 6, 2, 6, 2, 6, 2, 6, 2, 6,
  2, 6, 2, 6, 2, 6, 2, 31, 48, 0, 470, 1,
  36, 3, 4, 4, 6, 1, 5, 85, 3, 1, 3, 2,
  2, 89, 2, 3, 6, 42, 2, 93, 18, 31, 49, 15,
  513, 6591, 65, 22156, 68, 45, 3, 268, 4, 27, 21, 47,
  5, 9, 2, 102, 11, 1, 38, 8, 3, 102, 3, 63,
  6, 1, 2, 0, 2, 4, 25, 48, 3, 1, 6, 0,
  20, 51, 15, 49, 17, 1, 11, 9, 7, 23, 4, 0,
  2, 48, 3, 33, 15, 28, 4, 2, 2, 47, 3, 3,
  3, 1, 18, 10, 7, 30, 2, 46, 3, 1, 3, 1,
  10, 12, 4, 9, 7, 22, 4, 0, 2, 0, 2, 68,
  25, 2, 3, 10, 2, 1, 5, 2, 2, 0, 11, 5,
  3, 5, 3, 5, 10, 6, 2, 6, 2, 42, 2, 13,
  7, 114, 3, 0, 3, 0, 5, 0, 3, 9, 7, 11171,
  13, 22, 5, 48, 8453, 365, 3, 105, 39, 6, 13, 4,
  6, 11, 2, 12, 2, 4, 2, 0, 2, 1, 2, 1,
  2, 107, 34, 362, 19, 63, 3, 53, 41, 11, 5, 15,
  17, 15, 4, 1, 25, 2, 33, 4, 2, 134, 20, 9,
  8, 25, 5, 0, 2, 25, 12, 88, 4, 5, 3, 5,
  3, 5, 3, 2, 36, 11, 2, 25, 2, 18, 2, 1,
  2, 14, 3, 13, 35, 122, 259, 0, 131, 28, 4, 48,
  16, 0, 32, 31, 14, 19, 2, 7, 7, 42, 6, 29,
  3, 35, 5, 7, 49, 157, 3, 9, 7, 35, 5, 35,
  5, 39, 9, 51, 13, 10, 2, 14, 2, 6, 2, 1,
  2, 10, 2, 14, 2, 6, 2, 1, 68, 310, 10, 21,
  11, 7, 25, 5, 2, 41, 2, 8, 70, 5, 3, 0,
  2, 43, 2, 1, 4, 0, 3, 22, 11, 22, 10, 30,
  66, 18, 2, 1, 11, 21, 11, 25, 71, 55, 7, 1,
  65, 3, 2, 1, 6, 7, 2, 2, 2, 28, 3, 2,
  5, 0, 33, 28, 4, 28, 36, 7, 2, 29, 26, 53,
  11, 21, 11, 18, 14, 17, 111, 72, 56, 50, 14, 50,
  14, 39, 9, 9, 327, 41, 2, 1, 4, 1, 76, 31,
  11, 0, 9, 32, 32, 21, 43, 20, 28, 22, 11, 0,
  2, 67, 32, 15, 10, 2, 2, 44, 4, 3, 3, 1,
  8, 0, 14, 24, 8, 9, 7, 43, 2, 7, 2, 9,
  5, 0, 3, 0, 9, 35, 3, 0, 10, 1, 2, 47,
  4, 8, 3, 3, 5, 3, 3, 11, 2, 0, 36, 17,
  2, 24, 4, 2, 3, 0, 2, 1, 7, 3, 63, 6,
  2, 0, 2, 3, 2, 14, 2, 9, 8, 47, 4, 7,
  6, 9, 7, 1, 4, 7, 3, 1, 3, 21, 2, 6,
  2, 1, 2, 4, 2, 2, 3, 0, 16, 0, 13, 4,
  5, 6, 4, 4, 140, 52, 4, 7, 3, 2, 2, 4,
  6, 9, 5, 3, 31, 47, 4, 5, 2, 0, 5, 1,
  2, 3, 2, 0, 9, 9, 167, 46, 4, 3, 7, 1,
  2, 1, 24, 5, 35, 47, 4, 7, 3, 0, 2, 1,
  4, 0, 12, 9, 39, 43, 2, 0, 3, 5, 2, 1,
  8, 9, 55, 26, 3, 2, 3, 3, 2, 4, 5, 9,
  7, 6, 186, 43, 4, 8, 2, 1, 102, 73, 22, 7,
  3, 0, 3, 7, 2, 1, 2, 23, 12, 1, 2, 1,
  2, 0, 2, 0, 13, 9, 71, 7, 3, 38, 4, 3,
  3, 1, 5, 1, 2, 0, 29, 56, 2, 4, 9, 0,
  9, 6, 3, 61, 2, 1, 4, 0, 19, 72, 264, 8,
  2, 36, 2, 6, 2, 5, 2, 1, 16, 9, 25, 29,
  3, 21, 3, 6, 2, 1, 2, 1, 74, 6, 2, 1,
  2, 43, 4, 0, 2, 1, 2, 8, 9, 9, 7, 5,
  2, 1, 2, 31, 7, 1, 4, 0, 2, 1, 8, 9,
  311, 20, 12, 2, 2, 12, 2, 33, 3, 4, 6, 0,
  2, 0, 14, 9, 87, 0, 80, 921, 231, 195, 2637, 96,
  16, 1071, 17, 21, 4011, 582, 8634, 568, 8, 30, 2, 9,
  7, 78, 2, 9, 7, 29, 3, 4, 12, 54, 10, 3,
  13, 9, 10, 20, 6, 18, 689, 63, 129, 74, 5, 1,
  63, 16, 65, 1, 2, 1, 28, 6135, 9, 1237, 43, 8,
  8936, 3, 2, 6, 2, 1, 2, 290, 16, 0, 30, 2,
  3, 0, 15, 3, 9, 395, 2309, 106, 6, 12, 4, 8,
  8, 9, 4, 1, 4706, 45, 3, 22, 545, 2, 18, 7,
  3, 6, 31, 3, 149, 2, 444, 84, 2, 70, 2, 1,
  3, 0, 3, 1, 3, 3, 2, 11, 2, 0, 2, 6,
  2, 64, 2, 3, 3, 7, 2, 6, 2, 27, 2, 3,
  2, 4, 2, 0, 4, 6, 2, 339, 3, 24, 2, 24,
  2, 30, 2, 24, 2, 30, 2, 24, 2, 30, 2, 24,
  2, 30, 2, 24, 2, 7, 3, 49, 513, 54, 5, 49,
  9, 0, 15, 0, 23, 4, 2, 14, 1105, 30, 7, 5,
  214, 6, 2, 16, 3, 6, 2, 1, 2, 4, 6, 61,
  34, 0, 113, 44, 4, 13, 3, 9, 5, 0, 322, 30,
  18, 57, 471, 41, 743, 6, 2, 3, 2, 1, 2, 14,
  2, 196, 12, 6, 42, 75, 5, 9, 1191, 3, 2, 26,
  2, 1, 2, 0, 3, 0, 2, 9, 2, 3, 2, 0,
  2, 0, 7, 0, 5, 0, 2, 0, 2, 0, 2, 2,
  2, 1, 2, 0, 3, 0, 2, 0, 2, 0, 2, 0,
  2, 0, 2, 1, 2, 0, 3, 3, 2, 6, 2, 3,
  2, 3, 2, 0, 2, 9, 2, 16, 6, 2, 2, 4,
  2, 16, 3381, 9, 1031, 42719, 33, 4153, 7, 221, 3, 5761,
  15, 7472, 3104, 541, 1507, 4938, 6, 4191, 712017, 239,
];

const _goToLowerSpans = <int>[
  0x41, 0x5A, 32, 1, 0xC0, 0xD6, 32, 1, 0xD8, 0xDE, 32, 1,
  0x100, 0x12E, 1, 2, 0x130, 0x130, -199, 1, 0x132, 0x136, 1, 2,
  0x139, 0x147, 1, 2, 0x14A, 0x176, 1, 2, 0x178, 0x178, -121, 1,
  0x179, 0x17D, 1, 2, 0x181, 0x181, 210, 1, 0x182, 0x184, 1, 2,
  0x186, 0x186, 206, 1, 0x187, 0x187, 1, 1, 0x189, 0x18A, 205, 1,
  0x18B, 0x18B, 1, 1, 0x18E, 0x18E, 79, 1, 0x18F, 0x18F, 202, 1,
  0x190, 0x190, 203, 1, 0x191, 0x191, 1, 1, 0x193, 0x193, 205, 1,
  0x194, 0x194, 207, 1, 0x196, 0x196, 211, 1, 0x197, 0x197, 209, 1,
  0x198, 0x198, 1, 1, 0x19C, 0x19C, 211, 1, 0x19D, 0x19D, 213, 1,
  0x19F, 0x19F, 214, 1, 0x1A0, 0x1A4, 1, 2, 0x1A6, 0x1A6, 218, 1,
  0x1A7, 0x1A7, 1, 1, 0x1A9, 0x1A9, 218, 1, 0x1AC, 0x1AC, 1, 1,
  0x1AE, 0x1AE, 218, 1, 0x1AF, 0x1AF, 1, 1, 0x1B1, 0x1B2, 217, 1,
  0x1B3, 0x1B5, 1, 2, 0x1B7, 0x1B7, 219, 1, 0x1B8, 0x1B8, 1, 1,
  0x1BC, 0x1BC, 1, 1, 0x1C4, 0x1C4, 2, 1, 0x1C5, 0x1C5, 1, 1,
  0x1C7, 0x1C7, 2, 1, 0x1C8, 0x1C8, 1, 1, 0x1CA, 0x1CA, 2, 1,
  0x1CB, 0x1DB, 1, 2, 0x1DE, 0x1EE, 1, 2, 0x1F1, 0x1F1, 2, 1,
  0x1F2, 0x1F4, 1, 2, 0x1F6, 0x1F6, -97, 1, 0x1F7, 0x1F7, -56, 1,
  0x1F8, 0x21E, 1, 2, 0x220, 0x220, -130, 1, 0x222, 0x232, 1, 2,
  0x23A, 0x23A, 10795, 1, 0x23B, 0x23B, 1, 1, 0x23D, 0x23D, -163, 1,
  0x23E, 0x23E, 10792, 1, 0x241, 0x241, 1, 1, 0x243, 0x243, -195, 1,
  0x244, 0x244, 69, 1, 0x245, 0x245, 71, 1, 0x246, 0x24E, 1, 2,
  0x370, 0x372, 1, 2, 0x376, 0x376, 1, 1, 0x37F, 0x37F, 116, 1,
  0x386, 0x386, 38, 1, 0x388, 0x38A, 37, 1, 0x38C, 0x38C, 64, 1,
  0x38E, 0x38F, 63, 1, 0x391, 0x3A1, 32, 1, 0x3A3, 0x3AB, 32, 1,
  0x3CF, 0x3CF, 8, 1, 0x3D8, 0x3EE, 1, 2, 0x3F4, 0x3F4, -60, 1,
  0x3F7, 0x3F7, 1, 1, 0x3F9, 0x3F9, -7, 1, 0x3FA, 0x3FA, 1, 1,
  0x3FD, 0x3FF, -130, 1, 0x400, 0x40F, 80, 1, 0x410, 0x42F, 32, 1,
  0x460, 0x480, 1, 2, 0x48A, 0x4BE, 1, 2, 0x4C0, 0x4C0, 15, 1,
  0x4C1, 0x4CD, 1, 2, 0x4D0, 0x52E, 1, 2, 0x531, 0x556, 48, 1,
  0x10A0, 0x10C5, 7264, 1, 0x10C7, 0x10C7, 7264, 1, 0x10CD, 0x10CD, 7264, 1,
  0x13A0, 0x13EF, 38864, 1, 0x13F0, 0x13F5, 8, 1, 0x1C90, 0x1CBA, -3008, 1,
  0x1CBD, 0x1CBF, -3008, 1, 0x1E00, 0x1E94, 1, 2, 0x1E9E, 0x1E9E, -7615, 1,
  0x1EA0, 0x1EFE, 1, 2, 0x1F08, 0x1F0F, -8, 1, 0x1F18, 0x1F1D, -8, 1,
  0x1F28, 0x1F2F, -8, 1, 0x1F38, 0x1F3F, -8, 1, 0x1F48, 0x1F4D, -8, 1,
  0x1F59, 0x1F5F, -8, 2, 0x1F68, 0x1F6F, -8, 1, 0x1F88, 0x1F8F, -8, 1,
  0x1F98, 0x1F9F, -8, 1, 0x1FA8, 0x1FAF, -8, 1, 0x1FB8, 0x1FB9, -8, 1,
  0x1FBA, 0x1FBB, -74, 1, 0x1FBC, 0x1FBC, -9, 1, 0x1FC8, 0x1FCB, -86, 1,
  0x1FCC, 0x1FCC, -9, 1, 0x1FD8, 0x1FD9, -8, 1, 0x1FDA, 0x1FDB, -100, 1,
  0x1FE8, 0x1FE9, -8, 1, 0x1FEA, 0x1FEB, -112, 1, 0x1FEC, 0x1FEC, -7, 1,
  0x1FF8, 0x1FF9, -128, 1, 0x1FFA, 0x1FFB, -126, 1, 0x1FFC, 0x1FFC, -9, 1,
  0x2126, 0x2126, -7517, 1, 0x212A, 0x212A, -8383, 1, 0x212B, 0x212B, -8262, 1,
  0x2132, 0x2132, 28, 1, 0x2160, 0x216F, 16, 1, 0x2183, 0x2183, 1, 1,
  0x24B6, 0x24CF, 26, 1, 0x2C00, 0x2C2F, 48, 1, 0x2C60, 0x2C60, 1, 1,
  0x2C62, 0x2C62, -10743, 1, 0x2C63, 0x2C63, -3814, 1, 0x2C64, 0x2C64, -10727, 1,
  0x2C67, 0x2C6B, 1, 2, 0x2C6D, 0x2C6D, -10780, 1, 0x2C6E, 0x2C6E, -10749, 1,
  0x2C6F, 0x2C6F, -10783, 1, 0x2C70, 0x2C70, -10782, 1, 0x2C72, 0x2C72, 1, 1,
  0x2C75, 0x2C75, 1, 1, 0x2C7E, 0x2C7F, -10815, 1, 0x2C80, 0x2CE2, 1, 2,
  0x2CEB, 0x2CED, 1, 2, 0x2CF2, 0x2CF2, 1, 1, 0xA640, 0xA66C, 1, 2,
  0xA680, 0xA69A, 1, 2, 0xA722, 0xA72E, 1, 2, 0xA732, 0xA76E, 1, 2,
  0xA779, 0xA77B, 1, 2, 0xA77D, 0xA77D, -35332, 1, 0xA77E, 0xA786, 1, 2,
  0xA78B, 0xA78B, 1, 1, 0xA78D, 0xA78D, -42280, 1, 0xA790, 0xA792, 1, 2,
  0xA796, 0xA7A8, 1, 2, 0xA7AA, 0xA7AA, -42308, 1, 0xA7AB, 0xA7AB, -42319, 1,
  0xA7AC, 0xA7AC, -42315, 1, 0xA7AD, 0xA7AD, -42305, 1, 0xA7AE, 0xA7AE, -42308, 1,
  0xA7B0, 0xA7B0, -42258, 1, 0xA7B1, 0xA7B1, -42282, 1, 0xA7B2, 0xA7B2, -42261, 1,
  0xA7B3, 0xA7B3, 928, 1, 0xA7B4, 0xA7C2, 1, 2, 0xA7C4, 0xA7C4, -48, 1,
  0xA7C5, 0xA7C5, -42307, 1, 0xA7C6, 0xA7C6, -35384, 1, 0xA7C7, 0xA7C9, 1, 2,
  0xA7D0, 0xA7D0, 1, 1, 0xA7D6, 0xA7D8, 1, 2, 0xA7F5, 0xA7F5, 1, 1,
  0xFF21, 0xFF3A, 32, 1, 0x10400, 0x10427, 40, 1, 0x104B0, 0x104D3, 40, 1,
  0x10570, 0x1057A, 39, 1, 0x1057C, 0x1058A, 39, 1, 0x1058C, 0x10592, 39, 1,
  0x10594, 0x10595, 39, 1, 0x10C80, 0x10CB2, 64, 1, 0x118A0, 0x118BF, 32, 1,
  0x16E40, 0x16E5F, 32, 1, 0x1E900, 0x1E921, 34, 1,
];

// Exact port of regexp2/syntax/charclass.go lcTable (op: 0=Set, 1=Add, 2=Bor, 3=Bad).
const _regexp2LcTable = <int>[
  0x0041, 0x005A, 1, 32, 0x00C0, 0x00DE, 1, 32, 0x0100, 0x012E, 2, 0,
  0x0130, 0x0130, 0, 0x0069, 0x0132, 0x0136, 2, 0, 0x0139, 0x0147, 3, 0,
  0x014A, 0x0176, 2, 0, 0x0178, 0x0178, 0, 0x00FF, 0x0179, 0x017D, 3, 0,
  0x0181, 0x0181, 0, 0x0253, 0x0182, 0x0184, 2, 0, 0x0186, 0x0186, 0, 0x0254,
  0x0187, 0x0187, 0, 0x0188, 0x0189, 0x018A, 1, 205, 0x018B, 0x018B, 0, 0x018C,
  0x018E, 0x018E, 0, 0x01DD, 0x018F, 0x018F, 0, 0x0259, 0x0190, 0x0190, 0, 0x025B,
  0x0191, 0x0191, 0, 0x0192, 0x0193, 0x0193, 0, 0x0260, 0x0194, 0x0194, 0, 0x0263,
  0x0196, 0x0196, 0, 0x0269, 0x0197, 0x0197, 0, 0x0268, 0x0198, 0x0198, 0, 0x0199,
  0x019C, 0x019C, 0, 0x026F, 0x019D, 0x019D, 0, 0x0272, 0x019F, 0x019F, 0, 0x0275,
  0x01A0, 0x01A4, 2, 0, 0x01A7, 0x01A7, 0, 0x01A8, 0x01A9, 0x01A9, 0, 0x0283,
  0x01AC, 0x01AC, 0, 0x01AD, 0x01AE, 0x01AE, 0, 0x0288, 0x01AF, 0x01AF, 0, 0x01B0,
  0x01B1, 0x01B2, 1, 217, 0x01B3, 0x01B5, 3, 0, 0x01B7, 0x01B7, 0, 0x0292,
  0x01B8, 0x01B8, 0, 0x01B9, 0x01BC, 0x01BC, 0, 0x01BD, 0x01C4, 0x01C5, 0, 0x01C6,
  0x01C7, 0x01C8, 0, 0x01C9, 0x01CA, 0x01CB, 0, 0x01CC, 0x01CD, 0x01DB, 3, 0,
  0x01DE, 0x01EE, 2, 0, 0x01F1, 0x01F2, 0, 0x01F3, 0x01F4, 0x01F4, 0, 0x01F5,
  0x01FA, 0x0216, 2, 0, 0x0386, 0x0386, 0, 0x03AC, 0x0388, 0x038A, 1, 37,
  0x038C, 0x038C, 0, 0x03CC, 0x038E, 0x038F, 1, 63, 0x0391, 0x03AB, 1, 32,
  0x03E2, 0x03EE, 2, 0, 0x0401, 0x040F, 1, 80, 0x0410, 0x042F, 1, 32,
  0x0460, 0x0480, 2, 0, 0x0490, 0x04BE, 2, 0, 0x04C1, 0x04C3, 3, 0,
  0x04C7, 0x04C7, 0, 0x04C8, 0x04CB, 0x04CB, 0, 0x04CC, 0x04D0, 0x04EA, 2, 0,
  0x04EE, 0x04F4, 2, 0, 0x04F8, 0x04F8, 0, 0x04F9, 0x0531, 0x0556, 1, 48,
  0x10A0, 0x10C5, 1, 48, 0x1E00, 0x1EF8, 2, 0, 0x1F08, 0x1F0F, 1, -8,
  0x1F18, 0x1F1F, 1, -8, 0x1F28, 0x1F2F, 1, -8, 0x1F38, 0x1F3F, 1, -8,
  0x1F48, 0x1F4D, 1, -8, 0x1F59, 0x1F59, 0, 0x1F51, 0x1F5B, 0x1F5B, 0, 0x1F53,
  0x1F5D, 0x1F5D, 0, 0x1F55, 0x1F5F, 0x1F5F, 0, 0x1F57, 0x1F68, 0x1F6F, 1, -8,
  0x1F88, 0x1F8F, 1, -8, 0x1F98, 0x1F9F, 1, -8, 0x1FA8, 0x1FAF, 1, -8,
  0x1FB8, 0x1FB9, 1, -8, 0x1FBA, 0x1FBB, 1, -74, 0x1FBC, 0x1FBC, 0, 0x1FB3,
  0x1FC8, 0x1FCB, 1, -86, 0x1FCC, 0x1FCC, 0, 0x1FC3, 0x1FD8, 0x1FD9, 1, -8,
  0x1FDA, 0x1FDB, 1, -100, 0x1FE8, 0x1FE9, 1, -8, 0x1FEA, 0x1FEB, 1, -112,
  0x1FEC, 0x1FEC, 0, 0x1FE5, 0x1FF8, 0x1FF9, 1, -128, 0x1FFA, 0x1FFB, 1, -126,
  0x1FFC, 0x1FFC, 0, 0x1FF3, 0x2160, 0x216F, 1, 16, 0x24B6, 0x24D0, 1, 26,
  0xFF21, 0xFF3A, 1, 32,
];

typedef _RuneRange = ({int first, int last});

List<_RuneRange> _decodeDeltaRanges(List<int> deltas) {
  final out = <_RuneRange>[];
  var prevHi = 0;
  for (var i = 0; i < deltas.length; i += 2) {
    final first = prevHi + deltas[i];
    final last = first + deltas[i + 1];
    out.add((first: first, last: last));
    prevHi = last;
  }
  return out;
}

List<_RuneRange> _negateRuneRanges(List<_RuneRange> ranges) {
  final out = <_RuneRange>[];
  for (final span in const <({int min, int max})>[
    (min: 0, max: 0xD7FF),
    (min: 0xE000, max: 0x10FFFF),
  ]) {
    var cursor = span.min;
    for (final r in ranges) {
      if (r.last < span.min) continue;
      if (r.first > span.max) break;
      final first = r.first < span.min ? span.min : r.first;
      final last = r.last > span.max ? span.max : r.last;
      if (first > cursor) {
        out.add((first: cursor, last: first - 1));
      }
      cursor = last + 1;
    }
    if (cursor <= span.max) {
      out.add((first: cursor, last: span.max));
    }
  }
  return out;
}

String _formatRuneRanges(List<_RuneRange> ranges) {
  final buffer = StringBuffer();
  for (final r in ranges) {
    if (r.first == r.last) {
      buffer.write(_escapeCharClassRune(r.first));
    } else if (r.first + 1 == r.last) {
      buffer
        ..write(_escapeCharClassRune(r.first))
        ..write(_escapeCharClassRune(r.last));
    } else {
      buffer
        ..write(_escapeCharClassRune(r.first))
        ..write('-')
        ..write(_escapeCharClassRune(r.last));
    }
  }
  return buffer.toString();
}

class _GoCaseTables {
  _GoCaseTables() {
    for (var i = 0; i < _goToLowerSpans.length; i += 4) {
      final lo = _goToLowerSpans[i];
      final hi = _goToLowerSpans[i + 1];
      final delta = _goToLowerSpans[i + 2];
      final stride = _goToLowerSpans[i + 3];
      for (var r = lo; r <= hi; r += stride) {
        final l = r + delta;
        upperToLower[r] = l;
        upperPairs.add((upper: r, lower: l));
        equivByLower.putIfAbsent(l, () => <int>[l]).add(r);
      }
    }
    for (final list in equivByLower.values) {
      list.sort();
    }
    digitRanges = _decodeDeltaRanges(_goDigitRangeDeltas);
    wordRanges = _decodeDeltaRanges(_goWordRangeDeltas);
    digitChars = _formatRuneRanges(digitRanges);
    nonDigitChars = _formatRuneRanges(_negateRuneRanges(digitRanges));
    wordChars = _formatRuneRanges(wordRanges);
    digitClass = '[$digitChars]';
    nonDigitClass = '[^$digitChars]';
    wordClass = '[$wordChars]';
    nonWordClass = '[^$wordChars]';
    wordBoundary =
        '(?:(?<=$wordClass)(?!$wordClass)|(?<!$wordClass)(?=$wordClass))';
    nonWordBoundary =
        '(?:(?<=$wordClass)(?=$wordClass)|(?<!$wordClass)(?!$wordClass))';
  }

  final upperToLower = <int, int>{};
  final upperPairs = <({int upper, int lower})>[];
  final equivByLower = <int, List<int>>{};
  late final List<_RuneRange> digitRanges;
  late final List<_RuneRange> wordRanges;
  late final String digitChars;
  late final String nonDigitChars;
  late final String wordChars;
  late final String digitClass;
  late final String nonDigitClass;
  late final String wordClass;
  late final String nonWordClass;
  late final String wordBoundary;
  late final String nonWordBoundary;

  int toLower(int rune) => upperToLower[rune] ?? rune;

  List<int>? equivClass(int rune) => equivByLower[toLower(rune)];
}

final _goCaseTables = _GoCaseTables();

void _canonicalizeRanges(List<_RuneRange> ranges) {
  if (ranges.length <= 1) return;
  ranges.sort((a, b) => a.first.compareTo(b.first));
  var write = 0;
  for (var read = 1; read < ranges.length; read++) {
    final current = ranges[write];
    final next = ranges[read];
    if (next.first <= current.last + 1) {
      if (next.last > current.last) {
        ranges[write] = (first: current.first, last: next.last);
      }
    } else {
      write++;
      ranges[write] = next;
    }
  }
  ranges.length = write + 1;
}

bool _runeInRanges(List<_RuneRange> ranges, int rune) {
  var lo = 0;
  var hi = ranges.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final r = ranges[mid];
    if (rune < r.first) {
      hi = mid - 1;
    } else if (rune > r.last) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

void _addRegexp2LowercaseRange(List<_RuneRange> ranges, int chMin, int chMax) {
  final count = _regexp2LcTable.length ~/ 4;
  var i = 0;
  var iMax = count;
  while (i < iMax) {
    final iMid = (i + iMax) >> 1;
    if (_regexp2LcTable[iMid * 4 + 1] < chMin) {
      i = iMid + 1;
    } else {
      iMax = iMid;
    }
  }
  for (; i < count; i++) {
    final base = i * 4;
    final lcMin = _regexp2LcTable[base];
    if (lcMin > chMax) return;
    final lcMax = _regexp2LcTable[base + 1];
    final op = _regexp2LcTable[base + 2];
    final data = _regexp2LcTable[base + 3];
    var chMinT = lcMin < chMin ? chMin : lcMin;
    var chMaxT = lcMax > chMax ? chMax : lcMax;
    switch (op) {
      case 0:
        chMinT = data;
        chMaxT = data;
      case 1:
        chMinT += data;
        chMaxT += data;
      case 2:
        chMinT |= 1;
        chMaxT |= 1;
      case 3:
        chMinT += (chMinT & 1);
        chMaxT += (chMaxT & 1);
    }
    if (chMinT < chMin || chMaxT > chMax) {
      ranges.add((first: chMinT, last: chMaxT));
      _canonicalizeRanges(ranges);
    }
  }
}

void _expandIgnoreCaseClassRanges(List<_RuneRange> ranges) {
  if (ranges.isEmpty) return;
  final toAdd = <_RuneRange>[];
  for (var i = 0; i < ranges.length; i++) {
    final r = ranges[i];
    if (r.first == r.last) {
      final lower = _goCaseTables.toLower(r.first);
      ranges[i] = (first: lower, last: lower);
    } else {
      toAdd.add(r);
    }
  }
  for (final r in toAdd) {
    _addRegexp2LowercaseRange(ranges, r.first, r.last);
  }
  _canonicalizeRanges(ranges);

  final toInclude = <_RuneRange>[];
  final toExclude = <int>[];
  for (final pair in _goCaseTables.upperPairs) {
    if (_runeInRanges(ranges, pair.lower)) {
      toInclude.add((first: pair.upper, last: pair.upper));
    } else if (_runeInRanges(ranges, pair.upper)) {
      toExclude.add(pair.upper);
    }
  }
  if (toExclude.isNotEmpty) {
    for (final ex in toExclude) {
      for (var i = 0; i < ranges.length; i++) {
        final r = ranges[i];
        if (ex < r.first || ex > r.last) continue;
        if (r.first == r.last) {
          ranges.removeAt(i);
        } else if (ex == r.first) {
          ranges[i] = (first: r.first + 1, last: r.last);
        } else if (ex == r.last) {
          ranges[i] = (first: r.first, last: r.last - 1);
        } else {
          ranges[i] = (first: r.first, last: ex - 1);
          ranges.insert(i + 1, (first: ex + 1, last: r.last));
        }
        break;
      }
    }
  }
  if (toInclude.isNotEmpty) {
    ranges.addAll(toInclude);
    _canonicalizeRanges(ranges);
  }
}

RegExp? _compileClashRegex(String rawPattern) {
  final buffer = StringBuffer();
  var flags = (ignoreCase: false, multiLine: false, dotAll: false);
  final groupStack = <_RegexFlags>[];

  void emitRuneOutsideClass(int rune) {
    if (flags.ignoreCase) {
      final equiv = _goCaseTables.equivClass(rune);
      if (equiv != null) {
        buffer.write('[');
        for (final r in equiv) {
          buffer.write(_escapeCharClassRune(r));
        }
        buffer.write(']');
        return;
      }
    }
    buffer.write(_escapeOutsideRune(rune));
  }

  var i = 0;
  while (i < rawPattern.length) {
    final ch = rawPattern[i];
    if (ch == r'\') {
      if (i + 1 >= rawPattern.length) {
        return null;
      }
      final next = rawPattern[i + 1];
      switch (next) {
        case 'A':
          buffer.write('^');
          i += 2;
          continue;
        case 'z':
          buffer.write(r'$');
          i += 2;
          continue;
        case 'Z':
          buffer.write(r'(?=\n?$)');
          i += 2;
          continue;
        case 'b':
          buffer.write(_goCaseTables.wordBoundary);
          i += 2;
          continue;
        case 'B':
          buffer.write(_goCaseTables.nonWordBoundary);
          i += 2;
          continue;
        case 'w':
          buffer.write(_goCaseTables.wordClass);
          i += 2;
          continue;
        case 'W':
          buffer.write(_goCaseTables.nonWordClass);
          i += 2;
          continue;
        case 'd':
          buffer.write(_goCaseTables.digitClass);
          i += 2;
          continue;
        case 'D':
          buffer.write(_goCaseTables.nonDigitClass);
          i += 2;
          continue;
        case 's':
          buffer.write(_regexp2SpaceClass);
          i += 2;
          continue;
        case 'S':
          buffer.write(_regexp2NonSpaceClass);
          i += 2;
          continue;
        default:
          final escaped = _readCharEscapeRune(
            rawPattern,
            i,
            inCharClass: false,
          );
          if (escaped == null) return null;
          emitRuneOutsideClass(escaped.rune);
          i = escaped.nextIndex;
          continue;
      }
    }

    if (ch == '[') {
      if (i + 1 < rawPattern.length && rawPattern[i + 1] == '^') {
        buffer.write('[^');
        i += 2;
      } else {
        buffer.write('[');
        i++;
      }
      var isFirstInClass = true;
      var closed = false;
      var hasNegatedShorthand = false;
      final classRanges = <_RuneRange>[];
      final classShorthands = <String>[];
      while (i < rawPattern.length) {
        if (rawPattern[i] == ']' && !isFirstInClass) {
          i++;
          closed = true;
          break;
        }
        final first = (rawPattern[i] == ']' && isFirstInClass)
            ? (token: const _ClassChar(0x5D), nextIndex: i + 1)
            : _readClassToken(rawPattern, i);
        if (first == null) return null;
        i = first.nextIndex;
        isFirstInClass = false;

        if (i < rawPattern.length && rawPattern[i] == '-') {
          if (i + 1 < rawPattern.length && rawPattern[i + 1] == '[') {
            return null;
          }
          if (i + 1 < rawPattern.length && rawPattern[i + 1] != ']') {
            if (first.token is! _ClassChar) return null;
            final firstChar = first.token as _ClassChar;
            if (firstChar.escapedDash) return null;
            i++;
            final second = _readClassToken(rawPattern, i);
            if (second == null || second.token is! _ClassChar) return null;
            final secondChar = second.token as _ClassChar;
            if (secondChar.escapedDash) return null;
            i = second.nextIndex;
            if (i + 1 < rawPattern.length &&
                rawPattern[i] == '-' &&
                rawPattern[i + 1] == '[') {
              return null;
            }
            final startRune = firstChar.rune;
            final endRune = secondChar.rune;
            if (startRune > endRune) return null;
            classRanges.add((first: startRune, last: endRune));
            _canonicalizeRanges(classRanges);
            continue;
          }
        }

        switch (first.token) {
          case _ClassShorthand(:final expansion, :final negated):
            if (negated) hasNegatedShorthand = true;
            classShorthands.add(expansion);
          case _ClassChar(:final rune):
            classRanges.add((first: rune, last: rune));
            _canonicalizeRanges(classRanges);
        }
      }
      if (!closed) return null;
      if (hasNegatedShorthand && classShorthands.length > 1) return null;
      if (flags.ignoreCase) {
        _expandIgnoreCaseClassRanges(classRanges);
      }
      buffer.write(_formatRuneRanges(classRanges));
      classShorthands.forEach(buffer.write);
      buffer.write(']');
      continue;
    }

    if (ch == '(') {
      final rest = rawPattern.substring(i);
      if (rest.startsWith('(?)')) {
        buffer.write('(?:)');
        i += 3;
        continue;
      }
      final flagOnly = _inlineFlagOnlyPattern.firstMatch(rest);
      if (flagOnly != null) {
        flags = _applyInlineFlags(flags, flagOnly.group(1)!);
        i += flagOnly.group(0)!.length;
        continue;
      }
      final flagGroup = _inlineFlagGroupPattern.firstMatch(rest);
      if (flagGroup != null) {
        groupStack.add(flags);
        flags = _applyInlineFlags(flags, flagGroup.group(1)!);
        buffer.write('(?:');
        i += flagGroup.group(0)!.length;
        continue;
      }
      if (rest.startsWith('(?:') ||
          rest.startsWith('(?=') ||
          rest.startsWith('(?!')) {
        groupStack.add(flags);
        buffer.write(rest.substring(0, 3));
        i += 3;
        continue;
      }
      if (rest.startsWith('(?<=') || rest.startsWith('(?<!')) {
        groupStack.add(flags);
        buffer.write(rest.substring(0, 4));
        i += 4;
        continue;
      }
      final namedGroup = _namedCaptureGroupPattern.firstMatch(rest);
      if (namedGroup != null) {
        final matched = namedGroup.group(0)!;
        groupStack.add(flags);
        buffer.write(matched);
        i += matched.length;
        continue;
      }
      if (rest.startsWith('(?')) {
        // Atomic groups (?>...), conditionals, balancing groups, comments, and
        // unsupported option flags fail closed to preserve Core semantics.
        return null;
      }
      groupStack.add(flags);
      buffer.write('(');
      i++;
      continue;
    }

    if (ch == ')') {
      if (groupStack.isEmpty) return null;
      flags = groupStack.removeLast();
      buffer.write(')');
      i++;
      continue;
    }

    if (ch == '^') {
      buffer.write(flags.multiLine ? r'(?:^|(?<=\n))' : '^');
      i++;
      continue;
    }

    if (ch == r'$') {
      buffer.write(flags.multiLine ? r'(?=\n|$)' : r'(?=\n?$)');
      i++;
      continue;
    }

    if (ch == '.') {
      buffer.write(flags.dotAll ? r'[\s\S]' : r'[^\n]');
      i++;
      continue;
    }

    if (ch == '|' || ch == '*' || ch == '+' || ch == '?') {
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == '{') {
      final quant = _quantifierBracePattern.firstMatch(rawPattern.substring(i));
      if (quant != null) {
        final token = quant.group(0)!;
        buffer.write(token);
        i += token.length;
      } else {
        buffer.write(r'\{');
        i++;
      }
      continue;
    }

    if (ch == '}' || ch == ']') {
      buffer.write('\\$ch');
      i++;
      continue;
    }

    final raw = _readRawRune(rawPattern, i);
    if (raw == null) return null;
    emitRuneOutsideClass(raw.rune);
    i = raw.nextIndex;
  }

  if (groupStack.isNotEmpty) return null;

  try {
    return RegExp(
      buffer.toString(),
      caseSensitive: true,
      multiLine: false,
      unicode: true,
    );
  } on FormatException {
    return null;
  }
}

typedef _ParsedGroupFilter = ({
  bool hasFilter,
  bool allValid,
  List<RegExp> regexes,
});

_ParsedGroupFilter _parseGroupFilter(Object? raw) {
  if (raw == null) {
    return (hasFilter: false, allValid: true, regexes: const []);
  }
  if (raw is! String) {
    return (hasFilter: true, allValid: false, regexes: const []);
  }
  if (raw.isEmpty) {
    return (hasFilter: false, allValid: true, regexes: const []);
  }
  final result = <RegExp>[];
  var allValid = true;
  for (final part in raw.split('`')) {
    final compiled = _compileClashRegex(part);
    if (compiled == null) {
      allValid = false;
    } else {
      result.add(compiled);
    }
  }
  return (hasFilter: true, allValid: allValid, regexes: result);
}

typedef _ParsedExcludeTypes = ({Set<String> types, bool valid});

_ParsedExcludeTypes _parseExcludeTypes(Object? raw) {
  if (raw == null) return (types: const {}, valid: true);
  if (raw is! String) return (types: const {}, valid: false);
  if (raw.trim().isEmpty) return (types: const {}, valid: true);
  final types = <String>{};
  for (final item in raw.split('|')) {
    final normalized = item.trim().toLowerCase();
    if (normalized.isEmpty) continue;
    types.add(normalized);
    final canonical = _canonicalAdapterType(normalized);
    if (canonical != null) {
      types.add(canonical);
    }
  }
  return (types: types, valid: true);
}

class _SelectGroupRule {
  const _SelectGroupRule({
    required this.name,
    required this.explicitProxies,
    required this.usedProviders,
    required this.includeAllProxies,
    required this.includeAllProviders,
    required this.filter,
    required this.excludeFilter,
    required this.excludeTypes,
  });

  final String name;
  final Set<String> explicitProxies;
  final Set<String> usedProviders;
  final bool includeAllProxies;
  final bool includeAllProviders;
  final _ParsedGroupFilter filter;
  final _ParsedGroupFilter excludeFilter;
  final _ParsedExcludeTypes excludeTypes;

  bool matches({
    required String name,
    required String? type,
    required CatalogNodeSource source,
    String? providerName,
  }) {
    if (!excludeTypes.valid || !excludeFilter.allValid || !filter.allValid) {
      return false;
    }
    final normalizedType = type?.trim().toLowerCase();
    final canonicalType = _canonicalAdapterType(normalizedType);
    if ((normalizedType != null &&
            normalizedType.isNotEmpty &&
            excludeTypes.types.contains(normalizedType)) ||
        (canonicalType != null && excludeTypes.types.contains(canonicalType))) {
      return false;
    }
    if (excludeFilter.regexes.any((reg) => reg.hasMatch(name))) {
      return false;
    }
    if (source == CatalogNodeSource.inline && explicitProxies.contains(name)) {
      return true;
    }
    final includedBySource = switch (source) {
      CatalogNodeSource.inline => includeAllProxies,
      CatalogNodeSource.provider => includeAllProviders ||
          (providerName != null && usedProviders.contains(providerName)),
    };
    if (!includedBySource) return false;
    if (!filter.hasFilter) return true;
    return filter.regexes.any((reg) => reg.hasMatch(name));
  }
}

class _SelectGroupIndex {
  _SelectGroupIndex(List? rawGroups) {
    for (final group in rawGroups ?? const []) {
      if (group is! Map) {
        throw const CatalogBuildException('parseFailed');
      }
      if (group['type'] != 'select') continue;
      final name = group['name'];
      final proxies = group['proxies'];
      if (name is! String || (proxies != null && proxies is! List)) {
        throw const CatalogBuildException('parseFailed');
      }
      final explicitProxies = <String>{};
      for (final proxyName in (proxies as List?) ?? const []) {
        if (proxyName is! String) {
          throw const CatalogBuildException('parseFailed');
        }
        explicitProxies.add(proxyName);
      }
      if (group['hidden'] == true) continue;
      final usedProviders = <String>{};
      if (group['use'] case final List<Object?> useList) {
        usedProviders.addAll(useList.whereType<String>());
      }
      final includeAll = group['include-all'] == true;
      _rules.add(_SelectGroupRule(
        name: name,
        explicitProxies: explicitProxies,
        usedProviders: usedProviders,
        includeAllProxies: includeAll || group['include-all-proxies'] == true,
        includeAllProviders:
            includeAll || group['include-all-providers'] == true,
        filter: _parseGroupFilter(group['filter']),
        excludeFilter: _parseGroupFilter(group['exclude-filter']),
        excludeTypes: _parseExcludeTypes(group['exclude-type']),
      ));
    }
  }

  final _rules = <_SelectGroupRule>[];

  List<String> forNode({
    required Object? name,
    Object? type,
    required CatalogNodeSource source,
    String? providerName,
  }) {
    if (name is! String) return const [];
    final typeName = type is String ? type : null;
    final result = <String>[];
    for (final rule in _rules) {
      if (!result.contains(rule.name) &&
          rule.matches(
            name: name,
            type: typeName,
            source: source,
            providerName: providerName,
          )) {
        result.add(rule.name);
      }
    }
    return result;
  }
}

/// Pure projection shared by file catalogs and the already-applied live config.
/// Provider definitions are not read: P0 only exposes their names as unknown.
/// [isolatedTest] applies P1 admission limits only to the file/display catalog.
/// Runtime identity verification and recording keep their existing semantics.
ProfileCatalog buildProfileCatalog({
  required String profileId,
  required String fingerprint,
  required Map<String, dynamic> raw,
  bool isolatedTest = false,
  int maxNodes = NodeCatalogService.maxProjectionNodes,
}) {
  final rawProxies = raw['proxies'];
  final rawGroups = raw['proxy-groups'];
  final rawProviders = raw['proxy-providers'];
  if ((rawProxies != null && rawProxies is! List) ||
      (rawGroups != null && rawGroups is! List) ||
      (rawProviders != null && rawProviders is! Map)) {
    throw const CatalogBuildException('parseFailed');
  }

  final selectGroups = _SelectGroupIndex(rawGroups as List?);

  final nodes = <CatalogNode>[];
  for (final (sourceIndex, proxy)
      in ((rawProxies as List?) ?? const []).indexed) {
    if (proxy is Map && _nonLeafTypes.contains(proxy['type'])) continue;
    if (nodes.length >= maxNodes) {
      throw const CatalogBuildException('tooManyNodes');
    }
    if (proxy is Map) {
      try {
        final node = catalogNodeFromMap(
          profileId: profileId,
          proxy: proxy,
          selectGroups: selectGroups.forNode(
            name: proxy['name'],
            type: proxy['type'],
            source: CatalogNodeSource.inline,
          ),
        );
        nodes.add(isolatedTest
            ? node.copyWith(
                unsupported: catalogIsolationUnsupportedReason(proxy))
            : node);
        continue;
      } on FormatException {
        // One unsupported shape must not hide the rest of this configuration.
        // Only approved display fields are allowed into its placeholder.
      }
    }
    final name = proxy is Map ? proxy['name'] : null;
    final type = proxy is Map ? proxy['type'] : null;
    nodes.add(unparsedCatalogNode(
      profileId: profileId,
      sourceIndex: sourceIndex,
      name: name is String ? name : null,
      type: type is String ? type : null,
    ));
  }

  final providers = <String, int>{};
  for (final name in (rawProviders as Map?)?.keys ?? const []) {
    if (name is! String) {
      throw const CatalogBuildException('parseFailed');
    }
    providers[name] = -1;
  }
  return ProfileCatalog(
    profileId: profileId,
    fingerprint: fingerprint,
    status: ProfileCatalogStatus.ready,
    nodes: List<CatalogNode>.unmodifiable(nodes),
    providerNodeCounts: Map<String, int>.unmodifiable(providers),
  );
}

/// Builds read-only summaries through the existing config/script pipeline.
/// Its dependencies deliberately offer no apply, download, or service actions.
class NodeCatalogService {
  NodeCatalogService({
    required this.readProfileConfig,
    required this.evaluate,
    required this.fileMetadata,
    required this.scriptFingerprint,
    this.prepareCatalog,
    this.releaseCatalog,
    this.providerCachePath,
    this.providerResolver,
    this.onError,
    this.onPrepared,
  });

  static const maxNodes = 2000;
  static const maxProjectionNodes = 100000;
  static const maxCachedCatalogs = 8;
  static const maxConcurrentBuilds = 2;

  final Future<Map<String, dynamic>> Function(String) readProfileConfig;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) evaluate;
  final Future<CatalogFileMetadata?> Function(String) fileMetadata;

  /// The current script id plus a hash of its content; never source text.
  final String Function() scriptFingerprint;
  final PrepareNodeCatalog? prepareCatalog;
  final CatalogProviderResolver? providerResolver;
  final Future<bool> Function(String catalogId)? releaseCatalog;
  final Future<String?> Function(String profileId, String providerName,
      Map<String, dynamic> definition)? providerCachePath;
  final void Function(String reason)? onError;
  final void Function(ProfileCatalog catalog)? onPrepared;

  final _cache = <String, ProfileCatalog>{};
  final _dirtyCache = <String>{};
  final _generations = <String, int>{};
  final _inFlight =
      <String, ({int generation, Future<ProfileCatalog> future})>{};
  final _waiting = Queue<Completer<void>>();
  var _activeBuilds = 0;
  final _prepared = <String, ProfileCatalog>{};
  final _preparing = <String, Future<ProfileCatalog>>{};
  final _allPlanProfiles = <String, int>{};
  final _allCatalogOwners = <String, void Function()>{};

  ProfileCatalog? peek(String profileId) => _cache[profileId];

  void invalidate(String profileId, {bool keepCached = false}) {
    _generations[profileId] = (_generations[profileId] ?? 0) + 1;
    _preparing.remove(profileId);
    final prepared = _prepared.remove(profileId);
    if (prepared?.coreCatalogId case final String id) {
      unawaited(_releaseCore(id));
    }
    if (keepCached && _cache.containsKey(profileId)) {
      _dirtyCache.add(profileId);
    } else {
      _cache.remove(profileId);
      _dirtyCache.remove(profileId);
    }
  }

  void clear() {
    <String>{
      ..._cache.keys,
      ..._inFlight.keys,
      ..._preparing.keys,
      ..._prepared.keys,
      ..._allPlanProfiles.keys
    }.forEach(invalidate);
  }

  /// Preparation is explicit and short lived. Raw credentials exist only in
  /// this call, never in a provider, display model or persistent health cache.
  /// Each batch prepares anew because Core can evict an idle catalog itself.
  Future<ProfileCatalog> ensurePrepared(Profile profile) {
    if (profile.isUpdating) {
      return Future.error(const CatalogBuildException('configChanged'));
    }
    final pending = _preparing[profile.id];
    if (pending != null) return pending;
    final generation = _generations[profile.id] ?? 0;
    late final Future<ProfileCatalog> future;
    future = _prepare(profile, generation).whenComplete(() {
      if (identical(_preparing[profile.id], future)) {
        _preparing.remove(profile.id);
      }
    });
    _preparing[profile.id] = future;
    return future;
  }

  Future<void> releasePrepared(String catalogId) async {
    _allCatalogOwners.remove(catalogId)?.call();
    _prepared.removeWhere((_, value) => value.coreCatalogId == catalogId);
    await _releaseCore(catalogId);
  }

  /// Revoke only the caller's still-pending preparation. A later view can
  /// immediately start a fresh generation without sharing the retired handle.
  void cancelPreparation(String profileId, Future<ProfileCatalog> expected) {
    if (!identical(_preparing[profileId], expected)) return;
    _generations[profileId] = (_generations[profileId] ?? 0) + 1;
    _preparing.remove(profileId);
  }

  Future<void> _releaseCore(String catalogId) async {
    try {
      if (await releaseCatalog?.call(catalogId) == false) {
        onError?.call('releaseFailed');
      }
    } catch (_) {
      onError?.call('releaseFailed');
    }
  }

  /// Explicit full-profile testing only. Display queries and single-node
  /// preparation never reach the resolver or initiate a provider download.
  Future<CatalogTestPlan> resolveForTestAll(Profile profile,
      {required bool Function() isCurrent}) async {
    final generation = _generations[profile.id] ?? 0;
    final metadata = await fileMetadata(profile.id);
    if (metadata == null) throw const CatalogBuildException('fileMissing');
    if (profile.isUpdating) throw const CatalogBuildException('updating');
    final script = scriptFingerprint();
    var disposed = false;
    bool current() =>
        !disposed && isCurrent() && _isCurrent(profile.id, generation);
    void check() {
      if (!current()) throw const CatalogBuildException('cancelled');
    }

    Future<void> verify() async {
      check();
      if (await fileMetadata(profile.id) != metadata ||
          scriptFingerprint() != script) {
        throw const CatalogBuildException('configChanged');
      }
      check();
    }

    final maps = <Map<String, dynamic>>[];
    final encodedNodeBytes = <int>[];
    var payloadBytes = 0;
    const maxProfilePayloadBytes = 32 * 1024 * 1024;
    final nodes = <CatalogNode>[];
    final issues = <CatalogProviderIssue>[];
    final providerCounts = <String, int>{};
    final held = <String>{};
    _allPlanProfiles[profile.id] = (_allPlanProfiles[profile.id] ?? 0) + 1;
    void dropPlan() {
      if (disposed) return;
      disposed = true;
      maps.clear();
      encodedNodeBytes.clear();
      final count = (_allPlanProfiles[profile.id] ?? 1) - 1;
      if (count <= 0) {
        _allPlanProfiles.remove(profile.id);
      } else {
        _allPlanProfiles[profile.id] = count;
      }
      for (final id in held.toList()) {
        unawaited(releasePrepared(id));
      }
      held.clear();
    }

    await _acquire();
    try {
      check();
      final raw = await evaluate(await readProfileConfig(profile.id));
      check();
      // Validate containers/groups without applying the per-Core 2000-node
      // ceiling to the complete profile; preparation partitions below.
      if (raw['proxies'] != null && raw['proxies'] is! List) {
        throw const CatalogBuildException('parseFailed');
      }
      buildProfileCatalog(
          profileId: profile.id,
          fingerprint: '',
          raw: {...raw, 'proxies': const []});
      final selectGroups = _SelectGroupIndex(raw['proxy-groups'] as List?);
      void append(Object? value, CatalogNodeSource source, String? provider) {
        if (value is Map && _nonLeafTypes.contains(value['type'])) return;
        if (nodes.length >= maxProjectionNodes) {
          issues.add(CatalogProviderIssue(
              providerName: provider, reason: 'tooManyNodes', count: 1));
          return;
        }
        Map<String, dynamic> map;
        try {
          map = value is Map ? Map<String, dynamic>.from(value) : {};
        } catch (_) {
          map = {};
        }
        final bytes = utf8.encode(jsonEncode(map)).length;
        // The inner JSON is itself a string in Action.data. Count both
        // encodings, including escaped credentials, before retaining a node.
        final frameBytes = utf8.encode(jsonEncode(jsonEncode(map))).length - 2;
        if (payloadBytes + bytes > maxProfilePayloadBytes ||
            frameBytes > 512 * 1024 - 1024) {
          issues.add(CatalogProviderIssue(
              providerName: provider, reason: 'providerTooLarge', count: 1));
          return;
        }
        CatalogNode node;
        try {
          node = catalogNodeFromMap(
                  profileId: profile.id,
                  proxy: map,
                  source: source,
                  providerName: provider,
                  selectGroups: selectGroups.forNode(
                      name: map['name'],
                      type: map['type'],
                      source: source,
                      providerName: provider))
              .copyWith(unsupported: catalogIsolationUnsupportedReason(map));
        } on FormatException {
          node = unparsedCatalogNode(
              profileId: profile.id,
              sourceIndex: nodes.length,
              source: source,
              providerName: provider,
              name: map['name'] is String ? map['name'] as String : null,
              type: map['type'] is String ? map['type'] as String : null);
        }
        maps.add(map);
        encodedNodeBytes.add(frameBytes);
        payloadBytes += bytes;
        nodes.add(node);
      }

      for (final rawNode in (raw['proxies'] as List?) ?? const []) {
        append(rawNode, CatalogNodeSource.inline, null);
      }
      for (final entry
          in ((raw['proxy-providers'] as Map?) ?? const {}).entries) {
        check();
        final name = entry.key as String;
        if (entry.value is! Map || providerResolver == null) {
          issues.add(CatalogProviderIssue(
              providerName: name,
              reason: entry.value is Map
                  ? 'providerOptionsUnsupported'
                  : 'parseFailed'));
          providerCounts[name] = -1;
          continue;
        }
        final resolved = await providerResolver!.resolve(
            profile.id, name, Map<String, dynamic>.from(entry.value as Map),
            isCurrent: current);
        check();
        issues.addAll(resolved.issues);
        final sourceBytes = resolved.proxies.fold<int>(
            0, (sum, value) => sum + utf8.encode(jsonEncode(value)).length);
        if (payloadBytes + sourceBytes > maxProfilePayloadBytes) {
          issues.add(CatalogProviderIssue(
              providerName: name,
              reason: 'providerTooLarge',
              count: resolved.proxies.length));
          providerCounts[name] = -1;
          continue;
        }
        final before = nodes.length;
        for (final proxy in resolved.proxies) {
          append(proxy, CatalogNodeSource.provider, name);
        }
        providerCounts[name] = nodes.length - before;
      }
      await verify();
      final fingerprint = '${metadata.modifiedMicros}|${metadata.size}|$script';
      final display = ProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          status: ProfileCatalogStatus.ready,
          nodes: List.unmodifiable(nodes),
          providerNodeCounts: Map.unmodifiable(providerCounts));
      _cache.remove(profile.id);
      _cache[profile.id] = display;
      _dirtyCache.remove(profile.id);
      while (_cache.length > maxCachedCatalogs) {
        _cache.remove(_cache.keys.first);
      }
      onPrepared?.call(display);
      final chunks = <({int start, int end})>[];
      var start = 0;
      var frameBytes = 1024; // Fixed Action/catalog metadata is under 1 KiB.
      for (var i = 0; i < nodes.length; i++) {
        if (i - start >= maxNodes ||
            frameBytes + encodedNodeBytes[i] + 1 > 512 * 1024) {
          chunks.add((start: start, end: i));
          start = i;
          frameBytes = 1024;
        }
        frameBytes += encodedNodeBytes[i] + 1;
      }
      if (start < nodes.length) chunks.add((start: start, end: nodes.length));
      return CatalogTestPlan(
          nodes: nodes,
          providerIssues: issues,
          chunkCount: chunks.length,
          onDispose: dropPlan,
          prepare: (index) async {
            await verify();
            final prepare = prepareCatalog;
            if (prepare == null || releaseCatalog == null) {
              throw const CatalogBuildException('runtimeUnavailable');
            }
            final start = chunks[index].start;
            final end = chunks[index].end;
            final selected = List<CatalogNode>.from(nodes.sublist(start, end));
            final payload = maps.sublist(start, end);
            final random = Random.secure();
            final id =
                'c-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
            try {
              final response = jsonDecode(await prepare(id, payload, const []));
              await verify();
              if (response is! Map ||
                  response['catalog-id'] != id ||
                  response['nodes'] is! List ||
                  (response['nodes'] as List).length != selected.length) {
                throw const CatalogBuildException('invalidResponse');
              }
              final seen = <int>{};
              for (final row in response['nodes'] as List) {
                if (row is! Map ||
                    row['index'] is! int ||
                    row['supported'] is! bool) {
                  throw const CatalogBuildException('invalidResponse');
                }
                final i = row['index'] as int;
                if (i < 0 || i >= selected.length || !seen.add(i)) {
                  throw const CatalogBuildException('invalidResponse');
                }
                final node = selected[i];
                final supported = row['supported'] == true &&
                    node.unsupported == CatalogUnsupportedReason.none;
                selected[i] = node.copyWith(
                    coreIndex: supported ? i : null,
                    unsupported: supported
                        ? CatalogUnsupportedReason.none
                        : node.unsupported != CatalogUnsupportedReason.none
                            ? node.unsupported
                            : switch (row['reason']) {
                                'chainUnsupported' =>
                                  CatalogUnsupportedReason.chainUnsupported,
                                'typeUnsupported' =>
                                  CatalogUnsupportedReason.typeUnsupported,
                                'strictModeUnsupported' =>
                                  CatalogUnsupportedReason
                                      .strictModeUnsupported,
                                _ => CatalogUnsupportedReason.parseFailed,
                              });
              }
              await verify();
              held.add(id);
              _allCatalogOwners[id] = () => held.remove(id);
              return display.copyWith(nodes: selected, coreCatalogId: id);
            } on CatalogBuildException {
              held.remove(id);
              await _releaseCore(id);
              rethrow;
            } catch (_) {
              held.remove(id);
              await _releaseCore(id);
              throw const CatalogBuildException('prepareFailed');
            }
          });
    } on CatalogBuildException {
      dropPlan();
      rethrow;
    } catch (_) {
      dropPlan();
      throw const CatalogBuildException('parseFailed');
    } finally {
      _release();
    }
  }

  Future<ProfileCatalog> _prepare(Profile profile, int generation) async {
    final prepare = prepareCatalog;
    if (prepare == null || releaseCatalog == null) {
      throw const CatalogBuildException('runtimeUnavailable');
    }
    final random = Random.secure();
    final id =
        'c-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    var sent = false;
    await _acquire();
    try {
      final metadata = await fileMetadata(profile.id);
      if (metadata == null) {
        throw const CatalogBuildException('fileMissing');
      }
      final script = scriptFingerprint();
      final raw = await evaluate(await readProfileConfig(profile.id));
      final fingerprint = '${metadata.modifiedMicros}|${metadata.size}|$script';
      final catalog = buildProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          raw: raw,
          isolatedTest: true,
          maxNodes: maxNodes);
      final proxies = <Map<String, dynamic>>[];
      for (final proxy in (raw['proxies'] as List?) ?? const []) {
        if (proxy is Map && _nonLeafTypes.contains(proxy['type'])) continue;
        proxies.add(proxy is Map ? Map<String, dynamic>.from(proxy) : {});
      }
      final providers = <Map<String, dynamic>>[];
      for (final entry in ((raw['proxy-providers'] as Map?) ?? {}).entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final path = await providerCachePath?.call(profile.id,
            entry.key as String, Map<String, dynamic>.from(entry.value as Map));
        if (path != null) providers.add({'name': entry.key, 'path': path});
      }
      // A file/script change during evaluation must not be tested under the
      // previous display identity or survive subscription deletion.
      Future<void> verifyCurrent() async {
        final currentMetadata = await fileMetadata(profile.id);
        if (!_isCurrent(profile.id, generation) ||
            currentMetadata != metadata ||
            scriptFingerprint() != script) {
          throw const CatalogBuildException('configChanged');
        }
      }

      await verifyCurrent();
      final previous = _prepared.remove(profile.id);
      if (previous?.coreCatalogId case final String oldId) {
        await _releaseCore(oldId);
      }
      while (_prepared.length >= 3) {
        final oldest = _prepared.remove(_prepared.keys.first)!;
        await _releaseCore(oldest.coreCatalogId!);
      }
      sent = true;
      final encoded = await prepare(id, proxies, providers);
      final response = jsonDecode(encoded);
      if (response is! Map ||
          response['catalog-id'] != id ||
          response['nodes'] is! List) {
        throw const CatalogBuildException('invalidResponse');
      }
      final nodes = List<CatalogNode>.of(catalog.nodes);
      final rows = response['nodes'] as List;
      if (rows.length != nodes.length) {
        throw const CatalogBuildException('invalidResponse');
      }
      final seen = <int>{};
      for (final row in rows) {
        if (row is! Map || row['index'] is! int || row['supported'] is! bool) {
          throw const CatalogBuildException('invalidResponse');
        }
        final index = row['index'] as int;
        if (index < 0 || index >= nodes.length || !seen.add(index)) {
          throw const CatalogBuildException('invalidResponse');
        }
        final node = nodes[index];
        // Malformed placeholders have no endpoint identity and are never
        // eligible for a measurement even if a remote response says otherwise.
        final reason = switch (row['reason']) {
          'chainUnsupported' => CatalogUnsupportedReason.chainUnsupported,
          'typeUnsupported' => CatalogUnsupportedReason.typeUnsupported,
          'strictModeUnsupported' =>
            CatalogUnsupportedReason.strictModeUnsupported,
          _ => CatalogUnsupportedReason.parseFailed,
        };
        final supported = row['supported'] == true &&
            node.unsupported == CatalogUnsupportedReason.none;
        nodes[index] = node.copyWith(
            coreIndex: supported ? index : null,
            unsupported: supported
                ? CatalogUnsupportedReason.none
                : node.unsupported != CatalogUnsupportedReason.none
                    ? node.unsupported
                    : reason);
      }
      await verifyCurrent();
      final prepared = catalog.copyWith(coreCatalogId: id, nodes: nodes);
      _prepared[profile.id] = prepared;
      // Preserve newly discovered unsupported rows in the display cache. Core
      // handles and indices remain private to this short-lived preparation.
      final display = prepared.copyWith(coreCatalogId: null, nodes: [
        for (final node in nodes) node.copyWith(coreIndex: null),
      ]);
      _cache[profile.id] = display;
      _dirtyCache.remove(profile.id);
      while (_cache.length > maxCachedCatalogs) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest);
        _dirtyCache.remove(oldest);
      }
      onPrepared?.call(display);
      return prepared;
    } on CatalogBuildException {
      if (sent) await _releaseCore(id);
      rethrow;
    } catch (_) {
      if (sent) await _releaseCore(id);
      throw const CatalogBuildException('prepareFailed');
    } finally {
      _release();
    }
  }

  Future<ProfileCatalog> load(Profile profile) {
    final generation = _generations[profile.id] ?? 0;
    final pending = _inFlight[profile.id];
    if (pending != null && pending.generation == generation) {
      return pending.future;
    }
    late final Future<ProfileCatalog> future;
    future = _load(profile, generation).whenComplete(() {
      if (identical(_inFlight[profile.id]?.future, future)) {
        _inFlight.remove(profile.id);
      }
    });
    _inFlight[profile.id] = (generation: generation, future: future);
    return future;
  }

  Future<ProfileCatalog> _load(Profile profile, int generation) async {
    var fingerprint = '';
    try {
      final metadata = await fileMetadata(profile.id);
      if (metadata == null) {
        if (_isCurrent(profile.id, generation)) _cache.remove(profile.id);
        return ProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          status: ProfileCatalogStatus.fileMissing,
        );
      }
      final cached = _cache[profile.id];
      if (profile.isUpdating) {
        return (cached ??
                ProfileCatalog(
                  profileId: profile.id,
                  fingerprint: fingerprint,
                  status: ProfileCatalogStatus.updating,
                ))
            .copyWith(status: ProfileCatalogStatus.updating);
      }
      fingerprint =
          '${metadata.modifiedMicros}|${metadata.size}|${scriptFingerprint()}';
      if (cached?.fingerprint == fingerprint &&
          !_dirtyCache.contains(profile.id)) {
        _cache
          ..remove(profile.id)
          ..[profile.id] = cached!;
        return cached;
      }

      await _acquire();
      try {
        final raw = await readProfileConfig(profile.id);
        final evaluated = await evaluate(raw);
        final catalog = buildProfileCatalog(
          profileId: profile.id,
          fingerprint: fingerprint,
          raw: evaluated,
          isolatedTest: true,
        );
        if (_isCurrent(profile.id, generation)) {
          _dirtyCache.remove(profile.id);
          _cache
            ..remove(profile.id)
            ..[profile.id] = catalog;
          if (_cache.length > maxCachedCatalogs) {
            final oldest = _cache.keys.first;
            _cache.remove(oldest);
            _dirtyCache.remove(oldest);
          }
        }
        return catalog;
      } finally {
        _release();
      }
    } catch (error) {
      if (_isCurrent(profile.id, generation)) _cache.remove(profile.id);
      return ProfileCatalog(
        profileId: profile.id,
        fingerprint: fingerprint,
        status: ProfileCatalogStatus.parseFailed,
        // Even a URL-stripped exception can contain servers or credentials.
        errorSummary:
            error is CatalogBuildException && error.reason == 'tooManyNodes'
                ? 'tooManyNodes'
                : 'parseFailed',
      );
    }
  }

  bool _isCurrent(String id, int generation) =>
      (_generations[id] ?? 0) == generation;

  Future<void> _acquire() async {
    if (_activeBuilds < maxConcurrentBuilds) {
      _activeBuilds++;
      return;
    }
    final ready = Completer<void>();
    _waiting.add(ready);
    await ready.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _activeBuilds--;
    } else {
      _waiting.removeFirst().complete();
    }
  }
}
