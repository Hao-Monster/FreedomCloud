import 'dart:async';

import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/providers/purchase_support_provider.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PurchaseView extends ConsumerStatefulWidget {
  const PurchaseView({
    super.key,
    @visibleForTesting this.apiOverride,
    @visibleForTesting this.storageOverride,
    @visibleForTesting this.downloadOverride,
    @visibleForTesting this.saveConfigOverride,
  });

  @visibleForTesting
  final XboardApi? apiOverride;
  @visibleForTesting
  final PurchaseStorage? storageOverride;
  @visibleForTesting
  final Future<Profile> Function(Profile)? downloadOverride;
  @visibleForTesting
  final Future<bool> Function(Config config)? saveConfigOverride;

  @override
  ConsumerState<PurchaseView> createState() => _PurchaseViewState();
}

class _PurchaseViewState extends ConsumerState<PurchaseView> {
  PurchaseManager? _ownedManager;
  SupportManagerHandle? _ownedSupportHandle;
  late final PurchaseManager _manager;
  late final SupportManager _supportManager;
  int? _autoSyncedAccountId;

  bool get _hasTestOverrides =>
      widget.apiOverride != null ||
      widget.storageOverride != null ||
      widget.downloadOverride != null ||
      widget.saveConfigOverride != null;

  void _onOwnedManagerChanged() {
    if (!mounted) return;
    syncSupportManagerWithPurchase(_manager, _supportManager);
    if (!_manager.loggedIn) {
      _autoSyncedAccountId = null;
      return;
    }
    final accountId = _manager.account?.id;
    if (!_manager.busy &&
        !_manager.syncing &&
        !_manager.unresolvedRedemption &&
        accountId != null &&
        _autoSyncedAccountId != accountId &&
        !_manager.hasAttemptedInitialSyncFor(accountId) &&
        (_manager.subscription?.valid ?? false) &&
        globalState.isConfigInitialized &&
        ref.read(profilesProvider).isEmpty) {
      _autoSyncedAccountId = accountId;
      scheduleMicrotask(() {
        if (mounted &&
            _manager.loggedIn &&
            _manager.account?.id == accountId &&
            !_manager.busy &&
            !_manager.syncing &&
            !_manager.unresolvedRedemption) {
          unawaited(_manager.syncSubscription());
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_hasTestOverrides) {
      final coordinator = ref.read(purchaseSupportCoordinatorProvider)
        ..ensureInitialized();
      _manager = coordinator.purchaseManager;
      _supportManager = coordinator.supportManager;
      return;
    }

    late final DioXboardApi defaultApi;
    final api = widget.apiOverride ??
        (defaultApi = DioXboardApi(
          shouldFallbackToDirect: () =>
              shouldFallbackToDirectForUri(defaultApi.baseUri),
        ));
    final storage = widget.storageOverride ?? SecurePurchaseStorage(api.baseUri);
    final synchronizer = createAppPurchaseSynchronizer(
      read: ref.read,
      origin: api.baseUri,
      storage: storage,
      isActive: () => mounted,
      downloadOverride: widget.downloadOverride,
      saveConfigOverride: widget.saveConfigOverride,
    );
    _ownedSupportHandle = createSupportManagerHandle(
      fallbackBaseUrl: () => api.baseUri,
    );
    _supportManager = _ownedSupportHandle!.manager;
    _ownedManager = PurchaseManager(
      api: api,
      storage: storage,
      synchronize: synchronizer.synchronize,
    )..addListener(_onOwnedManagerChanged);
    _manager = _ownedManager!;
    syncSupportManagerWithPurchase(_manager, _supportManager);
    unawaited(_manager.initialize());
    unawaited(_manager.loadPlans());
  }

  @override
  void dispose() {
    if (_ownedManager != null) {
      _ownedManager!
        ..removeListener(_onOwnedManagerChanged)
        ..dispose();
      _ownedSupportHandle?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (globalState.isConfigInitialized) {
      ref.watch(profilesProvider.select((profiles) => profiles.length));
      ref.watch(currentProfileIdProvider);
    }
    final isPurchaseTab = ref.watch(
      currentPageLabelProvider.select((label) => label == PageLabel.purchase),
    );
    final isActiveTab = globalState.homeScaffoldKey.currentContext == null ||
        !globalState.isAppStateInitialized ||
        isPurchaseTab;
    return PurchaseCenter(
      manager: _manager,
      supportManager: _supportManager,
      isActiveTab: isActiveTab,
      openLink: openHttpsExternalLink,
      openProfiles: () {
        ref.read(proxiesScopeProvider.notifier).state = ProxiesScope.all;
        if (globalState.isAppControllerReady) {
          globalState.appController.toPage(PageLabel.proxies);
        } else {
          ref.read(currentPageLabelProvider.notifier).value = PageLabel.proxies;
        }
      },
    );
  }
}
