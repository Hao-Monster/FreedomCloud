import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = XboardAccount(id: 7, email: 'member@example.test');
const _reward = GiftReward(
  purchaseSnapshot: GiftPurchaseSnapshot(
    planId: 3,
    planName: 'Travel plan',
    period: 'monthly',
    transferEnable: 107374182400,
  ),
);
const _preview = GiftPreview(
  codeId: 9,
  type: 4,
  name: 'Monthly gift',
  canRedeem: true,
  rewards: _reward,
  purchasePreview: GiftPurchasePreview(
    transferBefore: 107374182400,
    transferAfter: 107374182400,
    usedTraffic: 1073741824,
    renewal: true,
  ),
);

void main() {
  Future<void> showCenter(
    WidgetTester tester,
    _Manager manager, {
    Size size = const Size(1000, 900),
    List<Uri>? openedLinks,
    double textScale = 1,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
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
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'previews the current account and redeems only after confirmation',
      (tester) async {
    final manager = _Manager();
    await showCenter(tester, manager);
    await tester.enterText(find.byKey(const Key('purchase-code')), 'ABCD1234');
    await tap(tester, 'purchase-check');
    expect(manager.checked, 1);
    expect(manager.redeemed, 0);
    expect(find.text('Redeem for: member@example.test'), findsOneWidget);
    expect(find.textContaining('100 GiB → 100 GiB'), findsOneWidget);
    expect(find.textContaining('Used traffic is preserved: 1 GiB'),
        findsOneWidget);
    await tap(tester, 'purchase-redeem');
    expect(manager.redeemed, 1);
    expect(find.textContaining('Gift card redeemed'), findsOneWidget);
    expect(find.byKey(const Key('purchase-redeem')), findsNothing);
  });

  testWidgets('ineligible preview has a disabled confirmation button',
      (tester) async {
    final manager = _Manager()
      ..nextPreview = const GiftPreview(
        codeId: 9,
        type: 4,
        name: 'Other plan',
        canRedeem: false,
        reason: 'This card belongs to a different plan.',
        rewards: _reward,
      );
    await showCenter(tester, manager);
    await tester.enterText(find.byKey(const Key('purchase-code')), 'ABCD1234');
    await tap(tester, 'purchase-check');
    expect(find.text('This card belongs to a different plan.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('purchase-redeem')),
            )
            .onPressed,
        isNull);
    expect(manager.redeemed, 0);
  });

  testWidgets('editing the code invalidates its preview', (tester) async {
    final manager = _Manager();
    await showCenter(tester, manager);
    await tester.enterText(find.byKey(const Key('purchase-code')), 'ABCD1234');
    await tap(tester, 'purchase-check');
    expect(find.byKey(const Key('purchase-redeem')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('purchase-code')), 'OTHER1234');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-redeem')), findsNothing);
    expect(manager.redeemed, 0);
  });

  testWidgets('mystery preview hides the sampled reward', (tester) async {
    final manager = _Manager()
      ..nextPreview = const GiftPreview(
        codeId: 9,
        type: 3,
        name: 'Mystery gift',
        canRedeem: true,
        rewards: GiftReward(balance: 99900),
      );
    await showCenter(tester, manager);
    await tester.enterText(find.byKey(const Key('purchase-code')), 'ABCD1234');
    await tap(tester, 'purchase-check');
    expect(find.textContaining('actual benefits are revealed after redemption'),
        findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
  });

  testWidgets(
      'successful redemption remains visible if subscription sync fails',
      (tester) async {
    final manager = _Manager()
      ..receipt =
          const GiftReceipt(templateName: 'Monthly gift', rewards: _reward)
      ..syncError = const XboardException(
        code: 'sync_failed',
        message: 'Subscription download timed out.',
      );
    await showCenter(tester, manager);
    expect(find.textContaining('Gift card redeemed'), findsOneWidget);
    expect(
        find.textContaining('Redemption is complete. Subscription sync failed'),
        findsOneWidget);
    await tap(tester, 'purchase-sync');
    expect(manager.syncCalls, 1);
    expect(manager.redeemed, 0);
  });

  testWidgets('unknown redemption disables new codes and exposes recovery',
      (tester) async {
    final manager = _Manager()
      ..code = 'ABCD1234'
      ..unresolvedRedemption = true;
    await showCenter(tester, manager);
    expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('purchase-code')),
            )
            .enabled,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('purchase-check')),
            )
            .onPressed,
        isNull);
    await tap(tester, 'purchase-recover');
    expect(manager.recoveryCalls, 1);
    expect(manager.redeemed, 0);
  });

  testWidgets('completed sync has visible confirmation', (tester) async {
    final manager = _Manager()..subscriptionSynced = true;
    await showCenter(tester, manager);
    expect(find.text('Subscription synced successfully.'), findsOneWidget);
  });

  testWidgets('client error codes produce readable localized feedback',
      (tester) async {
    final manager = _Manager()
      ..error = const XboardException(code: 'gift_code_format', message: '');
    await showCenter(tester, manager);
    expect(
      find.text('Enter an 8–32 character code using letters and numbers.'),
      findsOneWidget,
    );
  });

  testWidgets('balance credits do not claim a subscription was activated',
      (tester) async {
    final manager = _Manager()
      ..receipt = const GiftReceipt(
        templateName: 'Balance gift',
        rewards: GiftReward(balance: 2500),
      );
    await showCenter(tester, manager);
    expect(
        find.textContaining(
            'A balance credit does not activate a subscription.'),
        findsOneWidget);
    expect(find.textContaining('¥25.00'), findsOneWidget);
  });

  testWidgets('history loads the requested page and respects boundaries',
      (tester) async {
    final manager = _Manager()..history = _history(1);
    await showCenter(tester, manager);
    expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('purchase-history-previous')),
            )
            .onPressed,
        isNull);
    await tap(tester, 'purchase-history-next');
    expect(manager.requestedPages, [2]);
    expect(find.textContaining('Page: 2 / 2'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('purchase-history-next')),
            )
            .onPressed,
        isNull);
  });

  testWidgets('narrow layout wraps long errors and keeps actions reachable',
      (tester) async {
    final manager = _Manager()
      ..error = XboardException(
        code: 'not_eligible',
        message: List.filled(8, 'Resolve an existing order before redeeming.')
            .join(' '),
      )
      ..preview = _preview
      ..code = 'ABCD1234'
      ..history = _history(1);
    await showCenter(tester, manager,
        size: const Size(320, 640), textScale: 1.3);
    await tester.ensureVisible(find.byKey(const Key('purchase-history-next')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('WeChat ID: dxm_qa'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'login supports website account routes and clears password on logout',
      (tester) async {
    final manager = _Manager()..account = null;
    final links = <Uri>[];
    await showCenter(tester, manager, openedLinks: links);
    await tester.tap(find.text('Create account on website'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset password on website'));
    await tester.pumpAndSettle();
    expect(links.map((uri) => uri.fragment), ['/register', '/forgetpassword']);
    await tester.enterText(
        find.byKey(const Key('purchase-email')), _account.email);
    await tester.enterText(
        find.byKey(const Key('purchase-password')), 'test-password');
    await tap(tester, 'purchase-login');
    expect(manager.logins, 1);
    await tap(tester, 'purchase-logout');
    expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('purchase-password')),
            )
            .controller!
            .text,
        isEmpty);
    expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('purchase-email')),
            )
            .controller!
            .text,
        isEmpty);
  });

  testWidgets('Chinese history and preview render on a narrow viewport',
      (tester) async {
    final manager = _Manager()
      ..history = _history(1)
      ..preview = _preview
      ..code = 'ABCD1234';
    await showCenter(
      tester,
      manager,
      locale: const Locale('zh', 'CN'),
      size: const Size(320, 640),
    );
    expect(find.text('礼品卡兑换'), findsOneWidget);
    expect(find.text('确认兑换'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('purchase-history-next')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

GiftHistoryPage _history(int page) => GiftHistoryPage(
      entries: [
        GiftHistoryEntry(
          id: page,
          codeId: page,
          maskedCode: 'ABCD****',
          templateName: 'Gift $page',
          rewards: _reward,
          usedAt: DateTime.utc(2026, 10, 4),
        ),
      ],
      page: page,
      lastPage: 2,
      total: 2,
    );

class _Api implements XboardApi {
  @override
  final Uri baseUri = Uri.parse('https://example.test/');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager extends ChangeNotifier implements PurchaseManager {
  @override
  XboardPlanCatalog? planCatalog;
  @override
  bool plansLoading = false;
  @override
  XboardException? plansError;
  @override
  Future<void> loadPlans() async {}

  @override
  final XboardApi api = _Api();
  @override
  XboardAccount? account = _account;
  @override
  XboardSubscription? subscription = XboardSubscription(
    planId: 3,
    planName: 'Travel plan',
    valid: true,
    url: Uri.parse('https://example.test/subscribe'),
    total: 107374182400,
  );
  @override
  GiftPreview? preview;
  GiftPreview nextPreview = _preview;
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
  Uri? cardStoreUrl;
  @override
  bool restoring = false;
  @override
  bool busy = false;
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
  int syncCalls = 0;
  int recoveryCalls = 0;
  int logins = 0;
  List<int> requestedPages = [];

  @override
  bool get loggedIn => account != null;
  @override
  bool get canRedeem => (preview?.canRedeem ?? false) && !unresolvedRedemption;
  @override
  bool get canSync => loggedIn;

  @override
  void setCode(String value) {
    code = value;
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
    receipt =
        GiftReceipt(templateName: preview!.name, rewards: preview!.rewards);
    preview = null;
    code = '';
    notifyListeners();
  }

  @override
  Future<void> recoverRedemption() async {
    recoveryCalls++;
  }

  @override
  Future<void> syncSubscription() async {
    syncCalls++;
  }

  @override
  Future<void> loadHistory(int page) async {
    requestedPages.add(page);
    history = _history(page);
    notifyListeners();
  }

  @override
  Future<void> login(String email, String password) async {
    logins++;
    account = _account;
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    account = null;
    code = '';
    preview = null;
    receipt = null;
    notifyListeners();
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> initialize() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
