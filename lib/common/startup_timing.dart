import 'print.dart';

final RegExp _correlationIdPattern = RegExp(r'^[0-9a-zA-Z_-]{1,64}$');
String? _startupTimingCorrelationId;

String? get startupTimingCorrelationId => _startupTimingCorrelationId;

void setStartupTimingCorrelationId(String? value) {
  final trimmed = value?.trim();
  _startupTimingCorrelationId =
      trimmed != null && _correlationIdPattern.hasMatch(trimmed)
          ? trimmed
          : null;
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
  String? detail,
}) {
  final correlationId = _startupTimingCorrelationId;
  final fields = <String>[
    'stage=$stage',
    'elapsedMs=${watch.elapsedMilliseconds}',
    if (outcome != null) 'outcome=$outcome',
    if (attempt != null) 'attempt=$attempt',
    if (detail != null && detail.isNotEmpty) 'detail=$detail',
    if (correlationId != null) 'correlationId=$correlationId',
  ];
  commonPrint.log('[startup-timing] ${fields.join(' ')}');
}
