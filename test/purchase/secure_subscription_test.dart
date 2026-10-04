import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flclashx/services/secure_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

final _subscriptionUri =
    Uri.parse('https://subscription.test.invalid:8443/s/test-token');
const _deviceHeaders = {
  'x-hwid': 'fixture-device-id',
  'x-device-os': 'Windows',
  'x-ver-os': '11',
  'x-device-model': 'Fixture desktop',
  'User-Agent': 'FlClashX/test',
};

TypeMatcher<FormatException> _sanitizedFailure(
        String message) =>
    isA<FormatException>()
        .having((error) => error.message, 'message', message)
        .having((error) => error.source, 'source', isNull)
        .having((error) => error.toString(), 'printable error',
            'FormatException: $message')
        .having((error) => error.toString(), 'subscription URL',
            isNot(contains(_subscriptionUri.toString())))
        .having((error) => error.toString(), 'subscription token',
            isNot(contains('test-token')));

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final ResponseBody Function(RequestOptions request, int index) handle;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handle(options, requests.length - 1);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(int status, {String? location}) =>
    ResponseBody.fromBytes([0, 65, 128, 255], status,
        headers: {
          if (location != null) HttpHeaders.locationHeader: [location],
          HttpHeaders.contentTypeHeader: ['application/octet-stream'],
          'subscription-userinfo': ['upload=1; download=2; total=100'],
        });

class _HttpClientProbe implements HttpClient {
  bool Function(X509Certificate, String, int)? certificateCallback;
  String Function(Uri)? proxy;
  final List<Uri> requests = [];

  @override
  set badCertificateCallback(
          bool Function(X509Certificate, String, int)? value) =>
      certificateCallback = value;

  @override
  set findProxy(String Function(Uri)? value) => proxy = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    requests.add(url);
    return Future.error(const SocketException('fixture stops before network'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CertificateProbe implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _Adapter adapter;

  SecureSubscriptionDownloader downloader(
      ResponseBody Function(RequestOptions request, int index) respond) {
    adapter = _Adapter(respond);
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    return SecureSubscriptionDownloader(dio: dio);
  }

  test('requires an HTTPS URL with a host and no embedded credentials',
      () async {
    final service = downloader((_, __) => _response(200));
    for (final address in [
      'http://subscription.test.invalid/s/token',
      'ftp://subscription.test.invalid/s/token',
      'https:/missing-host',
      'https://user:password@subscription.test.invalid/s/token',
      '/s/token',
    ]) {
      await expectLater(service.download(Uri.parse(address), _deviceHeaders),
          throwsA(isA<FormatException>()));
    }
    expect(adapter.requests, isEmpty);
  });

  test(
      'returns only a successful 200 response with unchanged bytes and headers',
      () async {
    final service = downloader((_, __) => _response(200));
    final result = await service.download(_subscriptionUri, _deviceHeaders);

    expect(result.statusCode, 200);
    expect(result.data, orderedEquals([0, 65, 128, 255]));
    expect(result.headers.value('subscription-userinfo'),
        'upload=1; download=2; total=100');
    final request = adapter.requests.single;
    expect(request.uri, _subscriptionUri);
    expect(request.method, 'GET');
    expect(request.responseType, ResponseType.bytes);
    expect(request.followRedirects, isFalse);
    expect(request.connectTimeout, const Duration(seconds: 15));
    expect(request.receiveTimeout, const Duration(seconds: 60));
    expect(request.sendTimeout, const Duration(seconds: 15));
    for (final entry in _deviceHeaders.entries) {
      expect(request.headers[entry.key], entry.value);
    }
  });

  for (final status in [301, 302, 303, 307, 308]) {
    test(
        'follows same-origin $status redirects while preserving device headers',
        () async {
      final service = downloader((_, index) => index == 0
          ? _response(status, location: '/next/subscription.yaml')
          : _response(200));
      final result = await service.download(_subscriptionUri, _deviceHeaders);

      expect(result.data, orderedEquals([0, 65, 128, 255]));
      expect(adapter.requests.map((request) => request.uri), [
        _subscriptionUri,
        Uri.parse(
            'https://subscription.test.invalid:8443/next/subscription.yaml'),
      ]);
      for (final request in adapter.requests) {
        expect(request.followRedirects, isFalse);
        expect(request.method, 'GET');
        for (final entry in _deviceHeaders.entries) {
          expect(request.headers[entry.key], entry.value);
        }
      }
    });
  }

  test('resolves relative redirects against the current location', () async {
    final service = downloader((_, index) => switch (index) {
          0 => _response(302, location: '/next/directory/start'),
          1 => _response(307, location: '../final.yaml?format=clash'),
          _ => _response(200),
        });
    await service.download(_subscriptionUri, _deviceHeaders);

    expect(
        adapter.requests.last.uri,
        Uri.parse(
            'https://subscription.test.invalid:8443/next/final.yaml?format=clash'));
    expect(adapter.requests, hasLength(3));
  });

  test('rejects unsafe redirects before forwarding any request or device ID',
      () async {
    for (final location in [
      'https://other.test.invalid:8443/s/token',
      '//other.test.invalid:8443/s/token',
      'https://subscription.test.invalid/s/token',
      'http://subscription.test.invalid:8443/s/token',
      'https://user:password@subscription.test.invalid:8443/s/token',
      'file:///tmp/subscription.yaml',
    ]) {
      final service = downloader((_, __) => _response(302, location: location));
      await expectLater(service.download(_subscriptionUri, _deviceHeaders),
          throwsA(isA<FormatException>()));
      expect(adapter.requests, hasLength(1), reason: location);
      expect(adapter.requests.single.uri, _subscriptionUri);
    }
  });

  for (final status in [201, 202, 204, 206, 226, 300, 304, 305, 306, 399]) {
    test('does not accept status $status as a subscription', () async {
      final service = downloader((_, __) => _response(status));
      await expectLater(service.download(_subscriptionUri, _deviceHeaders),
          throwsA(isA<FormatException>()));
      expect(adapter.requests, hasLength(1));
    });
  }

  for (final status in [400, 401, 403, 404, 500, 503]) {
    test('rejects HTTP status $status without disclosing the subscription URL',
        () async {
      final service = downloader((_, __) => _response(status));
      await expectLater(service.download(_subscriptionUri, _deviceHeaders),
          throwsA(_sanitizedFailure('Subscription download failed')));
      expect(adapter.requests, hasLength(1));
    });
  }

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.badCertificate,
  ]) {
    test('sanitizes $type errors containing secret URLs', () async {
      final service = downloader((request, _) => throw DioException(
            requestOptions: request,
            type: type,
            message: 'Failed to request ${request.uri}',
          ));
      await expectLater(service.download(_subscriptionUri, _deviceHeaders),
          throwsA(_sanitizedFailure('Subscription download failed')));
      expect(adapter.requests, hasLength(1));
    });
  }

