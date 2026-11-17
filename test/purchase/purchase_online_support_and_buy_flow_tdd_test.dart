import 'dart:async';

import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _plan50G = XboardPlanOffer(
  id: 101,
  name: '50G 永久流量包',
  transferGiB: 50,
  speedLimit: 0,
  deviceLimit: 0,
  resetTrafficMethod: 2,
  tags: ['轻量入门'],
  prices: [XboardPlanPrice(period: 'onetime', amount: 3800)],
);

const _plan100G = XboardPlanOffer(
  id: 103,
  name: '100G 永久流量包',
  transferGiB: 100,
  speedLimit: 0,
  deviceLimit: 0,
  resetTrafficMethod: 2,
  tags: ['日常常备'],
  prices: [XboardPlanPrice(period: 'onetime', amount: 7500)],
);

const _plan200G = XboardPlanOffer(
  id: 102,
  name: '200G 永久流量包',
  transferGiB: 200,
  speedLimit: 0,
  deviceLimit: 0,
  resetTrafficMethod: 2,
  tags: ['主力推荐'],
  prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
);

const _plan500G = XboardPlanOffer(
  id: 104,
  name: '500G 永久流量包',
  transferGiB: 500,
  speedLimit: 0,
  deviceLimit: 0,
  resetTrafficMethod: 2,
  tags: ['超值囤货'],
  prices: [XboardPlanPrice(period: 'onetime', amount: 27000)],
);

