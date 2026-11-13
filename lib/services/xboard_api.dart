import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/pre_request_transport.dart';

abstract class XboardApi {
  Uri get baseUri;
  Future<XboardPlanCatalog> getPlanCatalog();
  Future<String> login(String email, String password);
  Future<XboardAccount> getAccount(String authorization);
  Future<XboardSubscription> getSubscription(String authorization);
  Future<GiftPreview> checkGift(String authorization, String code);
  Future<GiftReceipt> redeemGift(String authorization, String code);
  Future<GiftHistoryPage> getGiftHistory(String authorization, {int page = 1});
  Future<Uri?> getCardStore(String authorization);
  Future<void> logout(String authorization);
  void close();
}

abstract interface class XboardExtendedApi {
  Future<XboardPurchaseChannels> getGuestPurchaseChannels();
  Future<XboardPurchaseChannels> getUserPurchaseChannels(String authorization);
  Future<String> register(String email, String password);
}

abstract interface class XboardPassportApi implements XboardExtendedApi {
  Future<XboardGuestAuthConfig> getGuestAuthConfig();
  Future<String> registerAccount({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  });
  Future<void> sendRegistrationEmailCode(String email);
  Future<void> sendPasswordResetEmailCode(String email);
  Future<void> confirmPasswordReset({
    required String email,
    required String emailCode,
    required String password,
  });
}

class XboardException implements Exception {
  const XboardException({
    required this.code,
    required this.message,
    this.statusCode,
    this.isUncertain = false,
    this.retryAfterSeconds,
  });

  final String code;
  final String message;
  final int? statusCode;
  final bool isUncertain;
  final int? retryAfterSeconds;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'XboardException($code): $message';
}

class _GuestCommConfigBundle {
  const _GuestCommConfigBundle({
    required this.channels,
    required this.authConfig,
    required this.fetchedAt,
  });

  final XboardPurchaseChannels channels;
  final XboardGuestAuthConfig authConfig;
  final DateTime fetchedAt;
}

