import 'iterable.dart';

class FixedList<T> {
  FixedList(this.maxLength, {List<T>? list})
      : _list = (list ?? [])..truncate(maxLength);
  final int maxLength;
  final List<T> _list;
  List<T>? _unmodifiableCache;

  void add(T item) {
    _unmodifiableCache = null;
    _list.add(item);
    _list.truncate(maxLength);
  }

  void addAll(Iterable<T> items) {
    final batch = items is List<T> ? items : items.toList(growable: false);
    if (batch.isEmpty) return;
    _unmodifiableCache = null;
    if (batch.length >= maxLength) {
      _list
        ..clear()
        ..addAll(batch.sublist(batch.length - maxLength));
      return;
    }
    final overflow = _list.length + batch.length - maxLength;
    if (overflow > 0) {
      _list.removeRange(0, overflow);
    }
    _list.addAll(batch);
  }

  void clear() {
    _unmodifiableCache = null;
    _list.clear();
  }

  List<T> get list => _unmodifiableCache ??= List.unmodifiable(_list);

  int get length => _list.length;

  T operator [](int index) => _list[index];

  FixedList<T> copyWith() => FixedList(
        maxLength,
        list: List.of(_list),
      );

  FixedList<T> copyWithAdded(Iterable<T> items) {
    final batch = items is List<T> ? items : items.toList(growable: false);
    if (batch.isEmpty) return copyWith();
    if (batch.length >= maxLength) {
      return FixedList(
        maxLength,
        list: batch.sublist(batch.length - maxLength),
      );
    }
    final keepDrop = (_list.length + batch.length) - maxLength;
    return FixedList(
      maxLength,
      list: <T>[
        if (keepDrop <= 0) ..._list else ..._list.sublist(keepDrop),
        ...batch,
      ],
    );
  }
}

class FixedMap<K, V> {
  FixedMap(this.maxLength, {Map<K, V>? map}) {
    _map = map ?? {};
  }
  int maxLength;
  late Map<K, V> _map;

  V? updateCacheValue(K key, V Function() callback) {
    final realValue = _map.updateCacheValue(
      key,
      callback,
    );
    _adjustMap();
    return realValue;
  }

  void clear() {
    _map.clear();
  }

  void updateMaxLength(int size) {
    maxLength = size;
    _adjustMap();
  }

  void updateMap(Map<K, V> map) {
    _map = map;
    _adjustMap();
  }

  void _adjustMap() {
    if (_map.length > maxLength) {
      _map = Map.fromEntries(
        map.entries.toList()..truncate(maxLength),
      );
    }
  }

  V? get(K key) => _map[key];

  bool containsKey(K key) => _map.containsKey(key);

  int get length => _map.length;

  Map<K, V> get map => Map.unmodifiable(_map);
}
