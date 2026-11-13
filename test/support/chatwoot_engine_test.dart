import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flclashx/manager/support_manager.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flclashx/services/pre_request_transport.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  bool corruptWrites = false;

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
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<dynamic> sent = [];
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
    await incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRealtimeConnection implements ChatwootRealtimeConnection {
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
          'chatwoot_session_v1_${sha256.convert(utf8.encode('${baseUrl.origin}|$websiteToken|guest'))}';
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
            },
            'contact': {
              'id': 77,
              'pubsub_token': 'pubsub_direct',
            },
            'auth_token': 'jwt_direct',
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

      expect(received, hasLength(7));
      expect(received[0], isA<ChatwootMessageCreatedEvent>());
      expect(
        (received[0] as ChatwootMessageCreatedEvent).message.content,
        'Hello from agent',
      );
      expect(received[1], isA<ChatwootMessageUpdatedEvent>());
      expect(
        (received[2] as ChatwootTypingEvent).isTyping,
        isTrue,
      );
      expect(
        (received[3] as ChatwootTypingEvent).isTyping,
        isFalse,
      );
      expect(
        (received[4] as ChatwootConversationStatusChangedEvent).status,
        'resolved',
      );
      expect(
        (received[5] as ChatwootContactMergedEvent).pubsubToken,
        'pubsub_merged',
      );
      expect(received[6], isA<ChatwootSubscriptionRejectedEvent>());

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
      expect(manager.isRealtimeConnected, isTrue);
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
            return [
              ChatwootMessage(
                id: 11,
                content: 'Missed while offline',
                type: ChatwootMessageType.agent,
                createdAt: DateTime.utc(2026, 11, 13, 12, 1),
              ),
            ];
          };

        final storage = SecureChatwootSessionStorage(
          storage: _InMemorySecureStorage(),
        );
        final createdConnections = <_FakeRealtimeConnection>[];
        var connectAttempt = 0;

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
}
