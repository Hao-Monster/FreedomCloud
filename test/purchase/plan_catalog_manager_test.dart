import 'dart:async';

import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

XboardPlanCatalog _catalog() => const XboardPlanCatalog(plans: [
      XboardPlanOffer(
        id: 7,
        name: 'Public plan',
        transferGiB: 150,
        speedLimit: 100,
        deviceLimit: 3,
        prices: [XboardPlanPrice(period: 'monthly', amount: 990)],
      ),
    ]);

class _Storage implements PurchaseStorage {
  int calls = 0;
  PurchaseSession? saved;
  Completer<PurchaseSession?>? reading;

  @override
  Future<PurchaseSession?> readSession() async {
    calls++;
    return reading == null ? saved : reading!.future;
  }

  @override
  Future<PendingGiftRedemption?> readPending(int accountId) async {
    calls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected secure storage call ${invocation.memberName}');
  }
}

class _Api implements XboardApi {
  int catalogCalls = 0;
  int authenticatedCalls = 0;
  int unexpectedCalls = 0;
  Future<XboardPlanCatalog> Function()? catalogResponse;

  @override
  Future<XboardPlanCatalog> getPlanCatalog() async {
    catalogCalls++;
    return catalogResponse == null ? _catalog() : catalogResponse!();
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async {
    authenticatedCalls++;
    return const XboardAccount(id: 4, email: 'catalog@example.test');
  }

  @override
  Future<XboardSubscription> getSubscription(String authorization) async {
    authenticatedCalls++;
    return XboardSubscription(
        valid: false, url: Uri.parse('https://example.test/subscription'));
  }

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization,
      {int page = 1}) async {
    authenticatedCalls++;
    return GiftHistoryPage(entries: [], page: 1, lastPage: 1, total: 0);
  }

  @override
  Future<Uri?> getCardStore(String authorization) async {
    authenticatedCalls++;
    return Uri.parse('https://example.test/cards');
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError(
        'Unexpected account or gift call ${invocation.memberName}');
  }
}

