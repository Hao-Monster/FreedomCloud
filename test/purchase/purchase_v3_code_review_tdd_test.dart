import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/secure_subscription.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/purchase.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CrFakeStorage implements PurchaseStorage {
  PurchaseSession? session;
  final Map<int, PendingGiftRedemption> pending = {};
  final Map<int, String> profileIds = {};

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
  Future<String?> readProfileId(int accountId) async => profileIds[accountId];

  @override
  Future<void> saveProfileId(int accountId, String profileId) async =>
      profileIds[accountId] = profileId;
}

class _CrFakeApi implements XboardApi, XboardExtendedApi {
  @override
  final Uri baseUri = Uri.parse('https://panel.example.test:8443');

  bool failCatalog = false;
  XboardException? loginError;
  XboardException? registerError;
  XboardException? checkError;
  Completer<XboardPurchaseChannels>? guestChannelsGate;
  int guestChannelsCalls = 0;
  int userChannelsCalls = 0;
  int checkCalls = 0;
  int subscriptionCalls = 0;
  final Set<String> exhaustedCodes = {};

  XboardPurchaseChannels guestChannels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://store.example.test/all'),
    cardStore200gUrl: Uri.parse('https://store.example.test/guest-200g'),
    chatwootBaseUrl: Uri.parse('https://chat.example.test'),
    chatwootWebsiteToken: 'cw_token_demo',
  );

  XboardPurchaseChannels userChannels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://store.example.test/user-all'),
    cardStore200gUrl: Uri.parse('https://store.example.test/user-200g'),
    chatwootBaseUrl: Uri.parse('https://chat.example.test'),
    chatwootWebsiteToken: 'cw_user_token',
  );

  XboardPlanCatalog catalog = const XboardPlanCatalog(
    plans: [
      XboardPlanOffer(
        id: 202,
        name: '200G 永久流量包',
        transferGiB: 200,
        speedLimit: null,
        deviceLimit: null,
        prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
        content: '- 高速专线\n- 购买链接: [点击购卡](https://store.example.test/md-200g)，付款即发',
        tags: ['主力推荐'],
        resetTrafficMethod: 2,
        capacityRemaining: null,
        resetTrafficPrice: null,
        hasSpeedLimit: true,
        hasDeviceLimit: true,
        hasResetTrafficMethod: true,
        hasCapacityRemaining: true,
      ),
    ],
  );

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async {
    if (failCatalog) {
      throw const XboardException(code: 'connection_error', message: '网络错误');
    }
    return catalog;
  }

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async {
    guestChannelsCalls++;
    if (guestChannelsGate != null) {
      return guestChannelsGate!.future;
    }
    return guestChannels;
  }

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
    String authorization,
  ) async {
    userChannelsCalls++;
    return userChannels;
  }

  @override
  Future<String> login(String email, String password) async {
    if (loginError != null) throw loginError!;
    return 'Bearer login_token_123';
  }

  @override
  Future<String> register(String email, String password) async {
    if (registerError != null) throw registerError!;
    return 'Bearer register_token_456';
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      const XboardAccount(
        id: 88,
        email: 'user@example.test',
        isDistributor: false,
      );

  @override
  Future<XboardSubscription> getSubscription(String authorization) async {
    subscriptionCalls++;
    return XboardSubscription(
      planId: 1,
      planName: '体验套餐',
      valid: true,
      url: Uri.parse('https://panel.example.test:8443/api/v1/client/subscribe?token=t1'),
      upload: 0,
      download: 0,
      total: 2 * 1073741824,
      expiresAt: null,
      balance: 0,
    );
  }

  @override
  Future<GiftPreview> checkGift(String authorization, String code) async {
    checkCalls++;
    if (checkError != null) throw checkError!;
    if (exhaustedCodes.contains(code)) {
      throw const XboardException(
        code: 'gift_card_rejected',
        message: '礼品卡已无剩余次数',
        statusCode: 400,
      );
    }
    return const GiftPreview(
      codeId: 901,
      type: 4,
      name: '200G 兑换卡',
      canRedeem: true,
      rewards: GiftReward(
        transferEnable: 200 * 1073741824,
        purchaseSnapshot: GiftPurchaseSnapshot(
          planId: 202,
          planName: '200G 永久流量包',
          period: 'onetime',
          transferEnable: 200 * 1073741824,
        ),
      ),
      purchasePreview: GiftPurchasePreview(
        transferBefore: 2 * 1073741824,
        transferAfter: 202 * 1073741824,
        usedTraffic: 0,
        expiresBefore: null,
        expiresAfter: null,
        renewal: false,
      ),
    );
  }

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) async {
    exhaustedCodes.add(code);
    return const GiftReceipt(
      templateName: '200G 兑换卡',
      rewards: GiftReward(transferEnable: 200 * 1073741824),
      orderTradeNo: 'ORDER_CR_01',
      codeId: 901,
    );
  }

  @override
  Future<GiftHistoryPage> getGiftHistory(
    String authorization, {
    int page = 1,
  }) async =>
      GiftHistoryPage(entries: const [], page: page, lastPage: 1, total: 0);

  @override
  Future<Uri?> getCardStore(String authorization) async =>
      userChannels.cardStoreUrl;

  @override
  Future<void> logout(String authorization) async {}

  @override
  void close() {}
}

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class _PhaseSimulatedHttpClient implements HttpClient {
  _PhaseSimulatedHttpClient({
    required this.onOpenUrl,
    this.onCloseRequest,
  });

  final Future<void> Function(String method, Uri url, String proxyRoute)
      onOpenUrl;
  final Future<HttpClientResponse> Function(String method, Uri url)?
      onCloseRequest;

  String Function(Uri url)? proxyResolver;
  bool Function(X509Certificate cert, String host, int port)? certCallback;

  @override
  set findProxy(String Function(Uri url)? f) => proxyResolver = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) =>
      certCallback = callback;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final route = proxyResolver?.call(url) ?? 'PROXY localhost:7890';
    await onOpenUrl(method, url, route);
    return _PhaseSimulatedRequest(
      url: url,
      method: method,
      onClose: onCloseRequest,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhaseSimulatedRequest implements HttpClientRequest {
  _PhaseSimulatedRequest({
    required this.url,
    required this.method,
    this.onClose,
  });

  final Uri url;
  @override
  final String method;
  final Future<HttpClientResponse> Function(String method, Uri url)? onClose;

  @override
  final HttpHeaders headers = _DummyHeaders();

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
    return _JsonSimulatedResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'success',
        'data': {'auth_data': 'Bearer direct_recovered_token'},
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _JsonSimulatedResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _JsonSimulatedResponse({required this.statusCode, required String body})
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
  final HttpHeaders headers = _DummyHeaders(contentTypeJson: true);

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

class _DummyHeaders implements HttpHeaders {
  _DummyHeaders({this.contentTypeJson = false});

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpCenter(
  WidgetTester tester,
  PurchaseManager manager, {
  List<Uri>? openedLinks,
  bool tickerEnabled = true,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(1280, 900),
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        body: TickerMode(
          enabled: tickerEnabled,
          child: PurchaseCenter(
            manager: manager,
            openLink: (uri) async => openedLinks?.add(uri),
            openProfiles: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var clipboardText = '';

  setUp(() {
    clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        clipboardText = (args?['text'] as String?) ?? '';
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'CR-01: offstage tab never reads clipboard, and bare UUID / 2FA codes are never exfiltrated',
      (tester) async {
    final api = _CrFakeApi();
    final storage = _CrFakeStorage()
      ..session = const PurchaseSession(88, 'Bearer saved_token');
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    await manager.loadPlans();

    // Offstage tab (TickerMode disabled, as in HomePage KeepScope):
    await _pumpCenter(tester, manager, tickerEnabled: false);
    clipboardText = '兑换码: VIP-2026-LEAK88';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);
    expect(api.checkCalls, 0);

    // Visible tab WITHOUT handoffPlan: bare UUID or 2FA recovery code must NEVER auto-check!
    await _pumpCenter(tester, manager, tickerEnabled: true);
    clipboardText = '550e8400-e29b-41d4-a716-446655440000';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);
    expect(api.checkCalls, 0);

    clipboardText = 'a1b2c-3d4e5';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);
    expect(api.checkCalls, 0);

    // Visible tab WITH handoffPlan: UUID is STILL rejected, while mixed-case bare code works!
    manager.markPlanHandoff(api.catalog.plans.first);
    await tester.pumpAndSettle();

    clipboardText = '550e8400-e29b-41d4-a716-446655440000';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);
    expect(api.checkCalls, 0);

    clipboardText = 'Vip2026Pro99';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.code, 'VIP2026PRO99');
    expect(api.checkCalls, 1);
  });

  testWidgets(
      'CR-02: guest PurchaseView auto-loads channels, Chatwoot opens /widget URL, and slow guest fetch never overwrites auth channels',
      (tester) async {
    final api = _CrFakeApi()..failCatalog = true;
    final storage = _CrFakeStorage();
    globalState.config = const Config(themeProps: defaultThemeProps);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Scaffold(
            body: PurchaseView(
              apiOverride: api,
              storageOverride: storage,
              downloadOverride: (profile) async => profile,
              saveConfigOverride: (_) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Even when plan catalog fails on guest entry, self-service store & Chatwoot buttons MUST appear!
    expect(find.byKey(const Key('purchase-support-store')), findsOneWidget);
    expect(find.byKey(const Key('purchase-support-chat')), findsOneWidget);

    // Verify Chatwoot Widget URL formation & validation directly:
    expect(
      api.guestChannels.resolveChatwootWidgetUrl(),
      Uri.parse(
        'https://chat.example.test/widget?website_token=cw_token_demo&locale=zh_CN',
      ),
    );
    expect(
      XboardPurchaseChannels(
        chatwootBaseUrl: Uri.parse('https://chat.example.test/app/login'),
        chatwootWebsiteToken: 'cw_token_demo',
      ).resolveChatwootWidgetUrl(),
      isNull,
    );

    // Verify slow in-flight guest channel response does NOT overwrite logged-in user channels:
    final raceApi = _CrFakeApi()
      ..guestChannelsGate = Completer<XboardPurchaseChannels>();
    final raceManager = PurchaseManager(
      api: raceApi,
      storage: _CrFakeStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(raceManager.dispose);
    final slowGuestFuture = raceManager.ensurePurchaseChannels();
    await raceManager.login('user@example.test', 'password123');
    expect(
      raceManager.purchaseChannels?.cardStore200gUrl,
      Uri.parse('https://store.example.test/user-200g'),
    );
    raceApi.guestChannelsGate!.complete(raceApi.guestChannels);
    await slowGuestFuture;
    expect(
      raceManager.purchaseChannels?.cardStore200gUrl,
      Uri.parse('https://store.example.test/user-200g'),
    );

    // After logout, guest channels are restored so support buttons remain available:
    raceApi.guestChannelsGate = null;
    await raceManager.logout();
    await tester.pumpAndSettle();
    expect(
      raceManager.purchaseChannels?.cardStore200gUrl,
      Uri.parse('https://store.example.test/guest-200g'),
    );
  });

  test(
      'CR-03 & CR-04: HandshakeException in openUrl falls back to DIRECT, post-request drop never replays register, and SecureSubscriptionDownloader falls back to DIRECT',
      () async {
    // 1. HandshakeException during proxy openUrl -> falls back to DIRECT & succeeds!
    final routesAttempted = <String>[];
    await HttpOverrides.runZoned(
      () async {
        final api = DioXboardApi(
          baseUri: Uri.parse('https://panel.example.test:8443'),
          shouldFallbackToDirect: () => true,
        );
        addTearDown(api.close);
        final token = await api.register('new@example.test', 'password1234');
        expect(token, 'Bearer direct_recovered_token');
        expect(routesAttempted, ['PROXY localhost:7890', 'DIRECT']);
      },
      createHttpClient: (_) => _PhaseSimulatedHttpClient(
        onOpenUrl: (_, __, route) async {
          routesAttempted.add(route);
          if (route.startsWith('PROXY ')) {
            throw const HandshakeException(
              'Connection terminated during handshake',
            );
          }
        },
      ),
    );

    // 2. Post-request drop (openUrl succeeded, close() dropped) -> NEVER replays register()!
    var registerPostAttempts = 0;
    await HttpOverrides.runZoned(
      () async {
        final api = DioXboardApi(
          baseUri: Uri.parse('https://panel.example.test:8443'),
          shouldFallbackToDirect: () => true,
        );
        addTearDown(api.close);
        await expectLater(
          api.register('once@example.test', 'password1234'),
          throwsA(
            isA<XboardException>()
                .having((e) => e.code, 'code', 'connection_error')
                .having((e) => e.isUncertain, 'isUncertain', isTrue),
          ),
        );
        expect(registerPostAttempts, 1);
      },
      createHttpClient: (_) => _PhaseSimulatedHttpClient(
        onOpenUrl: (_, __, ___) async {},
        onCloseRequest: (_, __) async {
          registerPostAttempts++;
          throw const HttpException(
            'Connection closed before full header was received',
          );
        },
      ),
    );

    // 3. Certificate verification failure on DIRECT maps to certificate_error:
    await HttpOverrides.runZoned(
      () async {
        final api = DioXboardApi(
          baseUri: Uri.parse('https://panel.example.test:8443'),
          shouldFallbackToDirect: () => false,
        );
        addTearDown(api.close);
        await expectLater(
          api.getPlanCatalog(),
          throwsA(
            isA<XboardException>().having(
              (e) => e.code,
              'code',
              'certificate_error',
            ),
          ),
        );
      },
      createHttpClient: (_) => _PhaseSimulatedHttpClient(
        onOpenUrl: (_, __, ___) async {
          throw const HandshakeException(
            'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)',
          );
        },
      ),
    );

    // 4. SecureSubscriptionDownloader falls back to DIRECT on proxy HandshakeException:
    final subRoutes = <String>[];
    await HttpOverrides.runZoned(
      () async {
        final downloader = SecureSubscriptionDownloader(
          shouldFallbackToDirect: (_) => true,
        );
        final res = await downloader.download(
          Uri.parse('https://panel.example.test:8443/sub/token'),
          const {'User-Agent': 'FlClashX'},
        );
        expect(res.statusCode, 200);
        expect(subRoutes, ['PROXY localhost:7890', 'DIRECT']);
      },
      createHttpClient: (_) => _PhaseSimulatedHttpClient(
        onOpenUrl: (_, __, route) async {
          subRoutes.add(route);
          if (route.startsWith('PROXY ')) {
            throw const HandshakeException('Connection reset during TLS');
          }
        },
      ),
    );
  });

  testWidgets(
      'CR-05 & CR-06: login 401 preserves guest prelogin code/handoff/channels, and switching auth tabs preserves email/password while clearing stale error',
      (tester) async {
    final api = _CrFakeApi()
      ..loginError = const XboardException(
        code: 'unauthorized',
        message: '账号或密码错误',
        statusCode: 401,
      )
      ..registerError = const XboardException(
        code: 'email_exists',
        message: '',
        statusCode: 400,
      );
    final manager = PurchaseManager(
      api: api,
      storage: _CrFakeStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();
    manager.markPlanHandoff(api.catalog.plans.first);

    await _pumpCenter(tester, manager);

    // Pre-fill gift code before login:
    await tester.enterText(
      find.byKey(const Key('purchase-prelogin-code')),
      'VIP2026KEEP99',
    );
    await tester.pump();
    expect(manager.code, 'VIP2026KEEP99');

    // CR-06: Switch to Register tab, submit existing email -> switch back to Login tab:
    await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'alice@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'wrongpass123',
    );
    await tester.tap(find.byKey(const Key('purchase-register-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('该邮箱已注册'), findsOneWidget);

    // Tap Login tab: email & password MUST remain intact, and email_exists error MUST clear!
    await tester.tap(find.byKey(const Key('purchase-auth-tab-login')));
    await tester.pumpAndSettle();
    final emailField =
        tester.widget<TextFormField>(find.byKey(const Key('purchase-email')));
    final passField = tester
        .widget<TextFormField>(find.byKey(const Key('purchase-password')));
    expect(emailField.controller?.text, 'alice@example.test');
    expect(passField.controller?.text, 'wrongpass123');
    expect(find.textContaining('该邮箱已注册'), findsNothing);

    // CR-05: Submit wrong password on Login -> 401 must NOT wipe prelogin code, handoff, or channels!
    await tester.tap(find.byKey(const Key('purchase-login')));
    await tester.pumpAndSettle();
    expect(manager.code, 'VIP2026KEEP99');
    expect(manager.handoffPlan?.id, 202);
    expect(manager.purchaseChannels, isNotNull);
    expect(find.byKey(const Key('purchase-handoff-banner')), findsOneWidget);
  });

  testWidgets(
      'CR-07: PurchaseView 0-profile auto-sync never clobbers prefilled code error and never double-fires after failed register sync',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 900);
    globalState.config = const Config(themeProps: defaultThemeProps);

    // Case A: 0-profile login with exhausted prefilled code keeps error visible!
    final loginApi = _CrFakeApi()..exhaustedCodes.add('EXHAUSTED99');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Scaffold(
            body: PurchaseView(
              apiOverride: loginApi,
              storageOverride: _CrFakeStorage(),
              downloadOverride: (profile) async => profile,
              saveConfigOverride: (_) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('purchase-prelogin-code')),
      'EXHAUSTED99',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'password1234',
    );
    await tester.tap(find.byKey(const Key('purchase-login')));
    await tester.pumpAndSettle();

    expect(find.textContaining('礼品卡已无剩余次数'), findsOneWidget);

    // Case B: 0-profile register when download fails runs download ONLY ONCE!
    var downloadAttempts = 0;
    final regApi = _CrFakeApi();
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Scaffold(
            body: PurchaseView(
              apiOverride: regApi,
              storageOverride: _CrFakeStorage(),
              downloadOverride: (_) async {
                downloadAttempts++;
                throw const FormatException('Simulated download failure');
              },
              saveConfigOverride: (_) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'trial@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'password1234',
    );
    await tester.tap(find.byKey(const Key('purchase-register-submit')));
    await tester.pumpAndSettle();

    expect(downloadAttempts, 1);
    expect(regApi.subscriptionCalls, 1);
  });

  testWidgets(
      'CR-08 & CR-09: keyboard focusability, rapid-click buy debounce, post-redeem clipboard suppression, and empty paste feedback',
      (tester) async {
    final gate = Completer<XboardPurchaseChannels>();
    final api = _CrFakeApi()
      ..guestChannelsGate = gate
      ..catalog = const XboardPlanCatalog(
        plans: [
          XboardPlanOffer(
            id: 202,
            name: '200G 永久流量包',
            transferGiB: 200,
            speedLimit: null,
            deviceLimit: null,
            prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
            content: '- 高速节点',
            tags: ['主力推荐'],
            resetTrafficMethod: 2,
            capacityRemaining: null,
            resetTrafficPrice: null,
            hasSpeedLimit: true,
            hasDeviceLimit: true,
            hasResetTrafficMethod: true,
            hasCapacityRemaining: true,
          ),
        ],
      );
    final storage = _CrFakeStorage();
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    await manager.loadPlans();

    final openedLinks = <Uri>[];
    await _pumpCenter(tester, manager, openedLinks: openedLinks);

    // CR-08a: Auth mode tabs and prelogin paste button must NOT be wrapped in ExcludeFocusTraversal!
    expect(
      find.ancestor(
        of: find.byKey(const Key('purchase-auth-tab-register')),
        matching: find.byWidgetPredicate(
          (w) => w is ExcludeFocusTraversal && w.excluding,
        ),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('purchase-prelogin-code-paste')),
        matching: find.byWidgetPredicate(
          (w) => w is ExcludeFocusTraversal && w.excluding,
        ),
      ),
      findsNothing,
    );

    // CR-08b: Rapidly tapping Buy 3 times while channels are loading opens browser ONLY ONCE!
    final buyBtn = find.byKey(const Key('purchase-plan-buy-202'));
    await tester.tap(buyBtn);
    await tester.pump();
    await tester.tap(buyBtn, warnIfMissed: false);
    await tester.tap(buyBtn, warnIfMissed: false);
    gate.complete(api.guestChannels);
    await tester.pumpAndSettle();
    expect(openedLinks, [Uri.parse('https://store.example.test/guest-200g')]);

    // CR-09a: Empty clipboard manual paste gives SnackBar feedback:
    clipboardText = '   ';
    await tester.tap(find.byKey(const Key('purchase-prelogin-code-paste')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);

    // CR-09b: Paste code manually -> login -> redeem -> Alt-Tab back with same exhausted code in clipboard -> NO error!
    api.guestChannelsGate = null;
    await manager.login('user@example.test', 'password1234');
    await tester.pumpAndSettle();

    clipboardText = '兑换码: FRESH2026CARD';
    await tester.tap(find.byKey(const Key('purchase-code-paste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-check')));
    await tester.pumpAndSettle();
    expect(api.checkCalls, 1);

    await tester.ensureVisible(find.byKey(const Key('purchase-redeem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-redeem')));
    await tester.pumpAndSettle();
    expect(manager.receipt, isNotNull);
    expect(manager.code, isEmpty);

    // Simulate Alt-Tab resume while exhausted code is STILL in OS clipboard:
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.checkCalls, 1);
    expect(manager.error, isNull);
  });

  test(
      'CR-10, CR-11a/b, CR-15: backend error codes, channel/markdown URL resilience, and tier GiB false-positive guard',
      () async {
    // CR-10: Verify DioXboardApi maps captcha_invalid, captcha_unavailable, email_domain_not_allowed, gmail_alias_not_allowed:
    Future<XboardException> captureError(
      int status,
      Map<String, Object?> payload,
    ) async {
      final dio = Dio()
        ..httpClientAdapter = _CapturingAdapter(
          (_) async => ResponseBody.fromString(
            jsonEncode(payload),
            status,
            headers: {
              'content-type': ['application/json'],
            },
          ),
        );
      final testApi = DioXboardApi(dio: dio);
      addTearDown(testApi.close);
      try {
        await testApi.register('a@example.test', 'password1234');
        fail('Expected XboardException');
      } on XboardException catch (e) {
        return e;
      }
    }

    final captchaInvalid = await captureError(400, {
      'error': {'code': 'captcha_invalid', 'message': '验证码有误'},
    });
    expect(captchaInvalid.code, 'register_web_required');

    final captchaUnavailable = await captureError(503, {
      'error': {'code': 'captcha_unavailable', 'message': '验证码服务暂不可用'},
    });
    expect(captchaUnavailable.code, 'register_web_required');

    final domainRejected = await captureError(400, {
      'error': {'code': 'email_domain_not_allowed'},
      'message': '邮箱后缀不处于白名单中',
    });
    expect(domainRejected.code, 'email_domain_not_allowed');

    // CR-11a: Single legacy/broken secondary URL degrades to null instead of crashing all channels:
    final channelDio = Dio()
      ..httpClientAdapter = _CapturingAdapter(
        (_) async => ResponseBody.fromString(
          jsonEncode({
            'status': 'success',
            'data': {
              'card_store_url': 'https://store.example.test/main',
              'card_store_50g_url': 'http://legacy-insecure.example.test/50g',
              'card_store_200g_url': 'https://store.example.test/200g',
              'chatwoot_base_url': 'https://chat.example.test#frag',
              'chatwoot_website_token': 'tok_1',
            },
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    final channelApi = DioXboardApi(dio: channelDio);
    addTearDown(channelApi.close);
    final parsedChannels = await channelApi.getGuestPurchaseChannels();
    expect(
      parsedChannels.cardStoreUrl,
      Uri.parse('https://store.example.test/main'),
    );
    expect(parsedChannels.cardStore50gUrl, isNull);
    expect(
      parsedChannels.cardStore200gUrl,
      Uri.parse('https://store.example.test/200g'),
    );
    expect(parsedChannels.chatwootBaseUrl, isNull);

    // CR-11b & CR-15: Markdown link + trailing Chinese punctuation + tier GiB false-positive guard + metadata stripping:
    expect(
      XboardPurchaseChannels.extractPlanContentPurchaseUrl(
        '- **发卡网**：[点此购卡](https://store.example.test/md-200g)，自动发货！',
      ),
      Uri.parse('https://store.example.test/md-200g'),
    );
    expect(
      XboardPurchaseChannels.extractPlanContentPurchaseUrl(
        'card_store_url: https://store.example.test/item#bad-frag',
      ),
      isNull,
    );
    expect(
      XboardPurchaseChannels.stripPlanPurchaseMetadata(
        '- 高速专线\n- 购买链接: [点击购卡](https://store.example.test/md-200g)\n- 不限设备',
      ),
      '- 高速专线\n- 不限设备',
    );
    expect(
      XboardPurchaseChannels.detectTierGiB(
        const XboardPlanOffer(
          id: 9,
          name: '1000G 旗舰包（50G口接入）',
          transferGiB: 1000,
          speedLimit: null,
          deviceLimit: null,
          prices: [XboardPlanPrice(period: 'onetime', amount: 50000)],
          content: '',
          tags: [],
          resetTrafficMethod: 2,
          capacityRemaining: null,
          resetTrafficPrice: null,
          hasSpeedLimit: false,
          hasDeviceLimit: false,
          hasResetTrafficMethod: true,
          hasCapacityRemaining: false,
        ),
      ),
      isNull,
    );
  });

  testWidgets(
      'CR-11c, CR-14, CR-16: rendered card strips purchase metadata, handoff dismiss >=36x36, and hyphenated code preserves cursor on async notify',
      (tester) async {
    final api = _CrFakeApi();
    final manager = PurchaseManager(
      api: api,
      storage: _CrFakeStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    await manager.loadPlans();
    manager.markPlanHandoff(api.catalog.plans.first);

    await _pumpCenter(tester, manager);
    expect(find.textContaining('购买链接'), findsNothing);
    final dismissSize =
        tester.getSize(find.byKey(const Key('purchase-handoff-dismiss')));
    expect(dismissSize.width, greaterThanOrEqualTo(36));
    expect(dismissSize.height, greaterThanOrEqualTo(36));

    // CR-16: Enter hyphenated code, trigger async loadPlans() notification -> hyphen remains intact!
    await tester.enterText(
      find.byKey(const Key('purchase-prelogin-code')),
      'VIP-2026-',
    );
    await tester.pump();
    await manager.loadPlans();
    await tester.pump();
    final codeField = tester
        .widget<TextField>(find.byKey(const Key('purchase-prelogin-code')));
    expect(codeField.controller?.text, 'VIP-2026-');
  });
}
