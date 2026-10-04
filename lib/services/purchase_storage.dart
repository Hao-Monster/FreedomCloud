import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PurchaseSession {
  const PurchaseSession(this.accountId, this.authorization);

  final int accountId;
  final String authorization;
}

/// Persisted before sending a redemption, so a restart cannot turn a timeout
/// into an invitation to spend a reusable card a second time.
class PendingGiftRedemption {
  const PendingGiftRedemption({
    required this.code,
    required this.type,
    required this.codeId,
    required this.previousUsageIds,
    required this.baselineComplete,
  });

  final String code;
  final int type;
  final int? codeId;
  final List<int> previousUsageIds;
  final bool baselineComplete;
}

abstract class PurchaseStorage {
  Future<PurchaseSession?> readSession();
  Future<void> saveSession(PurchaseSession session);
  Future<void> clearSession();
  Future<PendingGiftRedemption?> readPending(int accountId);
  Future<void> savePending(int accountId, PendingGiftRedemption pending);
  Future<void> clearPending(int accountId);
  Future<String?> readProfileId(int accountId);
  Future<void> saveProfileId(int accountId, String profileId);
}

class SecurePurchaseStorage implements PurchaseStorage {
  SecurePurchaseStorage(Uri origin, {FlutterSecureStorage? storage})
      : _prefix =
            'flclashx.xboard.${sha256.convert(utf8.encode(origin.origin))}',
        _storage = storage ??
            const FlutterSecureStorage(
              // This app does not share credentials with other macOS apps.
              // The login Keychain avoids requiring a distribution profile.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  final FlutterSecureStorage _storage;
  final String _prefix;

  Future<void> _write(String suffix, String value) async {
    final key = '$_prefix.$suffix';
    await _storage.write(key: key, value: value);
    if (await _storage.read(key: key) != value) {
      throw const FormatException('Secure storage did not retain the value');
    }
  }

  Future<void> _delete(String suffix) async {
    final key = '$_prefix.$suffix';
    await _storage.delete(key: key);
    if (await _storage.read(key: key) != null) {
      throw const FormatException('Secure storage did not remove the value');
    }
  }

  @override
  Future<PurchaseSession?> readSession() async {
    final value = await _storage.read(key: '$_prefix.session');
    if (value == null) return null;
    final data = jsonDecode(value);
    if (data is! Map<String, dynamic> ||
        data['account_id'] is! int ||
        (data['account_id'] as int) <= 0 ||
        data['authorization'] is! String ||
        !RegExp(r'^Bearer [A-Za-z0-9_-]+$')
            .hasMatch(data['authorization'] as String)) {
      throw const FormatException('Invalid stored account session');
    }
    return PurchaseSession(
        data['account_id'] as int, data['authorization'] as String);
  }

  @override
  Future<void> saveSession(PurchaseSession session) => _write(
        'session',
        jsonEncode({
          'account_id': session.accountId,
          'authorization': session.authorization
        }),
      );

  @override
  Future<void> clearSession() => _delete('session');

  @override
  Future<PendingGiftRedemption?> readPending(int accountId) async {
    final value = await _storage.read(key: '$_prefix.pending.$accountId');
    if (value == null) return null;
    final data = jsonDecode(value);
    if (data is! Map<String, dynamic> ||
        data['code'] is! String ||
        !RegExp(r'^[A-Z0-9]{8,32}$').hasMatch(data['code'] as String) ||
        data['type'] is! int ||
        (data['type'] as int) < 1 ||
        (data['type'] as int) > 4 ||
        (data['code_id'] != null &&
            (data['code_id'] is! int || (data['code_id'] as int) <= 0)) ||
        data['previous_ids'] is! List ||
        !(data['previous_ids'] as List)
            .every((value) => value is int && value > 0) ||
        data['baseline_complete'] is! bool) {
      throw const FormatException('Invalid pending redemption');
    }
    return PendingGiftRedemption(
      code: data['code'] as String,
      type: data['type'] as int,
      codeId: data['code_id'] as int?,
      previousUsageIds: List<int>.from(data['previous_ids'] as List),
      baselineComplete: data['baseline_complete'] as bool,
    );
  }

  @override
  Future<void> savePending(int accountId, PendingGiftRedemption pending) =>
      _write(
        'pending.$accountId',
        jsonEncode({
          'code': pending.code,
          'type': pending.type,
          'code_id': pending.codeId,
          'previous_ids': pending.previousUsageIds,
          'baseline_complete': pending.baselineComplete,
        }),
      );

  @override
  Future<void> clearPending(int accountId) => _delete('pending.$accountId');

  @override
  Future<String?> readProfileId(int accountId) =>
      _storage.read(key: '$_prefix.profile.$accountId');

  @override
  Future<void> saveProfileId(int accountId, String profileId) =>
      _write('profile.$accountId', profileId);
}
