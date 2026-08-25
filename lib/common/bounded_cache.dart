import 'dart:collection';

typedef CacheEvictionCallback<K, V> = void Function(K key, V value);

/// A small least-recently-used cache with an explicit memory bound.
///
/// [V] may be nullable. A cached null is still treated as a cache hit, which is
/// useful for negative icon lookups that should not hit the platform repeatedly.
class BoundedCache<K, V> {
  BoundedCache({
    required this.maxEntries,
    this.onEvict,
  }) : assert(maxEntries > 0, 'maxEntries must be positive');

  final int maxEntries;
  final CacheEvictionCallback<K, V>? onEvict;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  bool containsKey(K key) => _entries.containsKey(key);

  V putIfAbsent(K key, V Function() loader) {
    if (_entries.containsKey(key)) {
      final value = _entries[key] as V;
      _entries
        ..remove(key)
        ..[key] = value;
      return value;
    }

    final value = loader();
    _entries[key] = value;
    if (_entries.length > maxEntries) {
      final oldestKey = _entries.keys.first;
      final oldestValue = _entries.remove(oldestKey) as V;
      onEvict?.call(oldestKey, oldestValue);
    }
    return value;
  }

  void clear() {
    if (onEvict != null) {
      for (final entry in _entries.entries) {
        onEvict!(entry.key, entry.value);
      }
    }
    _entries.clear();
  }
}
