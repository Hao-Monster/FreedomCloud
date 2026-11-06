import 'print.dart';

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
  final fields = <String>[
    'stage=$stage',
    'elapsedMs=${watch.elapsedMilliseconds}',
    if (outcome != null) 'outcome=$outcome',
    if (attempt != null) 'attempt=$attempt',
    if (detail != null && detail.isNotEmpty) 'detail=$detail',
  ];
  commonPrint.log('[startup-timing] ${fields.join(' ')}');
}
