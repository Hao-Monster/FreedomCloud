import 'dart:io';

import 'print.dart';

final RegExp _correlationIdPattern = RegExp(r'^[0-9a-zA-Z_-]{1,64}$');
String? _startupTimingCorrelationId;
// Diagnostic label only; the Agent instance ID still comes from the handshake.
final String startupTimingUiRunId = '${pid}_${DateTime.now().microsecondsSinceEpoch}';

String? get startupTimingCorrelationId => _startupTimingCorrelationId;

void _writeTiming(String fields) {
  try {
    commonPrint.log('[startup-timing] $fields');
  } catch (_) {
    // The log sink can be unavailable during startup or shutdown.
    // A diagnostic failure must not escape into the operation being timed.
  }
}

void setStartupTimingCorrelationId(String? value) {
  final trimmed = value?.trim();
  final previous = _startupTimingCorrelationId;
  _startupTimingCorrelationId =
      trimmed != null && _correlationIdPattern.hasMatch(trimmed)
          ? trimmed
          : null;
  if (_startupTimingCorrelationId != null && _startupTimingCorrelationId != previous) {
    _writeTiming('event=correlation_bind uiRunId=$startupTimingUiRunId correlationId=$_startupTimingCorrelationId');
  }
}

/// Emits a bounded, credential-free duration record for the startup path.
///
/// Keep the format stable so a cold-start log can be grouped by `stage` and
/// compared across UI/Core/Helper components.
void logStartupTiming(
  String stage,
  Stopwatch watch, {
  String? outcome,
  int? attempt,
  int? corePid,
  int? tunAttempt,
  String? detail,
}) {
  final correlationId = _startupTimingCorrelationId;
  final fields = <String>[
    'uiRunId=$startupTimingUiRunId',
    'stage=$stage',
    'elapsedMs=${watch.elapsedMilliseconds}',
    if (outcome != null) 'outcome=$outcome',
    if (attempt != null) 'attempt=$attempt',
    if (corePid != null) 'corePid=$corePid',
    if (tunAttempt != null) 'tunAttempt=$tunAttempt',
    if (detail != null && detail.isNotEmpty) 'detail=$detail',
    if (correlationId != null) 'correlationId=$correlationId',
  ];
  _writeTiming(fields.join(' '));
}