  test('sanitizes malformed redirect errors without forwarding the request',
      () async {
    const location = 'https://[invalid?token=redirect-secret';
    final service = downloader((_, __) => _response(302, location: location));
    await expectLater(
        service.download(_subscriptionUri, _deviceHeaders),
        throwsA(_sanitizedFailure('Unsafe subscription redirect').having(
            (error) => error.toString(),
            'redirect token',
            isNot(contains('redirect-secret')))));
    expect(adapter.requests, hasLength(1));
  });

  test('rejects a redirect without a Location header', () async {
    final service = downloader((_, __) => _response(302));
    await expectLater(service.download(_subscriptionUri, _deviceHeaders),
        throwsA(isA<FormatException>()));
    expect(adapter.requests, hasLength(1));
  });

  test('accepts a 200 response after exactly five safe redirects', () async {
    final service = downloader((_, index) => index < 5
        ? _response(302, location: '/step/${index + 1}')
        : _response(200));
    final result = await service.download(_subscriptionUri, _deviceHeaders);

    expect(result.statusCode, 200);
    expect(adapter.requests, hasLength(6));
    expect(adapter.requests.last.uri.path, '/step/5');
  });

  test('stops a redirect loop before requesting a sixth redirect target',
      () async {
    final service = downloader(
        (_, __) => _response(302, location: _subscriptionUri.toString()));
    await expectLater(
        service.download(_subscriptionUri, _deviceHeaders),
        throwsA(isA<FormatException>().having((error) => error.message,
            'message', 'Too many subscription redirects')));
    expect(adapter.requests, hasLength(6));
  });

  test(
      'production transport rejects trust-all overrides and keeps proxy routing',
      () async {
    final client = _HttpClientProbe()
      ..badCertificateCallback = ((_, __, ___) => true)
      ..findProxy = ((_) => 'PROXY localhost:7890');
    await HttpOverrides.runZoned(() async {
      final service = SecureSubscriptionDownloader();
      await expectLater(service.download(_subscriptionUri, _deviceHeaders),
          throwsA(_sanitizedFailure('Subscription download failed')));

      expect(client.requests, [_subscriptionUri]);
      expect(
          client.certificateCallback
              ?.call(_CertificateProbe(), _subscriptionUri.host, 8443),
          isFalse);
      expect(client.proxy?.call(_subscriptionUri), 'PROXY localhost:7890');
    }, createHttpClient: (_) => client);
  });
}
