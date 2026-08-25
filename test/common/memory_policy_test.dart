import 'package:flclashx/common/memory_policy.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop decoded image cache has an explicit memory bound', () {
    final cache = ImageCache();

    configureDecodedImageCache(cache, isDesktop: true);

    expect(cache.maximumSize, desktopImageCacheEntries);
    expect(cache.maximumSizeBytes, desktopImageCacheBytes);
  });

  test('mobile keeps Flutter image cache defaults', () {
    final cache = ImageCache();
    final entries = cache.maximumSize;
    final bytes = cache.maximumSizeBytes;

    configureDecodedImageCache(cache, isDesktop: false);

    expect(cache.maximumSize, entries);
    expect(cache.maximumSizeBytes, bytes);
  });
}