/// Owns a dedicated Dio instance, so application interceptors cannot log secrets
/// or automatically repeat entitlement mutations.
class DioXboardApi implements XboardApi, XboardPassportApi {
  DioXboardApi({
    Dio? dio,
    Uri? baseUri,
    bool Function()? shouldFallbackToDirect,
  })  : baseUri = _validateOrigin(baseUri ?? Uri.parse(_configuredOrigin)),
        _ownsTransport = dio == null,
        _shouldFallbackToDirect = shouldFallbackToDirect,
        _dio = dio ?? Dio() {
    if (dio == null) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          // Keep the application's proxy routing, but never its permissive
          // certificate override for account credentials and gift codes.
          final client = HttpClient()
            ..badCertificateCallback = ((_, __, ___) => false);
          return wrapPreRequestHttpClient(client);
        },
      );
    }
    _dio.interceptors.clear();
    _dio.options = _buildBaseOptions(
      this.baseUri,
      connectTimeout: dio == null
          ? const Duration(seconds: 6)
          : const Duration(seconds: 15),
    );
  }

  static BaseOptions _buildBaseOptions(
    Uri origin, {
    Duration connectTimeout = const Duration(seconds: 15),
  }) =>
      BaseOptions(
        baseUrl: origin.origin,
        connectTimeout: connectTimeout,
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
        headers: {'Accept': Headers.jsonContentType},
      );

  static const _configuredOrigin = String.fromEnvironment(
    'XBOARD_BASE_URL',
    defaultValue: 'https://fast.hjy.ca:8443',
  );

  static const Duration _guestConfigTtl = Duration(seconds: 30);

  @override
  final Uri baseUri;
  final bool _ownsTransport;
  final bool Function()? _shouldFallbackToDirect;
  final Dio _dio;
  Dio? _directDio;
  bool _closed = false;
  _GuestCommConfigBundle? _guestConfigCache;
  Future<_GuestCommConfigBundle>? _guestConfigInFlight;

  Dio _ensureDirectDio() {
    if (_closed) {
      throw const XboardException(
        code: 'connection_error',
        message: '无法连接购买服务，请检查网络后重试',
      );
    }
    final existing = _directDio;
    if (existing != null) return existing;
    final direct = Dio(_buildBaseOptions(baseUri))
      ..interceptors.clear()
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => wrapPreRequestHttpClient(
          HttpClient()
            ..findProxy = ((_) => 'DIRECT')
            ..badCertificateCallback = ((_, __, ___) => false),
        ),
      );
    _directDio = direct;
    return direct;
  }

  @override
  Future<XboardPlanCatalog> getPlanCatalog() => _request(
        '/api/v1/guest/plans',
        parse: (body) {
          final root = _object(body);
          if (root['status'] != 'success') _invalid();
          final plans = <XboardPlanOffer>[];
          final ids = <int>{};
          for (final value in _list(root['data'])) {
            final data = _object(value);
            if (!_boolean(data, 'can_purchase')) continue;
            final priceData = _object(data['prices']);
            final prices = _planPrices(priceData);
            // A traffic reset is not a new subscription, and missing prices
            // must never become a zero-price offer.
            if (prices.isEmpty) continue;
            final id = _positive(data, 'id');
            if (!ids.add(id)) _invalid();
            plans.add(XboardPlanOffer(
              id: id,
              name: _string(data, 'name'),
              transferGiB: _nonnegative(data, 'transfer_enable'),
              speedLimit: data['speed_limit'] == null
                  ? null
                  : _nonnegative(data, 'speed_limit'),
              deviceLimit: data['device_limit'] == null
                  ? null
                  : _nonnegative(data, 'device_limit'),
              prices: prices,
              content: _optionalString(data, 'content') ?? '',
              tags: _planTags(data['tags']),
              resetTrafficMethod: data['reset_traffic_method'] == null
                  ? null
                  : _integer(data, 'reset_traffic_method'),
              capacityRemaining: data['capacity_remaining'] == null
                  ? null
                  : _nonnegative(data, 'capacity_remaining'),
              resetTrafficPrice: priceData['reset_traffic'] == null
                  ? null
                  : _nonnegative(priceData, 'reset_traffic'),
              hasSpeedLimit: data.containsKey('speed_limit'),
              hasDeviceLimit: data.containsKey('device_limit'),
              hasResetTrafficMethod: data.containsKey('reset_traffic_method'),
              hasCapacityRemaining: data.containsKey('capacity_remaining'),
            ));
          }
          return XboardPlanCatalog(plans: List.unmodifiable(plans));
        },
      );

  @override
  Future<String> login(String email, String password) => _request(
        '/api/v1/passport/auth/login',
        method: 'POST',
        data: {'email': email.trim(), 'password': password},
        parse: (body) {
          final result = _data(body);
          // The adjacent `token` property is a subscription token, not auth.
          final authorization = _string(result, 'auth_data');
          if (!_validAuthorization(authorization)) _invalid();
          return authorization;
        },
      );

  @override
  Future<String> register(String email, String password) => registerAccount(
        email: email,
        password: password,
      );

  @override
  Future<String> registerAccount({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) {
    final trimmedEmailCode = emailCode?.trim();
    final trimmedInviteCode = inviteCode?.trim();
    return _request(
      '/api/v1/passport/auth/register',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        if (trimmedEmailCode != null && trimmedEmailCode.isNotEmpty)
          'email_code': trimmedEmailCode,
        if (trimmedInviteCode != null && trimmedInviteCode.isNotEmpty)
          'invite_code': trimmedInviteCode,
      },
      nonIdempotentAfterSend: true,
      parse: (body) {
        final result = _data(body);
        final raw = _string(result, 'auth_data');
        final authorization = raw.startsWith('Bearer ') ? raw : 'Bearer $raw';
        if (!_validAuthorization(authorization)) _invalid();
        return authorization;
      },
    );
  }

  @override
  Future<void> sendRegistrationEmailCode(String email) =>
      _postWithLegacy404Fallback(
        primaryPath: '/api/v1/auth/registration-email/request',
        fallbackPath: '/api/v1/passport/comm/sendEmailVerify',
        data: {'email': email.trim()},
      );

  @override
  Future<void> sendPasswordResetEmailCode(String email) =>
      _postWithLegacy404Fallback(
        primaryPath: '/api/v1/auth/password-reset/request',
        fallbackPath: '/api/v1/passport/comm/sendEmailVerify',
        data: {'email': email.trim()},
      );

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String emailCode,
    required String password,
  }) =>
      _postWithLegacy404Fallback(
        primaryPath: '/api/v1/auth/password-reset/confirm',
        fallbackPath: '/api/v1/passport/auth/forget',
        data: {
          'email': email.trim(),
          'email_code': emailCode.trim(),
          'password': password,
        },
      );

  Future<void> _postWithLegacy404Fallback({
    required String primaryPath,
    required String fallbackPath,
    required Map<String, Object?> data,
  }) async {
    Future<void> send(String path) => _request<void>(
          path,
          method: 'POST',
          data: data,
          mutation: true,
          allowEmpty204: true,
          parse: _parseAcknowledgeResponse,
        );

    try {
      await send(primaryPath);
    } on XboardException catch (error) {
      if (error.statusCode != 404) rethrow;
      await send(fallbackPath);
    }
  }

  @override
  Future<XboardAccount> getAccount(String authorization) => _request(
        '/api/v1/auth/session',
        authorization: authorization,
        parse: (body) {
          final result = _data(body);
          return XboardAccount(
            id: _positive(result, 'id'),
            email: _string(result, 'email'),
            isDistributor: _boolean(result, 'is_distributor'),
          );
        },
      );

  @override
  Future<XboardSubscription> getSubscription(String authorization) => _request(
        '/api/v1/subscription',
        authorization: authorization,
        parse: (body) {
          final result = _data(body);
          _requireKeys(result, ['plan_id', 'plan', 'expired_at']);
          final planId = _optionalPositive(result, 'plan_id');
          final plan = result['plan'] == null ? null : _object(result['plan']);
          return XboardSubscription(
            planId: planId,
            planName: plan == null ? null : _string(plan, 'name'),
            valid: _boolean(result, 'subscription_valid'),
            url: _httpsUrl(_string(result, 'subscribe_url')),
            upload: _nonnegative(result, 'u'),
            download: _nonnegative(result, 'd'),
            total: _nonnegative(result, 'transfer_enable'),
            expiresAt: _optionalDate(result, 'expired_at'),
            balance: result['balance'] == null
                ? null
                : _nonnegative(result, 'balance'),
          );
        },
      );

  @override
  Future<GiftPreview> checkGift(String authorization, String code) => _request(
        '/api/v1/user/gift-card/check',
        method: 'POST',
        authorization: authorization,
        data: {'code': code.trim()},
        parse: (body) {
          final result = _data(body);
          final codeInfo = _object(result['code_info']);
          final modern = result.containsKey('template');
          final template =
              _object(modern ? result['template'] : codeInfo['template']);
          final type = _giftType(template, 'type');
          final canRedeem = _boolean(result, 'can_redeem');
          final rewards = _reward(result['reward_preview']);
          final preview = result['purchase_preview'] == null
              ? null
              : _purchasePreview(_object(result['purchase_preview']));
          if (type == 4 &&
              (rewards.purchaseSnapshot == null ||
                  (canRedeem && preview == null))) {
            _invalid();
          }
          return GiftPreview(
            codeId: modern
                ? _positive(codeInfo, 'id')
                : _optionalPositive(codeInfo, 'code_id'),
            type: type,
            name: _string(template, 'name'),
            canRedeem: canRedeem,
            reason: canRedeem
                ? null
                : _safeGiftReason(result['reason']) ?? '当前账号不满足兑换条件',
            rewards: rewards,
            purchasePreview: preview,
          );
        },
      );

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) => _request(
        '/api/v1/user/gift-card/redeem',
        method: 'POST',
        authorization: authorization,
        data: {'code': code.trim()},
        mutation: true,
        parse: (body) {
          final result = _data(body);
          final usage =
              result['usage'] == null ? null : _object(result['usage']);
          return GiftReceipt(
            templateName: _string(result, 'template_name'),
            rewards: _reward(result['rewards']),
            orderTradeNo: _optionalString(usage ?? result, 'order_trade_no'),
            codeId: _optionalPositive(usage ?? result, 'code_id'),
          );
        },
      );

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization, {int page = 1}) {
    if (page < 1 || page > 1000000) {
      throw const XboardException(code: 'invalid_page', message: '兑换记录页码无效');
    }
    return _request(
      '/api/v1/user/gift-card/history',
      authorization: authorization,
      queryParameters: {'page': page},
      parse: (body) {
        final root = _object(body);
        final legacy = root.containsKey('pagination');
        final result = legacy ? root : _data(body);
        final pagination = legacy ? _object(root['pagination']) : result;
        final entries = _list(legacy ? root['data'] : result['items'])
            .map((item) => _historyEntry(_object(item), legacy: legacy))
            .toList();
        final total = _nonnegative(pagination, 'total');
        final current = _positive(pagination, legacy ? 'current_page' : 'page');
        final size = _positive(pagination, legacy ? 'per_page' : 'page_size');
        final last = legacy
            ? _positive(pagination, 'last_page')
            : ((total + size - 1) ~/ size).clamp(1, 1000000);
        if (entries.length > size ||
            total < entries.length ||
            current != page) {
          _invalid();
        }
        return GiftHistoryPage(
          entries: entries,
          page: current,
          lastPage: last,
          total: total,
        );
      },
    );
  }

  Future<_GuestCommConfigBundle> _loadGuestCommConfig() {
    if (_closed) {
      return _request<_GuestCommConfigBundle>(
        '/api/v1/guest/comm/config',
        parse: (_) => _invalid(),
      );
    }
    final cached = _guestConfigCache;
    if (cached != null) {
      if (DateTime.now().difference(cached.fetchedAt) < _guestConfigTtl) {
        return Future<_GuestCommConfigBundle>.value(cached);
      }
      _guestConfigCache = null;
    }
    final inFlight = _guestConfigInFlight;
    if (inFlight != null) return inFlight;

    late final Future<_GuestCommConfigBundle> future;
    future = _request<_GuestCommConfigBundle>(
      '/api/v1/guest/comm/config',
      parse: (body) {
        final data = _data(body);
        return _GuestCommConfigBundle(
          channels: _parsePurchaseChannels(data),
          authConfig: _parseGuestAuthConfig(data),
          fetchedAt: DateTime.now(),
        );
      },
    ).then((bundle) {
      if (!_closed) {
        _guestConfigCache = bundle;
      }
      return bundle;
    }).whenComplete(() {
      if (identical(_guestConfigInFlight, future)) {
        _guestConfigInFlight = null;
      }
    });
    _guestConfigInFlight = future;
    return future;
  }

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async =>
      (await _loadGuestCommConfig()).channels;

  @override
  Future<XboardGuestAuthConfig> getGuestAuthConfig() async =>
      (await _loadGuestCommConfig()).authConfig;

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
    String authorization,
  ) =>
      _request(
        '/api/v1/user/purchase-channels',
        authorization: authorization,
        parse: (body) => _parsePurchaseChannels(_data(body)),
      );

  @override
  Future<Uri?> getCardStore(String authorization) => _request(
        '/api/v1/user/purchase-channels',
        authorization: authorization,
        parse: (body) => _optionalHttpsField(_data(body), 'card_store_url'),
      );

  @override
  Future<void> logout(String authorization) => _request<void>(
        '/api/v1/auth/logout',
        method: 'POST',
        authorization: authorization,
        mutation: true,
        emptyResponse: true,
        parse: (_) {},
      );

  @override
  void close() {
    _closed = true;
    _guestConfigCache = null;
    _guestConfigInFlight = null;
    _dio.close(force: true);
    final direct = _directDio;
    _directDio = null;
    direct?.close(force: true);
  }

  bool _canFallbackToDirect(DioException error, {required bool mutation}) {
    if (_closed ||
        mutation ||
        !_ownsTransport ||
        !(_shouldFallbackToDirect?.call() ?? false)) {
      return false;
    }
    return isPreRequestDioFailure(error);
  }

  Future<Response<Object?>> _performRequest(
    Dio client,
    String path, {
    required String method,
    String? authorization,
    Map<String, Object?>? data,
    Map<String, Object?>? queryParameters,
  }) =>
      client.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          followRedirects: false,
          maxRedirects: 0,
          headers: {
            if (authorization != null) 'Authorization': authorization,
          },
        ),
      );

  Future<T> _request<T>(
    String path, {
    String method = 'GET',
    String? authorization,
    Map<String, Object?>? data,
    Map<String, Object?>? queryParameters,
    bool mutation = false,
    bool nonIdempotentAfterSend = false,
    bool emptyResponse = false,
    bool allowEmpty204 = false,
    required T Function(Object? body) parse,
  }) async {
    if (authorization != null && !_validAuthorization(authorization)) {
      throw const XboardException(
        code: 'invalid_authorization',
        message: '登录凭据无效，请重新登录',
        statusCode: 401,
      );
    }
    if (_closed) {
      throw const XboardException(
        code: 'connection_error',
        message: '无法连接购买服务，请检查网络后重试',
      );
    }
    int? status;
    final uncertainAfterSend = mutation || nonIdempotentAfterSend;
    try {
      Response<Object?> response;
      try {
        response = await _performRequest(
          _dio,
          path,
          method: method,
          authorization: authorization,
          data: data,
          queryParameters: queryParameters,
        );
      } on DioException catch (error) {
        if (!_canFallbackToDirect(error, mutation: mutation)) rethrow;
        response = await _performRequest(
          _ensureDirectDio(),
          path,
          method: method,
          authorization: authorization,
          data: data,
          queryParameters: queryParameters,
        );
      }
      status = response.statusCode;
      if (status == null) _invalid();
      final retryAfter = _parseRetryAfterSeconds(response.headers);
      if (status >= 300 && status < 400) {
        throw XboardException(
          code: 'redirect_blocked',
          message: '购买服务返回了重定向，请联系管理员核对服务地址',
          statusCode: status,
          isUncertain: uncertainAfterSend,
          retryAfterSeconds: retryAfter,
        );
      }
      if (status < 200 || status >= 300) {
        throw _serverError(
          response.data,
          status,
          mutation: uncertainAfterSend,
          retryAfterSeconds: retryAfter,
        );
      }
      if (emptyResponse) {
        if (status != 204) _invalid();
      } else if (allowEmpty204 && status == 204) {
        return parse(null);
      } else {
        final root = _object(response.data);
        if (root['status'] == 'fail') {
          throw _serverError(
            root,
            status,
            mutation: uncertainAfterSend,
            retryAfterSeconds: retryAfter,
          );
        }
      }
      return parse(response.data);
    } on XboardException {
      rethrow;
    } on FormatException {
      throw XboardException(
        code: 'invalid_response',
        message: uncertainAfterSend ? '服务响应格式异常，兑换结果需要进一步确认' : '服务响应格式异常，请稍后重试',
        statusCode: status,
        isUncertain: uncertainAfterSend,
      );
    } on DioException catch (error) {
      // Never expose DioException: it can include request headers and bodies.
      final certificate = isCertificateDioFailure(error);
      final uncertain = !certificate &&
          (mutation ||
              (nonIdempotentAfterSend && !isPreRequestDioFailure(error)));
      throw XboardException(
        code: certificate ? 'certificate_error' : 'connection_error',
        message: certificate
            ? '购买服务的安全证书无法验证'
            : uncertain
                ? '连接中断，请确认操作是否已生效后再重试'
                : '无法连接购买服务，请检查网络后重试',
        statusCode: error.response?.statusCode,
        isUncertain: uncertain,
        retryAfterSeconds: _parseRetryAfterSeconds(error.response?.headers),
      );
    }
  }
}

