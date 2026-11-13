import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _trialAccount = XboardAccount(id: 108, email: 'newbie@example.test');

final _trialSubscription = XboardSubscription(
  valid: true,
  planId: 1,
  planName: '新客 2G 体验套餐',
  upload: 0,
  download: 0,
  total: 2 * 1073741824,
  url: Uri.parse('https://fast.hjy.ca:8443/api/v1/client/subscribe?token=TRIAL2G'),
);

const _standardPlans = <XboardPlanOffer>[
  XboardPlanOffer(
    id: 101,
    name: '50G 永久流量包',
    transferGiB: 50,
    speedLimit: 0,
    deviceLimit: 0,
    resetTrafficMethod: 2,
    tags: ['轻量入门'],
    prices: [XboardPlanPrice(period: 'onetime', amount: 3800)],
  ),
  XboardPlanOffer(
    id: 102,
    name: '200G 永久流量包 · 美国/日本',
    transferGiB: 200,
    speedLimit: 0,
    deviceLimit: 0,
    resetTrafficMethod: 2,
    tags: ['主力推荐', 'IEPL专线'],
    prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
  ),
];

const _giftPreview200G = GiftPreview(
  codeId: 302,
  type: 4,
  name: '200G 永久流量包兑换卡',
  canRedeem: true,
  rewards: GiftReward(
    purchaseSnapshot: GiftPurchaseSnapshot(
      planId: 102,
      planName: '200G 永久流量包 · 美国/日本',
      period: 'onetime',
      transferEnable: 200 * 1073741824,
    ),
  ),
  purchasePreview: GiftPurchasePreview(
    transferBefore: 2 * 1073741824,
    transferAfter: 200 * 1073741824,
    usedTraffic: 0,
    expiresBefore: null,
    expiresAfter: null,
    renewal: false,
  ),
);

