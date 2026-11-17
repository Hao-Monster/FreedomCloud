import 'dart:async';

import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flutter/foundation.dart';

typedef PurchaseSubscriptionSync = Future<void> Function(
    XboardAccount account, XboardSubscription subscription);

enum _GiftOperation { check, redeem }

enum _AuthOperation { login, register, resetPassword }

/// Keeps account authentication, card consumption, and local configuration
/// updates separate. A failed download must never repeat a successful redemption.
class PurchaseManager extends ChangeNotifier {
  PurchaseManager({
    required this.api,
    required this.storage,
    required PurchaseSubscriptionSync synchronize,
  }) : _synchronize = synchronize {
    _realInstances[this] = true;
  }

  static final Expando<bool> _realInstances = Expando<bool>();

  static bool isRealInstance(PurchaseManager instance) =>
      _realInstances[instance] ?? false;

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
  XboardPurchaseChannels? purchaseChannels;
  XboardGuestAuthConfig guestAuthConfig = const XboardGuestAuthConfig();
  XboardPlanOffer? handoffPlan;
  XboardException? error;
  XboardException? historyError;
  XboardException? syncError;
  XboardException? channelError;
  bool restoring = true;
  bool busy = false;
  bool sendingEmailCode = false;
  bool passwordResetSucceeded = false;
  bool inviteCodeRequiredByServer = false;
  bool emailVerifyRequiredByServer = false;
  bool syncing = false;
  bool subscriptionSynced = false;
  String code = '';

  String? _authorization;
  String? _previewCode;
  PendingGiftRedemption? _pending;
  bool _disposed = false;
  bool _pendingStateReady = false;
  _GiftOperation? _giftOperation;
  _AuthOperation? _authOperation;
  Future<XboardPurchaseChannels?>? _channelsInFlight;
  int _sessionEpoch = 0;
  int _authActionGeneration = 0;
  int? _initialSyncAttemptedAccountId;
  bool _pendingInitialAutoSync = false;

  bool get checkingCode => _giftOperation == _GiftOperation.check;
  bool get redeemingCode => _giftOperation == _GiftOperation.redeem;
  bool get registering => _authOperation == _AuthOperation.register;
  bool get resettingPassword => _authOperation == _AuthOperation.resetPassword;
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

  bool hasAttemptedInitialSyncFor(int accountId) =>
      _initialSyncAttemptedAccountId == accountId;

  void clearError() {
    if (_disposed || error == null) return;
    error = null;
    _notify();
  }

  void clearPasswordResetState() {
    if (_disposed || !passwordResetSucceeded) return;
    passwordResetSucceeded = false;
    _notify();
  }

  Uri? resolvePlanStoreUrl(XboardPlanOffer plan) =>
      XboardPurchaseChannels.extractPlanContentPurchaseUrl(plan.content) ??
      purchaseChannels?.resolvePlanStoreUrl(plan) ??
      cardStoreUrl;

  void markPlanHandoff(XboardPlanOffer plan) {
    if (_disposed) return;
    handoffPlan = plan;
    _notify();
  }

  void clearPlanHandoff() {
    if (_disposed || handoffPlan == null) return;
    handoffPlan = null;
    _notify();
  }

