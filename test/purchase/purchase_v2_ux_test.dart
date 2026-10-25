import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
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
    await tester.ensureVisible(find.byKey(const Key('purchase-history-toggle')));
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
    final loginElement = tester.element(find.byKey(const Key('purchase-login')));
    var loginFocused = FocusManager.instance.primaryFocus?.context == loginElement;
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
        url: Uri.parse('https://panel.example.test/api/v1/client/subscribe?token=SYNTH'),
      ),
    );
    expect(savedProfiles.single.label, isNot(contains('Xboard')));
    expect(savedProfiles.single.label, contains(_account.email));
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
  int redeemed = 0;

  @override
  bool get loggedIn => account != null;
  @override
  bool get canRedeem => (preview?.canRedeem ?? false) && !unresolvedRedemption;
  @override
  bool get canSync => loggedIn;

  @override
  void setCode(String value) {
    code = value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    preview = null;
    notifyListeners();
  }

  @override
  Future<void> checkCode() async {
    checked++;
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
  Future<void> logout() async {
    account = null;
    notifyListeners();
  }

  @override
  Future<void> loadHistory(int page) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
