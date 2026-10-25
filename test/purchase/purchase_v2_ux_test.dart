import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flclashx/views/purchase/plan_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = XboardAccount(id: 42, email: 'vip@example.test');

const _usFlagshipPlan = XboardPlanOffer(
  id: 1,
  name: 'ultra线路-美国',
  transferGiB: 200,
  speedLimit: 0,
  deviceLimit: 0,
  resetTrafficMethod: 2,
  capacityRemaining: null,
  hasSpeedLimit: true,
  hasDeviceLimit: true,
  hasResetTrafficMethod: true,
  hasCapacityRemaining: true,
  tags: ['IEPL专线', '流媒体解锁'],
  prices: [XboardPlanPrice(period: 'onetime', amount: 15000)],
  content: '''
## 套餐特点
- 美国原生高速专线
- 一次性流量包无时间限制
- 支持 Windows / macOS / iOS / Android
- 全天晚高峰低延迟稳定连接

## 使用说明
1. 点击获取兑换码联系客服或前往商店
2. 登录账户后输入兑换码查询权益
3. 确认兑换后自动同步订阅配置

## 注意事项
- 请妥善保管兑换码勿泄露给他人
- 最终开通套餐以兑换码预览为准
''',
);

const _mixedPlans = <XboardPlanOffer>[
  _usFlagshipPlan,
  XboardPlanOffer(
    id: 2,
    name: 'Global Pro · 日本/新加坡',
    transferGiB: 500,
    speedLimit: 500,
    deviceLimit: 5,
    resetTrafficMethod: 0,
    capacityRemaining: 8,
    prices: [
      XboardPlanPrice(period: 'monthly', amount: 2990),
      XboardPlanPrice(period: 'yearly', amount: 29900),
    ],
  ),
  XboardPlanOffer(
    id: 3,
    name: 'Sold Out Limited',
    transferGiB: 100,
    capacityRemaining: 0,
    prices: [XboardPlanPrice(period: 'monthly', amount: 990)],
  ),
];

const _planBPreview = GiftPreview(
  codeId: 88,
  type: 4,
  name: 'Global Pro 月付兑换码',
  canRedeem: true,
  rewards: GiftReward(
    purchaseSnapshot: GiftPurchaseSnapshot(
      planId: 2,
      planName: 'Global Pro · 日本/新加坡',
      period: 'monthly',
      transferEnable: 536870912000,
    ),
  ),
  purchasePreview: GiftPurchasePreview(
    transferBefore: 214748364800,
    transferAfter: 536870912000,
    usedTraffic: 10737418240,
    expiresBefore: null,
    expiresAfter: null,
    renewal: false,
  ),
);

