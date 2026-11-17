import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flclashx/services/pre_request_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  bool corruptWrites = false;
  bool throwOnRead = false;
  bool throwOnWrite = false;
  bool throwOnDelete = false;

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
    if (throwOnRead) {
      throw PlatformException(code: 'read_failed', message: 'Keychain locked');
    }
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
    if (throwOnWrite) {
      throw PlatformException(code: 'write_failed', message: 'Access denied');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = corruptWrites ? 'corrupted-value' : value;
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
    if (throwOnDelete) {
      throw PlatformException(code: 'delete_failed', message: 'Access denied');
    }
    values.remove(key);
  }
}

class _MockDioAdapter implements HttpClientAdapter {
  _MockDioAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options, String? body)
      handler;
  final List<RequestOptions> requests = [];
  final List<String?> bodies = [];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = await requestStream?.toList();
    final body = chunks == null
        ? null
        : utf8.decode(chunks.expand((chunk) => chunk).toList());
    bodies.add(body);
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

ResponseBody _jsonResponse(Object? body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _HttpClientProbe implements HttpClient {
  bool Function(X509Certificate, String, int)? certificateCallback;
  String Function(Uri)? proxy;
  Duration? timeout;
  bool closed = false;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? value,
  ) =>
      certificateCallback = value;

  @override
  set findProxy(String Function(Uri)? value) => proxy = value;

  @override
  set connectionTimeout(Duration? value) => timeout = value;

  @override
  Duration? get connectionTimeout => timeout;

  @override
  void close({bool force = false}) => closed = true;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Future.error(const SocketException('probe stops before network'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CertificateProbe implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeWebSocket implements WebSocket {
  _FakeWebSocket({
    this.hangClose = false,
    this.throwOnCancel = false,
  }) {
    incoming = StreamController<dynamic>(
      onCancel: () {
        if (throwOnCancel) {
          throw StateError('cancel failed');
        }
      },
    );
  }

  late final StreamController<dynamic> incoming;
  final List<dynamic> sent = [];
  final bool hangClose;
  final bool throwOnCancel;
  bool closed = false;

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      incoming.stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    if (hangClose) {
      return Completer<void>().future;
    }
    await incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRealtimeConnection implements ChatwootRealtimeConnection {
  _FakeRealtimeConnection({
    this.closeGate,
    this.throwOnClose = false,
  });

  final Completer<void>? closeGate;
  final bool throwOnClose;
  final StreamController<ChatwootRealtimeEvent> _controller =
      StreamController<ChatwootRealtimeEvent>.broadcast();
  final Completer<void> _done = Completer<void>();
  int presenceCalls = 0;
  bool closed = false;

  void emit(ChatwootRealtimeEvent event) {
    if (!closed && !_controller.isClosed) {
      _controller.add(event);
    }
  }

  void drop() {
    unawaited(close());
  }

  @override
  Stream<ChatwootRealtimeEvent> get events => _controller.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => closed;

  @override
  Future<void> sendPresence() async {
    presenceCalls++;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (closeGate != null) {
      await closeGate!.future;
    }
    if (throwOnClose) {
      await _controller.close();
      if (!_done.isCompleted) {
        _done.complete();
      }
      throw StateError('close boom');
    }
    await _controller.close();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

class _FakeChatwootService implements ChatwootService {
  int initCalls = 0;
  int updateContactCalls = 0;
  int fetchConversationCalls = 0;
  int fetchMessagesCalls = 0;
  int sendMessageCalls = 0;
  int updateLastSeenCalls = 0;

  final List<String?> seenInitAuthTokens = [];
  final List<int?> seenBeforeParams = [];
  final List<int?> seenAfterParams = [];
  final List<({String? email, String? name, Map<String, Object?>? attrs})>
      contactUpdates = [];

  Future<
      ({
        ChatwootChannelConfig config,
        String authToken,
        ChatwootContact contact,
      })> Function({
    required Uri baseUrl,
    required String websiteToken,
    String? authToken,
  })? onInit;

  Future<ChatwootContact?> Function({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  })? onUpdateContact;

  Future<ChatwootConversation?> Function({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  })? onFetchConversation;

  Future<List<ChatwootMessage>> Function({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  })? onFetchMessages;

  Future<ChatwootMessage> Function({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    required String content,
    required String echoId,
  })? onSendMessage;

  @override
  Future<
      ({
        ChatwootChannelConfig config,
        String authToken,
        ChatwootContact contact,
      })> initializeSession({
    required Uri baseUrl,
    required String websiteToken,
    String? authToken,
  }) async {
    initCalls++;
    seenInitAuthTokens.add(authToken);
    if (onInit != null) {
      return onInit!(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: authToken,
      );
    }
    return (
      config: ChatwootChannelConfig(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        websiteName: 'FreedomCloud Support',
        welcomeTitle: 'Hi there',
      ),
      authToken: authToken ?? 'auth_token_default',
      contact: const ChatwootContact(
        id: 1,
        pubsubToken: 'pubsub_default',
      ),
    );
  }

  @override
  Future<ChatwootContact?> updateContact({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  }) async {
    updateContactCalls++;
    contactUpdates.add((email: email, name: name, attrs: customAttributes));
    if (onUpdateContact != null) {
      return onUpdateContact!(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: authToken,
        email: email,
        name: name,
        customAttributes: customAttributes,
      );
    }
    return ChatwootContact(
      id: 1,
      email: email,
      name: name,
      pubsubToken: 'pubsub_default',
    );
  }

  @override
  Future<ChatwootConversation?> fetchConversation({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async {
    fetchConversationCalls++;
    if (onFetchConversation != null) {
      return onFetchConversation!(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: authToken,
      );
    }
    return const ChatwootConversation(id: 99, status: 'open');
  }

  @override
  Future<List<ChatwootMessage>> fetchMessages({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  }) async {
    fetchMessagesCalls++;
    seenBeforeParams.add(before);
    seenAfterParams.add(after);
    if (onFetchMessages != null) {
      return onFetchMessages!(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: authToken,
        before: before,
        after: after,
      );
    }
    return const [];
  }

  @override
  Future<ChatwootMessage> sendMessage({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    required String content,
    required String echoId,
  }) async {
    sendMessageCalls++;
    if (onSendMessage != null) {
      return onSendMessage!(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: authToken,
        content: content,
        echoId: echoId,
      );
    }
    return ChatwootMessage(
      id: 500 + sendMessageCalls,
      echoId: echoId,
      content: content,
      type: ChatwootMessageType.visitor,
      createdAt: DateTime.utc(2026, 11, 13, 12, 0, sendMessageCalls),
      deliveryState: ChatwootDeliveryState.sent,
    );
  }

  @override
  Future<void> updateLastSeen({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async {
    updateLastSeenCalls++;
  }

  @override
  void close() {}
}

void main() {
  final baseUrl = Uri.parse('https://chat.test.invalid');
  const websiteToken = 'wt_test_token_123';

  group('Chatwoot models', () {
    test('validates HTTPS baseUrl and rejects insecure/malformed origins', () {
      for (final badUrl in [
        'http://chat.test.invalid',
        'https://',
        'https://user:pass@chat.test.invalid',
        'https://chat.test.invalid?a=1',
        'https://chat.test.invalid#frag',
      ]) {
        expect(
          () => ChatwootChannelConfig(
            baseUrl: Uri.parse(badUrl),
            websiteToken: websiteToken,
          ),
          throwsArgumentError,
        );
      }

      final valid = ChatwootChannelConfig(
        baseUrl: Uri.parse('https://chat.test.invalid:8443/'),
        websiteToken: '  $websiteToken  ',
      );
      expect(valid.baseUrl, Uri.parse('https://chat.test.invalid:8443'));
      expect(valid.websiteToken, websiteToken);
    });

    test('parses message_type from ints and strings', () {
      expect(ChatwootMessageType.parse(0), ChatwootMessageType.visitor);
      expect(ChatwootMessageType.parse(1), ChatwootMessageType.agent);
      expect(ChatwootMessageType.parse(2), ChatwootMessageType.activity);
      expect(ChatwootMessageType.parse(3), ChatwootMessageType.template);
      expect(ChatwootMessageType.parse('incoming'), ChatwootMessageType.visitor);
      expect(ChatwootMessageType.parse('outgoing'), ChatwootMessageType.agent);
      expect(ChatwootMessageType.parse('activity'), ChatwootMessageType.activity);
      expect(ChatwootMessageType.parse('template'), ChatwootMessageType.template);
      expect(() => ChatwootMessageType.parse(99), throwsFormatException);
    });

    test('provides stableKey prioritizing echoId then id', () {
      final optimistic = ChatwootMessage(
        echoId: 'echo-1',
        content: 'hello',
        type: ChatwootMessageType.visitor,
        createdAt: DateTime.utc(2026, 11, 13),
        deliveryState: ChatwootDeliveryState.sending,
      );
      final reconciled = optimistic.copyWith(
        id: 42,
        deliveryState: ChatwootDeliveryState.sent,
      );
      final serverOnly = ChatwootMessage(
        id: 43,
        content: 'reply',
        type: ChatwootMessageType.agent,
        createdAt: DateTime.utc(2026, 11, 13),
      );
      expect(optimistic.stableKey, 'echo:echo-1');
      expect(reconciled.stableKey, 'echo:echo-1');
      expect(serverOnly.stableKey, 'id:43');
    });
  });

  group('SecureChatwootSessionStorage', () {
    test('isolates guest and account sessions via SHA-256 key', () async {
      final secure = _InMemorySecureStorage();
      final storage = SecureChatwootSessionStorage(storage: secure);

      const guestSession = ChatwootSession(
        authToken: 'secret-guest-jwt',
        pubsubToken: 'pubsub-guest',
        contactId: 10,
        scopeKey: 'guest',
      );
      const userASession = ChatwootSession(
        authToken: 'secret-user-a-jwt',
        pubsubToken: 'pubsub-a',
        contactId: 20,
        scopeKey: 'account:101',
        boundEmail: 'a@example.com',
      );
      const userBSession = ChatwootSession(
        authToken: 'secret-user-b-jwt',
        pubsubToken: 'pubsub-b',
        contactId: 30,
        scopeKey: 'account:202',
        boundEmail: 'b@example.com',
      );

      await storage.saveSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        session: guestSession,
      );
      await storage.saveSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        session: userASession,
      );
      await storage.saveSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        session: userBSession,
      );

      final expectedGuestKey =
          'chatwoot_session_v2_${sha256.convert(utf8.encode(jsonEncode([baseUrl.toString(), websiteToken, 'guest'])))}';
      expect(secure.values.containsKey(expectedGuestKey), isTrue);
      expect(guestSession.toString(), isNot(contains('secret-guest-jwt')));
      expect(userASession.toString(), isNot(contains('a@example.com')));

      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'guest',
        ),
        guestSession,
      );
      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'account:101',
        ),
        userASession,
      );
      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'account:202',
        ),
        userBSession,
      );

      await storage.clearSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: 'account:101',
      );
      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'account:101',
        ),
        isNull,
      );
      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'guest',
        ),
        guestSession,
      );
    });

    test('fails closed on corrupted storage or failed readback', () async {
      final secure = _InMemorySecureStorage();
      final storage = SecureChatwootSessionStorage(storage: secure);
      final key = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      secure.values[key] = '{not valid json';
      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'guest',
        ),
        isNull,
      );

      secure.corruptWrites = true;
      await expectLater(
        storage.saveSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          session: const ChatwootSession(
            authToken: 'token-1',
            scopeKey: 'guest',
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('DioChatwootService', () {
    test('enforces strict TLS and preserves proxy routing on primary client',
        () async {
      final client = _HttpClientProbe()
        ..badCertificateCallback = ((_, __, ___) => true)
        ..findProxy = ((_) => 'PROXY 127.0.0.1:7890');

      await HttpOverrides.runZoned(() async {
        final service = DioChatwootService();
        addTearDown(service.close);
        await expectLater(
          service.initializeSession(
            baseUrl: baseUrl,
            websiteToken: websiteToken,
          ),
          throwsA(isA<ChatwootException>()),
        );
        expect(
          client.certificateCallback?.call(_CertificateProbe(), 'chat.test.invalid', 443),
          isFalse,
        );
        expect(
          client.proxy?.call(baseUrl),
          'PROXY 127.0.0.1:7890',
        );
      }, createHttpClient: (_) => client);
    });

    test('supports proxy-to-DIRECT fallback on pre-request failure only',
        () async {
      var fallbackEnabled = true;
      final primaryAdapter = _MockDioAdapter((options, _) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const PreRequestTransportException(
            SocketException('proxy unreachable'),
          ),
        );
      });
      final directAdapter = _MockDioAdapter((options, _) async => _jsonResponse({
            'website_channel_config': {
              'website_name': 'Direct Help',
              'allow_messages_after_resolved': false,
              'auth_token': 'jwt_direct',
            },
            'contact': {
              'id': 77,
              'pubsub_token': 'pubsub_direct',
            },
          }));

      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = primaryAdapter,
        directDio: Dio()..httpClientAdapter = directAdapter,
        shouldFallbackToDirect: () => fallbackEnabled,
      );
      addTearDown(service.close);

      final result = await service.initializeSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
      );
      expect(result.authToken, 'jwt_direct');
      expect(result.config.websiteName, 'Direct Help');
      expect(result.config.allowMessagesAfterResolved, isFalse);
      expect(primaryAdapter.requests, hasLength(1));
      expect(directAdapter.requests, hasLength(1));

      fallbackEnabled = false;
      await expectLater(
        service.initializeSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
        ),
        throwsA(isA<ChatwootException>()
            .having((e) => e.code, 'code', 'connection_error')),
      );
      expect(directAdapter.requests, hasLength(1));
    });

    test('never falls back to DIRECT on TLS certificate failures', () async {
      final primaryAdapter = _MockDioAdapter((options, _) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const PreRequestTransportException(
            HandshakeException('CERTIFICATE_VERIFY_FAILED: self signed'),
          ),
        );
      });
      final directAdapter = _MockDioAdapter(
        (options, _) async => _jsonResponse({'should_not': 'reach'}),
      );

      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = primaryAdapter,
        directDio: Dio()..httpClientAdapter = directAdapter,
        shouldFallbackToDirect: () => true,
      );
      addTearDown(service.close);

      await expectLater(
        service.fetchConversation(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          authToken: 'secret-jwt',
        ),
        throwsA(
          isA<ChatwootException>()
              .having((e) => e.code, 'code', 'certificate_error')
              .having((e) => e.toString(), 'sanitized', isNot(contains('secret-jwt'))),
        ),
      );
      expect(directAdapter.requests, isEmpty);
    });

    test('executes widget endpoints, omits identifier, and filters private notes',
        () async {
      late _MockDioAdapter adapter;
      adapter = _MockDioAdapter((options, body) async {
        if (options.uri.path == '/api/v1/widget/contact' &&
            options.method == 'PATCH') {
          return _jsonResponse({
            'id': 55,
            'email': 'member@test.invalid',
            'pubsub_token': 'pubsub_55',
          });
        }
        if (options.uri.path == '/api/v1/widget/conversations') {
          return _jsonResponse({
            'id': 88,
            'status': 'open',
            'contact_last_seen_at': 1700000000,
          });
        }
        if (options.uri.path == '/api/v1/widget/messages' &&
            options.method == 'GET') {
          return _jsonResponse({
            'payload': [
              {
                'id': 1,
                'content': 'Public visitor message',
                'message_type': 0,
                'created_at': 1700000010,
                'private': false,
              },
              {
                'id': 2,
                'content': 'Internal agent note',
                'message_type': 1,
                'created_at': 1700000020,
                'private': true,
              },
              {
                'id': 3,
                'content': 'Agent reply',
                'message_type': 'outgoing',
                'created_at': '2026-11-13T10:00:00Z',
                'sender': {'name': 'Alice'},
              },
            ],
          });
        }
        if (options.uri.path == '/api/v1/widget/messages' &&
            options.method == 'POST') {
          return _jsonResponse({
            'id': 4,
            'content': 'Follow-up',
            'echo_id': 'e-4',
            'message_type': 0,
            'created_at': 1700000030,
          });
        }
        return _jsonResponse({}, status: 204);
      });

      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.close);

      await service.updateContact(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: 'jwt-abc',
        email: 'member@test.invalid',
        name: 'Member',
        customAttributes: const {'plan': 'Pro'},
      );
      final patchReq = adapter.requests.last;
      final patchBody = jsonDecode(adapter.bodies.last!) as Map<String, dynamic>;
      expect(patchReq.headers['X-Auth-Token'], 'jwt-abc');
      expect(patchReq.uri.queryParameters['website_token'], websiteToken);
      expect(patchBody.containsKey('identifier'), isFalse);
      expect(patchBody['email'], 'member@test.invalid');
      expect(patchBody['custom_attributes'], {'plan': 'Pro'});

      final conv = await service.fetchConversation(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: 'jwt-abc',
      );
      expect(conv?.id, 88);
      expect(conv?.status, 'open');

      final msgs = await service.fetchMessages(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: 'jwt-abc',
        after: 0,
      );
      expect(msgs, hasLength(2));
      expect(msgs.map((m) => m.id), [1, 3]);
      expect(msgs[1].senderName, 'Alice');
      expect(msgs[1].type, ChatwootMessageType.agent);
      expect(adapter.requests.last.uri.queryParameters['after'], '0');

      final sent = await service.sendMessage(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: 'jwt-abc',
        content: 'Follow-up',
        echoId: 'e-4',
      );
      expect(sent.id, 4);
      expect(sent.echoId, 'e-4');
      expect(sent.deliveryState, ChatwootDeliveryState.sent);
    });

    test('maps HTTP 403 on sendMessage to isResolvedLocked', () async {
      final adapter = _MockDioAdapter((_, __) async => _jsonResponse(
            {'error': 'Conversation is already resolved'},
            status: 403,
          ));
      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.close);

      await expectLater(
        service.sendMessage(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          authToken: 'jwt-abc',
          content: 'hello',
          echoId: 'e-1',
        ),
        throwsA(
          isA<ChatwootException>()
              .having((e) => e.isResolvedLocked, 'isResolvedLocked', isTrue)
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('ActionCableChatwootRealtime', () {
    test('subscribes on welcome, parses all events, and falls back to DIRECT',
        () async {
      final fakeSocket = _FakeWebSocket();
      final probes = <_HttpClientProbe>[];
      var attempt = 0;

      final realtime = await HttpOverrides.runZoned(
        () => ActionCableChatwootRealtime.connect(
          baseUrl: Uri.parse('https://chat.test.invalid:8443'),
          pubsubToken: 'pubsub_xyz',
          shouldFallbackToDirect: () => true,
          webSocketConnector: (url, client) async {
            expect(url, 'wss://chat.test.invalid:8443/cable');
            attempt++;
            if (attempt == 1) {
              throw const SocketException('proxy failed');
            }
            return fakeSocket;
          },
        ),
        createHttpClient: (_) {
          final probe = _HttpClientProbe()
            ..badCertificateCallback = ((_, __, ___) => true)
            ..findProxy = ((_) => 'PROXY 127.0.0.1:7890');
          probes.add(probe);
          return probe;
        },
      );

      expect(probes, hasLength(2));
      expect(
        probes[0].certificateCallback?.call(_CertificateProbe(), 'chat.test.invalid', 443),
        isFalse,
      );
      expect(
        probes[1].certificateCallback?.call(_CertificateProbe(), 'chat.test.invalid', 443),
        isFalse,
      );
      expect(probes[1].proxy?.call(baseUrl), 'DIRECT');

      final received = <ChatwootRealtimeEvent>[];
      final sub = realtime.events.listen(received.add);

      fakeSocket.incoming.add(jsonEncode({'type': 'welcome'}));
      fakeSocket.incoming.add(jsonEncode({'type': 'ping', 'message': 123}));
      fakeSocket.incoming.add(jsonEncode({'type': 'confirm_subscription'}));
      await Future<void>.delayed(Duration.zero);

      expect(fakeSocket.sent, hasLength(1));
      final subscribeFrame =
          jsonDecode(fakeSocket.sent.single as String) as Map<String, dynamic>;
      expect(subscribeFrame['command'], 'subscribe');
      expect(
        jsonDecode(subscribeFrame['identifier'] as String),
        {'channel': 'RoomChannel', 'pubsub_token': 'pubsub_xyz'},
      );

      await realtime.sendPresence();
      expect(fakeSocket.sent, hasLength(2));
      final presenceFrame =
          jsonDecode(fakeSocket.sent[1] as String) as Map<String, dynamic>;
      expect(presenceFrame['command'], 'message');
      expect(
        jsonDecode(presenceFrame['data'] as String),
        {'action': 'update_presence'},
      );

      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'message.created',
          'data': {
            'id': 11,
            'content': 'Hello from agent',
            'message_type': 1,
            'created_at': 1700000100,
            'sender': {'name': 'Bob'},
          },
        },
      }));
      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'message.created',
          'data': {
            'id': 12,
            'content': 'Secret internal note',
            'message_type': 1,
            'created_at': 1700000101,
            'private': true,
          },
        },
      }));
      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'message.updated',
          'data': {
            'id': 11,
            'content': 'Edited reply',
            'message_type': 1,
            'created_at': 1700000100,
          },
        },
      }));
      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'conversation.typing_on',
          'data': {
            'user': {'name': 'Bob'},
          },
        },
      }));
      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'conversation.typing_off',
          'data': {
            'user': {'name': 'Bob'},
          },
        },
      }));
      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'conversation.status_changed',
          'data': {'id': 99, 'status': 'resolved'},
        },
      }));
      fakeSocket.incoming.add(jsonEncode({
        'message': {
          'event': 'contact.merged',
          'data': {'id': 501, 'pubsub_token': 'pubsub_merged'},
        },
      }));
      fakeSocket.incoming.add(jsonEncode({'type': 'reject_subscription'}));

      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(8));
      expect(received[0], isA<ChatwootSubscriptionConfirmedEvent>());
      expect(received[1], isA<ChatwootMessageCreatedEvent>());
      expect(
        (received[1] as ChatwootMessageCreatedEvent).message.content,
        'Hello from agent',
      );
      expect(received[2], isA<ChatwootMessageUpdatedEvent>());
      expect(
        (received[3] as ChatwootTypingEvent).isTyping,
        isTrue,
      );
      expect(
        (received[4] as ChatwootTypingEvent).isTyping,
        isFalse,
      );
      expect(
        (received[5] as ChatwootConversationStatusChangedEvent).status,
        'resolved',
      );
      expect(
        (received[6] as ChatwootContactMergedEvent).pubsubToken,
        'pubsub_merged',
      );
      expect(received[7], isA<ChatwootSubscriptionRejectedEvent>());

      await sub.cancel();
      await realtime.close();
      expect(realtime.isClosed, isTrue);
      expect(fakeSocket.closed, isTrue);
    });

    test('rejects certificate failure without falling back to DIRECT',
        () async {
      var calls = 0;
      await expectLater(
        ActionCableChatwootRealtime.connect(
          baseUrl: baseUrl,
          pubsubToken: 'pubsub_xyz',
          shouldFallbackToDirect: () => true,
          webSocketConnector: (_, __) async {
            calls++;
            throw const HandshakeException(
              'CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate',
            );
          },
        ),
        throwsA(isA<ChatwootException>()
            .having((e) => e.code, 'code', 'certificate_error')),
      );
      expect(calls, 1);
    });
  });

  group('SupportManager', () {
    test('stays completely idle until openPanel and frees resources on close',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final connections = <_FakeRealtimeConnection>[];

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async {
          final conn = _FakeRealtimeConnection();
          connections.add(conn);
          return conn;
        },
      )
        ..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken)
        ..bindAccount(accountId: 42, email: 'user@test.invalid');
      await Future<void>.delayed(Duration.zero);

      expect(service.initCalls, 0);
      expect(service.fetchMessagesCalls, 0);
      expect(connections, isEmpty);
      expect(manager.hasActiveRealtimeResources, isFalse);

      await manager.openPanel(initialDraft: 'Need help with order');
      expect(manager.isPanelOpen, isTrue);
      expect(manager.takePendingDraft(), 'Need help with order');
      expect(manager.takePendingDraft(), isNull);
      expect(service.initCalls, 1);
      expect(service.updateContactCalls, 1);
      expect(service.fetchConversationCalls, 1);
      expect(service.fetchMessagesCalls, 1);
      expect(connections, hasLength(1));
      expect(manager.isRealtimeConnected, isFalse);
      expect(manager.isConnecting, isTrue);
      connections.single.emit(const ChatwootSubscriptionConfirmedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRealtimeConnected, isTrue);
      expect(manager.isConnecting, isFalse);
      expect(manager.hasActiveRealtimeResources, isTrue);

      await manager.closePanel();
      expect(manager.isPanelOpen, isFalse);
      expect(manager.isRealtimeConnected, isFalse);
      expect(connections.single.closed, isTrue);
      expect(manager.hasActiveRealtimeResources, isFalse);

      manager.dispose();
      expect(manager.hasActiveRealtimeResources, isFalse);
    });

    test('deduplicates optimistic echo_id and WebSocket message.created races',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      late _FakeRealtimeConnection realtime;
      final sendCompleter = Completer<ChatwootMessage>();

      service.onSendMessage = ({
        required baseUrl,
        required websiteToken,
        required authToken,
        required content,
        required echoId,
      }) =>
          sendCompleter.future;

      final manager = SupportManager(
        service: service,
        storage: storage,
        echoIdGenerator: () => 'echo-fixed-1',
        realtimeConnector: (_, __) async {
          realtime = _FakeRealtimeConnection();
          return realtime;
        },
      );
      addTearDown(manager.dispose);

      manager.configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      await manager.openPanel();

      final sendFuture = manager.sendMessage('Hi support');
      expect(manager.messages, hasLength(1));
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.sending);
      expect(manager.messages.single.stableKey, 'echo:echo-fixed-1');

      // Simulate WebSocket echoing the server message BEFORE REST completes.
      final serverMessage = ChatwootMessage(
        id: 701,
        echoId: 'echo-fixed-1',
        content: 'Hi support',
        type: ChatwootMessageType.visitor,
        createdAt: DateTime.utc(2026, 11, 13, 12, 1),
      );
      realtime.emit(ChatwootMessageCreatedEvent(serverMessage));
      await Future<void>.delayed(Duration.zero);

      expect(manager.messages, hasLength(1));
      expect(manager.messages.single.id, 701);
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.sent);

      sendCompleter.complete(serverMessage);
      await sendFuture;

      expect(manager.messages, hasLength(1));
      expect(manager.messages.single.id, 701);
      expect(manager.messages.single.stableKey, 'echo:echo-fixed-1');
    });

    test('marks failed sends and retries cleanly, plus handles 403 reset',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      var attempt = 0;

      service.onSendMessage = ({
        required baseUrl,
        required websiteToken,
        required authToken,
        required content,
        required echoId,
      }) async {
        attempt++;
        if (attempt == 1) {
          throw const ChatwootException(
            code: 'connection_error',
            message: 'network down',
          );
        }
        if (attempt == 2) {
          return ChatwootMessage(
            id: 801,
            echoId: echoId,
            content: content,
            type: ChatwootMessageType.visitor,
            createdAt: DateTime.utc(2026, 11, 13, 12, 2),
          );
        }
        throw const ChatwootException(
          code: 'conversation_resolved',
          message: 'resolved',
          statusCode: 403,
          isResolvedLocked: true,
        );
      };

      final manager = SupportManager(
        service: service,
        storage: storage,
        echoIdGenerator: () => 'echo-retry-$attempt',
        realtimeConnector: (_, __) async => _FakeRealtimeConnection(),
      );
      addTearDown(manager.dispose);

      manager.configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      await manager.openPanel();

      await manager.sendMessage('Retry me');
      expect(manager.messages, hasLength(1));
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.failed);
      final echoId = manager.messages.single.echoId!;

      await manager.retryMessage(echoId);
      expect(manager.messages, hasLength(1));
      expect(manager.messages.single.id, 801);
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.sent);

      await manager.sendMessage('After resolve');
      expect(manager.isConversationLocked, isTrue);

      await manager.startNewConversation();
      expect(manager.isConversationLocked, isFalse);
      expect(manager.messages, isEmpty);
      expect(service.initCalls, 2);
    });

    test('isolates guest, userA, and userB sessions without leaking history',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final connections = <_FakeRealtimeConnection>[];

      service.onInit = ({
        required baseUrl,
        required websiteToken,
        authToken,
      }) async {
        final suffix = authToken ?? 'fresh_${service.initCalls}';
        return (
          config: ChatwootChannelConfig(
            baseUrl: baseUrl,
            websiteToken: websiteToken,
          ),
          authToken: suffix,
          contact: ChatwootContact(
            id: service.initCalls,
            pubsubToken: 'pubsub_$suffix',
          ),
        );
      };

      service.onFetchMessages = ({
        required baseUrl,
        required websiteToken,
        required authToken,
        before,
        after,
      }) async =>
          [
            ChatwootMessage(
              id: authToken.hashCode,
              content: 'Msg for $authToken',
              type: ChatwootMessageType.agent,
              createdAt: DateTime.utc(2026, 11, 13, 12, 0),
            ),
          ];

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async {
          final conn = _FakeRealtimeConnection();
          connections.add(conn);
          return conn;
        },
      );
      addTearDown(manager.dispose);

      manager.configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);

      // 1. Guest opens panel.
      await manager.openPanel();
      expect(manager.scopeKey, 'guest');
      expect(manager.messages.single.content, 'Msg for fresh_1');

      // 2. Switch to User A while panel is open.
      manager.bindAccount(accountId: 10, email: 'userA@test.invalid');
      expect(manager.messages, isEmpty);
      expect(connections.first.closed, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(manager.scopeKey, 'account:10');
      expect(manager.messages.single.content, 'Msg for fresh_2');

      // 3. Close panel and switch to User B -> must stay lazy!
      await manager.closePanel();
      manager.bindAccount(accountId: 20, email: 'userB@test.invalid');
      expect(manager.messages, isEmpty);
      expect(service.initCalls, 2);

      // 4. Reopen as User B, then switch back to User A and verify stored token reuse.
      await manager.openPanel();
      expect(manager.messages.single.content, 'Msg for fresh_3');

      manager.bindAccount(accountId: 10, email: 'userA@test.invalid');
      await Future<void>.delayed(Duration.zero);
      expect(service.seenInitAuthTokens.last, 'fresh_2');
      expect(manager.messages.single.content, 'Msg for fresh_2');
    });

    test('uses bounded reconnect backoff, typing expiry, and leaks zero timers',
        () {
      fakeAsync((async) {
        final createdConnections = <_FakeRealtimeConnection>[];
        var connectAttempt = 0;

        final service = _FakeChatwootService()
          ..onFetchMessages = ({
            required baseUrl,
            required websiteToken,
            required authToken,
            before,
            after,
          }) async {
            if (after == null) {
              return [
                ChatwootMessage(
                  id: 10,
                  content: 'Initial',
                  type: ChatwootMessageType.agent,
                  createdAt: DateTime.utc(2026, 11, 13, 12, 0),
                ),
              ];
            }
            if (connectAttempt >= 7 && after < 11) {
              return [
                ChatwootMessage(
                  id: 11,
                  content: 'Missed while offline',
                  type: ChatwootMessageType.agent,
                  createdAt: DateTime.utc(2026, 11, 13, 12, 1),
                ),
              ];
            }
            return const [];
          };

        final storage = SecureChatwootSessionStorage(
          storage: _InMemorySecureStorage(),
        );

        final manager = SupportManager(
          service: service,
          storage: storage,
          presenceInterval: const Duration(seconds: 60),
          typingExpiry: const Duration(seconds: 5),
          realtimeConnector: (_, __) async {
            connectAttempt++;
            if (connectAttempt >= 2 && connectAttempt <= 6) {
              throw const ChatwootException(
                code: 'realtime_connection_error',
                message: 'offline',
              );
            }
            final conn = _FakeRealtimeConnection();
            createdConnections.add(conn);
            return conn;
          },
        )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
        unawaited(manager.openPanel());
        async.flushMicrotasks();
        createdConnections.first.emit(const ChatwootSubscriptionConfirmedEvent());
        async.flushMicrotasks();

        expect(manager.isRealtimeConnected, isTrue);
        expect(createdConnections, hasLength(1));

        // Typing indicator auto-expires after 5s.
        createdConnections.first.emit(
          const ChatwootTypingEvent(isTyping: true, senderName: 'Agent'),
        );
        async.flushMicrotasks();
        expect(manager.isAgentTyping, isTrue);
        expect(manager.typingAgentName, 'Agent');
        async.elapse(const Duration(seconds: 5));
        expect(manager.isAgentTyping, isFalse);

        // Presence timer fires at 60s.
        async.elapse(const Duration(seconds: 60));
        expect(createdConnections.first.presenceCalls, 1);

        // Simulate disconnect and verify 1s, 2s, 4s, 8s, 15s backoff schedule.
        createdConnections.first.drop();
        async.flushMicrotasks();
        expect(manager.isRealtimeConnected, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(connectAttempt, 2);
        async.elapse(const Duration(seconds: 2));
        expect(connectAttempt, 3);
        async.elapse(const Duration(seconds: 4));
        expect(connectAttempt, 4);
        async.elapse(const Duration(seconds: 8));
        expect(connectAttempt, 5);
        async.elapse(const Duration(seconds: 15));
        expect(connectAttempt, 6);
        async.elapse(const Duration(seconds: 15));
        expect(connectAttempt, 7);
        async.flushMicrotasks();
        createdConnections.last.emit(const ChatwootSubscriptionConfirmedEvent());
        async.flushMicrotasks();

        expect(manager.isRealtimeConnected, isTrue);
        expect(service.seenAfterParams.last, 10);
        expect(manager.messages.map((m) => m.id), [10, 11]);

        unawaited(manager.closePanel());
        async.flushMicrotasks();
        expect(manager.hasActiveRealtimeResources, isFalse);

        manager.dispose();
        async.elapse(const Duration(minutes: 5));
        expect(manager.hasActiveRealtimeResources, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('handles contact.merged by persisting new pubsubToken and reconnecting',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final pubsubHistory = <String>[];
      final connections = <_FakeRealtimeConnection>[];

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, pubsub) async {
          pubsubHistory.add(pubsub);
          final conn = _FakeRealtimeConnection();
          connections.add(conn);
          return conn;
        },
      );
      addTearDown(manager.dispose);

      manager.configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      await manager.openPanel();
      expect(pubsubHistory, ['pubsub_default']);

      connections.first.emit(
        const ChatwootContactMergedEvent(
          contactId: 909,
          pubsubToken: 'pubsub_new_909',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(connections.first.closed, isTrue);
      expect(pubsubHistory, ['pubsub_default', 'pubsub_new_909']);
      expect(manager.contact?.id, 909);

      final persisted = await storage.readSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      expect(persisted?.contactId, 909);
      expect(persisted?.pubsubToken, 'pubsub_new_909');
    });
  });

  group('Slice A Code Review TDD', () {
    test('P3-2: isCertificateTransportError detects TlsException and unknown ca',
        () {
      expect(
        isCertificateTransportError(const CertificateException('bad cert')),
        isTrue,
      );
      expect(
        isCertificateTransportError(const TlsException('unknown ca')),
        isTrue,
      );
      expect(
        isCertificateTransportError(
          const PreRequestTransportException(
            HandshakeException('CERTIFICATE_VERIFY_FAILED: unknown ca'),
          ),
        ),
        isTrue,
      );
      expect(
        isCertificateTransportError(
          const HandshakeException('Connection reset during TLS'),
        ),
        isFalse,
      );
      expect(
        isCertificateTransportError(const SocketException('unreachable')),
        isFalse,
      );
    });

    test('P3-3: storageKeyFor isolates subpaths and delimiters and supports v1 fallback',
        () async {
      final org1 = Uri.parse('https://chat.test.invalid/org1');
      final org2 = Uri.parse('https://chat.test.invalid/org2');
      final key1 = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: org1,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      final key2 = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: org2,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      expect(key1, isNot(equals(key2)));

      final pipeA = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: baseUrl,
        websiteToken: 'a|b',
        scopeKey: 'c',
      );
      final pipeB = SecureChatwootSessionStorage.storageKeyFor(
        baseUrl: baseUrl,
        websiteToken: 'a',
        scopeKey: 'b|c',
      );
      expect(pipeA, isNot(equals(pipeB)));

      // Compatibility: root origin reads legacy v1 key and clearSession removes it.
      final secure = _InMemorySecureStorage();
      final storage = SecureChatwootSessionStorage(storage: secure);
      final legacyKey =
          'chatwoot_session_v1_${sha256.convert(utf8.encode('${baseUrl.origin}|$websiteToken|guest'))}';
      const legacySession = ChatwootSession(
        authToken: 'legacy_jwt',
        pubsubToken: 'legacy_pubsub',
        contactId: 12,
        scopeKey: 'guest',
      );
      secure.values[legacyKey] = jsonEncode(legacySession.toJson());
      expect(
        await storage.readSession(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          scopeKey: 'guest',
        ),
        legacySession,
      );
      await storage.clearSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      expect(secure.values.containsKey(legacyKey), isFalse);
    });

    test(
        'P0-1: initializeSession reads nested website_channel_config.auth_token on cold init and rotates stale input token',
        () async {
      final adapter = _MockDioAdapter((options, _) async {
        expect(options.uri.path, '/api/v1/widget/config');
        final sentToken = options.headers['X-Auth-Token'];
        return _jsonResponse({
          'website_channel_config': {
            'website_name': 'Nested Config Support',
            'auth_token':
                sentToken == null ? 'fresh_nested_jwt' : 'rotated_nested_jwt',
          },
          'contact': {
            'id': sentToken == null ? 101 : 202,
            'pubsub_token':
                sentToken == null ? 'pubsub_fresh' : 'pubsub_rotated',
          },
        });
      });

      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.close);

      // Cold init (authToken == null) with no top-level auth_token.
      final cold = await service.initializeSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
      );
      expect(cold.authToken, 'fresh_nested_jwt');
      expect(cold.contact.id, 101);

      // Stale input token replaced by server rotated website_channel_config.auth_token.
      final rotated = await service.initializeSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: 'stale_input_jwt',
      );
      expect(rotated.authToken, 'rotated_nested_jwt');
      expect(rotated.contact.id, 202);
    });

    test('P2-1: sendMessage is nonIdempotent and never retries on directDio',
        () async {
      final primaryAdapter = _MockDioAdapter((options, _) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const PreRequestTransportException(
            SocketException('proxy unreachable'),
          ),
        );
      });
      final directAdapter = _MockDioAdapter(
        (options, _) async => _jsonResponse({
          'id': 99,
          'content': 'should not double send',
          'message_type': 0,
          'created_at': 1700000100,
        }),
      );

      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = primaryAdapter,
        directDio: Dio()..httpClientAdapter = directAdapter,
        shouldFallbackToDirect: () => true,
      );
      addTearDown(service.close);

      await expectLater(
        service.sendMessage(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          authToken: 'jwt_1',
          content: 'hello',
          echoId: 'echo-1',
        ),
        throwsA(
          isA<ChatwootException>()
              .having((e) => e.code, 'code', 'connection_error'),
        ),
      );
      expect(primaryAdapter.requests, hasLength(1));
      expect(directAdapter.requests, isEmpty);
    });

    test('P2-5, P3-1, P3-4: 404 maps to not_found, non-JSON 403 maps cleanly, and unknown message_type skips single item',
        () async {
      final adapter = _MockDioAdapter((options, _) async {
        if (options.uri.path == '/api/v1/widget/conversations') {
          return ResponseBody.fromString('<html>404</html>', 404);
        }
        if (options.uri.path == '/api/v1/widget/contact') {
          return ResponseBody.fromString(
            '<html>403 Forbidden</html>',
            403,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }
        if (options.uri.path == '/api/v1/widget/messages' &&
            options.method == 'POST') {
          return ResponseBody.fromString(
            '<html>403 Forbidden</html>',
            403,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        }
        return _jsonResponse({
          'payload': [
            {
              'id': 1,
              'content': 'Valid',
              'message_type': 0,
              'created_at': 1700000010,
            },
            {
              'id': 2,
              'content': 'Future unknown type',
              'message_type': 99,
              'created_at': 1700000020,
            },
            {
              'id': 3,
              'content': 'Valid reply',
              'message_type': 1,
              'created_at': 1700000030,
            },
          ],
        });
      });

      final service = DioChatwootService(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(service.close);

      await expectLater(
        service.fetchConversation(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          authToken: 'jwt-1',
        ),
        throwsA(
          isA<ChatwootException>()
              .having((e) => e.code, 'code', 'not_found')
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );

      await expectLater(
        service.updateContact(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          authToken: 'jwt-1',
          email: 'a@b.c',
        ),
        throwsA(
          isA<ChatwootException>()
              .having((e) => e.code, 'code', 'forbidden')
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );

      await expectLater(
        service.sendMessage(
          baseUrl: baseUrl,
          websiteToken: websiteToken,
          authToken: 'jwt-1',
          content: 'hi',
          echoId: 'e-1',
        ),
        throwsA(
          isA<ChatwootException>()
              .having((e) => e.code, 'code', 'conversation_resolved')
              .having((e) => e.isResolvedLocked, 'isResolvedLocked', isTrue)
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );

      final msgs = await service.fetchMessages(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        authToken: 'jwt-1',
      );
      expect(msgs.map((m) => m.id), [1, 3]);
    });

    test('P1-2: ActionCable handshake enforces overall connectTimeout and external cancelSignal abort',
        () async {
      // 1. Handshake timeout closes primary probe and falls back to DIRECT.
      final probes = <_HttpClientProbe>[];
      // Closed by ActionCableChatwootRealtime.close().
      // ignore: close_sinks
      final directSocket = _FakeWebSocket();
      var attempt = 0;

      final recovered = await HttpOverrides.runZoned(
        () => ActionCableChatwootRealtime.connect(
          baseUrl: baseUrl,
          pubsubToken: 'pubsub_timeout',
          connectTimeout: const Duration(milliseconds: 30),
          shouldFallbackToDirect: () => true,
          webSocketConnector: (_, __) {
            attempt++;
            if (attempt == 1) {
              return Completer<WebSocket>().future;
            }
            return Future<WebSocket>.value(directSocket);
          },
        ),
        createHttpClient: (_) {
          final p = _HttpClientProbe();
          probes.add(p);
          return p;
        },
      );
      expect(attempt, 2);
      expect(probes, hasLength(2));
      expect(probes[0].closed, isTrue);
      expect(probes[1].proxy?.call(baseUrl), 'DIRECT');
      await recovered.close();

      // 2. External cancelSignal aborts pending handshake immediately without DIRECT fallback.
      final cancelProbes = <_HttpClientProbe>[];
      final cancelCompleter = Completer<void>();
      var cancelAttempts = 0;
      final connectFuture = HttpOverrides.runZoned(
        () => ActionCableChatwootRealtime.connect(
          baseUrl: baseUrl,
          pubsubToken: 'pubsub_cancel',
          connectTimeout: const Duration(seconds: 5),
          shouldFallbackToDirect: () => true,
          cancelSignal: cancelCompleter.future,
          webSocketConnector: (_, __) {
            cancelAttempts++;
            return Completer<WebSocket>().future;
          },
        ),
        createHttpClient: (_) {
          final p = _HttpClientProbe();
          cancelProbes.add(p);
          return p;
        },
      );
      await Future<void>.delayed(Duration.zero);
      cancelCompleter.complete();

      await expectLater(
        connectFuture,
        throwsA(isA<ChatwootException>()),
      );
      expect(cancelAttempts, 1);
      expect(cancelProbes.single.closed, isTrue);
    });

    test('P1-3 & P2-2: ActionCable disconnect frame, ping watchdog, safe close(), malformed frame & private typing',
        () async {
      // 1. Malformed frames & is_private typing dropped; disconnect(reconnect: false) emitted.
      // Closed via rt1.close().
      // ignore: close_sinks
      final socket1 = _FakeWebSocket();
      final rt1 = await HttpOverrides.runZoned(
        () => ActionCableChatwootRealtime.connect(
          baseUrl: baseUrl,
          pubsubToken: 'pubsub_rt1',
          pingTimeout: const Duration(seconds: 5),
          webSocketConnector: (_, __) async => socket1,
        ),
        createHttpClient: (_) => _HttpClientProbe(),
      );
      final events1 = <ChatwootRealtimeEvent>[];
      final sub1 = rt1.events.listen(events1.add);

      socket1.incoming.add(jsonEncode({'type': 'confirm_subscription'}));
      socket1.incoming.add(jsonEncode({
        'message': {
          'event': 123,
          'data': {},
        },
      }));
      socket1.incoming.add(jsonEncode({
        'message': {
          'event': 'conversation.typing_on',
          'data': {
            'user': {'name': 456},
          },
        },
      }));
      socket1.incoming.add(jsonEncode({
        'message': {
          'event': 'conversation.typing_on',
          'data': {
            'user': {'name': 'Agent'},
            'is_private': true,
          },
        },
      }));
      socket1.incoming.add(jsonEncode({
        'type': 'disconnect',
        'reason': 'unauthorized',
        'reconnect': false,
      }));
      await Future<void>.delayed(Duration.zero);

      expect(events1, hasLength(2));
      expect(events1[0], isA<ChatwootSubscriptionConfirmedEvent>());
      expect(
        events1[1],
        isA<ChatwootDisconnectedEvent>()
            .having((e) => e.reconnect, 'reconnect', isFalse)
            .having((e) => e.reason, 'reason', 'unauthorized'),
      );
      await sub1.cancel();
      await rt1.close();

      // 2. Ping watchdog resets on ping frames and drops when server goes silent,
      // plus close() does not hang on hanging _socket.close() or throwing cancel().
      // Closed via watchdog close().
      // ignore: close_sinks
      final socket2 = _FakeWebSocket(hangClose: true, throwOnCancel: true);
      final rt2 = await HttpOverrides.runZoned(
        () => ActionCableChatwootRealtime.connect(
          baseUrl: baseUrl,
          pubsubToken: 'pubsub_rt2',
          pingTimeout: const Duration(milliseconds: 45),
          closeTimeout: const Duration(milliseconds: 25),
          webSocketConnector: (_, __) async => socket2,
        ),
        createHttpClient: (_) => _HttpClientProbe(),
      );
      final events2 = <ChatwootRealtimeEvent>[];
      final sub2 = rt2.events.listen(events2.add);

      await Future<void>.delayed(const Duration(milliseconds: 25));
      socket2.incoming.add(jsonEncode({'type': 'ping', 'message': 1}));
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(rt2.isClosed, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        events2.any((e) => e is ChatwootDisconnectedEvent && e.reconnect),
        isTrue,
      );
      await rt2.done;
      await sub2.cancel();
      expect(rt2.isClosed, isTrue);
    });

    test('P1-1 & P3-5: panelToken contract and concurrent _connectRealtime generation guard',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final completers = <Completer<ChatwootRealtimeConnection>>[];
      final created = <_FakeRealtimeConnection>[];

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) {
          final c = Completer<ChatwootRealtimeConnection>();
          completers.add(c);
          return c.future;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      // Panel token contract: stale openPanel/closePanel are ignored.
      final token1 = manager.acquirePanelToken();
      final token2 = manager.acquirePanelToken();
      expect(token2, greaterThan(token1));

      await manager.openPanel(panelToken: token1);
      expect(manager.isPanelOpen, isFalse);

      final open2 = manager.openPanel(panelToken: token2);
      await Future<void>.delayed(Duration.zero);
      expect(manager.isPanelOpen, isTrue);
      expect(completers, hasLength(1));

      // Stale closePanel(token1) must be ignored while token2 is active.
      await manager.closePanel(panelToken: token1);
      expect(manager.isPanelOpen, isTrue);

      // Concurrent openPanel -> closePanel -> openPanel + concurrent openPanel with pending connector.
      await manager.closePanel(panelToken: token2);
      expect(manager.isPanelOpen, isFalse);

      final token3 = manager.acquirePanelToken();
      final open3a = manager.openPanel(panelToken: token3);
      await Future<void>.delayed(Duration.zero);
      expect(completers, hasLength(2));

      // Second concurrent openPanel() starts another _connectRealtime while #2 is pending.
      final open3b = manager.openPanel(panelToken: token3);
      await Future<void>.delayed(Duration.zero);
      expect(completers, hasLength(3));

      // Complete stale #1 and #2 connections -> both must be closed immediately without touching _connecting!
      final conn1 = _FakeRealtimeConnection();
      final conn2 = _FakeRealtimeConnection();
      created.addAll([conn1, conn2]);
      completers[0].complete(conn1);
      completers[1].complete(conn2);
      await Future<void>.delayed(Duration.zero);
      expect(conn1.closed, isTrue);
      expect(conn2.closed, isTrue);
      expect(manager.isConnecting, isTrue);

      // Complete active #3 connection -> becomes the sole active connection.
      final conn3 = _FakeRealtimeConnection();
      created.add(conn3);
      completers[2].complete(conn3);
      await open2;
      await open3a;
      await open3b;
      expect(conn3.closed, isFalse);
      conn3.emit(const ChatwootSubscriptionConfirmedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRealtimeConnected, isTrue);
      expect(manager.hasActiveRealtimeResources, isTrue);

      // P3-5: teardown throwing inside _connectRealtime resets _connecting cleanly.
      await manager.closePanel(panelToken: token3);
      final throwingConn = _FakeRealtimeConnection(throwOnClose: true);
      final brokenManager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async => throwingConn,
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(brokenManager.dispose);
      await brokenManager.openPanel();
      throwingConn.emit(
        const ChatwootContactMergedEvent(
          contactId: 8,
          pubsubToken: 'pubsub_8',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(brokenManager.isConnecting, isFalse);
    });

    test('P1-2 in SupportManager: closePanel aborts pending handshake via cancelSignal',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      var cancelCompleted = false;
      final connectorStarted = Completer<void>();

      final manager = SupportManager(
        service: service,
        storage: storage,
        cancelableRealtimeConnector: (_, __, cancelSignal) {
          unawaited(cancelSignal.then((_) => cancelCompleted = true));
          if (!connectorStarted.isCompleted) {
            connectorStarted.complete();
          }
          return Completer<ChatwootRealtimeConnection>().future;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      final openFuture = manager.openPanel();
      await connectorStarted.future;
      await manager.closePanel();
      await openFuture;
      expect(cancelCompleted, isTrue);
      expect(manager.hasActiveRealtimeResources, isFalse);
    });

    test('P1-3 in SupportManager: confirm_subscription gate, reject_subscription backoff & cap, disconnect(reconnect:false)',
        () {
      fakeAsync((async) {
        final service = _FakeChatwootService();
        final storage = SecureChatwootSessionStorage(
          storage: _InMemorySecureStorage(),
        );
        final conns = <_FakeRealtimeConnection>[];
        var connectCalls = 0;

        final manager = SupportManager(
          service: service,
          storage: storage,
          presenceInterval: const Duration(seconds: 30),
          realtimeConnector: (_, __) async {
            connectCalls++;
            final conn = _FakeRealtimeConnection();
            conns.add(conn);
            return conn;
          },
        )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);

        unawaited(manager.openPanel());
        async.flushMicrotasks();

        // Before confirm_subscription: NOT connected and presence timer must NOT fire.
        expect(manager.isRealtimeConnected, isFalse);
        expect(manager.isConnecting, isTrue);
        async.elapse(const Duration(seconds: 30));
        expect(conns.first.presenceCalls, 0);

        // Repeated reject_subscription preserves backoff [1, 2, 4, 8, 15] without resetting to 1s.
        conns.last.emit(const ChatwootSubscriptionRejectedEvent());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(connectCalls, 2);

        conns.last.emit(const ChatwootSubscriptionRejectedEvent());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 1));
        expect(connectCalls, 2); // Must wait full 2s, not reset to 1s!
        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(connectCalls, 3);

        conns.last.emit(const ChatwootSubscriptionRejectedEvent());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 4))
          ..flushMicrotasks();
        expect(connectCalls, 4);

        conns.last.emit(const ChatwootSubscriptionRejectedEvent());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 8))
          ..flushMicrotasks();
        expect(connectCalls, 5);

        conns.last.emit(const ChatwootSubscriptionRejectedEvent());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 15))
          ..flushMicrotasks();
        expect(connectCalls, 6);

        // Confirm on attempt 6 -> resets backoff and starts presence.
        conns.last.emit(const ChatwootSubscriptionConfirmedEvent());
        async.flushMicrotasks();
        expect(manager.isRealtimeConnected, isTrue);
        expect(manager.isConnecting, isFalse);
        async.elapse(const Duration(seconds: 30));
        expect(conns.last.presenceCalls, 1);

        // disconnect(reconnect: false) stops auto-reconnect cleanly.
        final callsBeforeStop = connectCalls;
        conns.last.emit(
          const ChatwootDisconnectedEvent(reconnect: false, reason: 'logout'),
        );
        async
          ..flushMicrotasks()
          ..elapse(const Duration(minutes: 2));
        expect(connectCalls, callsBeforeStop);
        expect(manager.isRealtimeConnected, isFalse);
        expect(manager.hasActiveRealtimeResources, isFalse);

        // Bounded rejections eventually stop auto-reconnect instead of looping forever.
        unawaited(manager.closePanel());
        async.flushMicrotasks();
        unawaited(manager.openPanel());
        async.flushMicrotasks();
        for (var i = 0; i < 15; i++) {
          if (conns.last.isClosed) break;
          conns.last.emit(const ChatwootSubscriptionRejectedEvent());
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 20))
            ..flushMicrotasks();
        }
        final callsAtCap = connectCalls;
        async.elapse(const Duration(minutes: 2));
        expect(connectCalls, callsAtCap);

        manager.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('P1-4: _markMessageFailed and _dispatchSend do not clobber WS-confirmed sent message',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      late _FakeRealtimeConnection realtime;
      final sendCompleter = Completer<ChatwootMessage>();

      service.onSendMessage = ({
        required baseUrl,
        required websiteToken,
        required authToken,
        required content,
        required echoId,
      }) =>
          sendCompleter.future;

      final manager = SupportManager(
        service: service,
        storage: storage,
        echoIdGenerator: () => 'echo-ws-first',
        realtimeConnector: (_, __) async {
          realtime = _FakeRealtimeConnection();
          return realtime;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      final sendFuture = manager.sendMessage('WS arrives first');

      realtime.emit(
        ChatwootMessageCreatedEvent(
          ChatwootMessage(
            id: 701,
            echoId: 'echo-ws-first',
            content: 'WS arrives first',
            type: ChatwootMessageType.visitor,
            createdAt: DateTime.utc(2026, 11, 14, 12, 0),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.sent);

      sendCompleter.completeError(
        const ChatwootException(
          code: 'connection_error',
          message: 'network dropped after server persisted',
        ),
      );
      await sendFuture;

      expect(manager.messages.single.id, 701);
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.sent);
      expect(manager.error, isNull);
    });

    test('P1-5: storage PlatformException and corruptWrites degrade gracefully across lifecycle',
        () async {
      final rawStorage = _InMemorySecureStorage()
        ..throwOnRead = true
        ..throwOnWrite = true
        ..throwOnDelete = true;
      final storage = SecureChatwootSessionStorage(storage: rawStorage);
      final service = _FakeChatwootService();
      late _FakeRealtimeConnection realtime;

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async {
          realtime = _FakeRealtimeConnection();
          return realtime;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      expect(manager.error, isNull);
      expect(manager.contact, isNotNull);

      manager.bindAccount(accountId: 42, email: 'u42@test.invalid');
      await Future<void>.delayed(Duration.zero);
      expect(manager.error, isNull);
      expect(manager.scopeKey, 'account:42');

      realtime.emit(
        const ChatwootContactMergedEvent(
          contactId: 999,
          pubsubToken: 'pubsub_merged_999',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(manager.contact?.id, 999);

      await manager.startNewConversation();
      expect(manager.error, isNull);

      // Also verify corruptWrites (FormatException on readback) degrades cleanly.
      rawStorage
        ..throwOnRead = false
        ..throwOnWrite = false
        ..throwOnDelete = false
        ..corruptWrites = true;
      await manager.startNewConversation();
      expect(manager.error, isNull);
      expect(manager.contact, isNotNull);
    });

    test('P1-6: confirm_subscription and openPanel fast-path sync resolved <-> open and missed messages',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final conns = <_FakeRealtimeConnection>[];
      var serverStatus = 'resolved';
      final serverMessages = <ChatwootMessage>[
        ChatwootMessage(
          id: 1,
          content: 'Initial',
          type: ChatwootMessageType.agent,
          createdAt: DateTime.utc(2026, 11, 14, 12, 0),
        ),
      ];

      service
        ..onInit = (({
          required baseUrl,
          required websiteToken,
          authToken,
        }) async =>
            (
              config: ChatwootChannelConfig(
                baseUrl: baseUrl,
                websiteToken: websiteToken,
                allowMessagesAfterResolved: false,
              ),
              authToken: 'jwt_sync',
              contact: const ChatwootContact(id: 1, pubsubToken: 'pubsub_sync'),
            ))
        ..onFetchConversation = (({
          required baseUrl,
          required websiteToken,
          required authToken,
        }) async =>
            ChatwootConversation(id: 55, status: serverStatus))
        ..onFetchMessages = ({
          required baseUrl,
          required websiteToken,
          required authToken,
          before,
          after,
        }) async {
          if (after == null) return List.of(serverMessages);
          return serverMessages.where((m) => (m.id ?? 0) > after).toList();
        };

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async {
          final c = _FakeRealtimeConnection();
          conns.add(c);
          return c;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      expect(manager.isConversationLocked, isTrue);

      // Message sent while handshake was confirming is reconciled on confirm_subscription.
      serverMessages.add(
        ChatwootMessage(
          id: 2,
          content: 'Missed during handshake',
          type: ChatwootMessageType.agent,
          createdAt: DateTime.utc(2026, 11, 14, 12, 1),
        ),
      );
      conns.last.emit(const ChatwootSubscriptionConfirmedEvent());
      await Future<void>.delayed(Duration.zero);
      expect(manager.messages.map((m) => m.id), [1, 2]);

      // Close panel, server reopens conversation and adds message, fast-path reopen syncs both.
      await manager.closePanel();
      serverStatus = 'open';
      serverMessages.add(
        ChatwootMessage(
          id: 3,
          content: 'Agent reopened while closed',
          type: ChatwootMessageType.agent,
          createdAt: DateTime.utc(2026, 11, 14, 12, 2),
        ),
      );

      await manager.openPanel();
      expect(manager.isConversationLocked, isFalse);
      expect(manager.messages.map((m) => m.id), [1, 2, 3]);
    });

    test('P1-7: startNewConversation resets epoch first so concurrent bindAccount is not wiped',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final closeGate = Completer<void>();
      final conns = <_FakeRealtimeConnection>[];

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async {
          final c = _FakeRealtimeConnection(
            closeGate: conns.isEmpty ? closeGate : null,
          );
          conns.add(c);
          return c;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      expect(manager.scopeKey, 'guest');

      final resetFuture = manager.startNewConversation();
      // While guest WS close() is suspended, switch to account:99.
      manager.bindAccount(accountId: 99, email: 'acct99@test.invalid');
      await Future<void>.delayed(Duration.zero);
      expect(manager.scopeKey, 'account:99');
      expect(manager.contact, isNotNull);

      closeGate.complete();
      await resetFuture;

      expect(manager.scopeKey, 'account:99');
      expect(manager.boundEmail, 'acct99@test.invalid');
      expect(manager.contact, isNotNull);
    });

    test('P2-2 in SupportManager: ignores realtime events for other conversation_id',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      late _FakeRealtimeConnection rt;
      service.onFetchConversation = ({
        required baseUrl,
        required websiteToken,
        required authToken,
      }) async =>
          const ChatwootConversation(id: 55, status: 'open');

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async {
          rt = _FakeRealtimeConnection();
          return rt;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      rt.emit(const ChatwootSubscriptionConfirmedEvent());
      await Future<void>.delayed(Duration.zero);

      rt
        ..emit(
          const ChatwootTypingEvent(
            isTyping: true,
            senderName: 'Other',
            conversationId: 999,
          ),
        )
        ..emit(
          ChatwootMessageCreatedEvent(
            ChatwootMessage(
              id: 404,
              content: 'Wrong conversation',
              type: ChatwootMessageType.agent,
              createdAt: DateTime.utc(2026, 11, 14, 12, 0),
            ),
            conversationId: 999,
          ),
        )
        ..emit(
          const ChatwootConversationStatusChangedEvent(
            conversationId: 999,
            status: 'resolved',
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(manager.isAgentTyping, isFalse);
      expect(manager.messages, isEmpty);
      expect(manager.conversation?.status, 'open');
    });

    test('P2-3: loadOlderMessages paginates via before cursor and deduplicates',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final olderGate = Completer<List<ChatwootMessage>>();

      service.onFetchMessages = ({
        required baseUrl,
        required websiteToken,
        required authToken,
        before,
        after,
      }) async {
        if (before == null) {
          return [
            ChatwootMessage(
              id: 21,
              content: 'M21',
              type: ChatwootMessageType.visitor,
              createdAt: DateTime.utc(2026, 11, 14, 12, 2),
            ),
            ChatwootMessage(
              id: 22,
              content: 'M22',
              type: ChatwootMessageType.agent,
              createdAt: DateTime.utc(2026, 11, 14, 12, 3),
            ),
          ];
        }
        if (before == 21) {
          return olderGate.future;
        }
        return const [];
      };

      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async => _FakeRealtimeConnection(),
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      expect(manager.hasMoreHistory, isTrue);

      final load1 = manager.loadOlderMessages();
      final load2 = manager.loadOlderMessages(); // Deduplicated while in flight.
      expect(manager.isLoadingOlder, isTrue);

      olderGate.complete([
        ChatwootMessage(
          id: 19,
          content: 'M19',
          type: ChatwootMessageType.agent,
          createdAt: DateTime.utc(2026, 11, 14, 12, 0),
        ),
        ChatwootMessage(
          id: 21,
          content: 'M21',
          type: ChatwootMessageType.visitor,
          createdAt: DateTime.utc(2026, 11, 14, 12, 2),
        ),
      ]);
      await Future.wait([load1, load2]);

      expect(manager.isLoadingOlder, isFalse);
      expect(service.seenBeforeParams, [null, 21]);
      expect(manager.messages.map((m) => m.id), [19, 21, 22]);

      await manager.loadOlderMessages();
      expect(manager.hasMoreHistory, isFalse);
      await manager.loadOlderMessages(); // No-op once exhausted.
      expect(service.seenBeforeParams, [null, 21, 19]);
    });

    test('P2-4: closed bindAccount metadata edit syncs on reopen and pendingDraft clears on scope reset',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      final manager = SupportManager(
        service: service,
        storage: storage,
        realtimeConnector: (_, __) async => _FakeRealtimeConnection(),
      )
        ..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken)
        ..bindAccount(accountId: 10, email: 'old@test.invalid');

      await manager.openPanel();
      expect(service.updateContactCalls, 1);

      await manager.closePanel();
      manager.bindAccount(
        accountId: 10,
        email: 'new@test.invalid',
        customAttributes: const {'plan': 'pro'},
      );
      expect(service.updateContactCalls, 1); // Lazy while closed!

      await manager.openPanel();
      expect(service.updateContactCalls, 2);
      expect(service.contactUpdates.last.email, 'new@test.invalid');
      expect(service.contactUpdates.last.attrs, {'plan': 'pro'});

      // Draft queued while open clears on account switch before takePendingDraft().
      await manager.openPanel(initialDraft: 'Leaked draft?');
      expect(manager.pendingDraft, 'Leaked draft?');
      manager.bindAccount(accountId: 20, email: 'user20@test.invalid');
      expect(manager.pendingDraft, isNull);
      expect(manager.takePendingDraft(), isNull);
    });

    test('P2-5 in SupportManager: 401/404 on send/fetch clears stale _session and self-heals',
        () async {
      final service = _FakeChatwootService();
      final rawStorage = _InMemorySecureStorage();
      final storage = SecureChatwootSessionStorage(storage: rawStorage);
      var initCount = 0;

      service
        ..onInit = ({
          required baseUrl,
          required websiteToken,
          authToken,
        }) async {
          initCount++;
          return (
            config: ChatwootChannelConfig(
              baseUrl: baseUrl,
              websiteToken: websiteToken,
            ),
            authToken: 'jwt_gen_$initCount',
            contact: ChatwootContact(
              id: initCount,
              pubsubToken: 'pubsub_$initCount',
            ),
          );
        }
        ..onSendMessage = ({
          required baseUrl,
          required websiteToken,
          required authToken,
          required content,
          required echoId,
        }) async {
        if (authToken == 'jwt_gen_1') {
          throw const ChatwootException(
            code: 'not_found',
            message: 'Contact deleted',
            statusCode: 404,
          );
        }
        return ChatwootMessage(
          id: 901,
          echoId: echoId,
          content: content,
          type: ChatwootMessageType.visitor,
          createdAt: DateTime.utc(2026, 11, 14, 12, 0),
        );
      };

      final manager = SupportManager(
        service: service,
        storage: storage,
        echoIdGenerator: () => 'echo-heal-1',
        realtimeConnector: (_, __) async => _FakeRealtimeConnection(),
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();
      expect(initCount, 1);

      await manager.sendMessage('Trigger 404 heal');
      expect(initCount, 2);
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.failed);

      final persisted = await storage.readSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      expect(persisted?.authToken, 'jwt_gen_2');

      // Retry now uses healed jwt_gen_2 and succeeds!
      await manager.retryMessage('echo-heal-1');
      expect(manager.messages.single.deliveryState, ChatwootDeliveryState.sent);
      expect(manager.messages.single.id, 901);

      // Reopen after deleted contact (404 on fetchConversation/fetchMessages) self-heals too.
      await manager.closePanel();
      service.onFetchConversation = ({
        required baseUrl,
        required websiteToken,
        required authToken,
      }) async {
        if (authToken == 'jwt_gen_2') {
          throw const ChatwootException(
            code: 'not_found',
            message: 'Contact deleted',
            statusCode: 404,
          );
        }
        return const ChatwootConversation(id: 55, status: 'open');
      };

      await manager.openPanel();
      expect(initCount, 3);
      final healed = await storage.readSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: 'guest',
      );
      expect(healed?.authToken, 'jwt_gen_3');
    });

    test('P2-6: localSequence keeps same-second optimistic and server-truncated messages strictly ordered',
        () async {
      final service = _FakeChatwootService();
      final storage = SecureChatwootSessionStorage(
        storage: _InMemorySecureStorage(),
      );
      late _FakeRealtimeConnection rt;
      final send1Gate = Completer<ChatwootMessage>();
      var seq = 0;

      service
        ..onFetchMessages = (({
          required baseUrl,
          required websiteToken,
          required authToken,
          before,
          after,
        }) async =>
            [
              ChatwootMessage(
                id: 9,
                content: 'Server initial',
                type: ChatwootMessageType.agent,
                createdAt:
                    DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
              ),
            ])
        ..onSendMessage = ({
          required baseUrl,
          required websiteToken,
          required authToken,
          required content,
          required echoId,
        }) {
        if (echoId == 'echo-seq-1') return send1Gate.future;
        return Future.value(
          ChatwootMessage(
            id: 12,
            echoId: echoId,
            content: content,
            type: ChatwootMessageType.visitor,
            createdAt: DateTime.now().toUtc().copyWith(
                  millisecond: 0,
                  microsecond: 0,
                ),
          ),
        );
      };

      final manager = SupportManager(
        service: service,
        storage: storage,
        echoIdGenerator: () => 'echo-seq-${++seq}',
        realtimeConnector: (_, __) async {
          rt = _FakeRealtimeConnection();
          return rt;
        },
      )..configureChannel(baseUrl: baseUrl, websiteToken: websiteToken);
      addTearDown(manager.dispose);

      await manager.openPanel();

      final future1 = manager.sendMessage('First optimistic');
      final nowSec = manager.messages.last.createdAt.copyWith(
        millisecond: 0,
        microsecond: 0,
      );
      // Agent WS message arrives in the SAME second with whole-second timestamp (.000Z)
      // while First optimistic has microsecond timestamp (.xxxZ) and is still sending.
      rt.emit(
        ChatwootMessageCreatedEvent(
          ChatwootMessage(
            id: 11,
            content: 'Agent same-second',
            type: ChatwootMessageType.agent,
            createdAt: nowSec,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Must NOT jump ahead of First optimistic!
      expect(
        manager.messages.map((m) => m.content),
        ['Server initial', 'First optimistic', 'Agent same-second'],
      );

      send1Gate.complete(
        ChatwootMessage(
          id: 10,
          echoId: 'echo-seq-1',
          content: 'First optimistic',
          type: ChatwootMessageType.visitor,
          createdAt: nowSec,
        ),
      );
      await future1;
      expect(
        manager.messages.map((m) => m.content),
        ['Server initial', 'First optimistic', 'Agent same-second'],
      );
    });
  });
}
