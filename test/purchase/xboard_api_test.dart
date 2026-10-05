import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _auth = 'Bearer account-test-credential';
const _code = 'TEST-CARD-123456';

Map<String, Object?> _success(Object? data) => {
      'status': 'success',
      'data': data,
    };

Map<String, Object?> _snapshot() => {
      'plan_id': 7,
      'plan_name': '测试套餐',
      'period': 'month_price',
      'transfer_enable': 107374182400,
      'speed_limit': 100,
      'device_limit': 3,
    };

Map<String, Object?> _purchaseReward() => {
      'plan_id': 7,
      'purchase_period': 'month_price',
      'purchase_snapshot': _snapshot(),
    };

Map<String, Object?> _purchasePreview() => {
      'transfer_before': 107374182400,
      'transfer_after': 107374182400,
      'used_traffic': 1024,
      'expires_before': '2026-10-10T00:00:00Z',
      'expires_after': '2026-11-10T00:00:00Z',
      'renewal': true,
    };

Map<String, Object?> _legacyPreview({
  int type = 4,
  bool withId = true,
  bool canRedeem = true,
  String? reason,
}) =>
    {
      'code_info': {
        if (withId) 'code_id': 19,
        'code': _code,
        'template': {'name': '测试礼品卡', 'type': type},
      },
      'reward_preview': type == 4 ? _purchaseReward() : {'balance': 500},
      'purchase_preview': type == 4 ? _purchasePreview() : null,
      'can_redeem': canRedeem,
      'reason': reason,
    };

