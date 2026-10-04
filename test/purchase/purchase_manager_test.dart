import 'dart:async';

import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Api api;
  late _Storage storage;
  late PurchaseManager manager;
  late int syncCalls;
  var failSync = false;
  Object? syncFailure;

  setUp(() {
    api = _Api();
    storage = _Storage();
    syncCalls = 0;
    failSync = false;
    syncFailure = null;
    manager = PurchaseManager(
        api: api,
        storage: storage,
        synchronize: (_, __) async {
          syncCalls++;
          // Match the native core validator, which can throw a String.
          // ignore: only_throw_errors
          if (syncFailure != null) throw syncFailure!;
          if (failSync) {
            throw const FormatException('synthetic download failure');
          }
        });
  });
  tearDown(() => manager.dispose());

  Future<void> login() =>
      manager.login('person@example.test', 'synthetic-password');
  Future<void> preview() async {
    manager.setCode('CODE12345678');
    await manager.checkCode();
  }

  test('restores the authenticated account from secure credentials', () async {
    storage.session = const PurchaseSession(1, 'Bearer saved');
    await manager.initialize();
    expect(manager.loggedIn, isTrue);
    expect(manager.account!.id, 1);
    expect(api.lastAuthorization, 'Bearer saved');
    expect(api.loginCalls, 0);
    expect(manager.restoring, isFalse);
  });

  test('expired saved authentication is erased without discarding pending work',
      () async {
    storage.session = const PurchaseSession(1, 'Bearer saved');
    storage.pending[1] = _pending();
    api.accountFailure = const XboardException(
        code: 'unauthenticated', message: '', statusCode: 401);
    await manager.initialize();
    expect(manager.loggedIn, isFalse);
    expect(storage.session, isNull);
    expect(storage.pending[1], isNotNull);
  });

  test('an edited code invalidates the previous eligible preview', () async {
    await login();
    await preview();
    expect(manager.canRedeem, isTrue);
    manager.setCode('DIFFERENT123');
    await manager.redeem();
    expect(manager.preview, isNull);
    expect(api.redemptions, isEmpty);
  });

  test('a denied preview cannot consume a card', () async {
    api.checked = const GiftPreview(
        codeId: 51,
        type: 4,
        name: 'Purchase',
        canRedeem: false,
        reason: 'Current plan differs',
        rewards: GiftReward());
    await login();
    await preview();
    await manager.redeem();
    expect(api.redemptions, isEmpty);
    expect(manager.preview!.canRedeem, isFalse);
  });

  test(
      'successful redemption survives download failure and only sync is retried',
      () async {
    failSync = true;
    await login();
    await preview();
    await manager.redeem();
    expect(manager.receipt, isNotNull);
    expect(manager.syncError!.code, 'subscription_sync_failed');
    expect(manager.unresolvedRedemption, isFalse);
    expect(storage.pending, isEmpty);
    failSync = false;
    await manager.syncSubscription();
    expect(manager.subscriptionSynced, isTrue);
    expect(api.redemptions, ['CODE12345678']);
    expect(syncCalls, 2);
  });

  test('balance-only reward does not invent an active subscription', () async {
    api
      ..sub = XboardSubscription(
          valid: false,
          url: Uri.parse('https://panel.example.test/s/synthetic'))
      ..result = const GiftReceipt(
          templateName: 'Balance', rewards: GiftReward(balance: 500));
    await login();
    await preview();
    await manager.redeem();
    expect(manager.receipt!.rewards.balance, 500);
    expect(manager.subscriptionSynced, isFalse);
    expect(syncCalls, 0);
  });

  test('native profile validation string is a safe synchronization failure',
      () async {
    syncFailure = 'synthetic validation message with private configuration';
    await login();
    await preview();
    await manager.redeem();
    expect(manager.receipt, isNotNull);
    expect(manager.syncError!.code, 'subscription_sync_failed');
    expect(manager.syncError!.message, isEmpty);
    expect(manager.unresolvedRedemption, isFalse);
  });

  test(
      'expired authentication during sync clears credentials and permits login',
      () async {
    await login();
    api.subscriptionFailure = const XboardException(
        code: 'unauthenticated', message: '', statusCode: 401);
    await manager.syncSubscription();
    expect(manager.loggedIn, isFalse);
    expect(storage.session, isNull);
    expect(manager.error!.isUnauthorized, isTrue);
  });

  test('confirmed redemption remains visible when follow-up session expires',
      () async {
    await login();
    await preview();
    api.response = () async {
      api.subscriptionFailure = const XboardException(
          code: 'unauthenticated', message: '', statusCode: 401);
      return api.result;
    };
    await manager.redeem();
    expect(manager.loggedIn, isFalse);
    expect(manager.receipt, isNotNull);
    expect(storage.pending, isEmpty);
    expect(storage.session, isNull);
    api.subscriptionFailure = null;
    await login();
    expect(manager.receipt, isNull);
  });

  test(
      'pending request is durable before consumption and repeated clicks are blocked',
      () async {
    final completion = Completer<GiftReceipt>();
    api.response = () {
      expect(storage.pending[1]!.code, 'CODE12345678');
      return completion.future;
    };
    await login();
    await preview();
    final first = manager.redeem();
    await Future<void>.delayed(Duration.zero);
    await manager.redeem();
    expect(api.redemptions.length, 1);
    completion.complete(api.result);
    await first;
    expect(manager.receipt, isNotNull);
  });

  test(
      'unknown purchase result blocks new codes and idempotent recovery uses redeem',
      () async {
    await login();
    await preview();
    api.response = () async => throw const XboardException(
        code: 'network_error', message: '', isUncertain: true);
    await manager.redeem();
    expect(manager.unresolvedRedemption, isTrue);
    expect(manager.receipt, isNull);
    manager.setCode('ANOTHERCODE');
    expect(manager.code, 'CODE12345678');
    api.response = null;
    await manager.recoverRedemption();
    expect(api.checkCalls, 1);
    expect(api.redemptions, ['CODE12345678', 'CODE12345678']);
    expect(manager.receipt, isNotNull);
    expect(manager.unresolvedRedemption, isFalse);
  });

  test('legacy card recovery matches code ID and excludes prior usages',
      () async {
    api
      ..checked = const GiftPreview(
          codeId: 51,
          type: 1,
          name: 'Reusable',
          canRedeem: true,
          rewards: GiftReward(balance: 100))
      ..entries = [_entry(1, 51), _entry(2, 52)];
    await login();
    await preview();
    api.response = () async => throw const XboardException(
        code: 'network_error', message: '', isUncertain: true);
    await manager.redeem();
    await manager.recoverRedemption();
    expect(manager.receipt, isNull);
    expect(manager.error!.code, 'gift_result_unconfirmed');
    expect(api.redemptions.length, 1);
    // Same masked text is deliberately shared by all entries.
    api.entries = [_entry(4, 52), _entry(3, 51), _entry(2, 52), _entry(1, 51)];
    await manager.recoverRedemption();
    expect(manager.receipt, isNotNull);
    expect(api.redemptions.length, 1);
    expect(manager.unresolvedRedemption, isFalse);
  });

  test('older server without code IDs never guesses from a masked prefix',
      () async {
    api.checked = const GiftPreview(
        codeId: null,
        type: 1,
        name: 'Old',
        canRedeem: true,
        rewards: GiftReward());
    await login();
    await preview();
    api.response = () async => throw const XboardException(
        code: 'network_error', message: '', isUncertain: true);
    await manager.redeem();
    api.entries = [_entry(3, null)];
    await manager.recoverRedemption();
    expect(manager.unresolvedRedemption, isTrue);
    expect(manager.receipt, isNull);
    expect(api.redemptions.length, 1);
  });

  test('a mismatched successful response remains unconfirmed', () async {
    await login();
    await preview();
    api.result = const GiftReceipt(
        codeId: 999, templateName: 'Other code', rewards: GiftReward());
    await manager.redeem();
    expect(manager.unresolvedRedemption, isTrue);
    expect(manager.receipt, isNull);
    expect(syncCalls, 0);
  });

  test('secure persistence failure prevents the redeem request', () async {
    await login();
    await preview();
    storage.failPendingWrite = true;
    await manager.redeem();
    expect(api.redemptions, isEmpty);
    expect(manager.error!.code, 'secure_storage_failed');
  });

  test('unreadable pending state fails closed until storage recovers',
      () async {
    storage.failPendingRead = true;
    await login();
    await preview();
    expect(manager.canRedeem, isFalse);
    await manager.redeem();
    expect(api.redemptions, isEmpty);
    storage.failPendingRead = false;
    await manager.refresh();
    await preview();
    expect(manager.canRedeem, isTrue);
  });

  test('history failure is represented as a failure instead of an empty result',
      () async {
    api.historyFailure =
        const XboardException(code: 'network_error', message: '');
    await login();
    expect(manager.history, isNull);
    expect(manager.historyError, isNotNull);
  });

  test(
      'logout clears account data and pending recovery stays scoped to its owner',
      () async {
    storage.pending[1] = _pending();
    await login();
    expect(manager.unresolvedRedemption, isTrue);
    await manager.logout();
    expect(manager.loggedIn, isFalse);
    expect(manager.history, isNull);
    expect(manager.code, '');
    expect(storage.pending[1], isNotNull);
    api.user = const XboardAccount(id: 2, email: 'second@example.test');
    await login();
    expect(manager.account!.id, 2);
    expect(manager.unresolvedRedemption, isFalse);
    expect(manager.code, '');
    expect(storage.pending[1], isNotNull);
  });

  test('fresh manager restores unresolved redemption after restart', () async {
    storage.session = const PurchaseSession(1, 'Bearer saved');
    storage.pending[1] = _pending();
    await manager.initialize();
    expect(manager.unresolvedRedemption, isTrue);
    expect(manager.code, 'CODE12345678');
    await manager.recoverRedemption();
    expect(manager.receipt, isNotNull);
    expect(storage.pending[1], isNull);
  });
}

