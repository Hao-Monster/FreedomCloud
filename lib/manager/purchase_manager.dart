import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter/foundation.dart';

typedef PurchaseSubscriptionSync = Future<void> Function(
    XboardAccount account, XboardSubscription subscription);

enum _GiftOperation { check, redeem }

/// Keeps account authentication, card consumption, and local configuration
/// updates separate. A failed download must never repeat a successful redemption.
class PurchaseManager extends ChangeNotifier {
  PurchaseManager({
    required this.api,
    required this.storage,
    required PurchaseSubscriptionSync synchronize,
  }) : _synchronize = synchronize;

  final XboardApi api;
  final PurchaseStorage storage;
  final PurchaseSubscriptionSync _synchronize;

  XboardPlanCatalog? planCatalog;
  XboardException? plansError;
  bool plansLoading = false;

  XboardAccount? account;
  XboardSubscription? subscription;
  GiftPreview? preview;
  GiftReceipt? receipt;
  GiftHistoryPage? history;
  Uri? cardStoreUrl;
  XboardException? error;
  XboardException? historyError;
  XboardException? syncError;
  XboardException? channelError;
  bool restoring = true;
  bool busy = false;
  bool syncing = false;
  bool subscriptionSynced = false;
  String code = '';

  String? _authorization;
  String? _previewCode;
  PendingGiftRedemption? _pending;
  bool _disposed = false;
  bool _pendingStateReady = false;
  _GiftOperation? _giftOperation;

  bool get checkingCode => _giftOperation == _GiftOperation.check;
  bool get redeemingCode => _giftOperation == _GiftOperation.redeem;
  bool get loggedIn => account != null && _authorization != null;
  bool get unresolvedRedemption => _pending != null;
  bool get canRedeem =>
      loggedIn &&
      _pendingStateReady &&
      !busy &&
      !unresolvedRedemption &&
      (preview?.canRedeem ?? false) &&
      _previewCode == code;
  bool get canSync => loggedIn && !busy && (subscription?.valid ?? false);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Public offers remain available independently of login and secure storage.
  /// Do not let catalogue errors or a slow request block gift-card operations.
  Future<void> loadPlans() async {
    if (_disposed || plansLoading) return;
    plansLoading = true;
    plansError = null;
    planCatalog = null;
    _notify();
    try {
      final result = await api.getPlanCatalog();
      if (!_disposed) planCatalog = result;
    } on Exception catch (cause) {
      if (!_disposed) plansError = _failure(cause, 'plan_catalog_failed');
    } finally {
      plansLoading = false;
      _notify();
    }
  }

  XboardException _failure(Object cause,
          [String fallback = 'purchase_failed']) =>
      cause is XboardException
          ? cause
          : XboardException(code: fallback, message: '');

  Future<void> _run(Future<void> Function() action,
      {_GiftOperation? giftOperation}) async {
    if (_disposed || busy) return;
    busy = true;
    _giftOperation = giftOperation;
    error = null;
    _notify();
    try {
      await action();
    } on Exception catch (cause) {
      final failure = _failure(cause);
      if (failure.isUnauthorized) {
        try {
          await storage.clearSession();
        } on Exception {
          error =
              const XboardException(code: 'secure_storage_failed', message: '');
        }
        final confirmedReceipt = receipt;
        _clearAccount();
        receipt = confirmedReceipt;
      }
      error ??= failure;
    } finally {
      busy = false;
      _giftOperation = null;
      restoring = false;
      _notify();
    }
  }

  Future<void> initialize() => _run(() async {
        final saved = await _storageReadSession();
        if (saved == null) return;
        final restored = await api.getAccount(saved.authorization);
        if (restored.id != saved.accountId || restored.isDistributor) {
          await storage.clearSession();
          throw const XboardException(
              code: 'purchase_account_unsupported', message: '');
        }
        _authorization = saved.authorization;
        account = restored;
        await _restorePending();
        await _refreshData();
      });

  Future<PurchaseSession?> _storageReadSession() async {
    try {
      return await storage.readSession();
    } on Exception {
      throw const XboardException(code: 'secure_storage_failed', message: '');
    }
  }