Map<String, Object?> _legacyHistoryEntry({String code = 'TEST-CAR****'}) => {
      'id': 88,
      'code_id': 19,
      'code': code,
      'template_name': '购买兑换码',
      'template_type': 4,
      'rewards_given': _purchaseReward(),
      'created_at': 1791072000,
      'order_trade_no': 'gift-order-88',
    };

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final Future<ResponseBody> Function(RequestOptions options) handle;
  final List<RequestOptions> requests = [];
  final List<String?> requestBodies = [];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = await requestStream?.toList();
    requestBodies.add(chunks == null
        ? null
        : utf8.decode(chunks.expand((chunk) => chunk).toList()));
    return handle(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _HttpClientProbe implements HttpClient {
  bool Function(X509Certificate, String, int)? certificateCallback;
  String Function(Uri)? proxy;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate, String, int)? value) =>
      certificateCallback = value;

  @override
  set findProxy(String Function(Uri)? value) => proxy = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('fixture stops before network'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CertificateProbe implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _Adapter adapter;
  late DioXboardApi api;

  void respond(Object? body, {int status = 200}) {
    adapter = _Adapter((_) async => _json(body, status: status));
    api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(api.close);
  }

  test(
      'production transport rejects a global trust-all override without changing proxy routing',
      () async {
    final client = _HttpClientProbe()
      ..badCertificateCallback = ((_, __, ___) => true)
      ..findProxy = ((_) => 'PROXY localhost:7890');
    await HttpOverrides.runZoned(() async {
      final secureApi = DioXboardApi();
      await expectLater(
          secureApi.getAccount(_auth), throwsA(isA<XboardException>()));
      expect(
          client.certificateCallback
              ?.call(_CertificateProbe(), 'test.invalid', 443),
          isFalse);
      expect(client.proxy?.call(Uri.parse('https://test.invalid')),
          'PROXY localhost:7890');
      secureApi.close();
    }, createHttpClient: (_) => client);
  });

  test('uses the configured HTTPS origin and preserves the port', () async {
    respond(_success(
        {'id': 2, 'email': 'member@test.invalid', 'is_distributor': false}));
    final account = await api.getAccount(_auth);
    expect(api.baseUri, Uri.parse('https://fast.hjy.ca:8443'));
    expect(adapter.requests.single.uri,
        Uri.parse('https://fast.hjy.ca:8443/api/v1/auth/session'));
    expect(adapter.requests.single.headers['Authorization'], _auth);
    expect(adapter.requests.single.followRedirects, isFalse);
    expect(adapter.requests.single.maxRedirects, 0);
    expect(account.id, 2);
    expect(account.email, 'member@test.invalid');
    expect(account.isDistributor, isFalse);
  });

  test('rejects insecure or non-origin service configuration', () {
    for (final url in [
      'http://test.invalid',
      'https://user:secret@test.invalid',
      'https://test.invalid/api',
      'https://test.invalid?token=secret',
      'https://test.invalid#secret',
    ]) {
      expect(() => DioXboardApi(baseUri: Uri.parse(url)), throwsArgumentError);
    }
  });

  test('login uses auth_data and never the neighboring subscription token',
      () async {
    respond(_success({
      'auth_data': _auth,
      'token': 'subscription-only-token',
      'is_admin': false,
    }));
    expect(await api.login(' member@test.invalid ', 'test-password'), _auth);
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/passport/auth/login');
    expect(request.method, 'POST');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(adapter.requestBodies.single!), {
      'email': 'member@test.invalid',
      'password': 'test-password',
    });
  });

  test('a missing account credential cannot silently use a subscription token',
      () async {
    respond(_success({'token': 'subscription-only-token'}));
    await expectLater(
        api.login('a@test.invalid', 'password'),
        throwsA(isA<XboardException>()
            .having((e) => e.code, 'code', 'invalid_response')));
  });

  test('invalid Authorization is rejected before making a request', () async {
    respond(_success({}));
    await expectLater(
      api.getAccount('Bearer token\r\nInjected: header'),
      throwsA(isA<XboardException>()
          .having((e) => e.isUnauthorized, 'unauthorized', isTrue)),
    );
    expect(adapter.requests, isEmpty);
  });

  test('subscription consumes byte quotas, exact URL, expiry and validity',
      () async {
    respond(_success({
      'plan_id': 7,
      'plan': {'id': 7, 'name': '测试套餐'},
      'subscription_valid': true,
      'subscribe_url': 'https://fast.hjy.ca:8443/subscription/fixture-token',
      'u': 200,
      'd': 800,
      'transfer_enable': 5000,
      'expired_at': '2026-11-01T00:00:00Z',
    }));
    final subscription = await api.getSubscription(_auth);
    expect(subscription.planId, 7);
    expect(subscription.planName, '测试套餐');
    expect(subscription.valid, isTrue);
    expect(subscription.usedTraffic, 1000);
    expect(subscription.remainingTraffic, 4000);
    expect(subscription.expiresAt, DateTime.utc(2026, 11));
    expect(subscription.url.port, 8443);
    expect(subscription.balance, isNull);
  });

  test('unsubscribed account and unlimited expiry preserve null semantics',
      () async {
    respond(_success({
      'plan_id': null,
      'plan': null,
      'subscription_valid': false,
      'subscribe_url': 'https://test.invalid/sub/fixture',
      'u': 0,
      'd': 0,
      'transfer_enable': 0,
      'expired_at': null,
    }));
    final subscription = await api.getSubscription(_auth);
    expect(subscription.planId, isNull);
    expect(subscription.expiresAt, isNull);
    expect(subscription.valid, isFalse);
    expect(subscription.remainingTraffic, 0);
  });

  test('Bearer purchase preview keeps fixed snapshot and before/after rights',
      () async {
    respond(_success(_legacyPreview()));
    final preview = await api.checkGift(_auth, ' $_code ');
    expect(adapter.requests.single.path, '/api/v1/user/gift-card/check');
    expect(jsonDecode(adapter.requestBodies.single!), {'code': _code});
    expect(preview.codeId, 19);
    expect(preview.type, 4);
    expect(preview.canRedeem, isTrue);
    expect(preview.rewards.purchaseSnapshot?.planName, '测试套餐');
    expect(preview.rewards.purchaseSnapshot?.transferEnable, 107374182400);
    expect(preview.purchasePreview?.usedTraffic, 1024);
    expect(preview.purchasePreview?.transferAfter, 107374182400);
    expect(preview.purchasePreview?.expiresAfter, DateTime.utc(2026, 11, 10));
    expect(preview.purchasePreview?.renewal, isTrue);
  });

  test('older Bearer preview preserves missing code identity as null',
      () async {
    respond(_success(_legacyPreview(withId: false)));
    expect((await api.checkGift(_auth, _code)).codeId, isNull);
  });

  test('modern preview reads separate template and code_info.id', () async {
    respond(_success({
      'code_info': {'id': 19, 'code': _code},
      'template': {'name': '余额卡', 'type': 1},
      'reward_preview': {'balance': 500},
      'can_redeem': true,
      'reason': '',
      'purchase_preview': null,
    }));
    final preview = await api.checkGift(_auth, _code);
    expect(preview.codeId, 19);
    expect(preview.type, 1);
    expect(preview.rewards.balance, 500);
    expect(preview.rewards.planId, isNull);
  });

  test('mystery preview remains explicitly uncertain about actual rewards',
      () async {
    respond(_success(_legacyPreview(type: 3)));
    final preview = await api.checkGift(_auth, _code);
    expect(preview.isMystery, isTrue);
    expect(preview.rewards.balance, 500);
  });

  test(
      'an explicit zero reward remains valid after backend multiplier rounding',
      () async {
    respond(_success({
      ..._legacyPreview(type: 1),
      'reward_preview': <String, Object?>{},
    }));
    final preview = await api.checkGift(_auth, _code);
    expect(preview.canRedeem, isTrue);
    expect(preview.rewards.isEmpty, isTrue);

    respond(_success({
      'template_name': '小额余额卡',
      'code_id': 19,
      'rewards': <String, Object?>{},
    }));
    final receipt = await api.redeemGift(_auth, _code);
    expect(receipt.codeId, 19);
    expect(receipt.rewards.isEmpty, isTrue);

    respond({
      'data': [
        {..._legacyHistoryEntry(), 'rewards_given': <String, Object?>{}},
      ],
      'pagination': {
        'current_page': 1,
        'last_page': 1,
        'per_page': 15,
        'total': 1,
      },
    });
    expect((await api.getGiftHistory(_auth)).entries.single.rewards.isEmpty,
        isTrue);
  });

  test('missing and unknown reward schemas cannot masquerade as zero rewards',
      () async {
    for (final value in [
      null,
      <String, Object?>{'new_reward_type': 100},
      <String, Object?>{'balance': 100, 'new_reward_type': 100},
    ]) {
      respond(_success({
        ..._legacyPreview(type: 1),
        'reward_preview': value,
      }));
      await expectLater(
          api.checkGift(_auth, _code), throwsA(isA<XboardException>()));
    }
  });

  test(
      'rejected preview keeps known eligibility reason without allowing redeem',
      () async {
    const reason = '当前套餐与购买兑换码不一致，兑换码未消耗';
    respond(_success(_legacyPreview(canRedeem: false, reason: reason)));
    final preview = await api.checkGift(_auth, _code);
    expect(preview.canRedeem, isFalse);
    expect(preview.reason, reason);
  });

  test('unknown eligibility text cannot reflect gift codes or credentials',
      () async {
    respond(_success(
        _legacyPreview(canRedeem: false, reason: 'debug $_auth $_code')));
    final preview = await api.checkGift(_auth, _code);
    expect(preview.reason, '当前账号不满足兑换条件');
    expect(preview.reason, isNot(contains(_code)));
  });

  test('redeem parses legacy receipt identity and actual rewards', () async {
    respond(_success({
      'template_name': '套餐购买码',
      'code_id': 19,
      'rewards': _purchaseReward(),
      'order_trade_no': 'gift-order-19',
    }));
    final receipt = await api.redeemGift(_auth, _code);
    expect(receipt.codeId, 19);
    expect(receipt.orderTradeNo, 'gift-order-19');
    expect(receipt.rewards.purchaseSnapshot?.planId, 7);
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/api/v1/user/gift-card/redeem');
  });

  test('redeem parses modern receipt identity inside usage', () async {
    respond(_success({
      'template_name': '余额卡',
      'rewards': {'balance': 1500},
      'usage': {'code_id': 19, 'order_trade_no': 'gift-order-19'},
    }));
    final receipt = await api.redeemGift(_auth, _code);
    expect(receipt.codeId, 19);
    expect(receipt.orderTradeNo, 'gift-order-19');
    expect(receipt.rewards.balance, 1500);
  });

  test('legacy history envelope preserves pagination and exact code identity',
      () async {
    respond({
      'data': [_legacyHistoryEntry(code: 'SHORT')],
      'pagination': {
        'current_page': 2,
        'last_page': 3,
        'per_page': 15,
        'total': 31
      },
    });
    final history = await api.getGiftHistory(_auth, page: 2);
    expect(adapter.requests.single.queryParameters['page'], 2);
    expect(history.page, 2);
    expect(history.lastPage, 3);
    expect(history.total, 31);
    expect(history.entries.single.id, 88);
    expect(history.entries.single.codeId, 19);
    expect(history.entries.single.maskedCode, 'SHOR****');
    expect(history.entries.single.orderTradeNo, 'gift-order-88');
    expect(history.entries.single.usedAt.isUtc, isTrue);
    expect(history.entries.clear, throwsUnsupportedError);
  });

  test('modern history preserves nullable old identities and ISO timestamps',
      () async {
    respond(_success({
      'items': [
        {
          'id': 88,
          'code_id': 19,
          'code': 'TEST-CAR****',
          'template_name': '余额卡',
          'template_type': 1,
          'rewards': {'balance': 200},
          'used_at': '2026-10-04T00:00:00Z',
        },
      ],
      'page': 1,
      'page_size': 15,
      'total': 1,
    }));
    final history = await api.getGiftHistory(_auth);
    expect(history.entries.single.usedAt, DateTime.utc(2026, 10, 4));
    expect(history.lastPage, 1);
    expect(history.entries.single.type, 1);
  });

  test('an empty history is explicit and remains an empty success', () async {
    respond({
      'data': <Object?>[],
      'pagination': {
        'current_page': 1,
        'last_page': 1,
        'per_page': 15,
        'total': 0
      },
    });
    expect((await api.getGiftHistory(_auth)).entries, isEmpty);
  });

  test('card store is optional but only opens an HTTPS URL', () async {
    respond(_success({'card_store_url': ''}));
    expect(await api.getCardStore(_auth), isNull);
    respond(
        _success({'card_store_url': 'https://cards.test.invalid/item?id=1'}));
    expect(await api.getCardStore(_auth),
        Uri.parse('https://cards.test.invalid/item?id=1'));
    respond(_success({'card_store_url': 'javascript:alert(1)'}));
    await expectLater(api.getCardStore(_auth), throwsA(isA<XboardException>()));
  });

  test('redirects cannot forward Authorization or repeat a mutation', () async {
    adapter = _Adapter((_) async => ResponseBody.fromString('', 302, headers: {
          'location': ['https://unexpected.test.invalid/steal'],
        }));
    api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(api.close);
    await expectLater(
        api.redeemGift(_auth, _code),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'redirect_blocked')
              .having((e) => e.isUncertain, 'uncertain', isTrue),
        ));
    expect(adapter.requests, hasLength(1));
  });

  test(
      'network failure is sanitized, never retried, and redemption is uncertain',
      () async {
    adapter = _Adapter((request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
          message: 'secret $_auth $_code test-password',
        ));
    api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(api.close);
    try {
      await api.redeemGift(_auth, _code);
      fail('Expected a sanitized uncertain error');
    } on XboardException catch (error) {
      expect(error.isUncertain, isTrue);
      expect(error.toString(), isNot(contains(_auth)));
      expect(error.toString(), isNot(contains(_code)));
      expect(error.toString(), isNot(contains('test-password')));
    }
    expect(adapter.requests, hasLength(1));
    await expectLater(
        api.checkGift(_auth, _code),
        throwsA(
          isA<XboardException>()
              .having((e) => e.isUncertain, 'uncertain', isFalse),
        ));
    expect(adapter.requests, hasLength(2));
  });

  test('server failure during redemption is uncertain and hides raw body',
      () async {
    respond({'message': 'debug $_auth $_code', 'error': 'secret'}, status: 502);
    await expectLater(
        api.redeemGift(_auth, _code),
        throwsA(
          isA<XboardException>()
              .having((e) => e.isUncertain, 'uncertain', isTrue)
              .having((e) => e.toString(), 'sanitized', isNot(contains(_code))),
        ));
  });

  test('definite known gift rejection preserves safe feedback', () async {
    respond({'status': 'fail', 'message': '礼品卡已过期'}, status: 400);
    await expectLater(
        api.redeemGift(_auth, _code),
        throwsA(
          isA<XboardException>()
              .having((e) => e.message, 'message', '礼品卡已过期')
              .having((e) => e.isUncertain, 'uncertain', isFalse),
        ));
  });

  test('unauthorized response can trigger session invalidation', () async {
    respond({'status': 'fail', 'message': 'raw $_auth'}, status: 401);
    await expectLater(
        api.getAccount(_auth),
        throwsA(
          isA<XboardException>()
              .having((e) => e.isUnauthorized, 'unauthorized', isTrue)
              .having((e) => e.message, 'sanitized', isNot(contains(_auth))),
        ));
  });

  test('missing, mistyped and unsupported preview fields fail closed',
      () async {
    for (final data in [
      <String, Object?>{},
      {..._legacyPreview(), 'can_redeem': 'true'},
      {..._legacyPreview(), 'reward_preview': <String, Object?>{}},
      {..._legacyPreview(), 'purchase_preview': null},
      _legacyPreview(type: 5),
    ]) {
      respond(_success(data));
      await expectLater(
          api.checkGift(_auth, _code),
          throwsA(
            isA<XboardException>()
                .having((e) => e.code, 'code', 'invalid_response'),
          ));
    }
  });

  test('malformed success receipt is uncertain instead of false success',
      () async {
    respond(_success({
      'template_name': '测试卡',
      'rewards': {'unknown_reward': 500},
    }));
    await expectLater(
        api.redeemGift(_auth, _code),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'invalid_response')
              .having((e) => e.isUncertain, 'uncertain', isTrue),
        ));
  });

  test('missing history array is not turned into an empty history', () async {
    respond({
      'pagination': {
        'current_page': 1,
        'last_page': 1,
        'per_page': 15,
        'total': 0
      }
    });
    await expectLater(
        api.getGiftHistory(_auth), throwsA(isA<XboardException>()));
  });

  test('logout requires actual 204 acknowledgement and closes owned transport',
      () async {
    adapter = _Adapter((_) async => ResponseBody.fromString('', 204));
    api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
    await api.logout(_auth);
    expect(adapter.requests.single.path, '/api/v1/auth/logout');
    expect(adapter.requests.single.method, 'POST');
    api.close();
    expect(adapter.closed, isTrue);
  });
}
