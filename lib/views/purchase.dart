import 'dart:async';
import 'dart:typed_data';

import 'package:flclashx/common/preferences.dart';
import 'package:flclashx/manager/purchase_manager.dart';
import 'package:flclashx/models/profile.dart';
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
  const PurchaseView({super.key});

  @override
  ConsumerState<PurchaseView> createState() => _PurchaseViewState();
}

class _PurchaseViewState extends ConsumerState<PurchaseView> {
  late final PurchaseManager _manager;

  @override
  void initState() {
    super.initState();
    final api = DioXboardApi();
    final storage = SecurePurchaseStorage(api.baseUri);
    Uint8List? downloadedBytes;
    final synchronizer = PurchaseProfileSynchronizer(
      origin: api.baseUri,
      storage: storage,
      readProfiles: () => ref.read(profilesProvider),
      download: (profile) async {
        final settings = await SharedPreferences.getInstance();
        downloadedBytes = null;
        final fetched = await profile.fetch(
            shouldSendHeaders: settings.getBool('sendDeviceHeaders') ?? true);
        downloadedBytes = fetched.bytes;
        return fetched.profile;
      },
      save: (profile) async {
        if (!mounted) throw const FormatException('Purchase view is closed');
        final beforeSave = ref.read(profilesProvider).getProfile(profile.id);
        final bytes = downloadedBytes;
        if (bytes == null) throw const FormatException('No downloaded profile');
        final written = await profile.saveFile(bytes,
            canSave: () =>
                mounted &&
                ref.read(profilesProvider).getProfile(profile.id) ==
                    beforeSave);
        downloadedBytes = null;
        if (!mounted ||
            ref.read(profilesProvider).getProfile(profile.id) != beforeSave) {
          throw const FormatException('Profile changed during synchronization');
        }
        // Save without auto-selecting a new profile or applying provider UI
        // settings to a different active subscription.
        globalState.appController.setProfileAndAutoApply(written);
        final saved = await preferences.saveConfig(globalState.config);
        if (!saved) {
          throw const FormatException('Profile settings were not saved');
        }
      },
    );
    _manager = PurchaseManager(
        api: api, storage: storage, synchronize: synchronizer.synchronize);
    unawaited(_manager.initialize());
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PurchaseCenter(
        manager: _manager,
        openLink: (url) async {
          if (url.scheme != 'https' ||
              url.host.isEmpty ||
              url.userInfo.isNotEmpty ||
              !await launchUrl(url, mode: LaunchMode.externalApplication)) {
            throw const FormatException('Could not open the account website');
          }
        },
        openProfiles: () => globalState.appController.toProfiles(),
      );
}
