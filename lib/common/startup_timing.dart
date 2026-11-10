import 'dart:io';

import 'package:flutter/foundation.dart';

import 'print.dart';

final RegExp _correlationIdPattern = RegExp(r'^[0-9a-zA-Z_-]{1,64}$');
String? _startupTimingCorrelationId;
final Stopwatch _appLaunchWatch = Stopwatch()..start();
bool _firstFrameLogged = false;
bool _tunnelReadyLogged = false;

// Diagnostic label only; the Agent instance ID still comes from the handshake.
final String startupTimingUiRunId =
    '${pid}_${DateTime.now().microsecondsSinceEpoch}';

String? get startupTimingCorrelationId => _startupTimingCorrelationId;

void _writeTiming(String fields) {
  try {
    commonPrint.log('[startup-timing] $fields');
  } catch (_) {
    // The log sink can be unavailable during startup or shutdown.
    // A diagnostic failure must not escape into the operation being timed.
  }
}

/// Captures the process entry timestamp at the start of `main()` so end-to-end
/// milestones measure true cold-launch wall-clock duration.
void markStartupLaunchEntry() {
  _appLaunchWatch
    ..reset()
    ..start();
  _firstFrameLogged = false;
  _tunnelReadyLogged = false;
}

@visibleForTesting
void resetStartupTimingForTest() {
  _startupTimingCorrelationId = null;
  _firstFrameLogged = false;
  _tunnelReadyLogged = false;
  _appLaunchWatch
    ..reset()
    ..start();
}

void setStartupTimingCorrelationId(String? value) {
  final trimmed = value?.trim();
  final previous = _startupTimingCorrelationId;
  _startupTimingCorrelationId =
      trimmed != null && _correlationIdPattern.hasMatch(trimmed)
          ? trimmed
          : null;
  if (_startupTimingCorrelationId != null &&
      _startupTimingCorrelationId != previous) {
    _writeTiming(
      'schema=2 source=ui event=correlation_bind '
      'uiRunId=$startupTimingUiRunId correlationId=$_startupTimingCorrelationId',
    );
  }
}

/// Emits the cold-start first-frame milestone at most once per process launch.
bool logStartupFirstFrameOnce({Stopwatch? watchOverride}) {
  if (_firstFrameLogged) return false;
  _firstFrameLogged = true;
  logStartupTiming(
    'e2e.first_frame',
    watchOverride ?? _appLaunchWatch,
    outcome: 'rendered',
  );
  return true;
}

/// Emits the cold-start tunnel/proxy readiness milestone at most once per
/// process launch.
bool logStartupTunnelReadyOnce({
  required String mode,
  required String outcome,
  int? corePid,
  int? tunAttempt,
  String? detail,
  Stopwatch? watchOverride,
}) {
  if (_tunnelReadyLogged) return false;
  _tunnelReadyLogged = true;
  final mergedDetail =
      detail != null && detail.isNotEmpty ? 'mode=$mode $detail' : 'mode=$mode';
  logStartupTiming(
    'e2e.tunnel_ready',
    watchOverride ?? _appLaunchWatch,
    outcome: outcome,
    corePid: corePid,
    tunAttempt: tunAttempt,
    detail: mergedDetail,
  );
  return true;
}

/// Emits a bounded, credential-free duration record for the startup path.
///
/// Keep `stage=<stage>` immediately after `[startup-timing]` so log filters and
/// existing assertions match deterministically while carrying `schema=2` and
/// `uiRunId` for cross-process correlation.
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
    'stage=$stage',
    'elapsedMs=${watch.elapsedMilliseconds}',
    if (outcome != null) 'outcome=$outcome',
    if (attempt != null) 'attempt=$attempt',
    if (corePid != null) 'corePid=$corePid',
    if (tunAttempt != null) 'tunAttempt=$tunAttempt',
    if (detail != null && detail.isNotEmpty) 'detail=$detail',
    'schema=2',
    'source=ui',
    'uiRunId=$startupTimingUiRunId',
    if (correlationId != null) 'correlationId=$correlationId',
  ];
  _writeTiming(fields.join(' '));
}