Uri _validateOrigin(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw ArgumentError('XBOARD_BASE_URL must be an HTTPS origin');
  }
  return Uri.parse(uri.origin);
}

const _catalogPeriods = [
  'monthly',
  'quarterly',
  'half_yearly',
  'yearly',
  'two_yearly',
  'three_yearly',
  'onetime',
];

List<String> _planTags(Object? value) {
  if (value == null) return const [];
  return List.unmodifiable(_list(value).map((tag) {
    if (tag is! String) _invalid();
    return tag;
  }));
}

List<XboardPlanPrice> _planPrices(Map<String, Object?> prices) {
  for (final entry in prices.entries) {
    final amount = entry.value;
    if (amount == null) continue;
    if ((!_catalogPeriods.contains(entry.key) &&
            entry.key != 'reset_traffic') ||
        amount is! int ||
        amount < 0 ||
        amount > 9000000000000000) {
      _invalid();
    }
  }
  return List.unmodifiable([
    for (final period in _catalogPeriods)
      if (prices[period] != null)
        XboardPlanPrice(period: period, amount: _nonnegative(prices, period)),
  ]);
}

bool _validAuthorization(String value) =>
    RegExp(r'^Bearer [A-Za-z0-9_-]+$').hasMatch(value);

Never _invalid() => throw const FormatException('Invalid Xboard response');

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, dynamic>) _invalid();
  return value.cast<String, Object?>();
}

