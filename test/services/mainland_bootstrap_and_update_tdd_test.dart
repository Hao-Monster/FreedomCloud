import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/constant.dart';
import 'package:flclashx/common/ed25519_verify.dart';
import 'package:flclashx/common/network.dart';
import 'package:flclashx/common/request.dart';
import 'package:flclashx/common/rule_compiler.dart';
import 'package:flclashx/common/signed_update.dart';
import 'package:flclashx/common/signed_update_unix.dart';
import 'package:flclashx/common/signed_update_windows.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/clash_config.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flclashx/services/purchase_profile_sync.dart';
import 'package:flclashx/services/purchase_storage.dart';
import 'package:flclashx/services/secure_subscription.dart';
import 'package:flclashx/services/xboard_api.dart';
import 'package:flclashx/services/xboard_bootstrap.dart';
import 'package:flclashx/state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Uint8List _hexDecode(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s+'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

class _RecordingHeaders implements HttpHeaders {
  final Map<String, List<String>> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  List<String>? operator [](String name) => values[name.toLowerCase()];

  @override
  String? value(String name) => values[name.toLowerCase()]?.firstOrNull;

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach(action);

  @override
  set contentLength(int value) {}

  @override
  set chunkedTransferEncoding(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordedHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _RecordedHttpResponse({
    required this.statusCode,
    required List<int> bodyBytes,
    Map<String, String>? headersMap,
  }) : _bodyBytes = Uint8List.fromList(bodyBytes) {
    headersMap?.forEach(headers.set);
  }

  final Uint8List _bodyBytes;

  @override
  final int statusCode;

  @override
  final _RecordingHeaders headers = _RecordingHeaders();

  @override
  int get contentLength => _bodyBytes.length;

  @override
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  String get reasonPhrase => 'Status $statusCode';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get persistentConnection => true;

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(_bodyBytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordedHttpRequest implements HttpClientRequest {
  _RecordedHttpRequest(this.method, this.uri, this.responder);

  @override
  final String method;
  @override
  final Uri uri;
  final Future<HttpClientResponse> Function() responder;

  @override
  final _RecordingHeaders headers = _RecordingHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  int contentLength = -1;
  @override
  bool bufferOutput = true;
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() => responder();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeNetworkHttpClient implements HttpClient {
  _FakeNetworkHttpClient(this.handler, {this.onOpenUrl});

  final Future<HttpClientResponse> Function(String method, Uri url,
      _FakeNetworkHttpClient client, _RecordedHttpRequest request) handler;
  final FutureOr<void> Function(String method, Uri url)? onOpenUrl;

  final List<Uri> requestedUrls = [];
  bool Function(X509Certificate, String, int)? capturedBadCertCallback;
  String Function(Uri)? capturedFindProxy;
  bool? lastFollowRedirects;

  @override
  Duration? connectionTimeout;
  @override
  bool autoUncompress = true;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate, String, int)? callback) =>
      capturedBadCertCallback = callback;

  @override
  set findProxy(String Function(Uri url)? f) => capturedFindProxy = f;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requestedUrls.add(url);
    await onOpenUrl?.call(method, url);
    late final _RecordedHttpRequest req;
    req = _RecordedHttpRequest(method, url, () {
      lastFollowRedirects = req.followRedirects;
      return handler(method, url, this, req);
    });
    return req;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DummyCert implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('unused');
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

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
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
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
    values.remove(key);
  }
}

void main() {
  group('1. Pure-Dart RFC 8032 Ed25519 Verifier', () {
    test('verifies RFC 8032 vectors 1, 2, 3 and rejects tampered inputs', () {
      // RFC 8032 Section 7.1 TEST 1 (empty message)
      final pk1 = _hexDecode(
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      );
      final sig1 = _hexDecode(
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );
      expect(
        ed25519Verify(
          publicKey: pk1,
          message: Uint8List(0),
          signature: sig1,
        ),
        isTrue,
      );

      // RFC 8032 Section 7.1 TEST 2 (1-byte message 0x72)
      final pk2 = _hexDecode(
        '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
      );
      final sig2 = _hexDecode(
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
        '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      );
      expect(
        ed25519Verify(
          publicKey: pk2,
          message: Uint8List.fromList([0x72]),
          signature: sig2,
        ),
        isTrue,
      );

      // RFC 8032 Section 7.1 TEST 3 (2-byte message 0xaf 0x82)
      final pk3 = _hexDecode(
        'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025',
      );
      final sig3 = _hexDecode(
        '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac'
        '18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a',
      );
      expect(
        ed25519Verify(
          publicKey: pk3,
          message: Uint8List.fromList([0xaf, 0x82]),
          signature: sig3,
        ),
        isTrue,
      );

      // Tamper message, signature, S >= L
      expect(
        ed25519Verify(
          publicKey: pk2,
          message: Uint8List.fromList([0x73]),
          signature: sig2,
        ),
        isFalse,
      );
      final badSig = Uint8List.fromList(sig2)..[63] ^= 0x01;
      expect(
        ed25519Verify(
          publicKey: pk2,
          message: Uint8List.fromList([0x72]),
          signature: badSig,
        ),
        isFalse,
      );
    });

    test('verifies pinned Stage-1 SIGNED_BOOTSTRAP_JSON with fn-2026-v1', () {
      const signedBootstrap =
          '{"payload":{"expires_at":"2028-11-16T00:00:00Z","issued_at":"2026-11-16T00:00:00Z","key_id":"fn-2026-v1","origins":[{"capabilities":["api","sub","update","geox"],"origin":"https://api.westernmoviefans.com","priority":10,"role":"primary"},{"capabilities":["api","sub","update","geox"],"origin":"https://fast.hjy.ca:8443","priority":20,"role":"direct"}],"schema_version":1,"tenant_id":"freedomnet-prod"},"signature":"0E50yFNR0krp7CYFtG_s4XiSEMOVir0OR5cpRvpTKq7MQYs6cHwjqcZELJ5gIrt3IY54WgBIOpMZj6Y7NB6uDQ"}';
      expect(
        base64Encode(_hexDecode(fnStage1PublicKeyHex)),
        fnStage1PublicKeyBase64,
      );

      // Reorder payload map keys intentionally to verify recursive canonical sorting.
      final doc = jsonDecode(signedBootstrap) as Map<String, dynamic>;
      final originalPayload = doc['payload'] as Map<String, dynamic>;
      final shuffledPayload = <String, dynamic>{
        'tenant_id': originalPayload['tenant_id'],
        'schema_version': originalPayload['schema_version'],
        'origins': [
          {
            'role': 'primary',
            'origin': 'https://api.westernmoviefans.com',
            'priority': 10,
            'capabilities': ['api', 'sub', 'update', 'geox'],
          },
          {
            'priority': 20,
            'origin': 'https://fast.hjy.ca:8443',
            'capabilities': ['api', 'sub', 'update', 'geox'],
            'role': 'direct',
          },
        ],
        'key_id': originalPayload['key_id'],
        'issued_at': originalPayload['issued_at'],
        'expires_at': originalPayload['expires_at'],
      };
      final tamperedDoc = {
        'payload': shuffledPayload,
        'signature': doc['signature'],
      };

      expect(
        verifySignedJsonEnvelope(
          tamperedDoc,
          now: DateTime.utc(2026, 11, 17),
        ),
        isTrue,
      );

      // Expired signature must fail.
      expect(
        verifySignedJsonEnvelope(
          tamperedDoc,
          now: DateTime.utc(2029, 1, 1),
        ),
        isFalse,
      );

      // Tampered tenant must fail.
      final wrongTenant = jsonDecode(signedBootstrap) as Map<String, dynamic>;
      (wrongTenant['payload'] as Map<String, dynamic>)['tenant_id'] =
          'evil-tenant';
      expect(
        verifySignedJsonEnvelope(
          wrongTenant,
          now: DateTime.utc(2026, 11, 17),
        ),
        isFalse,
      );
    });
  });

  group('2. Bootstrap Mirror Pool, Origin Failover & Credential Isolation', () {
    test('seeds primary + fallback origins, validates signed bootstrap only',
        () {
      final pool = TransportMirrorPool.defaultTenant();
      expect(
        pool.orderedOrigins().map((u) => u.origin).toList(),
        ['https://api.westernmoviefans.com', 'https://fast.hjy.ca:8443'],
      );

      // Reject unsigned or invalidly signed bootstrap response.
      final invalidBootstrap = jsonDecode(fnDefaultSignedBootstrapJson)
          as Map<String, dynamic>;
      invalidBootstrap['signature'] =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      expect(pool.applyBootstrapResponse(invalidBootstrap), isNull);
      expect(
        pool.orderedOrigins().map((u) => u.origin).toList(),
        ['https://api.westernmoviefans.com', 'https://fast.hjy.ca:8443'],
      );

      // Accept valid pinned bootstrap JSON.
      final valid = pool.applyBootstrapResponse(
        jsonDecode(fnDefaultSignedBootstrapJson),
      );
      expect(valid, isNotNull);
      expect(valid!.tenantId, 'freedomnet-prod');
      expect(valid.origins, hasLength(2));
    });

    test('fails over idempotent reads on pre-request failure, NEVER replays mutations across mirrors',
        () async {
      final seenUrls = <Uri>[];
      var clientIndex = 0;

      await HttpOverrides.runZoned(
        () async {
          final api = DioXboardApi();
          addTearDown(api.close);

          final catalog = await api.getPlanCatalog();
          expect(catalog.plans.single.name, 'Mirror2 Plan');
          expect(
            seenUrls.map((u) => u.origin).toList(),
            ['https://api.westernmoviefans.com', 'https://fast.hjy.ca:8443'],
          );
          expect(api.activeOrigin.origin, 'https://fast.hjy.ca:8443');

          // Subsequent mutation locks onto healthy activeOrigin (fast.hjy.ca:8443).
          // Force fast.hjy.ca:8443 to fail with SocketException inside openUrl:
          // mutation MUST NOT blind-replay on api.westernmoviefans.com!
          seenUrls.clear();
          await expectLater(
            api.login('user@example.com', 'password123'),
            throwsA(isA<XboardException>()),
          );
          expect(
            seenUrls.map((u) => u.origin).toList(),
            ['https://fast.hjy.ca:8443'],
          );
        },
        createHttpClient: (_) {
          clientIndex++;
          return _FakeNetworkHttpClient(
            (method, url, _, __) async {
              if (url.path == '/api/v1/guest/plans' &&
                  url.origin == 'https://fast.hjy.ca:8443') {
                return _RecordedHttpResponse(
                  statusCode: 200,
                  headersMap: {'content-type': 'application/json'},
                  bodyBytes: utf8.encode(jsonEncode({
                    'status': 'success',
                    'data': [
                      {
                        'id': 1,
                        'name': 'Mirror2 Plan',
                        'transfer_enable': 100,
                        'can_purchase': true,
                        'prices': {'monthly': 2000},
                      }
                    ],
                  })),
                );
              }
              if (url.path.contains('/api/v1/passport/auth/login')) {
                throw SocketException(
                    'Login transport error on ${url.origin} #$clientIndex');
              }
              throw StateError('Unexpected $method $url');
            },
            onOpenUrl: (method, url) {
              seenUrls.add(url);
              if (url.path == '/api/v1/guest/plans' &&
                  url.origin == 'https://api.westernmoviefans.com') {
                throw const SocketException('Primary Cloudflare edge reset');
              }
              if (url.path.contains('/api/v1/passport/auth/login')) {
                throw SocketException(
                    'Login pre-request error on ${url.origin} #$clientIndex');
              }
            },
          );
        },
      );
    });

    test('TransportMirrorPool.raceIdempotent starts staggered hedge and cancels remaining timers on winner',
        () async {
      final pool = TransportMirrorPool.defaultTenant();
      final started = <String>[];
      final sw = Stopwatch()..start();
      final winner = await pool.raceIdempotent<String>(
        hedgeDelay: const Duration(milliseconds: 25),
        request: (origin) async {
          started.add(origin.origin);
          if (origin.origin == 'https://api.westernmoviefans.com') {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return 'slow-primary';
          }
          return 'fast-fallback';
        },
      );
      expect(winner, 'fast-fallback');
      expect(sw.elapsedMilliseconds, lessThan(180));
      expect(started, contains('https://api.westernmoviefans.com'));
      expect(started, contains('https://fast.hjy.ca:8443'));
    });

    test('never blind-replays login/register/redeem across mirrors even on pre-request socket failure',
        () async {
      final attemptOrigins = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final api = DioXboardApi();
          addTearDown(api.close);

          await expectLater(
            api.redeemGift('Bearer validtoken123', 'GIFT2026'),
            throwsA(isA<XboardException>()),
          );
          expect(attemptOrigins, ['https://api.westernmoviefans.com']);

          attemptOrigins.clear();
          await expectLater(
            api.login('a@b.com', 'password123'),
            throwsA(isA<XboardException>()),
          );
          expect(attemptOrigins, ['https://api.westernmoviefans.com']);

          attemptOrigins.clear();
          await expectLater(
            api.registerAccount(email: 'a@b.com', password: 'password123'),
            throwsA(isA<XboardException>()),
          );
          expect(attemptOrigins, ['https://api.westernmoviefans.com']);
        },
        createHttpClient: (_) => _FakeNetworkHttpClient(
          (method, url, _, __) =>
              throw const SocketException('Connection reset'),
          onOpenUrl: (method, url) {
            attemptOrigins.add(url.origin);
            throw const SocketException('Pre-request dial failed');
          },
        ),
      );
    });

    test('DioXboardApi.refreshBootstrap fails over and verifies Ed25519 envelope',
        () async {
      await HttpOverrides.runZoned(
        () async {
          final api = DioXboardApi();
          addTearDown(api.close);
          final refreshed = await api.refreshBootstrap();
          expect(refreshed, isNotNull);
          expect(refreshed!.tenantId, fnTenantId);
          expect(refreshed.origins, hasLength(2));
          expect(api.activeOrigin.origin, 'https://fast.hjy.ca:8443');
        },
        createHttpClient: (_) => _FakeNetworkHttpClient(
          (method, url, _, __) async => _RecordedHttpResponse(
            statusCode: 200,
            headersMap: {'content-type': 'application/json'},
            bodyBytes: utf8.encode(fnDefaultSignedBootstrapJson),
          ),
          onOpenUrl: (_, url) {
            if (url.origin == 'https://api.westernmoviefans.com') {
              throw const SocketException('Primary offline');
            }
          },
        ),
      );
    });

    test('preserves Canonical Tenant Namespace across :443 and :8443 origins and validates subscription mirror redirects safely',
        () async {
      final storageMem = _MemorySecureStorage();
      final sPrimary = SecurePurchaseStorage(
        Uri.parse('https://api.westernmoviefans.com'),
        storage: storageMem,
      );
      final sDirect = SecurePurchaseStorage(
        Uri.parse('https://fast.hjy.ca:8443'),
        storage: storageMem,
      );
      final sOther = SecurePurchaseStorage(
        Uri.parse('https://other-panel.example.com'),
        storage: storageMem,
      );

      await sDirect.saveSession(
        const PurchaseSession(99, 'Bearer canonical_token_99'),
      );
      final readFromPrimary = await sPrimary.readSession();
      expect(readFromPrimary?.accountId, 99);
      expect(readFromPrimary?.authorization, 'Bearer canonical_token_99');
      expect(await sOther.readSession(), isNull);

      final chatPrimaryKey = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: Uri.parse('https://api.westernmoviefans.com'),
        websiteToken: 'site-tok',
        scopeKey: 'account:99',
      );
      final chatDirectKey = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: Uri.parse('https://fast.hjy.ca:8443'),
        websiteToken: 'site-tok',
        scopeKey: 'account:99',
      );
      expect(chatPrimaryKey, chatDirectKey);

      final chatThirdPartyKey = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: Uri.parse('https://chat.other.example'),
        websiteToken: 'site-tok',
        scopeKey: 'account:99',
      );
      expect(chatThirdPartyKey, isNot(chatDirectKey));

      final mDirect = PurchaseProfileSynchronizer.accountMarkerFor(
        origin: Uri.parse('https://fast.hjy.ca:8443'),
        accountId: 99,
      );
      final mPrimary = PurchaseProfileSynchronizer.accountMarkerFor(
        origin: Uri.parse('https://api.westernmoviefans.com'),
        accountId: 99,
      );
      expect(mPrimary, mDirect);

      // Subscription downloader allows redirect across verified tenant origins,
      // but blocks arbitrary third-party redirects.
      await HttpOverrides.runZoned(
        () async {
          final downloader = SecureSubscriptionDownloader();
          addTearDown(downloader.close);
          final res = await downloader.download(
            Uri.parse('https://api.westernmoviefans.com/s/subtoken'),
            {},
          );
          expect(utf8.decode(res.data!), 'proxies: []');

          await expectLater(
            downloader.download(
              Uri.parse('https://api.westernmoviefans.com/s/evil'),
              {},
            ),
            throwsA(isA<FormatException>()),
          );
        },
        createHttpClient: (_) => _FakeNetworkHttpClient((_, url, __, ___) async {
          if (url.toString() == 'https://api.westernmoviefans.com/s/subtoken') {
            return _RecordedHttpResponse(
              statusCode: 302,
              bodyBytes: const [],
              headersMap: {
                HttpHeaders.locationHeader:
                    'https://fast.hjy.ca:8443/s/subtoken',
              },
            );
          }
          if (url.toString() == 'https://fast.hjy.ca:8443/s/subtoken') {
            return _RecordedHttpResponse(
              statusCode: 200,
              bodyBytes: utf8.encode('proxies: []'),
            );
          }
          if (url.toString() == 'https://api.westernmoviefans.com/s/evil') {
            return _RecordedHttpResponse(
              statusCode: 302,
              bodyBytes: const [],
              headersMap: {
                HttpHeaders.locationHeader: 'https://evil.example.com/payload',
              },
            );
          }
          throw StateError('Unexpected $url');
        }),
      );
    });
  });

  group('3. SignedUpdate TLS Strictness, DIRECT Routing, Ed25519 latest.json & GitHub Removal',
      () {
    test('SignedUpdate forces badCertificateCallback=false & DIRECT routing immune to FlClashHttpOverrides',
        () async {
      _FakeNetworkHttpClient? recordedClient;
      await HttpOverrides.runZoned(
        () async {
          final updater = SignedUpdate(
            manifestFeeds: [
              Uri.parse(
                'https://api.westernmoviefans.com/api/v1/client/releases/stable/latest.json',
              ),
            ],
            now: () => DateTime.utc(2026, 11, 17),
          );

          await expectLater(
            updater.checkAvailableUpdate('2.2.0'),
            throwsA(anything),
          );
          expect(recordedClient, isNotNull);
          expect(
            recordedClient!.capturedBadCertCallback
                ?.call(_DummyCert(), 'api.westernmoviefans.com', 443),
            isFalse,
          );
          expect(
            recordedClient!.capturedFindProxy?.call(
              Uri.parse('https://api.westernmoviefans.com/latest.json'),
            ),
            'DIRECT',
          );
        },
        createHttpClient: (_) {
          // Simulate FlClashHttpOverrides wrapping client first with permissive defaults,
          // verifying SignedUpdate explicitly overrides them back to strict TLS & DIRECT.
          final client = _FakeNetworkHttpClient((_, __, ___, ____) async {
            throw const SocketException('offline fixture');
          })
            ..badCertificateCallback = ((_, __, ___) => true)
            ..findProxy = ((_) => 'PROXY 127.0.0.1:7890');
          recordedClient = client;
          return client;
        },
      );
    });

    test('Request.checkForUpdate never hits api.github.com and SignedUpdate exposes SignedUpdateCheckResult',
        () async {
      final hitHosts = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final req = Request();
          final result = await req.checkForUpdate();
          expect(hitHosts, isNot(contains('api.github.com')));
          // Should not crash and must return null when offline/no manifest
          expect(result, isNull);
        },
        createHttpClient: (_) => _FakeNetworkHttpClient((_, url, __, ___) {
          hitHosts.add(url.host);
          throw const SocketException('No network in test');
        }),
      );

      // Verify exact shared signature expected by fn-ui-agent-ux
      const checkResult = SignedUpdateCheckResult(
        version: '9.9.9',
        releaseNotes: 'Mainland release notes',
        publishedAt: '2026-11-16T12:00:00Z',
      );
      expect(checkResult.version, '9.9.9');
      expect(checkResult.releaseNotes, 'Mainland release notes');
      expect(checkResult.publishedAt, '2026-11-16T12:00:00Z');
    });

    test('SignedUpdate.checkAvailableUpdate verifies Ed25519 latest.json and rejects tampered manifests',
        () async {
      final updater = SignedUpdate(
        manifestFeeds: [
          Uri.parse(
            'https://api.westernmoviefans.com/api/v1/client/releases/stable/latest.json',
          ),
        ],
        now: () => DateTime.utc(2026, 11, 17),
      );

      // Tampered Ed25519 latest.json must fail checkAvailableUpdate cleanly.
      final badManifest = {
        'payload': {
          'schema_version': 1,
          'key_id': fnStage1KeyId,
          'channel': 'stable',
          'version': '9.9.9',
          'published_at': '2026-11-16T00:00:00Z',
          'expires_at': '2028-11-16T00:00:00Z',
          'release_notes': 'Should be rejected',
          'targets': {
            'windows-x64': {
              'format': 'inno-exe',
              'entry': 'FreedomNet.exe',
              'filename': 'FreedomNet-setup.exe',
              'url':
                  'https://api.westernmoviefans.com/api/v1/client/releases/files/9.9.9/FreedomNet-setup.exe',
              'size': 1024,
              'sha256':
                  '0000000000000000000000000000000000000000000000000000000000000000',
            },
          },
        },
        'signature':
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      };

      await HttpOverrides.runZoned(
        () async {
          await expectLater(
            updater.checkAvailableUpdate('2.2.0'),
            throwsA(isA<StateError>()),
          );
        },
        createHttpClient: (_) => _FakeNetworkHttpClient((_, __, ___, ____) async =>
            _RecordedHttpResponse(
              statusCode: 200,
              headersMap: {'content-type': 'application/json'},
              bodyBytes: utf8.encode(jsonEncode(badManifest)),
            )),
      );
    });

    test('SignedUpdate.checkAvailableUpdate returns result for valid signed inno-exe and rejects portable-zip on Windows',
        () async {
      final testKey = Uint8List.fromList(
        base64Decode('11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='),
      );
      final updater = SignedUpdate(
        manifestFeeds: [
          Uri.parse(
            'https://api.westernmoviefans.com/api/v1/client/releases/stable/latest.json',
          ),
        ],
        trustedKeys: {'test-ed-1': testKey},
        now: () => DateTime.utc(2026, 11, 17),
      );

      final validInnoManifest = {
        'payload': {
          'schema_version': 1,
          'key_id': 'test-ed-1',
          'channel': 'stable',
          'version': '9.9.9',
          'published_at': '2026-11-16T00:00:00Z',
          'expires_at': '2028-11-16T00:00:00Z',
          'release_notes': 'Signed test release',
          'targets': {
            'windows-x64': {
              'format': 'inno-exe',
              'entry': 'FreedomNet.exe',
              'filename': 'FreedomNet-setup.exe',
              'url':
                  'https://api.westernmoviefans.com/api/v1/client/releases/files/9.9.9/FreedomNet-setup.exe',
              'size': 1024,
              'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
          },
        },
        'signature':
            '58SNf-7VkF1cz3_X7N5hZ8XW8piZ9niZrXXx5EnXUPya8ISqs8oT7xvGsfZeiWWze3GeneMtZDMytp3I91baCA',
      };

      await HttpOverrides.runZoned(
        () async {
          final available = await updater.checkAvailableUpdate('2.2.0');
          expect(available, isNotNull);
          expect(available!.version, '9.9.9');
          expect(available.releaseNotes, 'Signed test release');
          expect(available.publishedAt, '2026-11-16T00:00:00Z');
          expect(await updater.checkAvailableUpdate('9.9.9'), isNull);
        },
        createHttpClient: (_) => _FakeNetworkHttpClient((_, __, ___, ____) async =>
            _RecordedHttpResponse(
              statusCode: 200,
              headersMap: {'content-type': 'application/json'},
              bodyBytes: utf8.encode(jsonEncode(validInnoManifest)),
            )),
      );

      final portableZipManifest = {
        'payload': {
          'schema_version': 1,
          'key_id': 'test-ed-1',
          'channel': 'stable',
          'version': '9.9.9',
          'published_at': '2026-11-16T00:00:00Z',
          'expires_at': '2028-11-16T00:00:00Z',
          'release_notes': 'Signed test release',
          'targets': {
            'windows-x64': {
              'format': 'portable-zip',
              'entry': 'FreedomNet.exe',
              'filename': 'FreedomNet-portable.zip',
              'url':
                  'https://api.westernmoviefans.com/api/v1/client/releases/files/9.9.9/FreedomNet-portable.zip',
              'size': 1024,
              'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
          },
        },
        'signature':
            'gmrd_55_-3IXl7GKCaU3Emj99ZsnZhdlQNo7gZY9_1b4Mun73XvtlDNK9OORceDnpADxwYMwquB8bPl7RXLnDA',
      };

      await HttpOverrides.runZoned(
        () async {
          await expectLater(
            updater.checkAvailableUpdate('2.2.0'),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('发布清单格式不兼容: portable-zip'),
              ),
            ),
          );
        },
        createHttpClient: (_) => _FakeNetworkHttpClient((_, __, ___, ____) async =>
            _RecordedHttpResponse(
              statusCode: 200,
              headersMap: {'content-type': 'application/json'},
              bodyBytes: utf8.encode(jsonEncode(portableZipManifest)),
            )),
      );
    }, testOn: 'windows');

    test('signed_update_unix & windows scripts use FreedomNet branding and no FlClash* exclusive gates',
        () {
      expect(unixSignedUpdater, contains('FreedomNet'));
      expect(unixSignedUpdater, isNot(contains('FreedomCloud')));
      expect(windowsSignedUpdater, contains('FreedomNet.exe'));
      expect(windowsSignedUpdater, contains('ed25519'));
    });
  });

  group('4. Mainland GeoX, DNS, IPv6 Blackhole Guard, Tun Excludes & Anti-Cheat Rules',
      () {
    test('ClashCore.initGeo repairs 0-byte and missing files without exit(0)',
        () async {
      final tmp = await Directory.systemTemp.createTemp('fcx_geo_test_');
      addTearDown(() => tmp.delete(recursive: true));

      final zeroMmdb = File(p.join(tmp.path, mmdbFileName));
      await zeroMmdb.writeAsBytes(const <int>[]);
      final existingGeoIp = File(p.join(tmp.path, geoIpFileName));
      await existingGeoIp.writeAsBytes(const [1, 2, 3, 4]);

      final loadedAssets = <String>[];
      await ClashCore.ensureGeoFilesInitialized(
        homePath: tmp.path,
        loadAssetBytes: (assetPath) async {
          loadedAssets.add(assetPath);
          return Uint8List.fromList([9, 8, 7, 6]);
        },
      );

      expect(await zeroMmdb.length(), greaterThan(0));
      expect(await existingGeoIp.readAsBytes(), [1, 2, 3, 4]);
      expect(loadedAssets, contains('assets/data/$mmdbFileName'));
      expect(loadedAssets, contains('assets/data/$asnFileName'));
      expect(loadedAssets, contains('assets/data/$geoSiteFileName'));
      expect(loadedAssets, isNot(contains('assets/data/$geoIpFileName')));

      // Missing asset failure must log and never call exit(0).
      final tmp2 = await Directory.systemTemp.createTemp('fcx_geo_err_');
      addTearDown(() => tmp2.delete(recursive: true));
      await expectLater(
        ClashCore.ensureGeoFilesInitialized(
          homePath: tmp2.path,
          loadAssetBytes: (_) async => throw StateError('Asset missing'),
        ),
        completes,
      );
    });

    test('GeoXUrl, Dns, Tun defaults match Mainland China resilience specification',
        () {
      const geo = GeoXUrl();
      expect(
        geo.mmdb,
        'https://api.westernmoviefans.com/api/v1/client/geox/geoip.metadb',
      );
      expect(
        geo.asn,
        'https://api.westernmoviefans.com/api/v1/client/geox/ASN.mmdb',
      );
      expect(
        geo.geoip,
        'https://api.westernmoviefans.com/api/v1/client/geox/GeoIP.dat',
      );
      expect(
        geo.geosite,
        'https://api.westernmoviefans.com/api/v1/client/geox/GeoSite.dat',
      );

      const dns = Dns();
      expect(dns.defaultNameserver, ['223.5.5.5', '119.29.29.29']);
      expect(dns.proxyServerNameserver, [
        'https://doh.pub/dns-query',
        'https://dns.alidns.com/dns-query',
      ]);

      const tun = Tun();
      expect(tun.routeExcludeAddress, contains('192.168.0.0/16'));
      expect(tun.routeExcludeAddress, contains('10.0.0.0/8'));
      expect(tun.routeExcludeAddress, contains('172.16.0.0/12'));
    });

    test('mergeSubscriptionDnsConfig backfills missing Mainland bootstrap DNS without clobbering subscription',
        () {
      final subRawDns = <String, dynamic>{
        'enable': true,
        'nameserver': ['https://custom-sub-dns.example/dns-query'],
        'fake-ip-filter': ['+custom.internal'],
      };
      final merged = mergeAndBackfillDnsConfig(
        subscriptionDns: subRawDns,
        fallbackDnsJson: const Dns().toJson(),
        overrideDns: false,
      );
      expect(merged['enable'], isTrue);
      expect(
        merged['nameserver'],
        ['https://custom-sub-dns.example/dns-query'],
      );
      expect(merged['default-nameserver'], ['223.5.5.5', '119.29.29.29']);
      expect(merged['proxy-server-nameserver'], [
        'https://doh.pub/dns-query',
        'https://dns.alidns.com/dns-query',
      ]);
      expect(merged['fake-ip-filter'], contains('*.lan'));
      expect(merged['fake-ip-filter'], contains('+custom.internal'));
    });

    test('Ipv6ReachabilityGuard auto-downgrades broken IPv6 egress to false',
        () async {
      final guard = Ipv6ReachabilityGuard(
        listLocalIpv6Addresses: () async => [
          InternetAddress('240e:3b4:1234::56'),
        ],
        tryConnectIpv6: (_, __, {required timeout}) async {
          throw const SocketException('Network unreachable (IPv6 blackhole)');
        },
      );
      expect(await guard.isGlobalIpv6Reachable(forceRefresh: true), isFalse);

      final workingGuard = Ipv6ReachabilityGuard(
        listLocalIpv6Addresses: () async => [
          InternetAddress('240e:3b4:1234::56'),
        ],
        tryConnectIpv6: (_, __, {required timeout}) async => true,
      );
      expect(
        await workingGuard.isGlobalIpv6Reachable(forceRefresh: true),
        isTrue,
      );
    });

    test('compileEffectiveRules prepends anti-cheat & domestic PROCESS-NAME DIRECT rules on desktop only',
        () {
      final desktopResult = compileEffectiveRules(
        rawProfileRules: const ['MATCH,Proxy'],
        localSplitMode: LocalSplitMode.off,
        routeMode: RouteMode.bypassPrivate,
        isDesktop: true,
        hasGeoSite: true,
        hasGeoIp: true,
        scriptActive: false,
      );
      final desktopRules = desktopResult.rules;
      expect(desktopRules, contains('PROCESS-NAME,SGuard64.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,SGuardSvc64.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,vgc.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,EasyAntiCheat.exe,DIRECT'));
      expect(
          desktopRules, contains('PROCESS-NAME,EasyAntiCheat_EOS.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,BEService.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,WeChat.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,Weixin.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,WXWork.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,DingTalk.exe,DIRECT'));
      expect(desktopRules, contains('PROCESS-NAME,Feishu.exe,DIRECT'));
      expect(
        desktopRules.indexOf('PROCESS-NAME,SGuard64.exe,DIRECT'),
        lessThan(desktopRules.indexOf('MATCH,Proxy')),
      );

      // Mobile must NOT receive Windows .exe rules.
      final mobileResult = compileEffectiveRules(
        rawProfileRules: const ['MATCH,Proxy'],
        localSplitMode: LocalSplitMode.off,
        routeMode: RouteMode.bypassPrivate,
        isDesktop: false,
        hasGeoSite: true,
        hasGeoIp: true,
        scriptActive: false,
      );
      expect(mobileResult.rules, ['MATCH,Proxy']);
    });
  });
}
