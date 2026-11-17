import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flclashx/common/ed25519_verify.dart';

/// Canonical tenant identifier verified in FreedomNet signed bootstrap manifests.
const String fnTenantId = 'freedomnet-prod';

/// Fixed Canonical Tenant Namespace used to key local credentials, Chatwoot
/// sessions, pending gift-card baselines, and `xboardAccountMarker` across mirrors.
const String fnCanonicalTenantOrigin = 'https://fast.hjy.ca:8443';

/// Seed primary origin fronted by CDN for Mainland China access.
const String fnPrimaryBootstrapOrigin = 'https://api.westernmoviefans.com';

/// Dedicated subscription origin fronted by CDN for Mainland China access.
const String fnSubscriptionOrigin = 'https://sub.westernmoviefans.com';

/// Default Stage-1 seed origins in priority order.
const List<String> fnBootstrapSeedOrigins = <String>[
  fnPrimaryBootstrapOrigin,
  fnCanonicalTenantOrigin,
];

final Set<String> _globalFreedomNetOriginRegistry = <String>{
  fnPrimaryBootstrapOrigin,
  fnCanonicalTenantOrigin,
  fnSubscriptionOrigin,
};

/// Returns true when [candidate] is a strict HTTPS FreedomNet official origin
/// authorized for [capability]. Dedicated subscription mirrors such as
/// [fnSubscriptionOrigin] are restricted to `sub` traffic.
bool isOfficialFreedomNetOrigin(
  Uri candidate, {
  String? capability,
}) {
  if (candidate.scheme != 'https' ||
      candidate.host.isEmpty ||
      candidate.userInfo.isNotEmpty) {
    return false;
  }
  final origin = candidate.origin;
  if (origin == fnSubscriptionOrigin) {
    return capability == 'sub';
  }
  return _globalFreedomNetOriginRegistry.contains(origin);
}

/// Normalizes [origin] to its canonical HTTPS namespace. All known/verified
/// FreedomNet tenant origins collapse onto [fnCanonicalTenantOrigin] so
/// credentials, sessions, and profile markers remain continuous across mirrors,
/// while arbitrary third-party or test origins remain isolated.
Uri canonicalizeTenantOrigin(
  Uri origin, {
  Iterable<Uri>? extraTenantOrigins,
}) {
  if (origin.scheme != 'https' || origin.host.isEmpty) {
    return origin;
  }
  final normalized = Uri.parse(origin.origin);
  if (_globalFreedomNetOriginRegistry.contains(normalized.origin)) {
    return Uri.parse(fnCanonicalTenantOrigin);
  }
  if (extraTenantOrigins != null) {
    for (final candidate in extraTenantOrigins) {
      if (candidate.scheme == 'https' &&
          candidate.host.isNotEmpty &&
          candidate.origin == normalized.origin) {
        return Uri.parse(fnCanonicalTenantOrigin);
      }
    }
  }
  return normalized;
}

/// Validates and strips an origin candidate down to clean `https://host[:port]`.
Uri? tryNormalizeHttpsOrigin(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  return Uri.parse(uri.origin);
}

/// One validated origin entry from a signed client bootstrap manifest.
class BootstrapOrigin {
  const BootstrapOrigin({
    required this.origin,
    required this.priority,
    required this.role,
    required this.capabilities,
  });

  final Uri origin;
  final int priority;
  final String role;
  final Set<String> capabilities;

  bool supportsCapability(String? capability) =>
      capability == null ||
      capabilities.isEmpty ||
      capabilities.contains(capability);
}

/// Verified Ed25519 client bootstrap configuration (`schema_version == 1`).
class VerifiedBootstrapConfig {
  const VerifiedBootstrapConfig({
    required this.schemaVersion,
    required this.tenantId,
    required this.keyId,
    required this.issuedAt,
    required this.expiresAt,
    required this.origins,
  });

  final int schemaVersion;
  final String tenantId;
  final String keyId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final List<BootstrapOrigin> origins;

  /// Parses the compiled Stage-1 embedded bootstrap manifest.
  static VerifiedBootstrapConfig? tryParseFromEmbedded({DateTime? now}) {
    try {
      final raw = jsonDecode(fnDefaultSignedBootstrapJson);
      return tryParseAndVerify(raw, now: now);
    } catch (_) {
      return null;
    }
  }