  Future<void> _restorePending() async {
    try {
      _pending = await storage.readPending(account!.id);
      code = _pending?.code ?? '';
      _pendingStateReady = true;
    } on Exception {
      _pendingStateReady = false;
      throw const XboardException(code: 'secure_storage_failed', message: '');
    }
  }

  Future<void> login(String email, String password) => _run(() async {
        if (loggedIn) return;
        receipt = null;
        final authorization = await api.login(email.trim(), password);
        try {
          final authenticated = await api.getAccount(authorization);
          if (authenticated.isDistributor) {
            throw const XboardException(
                code: 'purchase_account_unsupported', message: '');
          }
          try {
            await storage
                .saveSession(PurchaseSession(authenticated.id, authorization));
          } on Exception {
            throw const XboardException(
                code: 'secure_storage_failed', message: '');
          }
          _authorization = authorization;
          account = authenticated;
        } on Exception {
          // The token was issued but never admitted to the client session.
          // Best-effort revocation does not mask the original failure.
          try {
            await api.logout(authorization);
          } on Exception {/* Already unusable or offline. */}
          rethrow;
        }
        await _restorePending();
        await _refreshData();
      });

  Future<void> logout() => _run(() async {
        final authorization = _authorization;
        // Erase the persisted login even when server-side revocation is offline.
        // Pending redemptions remain scoped to this account for the next login.
        try {
          await storage.clearSession();
        } on Exception {
          throw const XboardException(
              code: 'secure_storage_failed', message: '');
        }
        _clearAccount();
        if (authorization != null) {
          try {
            await api.logout(authorization);
          } on XboardException catch (cause) {
            if (!cause.isUnauthorized) {
              error = const XboardException(
                  code: 'logout_remote_failed', message: '');
            }
          }
        }
      });

  void _clearAccount() {
    _authorization = null;
    account = null;
    subscription = null;
    preview = null;
    receipt = null;
    history = null;
    cardStoreUrl = null;
    _pending = null;
    _pendingStateReady = false;
    code = '';
    _previewCode = null;
    historyError = null;
    syncError = null;
    channelError = null;
    subscriptionSynced = false;
  }

  void setCode(String value) {
    if (busy || unresolvedRedemption || _disposed) return;
    final normalized = value.trim().toUpperCase();
    if (normalized == code) return;
    code = normalized;
    preview = null;
    _previewCode = null;
    error = null;
    _notify();
  }

  Future<void> checkCode() => _run(() async {
        if (!loggedIn || unresolvedRedemption) return;
        preview = null;
        _previewCode = null;
        if (!RegExp(r'^[A-Z0-9]{8,32}$').hasMatch(code)) {
          throw const XboardException(code: 'gift_code_format', message: '');
        }
        final checked = await api.checkGift(_authorization!, code);
        preview = checked;
        _previewCode = code;
      }, giftOperation: _GiftOperation.check);

  Future<void> redeem() async {
    if (!canRedeem) return;
    await _run(() async {
      final checked = preview!;
      final priorIds = <int>[];
      var baselineComplete = checked.type == 4;
      if (checked.type != 4 && checked.codeId != null) {
        // Reusable legacy cards have no request idempotency key. Capture actual
        // prior usage IDs, not a masked prefix or an assumed timestamp order.
        for (var page = 1; page <= 20; page++) {
          final previous =
              await api.getGiftHistory(_authorization!, page: page);
          priorIds.addAll(previous.entries
              .where((entry) => entry.codeId == checked.codeId)
              .map((entry) => entry.id));
          if (page >= previous.lastPage) {
            baselineComplete = true;
            break;
          }
        }
      }
      final pending = PendingGiftRedemption(
        code: code,
        type: checked.type,
        codeId: checked.codeId,
        previousUsageIds: priorIds,
        baselineComplete: baselineComplete,
      );
      try {
        await storage.savePending(account!.id, pending);
      } on Exception {
        throw const XboardException(code: 'secure_storage_failed', message: '');
      }
      _pending = pending;
      receipt = null;
      syncError = null;
      subscriptionSynced = false;
      _notify();
      GiftReceipt result;
      try {
        result = await api.redeemGift(_authorization!, pending.code);
        _checkReceipt(result, pending);
      } on XboardException catch (cause) {
        preview = null;
        _previewCode = null;
        if (!cause.isUncertain) await _clearPending();
        rethrow;
      }
      await _completeRedemption(result);
    }, giftOperation: _GiftOperation.redeem);
  }

