import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flclashx/services/xboard_bootstrap.dart';
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

/// Persists Xboard account sessions, pending gift-card redemptions, and
/// managed-profile associations in platform secure storage.
///
/// Storage isolation across co-installed FreedomNet and FlClashX:
/// - On Windows, `flutter_secure_storage_windows` derives its encrypted file
///   directory from Win32 `CompanyName`/`ProductName` (`Runner.rc`), isolating
///   FreedomNet (`%APPDATA%\FreedomNet\FreedomNet`) from FlClashX
///   (`%APPDATA%\com.follow\clashx`) at the filesystem boundary.
/// - On shared OS credential stores (such as macOS login Keychain, Windows
///   Credential Manager entries, or in-place migrated profiles), [_legacyPrefix]
///   (`flclashx.xboard.*`) is strictly **read-only** so FreedomNet never writes
///   or deletes FlClashX's own credentials.
/// - When a user explicitly logs out or clears state in FreedomNet while a
///   legacy `flclashx.xboard.*` entry exists, [_delete] records a
///   FreedomNet-scoped tombstone (`$_prefix.<suffix>.legacy_cleared = '1'`)
///   instead of deleting the legacy key, preventing zombie re-login on restart
///   without disturbing FlClashX.
class SecurePurchaseStorage implements PurchaseStorage {
  SecurePurchaseStorage(Uri origin, {FlutterSecureStorage? storage})
      : _canonicalOrigin = canonicalizeTenantOrigin(origin).origin,
        _prefix =
            'freedomnet.xboard.${sha256.convert(utf8.encode(canonicalizeTenantOrigin(origin).origin))}',
        _legacyPrefix =
            'flclashx.xboard.${sha256.convert(utf8.encode(canonicalizeTenantOrigin(origin).origin))}',
        _storage = storage ??
            const FlutterSecureStorage(
              // This app does not share credentials with other macOS apps.
              // The login Keychain avoids requiring a distribution profile.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  final FlutterSecureStorage _storage;
  final String _canonicalOrigin;
  final String _prefix;
  final String _legacyPrefix;

  String get canonicalOrigin => _canonicalOrigin;

  String _legacyClearedKey(String suffix) => '$_prefix.$suffix.legacy_cleared';

  Future<String?> _readWithLegacyFallback(String suffix) async {
    final primary = await _storage.read(key: '$_prefix.$suffix');
    if (primary != null) return primary;
    if (await _storage.read(key: _legacyClearedKey(suffix)) == '1') {
      return null;
    }
    return _storage.read(key: '$_legacyPrefix.$suffix');
  }

  Future<void> _write(String suffix, String value) async {
    final key = '$_prefix.$suffix';
    await _storage.write(key: key, value: value);
    if (await _storage.read(key: key) != value) {
      throw const FormatException('Secure storage did not retain the value');
    }
    final clearedKey = _legacyClearedKey(suffix);
    if (await _storage.read(key: clearedKey) != null) {
      await _storage.delete(key: clearedKey);
      if (await _storage.read(key: clearedKey) != null) {
        throw const FormatException('Secure storage did not remove the value');
      }
    }
  }

  Future<void> _delete(String suffix) async {
    final key = '$_prefix.$suffix';
    await _storage.delete(key: key);
    if (await _storage.read(key: key) != null) {
      throw const FormatException('Secure storage did not remove the value');
    }
    final clearedKey = _legacyClearedKey(suffix);
    if (await _storage.read(key: '$_legacyPrefix.$suffix') != null) {
      await _storage.write(key: clearedKey, value: '1');
      if (await _storage.read(key: clearedKey) != '1') {
        throw const FormatException('Secure storage did not retain the value');
      }
    } else if (await _storage.read(key: clearedKey) != null) {
      await _storage.delete(key: clearedKey);
      if (await _storage.read(key: clearedKey) != null) {
        throw const FormatException('Secure storage did not remove the value');
      }
    }
  }

  @override
  Future<PurchaseSession?> readSession() async {
    final value = await _readWithLegacyFallback('session');
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
    final value = await _readWithLegacyFallback('pending.$accountId');
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
      _readWithLegacyFallback('profile.$accountId');

  @override
  Future<void> saveProfileId(int accountId, String profileId) =>
      _write('profile.$accountId', profileId);
}
