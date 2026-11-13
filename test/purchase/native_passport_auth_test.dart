import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final Future<ResponseBody> Function(RequestOptions options) handle;
  final List<RequestOptions> requests = [];
  final List<String?> requestBodies = [];

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
  void close({bool force = false}) {}
}

ResponseBody _json(
  Object? body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...?headers,
      },
    );

class _FakeStorage implements PurchaseStorage {
  PurchaseSession? session;
  final Map<int, PendingGiftRedemption> pending = {};

  @override
  Future<PurchaseSession?> readSession() async => session;

  @override
  Future<void> saveSession(PurchaseSession value) async => session = value;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<PendingGiftRedemption?> readPending(int accountId) async =>
      pending[accountId];

  @override
  Future<void> savePending(int accountId, PendingGiftRedemption value) async =>
      pending[accountId] = value;

  @override
  Future<void> clearPending(int accountId) async => pending.remove(accountId);

  @override
  Future<String?> readProfileId(int accountId) async => null;

  @override
  Future<void> saveProfileId(int accountId, String profileId) async {}
}

class _FakePassportApi implements XboardApi, XboardPassportApi {
  @override
  final Uri baseUri = Uri.parse('https://fast.hjy.ca:8443');

  XboardPurchaseChannels guestChannels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://shop.example.test/all'),
  );
  XboardGuestAuthConfig guestAuthConfig = const XboardGuestAuthConfig(
    isEmailVerify: true,
    isInviteForce: false,
    emailWhitelistSuffix: ['gmail.com', 'qq.com'],
  );

  Completer<XboardPurchaseChannels>? guestChannelGate;
  Completer<XboardGuestAuthConfig>? guestAuthGate;
  Completer<void>? emailSendGate;

  XboardException? registerFailure;
  XboardException? sendCodeFailure;
  XboardException? resetPasswordFailure;

  String? lastRegisterEmail;
  String? lastRegisterPassword;
  String? lastRegisterEmailCode;
  String? lastRegisterInviteCode;
  String? lastRegistrationCodeEmail;
  String? lastPasswordResetCodeEmail;
  String? lastResetEmail;
  String? lastResetEmailCode;
  String? lastResetPassword;

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: []);

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async {
    if (guestChannelGate != null) return guestChannelGate!.future;
    return guestChannels;
  }

  @override
  Future<XboardGuestAuthConfig> getGuestAuthConfig() async {
    if (guestAuthGate != null) return guestAuthGate!.future;
    return guestAuthConfig;
  }

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
          String authorization) async =>
      guestChannels;

  @override
  Future<Uri?> getCardStore(String authorization) async =>
      guestChannels.cardStoreUrl;

  @override
  Future<String> login(String email, String password) async =>
      'Bearer login_session_token';

  @override
  Future<String> register(String email, String password) =>
      registerAccount(email: email, password: password);

  @override
  Future<String> registerAccount({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    lastRegisterEmail = email;
    lastRegisterPassword = password;
    lastRegisterEmailCode = emailCode;
    lastRegisterInviteCode = inviteCode;
    if (registerFailure != null) throw registerFailure!;
    return 'Bearer registered_session_token';
  }

  @override
  Future<void> sendRegistrationEmailCode(String email) async {
    lastRegistrationCodeEmail = email;
    if (emailSendGate != null) await emailSendGate!.future;
    if (sendCodeFailure != null) throw sendCodeFailure!;
  }

  @override
  Future<void> sendPasswordResetEmailCode(String email) async {
    lastPasswordResetCodeEmail = email;
    if (emailSendGate != null) await emailSendGate!.future;
    if (sendCodeFailure != null) throw sendCodeFailure!;
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String emailCode,
    required String password,
  }) async {
    lastResetEmail = email;
    lastResetEmailCode = emailCode;
    lastResetPassword = password;
    if (resetPasswordFailure != null) throw resetPasswordFailure!;
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      const XboardAccount(id: 42, email: 'member@gmail.com');

  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      XboardSubscription(
        valid: false,
        url: Uri.parse('https://fast.hjy.ca:8443/sub/token'),
      );

  @override
  Future<GiftPreview> checkGift(String authorization, String code) async =>
      throw UnimplementedError();

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) async =>
      throw UnimplementedError();

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization,
          {int page = 1}) async =>
      GiftHistoryPage(entries: const [], page: 1, lastPage: 1, total: 0);

  @override
  Future<void> logout(String authorization) async {}

  @override
  void close() {}
}