  /// Verifies and parses [rawJson] as a signed client bootstrap envelope.
  /// Returns `null` when signature verification, expiry, tenant identity, or
  /// origin validation fails.
  static VerifiedBootstrapConfig? tryParseAndVerify(
    Object? rawJson, {
    String expectedTenantId = fnTenantId,
    Map<String, Uint8List>? trustedKeys,
    DateTime? now,
  }) {
    if (rawJson is! Map) return null;
    final envelope = Map<String, dynamic>.from(rawJson);
    if (!verifySignedJsonEnvelope(
      envelope,
      trustedKeys: trustedKeys,
      now: now,
      checkExpiry: true,
    )) {
      return null;
    }

    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    if (payload['schema_version'] != 1) return null;
    if (payload['tenant_id'] != expectedTenantId) return null;

    final keyId = payload['key_id'];
    final issuedRaw = payload['issued_at'];
    final expiresRaw = payload['expires_at'];
    if (keyId is! String ||
        issuedRaw is! String ||
        expiresRaw is! String) {
      return null;
    }
    final issuedAt = DateTime.tryParse(issuedRaw)?.toUtc();
    final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
    if (issuedAt == null || expiresAt == null) return null;

    final originsRaw = payload['origins'];
    if (originsRaw is! List) return null;

    final seen = <String>{};
    final parsedOrigins = <BootstrapOrigin>[];
    for (final item in originsRaw) {
      if (item is! Map) continue;
      final rawOrigin = item['origin'];
      final priority = item['priority'];
      final role = item['role'];
      final capsRaw = item['capabilities'];
      if (rawOrigin is! String || priority is! int || role is! String) {
        continue;
      }
      final uri = tryNormalizeHttpsOrigin(rawOrigin);
      if (uri == null || !seen.add(uri.origin)) continue;

      final caps = <String>{};
      if (capsRaw is List) {
        for (final c in capsRaw) {
          if (c is String && c.trim().isNotEmpty) {
            caps.add(c.trim());
          }
        }
      }
      parsedOrigins.add(
        BootstrapOrigin(
          origin: uri,
          priority: priority,
          role: role.trim(),
          capabilities: Set<String>.unmodifiable(caps),
        ),
      );
    }

    if (parsedOrigins.isEmpty) return null;
    parsedOrigins.sort((a, b) => a.priority.compareTo(b.priority));

    if (trustedKeys == null && expectedTenantId == fnTenantId) {
      for (final entry in parsedOrigins) {
        _globalFreedomNetOriginRegistry.add(entry.origin.origin);
      }
    }

    return VerifiedBootstrapConfig(
      schemaVersion: 1,
      tenantId: expectedTenantId,
      keyId: keyId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      origins: List<BootstrapOrigin>.unmodifiable(parsedOrigins),
    );
  }
}

/// Manages candidate HTTPS origins for FreedomNet with Ed25519-verified
/// bootstrap updates, health tracking, single-origin locking for mutations,
/// and staggered hedged racing for idempotent operations.
class TransportMirrorPool {
  TransportMirrorPool({
    List<Uri>? seedOrigins,
    Uri? canonicalOrigin,
    this.expectedTenantId = fnTenantId,
    this.trustedKeys,
    DateTime Function()? clock,
    this.unhealthyCooldown = const Duration(minutes: 2),
  })  : canonicalOrigin = canonicalOrigin ?? Uri.parse(fnCanonicalTenantOrigin),
        _clock = clock ?? (() => DateTime.now().toUtc()) {
    final seeds = seedOrigins ??
        fnBootstrapSeedOrigins.map(Uri.parse).toList(growable: false);
    final dedup = <String>{};
    for (var i = 0; i < seeds.length; i++) {
      final norm = tryNormalizeHttpsOrigin(seeds[i].toString());
      if (norm == null || !dedup.add(norm.origin)) continue;
      _entries.add(
        BootstrapOrigin(
          origin: norm,
          priority: (i + 1) * 10,
          role: i == 0 ? 'primary' : 'direct',
          capabilities: const {'api', 'sub', 'update', 'geox'},
        ),
      );
    }
    if (_entries.isEmpty) {
      throw ArgumentError('TransportMirrorPool requires at least one HTTPS origin');
    }
  }