PendingGiftRedemption _pending() => const PendingGiftRedemption(
    code: 'CODE12345678',
    type: 4,
    codeId: 51,
    previousUsageIds: [],
    baselineComplete: true);

GiftHistoryEntry _entry(int id, int? codeId) => GiftHistoryEntry(
    id: id,
    codeId: codeId,
    maskedCode: 'CODE****',
    templateName: 'Reward',
    rewards: const GiftReward(balance: 100),
    usedAt: DateTime.utc(2026, 10, 4));

class _Storage implements PurchaseStorage {
  PurchaseSession? session;
  final pending = <int, PendingGiftRedemption>{};
  final profiles = <int, String>{};
  bool failPendingWrite = false;
  bool failPendingRead = false;
  @override
  Future<PurchaseSession?> readSession() async => session;
  @override
  Future<void> saveSession(PurchaseSession value) async {
    session = value;
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<PendingGiftRedemption?> readPending(int id) async {
    if (failPendingRead) throw const FormatException('Unreadable');
    return pending[id];
  }

  @override
  Future<void> savePending(int id, PendingGiftRedemption value) async {
    if (failPendingWrite) throw const FormatException('Unavailable');
    pending[id] = value;
  }

  @override
  Future<void> clearPending(int id) async {
    pending.remove(id);
  }

  @override
  Future<String?> readProfileId(int id) async => profiles[id];
  @override
  Future<void> saveProfileId(int id, String profile) async {
    profiles[id] = profile;
  }
}

class _Api implements XboardApi {
  XboardAccount user = const XboardAccount(id: 1, email: 'person@example.test');
  XboardSubscription sub = XboardSubscription(
      planId: 3,
      planName: 'Plan',
      valid: true,
      url: Uri.parse('https://panel.example.test/s/synthetic'),
      total: 200);
  GiftPreview checked = const GiftPreview(
      codeId: 51,
      type: 4,
      name: 'Purchase',
      canRedeem: true,
      rewards: GiftReward());
  GiftReceipt result = const GiftReceipt(
      codeId: 51,
      templateName: 'Purchase',
      rewards: GiftReward(),
      orderTradeNo: 'ORDER1');
  final redemptions = <String>[];
  List<GiftHistoryEntry> entries = [];
  Future<GiftReceipt> Function()? response;
  XboardException? accountFailure;
  XboardException? historyFailure;
  XboardException? subscriptionFailure;
  int loginCalls = 0;
  int checkCalls = 0;
  String? lastAuthorization;
  @override
  Uri get baseUri => Uri.parse('https://panel.example.test');
  @override
  Future<String> login(String email, String password) async {
    loginCalls++;
    return 'Bearer synthetic';
  }

  @override
  Future<XboardAccount> getAccount(String authorization) async {
    lastAuthorization = authorization;
    if (accountFailure != null) throw accountFailure!;
    return user;
  }

  @override
  Future<XboardSubscription> getSubscription(String authorization) async {
    if (subscriptionFailure != null) throw subscriptionFailure!;
    return sub;
  }

  @override
  Future<GiftPreview> checkGift(String authorization, String code) async {
    checkCalls++;
    return checked;
  }

  @override
  Future<GiftReceipt> redeemGift(String authorization, String code) async {
    redemptions.add(code);
    return response == null ? result : response!();
  }

  @override
  Future<GiftHistoryPage> getGiftHistory(String authorization,
      {int page = 1}) async {
    if (historyFailure != null) throw historyFailure!;
    return GiftHistoryPage(
        entries: entries, page: page, lastPage: 1, total: entries.length);
  }

  @override
  Future<Uri?> getCardStore(String authorization) async => null;
  @override
  Future<void> logout(String authorization) async {}
  @override
  void close() {}
}