void main() {
  Future<void> pumpV3Center(
    WidgetTester tester,
    PurchaseManager manager, {
    Size size = const Size(1280, 900),
    Locale locale = const Locale('zh', 'CN'),
    Brightness brightness = Brightness.dark,
    double textScale = 1.0,
    List<Uri>? openedLinks,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        theme: ThemeData(
          brightness: brightness,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF03A9F4),
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: PurchaseCenter(
            manager: manager,
            openLink: (uri) async => openedLinks?.add(uri),
            openProfiles: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
      'T01: DioXboardApi falls back to DIRECT when proxy fails on non-mutations, parses guest/user channels, and supports register()',
      () async {
    final createdClients = <_FallbackHttpClient>[];
    await HttpOverrides.runZoned(() async {
      final api = DioXboardApi(shouldFallbackToDirect: () => true);
      addTearDown(api.close);

      // First HttpClient simulates dead system proxy; second HttpClient requires DIRECT.
      final catalog = await api.getPlanCatalog();
      expect(catalog.plans.single.name, '200G 永久流量包');
      expect(createdClients, hasLength(2));
      final proxyClient = createdClients[0];
      final directClient = createdClients[1];
      expect(proxyClient.proxyFn, isNull);
      expect(proxyClient.openUrlCalls, 1);
      expect(
        directClient.proxyFn?.call(Uri.parse('https://fast.hjy.ca:8443')),
        'DIRECT',
      );
      expect(
        directClient.badCertFn?.call(_DummyCert(), 'fast.hjy.ca', 8443),
        isFalse,
      );
      expect(directClient.openUrlCalls, 1);

      // Mutation (redeemGift) must NEVER retry over fallback so idempotency stays uncertain-safe.
      await expectLater(
        api.redeemGift('Bearer validtoken123', 'VIP2026CODE88'),
        throwsA(
          isA<XboardException>().having((e) => e.isUncertain, 'uncertain', isTrue),
        ),
      );
      expect(proxyClient.openUrlCalls, 2);
      expect(directClient.openUrlCalls, 1);
      expect(createdClients, hasLength(2));

      // Guest purchase channels parse nullable per-tier URLs and Chatwoot without Authorization.
      final guestChannels = await api.getGuestPurchaseChannels();
      expect(
        guestChannels.cardStoreUrl,
        Uri.parse('https://shop.example.test/all'),
      );
      expect(
        guestChannels.cardStore200gUrl,
        Uri.parse('https://shop.example.test/200g'),
      );
      expect(guestChannels.cardStore50gUrl, isNull);
      expect(
        guestChannels.chatwootBaseUrl,
        Uri.parse('https://chat.example.test'),
      );
      expect(guestChannels.chatwootWebsiteToken, 'pub-token-1');
      expect(
        guestChannels.resolvePlanStoreUrl(_standardPlans[1]),
        Uri.parse('https://shop.example.test/200g'),
      );
      expect(
        guestChannels.resolvePlanStoreUrl(_standardPlans[0]),
        Uri.parse('https://shop.example.test/all'),
      );

      // Per-plan Markdown purchase link overrides tier link.
      const customLinkPlan = XboardPlanOffer(
        id: 999,
        name: '200G 专属包',
        transferGiB: 200,
        prices: [XboardPlanPrice(period: 'onetime', amount: 12000)],
        content: '购买链接: https://shop.example.test/vip-200g\n- 专属高速线路',
      );
      expect(
        guestChannels.resolvePlanStoreUrl(customLinkPlan),
        Uri.parse('https://shop.example.test/vip-200g'),
      );

      // In-app register posts /api/v1/passport/auth/register and extracts auth_data.
      final bearer = await api.register('  NewUser@Example.test ', 'password1234');
      expect(bearer, 'Bearer registered_token_48_chars');

      // Authenticated user purchase channels also fall back cleanly when proxy is down.
      final userChannels = await api.getUserPurchaseChannels(bearer);
      expect(
        userChannels.cardStore500gUrl,
        Uri.parse('https://shop.example.test/500g'),
      );
    }, createHttpClient: (_) {
      final index = createdClients.length;
      final client = _FallbackHttpClient(failConnection: index == 0);
      createdClients.add(client);
      return client;
    });
  });

  testWidgets(
      'T02: unauthenticated plan card direct Buy opens exact per-tier store URL, shows handoff banner, and failed catalog shows accurate retry label',
      (tester) async {
    final api = _V3FakeApi();
    final storage = _V3FakeStorage();
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();

    final openedLinks = <Uri>[];
    await pumpV3Center(tester, manager, openedLinks: openedLinks);

    // Featured badge rendered on 200G plan.
    expect(find.byKey(const Key('purchase-plan-featured-102')), findsOneWidget);

    // Clicking direct Buy on 200G fetches guest channels on demand and opens exact 200G tier URL.
    await tester.tap(find.byKey(const Key('purchase-plan-buy-102')));
    await tester.pumpAndSettle();
    expect(openedLinks, [Uri.parse('https://shop.example.test/tier-200g')]);
    expect(api.guestChannelCalls, 1);

    // Handoff banner appears in workbench referencing the selected 200G plan.
    final handoff = find.byKey(const Key('purchase-handoff-banner'));
    expect(handoff, findsOneWidget);
    expect(
      find.descendant(
        of: handoff,
        matching: find.textContaining('200G 永久流量包'),
      ),
      findsOneWidget,
    );

    // Simulate catalog load failure: retry button uses plan-specific retry copy instead of "刷新账户".
    api.failCatalog = true;
    await manager.loadPlans();
    await tester.pumpAndSettle();
    final retryBtn = find.byKey(const Key('purchase-plans-retry'));
    expect(retryBtn, findsOneWidget);
    expect(
      find.descendant(of: retryBtn, matching: find.text('刷新账户')),
      findsNothing,
    );
    expect(
      find.descendant(of: retryBtn, matching: find.text('重新加载套餐')),
      findsOneWidget,
    );
  });

  testWidgets(
      'T03: in-app 2G trial registration auto-syncs trial subscription AND auto-previews pre-filled gift code without consuming',
      (tester) async {
    final api = _V3FakeApi();
    final storage = _V3FakeStorage();
    var syncedCount = 0;
    XboardSubscription? syncedSubscription;
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, sub) async {
        syncedCount++;
        syncedSubscription = sub;
      },
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await pumpV3Center(tester, manager);

    // Pre-fill gift code before registering.
    await tester.enterText(
      find.byKey(const Key('purchase-prelogin-code')),
      'vip-2026-gift88',
    );
    await tester.pump();
    expect(manager.code, 'VIP2026GIFT88');

    // Switch to Free 2G Register tab.
    await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'newbie@example.test',
    );
    // Password < 8 chars rejected locally in register mode.
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'short',
    );
    await tester.tap(find.byKey(const Key('purchase-register-submit')));
    await tester.pumpAndSettle();
    expect(api.registerCalls, 0);

    // Valid password >= 8 chars registers, auto-syncs 2G trial, and auto-previews gift code!
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'password1234',
    );
    await tester.tap(find.byKey(const Key('purchase-register-submit')));
    await tester.pumpAndSettle();

    expect(api.registerCalls, 1);
    expect(manager.loggedIn, isTrue);
    expect(syncedCount, 1);
    expect(syncedSubscription?.total, 2 * 1073741824);
    expect(manager.code, 'VIP2026GIFT88');
    expect(api.checkCalls, 1);
    expect(api.redeemCalls, 0);
    expect(find.byKey(const Key('purchase-preview-card')), findsOneWidget);
    expect(find.byKey(const Key('purchase-redeem')), findsOneWidget);
  });

  testWidgets(
      'T04: returning to window (AppLifecycleState.resumed) auto-detects clipboard code and previews benefits once without auto-redeeming',
      (tester) async {
    const clipboardText = '【发卡网发货】您的兑换码：RESUME-2026-PRO99';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final api = _V3FakeApi();
    final storage = _V3FakeStorage()
      ..session = const PurchaseSession(108, 'Bearer saved_session');
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await pumpV3Center(tester, manager);
    expect(manager.code, isEmpty);

    // Simulate user returning to FlClashX window after buying a card in browser.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(manager.code, 'RESUME2026PRO99');
    expect(api.checkCalls, 1);
    expect(api.redeemCalls, 0);
    expect(find.byKey(const Key('purchase-preview-card')), findsOneWidget);

    // User explicitly clears the code; resuming again with identical clipboard must NOT re-paste.
    await tester.tap(find.byKey(const Key('purchase-code-clear')));
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);
    expect(api.checkCalls, 1);
  });

  testWidgets(
      'T05: desktop 1280x900 geometry, Chatwoot + WeChat preservation, and 4-locale 2.0x textScale overflow safety',
      (tester) async {
    final api = _V3FakeApi();
    final storage = _V3FakeStorage();
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    final openedLinks = <Uri>[];
    await pumpV3Center(
      tester,
      manager,
      size: const Size(1280, 900),
      openedLinks: openedLinks,
    );

    // Desktop first-screen geometry intact.
    final plansRect = tester.getRect(find.byKey(const Key('purchase-plans')));
    final workbenchRect =
        tester.getRect(find.byKey(const Key('purchase-workbench')));
    final loginRect = tester.getRect(find.byKey(const Key('purchase-login')));
    expect(plansRect.right, lessThanOrEqualTo(workbenchRect.left));
    expect(loginRect.bottom, lessThanOrEqualTo(900));

    // Online Chatwoot button opens native in-app SupportChatSheet + external fallback + both backup WeChat entries coexist cleanly.
    final chatBtn = find.byKey(const Key('purchase-support-chat'));
    await tester.ensureVisible(chatBtn);
    await tester.tap(chatBtn);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(openedLinks, isEmpty);

    await tester.tap(find.byKey(const Key('support-open-external')));
    await tester.pumpAndSettle();
    expect(
      openedLinks,
      [
        Uri.parse(
          'https://chat.example.test/widget?website_token=public-widget-token&locale=zh_CN',
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);
    expect(find.text('微信号: ChasingDream_2021'), findsOneWidget);
    expect(find.text('微信号: dxm_qa'), findsOneWidget);

    // 4-locale 2.0x textScale stress check on narrow 320x800 in both Login & Register tabs.
    for (final locale in const [
      Locale('zh', 'CN'),
      Locale('en'),
      Locale('ja'),
      Locale('ru'),
    ]) {
      await pumpV3Center(
        tester,
        manager,
        size: const Size(320, 800),
        locale: locale,
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull, reason: 'login-$locale');
      await tester.ensureVisible(
        find.byKey(const Key('purchase-auth-tab-register')),
      );
      await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'register-$locale');
      await tester.ensureVisible(
        find.byKey(const Key('purchase-auth-tab-login')),
      );
      await tester.tap(find.byKey(const Key('purchase-auth-tab-login')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'T06: render Chinese V3 desktop preview artifacts with real PurchaseManager',
      (tester) async {
    String? previewFont;
    await tester.runAsync(() async {
      final fontFile = File(
        Platform.environment['PURCHASE_PREVIEW_FONT'] ??
            'C:/Windows/Fonts/msyh.ttc',
      );
      if (fontFile.existsSync()) {
        final bytes = await fontFile.readAsBytes();
        final loader = FontLoader('PurchaseV3PreviewChinese')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        previewFont = 'PurchaseV3PreviewChinese';
      }
      await (FontLoader('JetBrainsMono')
            ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')))
          .load();
      await (FontLoader('Twemoji')
            ..addFont(rootBundle.load('assets/fonts/Twemoji.Mozilla.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await Directory('build/purchase-preview').create(recursive: true);
    });

    final api = _V3FakeApi();
    final storage = _V3FakeStorage();
    final manager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);
    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1360, 960);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: previewFont,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF66BB6A),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0B110E),
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            body: PurchaseCenter(
              manager: manager,
              openLink: (_) async {},
              openProfiles: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Free 2G Register tab & click Buy on 200G to capture full V3 guest experience.
    await tester.tap(find.byKey(const Key('purchase-auth-tab-register')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-plan-buy-102')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final guestBoundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await guestBoundary.toImage(pixelRatio: 1.0);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/purchase-preview/v3-guest-register-handoff.png')
            .writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });

    // Also render catalog failure recovery state (mirrors user's original screenshot scenario).
    api.failCatalog = true;
    await manager.loadPlans();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final errorBoundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await errorBoundary.toImage(pixelRatio: 1.0);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/purchase-preview/v3-catalog-error-recovery.png')
            .writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  });
}

class _DummyCert implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FallbackHttpClient implements HttpClient {
  _FallbackHttpClient({required this.failConnection});

  final bool failConnection;
  int openUrlCalls = 0;
  String Function(Uri)? proxyFn;
  bool Function(X509Certificate, String, int)? badCertFn;

  @override
  Duration? connectionTimeout;

  @override
  set findProxy(String Function(Uri)? f) => proxyFn = f;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate, String, int)? callback) =>
      badCertFn = callback;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    openUrlCalls += 1;
    if (failConnection) {
      throw const SocketException('Proxy localhost:7890 refused connection');
    }
    return _StubHttpRequest(method, url);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHeaders implements HttpHeaders {
  final Map<String, List<String>> map = {
    HttpHeaders.contentTypeHeader: ['application/json; charset=utf-8'],
  };

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    map[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    map.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      map.forEach(action);

  @override
  List<String>? operator [](String name) => map[name.toLowerCase()];

  @override
  String? value(String name) => map[name.toLowerCase()]?.firstOrNull;

  @override
  set contentLength(int value) {}

  @override
  set chunkedTransferEncoding(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHttpRequest implements HttpClientRequest {
  _StubHttpRequest(this.method, this.uri);

  @override
  final String method;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = _StubHeaders();
  @override
  bool followRedirects = false;
  @override
  int maxRedirects = 0;
  @override
  bool persistentConnection = true;
  @override
  int contentLength = -1;

  final List<int> _body = <int>[];

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_body.addAll);

  @override
  Future<HttpClientResponse> close() async {
    final Object payload = switch (uri.path) {
      '/api/v1/guest/plans' => {
          'status': 'success',
          'data': [
            {
              'id': 200,
              'name': '200G 永久流量包',
              'transfer_enable': 200,
              'can_purchase': true,
              'prices': {'onetime': 15000},
            },
          ],
        },
      '/api/v1/guest/comm/config' || '/api/v1/user/purchase-channels' => {
          'status': 'success',
          'data': {
            'app_name': 'FreedomPost',
            'card_store_url': 'https://shop.example.test/all',
            'card_store_50g_url': null,
            'card_store_100g_url': 'https://shop.example.test/100g',
            'card_store_200g_url': 'https://shop.example.test/200g',
            'card_store_500g_url': 'https://shop.example.test/500g',
            'chatwoot_base_url': 'https://chat.example.test',
            'chatwoot_website_token': 'pub-token-1',
          },
        },
      '/api/v1/passport/auth/register' => {
          'status': 'success',
          'data': {
            'auth_data': 'Bearer registered_token_48_chars',
            'token': 'sub_token_ignore',
            'is_admin': false,
            'is_distributor': false,
          },
        },
      _ => {'status': 'fail', 'message': 'unexpected route'},
    };
    return _StubHttpResponse(utf8.encode(jsonEncode(payload)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHttpResponse extends Stream<List<int>> implements HttpClientResponse {
  _StubHttpResponse(this._bytes);

  final List<int> _bytes;

  @override
  final HttpHeaders headers = _StubHeaders();

  @override
  int get statusCode => 200;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  String get reasonPhrase => 'OK';

  @override
  int get contentLength => _bytes.length;

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

class _V3FakeStorage implements PurchaseStorage {
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

class _V3FakeApi implements XboardApi, XboardExtendedApi {
  @override
  final Uri baseUri = Uri.parse('https://fast.hjy.ca:8443');

  bool failCatalog = false;
  int guestChannelCalls = 0;
  int registerCalls = 0;
  int checkCalls = 0;
  int redeemCalls = 0;

  static final _channels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://shop.example.test/all'),
    cardStore50gUrl: Uri.parse('https://shop.example.test/tier-50g'),
    cardStore100gUrl: Uri.parse('https://shop.example.test/tier-100g'),
    cardStore200gUrl: Uri.parse('https://shop.example.test/tier-200g'),
    cardStore500gUrl: Uri.parse('https://shop.example.test/tier-500g'),
    chatwootBaseUrl: Uri.parse('https://chat.example.test'),
    chatwootWebsiteToken: 'public-widget-token',
  );

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async {
    if (failCatalog) {
      throw const XboardException(code: 'connection_error', message: '');
    }
    return const XboardPlanCatalog(plans: _standardPlans);
  }

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async {
    guestChannelCalls++;
    return _channels;
  }

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
    String authorization,
  ) async =>
      _channels;

  @override
  Future<String> register(String email, String password) async {
    registerCalls++;
    return 'Bearer registered_session';
  }

  @override
  Future<String> login(String email, String password) async =>
      'Bearer logged_in_session';

  @override
  Future<XboardAccount> getAccount(String authorization) async => _trialAccount;

  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      _trialSubscription;

  @override
  Future<GiftPreview> checkGift(String authorization, String code) async {
    checkCalls++;
    return _giftPreview200G;
  }

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) async {
    redeemCalls++;
    return GiftReceipt(
      codeId: 302,
      templateName: _giftPreview200G.name,
      rewards: _giftPreview200G.rewards,
    );
  }

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization,
          {int page = 1}) async =>
      GiftHistoryPage(entries: const [], page: page, lastPage: 1, total: 0);

  @override
  Future<Uri?> getCardStore(String authorization) async =>
      _channels.cardStoreUrl;

  @override
  Future<void> logout(String authorization) async {}

  @override
  void close() {}
}