List<Object?> _list(Object? value) {
  if (value is! List) _invalid();
  return value.cast<Object?>();
}

Map<String, Object?> _data(Object? body) {
  final root = _object(body);
  if (root['status'] != 'success') _invalid();
  return _object(root['data']);
}

void _requireKeys(Map<String, Object?> data, List<String> keys) {
  if (keys.any((key) => !data.containsKey(key))) _invalid();
}

String _string(Map<String, Object?> data, String key,
    {bool allowEmpty = false}) {
  final value = data[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) _invalid();
  return value;
}

String? _optionalString(Map<String, Object?> data, String key) {
  if (data[key] == null) return null;
  final value = _string(data, key, allowEmpty: true);
  return value.isEmpty ? null : value;
}

int _integer(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! int) _invalid();
  return value;
}

int _nonnegative(Map<String, Object?> data, String key) {
  final value = _integer(data, key);
  if (value < 0) _invalid();
  return value;
}

int _positive(Map<String, Object?> data, String key) {
  final value = _integer(data, key);
  if (value < 1) _invalid();
  return value;
}

int? _optionalPositive(Map<String, Object?> data, String key) =>
    data[key] == null ? null : _positive(data, key);

int _optionalNonnegative(Map<String, Object?> data, String key) =>
    data.containsKey(key) ? _nonnegative(data, key) : 0;

