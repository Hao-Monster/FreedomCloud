import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flclashx/common/process_icon.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> onePixel() {
  final result = Completer<ui.Image>();
  ui.decodeImageFromPixels(Uint8List.fromList([0, 0, 255, 255]), 1, 1,
      ui.PixelFormat.bgra8888, result.complete);
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG encoding disposes the image after returning valid bytes', () async {
    final image = await onePixel();
    final bytes = await encodeProcessIconImage(image);
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(image.debugDisposed, isTrue);
  });

  test('null PNG encoding still disposes the image', () async {
    final image = await onePixel();
    expect(
        await encodeProcessIconImage(image, encode: (_) async => null), isNull);
    expect(image.debugDisposed, isTrue);
  });

  test('failed PNG encoding disposes the image and later work succeeds',
      () async {
    final image = await onePixel();
    try {
      await expectLater(
        encodeProcessIconImage(image,
            encode: (_) async => throw StateError('encoder')),
        throwsStateError,
      );
      expect(image.debugDisposed, isTrue);
      final next = await onePixel();
      expect(await encodeProcessIconImage(next), isNotEmpty);
      expect(next.debugDisposed, isTrue);
    } finally {
      if (!image.debugDisposed) image.dispose();
    }
  });
}
