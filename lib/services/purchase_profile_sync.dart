import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_storage.dart';

/// Matches managed profiles by account ownership, even after subscription-token
/// rotation. Exact URL matching also adopts a subscription previously imported
/// by the user, preserving its label, overrides and selected proxy groups.
class PurchaseProfileSynchronizer {
  PurchaseProfileSynchronizer({
    required this.origin,
    required this.storage,
    required this.readProfiles,
    required this.download,
    required this.save,
  });

  final Uri origin;
  final PurchaseStorage storage;
  final List<Profile> Function() readProfiles;
  final Future<Profile> Function(Profile) download;
  final Future<void> Function(Profile) save;

  Future<void> synchronize(
      XboardAccount account, XboardSubscription subscription) async {
    if (!subscription.valid ||
        subscription.url.scheme != 'https' ||
        subscription.url.userInfo.isNotEmpty ||
        subscription.url.host.isEmpty) {
      throw const FormatException(
          'Subscription is not available for synchronization');
    }
    final ownership = sha256
        .convert(utf8.encode('${origin.origin}/${account.id}'))
        .toString();
    final profileId = await storage.readProfileId(account.id);
    final profiles = readProfiles();
    Profile? existing;
    for (final profile in profiles) {
      if (profile.providerHeaders[xboardAccountMarker] == ownership &&
          profile.id == profileId) {
        existing = profile;
        break;
      }
    }
    existing ??= _find(profiles,
        (profile) => profile.providerHeaders[xboardAccountMarker] == ownership);
    existing ??= _find(
        profiles,
        (profile) =>
            profile.url == subscription.url.toString() &&
            (profile.providerHeaders[xboardAccountMarker] == null ||
                profile.providerHeaders[xboardAccountMarker] == ownership));
    final base = existing ??
        Profile.normal(label: 'Xboard · ${account.email}')
            .copyWith(id: 'xboard-$ownership');
    final target = base.copyWith(
      url: subscription.url.toString(),
      providerHeaders: {
        ...base.providerHeaders,
        xboardAccountMarker: ownership,
        xboardTlsMarker: 'required'
      },
    );
    final fetched = await download(target);
    await storage.saveProfileId(account.id, fetched.id);
    // A local download must not restore a profile the user removed in flight.
    final latest = _find(readProfiles(), (profile) => profile.id == base.id);
    if (existing != null && latest == null) {
      throw const FormatException('Profile was removed during synchronization');
    }
    if (latest != null &&
        (latest.url != base.url ||
            latest.providerHeaders[xboardAccountMarker] !=
                base.providerHeaders[xboardAccountMarker])) {
      throw const FormatException(
          'Profile source changed during synchronization');
    }
    // Only replace downloaded metadata; local choices may have changed while
    // the network request or secure storage write was pending.
    final updated = (latest ?? fetched).copyWith(
      url: fetched.url,
      lastUpdateDate: fetched.lastUpdateDate,
      subscriptionInfo: fetched.subscriptionInfo,
      autoUpdateDuration:
          latest != null && latest.autoUpdateDuration != base.autoUpdateDuration
              ? latest.autoUpdateDuration
              : fetched.autoUpdateDuration,
      isUpdating: false,
      providerHeaders: {
        ...fetched.providerHeaders,
        xboardAccountMarker: ownership,
        xboardTlsMarker: 'required'
      },
    );
    await save(updated);
  }

  Profile? _find(List<Profile> profiles, bool Function(Profile) predicate) {
    for (final profile in profiles) {
      if (predicate(profile)) return profile;
    }
    return null;
  }
}