bool _boolean(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! bool) _invalid();
  return value;
}

int _giftType(Map<String, Object?> data, String key) {
  final type = _integer(data, key);
  if (type < 1 || type > 4) _invalid();
  return type;
}

DateTime _date(Object? value) {
  if (value is int && value >= 0 && value <= 253402300799) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null && date.isUtc) return date;
  }
  _invalid();
}

DateTime? _optionalDate(Map<String, Object?> data, String key) =>
    data[key] == null ? null : _date(data[key]);

Uri _httpsUrl(String value) {
  final url = Uri.tryParse(value);
  if (url == null ||
      url.scheme != 'https' ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty) {
    _invalid();
  }
  return url;
}

GiftReward _reward(Object? value) {
  final data = _object(value);
  const fields = {
    'balance',
    'transfer_enable',
    'expire_days',
    'device_limit',
    'reset_package',
    'plan_id',
    'plan_validity_days',
    'purchase_period',
    'purchase_snapshot',
  };
  if (data.keys.any((key) => !fields.contains(key))) _invalid();
  final result = GiftReward(
    balance: _optionalNonnegative(data, 'balance'),
    transferEnable: _optionalNonnegative(data, 'transfer_enable'),
    expireDays: _optionalNonnegative(data, 'expire_days'),
    deviceLimit: _optionalNonnegative(data, 'device_limit'),
    resetTraffic:
        data.containsKey('reset_package') && _boolean(data, 'reset_package'),
    planId: _optionalPositive(data, 'plan_id'),
    planValidityDays: _optionalNonnegative(data, 'plan_validity_days'),
    purchasePeriod: _optionalString(data, 'purchase_period'),
    purchaseSnapshot: data['purchase_snapshot'] == null
        ? null
        : _purchaseSnapshot(_object(data['purchase_snapshot'])),
  );
  // All backend reward fields use omitempty. A valid fractional multiplier
  // can round small rewards down to zero, so an explicit {} is meaningful.
  return result;
}

