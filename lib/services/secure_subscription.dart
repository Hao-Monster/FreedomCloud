import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/services/pre_request_transport.dart';

/// Download a managed account subscription without inheriting the legacy
/// client's permissive certificate callback or forwarding device IDs to a
/// different redirect origin. Existing OS/proxy routing remains in effect,
/// with optional pre-request DIRECT fallback when the local proxy tunnel fails.
class SecureSubscriptionDownloader {
  SecureSubscriptionDownloader({
    Dio? dio,
    this.shouldFallbackToDirect,
  })  : _dio = dio ?? Dio(),
        _ownsTransport = dio == null {
    _dio.options.connectTimeout = _ownsTransport && shouldFallbackToDirect != null
        ? const Duration(seconds: 6)
        : const Duration(seconds: 15);
    if (_ownsTransport) {
      _dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
        final client = wrapPreRequestHttpClient(HttpClient())
          ..badCertificateCallback = (_, __, ___) => false;
        return client;
      });
    }
  }

  final Dio _dio;
  final bool _ownsTransport;
  final bool Function(Uri url)? shouldFallbackToDirect;
  Dio? _directDio;
  bool _closed = false;

  void close() {
    _closed = true;
    _dio.close(force: true);
    final direct = _directDio;
    _directDio = null;
    direct?.close(force: true);
  }

  Dio _ensureDirectDio() {
    if (_closed) {
      throw const FormatException('Subscription download failed');
    }
    return _directDio ??= (Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
      ),
    )..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => wrapPreRequestHttpClient(HttpClient())
          ..findProxy = ((_) => 'DIRECT')
          ..badCertificateCallback = ((_, __, ___) => false),
      ));
  }

  Future<Response<Uint8List>> download(
    Uri url,
    Map<String, dynamic> headers,
  ) async {
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Managed subscriptions require HTTPS');
    }
    if (_closed) {
      throw const FormatException('Subscription download failed');
    }
    final options = Options(
      headers: headers,
      responseType: ResponseType.bytes,
      followRedirects: false,
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 15),
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    );
    var current = url;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (_closed) {
        throw const FormatException('Subscription download failed');
      }
      Response<Uint8List> response;
      try {
        response = await _dio.getUri<Uint8List>(current, options: options);
      } on DioException catch (error) {
        if (!_closed &&
            _ownsTransport &&
            isPreRequestDioFailure(error) &&
            (shouldFallbackToDirect?.call(current) ?? false)) {
          try {
            response = await _ensureDirectDio()
                .getUri<Uint8List>(current, options: options);
          } on DioException {
            throw const FormatException('Subscription download failed');
          }
        } else {
          // Background profile updates display thrown errors directly; never expose the secret URL.
          throw const FormatException('Subscription download failed');
        }
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
