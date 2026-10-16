import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

class CatalogPayloadException implements Exception {
  const CatalogPayloadException(this.reason);
  final String reason;
  @override
  String toString() => 'CatalogPayloadException($reason)';
}

const catalogPayloadFrameBytes = 512 * 1024;
const catalogPayloadDecodedBytes = 12 * 1024 * 1024;

Future<String> encodeCatalogPayload(String payload) => Isolate.run(() {
      final bytes = utf8.encode(payload);
      if (bytes.length > catalogPayloadDecodedBytes) {
        throw const CatalogPayloadException('providerTooLarge');
      }
      final encoded =
          jsonEncode({'payload-gzip': base64Encode(gzip.encode(bytes))});
      // Count the escaped string as sent within the Action, leaving ample space
      // for its method/id. Core and Agent retain their existing 1 MiB limit.
      if (utf8.encode(jsonEncode(encoded)).length > catalogPayloadFrameBytes) {
        throw const CatalogPayloadException('providerTooLarge');
      }
      return encoded;
    });

Future<String> decodeCatalogPayload(String message) => Isolate.run(() {
      if (utf8.encode(jsonEncode(message)).length > catalogPayloadFrameBytes) {
        throw const CatalogPayloadException('providerTooLarge');
      }
      try {
        final envelope = jsonDecode(message);
        if (envelope is! Map || envelope['payload-gzip'] is! String) {
          throw const CatalogPayloadException('invalidResponse');
        }
        final compressed = base64Decode(envelope['payload-gzip'] as String);
        final output = _BoundedPayloadSink();
        final decoder = gzip.decoder.startChunkedConversion(output);
        for (var start = 0; start < compressed.length; start += 4096) {
          final end = start + 4096 < compressed.length
              ? start + 4096
              : compressed.length;
          decoder.add(Uint8List.sublistView(compressed, start, end));
        }
        decoder.close();
        return utf8.decode(output.bytes.takeBytes());
      } on CatalogPayloadException {
        rethrow;
      } catch (_) {
        throw const CatalogPayloadException('invalidResponse');
      }
    });

class _BoundedPayloadSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > catalogPayloadDecodedBytes) {
      throw const CatalogPayloadException('providerTooLarge');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
