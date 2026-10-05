import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Download a managed account subscription without inheriting the legacy
/// client's permissive certificate callback or forwarding device IDs to a
/// different redirect origin. Existing OS/proxy routing remains in effect.
class SecureSubscriptionDownloader {
  SecureSubscriptionDownloader({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    if (dio == null) {
      _dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
        final client = HttpClient()
          ..badCertificateCallback = (_, __, ___) => false;
        return client;
      });
    }
  }

  final Dio _dio;

  Future<Response<Uint8List>> download(
    Uri url,
    Map<String, dynamic> headers,
  ) async {
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Managed subscriptions require HTTPS');
    }
    var current = url;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final Response<Uint8List> response;
      try {
        response = await _dio.getUri<Uint8List>(current,
            options: Options(
              headers: headers,
              responseType: ResponseType.bytes,
              followRedirects: false,
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ));
      } on DioException {
        // Background profile updates display thrown errors directly; never expose the secret URL.
        throw const FormatException('Subscription download failed');
      }
      final status = response.statusCode;
      if (status == 200) return response;
      if (![301, 302, 303, 307, 308].contains(status)) {
        throw const FormatException('Unexpected subscription response');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) {
        throw const FormatException('Missing subscription redirect');
      }
      final Uri next;
      try {
        next = current.resolve(location);
      } on FormatException {
        throw const FormatException('Unsafe subscription redirect');
      }
      if (next.scheme != 'https' ||
          next.host.isEmpty ||
          next.userInfo.isNotEmpty ||
          next.origin != url.origin) {
        throw const FormatException('Unsafe subscription redirect');
      }
      current = next;
    }
    throw const FormatException('Too many subscription redirects');
  }
}