  /// Creates a pool seeded with the embedded Stage-1 signed bootstrap contract.
  factory TransportMirrorPool.defaultTenant({
    DateTime Function()? clock,
    Duration unhealthyCooldown = const Duration(minutes: 2),
  }) {
    final pool = TransportMirrorPool(
      seedOrigins: fnBootstrapSeedOrigins.map(Uri.parse).toList(growable: false),
      canonicalOrigin: Uri.parse(fnCanonicalTenantOrigin),
      expectedTenantId: fnTenantId,
      clock: clock,
      unhealthyCooldown: unhealthyCooldown,
    );
    final embedded = VerifiedBootstrapConfig.tryParseFromEmbedded(
      now: (clock ?? (() => DateTime.now().toUtc()))(),
    );
    if (embedded != null) {
      pool._applyVerified(embedded);
    }
    return pool;
  }

  /// Shared tenant mirror pool used across subscription/client transports.
  static final TransportMirrorPool shared = TransportMirrorPool.defaultTenant();

  final Uri canonicalOrigin;
  final String expectedTenantId;
  final Map<String, Uint8List>? trustedKeys;
  final Duration unhealthyCooldown;
  final DateTime Function() _clock;

  final List<BootstrapOrigin> _entries = <BootstrapOrigin>[];
  final Map<String, DateTime> _unhealthyUntil = <String, DateTime>{};
  Uri? _activeOrigin;
  VerifiedBootstrapConfig? _lastVerifiedConfig;

  VerifiedBootstrapConfig? get lastVerifiedConfig => _lastVerifiedConfig;

  bool _isCooldownActive(Uri origin, DateTime now) {
    final until = _unhealthyUntil[origin.origin];
    if (until == null) return false;
    if (!now.isBefore(until)) {
      _unhealthyUntil.remove(origin.origin);
      return false;
    }
    return true;
  }

  /// Returns candidate origins ordered with healthy entries first (preferring
  /// the sticky proven-healthy origin when present), followed by any cooled-down
  /// origins in priority order so callers can still fall back cleanly.
  List<Uri> orderedOrigins({String? capability}) {
    final now = _clock();
    final matching = _entries
        .where((e) => e.supportsCapability(capability))
        .toList(growable: false);
    final pool = matching.isEmpty ? _entries : matching;

    final healthy = <BootstrapOrigin>[];
    final unhealthy = <BootstrapOrigin>[];
    for (final entry in pool) {
      if (_isCooldownActive(entry.origin, now)) {
        unhealthy.add(entry);
      } else {
        healthy.add(entry);
      }
    }

    final sticky = _activeOrigin;
    if (sticky != null) {
      final stickyIndex =
          healthy.indexWhere((e) => e.origin.origin == sticky.origin);
      if (stickyIndex > 0) {
        final picked = healthy.removeAt(stickyIndex);
        healthy.insert(0, picked);
      }
    }

    return List<Uri>.unmodifiable([
      ...healthy.map((e) => e.origin),
      ...unhealthy.map((e) => e.origin),
    ]);
  }

  /// Selects a single healthy origin for non-idempotent mutations (`login`,
  /// `register`, `redeem`, `logout`). Never switches mid-operation.
  Uri selectOriginForMutation({String? capability}) =>
      orderedOrigins(capability: capability).first;

  void markSuccess(Uri origin) {
    final norm = tryNormalizeHttpsOrigin(origin.toString());
    if (norm == null) return;
    _unhealthyUntil.remove(norm.origin);
    _activeOrigin = norm;
  }

  void markFailure(Uri origin) {
    final norm = tryNormalizeHttpsOrigin(origin.toString());
    if (norm == null) return;
    _unhealthyUntil[norm.origin] = _clock().add(unhealthyCooldown);
    if (_activeOrigin?.origin == norm.origin) {
      _activeOrigin = null;
    }
  }

  /// Verifies [body] using Ed25519 signature + `tenant_id` + expiry and
  /// replaces candidate origins only when verification passes.
  VerifiedBootstrapConfig? applyBootstrapResponse(Object? body) {
    final parsed = VerifiedBootstrapConfig.tryParseAndVerify(
      body,
      expectedTenantId: expectedTenantId,
      trustedKeys: trustedKeys,
      now: _clock(),
    );
    if (parsed == null) return null;
    _applyVerified(parsed);
    return parsed;
  }

  void _applyVerified(VerifiedBootstrapConfig config) {
    _lastVerifiedConfig = config;
    _entries
      ..clear()
      ..addAll(config.origins);
    final validSet = config.origins.map((e) => e.origin.origin).toSet();
    _unhealthyUntil.removeWhere((key, _) => !validSet.contains(key));
    if (_activeOrigin != null && !validSet.contains(_activeOrigin!.origin)) {
      _activeOrigin = null;
    }
  }