void main() {
  group('XboardGuestAuthConfig', () {
    test('defaults and email domain / Gmail plus alias helpers', () {
      const defaultConfig = XboardGuestAuthConfig();
      expect(defaultConfig.isEmailVerify, isFalse);
      expect(defaultConfig.isInviteForce, isFalse);
      expect(defaultConfig.emailWhitelistSuffix, isEmpty);
      expect(defaultConfig.isCaptcha, isFalse);
      expect(defaultConfig.captchaType, isNull);
      expect(defaultConfig.tosUrl, isNull);
      expect(defaultConfig.isEmailDomainAllowed('anything@custom.org'), isTrue);

      const restricted = XboardGuestAuthConfig(
        isEmailVerify: true,
        isInviteForce: true,
        emailWhitelistSuffix: ['gmail.com', '@Outlook.COM'],
      );
      expect(restricted.isEmailDomainAllowed(' User@GMAIL.COM '), isTrue);
      expect(restricted.isEmailDomainAllowed('user@outlook.com'), isTrue);
      expect(restricted.isEmailDomainAllowed('user@qq.com'), isFalse);
      expect(restricted.isEmailDomainAllowed('invalid'), isFalse);
      expect(restricted.isEmailDomainAllowed('a@b@gmail.com'), isFalse);
      expect(restricted.isEmailDomainAllowed('@gmail.com'), isFalse);

      expect(restricted.hasGmailPlusAlias('user+tag@gmail.com'), isTrue);
      expect(restricted.hasGmailPlusAlias('USER+1@GOOGLEMAIL.COM'), isTrue);
      expect(restricted.hasGmailPlusAlias('user@gmail.com'), isFalse);
      expect(restricted.hasGmailPlusAlias('user+tag@outlook.com'), isFalse);
      expect(restricted.hasGmailPlusAlias('@gmail.com'), isFalse);
    });
  });

  group('DioXboardApi XboardPassportApi', () {
    test('parses guest auth config and shares single-flight + 30s TTL cache',
        () async {
      final adapter = _Adapter((_) async => _json({
            'status': 'success',
            'data': {
              'is_email_verify': 1,
              'is_invite_force': true,
              'email_whitelist_suffix': [' @Gmail.com ', 'qq.com', ''],
              'is_captcha': 0,
              'captcha_type': 'turnstile',
              'tos_url': 'https://fast.hjy.ca:8443/tos',
              'card_store_url': 'https://shop.example.test/all',
            },
          }));
      final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);

      final channelsFuture = api.getGuestPurchaseChannels();
      final configFuture = api.getGuestAuthConfig();
      final channels = await channelsFuture;
      final config = await configFuture;
      expect(adapter.requests, hasLength(1));

      expect(channels.cardStoreUrl, Uri.parse('https://shop.example.test/all'));
      expect(config.isEmailVerify, isTrue);
      expect(config.isInviteForce, isTrue);
      expect(config.emailWhitelistSuffix, ['gmail.com', 'qq.com']);
      expect(config.isCaptcha, isFalse);
      expect(config.captchaType, 'turnstile');
      expect(config.tosUrl, Uri.parse('https://fast.hjy.ca:8443/tos'));

      // Cached within 30s TTL: subsequent reads make zero extra network calls.
      final cachedConfig = await api.getGuestAuthConfig();
      expect(cachedConfig.emailWhitelistSuffix, ['gmail.com', 'qq.com']);
      expect(adapter.requests, hasLength(1));
    });

    test('guest config handles 0/null whitelist, invalid tosUrl, and does not cache failures',
        () async {
      var attempt = 0;
      final adapter = _Adapter((_) async {
        attempt++;
        if (attempt == 1) {
          return _json({'status': 'fail', 'message': 'unavailable'},
              status: 503);
        }
        return _json({
          'status': 'success',
          'data': {
            'is_email_verify': false,
            'is_invite_force': false,
            'email_whitelist_suffix': 0,
            'tos_url': 'https://user:pass@example.test/tos#frag',
          },
        });
      });
      final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);

      await expectLater(
        api.getGuestAuthConfig(),
        throwsA(isA<XboardException>()
            .having((e) => e.code, 'code', 'server_error')),
      );
      final config = await api.getGuestAuthConfig();
      expect(attempt, 2);
      expect(config.emailWhitelistSuffix, isEmpty);
      expect(config.tosUrl, isNull);
    });

    test('registerAccount sends optional email_code and invite_code and normalizes Bearer',
        () async {
      final adapter = _Adapter((_) async => _json({
            'status': 'success',
            'data': {'auth_data': 'raw_token_12345'},
          }));
      final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);

      final auth = await api.registerAccount(
        email: ' user@gmail.com ',
        password: 'password1234',
        emailCode: ' 654321 ',
        inviteCode: ' INV888 ',
      );
      expect(auth, 'Bearer raw_token_12345');
      expect(adapter.requests.single.path, '/api/v1/passport/auth/register');
      expect(jsonDecode(adapter.requestBodies.single!), {
        'email': 'user@gmail.com',
        'password': 'password1234',
        'email_code': '654321',
        'invite_code': 'INV888',
      });
    });

    test('sendRegistrationEmailCode, sendPasswordResetEmailCode, confirmPasswordReset fall back on HTTP 404',
        () async {
      final adapter = _Adapter((options) async {
        if (options.path.startsWith('/api/v1/auth/')) {
          return _json({'message': 'not found'}, status: 404);
        }
        return _json({'data': true});
      });
      final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);

      await api.sendRegistrationEmailCode(' reg@gmail.com ');
      await api.sendPasswordResetEmailCode(' reset@gmail.com ');
      await api.confirmPasswordReset(
        email: ' reset@gmail.com ',
        emailCode: ' 112233 ',
        password: 'newpassword123',
      );

      expect(adapter.requests.map((r) => r.path).toList(), [
        '/api/v1/auth/registration-email/request',
        '/api/v1/passport/comm/sendEmailVerify',
        '/api/v1/auth/password-reset/request',
        '/api/v1/passport/comm/sendEmailVerify',
        '/api/v1/auth/password-reset/confirm',
        '/api/v1/passport/auth/forget',
      ]);
      expect(jsonDecode(adapter.requestBodies[5]!), {
        'email': 'reset@gmail.com',
        'email_code': '112233',
        'password': 'newpassword123',
      });
    });

    test('email and password-reset mutations never fall back to direct and mark timeouts uncertain',
        () async {
      var fallbackEvaluated = false;
      final adapter = _Adapter((request) async => throw DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          ));
      final api = DioXboardApi(
        dio: Dio()..httpClientAdapter = adapter,
        shouldFallbackToDirect: () {
          fallbackEvaluated = true;
          return true;
        },
      );
      addTearDown(api.close);

      await expectLater(
        api.sendRegistrationEmailCode('a@gmail.com'),
        throwsA(isA<XboardException>()
            .having((e) => e.isUncertain, 'uncertain', isTrue)),
      );
      await expectLater(
        api.confirmPasswordReset(
          email: 'a@gmail.com',
          emailCode: '123456',
          password: 'password1234',
        ),
        throwsA(isA<XboardException>()
            .having((e) => e.isUncertain, 'uncertain', isTrue)),
      );
      expect(fallbackEvaluated, isFalse);
      expect(adapter.requests, hasLength(2));
    });

    test('preserves Retry-After header and all auth/passport error codes',
        () async {
      Future<XboardException> sendError(
        int status,
        Map<String, Object?> payload, {
        String? retryAfter,
      }) async {
        final adapter = _Adapter((_) async => _json(
              payload,
              status: status,
              headers: retryAfter == null
                  ? null
                  : {
                      'retry-after': [retryAfter],
                    },
            ));
        final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
        addTearDown(api.close);
        try {
          await api.registerAccount(
            email: 'a@gmail.com',
            password: 'password1234',
          );
          fail('Expected XboardException');
        } on XboardException catch (e) {
          return e;
        }
      }

      final cooldown = await sendError(
        429,
        {
          'error': {'code': 'registration_email_cooldown'},
        },
        retryAfter: '45',
      );
      expect(cooldown.code, 'registration_email_cooldown');
      expect(cooldown.statusCode, 429);
      expect(cooldown.retryAfterSeconds, 45);

      final generic429 = await sendError(429, {'message': 'slow down'},
          retryAfter: '12');
      expect(generic429.code, 'rate_limited');
      expect(generic429.retryAfterSeconds, 12);

      for (final code in const [
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
      ]) {
        final status = code.endsWith('_unavailable') ? 503 : 400;
        final err = await sendError(status, {
          'error': {'code': code},
        });
        expect(err.code, code);
      }

      for (final captchaCode in const [
        'captcha_required',
        'captcha_invalid',
        'captcha_unavailable',
      ]) {
        final err = await sendError(400, {
          'error': {'code': captchaCode},
        });
        expect(err.code, 'register_web_required');
      }

      final validationEmailCode = await sendError(422, {
        'error': {
          'code': 'validation_failed',
          'fields': {'email_code': 'required'},
        },
      });
      expect(validationEmailCode.code, 'registration_email_invalid');
    });

    test('production transport keeps strict TLS verification on passport endpoints',
        () async {
      bool? badCertAccepted;
      await HttpOverrides.runZoned(() async {
        final api = DioXboardApi();
        await expectLater(
          api.sendRegistrationEmailCode('a@gmail.com'),
          throwsA(isA<XboardException>()),
        );
        api.close();
      }, createHttpClient: (_) {
        final probe = _TlsProbeClient(
          onBadCertSet: ({required accepted}) => badCertAccepted = accepted,
        );
        return probe;
      });
      expect(badCertAccepted, isFalse);
    });
  });

  group('PurchaseManager native passport auth', () {
    late _FakePassportApi api;
    late _FakeStorage storage;
    late PurchaseManager manager;

    setUp(() {
      api = _FakePassportApi();
      storage = _FakeStorage();
      manager = PurchaseManager(
        api: api,
        storage: storage,
        synchronize: (_, __) async {},
      );
    });

    tearDown(() => manager.dispose());

    test('ensurePurchaseChannels loads guestAuthConfig and guards against login epoch race',
        () async {
      final gate = Completer<XboardGuestAuthConfig>();
      api.guestAuthGate = gate;

      final channelsFuture = manager.ensurePurchaseChannels();
      await manager.login('member@gmail.com', 'password1234');
      expect(manager.loggedIn, isTrue);

      gate.complete(const XboardGuestAuthConfig(
        isEmailVerify: true,
        isInviteForce: true,
      ));
      await channelsFuture;

      expect(manager.guestAuthConfig.isEmailVerify, isFalse);
      expect(manager.guestAuthConfig.isInviteForce, isFalse);

      api
        ..guestAuthGate = null
        ..guestAuthConfig = const XboardGuestAuthConfig(
          isEmailVerify: true,
          isInviteForce: true,
        );
      await manager.logout();
      await manager.ensurePurchaseChannels();
      expect(manager.guestAuthConfig.isEmailVerify, isTrue);
      expect(manager.guestAuthConfig.isInviteForce, isTrue);
    });

    test('registerWithDetails tracks server-required invite/email flags and clears on success',
        () async {
      api.registerFailure = const XboardException(
        code: 'invitation_code_required',
        message: '',
        statusCode: 400,
      );
      await manager.registerWithDetails(
        email: ' new@gmail.com ',
        password: 'password1234',
      );
      expect(manager.loggedIn, isFalse);
      expect(manager.inviteCodeRequiredByServer, isTrue);
      expect(manager.emailVerifyRequiredByServer, isFalse);

      api.registerFailure = const XboardException(
        code: 'validation_failed',
        message: 'email_code is required',
        statusCode: 422,
      );
      await manager.registerWithDetails(
        email: 'new@gmail.com',
        password: 'password1234',
        inviteCode: 'INV999',
      );
      expect(manager.emailVerifyRequiredByServer, isTrue);

      api.registerFailure = null;
      await manager.registerWithDetails(
        email: ' new@gmail.com ',
        password: 'password1234',
        emailCode: ' 123456 ',
        inviteCode: ' INV999 ',
      );
      expect(manager.loggedIn, isTrue);
      expect(api.lastRegisterEmail, 'new@gmail.com');
      expect(api.lastRegisterEmailCode, '123456');
      expect(api.lastRegisterInviteCode, 'INV999');
      expect(manager.inviteCodeRequiredByServer, isFalse);
      expect(manager.emailVerifyRequiredByServer, isFalse);
    });

    test('sendRegistrationEmailCode and sendPasswordResetCode manage sendingEmailCode without setting busy',
        () async {
      final gate = Completer<void>();
      api.emailSendGate = gate;

      final future = manager.sendRegistrationEmailCode(' user@gmail.com ');
      expect(manager.sendingEmailCode, isTrue);
      expect(manager.busy, isFalse);

      gate.complete();
      expect(await future, isTrue);
      expect(manager.sendingEmailCode, isFalse);
      expect(api.lastRegistrationCodeEmail, 'user@gmail.com');

      api
        ..emailSendGate = null
        ..sendCodeFailure = const XboardException(
          code: 'password_reset_cooldown',
          message: '',
          statusCode: 429,
          retryAfterSeconds: 60,
        );
      expect(await manager.sendPasswordResetCode(' reset@gmail.com '), isFalse);
      expect(manager.sendingEmailCode, isFalse);
      expect(manager.error?.code, 'password_reset_cooldown');
      expect(manager.error?.retryAfterSeconds, 60);
    });

    test('resetPassword updates resettingPassword, passwordResetSucceeded, and clearPasswordResetState',
        () async {
      api.resetPasswordFailure = const XboardException(
        code: 'password_reset_invalid',
        message: '',
        statusCode: 400,
      );
      expect(
        await manager.resetPassword(
          email: 'user@gmail.com',
          emailCode: '000000',
          password: 'newpassword123',
        ),
        isFalse,
      );
      expect(manager.passwordResetSucceeded, isFalse);
      expect(manager.resettingPassword, isFalse);
      expect(manager.error?.code, 'password_reset_invalid');

      api.resetPasswordFailure = null;
      var sawResetting = false;
      void listener() {
        if (manager.resettingPassword) sawResetting = true;
      }

      manager.addListener(listener);
      final ok = await manager.resetPassword(
        email: ' user@gmail.com ',
        emailCode: ' 654321 ',
        password: 'newpassword123',
      );
      manager
        ..removeListener(listener)
        ..clearPasswordResetState();
      expect(ok, isTrue);
      expect(sawResetting, isTrue);
      expect(manager.resettingPassword, isFalse);
      expect(api.lastResetEmail, 'user@gmail.com');
      expect(api.lastResetEmailCode, '654321');
      expect(api.lastResetPassword, 'newpassword123');
      expect(manager.passwordResetSucceeded, isFalse);
    });

    test('clearPasswordResetState clears passwordResetSucceeded', () async {
      final ok = await manager.resetPassword(
        email: 'user@gmail.com',
        emailCode: '654321',
        password: 'newpassword123',
      );
      expect(ok, isTrue);
      expect(manager.passwordResetSucceeded, isTrue);
      manager.clearPasswordResetState();
      expect(manager.passwordResetSucceeded, isFalse);
    });
  });
}

class _TlsProbeClient implements HttpClient {
  _TlsProbeClient({required this.onBadCertSet});

  final void Function({required bool accepted}) onBadCertSet;

  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {
    if (callback != null) {
      onBadCertSet(accepted: callback(_DummyCert(), 'fast.hjy.ca', 443));
    }
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('stop before network'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DummyCert implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