GiftPurchaseSnapshot _purchaseSnapshot(Map<String, Object?> data) =>
    GiftPurchaseSnapshot(
      planId: _positive(data, 'plan_id'),
      planName: _string(data, 'plan_name'),
      period: _string(data, 'period'),
      transferEnable: _positive(data, 'transfer_enable'),
      speedLimit: _nonnegative(data, 'speed_limit'),
      deviceLimit: _nonnegative(data, 'device_limit'),
    );

GiftPurchasePreview _purchasePreview(Map<String, Object?> data) {
  _requireKeys(data, ['expires_before', 'expires_after']);
  return GiftPurchasePreview(
    transferBefore: _nonnegative(data, 'transfer_before'),
    transferAfter: _nonnegative(data, 'transfer_after'),
    usedTraffic: _nonnegative(data, 'used_traffic'),
    expiresBefore: _optionalDate(data, 'expires_before'),
    expiresAfter: _optionalDate(data, 'expires_after'),
    renewal: _boolean(data, 'renewal'),
  );
}

GiftHistoryEntry _historyEntry(Map<String, Object?> data,
    {required bool legacy}) {
  final code = _string(data, 'code');
  final prefix = code.split('*').first;
  // The server used to expose short codes unchanged. Always mask locally too.
  final masked = '${prefix.substring(0, prefix.length.clamp(0, 4))}****';
  return GiftHistoryEntry(
    id: _positive(data, 'id'),
    codeId: _optionalPositive(data, 'code_id'),
    maskedCode: masked,
    templateName: _string(data, 'template_name'),
    rewards: _reward(data[legacy ? 'rewards_given' : 'rewards']),
    usedAt: _date(data[legacy ? 'created_at' : 'used_at']),
    orderTradeNo: _optionalString(data, 'order_trade_no'),
    type:
        data['template_type'] == null ? null : _giftType(data, 'template_type'),
  );
}

