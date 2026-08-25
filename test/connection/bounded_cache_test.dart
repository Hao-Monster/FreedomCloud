import 'package:flclashx/common/bounded_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded cache evicts the least recently used entry', () {
    final evicted = <String>[];
    final cache = BoundedCache<String, int>(
      maxEntries: 2,
      onEvict: (key, value) => evicted.add('$key:$value'),
    );

    expect(cache.putIfAbsent('a', () => 1), 1);
    expect(cache.putIfAbsent('b', () => 2), 2);
    expect(cache.putIfAbsent('a', () => 99), 1);
    expect(cache.putIfAbsent('c', () => 3), 3);

    expect(cache.length, 2);
    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
    expect(cache.containsKey('c'), isTrue);
    expect(evicted, ['b:2']);
  });

  test('bounded cache stores nullable values without recomputing them', () {
    var loads = 0;
    final cache = BoundedCache<String, int?>(maxEntries: 1);

    expect(
        cache.putIfAbsent('missing', () {
          loads++;
          return null;
        }),
        isNull);
    expect(
        cache.putIfAbsent('missing', () {
          loads++;
          return 1;
        }),
        isNull);

    expect(loads, 1);
  });

  test('clear invokes eviction cleanup for every retained value', () {
    final evicted = <int>[];
    final cache = BoundedCache<String, int>(
      maxEntries: 3,
      onEvict: (_, value) => evicted.add(value),
    );
    cache
      ..putIfAbsent('a', () => 1)
      ..putIfAbsent('b', () => 2)
      ..clear();

    expect(cache, isEmpty);
    expect(evicted, unorderedEquals([1, 2]));
  });
}
