import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/services/xboard_bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted Chatwoot widget session scoped to a specific origin, website
/// token, and account scope (`'guest'` or `'account:<id>'`).
@immutable
class ChatwootSession {
  const ChatwootSession({
    required this.authToken,
    this.pubsubToken,
    this.contactId,
    required this.scopeKey,
    this.boundEmail,
  });

  final String authToken;
  final String? pubsubToken;
  final int? contactId;
  final String scopeKey;
  final String? boundEmail;

  static ChatwootSession? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final authToken = raw['auth_token'];
    final scopeKey = raw['scope_key'];
    final pubsubToken = raw['pubsub_token'];
    final contactId = raw['contact_id'];
    final boundEmail = raw['bound_email'];
    if (authToken is! String || authToken.trim().isEmpty) return null;
    if (scopeKey is! String || scopeKey.trim().isEmpty) return null;
    if (pubsubToken != null && pubsubToken is! String) return null;
    if (contactId != null && contactId is! int) return null;
    if (boundEmail != null && boundEmail is! String) return null;
    return ChatwootSession(
      authToken: authToken,
      pubsubToken: pubsubToken as String?,
      contactId: contactId as int?,
      scopeKey: scopeKey,
      boundEmail: boundEmail as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'auth_token': authToken,
        'pubsub_token': pubsubToken,
        'contact_id': contactId,
        'scope_key': scopeKey,
        'bound_email': boundEmail,
      };

  ChatwootSession copyWith({
    String? authToken,
    String? pubsubToken,
    int? contactId,
    String? scopeKey,
    String? boundEmail,
  }) =>
      ChatwootSession(
        authToken: authToken ?? this.authToken,
        pubsubToken: pubsubToken ?? this.pubsubToken,
        contactId: contactId ?? this.contactId,
        scopeKey: scopeKey ?? this.scopeKey,
        boundEmail: boundEmail ?? this.boundEmail,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatwootSession &&
          other.authToken == authToken &&
          other.pubsubToken == pubsubToken &&
          other.contactId == contactId &&
          other.scopeKey == scopeKey &&
          other.boundEmail == boundEmail;

  @override
  int get hashCode =>
      Object.hash(authToken, pubsubToken, contactId, scopeKey, boundEmail);

  @override
  String toString() =>
      'ChatwootSession(scopeKey: $scopeKey, contactId: $contactId)';
}

/// Abstract persistence contract for isolated per-account Chatwoot sessions.
abstract interface class ChatwootSessionStorage {
  Future<ChatwootSession?> readSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  });

  Future<void> saveSession({
    required Uri baseUrl,
    required String websiteToken,
    required ChatwootSession session,
  });

  Future<void> clearSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  });
}

/// Secure storage implementation isolating guest and account Chatwoot sessions
/// behind SHA-256 derived keys.
class SecureChatwootSessionStorage implements ChatwootSessionStorage {
  SecureChatwootSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Keep parity with SecurePurchaseStorage on macOS without requiring
              // a data-protection keychain entitlement.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  final FlutterSecureStorage _storage;

  static Uri _canonicalStorageBaseUrl(Uri baseUrl) {
    final valid = validateChatwootBaseUrl(baseUrl);
    final canonical = canonicalizeTenantOrigin(Uri.parse(valid.origin));
    if (canonical.origin == valid.origin) return valid;
    return canonical.replace(
      path: valid.path.isEmpty || valid.path == '/' ? null : valid.path,
    );
  }

  /// Computes the isolated storage key for a normalized base URL, website
  /// token, and scope. Tenant bootstrap origins collapse onto the Canonical
  /// Tenant Namespace so saved sessions survive mirror rotation.
  @visibleForTesting
  static String storageKeyFor({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) {
    final normalizedBaseUrl = _canonicalStorageBaseUrl(baseUrl).toString();
    final trimmedToken = websiteToken.trim();
    final trimmedScope = scopeKey.trim();
    if (trimmedToken.isEmpty || trimmedScope.isEmpty) {
      throw ArgumentError('websiteToken and scopeKey must not be empty');
    }
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode([normalizedBaseUrl, trimmedToken, trimmedScope]),
          ),
        )
        .toString();
    return 'chatwoot_session_v2_$digest';
  }

  static String? _legacyStorageKeyFor({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) {
    final valid = _canonicalStorageBaseUrl(baseUrl);
    if (valid.toString() != valid.origin) return null;
    final trimmedToken = websiteToken.trim();
    final trimmedScope = scopeKey.trim();
    if (trimmedToken.isEmpty || trimmedScope.isEmpty) return null;
    final digest = sha256
        .convert(utf8.encode('${valid.origin}|$trimmedToken|$trimmedScope'))
        .toString();
    return 'chatwoot_session_v1_$digest';
  }

  @override
  Future<ChatwootSession?> readSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async {
    final key = storageKeyFor(
      baseUrl: baseUrl,
      websiteToken: websiteToken,
      scopeKey: scopeKey,
    );
    var raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      final legacyKey = _legacyStorageKeyFor(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: scopeKey,
      );
      if (legacyKey != null) {
        raw = await _storage.read(key: legacyKey);
      }
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final session = ChatwootSession.tryFromJson(decoded);
      if (session == null || session.scopeKey != scopeKey.trim()) {
        return null;
      }
      return session;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveSession({
    required Uri baseUrl,
    required String websiteToken,
    required ChatwootSession session,
  }) async {
    if (session.authToken.trim().isEmpty) {
      throw ArgumentError.value(
        session.authToken,
        'session.authToken',
        'Cannot persist an empty Chatwoot authToken',
      );
    }
    final key = storageKeyFor(
      baseUrl: baseUrl,
      websiteToken: websiteToken,
      scopeKey: session.scopeKey,
    );
    final encoded = jsonEncode(session.toJson());
    await _storage.write(key: key, value: encoded);
    if (await _storage.read(key: key) != encoded) {
      throw const FormatException('Secure storage did not retain Chatwoot session');
    }
  }

  @override
  Future<void> clearSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async {
    final key = storageKeyFor(
      baseUrl: baseUrl,
      websiteToken: websiteToken,
      scopeKey: scopeKey,
    );
    await _storage.delete(key: key);
    if (await _storage.read(key: key) != null) {
      throw const FormatException('Secure storage did not remove Chatwoot session');
    }
    final legacyKey = _legacyStorageKeyFor(
      baseUrl: baseUrl,
      websiteToken: websiteToken,
      scopeKey: scopeKey,
    );
    if (legacyKey != null) {
      await _storage.delete(key: legacyKey);
    }
  }
}