void main() {
  late _Api api;
  late _Storage storage;
  late PurchaseManager manager;
  var disposed = false;
  var syncCalls = 0;

  setUp(() {
    api = _Api();
    storage = _Storage();
    disposed = false;
    syncCalls = 0;
    manager = PurchaseManager(
        api: api, storage: storage, synchronize: (_, __) async => syncCalls++);
  });
  tearDown(() {
    if (!disposed) manager.dispose();
  });

  void expectNoAccountWork() {
    expect(storage.calls, 0);
    expect(api.authenticatedCalls, 0);
    expect(api.unexpectedCalls, 0);
    expect(syncCalls, 0);
  }

  test('anonymous catalog loading never reads storage or starts account work',
      () async {
    expect(manager.loggedIn, isFalse);
    await manager.loadPlans();
    expect(manager.planCatalog!.plans.single.name, 'Public plan');
    expect(manager.plansLoading, isFalse);
    expect(manager.plansError, isNull);
    expect(manager.busy, isFalse);
    expect(manager.loggedIn, isFalse);
    expectNoAccountWork();
  });

  test(
      'catalog loading does not disable login or card editing with global busy',
      () async {
    final response = Completer<XboardPlanCatalog>();
    api.catalogResponse = () => response.future;
    final loading = manager.loadPlans();
    expect(manager.plansLoading, isTrue);
    expect(manager.busy, isFalse);
    manager.setCode('testcode123');
    expect(manager.code, 'TESTCODE123');
    response.complete(_catalog());
    await loading;
    expectNoAccountWork();
  });

  test('slow secure session restore does not block public catalog loading',
      () async {
    storage.reading = Completer<PurchaseSession?>();
    final restoring = manager.initialize();
    expect(manager.busy, isTrue);
    await manager.loadPlans();
    expect(manager.planCatalog!.plans.single.id, 7);
    expect(manager.restoring, isTrue);
    expect(manager.busy, isTrue);
    expect(storage.calls, 1);
    expect(api.authenticatedCalls, 0);
    storage.reading!.complete(null);
    await restoring;
    expect(manager.busy, isFalse);
    expect(api.unexpectedCalls, 0);
  });

  test('overlapping reload requests make only one catalog request', () async {
    final response = Completer<XboardPlanCatalog>();
    api.catalogResponse = () => response.future;
    final first = manager.loadPlans();
    final second = manager.loadPlans();
    expect(api.catalogCalls, 1);
    response.complete(_catalog());
    await Future.wait([first, second]);
    expect(manager.planCatalog!.plans, hasLength(1));
    expect(manager.plansLoading, isFalse);
  });

  test('reload failure clears stale quotes and supports an explicit retry',
      () async {
    await manager.loadPlans();
    final failing = Completer<XboardPlanCatalog>();
    api.catalogResponse = () => failing.future;
    final reloading = manager.loadPlans();
    expect(manager.planCatalog, isNull);
    failing.completeError(
        const XboardException(code: 'connection_error', message: ''));
    await reloading;
    expect(manager.planCatalog, isNull);
    expect(manager.plansError!.code, 'connection_error');
    expect(manager.plansLoading, isFalse);
    expect(manager.error, isNull);
    api.catalogResponse = null;
    await manager.loadPlans();
    expect(manager.plansError, isNull);
    expect(manager.planCatalog!.plans.single.prices.single.amount, 990);
    expect(api.catalogCalls, 3);
    expectNoAccountWork();
  });

  test('empty catalog is distinct from failed catalog', () async {
    api.catalogResponse = () async => const XboardPlanCatalog(plans: []);
    await manager.loadPlans();
    expect(manager.planCatalog, isNotNull);
    expect(manager.planCatalog!.plans, isEmpty);
    expect(manager.plansError, isNull);
    expectNoAccountWork();
  });

  test('a logged-in user receives the public catalog without account refresh',
      () async {
    storage.saved = const PurchaseSession(4, 'Bearer catalog_fixture');
    await manager.initialize();
    final account = manager.account;
    storage.calls = 0;
    api.authenticatedCalls = 0;
    await manager.loadPlans();
    expect(manager.loggedIn, isTrue);
    expect(manager.account, same(account));
    expect(manager.planCatalog!.plans.single.prices.single.amount, 990);
    expectNoAccountWork();
  });

  test('unexpected service exceptions remain a catalog failure without details',
      () async {
    api.catalogResponse = () async =>
        throw const FormatException('fixture private implementation detail');
    await manager.loadPlans();
    expect(manager.planCatalog, isNull);
    expect(manager.plansError!.code, 'plan_catalog_failed');
    expect(manager.plansError!.message, isEmpty);
    expect(manager.plansLoading, isFalse);
    expect(manager.error, isNull);
    expectNoAccountWork();
  });

  test(
      'catalog failure preserves the logged-in session and existing gift state',
      () async {
    storage.saved = const PurchaseSession(4, 'Bearer catalog_fixture');
    await manager.initialize();
    expect(manager.loggedIn, isTrue);
    final account = manager.account;
    final subscription = manager.subscription;
    final history = manager.history;
    final store = manager.cardStoreUrl;
    const preview = GiftPreview(
        codeId: 1,
        type: 1,
        name: 'Existing preview',
        canRedeem: true,
        rewards: GiftReward(balance: 100));
    const receipt = GiftReceipt(
        templateName: 'Existing receipt', rewards: GiftReward(balance: 100));
    const giftError =
        XboardException(code: 'gift_result_unconfirmed', message: '');
    manager
      ..code = 'EXISTINGCODE'
      ..preview = preview
      ..receipt = receipt
      ..error = giftError;
    storage.calls = 0;
    api
      ..authenticatedCalls = 0
      ..catalogResponse = () async => throw const XboardException(
          code: 'unauthenticated', message: '', statusCode: 401);
    await manager.loadPlans();
    expect(manager.plansError!.statusCode, 401);
    expect(manager.loggedIn, isTrue);
    expect(manager.account, same(account));
    expect(manager.subscription, same(subscription));
    expect(manager.history, same(history));
    expect(manager.cardStoreUrl, store);
    expect(manager.code, 'EXISTINGCODE');
    expect(manager.preview, same(preview));
    expect(manager.receipt, same(receipt));
    expect(manager.error, same(giftError));
    expectNoAccountWork();
  });

  test('late catalog completion never notifies a disposed manager', () async {
    final response = Completer<XboardPlanCatalog>();
    api.catalogResponse = () => response.future;
    var notifications = 0;
    manager.addListener(() => notifications++);
    final loading = manager.loadPlans();
    expect(notifications, greaterThan(0));
    manager.dispose();
    disposed = true;
    final notificationsAtDispose = notifications;
    response.complete(_catalog());
    await loading;
    expect(notifications, notificationsAtDispose);
    await manager.loadPlans();
    expect(api.catalogCalls, 1);
  });
}