void main() {
  Future<void> pumpCenter(
    WidgetTester tester,
    _UxManager manager, {
    Size size = const Size(1280, 900),
    Locale locale = const Locale('zh', 'CN'),
    Brightness brightness = Brightness.dark,
    double textScale = 1.0,
    List<Uri>? openedLinks,
    VoidCallback? onOpenProfiles,
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
            openProfiles: onOpenProfiles ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'R01/R03/R12: desktop wide dual-column places single flagship plan beside reachable workbench without Xboard branding',
      (tester) async {
    final manager = _UxManager()
      ..account = null
      ..planCatalog = const XboardPlanCatalog(plans: [_usFlagshipPlan]);
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    // De-Xboarded copywriting.
    expect(find.textContaining('Xboard'), findsNothing);

    // Side-by-side dual-column geometry.
    final plansRect = tester.getRect(find.byKey(const Key('purchase-plans')));
    final workbenchRect =
        tester.getRect(find.byKey(const Key('purchase-workbench')));
    expect(plansRect.right, lessThanOrEqualTo(workbenchRect.left));

    // Single flagship plan spans full left catalog column instead of leaving a half-column void.
    final cardRect = tester.getRect(find.byKey(const Key('purchase-plan-1')));
    expect(cardRect.width, greaterThan(550));

    // Login form is immediately visible in initial 900px viewport with zero scroll.
    final loginRect = tester.getRect(find.byKey(const Key('purchase-login')));
    expect(loginRect.bottom, lessThanOrEqualTo(900));

    // Country flag badge is detected for "ultra线路-美国" and rendered with Twemoji font.
    final flagBadge = find.byKey(const Key('purchase-plan-flag-1'));
    expect(flagBadge, findsOneWidget);
    final richTexts = tester.widgetList<RichText>(
      find.descendant(of: flagBadge, matching: find.byType(RichText)),
    );
    expect(
      richTexts.any((rt) => rt.text.toPlainText().contains('🇺🇸')),
      isTrue,
    );
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        spans.add(span);
        span.children?.forEach(collect);
      }
    }

    for (final rt in richTexts) {
      collect(rt.text);
    }
    expect(
      spans.any((s) =>
          (s.text?.contains('🇺🇸') ?? false) &&
          s.style?.fontFamily == FontFamily.twEmoji.value),
      isTrue,
    );
  });

  testWidgets(
      'R03: signed-in desktop keeps code input reachable on first screen even with 6 plans',
      (tester) async {
    final sixPlans = List<XboardPlanOffer>.generate(
      6,
      (index) => XboardPlanOffer(
        id: index + 1,
        name: 'Plan #${index + 1}',
        transferGiB: 100 * (index + 1),
        prices: const [XboardPlanPrice(period: 'monthly', amount: 1990)],
      ),
    );
    final manager = _UxManager()
      ..account = _account
      ..planCatalog = XboardPlanCatalog(plans: sixPlans);
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    final codeRect = tester.getRect(find.byKey(const Key('purchase-code')));
    final checkRect = tester.getRect(find.byKey(const Key('purchase-check')));
    expect(codeRect.top, greaterThanOrEqualTo(0));
    expect(checkRect.bottom, lessThanOrEqualTo(900));
  });

  testWidgets(
      'R02/R04: contextual plan CTA opens acquisition sheet, copies inquiry phrase without creating orders, and code preview still follows redeemed code',
      (tester) async {
    final copied = <String>[];
    var clipboardText = '您的卡密： synth-8888-code ';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final value = (call.arguments as Map)['text'] as String;
        copied.add(value);
        clipboardText = value;
      } else if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final openedLinks = <Uri>[];
    final manager = _UxManager()
      ..account = _account
      ..planCatalog = const XboardPlanCatalog(plans: _mixedPlans)
      ..nextPreview = _planBPreview;
    await pumpCenter(
      tester,
      manager,
      size: const Size(1280, 900),
      openedLinks: openedLinks,
    );

    // Sold-out plan (capacityRemaining == 0) disables its acquire CTA.
    final soldOutButton = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('purchase-plan-acquire-3')),
    );
    expect(soldOutButton.onPressed, isNull);

    // Long Markdown details on plan 1 are collapsed by default in PurchaseCenter and expand on tap.
    expect(find.text('最终开通套餐以兑换码预览为准', findRichText: true), findsNothing);
    await tester.tap(find.byKey(const Key('purchase-plan-details-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('最终开通套餐以兑换码预览为准', findRichText: true), findsOneWidget);

    // Category filter pills filter between period and onetime plans.
    await tester.tap(find.byKey(const Key('purchase-plans-filter-period')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-plan-1')), findsNothing);
    expect(find.byKey(const Key('purchase-plan-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-plans-filter-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-plan-1')), findsOneWidget);

    // Open contextual acquisition sheet for Plan 1 (Plan A).
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-acquire-sheet')), findsOneWidget);
    expect(manager.checked, 0);
    expect(manager.redeemed, 0);

    // Copy contextual inquiry text and open card store from sheet.
    await tester.tap(find.byKey(const Key('purchase-acquire-copy-inquiry')));
    await tester.pumpAndSettle();
    expect(copied.single, contains('ultra线路-美国'));
    expect(copied.single, contains('200 GiB'));
    expect(copied.single, contains('150.00'));

    await tester.tap(find.byKey(const Key('purchase-acquire-store')));
    await tester.pumpAndSettle();
    expect(openedLinks, [Uri.parse('https://shop.example.test/cards')]);

    // Dismiss sheet, then paste messy code for Plan B and verify preview shows Plan B without rebinding.
    clipboardText = '您的兑换码： planb-2026-vip ';
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-acquire-sheet')), findsNothing);

    await tester.tap(find.byKey(const Key('purchase-code-paste')));
    await tester.pumpAndSettle();
    expect(manager.code, 'PLANB2026VIP');

    await tester.tap(find.byKey(const Key('purchase-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-preview-card')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('purchase-preview-card')),
        matching: find.textContaining('Global Pro · 日本/新加坡'),
      ),
      findsOneWidget,
    );
    expect(manager.redeemed, 0);

    // Clear button resets code and invalidates preview.
    await tester.tap(find.byKey(const Key('purchase-code-clear')));
    await tester.pumpAndSettle();
    expect(manager.code, isEmpty);
    expect(find.byKey(const Key('purchase-preview-card')), findsNothing);
  });

  testWidgets(
      'R08/R11: redemption history is collapsed by default, expands on demand, and post-redemption exposes quick profile navigation',
      (tester) async {
    var openedProfiles = 0;
    final manager = _UxManager()
      ..account = _account
      ..subscriptionSynced = true
      ..receipt = GiftReceipt(
        templateName: 'Global Pro 月付兑换码',
        rewards: _planBPreview.rewards,
        orderTradeNo: 'ORD-20261025',
      )
      ..history = GiftHistoryPage(
        entries: [
          GiftHistoryEntry(
            id: 1,
            codeId: 88,
            maskedCode: 'PLAN****VIP',
            templateName: 'Global Pro 月付兑换码',
            rewards: _planBPreview.rewards,
            usedAt: DateTime.utc(2026, 10, 25, 8),
            orderTradeNo: 'ORD-20261025',
          ),
        ],
        page: 1,
        lastPage: 2,
        total: 2,
      );

    await pumpCenter(
      tester,
      manager,
      size: const Size(1280, 900),
      onOpenProfiles: () => openedProfiles++,
    );

    // Quick action after successful redemption triggers openProfiles.
    await tester.ensureVisible(find.byKey(const Key('purchase-open-profiles')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-open-profiles')));
    await tester.pumpAndSettle();
    expect(openedProfiles, 1);

    // History is collapsed by default.
    expect(find.byKey(const Key('purchase-history-toggle')), findsOneWidget);
    expect(find.byKey(const Key('purchase-history-next')), findsNothing);

    // Expanding history reveals masked entry and pagination controls.
    await tester
        .ensureVisible(find.byKey(const Key('purchase-history-toggle')));
    await tester.tap(find.byKey(const Key('purchase-history-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PLAN****VIP'), findsOneWidget);
    expect(find.byKey(const Key('purchase-history-next')), findsOneWidget);
  });

  testWidgets(
      'R12: narrow viewport provides one-tap jump to workbench and password visibility toggle skips Tab focus trap',
      (tester) async {
    final manager = _UxManager()
      ..account = null
      ..planCatalog = const XboardPlanCatalog(plans: _mixedPlans);
    await pumpCenter(
      tester,
      manager,
      locale: const Locale('en'),
      size: const Size(360, 640),
      brightness: Brightness.light,
    );

    expect(find.textContaining('Xboard'), findsNothing);
    final jumpButton = find.byKey(const Key('purchase-jump-workbench'));
    expect(jumpButton, findsOneWidget);
    await tester.tap(jumpButton);
    await tester.pumpAndSettle();

    final loginRect = tester.getRect(find.byKey(const Key('purchase-login')));
    expect(loginRect.top, lessThan(640));

    // Toggle password visibility and verify obscureText flips without breaking Tab order.
    EditableText passwordEditable() => tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('purchase-password')),
            matching: find.byType(EditableText),
          ),
        );
    expect(passwordEditable().obscureText, isTrue);
    await tester.tap(find.byKey(const Key('purchase-password-visibility')));
    await tester.pumpAndSettle();
    expect(passwordEditable().obscureText, isFalse);

    // Focus email -> Tab -> password -> Tab -> login (visibility icon skipped).
    await tester.tap(find.byKey(const Key('purchase-email')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(passwordEditable().focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final loginElement =
        tester.element(find.byKey(const Key('purchase-login')));
    var loginFocused =
        FocusManager.instance.primaryFocus?.context == loginElement;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((el) {
      loginFocused |= el == loginElement;
      return !loginFocused;
    });
    expect(loginFocused, isTrue);
    expect(tester.takeException(), isNull);

    // Also verify 2.0x text scale in dark theme on narrow viewport without overflow.
    final scaledManager = _UxManager()
      ..account = _account
      ..planCatalog = const XboardPlanCatalog(plans: _mixedPlans)
      ..preview = _planBPreview
      ..code = 'PLANBVIP';
    await pumpCenter(
      tester,
      scaledManager,
      size: const Size(320, 800),
      textScale: 2.0,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('purchase-redeem')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('PurchaseProfileSynchronizer creates brand-clean managed profile label',
      () async {
    final savedProfiles = <Profile>[];
    final storage = _MemProfileStorage();
    final sync = PurchaseProfileSynchronizer(
      origin: Uri.parse('https://panel.example.test'),
      storage: storage,
      readProfiles: () => List.of(savedProfiles),
      download: (target) async => target,
      save: (updated) async => savedProfiles.add(updated),
    );
    await sync.synchronize(
      _account,
      XboardSubscription(
        valid: true,
        planId: 1,
        planName: 'ultra线路-美国',
        url: Uri.parse(
            'https://panel.example.test/api/v1/client/subscribe?token=SYNTH'),
      ),
    );
    expect(savedProfiles.single.label, isNot(contains('Xboard')));
    expect(savedProfiles.single.label, contains(_account.email));
  });

  testWidgets(
      'CR-01: Markdown progressive collapse preserves leading-blank-line GFM tables and fenced code blocks',
      (tester) async {
    const richCollapsiblePlan = XboardPlanOffer(
      id: 21,
      name: '旗舰双栈专线 · 美国',
      transferGiB: 300,
      prices: [XboardPlanPrice(period: 'monthly', amount: 3900)],
      content: '\n\n\n\n'
          '| 节点 | 带宽 |\n'
          '| --- | --- |\n'
          '| 东京 | 10Gbps |\n'
          '| 新加坡 | 10Gbps |\n\n'
          '```yaml\n'
          'mode: rule\n'
          '```\n\n'
          '- 第五行补充权益说明\n'
          '- 第六行隐藏条款说明\n'
          '- 第七行隐藏条款说明\n\n'
          '尾部隐藏段落说明\n',
    );
    final manager = _UxManager()
      ..planCatalog = const XboardPlanCatalog(plans: [richCollapsiblePlan]);

    await pumpCenter(tester, manager, size: const Size(1280, 900));

    // Collapsed state keeps GFM table intact and closes code fence cleanly, while omitting tail lines.
    expect(
      find.byKey(const Key('purchase-plan-details-toggle-21')),
      findsOneWidget,
    );
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('10Gbps', findRichText: true), findsNWidgets(2));
    expect(
        find.textContaining('mode: rule', findRichText: true), findsOneWidget);
    expect(find.text('```yaml', findRichText: true), findsNothing);
    expect(find.text('尾部隐藏段落说明', findRichText: true), findsNothing);

    await tester.tap(find.byKey(const Key('purchase-plan-details-toggle-21')));
    await tester.pumpAndSettle();
    expect(find.text('尾部隐藏段落说明', findRichText: true), findsOneWidget);
  });

  testWidgets(
      'CR-02: smart paste ignores timestamps and URL ports and preserves overlong tokens for local format validation',
      (tester) async {
    var clipboardText = '您的兑换码：synth-8888-code\n'
        '官网地址：https://panel.example.test:8443/shop\n'
        '客服在线时间 09:00-18:30';
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

    final manager = _UxManager()..account = _account;
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    await tester.tap(find.byKey(const Key('purchase-code-paste')));
    await tester.pumpAndSettle();
    expect(manager.code, 'SYNTH8888CODE');

    // Clear and paste an overlong (>32 chars) invalid token; it must NOT be truncated to 32 chars.
    await tester.tap(find.byKey(const Key('purchase-code-clear')));
    await tester.pumpAndSettle();
    clipboardText = '兑换码：ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890EXTRA';
    await tester.tap(find.byKey(const Key('purchase-code-paste')));
    await tester.pumpAndSettle();
    expect(manager.code, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890EXTRA');

    await tester.tap(find.byKey(const Key('purchase-check')));
    await tester.pumpAndSettle();
    expect(manager.apiCheckCalls, 0);
    expect(manager.error?.code, 'gift_code_format');
  });

  testWidgets(
      'CR-03: acquisition sheet shows Copy label on WeChat buttons, gives modal-visible feedback, and reacts to cardStoreUrl updates',
      (tester) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final manager = _UxManager()
      ..cardStoreUrl = null
      ..planCatalog = const XboardPlanCatalog(plans: [_usFlagshipPlan]);
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    await tester.tap(find.byKey(const Key('purchase-plan-acquire-1')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('purchase-acquire-sheet'));
    expect(sheet, findsOneWidget);
    expect(find.byKey(const Key('purchase-acquire-store')), findsNothing);

    final wechatCopyBtn =
        find.byKey(const Key('purchase-acquire-wechat-ChasingDream_2021'));
    expect(
      find.descendant(of: wechatCopyBtn, matching: find.text('复制')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: wechatCopyBtn, matching: find.text('微信号')),
      findsNothing,
    );

    await tester.tap(wechatCopyBtn);
    await tester.pumpAndSettle();
    expect(copied, ['ChasingDream_2021']);
    expect(
      find.byKey(const Key('purchase-acquire-feedback')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    // Live update to cardStoreUrl while modal sheet is open updates sheet immediately.
    manager
      ..cardStoreUrl = Uri.parse('https://shop.example.test/live-cards')
      ..notify();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-acquire-store')), findsOneWidget);
  });

  testWidgets(
      'CR-04: plan region badge preserves multi-country order, shows globe for global plans, and avoids marketing false positives',
      (tester) async {
    const regionPlans = <XboardPlanOffer>[
      XboardPlanOffer(
        id: 10,
        name: '标准套餐 · 日本/新加坡',
        transferGiB: 200,
        prices: [XboardPlanPrice(period: 'monthly', amount: 1990)],
      ),
      XboardPlanOffer(
        id: 11,
        name: 'Global Pass 全球通',
        transferGiB: 500,
        prices: [XboardPlanPrice(period: 'monthly', amount: 4990)],
      ),
      XboardPlanOffer(
        id: 12,
        name: 'MY Starter Plan',
        transferGiB: 100,
        prices: [XboardPlanPrice(period: 'monthly', amount: 990)],
      ),
      XboardPlanOffer(
        id: 13,
        name: 'ALL IN ONE Plan',
        transferGiB: 150,
        prices: [XboardPlanPrice(period: 'monthly', amount: 1490)],
      ),
    ];
    final manager = _UxManager()
      ..planCatalog = const XboardPlanCatalog(plans: regionPlans);
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    expect(
      find.descendant(
        of: find.byKey(const Key('purchase-plan-flag-10')),
        matching: find.text('🇯🇵 🇸🇬', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('purchase-plan-flag-11')),
        matching: find.text('🌐', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('purchase-plan-flag-12')), findsNothing);
    expect(find.byKey(const Key('purchase-plan-flag-13')), findsNothing);
  });

  testWidgets(
      'CR-05: hybrid plan exposes category filters, whitespace toggles clear suffix immediately, and failed logout keeps UI state',
      (tester) async {
    const hybridCatalog = XboardPlanCatalog(
      plans: [
        XboardPlanOffer(
          id: 31,
          name: '弹性套餐 · 香港',
          transferGiB: 200,
          prices: [
            XboardPlanPrice(period: 'monthly', amount: 2500),
            XboardPlanPrice(period: 'onetime', amount: 6000),
          ],
        ),
        XboardPlanOffer(
          id: 32,
          name: '纯月付套餐 · 日本',
          transferGiB: 150,
          prices: [XboardPlanPrice(period: 'monthly', amount: 1800)],
        ),
      ],
    );
    final manager = _UxManager()
      ..account = _account
      ..planCatalog = hybridCatalog
      ..failLogout = true
      ..history = GiftHistoryPage(
        entries: [
          GiftHistoryEntry(
            id: 1,
            codeId: 88,
            maskedCode: 'PLAN****VIP',
            templateName: 'Global Pro 月付兑换码',
            rewards: _planBPreview.rewards,
            usedAt: DateTime.utc(2026, 10, 25, 8),
          ),
        ],
        page: 1,
        lastPage: 1,
        total: 1,
      );

    await pumpCenter(tester, manager, size: const Size(1280, 900));

    // Hybrid + recurring-only catalog displays category filter chips.
    final onetimeChip = find.byKey(const Key('purchase-plans-filter-onetime'));
    expect(onetimeChip, findsOneWidget);
    await tester.tap(onetimeChip);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-plan-31')), findsOneWidget);
    expect(find.byKey(const Key('purchase-plan-32')), findsNothing);

    // Typing pure whitespace immediately switches paste suffix to clear suffix.
    await tester.enterText(find.byKey(const Key('purchase-code')), '   ');
    await tester.pump();
    expect(find.byKey(const Key('purchase-code-clear')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-code-clear')));
    await tester.pump();
    expect(find.byKey(const Key('purchase-code-paste')), findsOneWidget);

    // Failed logout preserves code and expanded history accordion.
    await tester.enterText(find.byKey(const Key('purchase-code')), 'KEEP1234');
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const Key('purchase-history-toggle')));
    await tester.tap(find.byKey(const Key('purchase-history-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PLAN****VIP'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('purchase-logout')));
    await tester.tap(find.byKey(const Key('purchase-logout')));
    await tester.pumpAndSettle();
    expect(manager.loggedIn, isTrue);
    expect(manager.code, 'KEEP1234');
    expect(find.textContaining('PLAN****VIP'), findsOneWidget);
  });

  testWidgets(
      'CR-06: narrow jump button and code suffix action are keyboard-reachable and accordions expose expanded semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final loggedOutManager = _UxManager()
        ..account = null
        ..planCatalog = const XboardPlanCatalog(plans: [_usFlagshipPlan]);
      await pumpCenter(
        tester,
        loggedOutManager,
        locale: const Locale('en'),
        size: const Size(360, 640),
      );

      bool isFocused(Finder target) {
        final element = tester.element(target);
        var hit = FocusManager.instance.primaryFocus?.context == element;
        FocusManager.instance.primaryFocus?.context
            ?.visitAncestorElements((el) {
          hit |= el == element;
          return !hit;
        });
        return hit;
      }

      // First Tab on narrow viewport reaches purchase-jump-workbench.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        isFocused(find.byKey(const Key('purchase-jump-workbench'))),
        isTrue,
      );

      // Plan details accordion exposes button + expanded semantics state.
      final planToggle =
          find.byKey(const Key('purchase-plan-details-toggle-1'));
      await tester.ensureVisible(planToggle);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(planToggle),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(planToggle);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(planToggle),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      // Logged-in code suffix button is reachable by Tab from purchase-code, and history accordion exposes semantics.
      final loggedInManager = _UxManager()
        ..account = _account
        ..history = GiftHistoryPage(
          entries: [],
          page: 1,
          lastPage: 1,
          total: 0,
        );
      await pumpCenter(tester, loggedInManager, size: const Size(1280, 900));

      await tester.tap(find.byKey(const Key('purchase-code')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        isFocused(find.byKey(const Key('purchase-code-paste'))),
        isTrue,
      );

      final historyToggle = find.byKey(const Key('purchase-history-toggle'));
      expect(
        tester.getSemantics(historyToggle),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(historyToggle);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(historyToggle),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  test(
      'CR2-01: smart paste skips ISO dates, emails, underscored IDs, and status_code noise while supporting wrapped labels',
      () {
    const receiptBlob = '【发货通知】2026-10-25 21:30:00\n'
        '账号：user12345@gmail.com\n'
        '客服微信：wxid_abc123456\n'
        'status_code: 200\n'
        'ABCD-EFGH-1234';
    expect(extractRedemptionCodeFromClipboard(receiptBlob), 'ABCDEFGH1234');
    expect(
      extractRedemptionCodeFromClipboard('您的兑换码：`A-1234-5678`'),
      'A12345678',
    );
    expect(
      extractRedemptionCodeFromClipboard('礼品卡：【VIP-2026-PRO88】'),
      'VIP2026PRO88',
    );
    expect(
      extractRedemptionCodeFromClipboard(
        '账号:user@gmail.com，官网https://panel.example.test/shop兑换码:ABCD-1234',
      ),
      'ABCD1234',
    );
  });

  testWidgets(
      'CR2-02: mid-string lowercase edit uppercases in place without jumping cursor to end or clobbering IME composing',
      (tester) async {
    final manager = _UxManager()..account = _account;
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    final codeFinder = find.byKey(const Key('purchase-code'));
    await tester.tap(codeFinder);
    await tester.pumpAndSettle();
    await tester.enterText(codeFinder, 'ABCD1234');
    await tester.pump();

    EditableText codeEditable() => tester.widget<EditableText>(
          find.descendant(of: codeFinder, matching: find.byType(EditableText)),
        );

    // Insert lowercase 'x' at index 2 (caret moves to offset 3).
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ABxCD1234',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(codeEditable().controller.text, 'ABXCD1234');
    expect(codeEditable().controller.selection.baseOffset, 3);
    expect(manager.code, 'ABXCD1234');

    // Active IME composition range must not be wiped or prematurely uppercased.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ABniXCD1234',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 2, end: 4),
      ),
    );
    await tester.pump();
    expect(codeEditable().controller.value.composing,
        const TextRange(start: 2, end: 4));
    expect(codeEditable().controller.text, 'ABniXCD1234');
  });

  testWidgets(
      'CR2-03: summarizePlanMarkdown keeps inline triple-backtick spans as paragraph text and avoids stray closing underline tags',
      (tester) async {
    const trickyPlan = XboardPlanOffer(
      id: 41,
      name: '企业专线 · 日本',
      transferGiB: 400,
      prices: [XboardPlanPrice(period: 'monthly', amount: 4500)],
      content: '```VIP2026``` 限时福利请在右侧核销\n\n'
          '支持 `<u>` 下划线语法渲染\n\n'
          '- 香港高速节点\n'
          '- 日本高速节点\n'
          '- 新加坡高速节点\n'
          '- 美国高速节点\n'
          '- 英国高速节点\n'
          '- 德国高速节点\n',
    );
    final summary = summarizePlanMarkdown(trickyPlan.content);
    expect(summary.collapsible, isTrue);
    expect(summary.preview.trimRight().endsWith('```'), isFalse);
    expect(summary.preview.trimRight().endsWith('</u>'), isFalse);

    final severedSummary = summarizePlanMarkdown(
      '<u>第一行重点说明\n'
      '第二行仍带下划线\n'
      '第三行仍带下划线\n'
      '第四行仍带下划线\n'
      '第五行仍带下划线\n'
      '第六行隐藏且带闭合</u>\n'
      '第七行隐藏补充\n',
    );
    expect(severedSummary.collapsible, isTrue);
    expect(severedSummary.preview.endsWith('</u>'), isTrue);

    final manager = _UxManager()
      ..planCatalog = const XboardPlanCatalog(plans: [trickyPlan]);
    await pumpCenter(tester, manager, size: const Size(1280, 900));
    expect(find.text('•'), findsWidgets);
    expect(find.textContaining('</u>', findRichText: true), findsNothing);
  });

  test(
      'CR2-04: resolvePlanRegionBadge handles Traditional HK/MO, North Korea without KR overlap, explicit global override, and English marketing noise',
      () {
    expect(resolvePlanRegionBadge('中國香港專線'), '🇭🇰');
    expect(resolvePlanRegionBadge('中國澳門專線'), '🇲🇴');
    expect(resolvePlanRegionBadge('North Korea Special'), '🇰🇵');
    expect(resolvePlanRegionBadge('全球旗舰套餐（含香港专线）'), '🌐');
    expect(resolvePlanRegionBadge('Global Pro · 日本/新加坡'), '🇯🇵 🇸🇬');
    expect(resolvePlanRegionBadge(r'Pro Plan $9.9/MO'), isNull);
    expect(resolvePlanRegionBadge('ALL YOU CAN USE'), isNull);
    expect(resolvePlanRegionBadge('WE ARE PRO'), isNull);
  });

  testWidgets(
      'CR2-05: password visibility resets to obscured after login/logout and unauthenticated 401 receipt preserves order details',
      (tester) async {
    final manager = _UxManager()..account = null;
    await pumpCenter(tester, manager, size: const Size(1280, 900));

    EditableText passwordEditable() => tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('purchase-password')),
            matching: find.byType(EditableText),
          ),
        );

    await tester.tap(find.byKey(const Key('purchase-password-visibility')));
    await tester.pumpAndSettle();
    expect(passwordEditable().obscureText, isFalse);

    await tester.enterText(
      find.byKey(const Key('purchase-email')),
      'vip@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-password')),
      'secret123',
    );
    await tester.tap(find.byKey(const Key('purchase-login')));
    await tester.pumpAndSettle();
    expect(manager.loggedIn, isTrue);

    await tester.ensureVisible(find.byKey(const Key('purchase-logout')));
    await tester.tap(find.byKey(const Key('purchase-logout')));
    await tester.pumpAndSettle();
    expect(manager.loggedIn, isFalse);
    expect(passwordEditable().obscureText, isTrue);

    // Simulate confirmed redemption surviving a follow-up 401 session expiration.
    manager
      ..receipt = GiftReceipt(
        templateName: '旗舰年付卡',
        rewards: _planBPreview.rewards,
        orderTradeNo: 'ORD-401-KEEP',
      )
      ..notify();
    await tester.pumpAndSettle();
    expect(find.text('旗舰年付卡'), findsOneWidget);
    expect(find.textContaining('ORD-401-KEEP'), findsOneWidget);
  });

  testWidgets(
      'CR2-06: catalog preserves filter and expanded details across 860px resize, and acquire sheet shows channelError fallback and close button',
      (tester) async {
    final manager = _UxManager()
      ..account = _account
      ..cardStoreUrl = null
      ..channelError = const XboardException(code: 'network_error', message: '')
      ..planCatalog = const XboardPlanCatalog(plans: _mixedPlans);

    await pumpCenter(tester, manager, size: const Size(1280, 900));

    await tester.tap(find.byKey(const Key('purchase-plans-filter-onetime')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-plan-2')), findsNothing);

    await tester.tap(find.byKey(const Key('purchase-plan-details-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.text('最终开通套餐以兑换码预览为准', findRichText: true), findsOneWidget);

    // Resize across 860px dual-column -> single-column breakpoint.
    tester.view.physicalSize = const Size(620, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-plan-2')), findsNothing);
    expect(find.text('最终开通套餐以兑换码预览为准', findRichText: true), findsOneWidget);

    // Open acquire sheet and verify channelError degradation notice + explicit close button.
    await tester
        .ensureVisible(find.byKey(const Key('purchase-plan-acquire-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-plan-acquire-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-acquire-sheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('purchase-acquire-sheet')),
        matching: find.text('礼品卡商店信息加载失败，仍可通过下方微信联系客服。'),
      ),
      findsOneWidget,
    );

    final closeBtn = find.byKey(const Key('purchase-acquire-close'));
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-acquire-sheet')), findsNothing);
  });
}

class _MemProfileStorage implements PurchaseStorage {
  final Map<int, String> ids = {};
  @override
  Future<String?> readProfileId(int accountId) async => ids[accountId];
  @override
  Future<void> saveProfileId(int accountId, String profileId) async =>
      ids[accountId] = profileId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeApi implements XboardApi {
  @override
  final Uri baseUri = Uri.parse('https://panel.example.test');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UxManager extends ChangeNotifier implements PurchaseManager {
  @override
  final XboardApi api = _FakeApi();
  @override
  XboardPlanCatalog? planCatalog =
      const XboardPlanCatalog(plans: [_usFlagshipPlan]);
  @override
  bool plansLoading = false;
  @override
  XboardException? plansError;
  @override
  Future<void> loadPlans() async {}

  @override
  XboardAccount? account = _account;
  @override
  XboardSubscription? subscription = XboardSubscription(
    valid: true,
    planId: 1,
    planName: 'ultra线路-美国',
    upload: 5368709120,
    download: 16106127360,
    total: 214748364800,
    url: Uri.parse('https://panel.example.test/s/synth'),
  );
  @override
  GiftPreview? preview;
  GiftPreview nextPreview = _planBPreview;
  @override
  GiftReceipt? receipt;
  @override
  GiftHistoryPage? history;
  @override
  XboardException? error;
  @override
  XboardException? historyError;
  @override
  XboardException? syncError;
  @override
  XboardException? channelError;
  @override
  Uri? cardStoreUrl = Uri.parse('https://shop.example.test/cards');
  @override
  bool restoring = false;
  @override
  bool busy = false;
  @override
  bool get checkingCode => false;
  @override
  bool get redeemingCode => false;
  @override
  bool syncing = false;
  @override
  bool subscriptionSynced = false;
  @override
  bool unresolvedRedemption = false;
  @override
  String code = '';
  int checked = 0;
  int apiCheckCalls = 0;
  int redeemed = 0;
  bool failLogout = false;

  void notify() => notifyListeners();

  @override
  bool get loggedIn => account != null;
  @override
  bool get canRedeem => (preview?.canRedeem ?? false) && !unresolvedRedemption;
  @override
  bool get canSync => loggedIn;

  static final RegExp _codeSeparators =
      RegExp(r'[\s\u00AD\u2010-\u2015\u2212-]+');

  @override
  void setCode(String value) {
    final normalized = value.replaceAll(_codeSeparators, '').toUpperCase();
    if (normalized == code) return;
    code = normalized;
    preview = null;
    error = null;
    notifyListeners();
  }

  @override
  Future<void> checkCode() async {
    checked++;
    preview = null;
    if (!RegExp(r'^[A-Z0-9]{8,32}$').hasMatch(code)) {
      error = const XboardException(code: 'gift_code_format', message: '');
      notifyListeners();
      return;
    }
    apiCheckCalls++;
    error = null;
    preview = nextPreview;
    notifyListeners();
  }

  @override
  Future<void> redeem() async {
    redeemed++;
  }

  @override
  Future<void> syncSubscription() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> login(String email, String password) async {
    account = XboardAccount(id: 42, email: email);
    error = null;
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    if (failLogout) {
      error = const XboardException(
        code: 'secure_storage_failed',
        message: '',
      );
      notifyListeners();
      return;
    }
    account = null;
    code = '';
    notifyListeners();
  }

  @override
  Future<void> loadHistory(int page) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
