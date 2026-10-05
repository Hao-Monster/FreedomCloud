import 'dart:async';

import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/l10n/l10n.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/pages/home.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flclashx/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = XboardAccount(id: 17, email: 'keyboard@example.test');
const _preview = GiftPreview(
  codeId: 31,
  type: 4,
  name: 'Synthetic gift',
  canRedeem: true,
  rewards: GiftReward(transferEnable: 1073741824),
);
const _receipt = GiftReceipt(
  codeId: 31,
  templateName: 'Synthetic gift',
  rewards: GiftReward(transferEnable: 1073741824),
);
final _subscription = XboardSubscription(
  valid: true,
  planName: 'Synthetic plan',
  url: Uri.parse('https://example.test/s/synthetic'),
  total: 1073741824,
);

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.manager.dispose());

  for (final scenario in [
    (size: const Size(916, 1024), offers: false),
    (size: const Size(480, 800), offers: false),
    (size: const Size(916, 1024), offers: true),
    (size: const Size(480, 800), offers: true),
  ]) {
    testWidgets(
        'login traversal stays together beside the real rail: $scenario',
        (tester) async {
      await fixture.manager.initialize();
      if (scenario.offers) await fixture.manager.loadPlans();
      await _show(tester, fixture, sidebar: true, size: scenario.size);
      await _focusField(tester, 'purchase-email');
      await _tab(tester);
      expect(_fieldFocus(tester, 'purchase-password').hasFocus, isTrue);
      await _tab(tester, backwards: true);
      expect(_fieldFocus(tester, 'purchase-email').hasFocus, isTrue);
      await _tab(tester);
      await _tab(tester);
      expect(
          _hasFocus(tester, find.byKey(const Key('purchase-login'))), isTrue);
      await _tab(tester);
      expect(
          _hasFocus(tester,
              find.widgetWithText(TextButton, 'Create account on website')),
          isTrue);
      await _tab(tester);
      expect(
          _hasFocus(tester,
              find.widgetWithText(TextButton, 'Reset password on website')),
          isTrue);
      // The group must order its children without trapping keyboard users.
      var reachedSupport = false;
      var reachedRail = false;
      for (var i = 0; i < 18 && !(reachedSupport && reachedRail); i++) {
        await _tab(tester);
        reachedSupport |=
            _hasFocus(tester, find.widgetWithText(TextButton, 'Copy').first);
        reachedRail |= _hasFocus(tester, find.byType(NavigationRail));
      }
      expect(reachedSupport, isTrue);
      expect(reachedRail, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Enter activates the focused login button only once while pending',
      (tester) async {
    await fixture.manager.initialize();
    await _show(tester, fixture, sidebar: true);
    await tester.enterText(
        find.byKey(const Key('purchase-email')), _account.email);
    await tester.enterText(
        find.byKey(const Key('purchase-password')), 'synthetic-password');
    await _focusField(tester, 'purchase-password');
    await _tab(tester);
    expect(_hasFocus(tester, find.byKey(const Key('purchase-login'))), isTrue);
    final login = Completer<String>();
    fixture.api.loginResponse = () => login.future;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.api.loginCalls, 1);
    expect(fixture.manager.busy, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.api.loginCalls, 1);
    login.complete('Bearer synthetic');
    await tester.pumpAndSettle();
    expect(fixture.manager.loggedIn, isTrue);
    expect(find.byKey(const Key('purchase-code')), findsOneWidget);
    expect(fixture.storage.session?.accountId, _account.id);
  });

  testWidgets(
      'password submit validates input and signs in through the manager',
      (tester) async {
    await fixture.manager.initialize();
    await _show(tester, fixture, sidebar: true);
    await tester.enterText(find.byKey(const Key('purchase-email')), 'invalid');
    await tester.enterText(
        find.byKey(const Key('purchase-password')), 'synthetic-password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fixture.api.loginCalls, 0);
    await tester.enterText(
        find.byKey(const Key('purchase-email')), _account.email);
    await _focusField(tester, 'purchase-password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fixture.api.loginCalls, 1);
    expect(fixture.manager.loggedIn, isTrue);
  });

  for (final outcome in ['success', 'failure', 'unauthorized']) {
    testWidgets('query shows its own progress and resets after $outcome',
        (tester) async {
      await fixture.signIn();
      fixture.manager.setCode('SYNTH1234');
      final pending = Completer<GiftPreview>();
      fixture.api.checkResponse = () => pending.future;
      await _show(tester, fixture);
      await _tap(tester, find.byKey(const Key('purchase-check')));
      _expectButton(tester, 'purchase-check', 'Checking…', enabled: false);
      expect(fixture.api.checkCalls, 1);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('purchase-code')))
              .enabled,
          isFalse);
      await fixture.manager.checkCode();
      expect(fixture.api.checkCalls, 1);
      fixture.manager.setCode('OTHER1234');
      expect(fixture.manager.code, 'SYNTH1234');
      if (outcome == 'success') {
        pending.complete(_preview);
      } else {
        pending.completeError(XboardException(
          code:
              outcome == 'unauthorized' ? 'unauthenticated' : 'gift_not_found',
          message: '',
          statusCode: outcome == 'unauthorized' ? 401 : 404,
        ));
      }
      await tester.pumpAndSettle();
      expect(fixture.manager.busy, isFalse);
      expect(find.text('Checking…'), findsNothing);
      if (outcome == 'unauthorized') {
        expect(fixture.storage.session, isNull);
        expect(find.byKey(const Key('purchase-login')), findsOneWidget);
      } else {
        _expectButton(tester, 'purchase-check', 'Preview benefits',
            enabled: true);
        expect(
            fixture.manager.preview, outcome == 'success' ? _preview : isNull);
        expect(
            fixture.manager.error, outcome == 'failure' ? isNotNull : isNull);
      }
    });
  }

  for (final operation in ['sync', 'refresh', 'history']) {
    testWidgets('$operation does not claim to be querying or redeeming',
        (tester) async {
      await fixture.signIn();
      await fixture.preview();
      final sync = Completer<void>();
      final subscription = Completer<XboardSubscription>();
      final history = Completer<GiftHistoryPage>();
      if (operation == 'sync') fixture.syncResponse = () => sync.future;
      if (operation == 'refresh') {
        fixture.api.subscriptionResponse = () => subscription.future;
      }
      if (operation == 'history') {
        fixture.api.historyResponse = (_) => history.future;
      }
      await _show(tester, fixture);
      await _tap(
          tester,
          operation == 'sync'
              ? find.byKey(const Key('purchase-sync'))
              : operation == 'refresh'
                  ? find.widgetWithText(TextButton, 'Refresh account')
                  : find.byKey(const Key('purchase-history-next')));
      expect(fixture.manager.busy, isTrue);
      if (operation == 'refresh') {
        _expectButton(tester, 'purchase-redeem', 'Confirm redemption',
            enabled: false);
      }
      _expectButton(tester, 'purchase-check', 'Preview benefits',
          enabled: false);
      _expectButton(tester, 'purchase-redeem', 'Confirm redemption',
          enabled: false);
      expect(fixture.api.checkCalls, 1);
      expect(fixture.api.redeemCalls, 0);
      await fixture.manager.checkCode();
      await fixture.manager.redeem();
      expect(fixture.api.checkCalls, 1);
      expect(fixture.api.redeemCalls, 0);
      if (operation == 'sync') {
        expect(find.text('Syncing subscription…'), findsOneWidget);
        expect(fixture.syncCalls, 1);
        sync.complete();
      } else if (operation == 'refresh') {
        subscription.complete(_subscription);
      } else {
        expect(fixture.api.requestedPages, [1, 2]);
        history.complete(_history(2));
      }
      await tester.pumpAndSettle();
      expect(fixture.manager.busy, isFalse);
      _expectButton(tester, 'purchase-check', 'Preview benefits',
          enabled: true);
      _expectButton(tester, 'purchase-redeem', 'Confirm redemption',
          enabled: true);
    });
  }

  testWidgets('redemption progress never appears on the query button',
      (tester) async {
    await fixture.signIn();
    await fixture.preview();
    final saving = Completer<void>();
    final redemption = Completer<GiftReceipt>();
    final syncing = Completer<void>();
    fixture.storage.savePendingResponse = () => saving.future;
    fixture.api.redeemResponse = () => redemption.future;
    fixture.syncResponse = () => syncing.future;
    await _show(tester, fixture);
    await _tap(tester, find.byKey(const Key('purchase-redeem')));
    _expectButton(tester, 'purchase-check', 'Preview benefits', enabled: false);
    _expectButton(tester, 'purchase-redeem', 'Redeeming…', enabled: false);
    expect(fixture.api.redeemCalls, 0);
    saving.complete();
    await tester.pumpAndSettle();
    expect(fixture.storage.pending[_account.id], isNotNull);
    expect(fixture.api.redeemCalls, 1);
    await fixture.manager.redeem();
    expect(fixture.api.redeemCalls, 1);
    redemption.complete(_receipt);
    await tester.pumpAndSettle();
    expect(fixture.manager.receipt, same(_receipt));
    expect(fixture.manager.syncing, isTrue);
    _expectButton(tester, 'purchase-check', 'Preview benefits', enabled: false);
    expect(find.text('Redeeming…'), findsNothing);
    syncing.complete();
    await tester.pumpAndSettle();
    expect(fixture.manager.subscriptionSynced, isTrue);
    expect(fixture.storage.pending, isEmpty);
    expect(fixture.api.redeemCalls, 1);
  });

  testWidgets('failed pending storage restores confirmation without consuming',
      (tester) async {
    await fixture.signIn();
    await fixture.preview();
    fixture.storage.savePendingResponse = () async {
      throw const FormatException('Synthetic storage failure');
    };
    await _show(tester, fixture);
    await _tap(tester, find.byKey(const Key('purchase-redeem')));
    expect(fixture.manager.error?.code, 'secure_storage_failed');
    expect(fixture.manager.busy, isFalse);
    expect(fixture.storage.pending, isEmpty);
    expect(fixture.api.redeemCalls, 0);
    _expectButton(tester, 'purchase-check', 'Preview benefits', enabled: true);
    _expectButton(tester, 'purchase-redeem', 'Confirm redemption',
        enabled: true);
    fixture.storage.savePendingResponse = null;
    await _tap(tester, find.byKey(const Key('purchase-redeem')));
    expect(fixture.api.redeemCalls, 1);
    expect(fixture.manager.receipt, same(_receipt));
    expect(fixture.manager.error, isNull);
    expect(fixture.storage.pending, isEmpty);
    expect(find.text('Redeeming…'), findsNothing);
  });

  testWidgets('recovering an uncertain redemption does not claim a new query',
      (tester) async {
    fixture.storage.pending[_account.id] = const PendingGiftRedemption(
      code: 'SYNTH1234',
      type: 4,
      codeId: 31,
      previousUsageIds: [],
      baselineComplete: true,
    );
    await fixture.signIn();
    final pending = Completer<GiftHistoryPage>();
    fixture.api.historyResponse = (_) => pending.future;
    await _show(tester, fixture);
    await _tap(tester, find.byKey(const Key('purchase-recover')));
    _expectButton(tester, 'purchase-check', 'Preview benefits', enabled: false);
    expect(fixture.api.checkCalls, 0);
    expect(fixture.api.redeemCalls, 0);
    fixture.api.historyResponse = null;
    pending.complete(_history(1, recovered: true));
    await tester.pumpAndSettle();
    expect(fixture.manager.receipt, isNotNull);
    expect(fixture.manager.unresolvedRedemption, isFalse);
    expect(fixture.api.redeemCalls, 0);
    expect(fixture.manager.busy, isFalse);
    expect(find.text('Checking…'), findsNothing);
  });
}

