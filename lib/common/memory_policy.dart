import 'package:flutter/painting.dart';

const desktopImageCacheEntries = 256;
const desktopImageCacheBytes = 32 * 1024 * 1024;

/// Flutter's desktop default permits up to 1000 decoded images / 100 MiB.
/// FlClashX mostly displays small icons, so a lower explicit bound avoids a
/// long-running process retaining large profile backgrounds and process icons.
void configureDecodedImageCache(
  ImageCache cache, {
  required bool isDesktop,
}) {
  if (!isDesktop) return;
  cache
    ..maximumSize = desktopImageCacheEntries
    ..maximumSizeBytes = desktopImageCacheBytes;
}