void main() {
  Future<void> pumpCenter(
    WidgetTester tester,
    PurchaseManager manager, {
    SupportManager? supportManager,
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
            supportManager: supportManager,
            openLink: (uri) async => openedLinks?.add(uri),
            openProfiles: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'TDD-BUY-01: removes WeChat backup block, shows Option A safety trust card with user copy, and card tap opens pure SupportChatSheet',
      (tester) async {
    final service = _FakeChatwootService();
    final supportManager = SupportManager(
      service: service,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
      echoIdGenerator: () => 'echo-buy-01-${service.sentContents.length + 1}',
    );
    addTearDown(supportManager.dispose);

    final api = _FakePurchaseApi();
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    // Check zh_CN UI.
    await pumpCenter(
      tester,
      manager,
      supportManager: supportManager,
      locale: const Locale('zh', 'CN'),
    );

    expect(find.textContaining('ChasingDream_2021'), findsNothing);
    expect(find.textContaining('dxm_qa'), findsNothing);
    expect(find.textContaining('备用人工协助'), findsNothing);
    expect(find.textContaining('微信号'), findsNothing);
    expect(find.textContaining('备用微信'), findsNothing);

    final lZh = AppLocalizations.of(tester.element(find.byType(PurchaseCenter)));
    expect(lZh.purchaseGetCardDescription, isNot(contains('微信')));
    expect(lZh.purchaseChannelError, isNot(contains('微信')));

    final safetyCard = find.byKey(const Key('purchase-safety-support-card'));
    await tester.ensureVisible(safetyCard);
    await tester.pumpAndSettle();
    expect(safetyCard, findsOneWidget);
    expect(
      find.descendant(
        of: safetyCard,
        matching: find.text('官方安全购卡保障 · 7×24 小时人工在线'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: safetyCard,
        matching: find.text('为了你的网络隐私与安全，购买请直接联系客服即可'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: safetyCard, matching: find.text('官方直营防伪')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: safetyCard, matching: find.text('资金安全护航')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: safetyCard, matching: find.text('全天候秒级响应')),
      findsOneWidget,
    );

    // Tapping safety card opens live support chat without auto-sending any message
    // and without showing any WeChat backup footer controls.
    await tester.tap(safetyCard);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(find.byKey(const Key('support-backup-wechat-toggle')), findsNothing);
    expect(find.byKey(const Key('support-backup-wechat-strip')), findsNothing);
    expect(service.sentContents, isEmpty);

    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);

    // Check en locale too.
    await pumpCenter(
      tester,
      manager,
      supportManager: supportManager,
      locale: const Locale('en'),
    );
    final lEn = AppLocalizations.of(tester.element(find.byType(PurchaseCenter)));
    expect(lEn.purchaseGetCardDescription.toLowerCase(), isNot(contains('wechat')));
    expect(lEn.purchaseChannelError.toLowerCase(), isNot(contains('wechat')));
    expect(find.textContaining('Backup support (WeChat)'), findsNothing);
    expect(find.textContaining('ChasingDream_2021'), findsNothing);
    expect(find.textContaining('dxm_qa'), findsNothing);
    expect(
      find.byKey(const Key('purchase-safety-support-card')),
      findsOneWidget,
    );
    expect(find.text(lEn.purchaseSafetyTitle), findsOneWidget);
    expect(find.text(lEn.purchaseSafetyBody), findsOneWidget);
  });

  testWidgets(
      'TDD-BUY-02: Buy button matches Xboard-Go 3-tier priority resolution, metadata stripping, external browser launch, and handoff banner',
      (tester) async {
    const customUnderlined50g = XboardPlanOffer(
      id: 101,
      name: '50G 永久流量包',
      transferGiB: 50,
      tags: ['轻量入门'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 3800)],
      content: '__购买链接__: <https://store.example.test/custom-50g>\n- 稳定不限速',
    );
    const markdownTitle100g = XboardPlanOffer(
      id: 103,
      name: '100G 永久流量包',
      transferGiB: 100,
      tags: ['日常常备'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 7500)],
      content: '购买链接: [Buy](<https://store.example.test/md-100g> "Card")\n- 高性价比',
    );
    const custom500g = XboardPlanOffer(
      id: 104,
      name: '300G 自定义流量包',
      transferGiB: 300,
      tags: ['特惠'],
      prices: [XboardPlanPrice(period: 'onetime', amount: 18800)],
      content: '- 全局兜底测试',
    );

    final fullChannels = XboardPurchaseChannels(
      cardStoreUrl: Uri.parse('https://store.example.test/global'),
      cardStore50gUrl: Uri.parse('https://store.example.test/tier-50g'),
      cardStore100gUrl: Uri.parse('https://store.example.test/tier-100g'),
      cardStore200gUrl: Uri.parse('https://store.example.test/tier-200g'),
      cardStore500gUrl: Uri.parse('https://store.example.test/tier-500g'),
      chatwootBaseUrl: Uri.parse('https://chat.example.test'),
      chatwootWebsiteToken: 'cw-token-test',
    );

    // Priority 1: per-plan metadata beats tier & global.
    expect(
      fullChannels.resolvePlanStoreUrl(customUnderlined50g),
      Uri.parse('https://store.example.test/custom-50g'),
    );
    expect(
      fullChannels.resolvePlanStoreUrl(markdownTitle100g),
      Uri.parse('https://store.example.test/md-100g'),
    );
    expect(
      XboardPurchaseChannels.stripPlanPurchaseMetadata(customUnderlined50g.content),
      '- 稳定不限速',
    );
    expect(
      XboardPurchaseChannels.stripPlanPurchaseMetadata(markdownTitle100g.content),
      '- 高性价比',
    );
    // Priority 2: tier URL beats global URL.
    expect(
      fullChannels.resolvePlanStoreUrl(_plan200G),
      Uri.parse('https://store.example.test/tier-200g'),
    );
    expect(
      fullChannels.resolvePlanStoreUrl(_plan500G),
      Uri.parse('https://store.example.test/tier-500g'),
    );
    // Priority 3: global URL fallback.
    expect(
      fullChannels.resolvePlanStoreUrl(custom500g),
      Uri.parse('https://store.example.test/global'),
    );

    final api = _FakePurchaseApi(
      plans: const [customUnderlined50g, markdownTitle100g, _plan200G, custom500g],
      channels: fullChannels,
    );
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    final openedLinks = <Uri>[];
    await pumpCenter(tester, manager, openedLinks: openedLinks);

    // Stripped metadata lines must not appear in rendered plan cards.
    expect(find.textContaining('__购买链接__'), findsNothing);
    expect(find.textContaining('custom-50g'), findsNothing);
    expect(find.textContaining('md-100g'), findsNothing);

    await tester.tap(find.byKey(const Key('purchase-plan-buy-101')));
    await tester.pumpAndSettle();
    expect(openedLinks, [Uri.parse('https://store.example.test/custom-50g')]);
    expect(find.byKey(const Key('purchase-handoff-banner')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('purchase-plan-buy-103')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-plan-buy-103')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('purchase-plan-buy-102')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-plan-buy-102')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('purchase-plan-buy-104')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-plan-buy-104')));
    await tester.pumpAndSettle();

    expect(openedLinks, [
      Uri.parse('https://store.example.test/custom-50g'),
      Uri.parse('https://store.example.test/md-100g'),
      Uri.parse('https://store.example.test/tier-200g'),
      Uri.parse('https://store.example.test/global'),
    ]);
  });

  testWidgets(
      'TDD-BUY-03: Buy button seamlessly falls back to live support with auto-sent inquiry when no card store URL is configured',
      (tester) async {
    final service = _FakeChatwootService();
    final supportManager = SupportManager(
      service: service,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
      echoIdGenerator: () => 'echo-buy-03-${service.sentContents.length + 1}',
    );
    addTearDown(supportManager.dispose);

    final api = _FakePurchaseApi(
      plans: const [_plan50G, _plan200G],
      channels: XboardPurchaseChannels(
        cardStoreUrl: null,
        chatwootBaseUrl: Uri.parse('https://chat.example.test'),
        chatwootWebsiteToken: 'cw-token-test',
      ),
    );
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    final openedLinks = <Uri>[];
    await pumpCenter(
      tester,
      manager,
      supportManager: supportManager,
      openedLinks: openedLinks,
    );

    final buyBtnFinder = find.byKey(const Key('purchase-plan-buy-101'));
    await tester.tap(buyBtnFinder);
    await tester.pumpAndSettle();

    expect(openedLinks, isEmpty);
    expect(find.byKey(const Key('purchase-acquire-sheet')), findsNothing);
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(
      service.sentContents,
      ['您好，我想咨询购买【50G 永久流量包 · 50 GiB（按流量 38.00）】兑换码。'],
    );

    // Close sheet and confirm the Buy CTA is NOT stuck disabled / loading.
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    final buyBtn = tester.widget<FilledButton>(buyBtnFinder);
    expect(buyBtn.onPressed, isNotNull);
  });

  testWidgets(
      'TDD-BUY-04: Get Code directly opens SupportChatSheet after lazy async channel bootstrap and auto-sends exact inquiry template',
      (tester) async {
    final service = _FakeChatwootService();
    final supportManager = SupportManager(
      service: service,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
      echoIdGenerator: () => 'echo-buy-04-${service.sentContents.length + 1}',
    );
    addTearDown(supportManager.dispose);

    final api = _FakePurchaseApi(
      plans: const [_plan50G, _plan200G],
      // First guest channel fetch fails so channelError != null until retried on demand.
      failGuestChannels: true,
    );
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    // Ensure initial failed channel fetch settled before pumping.
    await manager.ensurePurchaseChannels(force: true);
    expect(manager.purchaseChannels, isNull);
    expect(supportManager.isConfigured, isFalse);

    await pumpCenter(
      tester,
      manager,
      supportManager: supportManager,
    );

    // Delay the retry channel fetch asynchronously when clicking "获取兑换码".
    final channelGate = Completer<XboardPurchaseChannels>();
    api
      ..failGuestChannels = false
      ..pendingGuestChannels = channelGate;

    await tester.tap(find.byKey(const Key('purchase-plan-acquire-101')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('purchase-acquire-sheet')), findsNothing);
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(service.sentContents, isEmpty);

    // Complete async channel bootstrap -> SupportManager initializes Chatwoot session & auto-sends exact inquiry.
    channelGate.complete(api.defaultChannels);
    await tester.pumpAndSettle();

    const expectedInquiry =
        '您好，我想咨询购买【50G 永久流量包 · 50 GiB（按流量 38.00）】兑换码。';
    expect(service.sentContents, [expectedInquiry]);
    expect(
      find.descendant(
        of: find.byKey(const Key('support-message-list')),
        matching: find.text(expectedInquiry),
      ),
      findsOneWidget,
    );
    final composer = tester.widget<TextField>(
      find.byKey(const Key('support-composer')),
    );
    expect(composer.controller?.text, isEmpty);
  });

  testWidgets(
      'TDD-BUY-05: enforces 60s duplicate auto-send idempotency for same plan while allowing immediate send for different plan and resend after 60s',
      (tester) async {
    var fakeNow = DateTime.utc(2026, 11, 15, 10, 0, 0);
    final service = _FakeChatwootService(nowProvider: () => fakeNow);
    final supportManager = SupportManager(
      service: service,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
      echoIdGenerator: () => 'echo-buy-05-${service.sentContents.length + 1}',
      clock: () => fakeNow,
    );
    addTearDown(supportManager.dispose);

    final api = _FakePurchaseApi(plans: const [_plan50G, _plan200G]);
    final manager = PurchaseManager(
      api: api,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(manager.dispose);

    await manager.initialize();
    await manager.loadPlans();
    await manager.ensurePurchaseChannels();

    await pumpCenter(
      tester,
      manager,
      supportManager: supportManager,
    );

    const inquiry50G =
        '您好，我想咨询购买【50G 永久流量包 · 50 GiB（按流量 38.00）】兑换码。';
    const inquiry200G =
        '您好，我想咨询购买【200G 永久流量包 · 200 GiB（按流量 150.00）】兑换码。';

    // t = 0s: Tap 50G -> sends 1st message.
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-101')));
    await tester.pumpAndSettle();
    expect(service.sentContents, [inquiry50G]);
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();

    // t = 15s: Tap 50G again -> deduplicated, only opens sheet & displays existing message.
    fakeNow = fakeNow.add(const Duration(seconds: 15));
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(service.sentContents, [inquiry50G]);
    expect(
      find.descendant(
        of: find.byKey(const Key('support-message-list')),
        matching: find.text(inquiry50G),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();

    // t = 20s: Tap 200G -> different plan, sends 2nd message immediately.
    fakeNow = fakeNow.add(const Duration(seconds: 5));
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-102')));
    await tester.pumpAndSettle();
    expect(service.sentContents, [inquiry50G, inquiry200G]);
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();

    // t = 85s (> 60s after t=20s): Tap 200G -> resend permitted, sends 3rd message.
    fakeNow = fakeNow.add(const Duration(seconds: 65));
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-102')));
    await tester.pumpAndSettle();
    expect(service.sentContents, [inquiry50G, inquiry200G, inquiry200G]);
  });

  testWidgets(
      'TDD-BUY-06: falls back inquiry text into composer when channel unconfigured or conversation locked, and renders without overflow across 4 locales at 320x800 2.0x',
      (tester) async {
    const inquiry50G =
        '您好，我想咨询购买【50G 永久流量包 · 50 GiB（按流量 38.00）】兑换码。';

    // Case A: Chatwoot not configured -> opens sheet with inquiry retained in composer.
    final unconfiguredService = _FakeChatwootService();
    final unconfiguredSupport = SupportManager(
      service: unconfiguredService,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
    );
    addTearDown(unconfiguredSupport.dispose);

    final unconfiguredApi = _FakePurchaseApi(
      plans: const [_plan50G],
      channels: XboardPurchaseChannels(
        cardStoreUrl: Uri.parse('https://store.example.test/all'),
      ),
    );
    final unconfiguredManager = PurchaseManager(
      api: unconfiguredApi,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(unconfiguredManager.dispose);

    await unconfiguredManager.initialize();
    await unconfiguredManager.loadPlans();
    await unconfiguredManager.ensurePurchaseChannels();

    await pumpCenter(
      tester,
      unconfiguredManager,
      supportManager: unconfiguredSupport,
    );
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsOneWidget);
    expect(unconfiguredService.sentContents, isEmpty);
    final unconfiguredComposer = tester.widget<TextField>(
      find.byKey(const Key('support-composer')),
    );
    expect(unconfiguredComposer.controller?.text, inquiry50G);
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);

    // Case B: Conversation locked (resolved + allowMessagesAfterResolved=false) -> composer fallback.
    final lockedService = _FakeChatwootService()
      ..conversation = const ChatwootConversation(id: 501, status: 'resolved');
    final lockedSupport = SupportManager(
      service: lockedService,
      storage: _MemChatwootStorage(),
      realtimeConnector: (_, __) async => _FakeRealtime(),
    );
    addTearDown(lockedSupport.dispose);

    final configuredApi = _FakePurchaseApi(plans: const [_plan50G]);
    final lockedManager = PurchaseManager(
      api: configuredApi,
      storage: _MemPurchaseStorage(),
      synchronize: (_, __) async {},
    );
    addTearDown(lockedManager.dispose);

    await lockedManager.initialize();
    await lockedManager.loadPlans();
    await lockedManager.ensurePurchaseChannels();

    await pumpCenter(
      tester,
      lockedManager,
      supportManager: lockedSupport,
    );
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-locked-banner')), findsOneWidget);
    expect(lockedService.sentContents, isEmpty);
    final lockedComposer = tester.widget<TextField>(
      find.byKey(const Key('support-composer')),
    );
    expect(lockedComposer.controller?.text, inquiry50G);
    await tester.tap(find.byKey(const Key('support-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-chat-sheet')), findsNothing);

    // Case C: 4 locales at 320x800 with 2.0x textScale have zero RenderFlex overflows.
    for (final locale in const [
      Locale('zh', 'CN'),
      Locale('en'),
      Locale('ja'),
      Locale('ru'),
    ]) {
      await pumpCenter(
        tester,
        lockedManager,
        supportManager: lockedSupport,
        size: const Size(320, 800),
        locale: locale,
        textScale: 2.0,
      );
      await tester.ensureVisible(
        find.byKey(const Key('purchase-safety-support-card')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Expected zero overflow in $locale at 320x800 2.0x',
      );
    }
  });
}

class _MemPurchaseStorage implements PurchaseStorage {
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

class _FakePurchaseApi implements XboardApi, XboardExtendedApi {
  _FakePurchaseApi({
    this.plans = const [_plan50G, _plan100G, _plan200G, _plan500G],
    XboardPurchaseChannels? channels,
    this.failGuestChannels = false,
  }) : _channels = channels;

  final List<XboardPlanOffer> plans;
  final XboardPurchaseChannels? _channels;
  bool failGuestChannels;
  Completer<XboardPurchaseChannels>? pendingGuestChannels;

  final XboardPurchaseChannels defaultChannels = XboardPurchaseChannels(
    cardStoreUrl: Uri.parse('https://store.example.test/global'),
    chatwootBaseUrl: Uri.parse('https://chat.example.test'),
    chatwootWebsiteToken: 'cw-token-test',
  );

  @override
  final Uri baseUri = Uri.parse('https://fast.hjy.ca:8443');

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async =>
      XboardPlanCatalog(plans: plans);

  @override
  Future<XboardPurchaseChannels> getGuestPurchaseChannels() async {
    if (pendingGuestChannels != null) {
      final gate = pendingGuestChannels!;
      pendingGuestChannels = null;
      return gate.future;
    }
    if (failGuestChannels) {
      throw const XboardException(code: 'connection_error', message: '');
    }
    return _channels ?? defaultChannels;
  }

  @override
  Future<XboardPurchaseChannels> getUserPurchaseChannels(
    String authorization,
  ) =>
      getGuestPurchaseChannels();

  @override
  Future<String> register(String email, String password) async =>
      'Bearer reg-token';

  @override
  Future<String> login(String email, String password) async =>
      'Bearer login-token';

  @override
  Future<XboardAccount> getAccount(String authorization) async =>
      const XboardAccount(id: 1, email: 'buyer@example.test');

  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      XboardSubscription(
        valid: false,
        planId: null,
        planName: null,
        total: 0,
        url: Uri.parse('https://fast.hjy.ca:8443/sub'),
      );

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization, {int page = 1}) async =>
      GiftHistoryPage(entries: const [], page: page, lastPage: 1, total: 0);

  @override
  Future<Uri?> getCardStore(String authorization) async =>
      (_channels ?? defaultChannels).cardStoreUrl;

  @override
  Future<GiftPreview> checkGift(String authorization, String code) =>
      throw UnimplementedError();

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout(String authorization) async {}

  @override
  void close() {}
}

class _MemChatwootStorage implements ChatwootSessionStorage {
  final Map<String, ChatwootSession> _store = {};

  @override
  Future<void> clearSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async {
    _store.remove('${baseUrl.origin}|$websiteToken|$scopeKey');
  }

  @override
  Future<ChatwootSession?> readSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async =>
      _store['${baseUrl.origin}|$websiteToken|$scopeKey'];

  @override
  Future<void> saveSession({
    required Uri baseUrl,
    required String websiteToken,
    required ChatwootSession session,
  }) async {
    _store['${baseUrl.origin}|$websiteToken|${session.scopeKey}'] = session;
  }
}

class _FakeRealtime implements ChatwootRealtimeConnection {
  final StreamController<ChatwootRealtimeEvent> _controller =
      StreamController<ChatwootRealtimeEvent>.broadcast();
  bool _closed = false;

  @override
  Stream<ChatwootRealtimeEvent> get events => _controller.stream;

  @override
  Future<void> get done => _controller.done;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> sendPresence() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

class _FakeChatwootService implements ChatwootService {
  _FakeChatwootService({DateTime Function()? nowProvider})
      : _nowProvider = nowProvider;

  final DateTime Function()? _nowProvider;
  ChatwootConversation conversation = const ChatwootConversation(
    id: 501,
    status: 'open',
  );
  final List<ChatwootMessage> messages = [];
  final List<String> sentContents = [];
  int _nextId = 100;

  @override
  Future<
      ({
        ChatwootChannelConfig config,
        String authToken,
        ChatwootContact contact,
      })> initializeSession({
    required Uri baseUrl,
    required String websiteToken,
    String? authToken,
  }) async =>
      (
        config: ChatwootChannelConfig(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          websiteName: 'FreedomNet 客服',
          welcomeTitle: '欢迎光临',
          welcomeTagline: '通常 5 分钟内回复',
          replyTime: '通常几分钟内回复',
          allowMessagesAfterResolved: false,
        ),
        authToken: authToken ?? 'cw-auth-1',
        contact: const ChatwootContact(
          id: 9001,
          name: 'Visitor',
          pubsubToken: 'pubsub-1',
        ),
      );

  @override
  Future<ChatwootContact?> updateContact({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  }) async =>
      null;

  @override
  Future<ChatwootConversation?> fetchConversation({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async =>
      conversation;

  @override
  Future<List<ChatwootMessage>> fetchMessages({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  }) async {
    if (after != null) {
      return messages.where((m) => (m.id ?? 0) > after).toList();
    }
    return List<ChatwootMessage>.from(messages);
  }

  @override
  Future<ChatwootMessage> sendMessage({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    required String content,
    required String echoId,
  }) async {
    sentContents.add(content);
    final created = ChatwootMessage(
      id: _nextId++,
      echoId: echoId,
      content: content,
      type: ChatwootMessageType.visitor,
      createdAt: (_nowProvider?.call() ?? DateTime.now()).toUtc(),
    );
    messages.add(created);
    return created;
  }

  @override
  Future<void> updateLastSeen({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async {}

  @override
  void close() {}
}
