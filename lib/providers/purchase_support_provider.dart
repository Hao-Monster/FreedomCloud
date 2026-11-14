import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/common/http.dart';
import 'package:flclashx/common/preferences.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks whether transport errors for [uri] should fall back from the local
/// Clash proxy port to `DIRECT` when [FlClashHttpOverrides] is active.
bool shouldFallbackToDirectForUri(Uri uri) =>
    HttpOverrides.current is FlClashHttpOverrides &&
    globalState.isAppStateInitialized &&
    globalState.isConfigInitialized &&
    FlClashHttpOverrides.handleFindProxy(uri).startsWith('PROXY ');

/// Launches an external HTTPS link using the host browser, rejecting unsafe
/// schemes or credentials embedded in URLs.
Future<void> openHttpsExternalLink(Uri url) async {
  if (url.scheme != 'https' ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      !await launchUrl(url, mode: LaunchMode.externalApplication)) {
    throw const FormatException('Could not open the account website');
  }
}

/// Keeps [SupportManager]'s Chatwoot channel and account scope synchronized with
/// the active [PurchaseManager] state.
void syncSupportManagerWithPurchase(
  PurchaseManager purchaseManager,
  SupportManager supportManager,
) {
  if (!PurchaseManager.isRealInstance(purchaseManager)) {
    return;
  }
  final channels = purchaseManager.purchaseChannels;
  if (channels != null) {
    if (channels.chatwootBaseUrl != null &&
        channels.chatwootWebsiteToken != null) {
      supportManager.configureChannel(
        baseUrl: channels.chatwootBaseUrl,
        websiteToken: channels.chatwootWebsiteToken,
      );
    } else {
      supportManager.configureChannel(
        baseUrl: null,
        websiteToken: null,
      );
    }
  }
  final account = purchaseManager.account;
  supportManager.bindAccount(
    accountId: account?.id,
    email: account?.email,
  );
}

/// Bundles a [SupportManager] with its owned [ChatwootService] so callers can
/// dispose both cleanly together.
class SupportManagerHandle {
  SupportManagerHandle._({
    required this.manager,
    required ChatwootService service,
  }) : _service = service;

  final SupportManager manager;
  final ChatwootService _service;

  void dispose() {
    manager.dispose();
    _service.close();
  }
}

/// Creates a [SupportManagerHandle] wired with [DioChatwootService] and
/// [ActionCableChatwootRealtime] using the same direct-fallback policy as
/// [DioXboardApi].
SupportManagerHandle createSupportManagerHandle({
  Uri? Function()? fallbackBaseUrl,
}) {
  late final SupportManager manager;
  final service = DioChatwootService(
    shouldFallbackToDirect: () {
      final target = manager.channelConfig?.baseUrl ?? fallbackBaseUrl?.call();
      if (target == null) return false;
      return shouldFallbackToDirectForUri(target);
    },
  );
  manager = SupportManager(
    service: service,
    realtimeConnector: (baseUrl, pubsubToken) =>
        ActionCableChatwootRealtime.connect(
      baseUrl: baseUrl,
      pubsubToken: pubsubToken,
      shouldFallbackToDirect: () => shouldFallbackToDirectForUri(baseUrl),
    ),
  );
  return SupportManagerHandle._(manager: manager, service: service);
}

