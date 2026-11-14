import 'dart:io';

import 'package:dio/dio.dart';

class PreRequestTransportException implements Exception {
  const PreRequestTransportException(this.cause);

  final Object cause;

  @override
  String toString() => cause.toString();
}

Object? unwrapPreRequestTransportError(Object? error) => switch (error) {
      PreRequestTransportException(:final cause) => cause,
      final other => other,
    };

bool isPreRequestDioFailure(DioException error) {
  if (error.response != null) return false;
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.connectionError) {
    return true;
  }
  return error.error is PreRequestTransportException;
}

bool isCertificateTransportError(Object? error) {
  final cause = unwrapPreRequestTransportError(error);
  if (cause is CertificateException) return true;
  if (cause is TlsException) {
    final text =
        '${cause.message} ${cause.osError?.message ?? ''}'.toLowerCase();
    return text.contains('certificate') ||
        text.contains('cert_') ||
        text.contains('unable to get local issuer') ||
        text.contains('self signed') ||
        text.contains('hostname mismatch') ||
        text.contains('unknown ca');
  }
  return false;
}

bool isCertificateDioFailure(DioException error) {
  if (error.type == DioExceptionType.badCertificate) return true;
  return isCertificateTransportError(error.error);
}

HttpClient wrapPreRequestHttpClient(HttpClient inner) =>
    _PreRequestTrackingHttpClient(inner);

class _PreRequestTrackingHttpClient implements HttpClient {
  _PreRequestTrackingHttpClient(this._inner);

  final HttpClient _inner;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
        f,
  ) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )? f,
  ) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(void Function(String line)? callback) => _inner.keyLog = callback;

  Future<HttpClientRequest> _guard(
    Future<HttpClientRequest> Function() op,
  ) async {
    try {
      return await op();
    } on SocketException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(PreRequestTransportException(error), stackTrace);
    }
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _guard(() => _inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _guard(() => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _guard(() => _inner.get(host, port, path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _guard(() => _inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _guard(() => _inner.post(host, port, path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _guard(() => _inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _guard(() => _inner.put(host, port, path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _guard(() => _inner.putUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _guard(() => _inner.delete(host, port, path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _guard(() => _inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _guard(() => _inner.patch(host, port, path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _guard(() => _inner.patchUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _guard(() => _inner.head(host, port, path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _guard(() => _inner.headUrl(url));

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
