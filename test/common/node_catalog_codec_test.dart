import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flclashx/common/node_catalog_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compressed provider JSON round trips above normal frame size',
      () async {
    final payload = jsonEncode({
      'proxies': [
        for (var i = 0; i < 12000; i++)
          {
            'name': 'Node $i',
            'type': 'ss',
            'server': 'fixture.invalid',
            'port': 443,
            'password': 'PRIVATE'
          }
      ]
    });
    expect(utf8.encode(payload).length, greaterThan(1024 * 1024));
    final encoded = await encodeCatalogPayload(payload);
    expect(utf8.encode(jsonEncode(encoded)).length,
        lessThanOrEqualTo(catalogPayloadFrameBytes));
    expect(await decodeCatalogPayload(encoded), payload);
  });
  test('decompression rejects bomb and malformed data with fixed codes',
      () async {
    final bomb = jsonEncode({
      'payload-gzip': base64Encode(
          gzip.encode(List.filled(catalogPayloadDecodedBytes + 1, 65)))
    });
    await expectLater(
        decodeCatalogPayload(bomb),
        throwsA(isA<CatalogPayloadException>()
            .having((e) => e.reason, 'reason', 'providerTooLarge')));
    await expectLater(
        decodeCatalogPayload('{"payload-gzip":"PRIVATE"}'),
        throwsA(isA<CatalogPayloadException>()
            .having((e) => e.reason, 'reason', 'invalidResponse')));
  });
  test('high entropy payload and expanded request are bounded before IPC',
      () async {
    final random = Random(123);
    final payload =
        base64Encode(List.generate(700000, (_) => random.nextInt(256)));
    await expectLater(
        encodeCatalogPayload(payload),
        throwsA(isA<CatalogPayloadException>()
            .having((e) => e.reason, 'reason', 'providerTooLarge')));
    await expectLater(
        encodeCatalogPayload('x' * (catalogPayloadDecodedBytes + 1)),
        throwsA(isA<CatalogPayloadException>()
            .having((e) => e.reason, 'reason', 'providerTooLarge')));
  });
}
