import 'dart:async';

import 'package:flclashx/models/clash_config.dart';
import 'package:flclashx/models/profile.dart';
import 'package:flclashx/models/xboard.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _member = XboardAccount(id: 11, email: 'member@example.test');
const _other = XboardAccount(id: 12, email: 'other@example.test');
final _downloadDate = DateTime.utc(2026, 10, 4, 12);
const _override = OverrideData(
  enable: true,
  rule: OverrideRule(addedRules: [
    Rule(id: 'custom-1', value: 'DOMAIN,example.test,DIRECT'),
  ]),
);
const _newOverride = OverrideData(
  enable: true,
  rule: OverrideRule(addedRules: [
    Rule(id: 'custom-2', value: 'DOMAIN,updated.example.test,REJECT'),
  ]),
);

XboardSubscription _subscription([String token = 'synthetic-token']) =>
    XboardSubscription(
      valid: true,
      planId: 3,
      planName: 'Test plan',
      url: Uri.parse('https://panel.example.test/subscribe?token=$token'),
    );

Profile _profile(String id, {String? url}) => Profile(
      id: id,
      label: 'My local label',
      url: url ?? _subscription().url.toString(),
      autoUpdateDuration: const Duration(hours: 12),
      autoUpdate: false,
      selectedMap: const {'Proxy': 'Chosen node'},
      overrideData: _override,
      currentGroupName: 'Proxy',
      unfoldSet: const {'Proxy'},
    );

void main() {
  test('same account reuses its profile across syncs and token rotation',
      () async {
    final harness = _Harness();
    await harness.synchronizer.synchronize(_member, _subscription());
    final first = harness.profiles.single;
    expect(first.providerHeaders[xboardTlsMarker], 'required');

    await harness.synchronizer.synchronize(_member, _subscription());
    await harness.synchronizer
        .synchronize(_member, _subscription('rotated-synthetic-token'));

    expect(harness.profiles, hasLength(1));
    expect(harness.profiles.single.id, first.id);
    expect(harness.profiles.single.url,
        _subscription('rotated-synthetic-token').url.toString());
    expect(harness.storage.profileIds[_member.id], first.id);
    expect(harness.downloads, hasLength(3));
    expect(
        harness.downloads.every((profile) => profile.id == first.id), isTrue);
  });

  test('adopts an exact imported subscription while preserving user settings',
      () async {
    final imported = _profile('imported');
    final unrelated =
        _profile('unrelated', url: 'https://elsewhere.example.test/sub');
    final harness = _Harness([imported, unrelated]);

    await harness.synchronizer.synchronize(_member, _subscription());

    final saved =
        harness.profiles.firstWhere((profile) => profile.id == imported.id);
    expect(harness.profiles, hasLength(2));
    expect(saved.label, imported.label);
    expect(saved.selectedMap, imported.selectedMap);
    expect(saved.overrideData, imported.overrideData);
    expect(saved.currentGroupName, imported.currentGroupName);
    expect(saved.unfoldSet, imported.unfoldSet);
    expect(saved.autoUpdate, imported.autoUpdate);
    expect(saved.providerHeaders[xboardTlsMarker], 'required');
    expect(harness.profiles.firstWhere((profile) => profile.id == unrelated.id),
        unrelated);
    expect(harness.storage.profileIds[_member.id], imported.id);
  });

  test('a mapping to another account never overwrites its profile', () async {
    final harness = _Harness();
    // The same URL deliberately exercises both the ID and URL ownership guards.
    await harness.synchronizer.synchronize(_other, _subscription());
    final otherProfile = harness.profiles.single;
    harness.storage.profileIds[_member.id] = otherProfile.id;

    await harness.synchronizer.synchronize(_member, _subscription());

    expect(harness.profiles, hasLength(2));
    expect(
        harness.profiles.firstWhere((profile) => profile.id == otherProfile.id),
        otherProfile);
    expect(harness.storage.profileIds[_member.id], isNot(otherProfile.id));
    expect(harness.storage.profileIds[_other.id], otherProfile.id);
    expect(harness.downloads.last.id, isNot(otherProfile.id));
  });

  test('download failure neither saves nor remaps a profile', () async {
    final original = _profile('existing');
    final harness = _Harness([original])
      ..downloader = (_) async =>
          throw const FormatException('Synthetic download failure');

    await expectLater(
      harness.synchronizer.synchronize(_member, _subscription()),
      throwsA(isA<FormatException>()),
    );

    expect(harness.saved, isEmpty);
    expect(harness.storage.writeCalls, 0);
    expect(harness.storage.profileIds, isEmpty);
    expect(harness.profiles, [original]);
  });

  test('secure mapping read failure stops before downloading or saving',
      () async {
    final original = _profile('existing');
    final harness = _Harness([original])..storage.failRead = true;

    await expectLater(
      harness.synchronizer.synchronize(_member, _subscription()),
      throwsA(isA<FormatException>()),
    );

    expect(harness.downloads, isEmpty);
    expect(harness.saved, isEmpty);
    expect(harness.profiles, [original]);
  });

  test('secure mapping write failure does not save downloaded metadata',
      () async {
    final original = _profile('existing');
    final harness = _Harness([original])..storage.failWrite = true;

    await expectLater(
      harness.synchronizer.synchronize(_member, _subscription()),
      throwsA(isA<FormatException>()),
    );

    expect(harness.downloads, hasLength(1));
    expect(harness.storage.writeCalls, 1);
    expect(harness.saved, isEmpty);
    expect(harness.storage.profileIds, isEmpty);
    expect(harness.profiles, [original]);
  });

  test('deleting a profile during download does not resurrect it', () async {
    final original = _profile('existing');
    final harness = _Harness([original]);
    final started = Completer<void>();
    final release = Completer<void>();
    harness.downloader = (target) async {
      started.complete();
      await release.future;
      return _fetched(target);
    };
    final result = expectLater(
      harness.synchronizer.synchronize(_member, _subscription()),
      throwsA(isA<FormatException>()),
    );
    await started.future;
    harness.profiles.clear();
    release.complete();
    await result;

    expect(harness.saved, isEmpty);
    expect(harness.profiles, isEmpty);
  });

  test('local edits during download survive with fresh subscription metadata',
      () async {
    final original = _profile('existing');
    final harness = _Harness([original]);
    final started = Completer<void>();
    final release = Completer<void>();
    harness.downloader = (target) async {
      started.complete();
      await release.future;
      return _fetched(target);
    };
    final synchronization =
        harness.synchronizer.synchronize(_member, _subscription());
    await started.future;
    final edited = original.copyWith(
      label: 'Edited while downloading',
      selectedMap: {'Proxy': 'Newly chosen node'},
      overrideData: _newOverride,
      currentGroupName: 'New group',
      unfoldSet: {'New group'},
      autoUpdate: true,
    );
    harness.profiles[0] = edited;
    release.complete();
    await synchronization;

    expect(harness.profiles, hasLength(1));
    final saved = harness.profiles.single;
    expect(saved.label, edited.label);
    expect(saved.selectedMap, edited.selectedMap);
    expect(saved.overrideData, edited.overrideData);
    expect(saved.currentGroupName, edited.currentGroupName);
    expect(saved.unfoldSet, edited.unfoldSet);
    expect(saved.autoUpdate, edited.autoUpdate);
    expect(saved.lastUpdateDate, _downloadDate);
    expect(saved.subscriptionInfo, const SubscriptionInfo(total: 123456));
    expect(saved.providerHeaders['announce'], 'Synthetic latest metadata');
    expect(saved.providerHeaders[xboardTlsMarker], 'required');
    expect(saved.isUpdating, isFalse);
  });

  test('changing the profile source during download rejects the stale result',
      () async {
    final original = _profile('existing');
    final harness = _Harness([original]);
    final started = Completer<void>();
    final release = Completer<void>();
    harness.downloader = (target) async {
      started.complete();
      await release.future;
      return _fetched(target);
    };
    final result = expectLater(
      harness.synchronizer.synchronize(_member, _subscription()),
      throwsA(isA<FormatException>()),
    );
    await started.future;
    final edited = original.copyWith(
      url: 'https://different.example.test/subscription',
    );
    harness.profiles[0] = edited;
    release.complete();
    await result;

    expect(harness.saved, isEmpty);
    expect(harness.profiles, [edited]);
  });
}

