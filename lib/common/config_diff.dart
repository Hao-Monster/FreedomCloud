import 'dart:convert';

/// Stable structural comparison. Lists retain order because rule order matters.
List<String> configurationDiff(Object? before, Object? after,
    [String path = r'$']) {
  final result = <String>[];
  void visit(Object? a, Object? b, String key) {
    if (a is Map && b is Map) {
      final keys = {...a.keys, ...b.keys}.map((e) => e.toString()).toList()..sort();
      for (final name in keys) {
        if (!a.containsKey(name)) {
          result.add('+ $key.$name = ${jsonEncode(b[name])}');
        } else if (!b.containsKey(name)) {
          result.add('- $key.$name = ${jsonEncode(a[name])}');
        } else {
          visit(a[name], b[name], '$key.$name');
        }
      }
    } else if (jsonEncode(a) != jsonEncode(b)) {
      result.add('$key\n- ${jsonEncode(a)}\n+ ${jsonEncode(b)}');
    }
  }
  visit(before, after, path);
  return result;
}

Object? redactConfiguration(Object? value, [String key = '']) {
  if (RegExp(r'secret|password|token|private.key|authorization|uuid',
          caseSensitive: false).hasMatch(key)) {
    return '<redacted>';
  }
  if (value is Map) {
    return {for (final entry in value.entries)
      entry.key.toString(): redactConfiguration(entry.value, entry.key.toString())};
  }
  if (value is List) return value.map((v) => redactConfiguration(v, key)).toList();
  if (value is String && Uri.tryParse(value)?.hasScheme == true) {
    final uri = Uri.parse(value);
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return '${uri.scheme}://${uri.host}/<redacted-path>';
    }
  }
  return value;
}

Map<String, dynamic> normalizeConfiguration(Map<String, dynamic> config) {
  final result = Map<String, dynamic>.from(config);
  if (result.containsKey('rule')) result['rules'] = result.remove('rule');
  return result;
}
