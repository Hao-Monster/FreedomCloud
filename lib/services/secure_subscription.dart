import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/services/pre_request_transport.dart';
import 'package:flclashx/services/xboard_bootstrap.dart';

/// Download a managed account subscription without inheriting the legacy
/// client's permissive certificate callback or forwarding device IDs to an
/// untrusted third-party redirect origin. Verified FreedomNet bootstrap mirror
/// origins are permitted for both pre-request failover and same-tenant
/// redirects while arbitrary external origins are rejected.
class SecureSubscriptionDownloader {
  SecureSubscriptionDownloader({
    Dio? dio,
    this.shouldFallbackToDirect,
    TransportMirrorPool? mirrorPool,
  })  : _dio = dio ?? Dio(),
        _ownsTransport = dio == null,
        _mirrorPool = mirrorPool ?? TransportMirrorPool.shared {
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
  final TransportMirrorPool _mirrorPool;
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

  bool _isAllowedRedirectTarget(Uri source, Uri next) {
    if (next.scheme != 'https' ||
        next.host.isEmpty ||
        next.userInfo.isNotEmpty) {
      return false;
    }
    if (next.origin == source.origin) {
      return true;
    }
    return _mirrorPool.isKnownTenantOrigin(source, capability: 'sub') &&
        _mirrorPool.isKnownTenantOrigin(next, capability: 'sub');
  }

  Future<Response<Uint8List>> _fetchWithDirectFallback(
    Uri uri,
    Options options,
  ) async {
    try {
      return await _dio.getUri<Uint8List>(uri, options: options);
    } on DioException catch (error) {
      if (!_closed &&
          _ownsTransport &&
          !isCertificateDioFailure(error) &&
          isPreRequestDioFailure(error) &&
          (shouldFallbackToDirect?.call(uri) ?? false)) {
        try {
          return await _ensureDirectDio()
              .getUri<Uint8List>(uri, options: options);
        } on DioException catch (directError) {
          Error.throwWithStackTrace(directError, directError.stackTrace);
        }
      }
      rethrow;
    }
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

    final candidateOrigins = (_ownsTransport &&
            _mirrorPool.isKnownTenantOrigin(url, capability: 'sub'))
        ? _mirrorPool.orderedOrigins(capability: 'sub')
        : <Uri>[Uri.parse(url.origin)];
    // Ensure the requested URL's own origin is tried first unless another known
    // tenant mirror is already actively preferred; keep explicit origin order.
    final initialUris = <Uri>[
      url,
      for (final origin in candidateOrigins)
        if (origin.origin != url.origin) _mirrorPool.rewriteToOrigin(url, origin),
    ];

    late Response<Uint8List> response;
    var current = url;
    var connected = false;
    for (var i = 0; i < initialUris.length; i++) {
      if (_closed) {
        throw const FormatException('Subscription download failed');
      }
      final attemptUri = initialUris[i];
      try {
        response = await _fetchWithDirectFallback(attemptUri, options);
        current = attemptUri;
        connected = true;
        break;
      } on DioException catch (error) {
        final canFailover = !_closed &&
            !isCertificateDioFailure(error) &&
            isPreRequestDioFailure(error) &&
            i + 1 < initialUris.length;
        if (!canFailover) {
          throw const FormatException('Subscription download failed');
        }
      }
    }
    if (!connected) {
      throw const FormatException('Subscription download failed');
    }

    for (var redirects = 0; redirects <= 5; redirects++) {
      if (redirects > 0) {
        if (_closed) {
          throw const FormatException('Subscription download failed');
        }
        try {
          response = await _fetchWithDirectFallback(current, options);
        } on DioException {
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
      if (!_isAllowedRedirectTarget(url, next)) {
        throw const FormatException('Unsafe subscription redirect');
      }
      current = next;
    }
    throw const FormatException('Too many subscription redirects');
  }
}
