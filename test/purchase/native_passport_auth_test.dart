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
  bool failSaveSession = false;

  @override
  Future<PurchaseSession?> readSession() async => session;

  @override
  Future<void> saveSession(PurchaseSession value) async {
    if (failSaveSession) throw const FormatException('storage write failed');
    session = value;
  }

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

class _FakePassportApi
    implements XboardApi, XboardPassportApi, XboardRefreshableGuestConfigApi {
  @override
  final Uri baseUri = Uri.parse('https://fast.hjy.ca:8443');

  XboardPurchaseChannels guestChannels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://shop.example.test/all'),
  );
  XboardPurchaseChannels userChannels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://shop.example.test/user-all'),
  );
  XboardGuestAuthConfig guestAuthConfig = const XboardGuestAuthConfig(
    isEmailVerify: true,
    isInviteForce: false,
    emailWhitelistSuffix: ['gmail.com', 'qq.com'],
  );
  XboardSubscription subscription = XboardSubscription(
    valid: false,
    url: Uri.parse('https://fast.hjy.ca:8443/sub/token'),
  );

  Completer<XboardPurchaseChannels>? guestChannelGate;
  Completer<XboardGuestAuthConfig>? guestAuthGate;
  Completer<void>? emailSendGate;
  Completer<String>? loginGate;
  Completer<String>? registerGate;

  XboardException? registerFailure;
  XboardException? sendCodeFailure;
  XboardException? resetPasswordFailure;
  XboardException? accountFailure;
  XboardException? subscriptionFailure;
  Object? userChannelsFailure;

  int invalidateCacheCalls = 0;
  int guestChannelCalls = 0;
  int guestAuthCalls = 0;
  int getAccountCalls = 0;
  int sendRegistrationCodeCalls = 0;
  int confirmResetCalls = 0;
  final List<String> logoutTokens = [];

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
  void invalidateGuestConfigCache() {
    invalidateCacheCalls++;
  }

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      const XboardPlanCatalog(plans: []);

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async {
    guestChannelCalls++;
    if (guestChannelGate != null) return guestChannelGate!.future;
    return guestChannels;
  }

  @override
  Future<XboardGuestAuthConfig> getGuestAuthConfig() async {
    guestAuthCalls++;
    if (guestAuthGate != null) return guestAuthGate!.future;
    return guestAuthConfig;
  }

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
      String authorization) async {
    if (userChannelsFailure case final failure?) {
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
    return userChannels;
  }

  @override
  Future<Uri?> getCardStore(String authorization) async =>
      userChannels.cardStoreUrl;

  @override
  Future<String> login(String email, String password) async {
    if (loginGate != null) return loginGate!.future;
    return 'Bearer login_session_token';
  }

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
    if (registerGate != null) return registerGate!.future;
    if (registerFailure != null) throw registerFailure!;
    return 'Bearer registered_session_token';
  }

  @override
  Future<void> sendRegistrationEmailCode(String email) async {
    sendRegistrationCodeCalls++;
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
    confirmResetCalls++;
    lastResetEmail = email;
    lastResetEmailCode = emailCode;
    lastResetPassword = password;
    if (resetPasswordFailure != null) throw resetPasswordFailure!;
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async {
    getAccountCalls++;
    if (accountFailure != null) throw accountFailure!;
    return const XboardAccount(id: 42, email: 'member@gmail.com');
  }

  @override
  Future<XboardSubscription> getSubscription(String authorization) async {
    if (subscriptionFailure != null) throw subscriptionFailure!;
    return subscription;
  }

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
  Future<void> logout(String authorization) async {
    logoutTokens.add(authorization);
  }

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

  group('Slice B TDD remediations', () {
    test(
        'P1-10: certificate failures in openUrl never fall back to DIRECT, login uses nonIdempotentAfterSend, and non-cert proxy HandshakeException still falls back',
        () async {
      for (final failure in <Exception>[
        const CertificateException('untrusted leaf certificate'),
        const HandshakeException(
          'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)',
        ),
        const HandshakeException('tlsv1 alert unknown ca'),
      ]) {
        final routes = <String>[];
        await HttpOverrides.runZoned(
          () async {
            final api = DioXboardApi(
              baseUri: Uri.parse('https://fast.hjy.ca:8443'),
              shouldFallbackToDirect: () => true,
            );
            addTearDown(api.close);

            await expectLater(
              api.login('user@gmail.com', 'password1234'),
              throwsA(isA<XboardException>()
                  .having((e) => e.code, 'code', 'certificate_error')),
            );
            await expectLater(
              api.registerAccount(
                email: 'user@gmail.com',
                password: 'password1234',
              ),
              throwsA(isA<XboardException>()
                  .having((e) => e.code, 'code', 'certificate_error')),
            );
            await expectLater(
              api.getAccount('Bearer valid_token_123'),
              throwsA(isA<XboardException>()
                  .having((e) => e.code, 'code', 'certificate_error')),
            );
            expect(routes, everyElement('PROXY localhost:7890'));
            expect(routes, hasLength(3));
          },
          createHttpClient: (_) => _TransportStubClient(
            onOpenUrl: (_, __, route) async {
              routes.add(route);
              throw failure;
            },
          ),
        );
      }

      // Non-cert HandshakeException in openUrl on login falls back to DIRECT once.
      final loginRoutes = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final api = DioXboardApi(
            baseUri: Uri.parse('https://fast.hjy.ca:8443'),
            shouldFallbackToDirect: () => true,
          );
          addTearDown(api.close);
          final auth = await api.login('user@gmail.com', 'password1234');
          expect(auth, 'Bearer direct_login_token');
          expect(loginRoutes, ['PROXY localhost:7890', 'DIRECT']);
        },
        createHttpClient: (_) => _TransportStubClient(
          onOpenUrl: (_, __, route) async {
            loginRoutes.add(route);
            if (route.startsWith('PROXY ')) {
              throw const HandshakeException(
                'Proxy TLS tunnel closed during connect',
              );
            }
          },
          onCloseRequest: (_, __) async => _SimulatedHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'status': 'success',
              'data': {'auth_data': 'Bearer direct_login_token'},
            }),
          ),
        ),
      );

      // Post-openUrl failure on login never replays login and marks uncertain.
      var loginPosts = 0;
      await HttpOverrides.runZoned(
        () async {
          final api = DioXboardApi(
            baseUri: Uri.parse('https://fast.hjy.ca:8443'),
            shouldFallbackToDirect: () => true,
          );
          addTearDown(api.close);
          await expectLater(
            api.login('user@gmail.com', 'password1234'),
            throwsA(
              isA<XboardException>()
                  .having((e) => e.code, 'code', 'connection_error')
                  .having((e) => e.isUncertain, 'isUncertain', isTrue),
            ),
          );
          expect(loginPosts, 1);
        },
        createHttpClient: (_) => _TransportStubClient(
          onOpenUrl: (_, __, ___) async {},
          onCloseRequest: (_, __) async {
            loginPosts++;
            throw const HttpException('Connection closed mid-response');
          },
        ),
      );

      // Dead proxy SocketException during openUrl on login/registerAccount is tagged
      // as pre-request and falls back cleanly to DIRECT once (preserving T01).
      final socketRoutes = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final api = DioXboardApi(
            baseUri: Uri.parse('https://fast.hjy.ca:8443'),
            shouldFallbackToDirect: () => true,
          );
          addTearDown(api.close);
          final auth = await api.registerAccount(
            email: 'user@gmail.com',
            password: 'password1234',
          );
          expect(auth, 'Bearer direct_socket_fallback_token');
          expect(socketRoutes, ['PROXY localhost:7890', 'DIRECT']);
        },
        createHttpClient: (_) => _TransportStubClient(
          onOpenUrl: (_, __, route) async {
            socketRoutes.add(route);
            if (route.startsWith('PROXY ')) {
              throw const SocketException('Proxy localhost:7890 refused');
            }
          },
          onCloseRequest: (_, __) async => _SimulatedHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'status': 'success',
              'data': {'auth_data': 'Bearer direct_socket_fallback_token'},
            }),
          ),
        ),
      );

      // Untagged DioException.connectionError (not from openUrl) marks
      // nonIdempotentAfterSend endpoints uncertain, unlike idempotent GETs.
      final adapter = _Adapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Synthetic connectionError',
          error: const SocketException('Connection reset after send'),
        ),
      );
      final untaggedApi = DioXboardApi(
        dio: Dio()..httpClientAdapter = adapter,
        baseUri: Uri.parse('https://fast.hjy.ca:8443'),
      );
      addTearDown(untaggedApi.close);
      await expectLater(
        untaggedApi.login('user@gmail.com', 'password1234'),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'connection_error')
              .having((e) => e.isUncertain, 'isUncertain', isTrue)
              .having((e) => e.message, 'message', isNot(contains('兑换'))),
        ),
      );
      await expectLater(
        untaggedApi.registerAccount(
          email: 'user@gmail.com',
          password: 'password1234',
        ),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'connection_error')
              .having((e) => e.isUncertain, 'isUncertain', isTrue),
        ),
      );
      await expectLater(
        untaggedApi.getPlanCatalog(),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'connection_error')
              .having((e) => e.isUncertain, 'isUncertain', isFalse),
        ),
      );
    });

    test(
        'P1-11 & P3-8: XboardRefreshableGuestConfigApi + forceRefresh bypasses cache, and PurchaseManager guards in-flight races and updates cardStoreUrl',
        () async {
      var version = 0;
      final firstGate = Completer<void>();
      final adapter = _Adapter((_) async {
        version++;
        final current = version;
        if (current == 1) {
          await firstGate.future;
        }
        return _json({
          'status': 'success',
          'data': {
            'is_email_verify': current == 1 ? 0 : 1,
            'is_invite_force': current >= 3 ? 1 : 0,
            'card_store_url': current == 2
                ? 'https://shop.example.test/v2'
                : 'https://shop.example.test/v$current',
          },
        });
      });
      final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);
      expect(api, isA<XboardRefreshableGuestConfigApi>());

      final staleFuture = api.getGuestAuthConfig();
      await Future<void>.delayed(Duration.zero);
      final forcedChannels = await api.getGuestPurchaseChannels(forceRefresh: true);
      expect(forcedChannels.cardStoreUrl, Uri.parse('https://shop.example.test/v2'));
      expect((await api.getGuestAuthConfig()).isEmailVerify, isTrue);
      // Completing the earlier in-flight call must not overwrite the newer cache.
      firstGate.complete();
      await staleFuture;
      expect((await api.getGuestAuthConfig()).isEmailVerify, isTrue);
      expect(adapter.requests, hasLength(2));

      (api as XboardRefreshableGuestConfigApi).invalidateGuestConfigCache();
      final afterInvalidate = await api.getGuestAuthConfig();
      expect(afterInvalidate.isInviteForce, isTrue);
      expect(adapter.requests, hasLength(3));

      // PurchaseManager force refresh invalidates cache, updates/clears cardStoreUrl,
      // and rejects stale out-of-order responses or failures.
      final fakeApi = _FakePassportApi();
      final manager = PurchaseManager(
        api: fakeApi,
        storage: _FakeStorage(),
        synchronize: (_, __) async {},
      );
      addTearDown(manager.dispose);

      final slowGate = Completer<XboardGuestAuthConfig>();
      fakeApi.guestAuthGate = slowGate;
      final slowFuture = manager.ensurePurchaseChannels();

      fakeApi
        ..guestAuthGate = null
        ..guestChannels = XboardPurchaseChannels(
          cardStoreUrl: Uri.parse('https://shop.example.test/forced'),
        )
        ..guestAuthConfig = const XboardGuestAuthConfig(
          isEmailVerify: false,
          isInviteForce: true,
        );
      final forcedResult = await manager.ensurePurchaseChannels(force: true);
      expect(fakeApi.invalidateCacheCalls, 1);
      expect(forcedResult?.cardStoreUrl, Uri.parse('https://shop.example.test/forced'));
      expect(manager.cardStoreUrl, Uri.parse('https://shop.example.test/forced'));
      expect(manager.guestAuthConfig.isInviteForce, isTrue);

      // Older request failing or resolving later must NOT clobber newer forced result.
      slowGate.completeError(
        const XboardException(code: 'server_error', message: '', statusCode: 503),
      );
      await slowFuture;
      expect(manager.channelError, isNull);
      expect(manager.cardStoreUrl, Uri.parse('https://shop.example.test/forced'));
      expect(manager.guestAuthConfig.isInviteForce, isTrue);

      // Force refresh returning null cardStoreUrl clears prior guest cardStoreUrl.
      fakeApi.guestChannels = const XboardPurchaseChannels(cardStoreUrl: null);
      await manager.ensurePurchaseChannels(force: true);
      expect(manager.cardStoreUrl, isNull);
    });

    test(
        'P1-12: preserves 403 error codes before forbidden, preserves all five 429 codes, and parses modern + legacy 422 field errors',
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

      final invalidOrigin = await sendError(403, {
        'error': {'code': 'invalid_origin', 'message': '请求来源不受信任'},
      });
      expect(invalidOrigin.code, 'invalid_origin');
      expect(invalidOrigin.statusCode, 403);

      final explicit403 = await sendError(403, {
        'error': {'code': 'distributor_route_forbidden'},
      });
      expect(explicit403.code, 'distributor_route_forbidden');

      final generic403 = await sendError(403, {'message': 'Forbidden'});
      expect(generic403.code, 'forbidden');

      for (final code in const [
        'registration_rate_limited',
        'registration_busy',
        'registration_ip_limited',
        'password_reset_busy',
        'login_rate_limited',
      ]) {
        final err = await sendError(
          429,
          {
            'error': {'code': code},
          },
          retryAfter: '15',
        );
        expect(err.code, code);
        expect(err.statusCode, 429);
        expect(err.retryAfterSeconds, 15);
        expect(err.message, isNotEmpty);
      }

      final legacyEmail422 = await sendError(422, {
        'message': '邮箱格式不正确',
        'errors': {
          'email': ['邮箱格式不正确'],
        },
      });
      expect(legacyEmail422.code, 'validation_failed');
      expect(legacyEmail422.statusCode, 422);
      expect(legacyEmail422.message, contains('邮箱'));

      final legacyPassword422 = await sendError(422, {
        'message': '密码不得超过 1024 个字节',
        'errors': {
          'password': ['密码不得超过 1024 个字节'],
        },
      });
      expect(legacyPassword422.code, 'validation_failed');
      expect(legacyPassword422.message, contains('密码'));

      final legacyEmailCode422 = await sendError(422, {
        'message': '邮箱验证码有误',
        'errors': {
          'email_code': ['邮箱验证码有误'],
        },
      });
      expect(legacyEmailCode422.code, 'registration_email_invalid');

      final modernEmail422 = await sendError(422, {
        'error': {
          'code': 'validation_failed',
          'fields': {'email': '邮箱格式无效'},
        },
      });
      expect(modernEmail422.code, 'validation_failed');
      expect(modernEmail422.message, contains('邮箱'));

      final modernPassword422 = await sendError(422, {
        'error': {
          'code': 'validation_failed',
          'fields': {'password': '密码至少需要 8 个字符'},
        },
      });
      expect(modernPassword422.code, 'validation_failed');
      expect(modernPassword422.message, contains('密码'));

      final modernInvite422 = await sendError(422, {
        'error': {
          'code': 'validation_failed',
          'fields': {'invite_code': 'required'},
        },
      });
      expect(modernInvite422.code, 'invitation_code_required');
    });

    test(
        'P1-13 & P3-9: post-register recovery, deferred initial sync on refresh, initialize non-401 guest fetch, and disposed guards',
        () async {
      // (a) registerAccount succeeds, then getAccount fails 503 -> revokes token & surfaces registration_created_login_required.
      final apiA = _FakePassportApi()
        ..accountFailure = const XboardException(
          code: 'server_error',
          message: 'unavailable',
          statusCode: 503,
        );
      final storageA = _FakeStorage();
      final managerA = PurchaseManager(
        api: apiA,
        storage: storageA,
        synchronize: (_, __) async {},
      );
      addTearDown(managerA.dispose);
      await managerA.registerWithDetails(
        email: 'new@gmail.com',
        password: 'password1234',
      );
      expect(managerA.loggedIn, isFalse);
      expect(storageA.session, isNull);
      expect(apiA.logoutTokens, ['Bearer registered_session_token']);
      expect(managerA.error?.code, 'registration_created_login_required');
      expect(managerA.error?.message, '账号已创建成功，请直接登录以同步权益');

      // (b) registerAccount & getAccount succeed, saveSession throws -> revokes token & surfaces registration_created_login_required.
      final apiB = _FakePassportApi();
      final storageB = _FakeStorage()..failSaveSession = true;
      final managerB = PurchaseManager(
        api: apiB,
        storage: storageB,
        synchronize: (_, __) async {},
      );
      addTearDown(managerB.dispose);
      await managerB.registerWithDetails(
        email: 'new2@gmail.com',
        password: 'password1234',
      );
      expect(managerB.loggedIn, isFalse);
      expect(apiB.logoutTokens, ['Bearer registered_session_token']);
      expect(managerB.error?.code, 'registration_created_login_required');

      // (c) registerAccount & saveSession succeed, getSubscription 503 -> refresh() runs deferred initial auto-sync once!
      var syncCalls = 0;
      final apiC = _FakePassportApi()
        ..subscriptionFailure = const XboardException(
          code: 'server_error',
          message: '',
          statusCode: 503,
        );
      final storageC = _FakeStorage();
      final managerC = PurchaseManager(
        api: apiC,
        storage: storageC,
        synchronize: (_, __) async {
          syncCalls++;
        },
      );
      addTearDown(managerC.dispose);
      await managerC.registerWithDetails(
        email: 'sync@gmail.com',
        password: 'password1234',
      );
      expect(managerC.loggedIn, isTrue);
      expect(storageC.session, isNotNull);
      expect(syncCalls, 0);
      expect(managerC.hasAttemptedInitialSyncFor(42), isFalse);

      apiC
        ..subscriptionFailure = null
        ..subscription = XboardSubscription(
          valid: true,
          url: Uri.parse('https://fast.hjy.ca:8443/sub/valid'),
        );
      await managerC.refresh();
      expect(syncCalls, 1);
      expect(managerC.subscriptionSynced, isTrue);
      expect(managerC.hasAttemptedInitialSyncFor(42), isTrue);

      await managerC.refresh();
      expect(syncCalls, 1);

      // (d) initialize() with saved session + non-401 getAccount error populates guest config & channels.
      final apiD = _FakePassportApi()
        ..accountFailure = const XboardException(
          code: 'server_error',
          message: '',
          statusCode: 503,
        );
      final storageD = _FakeStorage()
        ..session = const PurchaseSession(42, 'Bearer saved');
      final managerD = PurchaseManager(
        api: apiD,
        storage: storageD,
        synchronize: (_, __) async {},
      );
      addTearDown(managerD.dispose);
      await managerD.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(managerD.loggedIn, isFalse);
      expect(storageD.session, isNotNull);
      expect(managerD.guestAuthConfig.isEmailVerify, isTrue);
      expect(
        managerD.purchaseChannels?.cardStoreUrl,
        Uri.parse('https://shop.example.test/all'),
      );

      // (e) P3-9: dispose() during awaiting login/registerAccount skips _authenticateWithAuthorization.
      final apiE = _FakePassportApi()
        ..loginGate = Completer<String>()
        ..registerGate = Completer<String>();
      final storageE = _FakeStorage();
      final disposedLogin = PurchaseManager(
        api: apiE,
        storage: storageE,
        synchronize: (_, __) async {},
      );
      final loginFuture = disposedLogin.login('a@gmail.com', 'password1234');
      disposedLogin.dispose();
      apiE.loginGate!.complete('Bearer late_login');
      await loginFuture;
      expect(apiE.getAccountCalls, 0);
      expect(storageE.session, isNull);

      final disposedReg = PurchaseManager(
        api: apiE,
        storage: storageE,
        synchronize: (_, __) async {},
      );
      final regFuture = disposedReg.registerWithDetails(
        email: 'a@gmail.com',
        password: 'password1234',
      );
      disposedReg.dispose();
      apiE.registerGate!.complete('Bearer late_register');
      await regFuture;
      expect(apiE.getAccountCalls, 0);
      expect(storageE.session, isNull);
    });

    test(
        'P2-12: non-gift uncertain errors never show gift-card copy while redeemGift keeps gift-card copy',
        () async {
      const authUncertainMsg = '请求状态未确认，请检查邮箱或尝试登录，切勿盲目重复提交';

      Future<void> expectNonGiftUncertain(
        Future<Object?> Function(DioXboardApi api) call,
      ) async {
        final adapter503 = _Adapter(
          (_) async => _json({'status': 'fail'}, status: 503),
        );
        final api503 = DioXboardApi(dio: Dio()..httpClientAdapter = adapter503);
        addTearDown(api503.close);
        await expectLater(
          call(api503),
          throwsA(
            isA<XboardException>()
                .having((e) => e.isUncertain, 'isUncertain', isTrue)
                .having((e) => e.message, 'message', authUncertainMsg)
                .having((e) => e.message, 'no gift', isNot(contains('兑换'))),
          ),
        );

        final adapterBadJson = _Adapter(
          (_) async => ResponseBody.fromString('{not-json', 200),
        );
        final apiBadJson =
            DioXboardApi(dio: Dio()..httpClientAdapter = adapterBadJson);
        addTearDown(apiBadJson.close);
        await expectLater(
          call(apiBadJson),
          throwsA(
            isA<XboardException>()
                .having((e) => e.isUncertain, 'isUncertain', isTrue)
                .having((e) => e.message, 'message', authUncertainMsg)
                .having((e) => e.message, 'no gift', isNot(contains('兑换'))),
          ),
        );
      }

      await expectNonGiftUncertain(
        (api) => api.login('a@gmail.com', 'password1234'),
      );
      await expectNonGiftUncertain(
        (api) =>
            api.registerAccount(email: 'a@gmail.com', password: 'password1234'),
      );
      await expectNonGiftUncertain(
        (api) => api.sendRegistrationEmailCode('a@gmail.com'),
      );
      await expectNonGiftUncertain(
        (api) => api.sendPasswordResetEmailCode('a@gmail.com'),
      );
      await expectNonGiftUncertain(
        (api) => api.confirmPasswordReset(
          email: 'a@gmail.com',
          emailCode: '123456',
          password: 'password1234',
        ),
      );

      final gift503 = DioXboardApi(
        dio: Dio()
          ..httpClientAdapter =
              _Adapter((_) async => _json({'status': 'fail'}, status: 503)),
      );
      addTearDown(gift503.close);
      await expectLater(
        gift503.redeemGift('Bearer token_123', 'CODE1234'),
        throwsA(
          isA<XboardException>()
              .having((e) => e.isUncertain, 'isUncertain', isTrue)
              .having((e) => e.message, 'message', contains('兑换')),
        ),
      );
    });

    test(
        'P2-13: _sendEmailCode guards busy/epoch/auth transitions and resetPassword rejects while loggedIn',
        () async {
      final api = _FakePassportApi()..loginGate = Completer<String>();
      final storage = _FakeStorage();
      final manager = PurchaseManager(
        api: api,
        storage: storage,
        synchronize: (_, __) async {},
      );
      addTearDown(manager.dispose);

      // While busy (login pending), _sendEmailCode returns false without hitting API.
      final loginFuture = manager.login('a@gmail.com', 'password1234');
      expect(manager.busy, isTrue);
      expect(await manager.sendRegistrationEmailCode('a@gmail.com'), isFalse);
      expect(api.sendRegistrationCodeCalls, 0);
      api.loginGate!.complete('Bearer token_123');
      await loginFuture;
      expect(manager.loggedIn, isTrue);

      // Logged-in resetPassword returns false cleanly without touching session or API.
      expect(
        await manager.resetPassword(
          email: 'a@gmail.com',
          emailCode: '123456',
          password: 'newpassword123',
        ),
        isFalse,
      );
      expect(api.confirmResetCalls, 0);
      expect(manager.loggedIn, isTrue);
      expect(storage.session, isNotNull);
      expect(manager.error, isNotNull);
      expect(manager.passwordResetSucceeded, isFalse);

      await manager.logout();
      api.loginGate = null;

      // Stale failing sendRegistrationEmailCode settling after login must not pollute manager.error.
      final sendGate = Completer<void>();
      api
        ..emailSendGate = sendGate
        ..sendCodeFailure = const XboardException(
          code: 'mail_unavailable',
          message: '',
          statusCode: 503,
        );
      final sendFuture = manager.sendRegistrationEmailCode('a@gmail.com');
      await manager.login('a@gmail.com', 'password1234');
      expect(manager.loggedIn, isTrue);
      sendGate.complete();
      expect(await sendFuture, isFalse);
      expect(manager.error, isNull);
    });

    test(
        'P2-14: _parseRetryAfterSeconds supports HTTP-date, ignores <= 0, and clamps to 86400',
        () async {
      Future<int?> parseRetry(String header) async {
        final adapter = _Adapter(
          (_) async => _json(
            {
              'error': {'code': 'login_rate_limited'},
            },
            status: 429,
            headers: {
              'retry-after': [header],
            },
          ),
        );
        final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
        addTearDown(api.close);
        try {
          await api.login('a@gmail.com', 'password1234');
          fail('Expected XboardException');
        } on XboardException catch (e) {
          return e.retryAfterSeconds;
        }
      }

      expect(await parseRetry('0'), isNull);
      expect(await parseRetry('-5'), isNull);
      expect(await parseRetry('999999999'), 86400);
      expect(await parseRetry('not-a-date'), isNull);
      expect(await parseRetry('Thu, 01 Jan 1970 00:00:00 GMT'), isNull);

      final future90 = HttpDate.format(
        DateTime.now().toUtc().add(const Duration(seconds: 90)),
      );
      expect(await parseRetry(future90), inInclusiveRange(88, 91));

      final future10Days = HttpDate.format(
        DateTime.now().toUtc().add(const Duration(days: 10)),
      );
      expect(await parseRetry(future10Days), 86400);
    });

    test(
        'P2-15: stop_register, email_gmail_limit_enable, isRestrictedGmailAlias, unmodifiable whitelist, and resilient channel scalar parsing',
        () async {
      const unmodifiableCfg = XboardGuestAuthConfig(
        emailWhitelistSuffix: ['gmail.com'],
      );
      expect(
        () => unmodifiableCfg.emailWhitelistSuffix.add('evil.com'),
        throwsUnsupportedError,
      );

      const defaultCfg = XboardGuestAuthConfig();
      expect(defaultCfg.isRegistrationStopped, isFalse);
      expect(defaultCfg.isGmailAliasRestricted, isNull);
      expect(defaultCfg.isRestrictedGmailAlias('user+tag@gmail.com'), isTrue);
      expect(defaultCfg.isRestrictedGmailAlias('first.last@gmail.com'), isFalse);

      const strictCfg = XboardGuestAuthConfig(isGmailAliasRestricted: true);
      expect(strictCfg.isRestrictedGmailAlias('user+tag@gmail.com'), isTrue);
      expect(strictCfg.isRestrictedGmailAlias('first.last@gmail.com'), isTrue);
      expect(
        strictCfg.isRestrictedGmailAlias('FIRST.LAST@GOOGLEMAIL.COM'),
        isTrue,
      );
      expect(strictCfg.isRestrictedGmailAlias('first.last@outlook.com'), isFalse);

      const relaxedCfg = XboardGuestAuthConfig(isGmailAliasRestricted: false);
      expect(relaxedCfg.isRestrictedGmailAlias('user+tag@gmail.com'), isFalse);
      expect(relaxedCfg.isRestrictedGmailAlias('first.last@gmail.com'), isFalse);

      final adapter = _Adapter((_) async => _json({
            'status': 'success',
            'data': {
              'is_email_verify': 1,
              'is_invite_force': 0,
              'stop_register': 1,
              'email_gmail_limit_enable': 1,
              'card_store_url': 0,
              'card_store_50g_url': false,
              'chatwoot_base_url': 123,
              'chatwoot_website_token': false,
            },
          }));
      final api = DioXboardApi(dio: Dio()..httpClientAdapter = adapter);
      addTearDown(api.close);
      final authCfg = await api.getGuestAuthConfig();
      final channels = await api.getGuestPurchaseChannels();
      expect(authCfg.isRegistrationStopped, isTrue);
      expect(authCfg.isGmailAliasRestricted, isTrue);
      expect(channels.cardStoreUrl, isNull);
      expect(channels.cardStore50gUrl, isNull);
      expect(channels.chatwootBaseUrl, isNull);
      expect(channels.chatwootWebsiteToken, isNull);
    });

    test(
        'P2-16: _refreshData keeps prior channels on transient or non-XboardException errors and force refresh reconciles sticky flags',
        () async {
      final api = _FakePassportApi();
      final manager = PurchaseManager(
        api: api,
        storage: _FakeStorage(),
        synchronize: (_, __) async {},
      );
      addTearDown(manager.dispose);

      // Reconcile sticky flags when force refresh gets relaxed guest config.
      api.registerFailure = const XboardException(
        code: 'invitation_code_required',
        message: '',
        statusCode: 422,
      );
      await manager.registerWithDetails(
        email: 'a@gmail.com',
        password: 'password1234',
      );
      api.registerFailure = const XboardException(
        code: 'registration_email_invalid',
        message: '',
        statusCode: 400,
      );
      await manager.registerWithDetails(
        email: 'a@gmail.com',
        password: 'password1234',
      );
      expect(manager.inviteCodeRequiredByServer, isTrue);
      expect(manager.emailVerifyRequiredByServer, isTrue);

      api
        ..registerFailure = null
        ..guestAuthConfig = const XboardGuestAuthConfig(
          isInviteForce: false,
          isEmailVerify: false,
        );
      await manager.ensurePurchaseChannels(force: true);
      expect(manager.inviteCodeRequiredByServer, isFalse);
      expect(manager.emailVerifyRequiredByServer, isFalse);

      // Logged-in transient 503 and FormatException in getUserPurchaseChannels
      // retain prior purchaseChannels/cardStoreUrl without failing refresh().
      await manager.login('member@gmail.com', 'password1234');
      expect(
        manager.purchaseChannels?.cardStoreUrl,
        Uri.parse('https://shop.example.test/user-all'),
      );
      expect(
        manager.cardStoreUrl,
        Uri.parse('https://shop.example.test/user-all'),
      );

      api.userChannelsFailure = const XboardException(
        code: 'server_error',
        message: '',
        statusCode: 503,
      );
      await manager.refresh();
      expect(manager.error, isNull);
      expect(manager.channelError?.code, 'server_error');
      expect(
        manager.purchaseChannels?.cardStoreUrl,
        Uri.parse('https://shop.example.test/user-all'),
      );
      expect(
        manager.cardStoreUrl,
        Uri.parse('https://shop.example.test/user-all'),
      );

      api.userChannelsFailure = const FormatException('bad channels json');
      await manager.refresh();
      expect(manager.error, isNull);
      expect(manager.channelError?.code, 'purchase_failed');
      expect(
        manager.purchaseChannels?.cardStoreUrl,
        Uri.parse('https://shop.example.test/user-all'),
      );
      expect(
        manager.cardStoreUrl,
        Uri.parse('https://shop.example.test/user-all'),
      );
    });

    test(
        'P3-7: admin MFA 202 or mfa_required maps to purchase_account_unsupported on login',
        () async {
      final api202 = DioXboardApi(
        dio: Dio()
          ..httpClientAdapter = _Adapter(
            (_) async => _json(
              {
                'status': 'success',
                'data': {'mfa_required': true, 'purpose': 'admin_login'},
              },
              status: 202,
            ),
          ),
      );
      addTearDown(api202.close);
      await expectLater(
        api202.login('admin@gmail.com', 'password1234'),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'purchase_account_unsupported')
              .having((e) => e.statusCode, 'statusCode', 202)
              .having(
                (e) => e.message,
                'message',
                '该账号已开启管理员二次验证，请在网页端登录',
              ),
        ),
      );

      final api200 = DioXboardApi(
        dio: Dio()
          ..httpClientAdapter = _Adapter(
            (_) async => _json(
              {
                'status': 'success',
                'data': {'mfa_required': true},
              },
              status: 200,
            ),
          ),
      );
      addTearDown(api200.close);
      await expectLater(
        api200.login('admin@gmail.com', 'password1234'),
        throwsA(
          isA<XboardException>()
              .having((e) => e.code, 'code', 'purchase_account_unsupported')
              .having((e) => e.statusCode, 'statusCode', 200),
        ),
      );
    });
  });
}