  /// Returns true when [candidate] is a valid HTTPS URL belonging to the
  /// canonical namespace, official subscription edge, or active bootstrap origins.
  bool isKnownTenantOrigin(Uri candidate, {String? capability}) {
    if (candidate.scheme != 'https' ||
        candidate.host.isEmpty ||
        candidate.userInfo.isNotEmpty) {
      return false;
    }
    final origin = candidate.origin;
    if (origin == canonicalOrigin.origin) return true;
    if (expectedTenantId == fnTenantId &&
        origin == fnSubscriptionOrigin &&
        capability == 'sub') {
      return true;
    }
    for (final entry in _entries) {
      if (entry.origin.origin == origin && entry.supportsCapability(capability)) {
        return true;
      }
    }
    return false;
  }

  /// Resolves [targetUrl] against [mirrorOrigin] keeping path and query intact.
  Uri rewriteToOrigin(Uri targetUrl, Uri mirrorOrigin) => mirrorOrigin.replace(
        path: targetUrl.path.isEmpty ? null : targetUrl.path,
        query: targetUrl.hasQuery ? targetUrl.query : null,
        fragment: targetUrl.hasFragment ? targetUrl.fragment : null,
      );

  /// Executes an idempotent [request] across candidate origins using staggered
  /// hedging ([hedgeDelay] between launching subsequent healthy origins), cancelling
  /// all pending timers once the first origin completes successfully.
  Future<T> raceIdempotent<T>({
    required Future<T> Function(Uri origin) request,
    Duration hedgeDelay = const Duration(milliseconds: 800),
    String? capability,
    bool Function()? isCancelled,
    bool Function(Object error)? isRetryableFailure,
  }) async {
    final origins = orderedOrigins(capability: capability);
    if (origins.length == 1 || hedgeDelay <= Duration.zero) {
      Object? lastError;
      StackTrace? lastStack;
      for (var i = 0; i < origins.length; i++) {
        if (isCancelled?.call() ?? false) {
          throw StateError('Mirror request cancelled');
        }
        final origin = origins[i];
        try {
          final result = await request(origin);
          markSuccess(origin);
          return result;
        } catch (error, stack) {
          if (isRetryableFailure != null && !isRetryableFailure(error)) {
            rethrow;
          }
          markFailure(origin);
          lastError = error;
          lastStack = stack;
        }
      }
      if (lastError != null && lastStack != null) {
        Error.throwWithStackTrace(lastError, lastStack);
      }
      throw StateError('No mirrors available');
    }

    final completer = Completer<T>();
    final pendingTimers = Queue<Timer>();
    var activeCount = 0;
    var nextIndex = 0;
    Object? lastError;
    StackTrace? lastStack;

    void cancelTimers() {
      while (pendingTimers.isNotEmpty) {
        pendingTimers.removeFirst().cancel();
      }
    }

    late void Function() launchNext;

    void onOriginError(Uri origin, Object error, StackTrace stack) {
      activeCount--;
      if (completer.isCompleted) return;
      final retryable = isRetryableFailure?.call(error) ?? true;
      if (!retryable) {
        cancelTimers();
        completer.completeError(error, stack);
        return;
      }
      markFailure(origin);
      lastError = error;
      lastStack = stack;
      if (nextIndex < origins.length) {
        launchNext();
      } else if (activeCount == 0 && !completer.isCompleted) {
        cancelTimers();
        completer.completeError(lastError!, lastStack!);
      }
    }

    launchNext = () {
      if (completer.isCompleted || nextIndex >= origins.length) return;
      if (isCancelled?.call() ?? false) {
        cancelTimers();
        if (!completer.isCompleted) {
          completer.completeError(StateError('Mirror request cancelled'));
        }
        return;
      }
      final origin = origins[nextIndex++];
      activeCount++;

      Timer? hedgeTimer;
      if (nextIndex < origins.length) {
        hedgeTimer = Timer(hedgeDelay, () {
          if (!completer.isCompleted) {
            launchNext();
          }
        });
        pendingTimers.add(hedgeTimer);
      }

      unawaited(() async {
        try {
          final value = await request(origin);
          hedgeTimer?.cancel();
          if (!completer.isCompleted) {
            cancelTimers();
            markSuccess(origin);
            completer.complete(value);
          }
        } catch (error, stack) {
          hedgeTimer?.cancel();
          onOriginError(origin, error, stack);
        }
      }());
    };

    launchNext();
    return completer.future;
  }
}