/// Creates a [PurchaseProfileSynchronizer] wired to Riverpod `read` and
/// `globalState.appController`.
PurchaseProfileSynchronizer createAppPurchaseSynchronizer({
  required T Function<T>(ProviderListenable<T>) read,
  required Uri origin,
  required PurchaseStorage storage,
  required bool Function() isActive,
  Future<Profile> Function(Profile)? downloadOverride,
  Future<bool> Function(Config config)? saveConfigOverride,
}) {
  Uint8List? downloadedBytes;
  return PurchaseProfileSynchronizer(
    origin: origin,
    storage: storage,
    readProfiles: () =>
        globalState.isConfigInitialized ? read(profilesProvider) : const [],
    download: downloadOverride ??
        (profile) async {
          final settings = await SharedPreferences.getInstance();
          downloadedBytes = null;
          final fetched = await profile.fetch(
            shouldSendHeaders: settings.getBool('sendDeviceHeaders') ?? true,
          );
          downloadedBytes = fetched.bytes;
          return fetched.profile;
        },
    save: (profile) async {
      if (!isActive()) {
        throw const FormatException('Purchase view is closed');
      }
      final beforeSave = read(profilesProvider).getProfile(profile.id);
      final Profile written;
      if (downloadOverride != null) {
        written = profile;
      } else {
        final bytes = downloadedBytes;
        if (bytes == null) {
          throw const FormatException('No downloaded profile');
        }
        written = await profile.saveFile(
          bytes,
          canSave: () =>
              isActive() &&
              read(profilesProvider).getProfile(profile.id) == beforeSave,
        );
        downloadedBytes = null;
      }
      if (!isActive() ||
          read(profilesProvider).getProfile(profile.id) != beforeSave) {
        throw const FormatException('Profile changed during synchronization');
      }
      var effectiveProfile = written;
      if (globalState.isAppControllerReady) {
        effectiveProfile =
            await globalState.appController.registerImportedProfileForNovice(
          written,
          isNewProfile: beforeSave == null,
        );
      } else {
        final hadZeroProfiles = read(profilesProvider).isEmpty;
        if (!written.providerHeaders.containsKey(smartSelectionModeMarker) &&
            written.selectedMap.isEmpty) {
          effectiveProfile =
              markProfileSelectionMode(written, NodeSelectionMode.smart);
        }
        read(profilesProvider.notifier).setProfile(effectiveProfile);
        if (read(currentProfileIdProvider) == null) {
          read(currentProfileIdProvider.notifier).value = effectiveProfile.id;
        }
        if (hadZeroProfiles) {
          read(pendingNoviceFirstProfileAutoTestProvider.notifier).state =
              effectiveProfile.id;
        }
      }
      final saveConfig = saveConfigOverride ?? preferences.saveConfig;
      final saved = await saveConfig(globalState.config);
      if (!saved) {
        throw const FormatException('Profile settings were not saved');
      }
      if (globalState.isAppControllerReady) {
        await globalState.appController
            .tryStartProxyForActiveNoviceProfile(effectiveProfile.id);
      }
    },
  );
}

/// App-lifetime coordinator that shares [PurchaseManager] and [SupportManager]
/// across tab switches so returning to PurchaseView mounts instantaneously
/// without redundant storage or network calls.
class PurchaseSupportCoordinator {
  PurchaseSupportCoordinator(this._ref) {
    late final DioXboardApi defaultApi;
    defaultApi = DioXboardApi(
      shouldFallbackToDirect: () =>
          shouldFallbackToDirectForUri(defaultApi.baseUri),
    );
    _init(
      api: defaultApi,
      storage: SecurePurchaseStorage(defaultApi.baseUri),
      supportHandle: createSupportManagerHandle(
        fallbackBaseUrl: () => defaultApi.baseUri,
      ),
    );
  }

  /// Creates an isolated coordinator backed by injected fakes for widget tests.
  @visibleForTesting
  PurchaseSupportCoordinator.test(
    this._ref, {
    required XboardApi api,
    required PurchaseStorage storage,
    required SupportManager supportManager,
    ChatwootService? chatwootService,
  }) {
    _api = api;
    _storage = storage;
    final synchronizer = createAppPurchaseSynchronizer(
      read: _ref.read,
      origin: _api.baseUri,
      storage: _storage,
      isActive: () => !_disposed,
    );
    purchaseManager = PurchaseManager(
      api: _api,
      storage: _storage,
      synchronize: synchronizer.synchronize,
    )..addListener(_onPurchaseManagerChanged);
    _supportHandle = chatwootService == null
        ? null
        : SupportManagerHandle._(
            manager: supportManager,
            service: chatwootService,
          );
    this.supportManager = supportManager;
    syncSupportManagerWithPurchase(purchaseManager, this.supportManager);
  }

