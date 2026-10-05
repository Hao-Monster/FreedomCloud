import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/models/xboard.dart';

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

class XboardException implements Exception {
  const XboardException({
    required this.code,
    required this.message,
    this.statusCode,
    this.isUncertain = false,
  });

  final String code;
  final String message;
  final int? statusCode;
  final bool isUncertain;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'XboardException($code): $message';
}

/// Owns a dedicated Dio instance, so application interceptors cannot log secrets
/// or automatically repeat entitlement mutations.
class DioXboardApi implements XboardApi {
  DioXboardApi({Dio? dio, Uri? baseUri})
      : baseUri = _validateOrigin(baseUri ?? Uri.parse(_configuredOrigin)),
        _dio = dio ?? Dio() {
    if (dio == null) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          // Keep the application's proxy routing, but never its permissive
          // certificate override for account credentials and gift codes.
          final client = HttpClient()
            ..badCertificateCallback = ((_, __, ___) => false);
          return client;
        },
      );
    }
    _dio.interceptors.clear();
    _dio.options = BaseOptions(
      baseUrl: this.baseUri.origin,
      connectTimeout: const Duration(seconds: 15),
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
  }

  static const _configuredOrigin = String.fromEnvironment(
    'XBOARD_BASE_URL',
    defaultValue: 'https://fast.hjy.ca:8443',
  );

  @override
  final Uri baseUri;
  final Dio _dio;

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
            final prices = _planPrices(data['prices']);
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

  @override
  Future<Uri?> getCardStore(String authorization) => _request(
        '/api/v1/user/purchase-channels',
        authorization: authorization,
        parse: (body) {
          final url = _string(_data(body), 'card_store_url', allowEmpty: true);
          return url.isEmpty ? null : _httpsUrl(url);
        },
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
  void close() => _dio.close(force: true);

  Future<T> _request<T>(
    String path, {
    String method = 'GET',
    String? authorization,
    Map<String, Object?>? data,
    Map<String, Object?>? queryParameters,
    bool mutation = false,
    bool emptyResponse = false,
    required T Function(Object? body) parse,
  }) async {
    if (authorization != null && !_validAuthorization(authorization)) {
      throw const XboardException(
        code: 'invalid_authorization',
        message: '登录凭据无效，请重新登录',
        statusCode: 401,
      );
    }
    int? status;
    try {
      final response = await _dio.request<Object?>(
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
      status = response.statusCode;
      if (status == null) _invalid();
      if (status >= 300 && status < 400) {
        throw XboardException(
          code: 'redirect_blocked',
          message: '购买服务返回了重定向，请联系管理员核对服务地址',
          statusCode: status,
          isUncertain: mutation,
        );
      }
      if (status < 200 || status >= 300) {
        throw _serverError(response.data, status, mutation: mutation);
      }
      if (emptyResponse) {
        if (status != 204) _invalid();
      } else {
        final root = _object(response.data);
        if (root['status'] == 'fail') {
          throw _serverError(root, status, mutation: mutation);
        }
      }
      return parse(response.data);
    } on XboardException {
      rethrow;
    } on FormatException {
      throw XboardException(
        code: 'invalid_response',
        message: mutation ? '服务响应格式异常，兑换结果需要进一步确认' : '服务响应格式异常，请稍后重试',
        statusCode: status,
        isUncertain: mutation,
      );
    } on DioException catch (error) {
      // Never expose DioException: it can include request headers and bodies.
      final certificate = error.type == DioExceptionType.badCertificate;
      throw XboardException(
        code: certificate ? 'certificate_error' : 'connection_error',
        message: certificate
            ? '购买服务的安全证书无法验证'
            : mutation
                ? '连接中断，兑换结果需要进一步确认'
                : '无法连接购买服务，请检查网络后重试',
        statusCode: error.response?.statusCode,
        isUncertain: mutation && !certificate,
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

List<XboardPlanPrice> _planPrices(Object? value) {
  final prices = _object(value);
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

XboardException _serverError(Object? body, int status,
    {required bool mutation}) {
  if (status == 401) {
    return XboardException(
      code: 'unauthorized',
      message: '账号或密码错误，或登录已失效，请重新登录',
      statusCode: status,
    );
  }
  if (status == 403) {
    return XboardException(
      code: 'forbidden',
      message: '当前账号没有使用此功能的权限',
      statusCode: status,
    );
  }
  if (status == 429) {
    return XboardException(
      code: 'rate_limited',
      message: '操作过于频繁，请稍后重试',
      statusCode: status,
    );
  }
  if (status >= 500 || status == 408) {
    return XboardException(
      code: 'server_error',
      message: mutation ? '服务暂时异常，兑换结果需要进一步确认' : '购买服务暂时不可用，请稍后重试',
      statusCode: status,
      isUncertain: mutation,
    );
  }
  final data = body is Map<String, dynamic> ? body : null;
  final reason = _safeGiftReason(data?['message']);
  return XboardException(
    code: reason == null ? 'request_failed' : 'gift_card_rejected',
    message: reason ?? '请求未完成，请检查输入或稍后重试',
    statusCode: status,
  );
}
