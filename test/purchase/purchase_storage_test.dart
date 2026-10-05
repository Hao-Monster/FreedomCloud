import 'dart:convert';

import 'package:flclashx/services/purchase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _authorization = 'Bearer storage-account-fixture';
const _giftCode = 'CARD12345678';
const _pending = PendingGiftRedemption(
  code: _giftCode,
  type: 1,
  codeId: 43,
  previousUsageIds: [2, 5],
  baselineComplete: true,
);

Map<String, Object?> _pendingJson() => {
      'code': _giftCode,
      'type': 1,
      'code_id': 43,
      'previous_ids': [2, 5],
      'baseline_complete': true,
    };

/// Exercises the secure-storage boundary only; this is not an OS Keychain,
/// DPAPI or Android Keystore integration test.
class _SecureStorageFixture extends FlutterSecureStorage {
  final values = <String, String>{};
  final writes = <String>[];
  final deletions = <String>[];
  bool ignoreWrites = false;
  bool corruptWrites = false;
  bool ignoreDeletes = false;
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  String keyEnding(String suffix) =>
      values.keys.singleWhere((key) => key.endsWith(suffix));

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failReads) throw PlatformException(code: 'fixture_read_failed');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes.add(key);
    if (failWrites) throw PlatformException(code: 'fixture_write_failed');
    if (ignoreWrites) return;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = corruptWrites ? 'fixture-readback-mismatch' : value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletions.add(key);
    if (failDeletes) throw PlatformException(code: 'fixture_delete_failed');
    if (!ignoreDeletes) values.remove(key);
  }
}

