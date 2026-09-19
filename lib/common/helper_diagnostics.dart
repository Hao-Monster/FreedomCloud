/// Formats a bounded, actionable diagnostic for a privileged helper request.
///
/// The helper response can contain paths or OS error text, so diagnostics are
/// intentionally single-line and capped before they reach the application log.
String formatHelperFailure({
  required String operation,
  int? statusCode,
  String? responseBody,
  Object? error,
}) {
  final parts = <String>['helper.$operation failed'];
  if (statusCode != null) parts.add('http=$statusCode');
  final detail = _boundedDetail(responseBody ?? error?.toString());
  if (detail != null) parts.add('detail=$detail');
  if (parts.length == 1) parts.add('detail=unknown');
  return parts.join(' ');
}

String? _boundedDetail(String? value) {
  if (value == null) return null;
  final normalized = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  if (normalized.isEmpty) return null;
  return normalized.length <= 240
      ? normalized
      : '${normalized.substring(0, 237)}...';
}