  Future<XboardPurchaseChannels?> ensurePurchaseChannels({bool force = false}) {
    if (_disposed) {
      return Future<XboardPurchaseChannels?>.value(null);
    }
    if (!force && purchaseChannels != null) {
      return Future<XboardPurchaseChannels?>.value(purchaseChannels);
    }
    final inFlight = _channelsInFlight;
    if (inFlight != null && !force) return inFlight;
    final extApi = switch (api) {
      final XboardExtendedApi value => value,
      _ => null,
    };
    if (extApi == null) {
      return Future<XboardPurchaseChannels?>.value(null);
    }
    final epochAtStart = _sessionEpoch;
    final authAtStart = _authorization;
    final wasLoggedIn = loggedIn && authAtStart != null;
    if (force) {
      if (extApi case final XboardRefreshableGuestConfigApi refreshable) {
        refreshable.invalidateGuestConfigCache();
      }
    }
    late final Future<XboardPurchaseChannels?> future;
    future = () async {
      try {
        final XboardPurchaseChannels loaded;
        XboardGuestAuthConfig? loadedAuthConfig;
        if (wasLoggedIn) {
          loaded = await extApi.getUserPurchaseChannels(authAtStart);
        } else if (extApi is XboardPassportApi) {
          final results = await Future.wait<Object>([
            extApi.getGuestPurchaseChannels(),
            extApi.getGuestAuthConfig(),
          ]);
          loaded = results[0] as XboardPurchaseChannels;
          loadedAuthConfig = results[1] as XboardGuestAuthConfig;
        } else {
          loaded = await extApi.getGuestPurchaseChannels();
        }
        if (!_disposed &&
            identical(_channelsInFlight, future) &&
            _sessionEpoch == epochAtStart &&
            loggedIn == wasLoggedIn) {
          purchaseChannels = loaded;
          if (loadedAuthConfig != null) {
            guestAuthConfig = loadedAuthConfig;
            if (force) {
              if (!loadedAuthConfig.isInviteForce) {
                inviteCodeRequiredByServer = false;
              }
              if (!loadedAuthConfig.isEmailVerify) {
                emailVerifyRequiredByServer = false;
              }
            }
          }
          cardStoreUrl = loaded.cardStoreUrl;
          channelError = null;
          _notify();
        }
        return loaded;
      } on Exception catch (cause) {
        if (!_disposed &&
            identical(_channelsInFlight, future) &&
            _sessionEpoch == epochAtStart &&
            loggedIn == wasLoggedIn) {
          final failure = _failure(cause);
          if (!failure.isUnauthorized) {
            channelError = failure;
            _notify();
          }
        }
        return null;
      } finally {
        if (identical(_channelsInFlight, future)) {
          _channelsInFlight = null;
        }
      }
    }();
    _channelsInFlight = future;
    return future;
  }

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

  Future<void> _run(
    Future<void> Function() action, {
    _GiftOperation? giftOperation,
    _AuthOperation? authOperation,
    bool clearError = true,
  }) async {
    if (_disposed || busy) return;
    busy = true;
    _authActionGeneration++;
    _giftOperation = giftOperation;
    _authOperation = authOperation;
    if (clearError) {
      error = null;
    }
    _notify();
    try {
      await action();
    } on Exception catch (cause) {
      final failure = _failure(cause);
      if (failure.isUnauthorized && loggedIn) {
        try {
          await storage.clearSession();
        } on Exception {
          error =
              const XboardException(code: 'secure_storage_failed', message: '');
        }
        final confirmedReceipt = receipt;
        _clearAccount();
        receipt = confirmedReceipt;
        unawaited(ensurePurchaseChannels());
      }
      error ??= failure;
    } finally {
      busy = false;
      _giftOperation = null;
      _authOperation = null;
      restoring = false;
      _notify();
    }
  }

