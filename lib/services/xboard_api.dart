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

abstract interface class XboardRefreshableGuestConfigApi {
  void invalidateGuestConfigCache();
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
    required this.fetchedElapsed,
  });

  final XboardPurchaseChannels channels;
  final XboardGuestAuthConfig authConfig;
  final Duration fetchedElapsed;
}

class _PreRequestSocketException implements SocketException {
  const _PreRequestSocketException(this.cause);

  final SocketException cause;

  @override
  String get message => cause.message;

  @override
  OSError? get osError => cause.osError;

  @override
  InternetAddress? get address => cause.address;

  @override
  int? get port => cause.port;

  @override
  String toString() => cause.toString();
}

class _OpenUrlSocketTaggingHttpClient implements HttpClient {
  _OpenUrlSocketTaggingHttpClient(this._inner);

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

  Future<HttpClientRequest> _tagSocketFailure(
    Future<HttpClientRequest> Function() op,
  ) async {
    try {
      return await op();
    } on SocketException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _PreRequestSocketException(error),
        stackTrace,
      );
    }
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _tagSocketFailure(() => _inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _tagSocketFailure(() => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _tagSocketFailure(() => _inner.get(host, port, path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _tagSocketFailure(() => _inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _tagSocketFailure(() => _inner.post(host, port, path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _tagSocketFailure(() => _inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _tagSocketFailure(() => _inner.put(host, port, path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _tagSocketFailure(() => _inner.putUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _tagSocketFailure(() => _inner.delete(host, port, path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _tagSocketFailure(() => _inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _tagSocketFailure(() => _inner.patch(host, port, path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _tagSocketFailure(() => _inner.patchUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _tagSocketFailure(() => _inner.head(host, port, path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _tagSocketFailure(() => _inner.headUrl(url));

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

/// Owns a dedicated Dio instance, so application interceptors cannot log secrets
/// or automatically repeat entitlement mutations.
class DioXboardApi
    implements
        XboardApi,
        XboardPassportApi,
        XboardRefreshableGuestConfigApi {
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
        createHttpClient: _createStrictHttpClient,
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
  static const String _authUncertainMessage =
      '请求状态未确认，请检查邮箱或尝试登录，切勿盲目重复提交';
  static const String _giftUncertainMessage = '服务暂时异常，兑换结果需要进一步确认';

  @override
  final Uri baseUri;
  final bool _ownsTransport;
  final bool Function()? _shouldFallbackToDirect;
  final Dio _dio;
  Dio? _directDio;
  bool _closed = false;
  final Stopwatch _guestConfigClock = Stopwatch()..start();
  _GuestCommConfigBundle? _guestConfigCache;
  Future<_GuestCommConfigBundle>? _guestConfigInFlight;
  int _guestConfigGeneration = 0;

  static HttpClient _createStrictHttpClient({bool forceDirect = false}) {
    // Keep proxy routing unless forcing direct fallback, but never adopt the
    // application's permissive certificate override for credentials/gifts.
    final client = HttpClient()
      ..badCertificateCallback = ((_, __, ___) => false);
    if (forceDirect) {
      client.findProxy = (_) => 'DIRECT';
    }
    return wrapPreRequestHttpClient(
      _OpenUrlSocketTaggingHttpClient(client),
    );
  }

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
        createHttpClient: () => _createStrictHttpClient(forceDirect: true),
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
        nonIdempotentAfterSend: true,
        uncertainMessage: _authUncertainMessage,
        parseWithStatus: (status, body) {
          if (status == 202) {
            throw const XboardException(
              code: 'purchase_account_unsupported',
              message: '该账号已开启管理员二次验证，请在网页端登录',
              statusCode: 202,
            );
          }
          final result = _data(body);
          if (result['mfa_required'] == true) {
            throw XboardException(
              code: 'purchase_account_unsupported',
              message: '该账号已开启管理员二次验证，请在网页端登录',
              statusCode: status,
            );
          }
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
      uncertainMessage: _authUncertainMessage,
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
          uncertainMessage: _authUncertainMessage,
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
        uncertainMessage: _giftUncertainMessage,
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
  void invalidateGuestConfigCache() {
    _guestConfigGeneration++;
    _guestConfigCache = null;
    _guestConfigInFlight = null;
  }

  Future<_GuestCommConfigBundle> _loadGuestCommConfig({
    bool forceRefresh = false,
  }) {
    if (_closed) {
      return _request<_GuestCommConfigBundle>(
        '/api/v1/guest/comm/config',
        parse: (_) => _invalid(),
      );
    }
    if (forceRefresh) {
      invalidateGuestConfigCache();
    } else {
      final cached = _guestConfigCache;
      if (cached != null) {
        if (_guestConfigClock.elapsed - cached.fetchedElapsed <
            _guestConfigTtl) {
          return Future<_GuestCommConfigBundle>.value(cached);
        }
        _guestConfigCache = null;
      }
      final inFlight = _guestConfigInFlight;
      if (inFlight != null) return inFlight;
    }

    final generation = _guestConfigGeneration;
    late final Future<_GuestCommConfigBundle> future;
    future = _request<_GuestCommConfigBundle>(
      '/api/v1/guest/comm/config',
      parse: (body) {
        final data = _data(body);
        return _GuestCommConfigBundle(
          channels: _parsePurchaseChannels(data),
          authConfig: _parseGuestAuthConfig(data),
          fetchedElapsed: _guestConfigClock.elapsed,
        );
      },
    ).then((bundle) {
      if (!_closed && _guestConfigGeneration == generation) {
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
  Future<XboardPurchaseChannels> getGuestPurchaseChannels({
    bool forceRefresh = false,
  }) async =>
      (await _loadGuestCommConfig(forceRefresh: forceRefresh)).channels;

  @override
  Future<XboardGuestAuthConfig> getGuestAuthConfig({
    bool forceRefresh = false,
  }) async =>
      (await _loadGuestCommConfig(forceRefresh: forceRefresh)).authConfig;

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
        uncertainMessage: '退出状态未确认，请刷新后重试',
        parse: (_) {},
      );

  @override
  void close() {
    _closed = true;
    invalidateGuestConfigCache();
    _dio.close(force: true);
    final direct = _directDio;
    _directDio = null;
    direct?.close(force: true);
  }

  bool _isCertificateFailure(DioException error) {
    if (isCertificateDioFailure(error)) return true;
    final cause = unwrapPreRequestTransportError(error.error);
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

  bool _isNonIdempotentPreRequestError(DioException error) =>
      error.response == null &&
      (error.error is PreRequestTransportException ||
          error.error is _PreRequestSocketException ||
          error.type == DioExceptionType.connectionTimeout);

  bool _canFallbackToDirect(
    DioException error, {
    required bool mutation,
    bool nonIdempotentAfterSend = false,
  }) {
    if (_closed ||
        mutation ||
        !_ownsTransport ||
        !(_shouldFallbackToDirect?.call() ?? false)) {
      return false;
    }
    if (_isCertificateFailure(error)) return false;
    if (nonIdempotentAfterSend) {
      return _isNonIdempotentPreRequestError(error);
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
    String? uncertainMessage,
    T Function(Object? body)? parse,
    T Function(int status, Object? body)? parseWithStatus,
  }) async {
    assert(
      parse != null || parseWithStatus != null,
      'Either parse or parseWithStatus must be provided.',
    );
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
        if (!_canFallbackToDirect(
          error,
          mutation: mutation,
          nonIdempotentAfterSend: nonIdempotentAfterSend,
        )) {
          rethrow;
        }
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
          uncertainMessage: uncertainMessage,
        );
      }
      if (emptyResponse) {
        if (status != 204) _invalid();
      } else if (allowEmpty204 && status == 204) {
        return parseWithStatus != null
            ? parseWithStatus(status, null)
            : parse!(null);
      } else {
        final root = _object(response.data);
        if (root['status'] == 'fail') {
          throw _serverError(
            root,
            status,
            mutation: uncertainAfterSend,
            retryAfterSeconds: retryAfter,
            uncertainMessage: uncertainMessage,
          );
        }
      }
      return parseWithStatus != null
          ? parseWithStatus(status, response.data)
          : parse!(response.data);
    } on XboardException {
      rethrow;
    } on FormatException {
      throw XboardException(
        code: 'invalid_response',
        message: uncertainAfterSend
            ? (uncertainMessage ?? '服务响应格式异常，请确认操作是否已生效后再重试')
            : '服务响应格式异常，请稍后重试',
        statusCode: status,
        isUncertain: uncertainAfterSend,
      );
    } on DioException catch (error) {
      // Never expose DioException: it can include request headers and bodies.
      final certificate = _isCertificateFailure(error);
      final preRequest = nonIdempotentAfterSend
          ? _isNonIdempotentPreRequestError(error)
          : isPreRequestDioFailure(error);
      final uncertain =
          !certificate && (mutation || (nonIdempotentAfterSend && !preRequest));
      throw XboardException(
        code: certificate ? 'certificate_error' : 'connection_error',
        message: certificate
            ? '购买服务的安全证书无法验证'
            : uncertain
                ? (uncertainMessage ?? '连接中断，请确认操作是否已生效后再重试')
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
  'registration_rate_limited',
  'registration_busy',
  'registration_ip_limited',
  'password_reset_invalid',
  'password_reset_locked',
  'password_reset_cooldown',
  'password_reset_rate_limited',
  'password_reset_busy',
  'passport_email_cooldown',
  'passport_email_rate_limited',
  'login_rate_limited',
  'mail_unavailable',
  'invalid_origin',
};

const _preservedAuthErrorMessages = {
  'registration_rate_limited': '注册请求过于频繁，请稍后重试',
  'registration_busy': '注册服务繁忙，请稍后重试',
  'registration_ip_limited': '当前网络注册过于频繁，请稍后重试',
  'password_reset_busy': '重置服务繁忙，请稍后重试',
  'login_rate_limited': '登录尝试过多，请稍后重试',
  'invalid_origin': '请求来源不受信任，请核对服务地址',
};

int? _parseRetryAfterSeconds(Headers? headers) {
  final raw = headers?.value('retry-after')?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = int.tryParse(raw);
  if (parsed != null) {
    if (parsed <= 0) return null;
    return parsed > 86400 ? 86400 : parsed;
  }
  try {
    final target = HttpDate.parse(raw).toUtc();
    final diff = target.difference(DateTime.now().toUtc());
    if (diff <= Duration.zero) return null;
    final seconds = (diff.inMilliseconds + 999) ~/ 1000;
    return seconds > 86400 ? 86400 : seconds;
  } on Exception {
    return null;
  }
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

XboardException? _validationError({
  required int status,
  required Object? backendCode,
  required Map<Object?, Object?>? fields,
  required Map<Object?, Object?>? legacyErrors,
  int? retryAfterSeconds,
}) {
  if (status != 422 && backendCode != 'validation_failed') return null;

  String? fieldText(String key) {
    final raw = fields?[key] ?? legacyErrors?[key];
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is String && item.trim().isNotEmpty) {
          return item.trim();
        }
      }
    }
    return null;
  }

  final hasEmail = (fields?.containsKey('email') ?? false) ||
      (legacyErrors?.containsKey('email') ?? false);
  final hasPassword = (fields?.containsKey('password') ?? false) ||
      (legacyErrors?.containsKey('password') ?? false) ||
      (fields?.containsKey('password_confirmation') ?? false) ||
      (legacyErrors?.containsKey('password_confirmation') ?? false);
  final hasEmailCode = (fields?.containsKey('email_code') ?? false) ||
      (legacyErrors?.containsKey('email_code') ?? false);
  final hasInviteCode = (fields?.containsKey('invite_code') ?? false) ||
      (legacyErrors?.containsKey('invite_code') ?? false);

  if (hasEmailCode && !hasEmail && !hasPassword && !hasInviteCode) {
    return XboardException(
      code: 'registration_email_invalid',
      message: '邮箱验证码有误，请重新核对',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  final inviteText = (fieldText('invite_code') ?? '').toLowerCase();
  if (hasInviteCode && !hasEmail && !hasPassword && !hasEmailCode) {
    final isInvalid = inviteText.contains('invalid') ||
        inviteText.contains('无效') ||
        inviteText.contains('不存在');
    return XboardException(
      code: isInvalid ? 'invitation_code_invalid' : 'invitation_code_required',
      message: isInvalid ? '邀请码无效，请检查后重试' : '必须使用邀请码才可以注册',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  final emailText = (fieldText('email') ?? '').toLowerCase();
  final passwordText =
      (fieldText('password') ?? fieldText('password_confirmation') ?? '')
          .toLowerCase();
  final messages = <String>[];
  if (hasEmail) {
    if (emailText.contains('taken') ||
        emailText.contains('exists') ||
        emailText.contains('存在') ||
        emailText.contains('已注册')) {
      messages.add('该邮箱已注册');
    } else if (emailText.contains('whitelist') ||
        emailText.contains('domain') ||
        emailText.contains('白名单') ||
        emailText.contains('后缀')) {
      messages.add('当前邮箱域名不在允许范围内');
    } else if (emailText.contains('gmail') ||
        emailText.contains('alias') ||
        emailText.contains('别名')) {
      messages.add('不支持 Gmail 别名邮箱');
    } else {
      messages.add('邮箱格式无效，请检查后重试');
    }
  }
  if (hasPassword) {
    if (passwordText.contains('1024') ||
        passwordText.contains('byte') ||
        passwordText.contains('字节')) {
      messages.add('密码不得超过 1024 个字节');
    } else if (passwordText.contains('confirm') ||
        passwordText.contains('match') ||
        passwordText.contains('一致')) {
      messages.add('两次输入的密码不一致');
    } else {
      messages.add('密码至少需要 8 个字符，请检查后重试');
    }
  }
  if (hasEmailCode) {
    messages.add('邮箱验证码有误');
  }
  if (hasInviteCode) {
    messages.add('需要填写有效的邀请码');
  }

  return XboardException(
    code: 'validation_failed',
    message: messages.isEmpty ? '输入信息格式有误，请检查后重试' : messages.join('；'),
    statusCode: status,
    retryAfterSeconds: retryAfterSeconds,
  );
}

XboardException _serverError(
  Object? body,
  int status, {
  required bool mutation,
  int? retryAfterSeconds,
  String? uncertainMessage,
}) {
  if (status == 401) {
    return XboardException(
      code: 'unauthorized',
      message: '账号或密码错误，或登录已失效，请重新登录',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  final data = body is Map ? body.cast<Object?, Object?>() : null;
  final rawError = data?['error'];
  final errorObj = rawError is Map ? rawError.cast<Object?, Object?>() : null;
  final backendCode = errorObj?['code'];
  final rawFields = errorObj?['fields'];
  final fields = rawFields is Map ? rawFields.cast<Object?, Object?>() : null;
  final rawLegacyErrors = data?['errors'];
  final legacyErrors =
      rawLegacyErrors is Map ? rawLegacyErrors.cast<Object?, Object?>() : null;

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
  if (backendCode is String && _preservedAuthErrorCodes.contains(backendCode)) {
    return XboardException(
      code: backendCode,
      message: _preservedAuthErrorMessages[backendCode] ?? '',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  if (status == 403) {
    if (backendCode is String &&
        RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(backendCode) &&
        backendCode != 'forbidden') {
      return XboardException(
        code: backendCode,
        message: _preservedAuthErrorMessages[backendCode] ??
            '请求被拒绝，请检查服务地址或账号权限',
        statusCode: status,
        retryAfterSeconds: retryAfterSeconds,
      );
    }
    return XboardException(
      code: 'forbidden',
      message: '当前账号没有使用此功能的权限',
      statusCode: status,
      retryAfterSeconds: retryAfterSeconds,
    );
  }
  final validation = _validationError(
    status: status,
    backendCode: backendCode,
    fields: fields,
    legacyErrors: legacyErrors,
    retryAfterSeconds: retryAfterSeconds,
  );
  if (validation != null) return validation;
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
      message: mutation
          ? (uncertainMessage ?? '服务暂时异常，请确认操作是否已生效后再重试')
          : '购买服务暂时不可用，请稍后重试',
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
  if (raw is! String) return null;
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

String? _optionalTrimmedString(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _optionalFlag(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw == null) return false;
  if (raw is bool) return raw;
  if (raw is int && (raw == 0 || raw == 1)) return raw == 1;
  _invalid();
}

bool? _optionalNullableFlag(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw == null) return null;
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

XboardGuestAuthConfig _parseGuestAuthConfig(Map<String, Object?> data) =>
    XboardGuestAuthConfig(
      isEmailVerify: _optionalFlag(data, 'is_email_verify'),
      isInviteForce: _optionalFlag(data, 'is_invite_force'),
      emailWhitelistSuffix:
          _parseEmailWhitelist(data['email_whitelist_suffix']),
      isCaptcha: _optionalFlag(data, 'is_captcha'),
      captchaType: _optionalTrimmedString(data, 'captcha_type'),
      tosUrl: _safeOptionalChannelHttpsUrl(data, 'tos_url'),
      isRegistrationStopped: _optionalFlag(data, 'stop_register'),
      isGmailAliasRestricted:
          _optionalNullableFlag(data, 'email_gmail_limit_enable'),
    );

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
      chatwootWebsiteToken:
          _optionalTrimmedString(data, 'chatwoot_website_token'),
    );