Future<void> _show(WidgetTester tester, _Fixture fixture,
    {bool sidebar = false, Size size = const Size(916, 1024)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [appSettingProvider.overrideWith(_AppSettings.new)],
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: CommonScaffold(
        disableBackground: true,
        appBar: AppBar(title: const Text('Purchase')),
        sideNavigationBar: sidebar
            ? CommonNavigationBar(
                viewMode: ViewMode.desktop,
                currentIndex: 5,
                navigationItems: [
                  for (final label in [
                    PageLabel.dashboard,
                    PageLabel.proxies,
                    PageLabel.profiles,
                    PageLabel.connections,
                    PageLabel.tools,
                    PageLabel.purchase,
                  ])
                    NavigationItem(
                        icon: const Icon(Icons.circle_outlined),
                        label: label,
                        view: const SizedBox.shrink()),
                ],
              )
            : null,
        body: PurchaseCenter(
          manager: fixture.manager,
          openLink: (_) async {},
          openProfiles: () {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FocusNode _fieldFocus(WidgetTester tester, String key) => tester
    .widget<EditableText>(find.descendant(
        of: find.byKey(Key(key)), matching: find.byType(EditableText)))
    .focusNode;

Future<void> _focusField(WidgetTester tester, String key) async {
  await _tap(tester, find.byKey(Key(key)));
  expect(_fieldFocus(tester, key).hasFocus, isTrue);
}

Future<void> _tab(WidgetTester tester, {bool backwards = false}) async {
  if (backwards) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (backwards) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

bool _hasFocus(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final root = tester.element(finder);
  final current = FocusManager.instance.primaryFocus?.context;
  if (current == root) return true;
  var matches = false;
  current?.visitAncestorElements((element) {
    matches |= element == root;
    return !matches;
  });
  return matches;
}

void _expectButton(WidgetTester tester, String key, String label,
    {required bool enabled}) {
  final finder = find.byKey(Key(key));
  expect(
      find.descendant(of: finder, matching: find.text(label)), findsOneWidget);
  expect(tester.widget<ButtonStyleButton>(finder).onPressed,
      enabled ? isNotNull : isNull);
}

class _AppSettings extends AppSetting {
  @override
  AppSettingProps build() => const AppSettingProps(showLabel: true);
}

class _Fixture {
  final api = _Api();
  final storage = _Storage();
  int syncCalls = 0;
  Future<void> Function()? syncResponse;
  late final manager = PurchaseManager(
    api: api,
    storage: storage,
    synchronize: (_, __) async {
      syncCalls++;
      await syncResponse?.call();
    },
  );

  Future<void> signIn() => manager.login(_account.email, 'synthetic-password');
  Future<void> preview() async {
    manager.setCode('SYNTH1234');
    await manager.checkCode();
  }
}

class _Storage implements PurchaseStorage {
  PurchaseSession? session;
  final pending = <int, PendingGiftRedemption>{};
  Future<void> Function()? savePendingResponse;

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
  Future<void> savePending(int accountId, PendingGiftRedemption value) async {
    await savePendingResponse?.call();
    pending[accountId] = value;
  }

  @override
  Future<void> clearPending(int accountId) async => pending.remove(accountId);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call ${invocation.memberName}');
}

GiftHistoryPage _history(int page, {bool recovered = false}) => GiftHistoryPage(
      entries: [
        GiftHistoryEntry(
          id: recovered ? 501 : page,
          codeId: recovered ? 31 : 99,
          maskedCode: 'SYNT****',
          templateName: 'Synthetic history',
          rewards: _receipt.rewards,
          usedAt: DateTime.utc(2026, 10, 5),
        )
      ],
      page: page,
      lastPage: 2,
      total: 2,
    );

class _Api implements XboardApi {
  @override
  final baseUri = Uri.parse('https://example.test');
  int loginCalls = 0;
  int checkCalls = 0;
  int redeemCalls = 0;
  final requestedPages = <int>[];
  Future<String> Function()? loginResponse;
  Future<GiftPreview> Function()? checkResponse;
  Future<GiftReceipt> Function()? redeemResponse;
  Future<XboardSubscription> Function()? subscriptionResponse;
  Future<GiftHistoryPage> Function(int page)? historyResponse;

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async => const XboardPlanCatalog(
        plans: [
          XboardPlanOffer(
            id: 9,
            name: 'Synthetic public plan',
            transferGiB: 150,
            prices: [XboardPlanPrice(period: 'monthly', amount: 990)],
          ),
        ],
      );

  @override
  Future<String> login(String email, String password) async {
    loginCalls++;
    return loginResponse == null ? 'Bearer synthetic' : loginResponse!();
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async => _account;
  @override
  Future<XboardSubscription> getSubscription(String authorization) async =>
      subscriptionResponse == null ? _subscription : subscriptionResponse!();
  @override
  Future<GiftPreview> checkGift(String authorization, String code) async {
    checkCalls++;
    return checkResponse == null ? _preview : checkResponse!();
  }

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) async {
    redeemCalls++;
    return redeemResponse == null ? _receipt : redeemResponse!();
  }

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization,
      {int page = 1}) async {
    requestedPages.add(page);
    return historyResponse == null ? _history(page) : historyResponse!(page);
  }

  @override
  Future<Uri?> getCardStore(String authorization) async => null;
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API call ${invocation.memberName}');
}