const _giftReasons = {
  '当前套餐与购买兑换码不一致，兑换码未消耗',
  '当前套餐购买模式不一致，不能在按周期和按流量之间转换',
  '请先取消待支付订单，或等待处理中订单完成后再兑换',
  '已达到该礼品卡的使用次数限制',
  '礼品卡仍在冷却期',
  '已有有效套餐，无法使用套餐礼品卡',
  '不满足礼品卡使用条件',
  '礼品卡已过期',
  '礼品卡已无剩余次数',
  '礼品卡已禁用',
  '礼品卡无效',
};

String? _safeGiftReason(Object? message) =>
    message is String && _giftReasons.contains(message) ? message : null;

const _preservedAuthErrorCodes = {
  'email_exists',
  'email_domain_not_allowed',
  'gmail_alias_not_allowed',
  'registration_closed',
  'invitation_code_required',
  'invitation_code_invalid',
  'invitation_unavailable',
  'registration_email_invalid',
  'registration_email_locked',
  'registration_email_cooldown',
  'registration_email_rate_limited',
  'registration_email_disabled',
  'password_reset_invalid',
  'password_reset_locked',
  'password_reset_cooldown',
  'password_reset_rate_limited',
  'passport_email_cooldown',
  'passport_email_rate_limited',
  'mail_unavailable',
};

