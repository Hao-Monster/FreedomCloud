import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _offers = XboardPlanCatalog(plans: [
  XboardPlanOffer(
    id: 1,
    name: 'Travel plan',
    transferGiB: 150,
    speedLimit: 200,
    deviceLimit: 3,
    prices: [
      XboardPlanPrice(period: 'monthly', amount: 1299),
      XboardPlanPrice(period: 'yearly', amount: 10000),
    ],
  ),
  XboardPlanOffer(
    id: 2,
    name: 'Starter plan',
    transferGiB: 10,
    prices: [XboardPlanPrice(period: 'onetime', amount: 0)],
  ),
]);

void main() {
  Future<void> showCenter(
    WidgetTester tester,
    _Manager manager, {
    Size size = const Size(1000, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: PurchaseCenter(
          manager: manager,
          openLink: (_) async {},
          openProfiles: () {},
        ),
      ),
    ));
    // Loading uses an indeterminate indicator, so it must not pumpAndSettle.
    await tester.pump();
  }

  testWidgets('guests see offers and prices before login with WeChat preserved',
      (tester) async {
    await showCenter(tester, _Manager());
    expect(find.text('Travel plan'), findsOneWidget);
    expect(find.text('12.99'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Traffic based'), findsOneWidget);
    expect(find.text('Traffic quota: 150 GiB'), findsOneWidget);
    expect(find.text('Speed limit: 200 Mbps'), findsOneWidget);
    expect(find.text('Device limit: 3'), findsOneWidget);
    expect(find.byKey(const Key('purchase-login')), findsOneWidget);
    expect(find.text('WeChat ID: ChasingDream_2021'), findsOneWidget);
    expect(find.text('WeChat ID: dxm_qa'), findsOneWidget);
    expect(find.text('Copy'), findsNWidgets(2));
    expect(find.text('Open gift card store'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Travel plan')).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const Key('purchase-email'))).dy));
  });

  testWidgets('signed-in offers preserve redemption, history and support',
      (tester) async {
    final manager = _Manager()
      ..account = const XboardAccount(id: 7, email: 'member@example.test');
    await showCenter(tester, manager);
    expect(find.text('Travel plan'), findsOneWidget);
    expect(find.byKey(const Key('purchase-code')), findsOneWidget);
    expect(find.byKey(const Key('purchase-check')), findsOneWidget);
    expect(find.byKey(const Key('purchase-sync')), findsOneWidget);
    expect(find.byKey(const Key('purchase-logout')), findsOneWidget);
    expect(find.text('Redemption history'), findsOneWidget);
    expect(find.text('WeChat ID: ChasingDream_2021'), findsOneWidget);
    expect(find.text('WeChat ID: dxm_qa'), findsOneWidget);
  });

  testWidgets('loading offers leaves login and existing support available',
      (tester) async {
    final manager = _Manager()
      ..planCatalog = null
      ..plansLoading = true;
    await showCenter(tester, manager);
    expect(find.byKey(const Key('purchase-plans-loading')), findsOneWidget);
    expect(find.byKey(const Key('purchase-login')), findsOneWidget);
    expect(find.text('WeChat ID: dxm_qa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog failure is isolated, readable and can retry',
      (tester) async {
    final manager = _Manager()
      ..planCatalog = null
      ..plansError = const XboardException(
        code: 'network_error',
        message: '<script>raw server error</script>',
      );
    await showCenter(tester, manager);
    expect(find.textContaining('raw server error'), findsNothing);
    expect(find.text('Plans could not be loaded. Please try again.'),
        findsOneWidget);
    expect(find.byKey(const Key('purchase-login')), findsOneWidget);
    expect(find.text('WeChat ID: dxm_qa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-plans-retry')));
    await tester.pump();
    expect(manager.planLoads, 1);
    expect(find.text('Travel plan'), findsOneWidget);
  });

  testWidgets('empty catalog has an explicit message without hiding support',
      (tester) async {
    final manager = _Manager()
      ..planCatalog = const XboardPlanCatalog(plans: []);
    await showCenter(tester, manager);
    expect(find.text('No plans are currently available.'), findsOneWidget);
    expect(find.byKey(const Key('purchase-login')), findsOneWidget);
    expect(find.text('WeChat ID: ChasingDream_2021'), findsOneWidget);
  });

  testWidgets('wide layout places two offers side by side', (tester) async {
    await showCenter(tester, _Manager());
    final first = tester.getRect(find.byKey(const Key('purchase-plan-1')));
    final second = tester.getRect(find.byKey(const Key('purchase-plan-2')));
    expect(first.top, second.top);
    expect(first.right, lessThan(second.left));
  });

  testWidgets('both existing WeChat copy actions work with offers visible',
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
    await showCenter(tester, _Manager());
    final copyButtons = find.widgetWithText(TextButton, 'Copy');
    for (var index = 0; index < 2; index++) {
      await tester.ensureVisible(copyButtons.at(index));
      await tester.pumpAndSettle();
      await tester.tap(copyButtons.at(index));
      await tester.pumpAndSettle();
    }
    expect(copied, ['ChasingDream_2021', 'dxm_qa']);
    expect(find.text('Travel plan'), findsOneWidget);
  });

  testWidgets('narrow large text preserves long names, zero prices and actions',
      (tester) async {
    final name = List.filled(8, 'Long descriptive plan name').join(' ');
    final manager = _Manager()
      ..planCatalog = XboardPlanCatalog(plans: [
        XboardPlanOffer(
          id: 1,
          name: name,
          transferGiB: 150,
          speedLimit: 1000,
          deviceLimit: 10,
          prices: const [XboardPlanPrice(period: 'onetime', amount: 0)],
        ),
        _offers.plans[1],
      ]);
    await showCenter(tester, manager, size: const Size(320, 640), textScale: 2);
    expect(find.text(name), findsOneWidget);
    expect(find.text('0.00'), findsNWidgets(2));
    final first = tester.getRect(find.byKey(const Key('purchase-plan-1')));
    final second = tester.getRect(find.byKey(const Key('purchase-plan-2')));
    expect(first.bottom, lessThan(second.top));
    await tester.ensureVisible(find.byKey(const Key('purchase-login')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('WeChat ID: dxm_qa'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('all sale periods and integer prices are displayed exactly',
      (tester) async {
    final manager = _Manager()
      ..planCatalog = const XboardPlanCatalog(plans: [
        XboardPlanOffer(id: 1, name: 'Every period', transferGiB: 1, prices: [
          XboardPlanPrice(period: 'monthly', amount: 1),
          XboardPlanPrice(period: 'quarterly', amount: 10),
          XboardPlanPrice(period: 'half_yearly', amount: 100),
          XboardPlanPrice(period: 'yearly', amount: 999),
          XboardPlanPrice(period: 'two_yearly', amount: 1000),
          XboardPlanPrice(period: 'three_yearly', amount: 9007199254740993),
          XboardPlanPrice(period: 'onetime', amount: 0),
        ]),
      ]);
    await showCenter(tester, manager);
    for (final label in [
      'Monthly',
      'Quarterly',
      'Half-yearly',
      'Yearly',
      'Two years',
      'Three years',
      'Traffic based',
      '0.01',
      '0.10',
      '1.00',
      '9.99',
      '10.00',
      '90071992547409.93',
      '0.00',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('Confirm the currency'), findsOneWidget);
  });
}

class _Api implements XboardApi {
  @override
  final Uri baseUri = Uri.parse('https://example.test');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager extends ChangeNotifier implements PurchaseManager {
  @override
  final XboardApi api = _Api();
  @override
  XboardPlanCatalog? planCatalog = _offers;
  @override
  bool plansLoading = false;
  @override
  XboardException? plansError;
  int planLoads = 0;
  @override
  Future<void> loadPlans() async {
    planLoads++;
    plansError = null;
    planCatalog = _offers;
    notifyListeners();
  }

  @override
  XboardAccount? account;
  @override
  XboardSubscription? subscription;
  @override
  GiftPreview? preview;
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
  Uri? cardStoreUrl = Uri.parse('https://example.test/cards');
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
  @override
  bool get loggedIn => account != null;
  @override
  bool get canRedeem => false;
  @override
  bool get canSync => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
