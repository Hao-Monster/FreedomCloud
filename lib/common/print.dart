import 'package:flclashx/common/file_logger.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/cupertino.dart';

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
/// application log sink.  Log files are routinely exported for diagnostics,
/// so redaction belongs at the shared logger boundary rather than at individual
/// call sites.  Loopback URLs are intentionally redacted too: they can carry
/// controller secrets in query strings.
String redactSensitiveLogData(String? text) {
  if (text == null || text.isEmpty) return text ?? '';

  var redacted = text.replaceAllMapped(_logUrlPattern, (_) => '<redacted-url>');
  // Remove scheme credentials first so the generic field matcher cannot leave
  // the token following `Bearer`/`Basic` in the log.
  redacted = redacted.replaceAllMapped(
    _logBearerPattern,
    (_) => '<redacted-authorization>',
  );
  redacted = redacted.replaceAllMapped(
    _logCredentialPattern,
    (match) => '${match.group(1)}<redacted>',
  );
  return redacted;
}

class CommonPrint {

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  CommonPrint._internal();
  static CommonPrint? _instance;

  static const _levelPriority = {
    LogLevel.debug: 0,
    LogLevel.info: 1,
    LogLevel.warning: 2,
    LogLevel.error: 3,
    LogLevel.silent: 4,
    LogLevel.app: 0,
  };

  void log(String? text) {
    final payload = '[FlClashX] ${redactSensitiveLogData(text)}';
    debugPrint(payload);

    fileLogger.log(payload);

    if (!globalState.isInit) {
      return;
    }
    final configuredLevel = globalState.effectiveLogLevel.value;
    final threshold = LogLevel.values.where(
      (l) => l.name == configuredLevel,
    ).firstOrNull;
    if (threshold != null &&
        (_levelPriority[LogLevel.app] ?? 0) < (_levelPriority[threshold] ?? 0)) {
      return;
    }
    globalState.appController.addLog(
      Log.app(payload),
    );
  }
}

final commonPrint = CommonPrint();
