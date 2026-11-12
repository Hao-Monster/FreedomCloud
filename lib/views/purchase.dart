import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/common/http.dart';
import 'package:flclashx/common/preferences.dart';
import 'package:flclashx/common/smart_node_selection.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/purchase/center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final PurchaseManager _manager;
  bool _wasLoggedIn = false;
  int? _autoSyncedAccountId;

  void _onManagerChanged() {
    if (!mounted) return;
    final isLoggedIn = _manager.loggedIn;
    if (!isLoggedIn) {
      _wasLoggedIn = false;
      _autoSyncedAccountId = null;
      return;
    }
    if (!_wasLoggedIn) {
      _wasLoggedIn = true;
    }
    final accountId = _manager.account?.id;
    if (!_manager.busy &&
        !_manager.syncing &&
        !_manager.unresolvedRedemption &&
        accountId != null &&
        _autoSyncedAccountId != accountId &&
        (_manager.subscription?.valid ?? false) &&
        globalState.isConfigInitialized &&
        ref.read(profilesProvider).isEmpty) {
      _autoSyncedAccountId = accountId;
      unawaited(_manager.syncSubscription());
    }
  }

  @override
  void initState() {
    super.initState();
    late final DioXboardApi defaultApi;
    final api = widget.apiOverride ??
        (defaultApi = DioXboardApi(
          shouldFallbackToDirect: () =>
              HttpOverrides.current is FlClashHttpOverrides &&
              FlClashHttpOverrides.handleFindProxy(defaultApi.baseUri)
                  .startsWith('PROXY '),
        ));
    final storage = widget.storageOverride ?? SecurePurchaseStorage(api.baseUri);
    Uint8List? downloadedBytes;
    final synchronizer = PurchaseProfileSynchronizer(
      origin: api.baseUri,
      storage: storage,
      readProfiles: () =>
          globalState.isConfigInitialized ? ref.read(profilesProvider) : const [],
      download: widget.downloadOverride ??
          (profile) async {
            final settings = await SharedPreferences.getInstance();
            downloadedBytes = null;
            final fetched = await profile.fetch(
                shouldSendHeaders:
                    settings.getBool('sendDeviceHeaders') ?? true);
            downloadedBytes = fetched.bytes;
            return fetched.profile;
          },
      save: (profile) async {
        if (!mounted) throw const FormatException('Purchase view is closed');
        final beforeSave = ref.read(profilesProvider).getProfile(profile.id);
        final Profile written;
        if (widget.downloadOverride != null) {
          written = profile;
        } else {
          final bytes = downloadedBytes;
          if (bytes == null) {
            throw const FormatException('No downloaded profile');
          }
          written = await profile.saveFile(bytes,
              canSave: () =>
                  mounted &&
                  ref.read(profilesProvider).getProfile(profile.id) ==
                      beforeSave);
          downloadedBytes = null;
        }
        if (!mounted ||
            ref.read(profilesProvider).getProfile(profile.id) != beforeSave) {
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
          final hadZeroProfiles = ref.read(profilesProvider).isEmpty;
          if (!written.providerHeaders.containsKey(smartSelectionModeMarker) &&
              written.selectedMap.isEmpty) {
            effectiveProfile =
                markProfileSelectionMode(written, NodeSelectionMode.smart);
          }
          ref.read(profilesProvider.notifier).setProfile(effectiveProfile);
          if (ref.read(currentProfileIdProvider) == null) {
            ref.read(currentProfileIdProvider.notifier).value =
                effectiveProfile.id;
          }
          if (hadZeroProfiles) {
            ref.read(pendingNoviceFirstProfileAutoTestProvider.notifier).state =
                effectiveProfile.id;
          }
        }
        final saveConfig = widget.saveConfigOverride ?? preferences.saveConfig;
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
    _manager = PurchaseManager(
        api: api, storage: storage, synchronize: synchronizer.synchronize)
      ..addListener(_onManagerChanged);
    unawaited(_manager.initialize());
    unawaited(_manager.loadPlans());
  }

  @override
  void dispose() {
    _manager
      ..removeListener(_onManagerChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (globalState.isConfigInitialized) {
      ref.watch(profilesProvider.select((profiles) => profiles.length));
      ref.watch(currentProfileIdProvider);
    }
    return PurchaseCenter(
      manager: _manager,
      openLink: (url) async {
        if (url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty ||
            !await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw const FormatException('Could not open the account website');
        }
      },
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
