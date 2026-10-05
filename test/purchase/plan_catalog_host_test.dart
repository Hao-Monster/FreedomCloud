import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/views/purchase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _origin = 'https://fast.hjy.ca:8443';

class _Headers implements HttpHeaders {
  final values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void forEach(void Function(String, List<String>) action) =>
      values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected header method ${invocation.memberName}');
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response()
      : _bytes = utf8.encode(jsonEncode({
          'status': 'success',
          'data': [
            {
              'id': 81,
              'name': 'Host-only plan fixture',
              'transfer_enable': 200,
              'speed_limit': null,
              'device_limit': null,
              'can_purchase': true,
              'prices': {'yearly': 15000},
            },
          ],
        }));

  final List<int> _bytes;

  @override
  final _Headers headers = _Headers()
    ..set(HttpHeaders.contentTypeHeader, 'application/json');

  @override
  int get statusCode => 200;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  String get reasonPhrase => 'OK';

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(_bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected response method ${invocation.memberName}');
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri);

  @override
  final String method;
  @override
  final Uri uri;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  Future<HttpClientResponse> close() async => _Response();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected request method ${invocation.memberName}');
}

/// Only the transport boundary is replaced. PurchaseView creates its real API,
/// storage, manager and initState work; no test manually calls loadPlans.
class _Client implements HttpClient {
  final requests = <_Request>[];

  @override
  Duration? connectionTimeout;

  @override
  set badCertificateCallback(
      bool Function(X509Certificate, String, int)? callback) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (method != 'GET' || url != Uri.parse('$_origin/api/v1/guest/plans')) {
      throw StateError('Unexpected network request: $method ${url.path}');
    }
    final request = _Request(method, url);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected HTTP method ${invocation.memberName}');
}

void main() {
  for (final corruptStoredSession in [false, true]) {
    testWidgets(
        'real PurchaseView loads guest catalog from initState '
        '${corruptStoredSession ? 'despite invalid saved credentials' : 'without saved credentials'}',
        (tester) async {
      final prefix = sha256.convert(utf8.encode(_origin));
      FlutterSecureStorage.setMockInitialValues({
        if (corruptStoredSession)
          'flclashx.xboard.$prefix.session': 'invalid synthetic session',
      });
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.delegate.supportedLocales,
            home: const Scaffold(body: PurchaseView()),
          ),
        ));
        await tester.pumpAndSettle();

        expect(client.requests, hasLength(1));
        expect(client.requests.single.headers.values,
            isNot(contains(HttpHeaders.authorizationHeader)));
        expect(find.text('Host-only plan fixture'), findsOneWidget);
        expect(find.text('Traffic quota: 200 GiB'), findsOneWidget);
        expect(find.text('150.00'), findsOneWidget);
        expect(find.byKey(const Key('purchase-email')), findsOneWidget);
        expect(find.byKey(const Key('purchase-password')), findsOneWidget);
        expect(find.byKey(const Key('purchase-login')), findsOneWidget);
        expect(find.text('WeChat ID: ChasingDream_2021'), findsOneWidget);
        expect(find.text('WeChat ID: dxm_qa'), findsOneWidget);
        if (corruptStoredSession) {
          expect(
              find.text(
                  'Secure account storage is unavailable. Retry after checking your system credential storage.'),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, createHttpClient: (_) => client);
    });
  }
}