  Future<void> _clearPending() async {
    try {
      await storage.clearPending(account!.id);
      _pending = null;
      _pendingStateReady = true;
    } on Exception {
      _pendingStateReady = false;
      throw const XboardException(code: 'secure_storage_failed', message: '');
    }
  }

  Future<void> _completeRedemption(GiftReceipt result) async {
    receipt = result;
    preview = null;
    _previewCode = null;
    code = '';
    _notify();
    await _clearPending();
    await _readHistory(1);
    // Synchronization errors are separate from the durable redemption result.
    await _syncLatest();
  }

  void _checkReceipt(GiftReceipt result, PendingGiftRedemption pending) {
    if (result.codeId != null &&
        pending.codeId != null &&
        result.codeId != pending.codeId) {
      throw const XboardException(
          code: 'invalid_response', message: '', isUncertain: true);
    }
  }

  Future<void> recoverRedemption() => _run(() async {
        if (!loggedIn || _pending == null) return;
        final pending = _pending!;
        if (pending.codeId != null && pending.baselineComplete) {
          for (var page = 1; page <= 20; page++) {
            final result =
                await api.getGiftHistory(_authorization!, page: page);
            if (page == 1) {
              history = result;
              historyError = null;
            }
            for (final entry in result.entries) {
              if (entry.codeId == pending.codeId &&
                  !pending.previousUsageIds.contains(entry.id)) {
                await _completeRedemption(GiftReceipt(
                  templateName: entry.templateName,
                  rewards: entry.rewards,
                  orderTradeNo: entry.orderTradeNo,
                ));
                return;
              }
            }
            if (page >= result.lastPage) break;
          }
        }
        if (pending.type == 4) {
          // Only purchase codes have server-enforced same-account idempotency.
          // Do not re-check an exhausted code: redeem returns its original receipt.
          final result = await api.redeemGift(_authorization!, pending.code);
          _checkReceipt(result, pending);
          await _completeRedemption(result);
          return;
        }
        subscription = await api.getSubscription(_authorization!);
        error =
            const XboardException(code: 'gift_result_unconfirmed', message: '');
      });

  Future<void> refresh() {
    if (!loggedIn) return initialize();
    if (!_pendingStateReady) {
      return _run(() async {
        await _restorePending();
        await _refreshData();
      });
    }
    if (unresolvedRedemption) return recoverRedemption();
    return _run(_refreshData);
  }

  Future<void> _refreshData() async {
    subscription = await api.getSubscription(_authorization!);
    await _readHistory(1);
    channelError = null;
    try {
      cardStoreUrl = await api.getCardStore(_authorization!);
    } on XboardException catch (cause) {
      if (cause.isUnauthorized) rethrow;
      cardStoreUrl = null;
      channelError = cause;
    }
  }

  Future<void> loadHistory(int page) => _run(() async {
        if (loggedIn && page > 0) await _readHistory(page);
      });

  Future<void> _readHistory(int page) async {
    historyError = null;
    try {
      history = await api.getGiftHistory(_authorization!, page: page);
    } on XboardException catch (cause) {
      if (cause.isUnauthorized) rethrow;
      historyError = cause;
    }
  }

  Future<void> syncSubscription() => _run(() async {
        if (loggedIn) await _syncLatest();
      });

  Future<void> _syncLatest() async {
    syncError = null;
    subscriptionSynced = false;
    syncing = true;
    _notify();
    try {
      subscription = await api.getSubscription(_authorization!);
      if (subscription!.valid && !_disposed) {
        await _synchronize(account!, subscription!);
        subscriptionSynced = true;
      }
    } catch (cause) {
      // The native core's config validator can throw a String. Never expose
      // that configuration-bearing payload or lose the successful receipt.
      if (cause is XboardException && cause.isUnauthorized) rethrow;
      syncError = _failure(cause, 'subscription_sync_failed');
    } finally {
      syncing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    api.close();
    super.dispose();
  }
}