  Future<void> initialize() => _run(() async {
        final PurchaseSession? saved;
        try {
          saved = await _storageReadSession();
        } on Exception {
          if (!loggedIn) {
            unawaited(ensurePurchaseChannels(force: channelError != null));
          }
          rethrow;
        }
        if (saved == null) {
          unawaited(ensurePurchaseChannels(force: channelError != null));
          return;
        }
        try {
          final restored = await api.getAccount(saved.authorization);
          if (_disposed) return;
          if (restored.id != saved.accountId || restored.isDistributor) {
            try {
              await storage.clearSession();
            } on Exception {
              throw const XboardException(
                  code: 'secure_storage_failed', message: '');
            }
            throw const XboardException(
                code: 'purchase_account_unsupported', message: '');
          }
          _sessionEpoch++;
          _authorization = saved.authorization;
          account = restored;
          await _restorePending();
          await _refreshData();
        } on Exception catch (cause) {
          if (cause is XboardException && cause.isUnauthorized) {
            try {
              await storage.clearSession();
            } on Exception {
              _clearAccount();
              unawaited(ensurePurchaseChannels(force: channelError != null));
              throw const XboardException(
                  code: 'secure_storage_failed', message: '');
            }
            _clearAccount();
          }
          if (!loggedIn) {
            unawaited(ensurePurchaseChannels(force: channelError != null));
          }
          rethrow;
        }
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

  Future<void> _authenticateWithAuthorization(
    String authorization, {
    required String prefilledCode,
    required bool autoSyncSubscription,
    bool fromRegistration = false,
  }) async {
    try {
      final authenticated = await api.getAccount(authorization);
      if (_disposed) return;
      if (authenticated.isDistributor) {
        throw const XboardException(
            code: 'purchase_account_unsupported', message: '');
      }
      try {
        await storage
            .saveSession(PurchaseSession(authenticated.id, authorization));
      } on Exception {
        throw const XboardException(code: 'secure_storage_failed', message: '');
      }
      if (_disposed) return;
      _sessionEpoch++;
      _channelsInFlight = null;
      _authorization = authorization;
      account = authenticated;
      inviteCodeRequiredByServer = false;
      emailVerifyRequiredByServer = false;
      passwordResetSucceeded = false;
    } on Exception catch (cause) {
      // The token was issued but never admitted to the client session.
      // Best-effort revocation does not mask the original failure.
      try {
        await api.logout(authorization);
      } on Exception {/* Already unusable or offline. */}
      if (fromRegistration &&
          !(cause is XboardException &&
              cause.code == 'purchase_account_unsupported')) {
        throw const XboardException(
          code: 'registration_created_login_required',
          message: '账号已创建成功，请直接登录以同步权益',
        );
      }
      rethrow;
    }
    await _restorePending();
    if (_pending == null && prefilledCode.isNotEmpty) {
      code = prefilledCode;
    }
    if (autoSyncSubscription) {
      _pendingInitialAutoSync = true;
    }
    await _refreshData();
    if (autoSyncSubscription && !_disposed) {
      _pendingInitialAutoSync = false;
      if (subscription?.valid ?? false) {
        await _syncLatest(reuseCurrentSubscription: true);
      }
    }
    if (_pending == null &&
        !_disposed &&
        RegExp(r'^[A-Z0-9]{8,32}$').hasMatch(code)) {
      try {
        final checked = await api.checkGift(_authorization!, code);
        preview = checked;
        _previewCode = code;
      } on XboardException catch (cause) {
        if (cause.isUnauthorized) rethrow;
        error = cause;
      }
    }
  }

  Future<void> login(String email, String password) => _run(
        () async {
          if (loggedIn) return;
          final prefilledCode = code;
          receipt = null;
          final authorization = await api.login(email.trim(), password);
          if (_disposed) return;
          await _authenticateWithAuthorization(
            authorization,
            prefilledCode: prefilledCode,
            autoSyncSubscription: false,
          );
        },
        authOperation: _AuthOperation.login,
      );

  Future<void> register(String email, String password) =>
      registerWithDetails(email: email, password: password);

  Future<void> registerWithDetails({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) =>
      _run(
        () async {
          if (loggedIn) return;
          final apiInstance = api;
          if (apiInstance is! XboardExtendedApi) {
            throw const XboardException(code: 'purchase_failed', message: '');
          }
          final prefilledCode = code;
          receipt = null;
          try {
            final String authorization;
            if (apiInstance is XboardPassportApi) {
              final passportApi = apiInstance as XboardPassportApi;
              authorization = await passportApi.registerAccount(
                email: email.trim(),
                password: password,
                emailCode: emailCode?.trim(),
                inviteCode: inviteCode?.trim(),
              );
            } else {
              authorization =
                  await (apiInstance as XboardExtendedApi).register(
                email.trim(),
                password,
              );
            }
            if (_disposed) return;
            await _authenticateWithAuthorization(
              authorization,
              prefilledCode: prefilledCode,
              autoSyncSubscription: true,
              fromRegistration: true,
            );
          } on XboardException catch (cause) {
            if (cause.code == 'invitation_code_required' ||
                cause.code.toLowerCase().contains('invite_code') ||
                cause.message.toLowerCase().contains('invite_code')) {
              inviteCodeRequiredByServer = true;
            }
            if (cause.code == 'registration_email_invalid' ||
                cause.code.toLowerCase().contains('email_code') ||
                cause.message.toLowerCase().contains('email_code')) {
              emailVerifyRequiredByServer = true;
            }
            rethrow;
          }
        },
        authOperation: _AuthOperation.register,
      );

  Future<bool> sendRegistrationEmailCode(String email) => _sendEmailCode(
        (passportApi) => passportApi.sendRegistrationEmailCode(email.trim()),
      );

  Future<bool> sendPasswordResetCode(String email) => _sendEmailCode(
        (passportApi) => passportApi.sendPasswordResetEmailCode(email.trim()),
      );

  Future<bool> _sendEmailCode(
    Future<void> Function(XboardPassportApi passportApi) send,
  ) async {
    if (_disposed || busy || sendingEmailCode) return false;
    final passportApi = switch (api) {
      final XboardPassportApi value => value,
      _ => null,
    };
    if (passportApi == null) {
      error = const XboardException(code: 'purchase_failed', message: '');
      passwordResetSucceeded = false;
      _notify();
      return false;
    }
    final epochAtStart = _sessionEpoch;
    final loggedInAtStart = loggedIn;
    final authGenAtStart = _authActionGeneration;
    sendingEmailCode = true;
    error = null;
    passwordResetSucceeded = false;
    _notify();
    try {
      await send(passportApi);
      return !_disposed &&
          _sessionEpoch == epochAtStart &&
          loggedIn == loggedInAtStart &&
          _authActionGeneration == authGenAtStart;
    } on Exception catch (cause) {
      if (!_disposed &&
          _sessionEpoch == epochAtStart &&
          loggedIn == loggedInAtStart &&
          _authActionGeneration == authGenAtStart) {
        error = _failure(cause);
      }
      return false;
    } finally {
      sendingEmailCode = false;
      _notify();
    }
  }

  Future<bool> resetPassword({
    required String email,
    required String emailCode,
    required String password,
  }) async {
    if (_disposed || busy) return false;
    if (loggedIn) {
      error = const XboardException(
        code: 'reset_password_requires_logout',
        message: '请先退出当前账号后再重置密码',
      );
      passwordResetSucceeded = false;
      _notify();
      return false;
    }
    var succeeded = false;
    await _run(
      () async {
        final passportApi = switch (api) {
          final XboardPassportApi value => value,
          _ => null,
        };
        if (passportApi == null) {
          throw const XboardException(code: 'purchase_failed', message: '');
        }
        passwordResetSucceeded = false;
        await passportApi.confirmPasswordReset(
          email: email.trim(),
          emailCode: emailCode.trim(),
          password: password,
        );
        if (!_disposed) {
          passwordResetSucceeded = true;
          succeeded = true;
        }
      },
      authOperation: _AuthOperation.resetPassword,
    );
    return succeeded;
  }

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
        unawaited(ensurePurchaseChannels());
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
    _sessionEpoch++;
    _channelsInFlight = null;
    _initialSyncAttemptedAccountId = null;
    _pendingInitialAutoSync = false;
    _authorization = null;
    account = null;
    subscription = null;
    preview = null;
    receipt = null;
    history = null;
    cardStoreUrl = null;
    purchaseChannels = null;
    guestAuthConfig = const XboardGuestAuthConfig();
    handoffPlan = null;
    _pending = null;
    _pendingStateReady = false;
    code = '';
    _previewCode = null;
    historyError = null;
    syncError = null;
    channelError = null;
    subscriptionSynced = false;
    passwordResetSucceeded = false;
    inviteCodeRequiredByServer = false;
    emailVerifyRequiredByServer = false;
  }

  static final RegExp _codeSeparators =
      RegExp(r'[\s\u00AD\u2010-\u2015\u2212-]+');

  static String normalizeCodeInput(String value) =>
      value.replaceAll(_codeSeparators, '').toUpperCase();

  void setCode(String value) {
    if (busy || unresolvedRedemption || _disposed) return;
    final normalized = normalizeCodeInput(value);
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
    handoffPlan = null;
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

  Future<void> _refreshAndFlushInitialAutoSync() async {
    await _refreshData();
    if (_pendingInitialAutoSync && !_disposed) {
      _pendingInitialAutoSync = false;
      if (subscription?.valid ?? false) {
        await _syncLatest(reuseCurrentSubscription: true);
      }
    }
  }

  Future<void> refresh() {
    if (!loggedIn) return initialize();
    if (!_pendingStateReady) {
      return _run(() async {
        await _restorePending();
        await _refreshAndFlushInitialAutoSync();
      });
    }
    if (unresolvedRedemption) return recoverRedemption();
    return _run(_refreshAndFlushInitialAutoSync);
  }

  Future<void> _refreshData() async {
    final authorization = _authorization!;
    XboardException? unauthorizedFailure;
    Exception? otherFailure;
    XboardSubscription? nextSubscription;

    final subscriptionFuture = () async {
      try {
        nextSubscription = await api.getSubscription(authorization);
      } on XboardException catch (cause) {
        if (cause.isUnauthorized) {
          unauthorizedFailure ??= cause;
        } else {
          otherFailure ??= cause;
        }
      } on Exception catch (cause) {
        otherFailure ??= cause;
      }
    }();

    final historyFuture = () async {
      historyError = null;
      try {
        history = await api.getGiftHistory(authorization, page: 1);
      } on XboardException catch (cause) {
        if (cause.isUnauthorized) {
          unauthorizedFailure ??= cause;
        } else {
          historyError = cause;
        }
      } on Exception catch (cause) {
        otherFailure ??= cause;
      }
    }();

    final cardStoreFuture = () async {
      channelError = null;
      try {
        final apiInstance = api;
        if (apiInstance is XboardExtendedApi) {
          final extApi = apiInstance as XboardExtendedApi;
          final channels =
              await extApi.getUserPurchaseChannels(authorization);
          purchaseChannels = channels;
          cardStoreUrl = channels.cardStoreUrl;
        } else {
          cardStoreUrl = await api.getCardStore(authorization);
        }
      } on XboardException catch (cause) {
        if (cause.isUnauthorized) {
          unauthorizedFailure ??= cause;
        } else {
          channelError = cause;
        }
      } catch (cause) {
        channelError = _failure(cause);
      }
    }();

    await Future.wait<void>([
      subscriptionFuture,
      historyFuture,
      cardStoreFuture,
    ]);
    if (unauthorizedFailure != null) throw unauthorizedFailure!;
    if (otherFailure != null) throw otherFailure!;
    subscription = nextSubscription;
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

  Future<void> syncSubscription() => _run(
        () async {
          if (loggedIn) await _syncLatest();
        },
        clearError: false,
      );

  Future<void> _syncLatest({bool reuseCurrentSubscription = false}) async {
    _pendingInitialAutoSync = false;
    if (account != null) {
      _initialSyncAttemptedAccountId = account!.id;
    }
    syncError = null;
    subscriptionSynced = false;
    syncing = true;
    _notify();
    try {
      if (!reuseCurrentSubscription || subscription == null) {
        subscription = await api.getSubscription(_authorization!);
      }
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