int? _parseRetryAfterSeconds(Headers? headers) {
  final raw = headers?.value('retry-after')?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

void _parseAcknowledgeResponse(Object? body) {
  if (body == null) return;
  final root = _object(body);
  final status = root['status'];
  if (status != null) {
    if (status != 'success') _invalid();
    return;
  }
  if (!root.containsKey('data')) _invalid();
}

XboardException _serverError(
  Object? body,
  int status, {
  required bool mutation,
  int? retryAfterSeconds,
}) {
  if (status == 401) {
    return XboardException(
      code: 'unauthorized',
      message: '账号或密码错误，或登录已失效，请重新登录',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  if (status == 403) {
    return XboardException(
      code: 'forbidden',
      message: '当前账号没有使用此功能的权限',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  final data = body is Map<String, dynamic> ? body : null;
  final errorObj = data?['error'] is Map<String, dynamic>
      ? data!['error'] as Map<String, dynamic>
      : null;
  final backendCode = errorObj?['code'];
  final fields = errorObj?['fields'] is Map<String, dynamic>
      ? errorObj!['fields'] as Map<String, dynamic>
      : null;
  if (backendCode == 'captcha_invalid' ||
      backendCode == 'captcha_unavailable' ||
      backendCode == 'captcha_required' ||
      backendCode == 'captcha_failed') {
    return XboardException(
      code: 'register_web_required',
      message: '',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  if (backendCode == 'validation_failed' &&
      (fields?.containsKey('email_code') ?? false)) {
    return XboardException(
      code: 'registration_email_invalid',
      message: '',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  if (backendCode is String && _preservedAuthErrorCodes.contains(backendCode)) {
    return XboardException(
      code: backendCode,
      message: '',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  if (status == 429) {
    return XboardException(
      code: 'rate_limited',
      message: '操作过于频繁，请稍后重试',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  if (status >= 500 || status == 408) {
    return XboardException(
      code: 'server_error',
      message: mutation ? '服务暂时异常，兑换结果需要进一步确认' : '购买服务暂时不可用，请稍后重试',
      statusCode: status,
      isUncertain: mutation,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  final reason = _safeGiftReason(data?['message']);
  return XboardException(
    code: reason == null ? 'request_failed' : 'gift_card_rejected',
    message: reason ?? '请求未完成，请检查输入或稍后重试',
    statusCode: status,
    retryAfterSeconds: retryAfterSeconds,
  );
}

Uri? _optionalHttpsField(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw == null) return null;
  if (raw is! String) _invalid();
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : _httpsUrl(trimmed);
}

Uri? _safeOptionalChannelHttpsUrl(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw == null) return null;
  if (raw is! String) _invalid();
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.hasFragment) {
    return null;
  }
  return parsed;
}

bool _optionalFlag(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw == null) return false;
  if (raw is bool) return raw;
  if (raw is int && (raw == 0 || raw == 1)) return raw == 1;
  _invalid();
}

List<String> _parseEmailWhitelist(Object? raw) {
  if (raw is! List) return const [];
  final result = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    var domain = item.trim().toLowerCase();
    while (domain.startsWith('@')) {
      domain = domain.substring(1).trim();
    }
    if (domain.isNotEmpty) {
      result.add(domain);
    }
  }
  return List.unmodifiable(result);
}

XboardGuestAuthConfig _parseGuestAuthConfig(Map<String, Object?> data) {
  final rawCaptchaType = data['captcha_type'];
  final captchaType = rawCaptchaType is String && rawCaptchaType.trim().isNotEmpty
      ? rawCaptchaType.trim()
      : null;
  final rawTos = data['tos_url'];
  final tosUrl = rawTos is String
      ? _safeOptionalChannelHttpsUrl(data, 'tos_url')
      : null;
  return XboardGuestAuthConfig(
    isEmailVerify: _optionalFlag(data, 'is_email_verify'),
    isInviteForce: _optionalFlag(data, 'is_invite_force'),
    emailWhitelistSuffix: _parseEmailWhitelist(data['email_whitelist_suffix']),
    isCaptcha: _optionalFlag(data, 'is_captcha'),
    captchaType: captchaType,
    tosUrl: tosUrl,
  );
}

XboardPurchaseChannels _parsePurchaseChannels(Map<String, Object?> data) =>
    XboardPurchaseChannels(
      cardStoreUrl: _safeOptionalChannelHttpsUrl(data, 'card_store_url'),
      cardStore50gUrl: _safeOptionalChannelHttpsUrl(data, 'card_store_50g_url'),
      cardStore100gUrl:
          _safeOptionalChannelHttpsUrl(data, 'card_store_100g_url'),
      cardStore200gUrl:
          _safeOptionalChannelHttpsUrl(data, 'card_store_200g_url'),
      cardStore500gUrl:
          _safeOptionalChannelHttpsUrl(data, 'card_store_500g_url'),
      chatwootBaseUrl: _safeOptionalChannelHttpsUrl(data, 'chatwoot_base_url'),
      chatwootWebsiteToken: _optionalString(data, 'chatwoot_website_token'),
    );