class _TransportStubClient implements HttpClient {
  _TransportStubClient({
    required this.onOpenUrl,
    this.onCloseRequest,
  });

  final Future<void> Function(String method, Uri url, String route) onOpenUrl;
  final Future<HttpClientResponse> Function(String method, Uri url)?
      onCloseRequest;

  String Function(Uri url)? _proxyResolver;

  @override
  set findProxy(String Function(Uri url)? f) => _proxyResolver = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {}

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final route = _proxyResolver?.call(url) ?? 'PROXY localhost:7890';
    await onOpenUrl(method, url, route);
    return _TransportStubRequest(
      url: url,
      method: method,
      onClose: onCloseRequest,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TransportStubRequest implements HttpClientRequest {
  _TransportStubRequest({
    required this.url,
    required this.method,
    this.onClose,
  });

  final Uri url;
  @override
  final String method;
  final Future<HttpClientResponse> Function(String method, Uri url)? onClose;

  @override
  final HttpHeaders headers = _StubHttpHeaders();

  @override
  bool followRedirects = false;

  @override
  int maxRedirects = 0;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  bool bufferOutput = true;

  @override
  Encoding encoding = utf8;

  @override
  Uri get uri => url;

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    if (onClose != null) {
      return onClose!(method, url);
    }
    return _SimulatedHttpResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'success',
        'data': {'id': 1, 'email': 'a@gmail.com', 'is_distributor': false},
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SimulatedHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _SimulatedHttpResponse({required this.statusCode, required String body})
      : _bytes = Uint8List.fromList(utf8.encode(body));

  @override
  final int statusCode;
  final Uint8List _bytes;

  @override
  int get contentLength => _bytes.length;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _StubHttpHeaders(contentTypeJson: true);

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  X509Certificate? get certificate => null;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHttpHeaders implements HttpHeaders {
  _StubHttpHeaders({this.contentTypeJson = false});

  final bool contentTypeJson;
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    if (contentTypeJson) {
      action('content-type', ['application/json; charset=utf-8']);
    }
    _values.forEach(action);
  }

  @override
  String? value(String name) => _values[name.toLowerCase()]?.firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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