void main() {
  late _SecureStorageFixture backend;
  late SecurePurchaseStorage storage;

  setUp(() {
    backend = _SecureStorageFixture();
    storage = SecurePurchaseStorage(
      Uri.parse('https://panel.test.invalid:8443'),
      storage: backend,
    );
  });

  test('missing secure values return null without creating placeholders',
      () async {
    expect(await storage.readSession(), isNull);
    expect(await storage.readPending(1), isNull);
    expect(await storage.readProfileId(1), isNull);
    expect(backend.values, isEmpty);
    expect(backend.writes, isEmpty);
  });

  test('session, pending recovery and profile association round trip',
      () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    await storage.saveProfileId(1, 'profile-for-account-1');

    final session = await storage.readSession();
    final pending = await storage.readPending(1);
    expect(session!.accountId, 1);
    expect(session.authorization, _authorization);
    expect(pending!.code, _giftCode);
    expect(pending.type, 1);
    expect(pending.codeId, 43);
    expect(pending.previousUsageIds, [2, 5]);
    expect(pending.baselineComplete, isTrue);
    expect(await storage.readProfileId(1), 'profile-for-account-1');

    final restored = SecurePurchaseStorage(
      Uri.parse('https://panel.test.invalid:8443'),
      storage: backend,
    );
    expect((await restored.readSession())!.authorization, _authorization);
    expect((await restored.readPending(1))!.codeId, 43);
    expect(await restored.readProfileId(1), 'profile-for-account-1');
  });

  test('old servers with unknown code identity round trip without inventing ID',
      () async {
    const pending = PendingGiftRedemption(
      code: _giftCode,
      type: 3,
      codeId: null,
      previousUsageIds: [],
      baselineComplete: false,
    );
    await storage.savePending(1, pending);
    final restored = await storage.readPending(1);
    expect(restored!.codeId, isNull);
    expect(restored.baselineComplete, isFalse);
    expect(restored.previousUsageIds, isEmpty);
  });

  test('host, scheme and port are isolated secure-storage origins', () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    await storage.saveProfileId(1, 'original-profile');

    for (final origin in [
      'https://other.test.invalid:8443',
      'https://panel.test.invalid:443',
      'http://panel.test.invalid:8443',
    ]) {
      final other = SecurePurchaseStorage(Uri.parse(origin), storage: backend);
      expect(await other.readSession(), isNull);
      expect(await other.readPending(1), isNull);
      expect(await other.readProfileId(1), isNull);
      await other.saveSession(const PurchaseSession(2, 'Bearer other-fixture'));
      await other.saveProfileId(1, 'other-profile');
      await other.clearSession();
      expect((await storage.readSession())!.authorization, _authorization);
      expect((await storage.readPending(1))!.code, _giftCode);
      expect(await storage.readProfileId(1), 'original-profile');
    }
  });

  test('pending records and profile mappings remain scoped to their account',
      () async {
    await storage.savePending(1, _pending);
    await storage.saveProfileId(1, 'profile-one');
    expect(await storage.readPending(2), isNull);
    expect(await storage.readProfileId(2), isNull);
    await storage.savePending(
      2,
      const PendingGiftRedemption(
        code: 'OTHER1234567',
        type: 4,
        codeId: 99,
        previousUsageIds: [],
        baselineComplete: true,
      ),
    );
    await storage.saveProfileId(2, 'profile-two');
    await storage.clearPending(2);
    expect((await storage.readPending(1))!.codeId, 43);
    expect(await storage.readPending(2), isNull);
    expect(await storage.readProfileId(1), 'profile-one');
    expect(await storage.readProfileId(2), 'profile-two');
  });

  test('logout erases the login while preserving account recovery and profiles',
      () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    await storage.saveProfileId(1, 'profile-one');
    await storage.clearSession();
    expect(await storage.readSession(), isNull);
    expect((await storage.readPending(1))!.previousUsageIds, [2, 5]);
    expect(await storage.readProfileId(1), 'profile-one');
    expect(backend.deletions, hasLength(1));
    expect(backend.deletions.single, endsWith('.session'));

    await storage
        .saveSession(const PurchaseSession(2, 'Bearer second-fixture'));
    expect((await storage.readSession())!.accountId, 2);
    expect(await storage.readPending(2), isNull);
    expect((await storage.readPending(1))!.code, _giftCode);
  });

  test('complete gift codes exist only in the secure pending value, never keys',
      () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    await storage.saveProfileId(1, 'profile-one');

    expect(backend.writes, hasLength(3));
    for (final key in backend.writes) {
      expect(
        key,
        matches(RegExp(
            r'^flclashx\.xboard\.[a-f0-9]{64}\.(session|pending\.1|profile\.1)$')),
      );
      expect(key, isNot(contains(_giftCode)));
      expect(key, isNot(contains(_authorization)));
      expect(key, isNot(contains('panel.test.invalid')));
    }
    final codeEntries = backend.values.entries
        .where((entry) => entry.value.contains(_giftCode))
        .toList();
    expect(codeEntries, hasLength(1));
    expect(codeEntries.single.key, endsWith('.pending.1'));
    expect(jsonDecode(codeEntries.single.value)['code'], _giftCode);
    final authEntries = backend.values.entries
        .where((entry) => entry.value.contains(_authorization))
        .toList();
    expect(authEntries, hasLength(1));
    expect(authEntries.single.key, endsWith('.session'));
  });

  test('malformed JSON cannot be mistaken for no saved session or pending work',
      () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    backend.values[backend.keyEnding('.session')] = '{invalid';
    backend.values[backend.keyEnding('.pending.1')] = '{invalid';
    await expectLater(storage.readSession(), throwsFormatException);
    await expectLater(storage.readPending(1), throwsFormatException);
  });

  test('corrupt session structure or identity is rejected', () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    final key = backend.keyEnding('.session');
    for (final value in [
      null,
      <Object?>[],
      <String, Object?>{},
      {'account_id': 0, 'authorization': _authorization},
      {'account_id': -2, 'authorization': _authorization},
      {'account_id': '1', 'authorization': _authorization},
      {'account_id': 1, 'authorization': 123},
      {'account_id': 1, 'authorization': 'subscription-token'},
    ]) {
      backend.values[key] = jsonEncode(value);
      await expectLater(storage.readSession(), throwsFormatException);
    }
  });

  test('empty or header-injecting saved Bearer values are rejected', () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    final key = backend.keyEnding('.session');
    for (final authorization in [
      'Bearer ',
      'Bearer  ',
      'Bearer token\r\nInjected: header',
      'Bearer token with spaces',
    ]) {
      backend.values[key] = jsonEncode({
        'account_id': 1,
        'authorization': authorization,
      });
      await expectLater(storage.readSession(), throwsFormatException);
    }
  });

  test('corrupt pending card, type, identity and usage baseline are rejected',
      () async {
    await storage.savePending(1, _pending);
    final key = backend.keyEnding('.pending.1');
    for (final value in [
      null,
      <Object?>[],
      <String, Object?>{},
      {..._pendingJson(), 'code': 'short'},
      {..._pendingJson(), 'code': 'CODE 12345678'},
      {..._pendingJson(), 'code': 'x' * 33},
      {..._pendingJson(), 'type': 0},
      {..._pendingJson(), 'type': 5},
      {..._pendingJson(), 'type': '1'},
      {..._pendingJson(), 'code_id': '43'},
      {..._pendingJson(), 'previous_ids': null},
      {
        ..._pendingJson(),
        'previous_ids': [1, '2']
      },
      {
        ..._pendingJson(),
        'previous_ids': [0]
      },
      {
        ..._pendingJson(),
        'previous_ids': [-1]
      },
      {..._pendingJson(), 'baseline_complete': 'true'},
    ]) {
      backend.values[key] = jsonEncode(value);
      await expectLater(storage.readPending(1), throwsFormatException);
    }
  });

  test('a persisted card identity must be positive or explicitly unknown',
      () async {
    await storage.savePending(1, _pending);
    final key = backend.keyEnding('.pending.1');
    for (final id in [0, -43]) {
      backend.values[key] = jsonEncode({..._pendingJson(), 'code_id': id});
      await expectLater(storage.readPending(1), throwsFormatException);
    }
  });

  test('missing and mismatched write readbacks reject every durable write',
      () async {
    for (final corrupt in [false, true]) {
      backend
        ..ignoreWrites = !corrupt
        ..corruptWrites = corrupt;
      await expectLater(
        storage.saveSession(const PurchaseSession(1, _authorization)),
        throwsFormatException,
      );
      await expectLater(
          storage.savePending(1, _pending), throwsFormatException);
      await expectLater(
          storage.saveProfileId(1, 'profile-one'), throwsFormatException);
    }
  });

  test('delete readback rejects an acknowledgement that leaves secrets present',
      () async {
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    backend.ignoreDeletes = true;
    await expectLater(storage.clearSession(), throwsFormatException);
    await expectLater(storage.clearPending(1), throwsFormatException);
    expect((await storage.readSession())!.authorization, _authorization);
    expect((await storage.readPending(1))!.code, _giftCode);
  });

  test(
      'platform read failures propagate instead of returning empty credentials',
      () async {
    backend.failReads = true;
    await expectLater(storage.readSession(), throwsA(isA<PlatformException>()));
    await expectLater(
        storage.readPending(1), throwsA(isA<PlatformException>()));
    await expectLater(
        storage.readProfileId(1), throwsA(isA<PlatformException>()));
    await expectLater(
      storage.saveSession(const PurchaseSession(1, _authorization)),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
        storage.clearSession(), throwsA(isA<PlatformException>()));
  });

  test(
      'platform write and delete failures cannot be reported as durable success',
      () async {
    backend.failWrites = true;
    await expectLater(
      storage.saveSession(const PurchaseSession(1, _authorization)),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
        storage.savePending(1, _pending), throwsA(isA<PlatformException>()));
    await expectLater(storage.saveProfileId(1, 'profile-one'),
        throwsA(isA<PlatformException>()));
    expect(backend.values, isEmpty);

    backend.failWrites = false;
    await storage.saveSession(const PurchaseSession(1, _authorization));
    await storage.savePending(1, _pending);
    backend.failDeletes = true;
    await expectLater(
        storage.clearSession(), throwsA(isA<PlatformException>()));
    await expectLater(
        storage.clearPending(1), throwsA(isA<PlatformException>()));
    expect((await storage.readSession())!.authorization, _authorization);
    expect((await storage.readPending(1))!.codeId, 43);
  });
}