Profile _fetched(Profile target) => target.copyWith(
      lastUpdateDate: _downloadDate,
      subscriptionInfo: const SubscriptionInfo(total: 123456),
      providerHeaders: {'announce': 'Synthetic latest metadata'},
      isUpdating: true,
    );

class _Harness {
  _Harness([List<Profile> initial = const []]) : profiles = List.of(initial) {
    synchronizer = PurchaseProfileSynchronizer(
      origin: Uri.parse('https://panel.example.test'),
      storage: storage,
      readProfiles: () => List.of(profiles),
      download: (target) async {
        downloads.add(target);
        return downloader(target);
      },
      save: (updated) async {
        saved.add(updated);
        final index =
            profiles.indexWhere((profile) => profile.id == updated.id);
        if (index == -1) {
          profiles.add(updated);
        } else {
          profiles[index] = updated;
        }
      },
    );
  }

  final List<Profile> profiles;
  final List<Profile> downloads = [];
  final List<Profile> saved = [];
  final _Storage storage = _Storage();
  late final PurchaseProfileSynchronizer synchronizer;
  Future<Profile> Function(Profile) downloader =
      (target) async => _fetched(target);
}

class _Storage implements PurchaseStorage {
  final Map<int, String> profileIds = {};
  bool failRead = false;
  bool failWrite = false;
  int writeCalls = 0;

  @override
  Future<String?> readProfileId(int accountId) async {
    if (failRead) throw const FormatException('Synthetic secure read failure');
    return profileIds[accountId];
  }

  @override
  Future<void> saveProfileId(int accountId, String profileId) async {
    writeCalls++;
    if (failWrite) {
      throw const FormatException('Synthetic secure write failure');
    }
    profileIds[accountId] = profileId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