  void _init({
    required XboardApi api,
    required PurchaseStorage storage,
    required SupportManagerHandle supportHandle,
  }) {
    _api = api;
    _storage = storage;
    final synchronizer = createAppPurchaseSynchronizer(
      read: _ref.read,
      origin: _api.baseUri,
      storage: _storage,
      isActive: () => !_disposed,
    );
    purchaseManager = PurchaseManager(
      api: _api,
      storage: _storage,
      synchronize: synchronizer.synchronize,
    )..addListener(_onPurchaseManagerChanged);
    _supportHandle = supportHandle;
    supportManager = supportHandle.manager;
    syncSupportManagerWithPurchase(purchaseManager, supportManager);
  }

  final Ref _ref;
  late final XboardApi _api;
  late final PurchaseStorage _storage;
  late final PurchaseManager purchaseManager;
  late final SupportManagerHandle? _supportHandle;
  late final SupportManager supportManager;

  bool _disposed = false;
  bool _initialized = false;
  Future<void>? _initFuture;
  int? _autoSyncedAccountId;

  /// Runs one-time initialization and catalog loading on first access.
  void ensureInitialized() {
    if (_disposed || _initialized) return;
    _initialized = true;
    _initFuture = purchaseManager.initialize();
    unawaited(_initFuture);
    unawaited(purchaseManager.loadPlans());
  }

  /// Ensures Chatwoot channel metadata is fetched and synced before opening
  /// support from a global navigation entry.
  Future<void> prepareSupport({bool force = false}) async {
    if (_disposed) return;
    ensureInitialized();
    await (_initFuture ?? Future<void>.value());
    if (_disposed) return;
    if (force || !supportManager.isConfigured) {
      await purchaseManager.ensurePurchaseChannels(
        force: force || purchaseManager.channelError != null,
      );
      if (_disposed) return;
      syncSupportManagerWithPurchase(purchaseManager, supportManager);
    }
  }

  Uri? resolveExternalWidgetUri(Locale locale) =>
      purchaseManager.purchaseChannels?.resolveChatwootWidgetUrl(
        locale: locale.toString(),
      );

  void _onPurchaseManagerChanged() {
    if (_disposed) return;
    syncSupportManagerWithPurchase(purchaseManager, supportManager);
    if (!purchaseManager.loggedIn) {
      _autoSyncedAccountId = null;
      return;
    }
    final accountId = purchaseManager.account?.id;
    if (!purchaseManager.busy &&
        !purchaseManager.syncing &&
        !purchaseManager.unresolvedRedemption &&
        accountId != null &&
        _autoSyncedAccountId != accountId &&
        !purchaseManager.hasAttemptedInitialSyncFor(accountId) &&
        (purchaseManager.subscription?.valid ?? false) &&
        globalState.isConfigInitialized &&
        _ref.read(profilesProvider).isEmpty) {
      _autoSyncedAccountId = accountId;
      scheduleMicrotask(() {
        if (!_disposed &&
            purchaseManager.loggedIn &&
            purchaseManager.account?.id == accountId &&
            !purchaseManager.busy &&
            !purchaseManager.syncing &&
            !purchaseManager.unresolvedRedemption) {
          unawaited(purchaseManager.syncSubscription());
        }
      });
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    purchaseManager
      ..removeListener(_onPurchaseManagerChanged)
      ..dispose();
    _supportHandle?.dispose();
  }
}

final purchaseSupportCoordinatorProvider =
    Provider<PurchaseSupportCoordinator>((ref) {
  final coordinator = PurchaseSupportCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
