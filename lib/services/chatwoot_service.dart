import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/services/pre_request_transport.dart';
import 'package:flutter/foundation.dart';

export 'package:flclashx/models/chatwoot.dart'
    show
        ChatwootContactMergedEvent,
        ChatwootConversationStatusChangedEvent,
        ChatwootDisconnectedEvent,
        ChatwootMessageCreatedEvent,
        ChatwootMessageUpdatedEvent,
        ChatwootRealtimeEvent,
        ChatwootSubscriptionConfirmedEvent,
        ChatwootSubscriptionRejectedEvent,
        ChatwootTypingEvent;

/// Active ActionCable realtime connection for a single Chatwoot contact scope.
abstract interface class ChatwootRealtimeConnection {
  Stream<ChatwootRealtimeEvent> get events;
  Future<void> get done;
  bool get isClosed;
  Future<void> sendPresence();
  Future<void> close();
}

/// Abstract Chatwoot Widget REST service contract.
abstract class ChatwootService {
  Future<
      ({
        ChatwootChannelConfig config,
        String authToken,
        ChatwootContact contact,
      })> initializeSession({
    required Uri baseUrl,
    required String websiteToken,
    String? authToken,
  });

  Future<ChatwootContact?> updateContact({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  });

  Future<ChatwootConversation?> fetchConversation({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  });

  Future<List<ChatwootMessage>> fetchMessages({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  });

  Future<ChatwootMessage> sendMessage({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    required String content,
    required String echoId,
  });

  Future<void> updateLastSeen({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  });

  void close();
}

/// Dio-backed Chatwoot Widget REST client with proxy-to-DIRECT pre-request
/// fallback, strict platform TLS verification, and token-safe error handling.
class DioChatwootService implements ChatwootService {
  DioChatwootService({
    Dio? dio,
    bool Function()? shouldFallbackToDirect,
    @visibleForTesting Dio? directDio,
  })  : _ownsTransport = dio == null,
        _shouldFallbackToDirect = shouldFallbackToDirect,
        _dio = dio ?? Dio(),
        _directDio = directDio {
    if (_ownsTransport) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => wrapPreRequestHttpClient(
          HttpClient()..badCertificateCallback = ((_, __, ___) => false),
        ),
      );
    }
    _dio.interceptors.clear();
    _dio.options = _buildBaseOptions(
      connectTimeout: _ownsTransport
          ? const Duration(seconds: 6)
          : const Duration(seconds: 15),
    );
    if (_directDio != null) {
      _directDio!
        ..interceptors.clear()
        ..options = _buildBaseOptions(
          connectTimeout: const Duration(seconds: 10),
        );
    }
  }

  static BaseOptions _buildBaseOptions({
    Duration connectTimeout = const Duration(seconds: 15),
  }) =>
      BaseOptions(
        connectTimeout: connectTimeout,
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
        headers: {'Accept': Headers.jsonContentType},
      );

  final Dio _dio;
  final bool _ownsTransport;
  final bool Function()? _shouldFallbackToDirect;
  Dio? _directDio;
  bool _closed = false;

  @override
  void close() {
    _closed = true;
    _dio.close(force: true);
    final direct = _directDio;
    _directDio = null;
    direct?.close(force: true);
  }

  Dio _ensureDirectDio() {
    if (_closed) {
      throw const ChatwootException(
        code: 'connection_error',
        message: '无法连接在线客服，请检查网络后重试',
      );
    }
    final existing = _directDio;
    if (existing != null) return existing;
    final direct = Dio(_buildBaseOptions())
      ..interceptors.clear()
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => wrapPreRequestHttpClient(
          HttpClient()
            ..findProxy = ((_) => 'DIRECT')
            ..badCertificateCallback = ((_, __, ___) => false),
        ),
      );
    _directDio = direct;
    return direct;
  }

  bool _canFallbackToDirect(
    DioException error, {
    bool nonIdempotent = false,
  }) {
    if (nonIdempotent ||
        _closed ||
        (!_ownsTransport && _directDio == null) ||
        !(_shouldFallbackToDirect?.call() ?? false)) {
      return false;
    }
    if (isCertificateDioFailure(error)) return false;
    return isPreRequestDioFailure(error);
  }

  Uri _endpointUri(
    Uri baseUrl,
    String apiPath,
    String websiteToken, {
    Map<String, String>? extraQuery,
  }) {
    final valid = validateChatwootBaseUrl(baseUrl);
    final trimmedToken = websiteToken.trim();
    if (trimmedToken.isEmpty) {
      throw ArgumentError.value(
        websiteToken,
        'websiteToken',
        'Chatwoot websiteToken must not be empty',
      );
    }
    final basePath = valid.path == '/' ? '' : valid.path;
    return valid.replace(
      path: '$basePath$apiPath',
      queryParameters: {
        'website_token': trimmedToken,
        ...?extraQuery,
      },
    );
  }

  Future<Response<Object?>> _performRequest(
    Dio client,
    Uri uri, {
    required String method,
    String? authToken,
    Object? data,
  }) =>
      client.requestUri<Object?>(
        uri,
        data: data,
        options: Options(
          method: method,
          followRedirects: false,
          maxRedirects: 0,
          headers: {
            if (authToken != null && authToken.isNotEmpty)
              'X-Auth-Token': authToken,
          },
        ),
      );

  Future<T> _request<T>(
    Uri baseUrl,
    String path, {
    required String websiteToken,
    String method = 'GET',
    String? authToken,
    bool requireAuthToken = false,
    Object? data,
    Map<String, String>? query,
    bool allowNotFound = false,
    bool resolvedLockOnForbidden = false,
    bool nonIdempotent = false,
    required T Function(int status, Object? body) parse,
  }) async {
    if (_closed) {
      throw const ChatwootException(
        code: 'connection_error',
        message: '无法连接在线客服，请检查网络后重试',
      );
    }
    if (requireAuthToken && (authToken == null || authToken.trim().isEmpty)) {
      throw const ChatwootException(
        code: 'unauthorized',
        message: '客服会话已失效，请重新打开会话',
        statusCode: 401,
        isUnauthorized: true,
      );
    }

    final uri = _endpointUri(
      baseUrl,
      path,
      websiteToken,
      extraQuery: query,
    );

    int? status;
    try {
      Response<Object?> response;
      try {
        response = await _performRequest(
          _dio,
          uri,
          method: method,
          authToken: authToken,
          data: data,
        );
      } on DioException catch (error) {
        if (!_canFallbackToDirect(error, nonIdempotent: nonIdempotent)) rethrow;
        response = await _performRequest(
          _ensureDirectDio(),
          uri,
          method: method,
          authToken: authToken,
          data: data,
        );
      }

      status = response.statusCode;
      if (status == null) {
        throw const FormatException('Missing HTTP status code');
      }
      if (status >= 300 && status < 400) {
        throw ChatwootException(
          code: 'redirect_blocked',
          message: '客服服务返回了重定向响应，请检查服务地址配置',
          statusCode: status,
        );
      }
      if (status == 404) {
        if (allowNotFound) {
          return parse(status, _tryDecodeBodyIfJsonString(response.data));
        }
        throw const ChatwootException(
          code: 'not_found',
          message: '客服会话或联系人不存在，正在重新建立连接',
          statusCode: 404,
        );
      }
      if (status == 401) {
        throw const ChatwootException(
          code: 'unauthorized',
          message: '客服会话已失效，正在重新建立连接',
          statusCode: 401,
          isUnauthorized: true,
        );
      }
      if (status == 403) {
        final decodedBody = _tryDecodeBodyIfJsonString(response.data);
        final isResolved = resolvedLockOnForbidden ||
            _looksLikeResolvedError(decodedBody);
        throw ChatwootException(
          code: isResolved ? 'conversation_resolved' : 'forbidden',
          message: isResolved ? '当前会话已结束，请发起新会话' : '当前无权访问客服会话',
          statusCode: 403,
          isResolvedLocked: isResolved,
        );
      }
      if (status == 429) {
        throw const ChatwootException(
          code: 'rate_limited',
          message: '操作过于频繁，请稍后再试',
          statusCode: 429,
        );
      }
      if (status < 200 || status >= 300) {
        throw ChatwootException(
          code: status >= 500 ? 'server_error' : 'request_failed',
          message: status >= 500
              ? '在线客服服务暂时不可用，请稍后重试'
              : '客服请求未完成，请稍后重试',
          statusCode: status,
        );
      }

      final decoded = _decodeBodyIfJsonString(response.data);
      return parse(status, decoded);
    } on ChatwootException {
      rethrow;
    } on FormatException {
      throw ChatwootException(
        code: 'invalid_response',
        message: '客服服务响应格式异常',
        statusCode: status,
      );
    } on DioException catch (error) {
      // Never propagate DioException directly: it can contain X-Auth-Token or PII.
      final certificate = isCertificateDioFailure(error);
      throw ChatwootException(
        code: certificate ? 'certificate_error' : 'connection_error',
        message: certificate
            ? '客服服务安全证书验证失败'
            : '无法连接在线客服，请检查网络后重试',
        statusCode: error.response?.statusCode,
      );
    }
  }

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
  }) =>
      _request(
        baseUrl,
        '/api/v1/widget/config',
        websiteToken: websiteToken,
        method: 'POST',
        authToken: authToken,
        data: const <String, Object?>{},
        parse: (_, body) {
          final root = _asObject(body);
          final channelRaw = _asNullableObject(
                root['website_channel_config'],
              ) ??
              root;
          final config = ChatwootChannelConfig(
            baseUrl: baseUrl,
            websiteToken: websiteToken,
            websiteName: _optionalString(channelRaw, 'website_name'),
            welcomeTitle: _optionalString(channelRaw, 'welcome_title'),
            welcomeTagline: _optionalString(channelRaw, 'welcome_tagline'),
            replyTime: _optionalString(channelRaw, 'reply_time'),
            allowMessagesAfterResolved:
                _optionalBool(channelRaw, 'allow_messages_after_resolved') ??
                    true,
            outOfOfficeMessage:
                _optionalString(channelRaw, 'out_of_office_message'),
          );

          final resolvedAuthToken = _optionalString(channelRaw, 'auth_token') ??
              _optionalString(root, 'auth_token') ??
              (authToken != null && authToken.trim().isNotEmpty
                  ? authToken.trim()
                  : null);
          if (resolvedAuthToken == null) {
            throw const FormatException('Missing auth_token in widget config');
          }

          final contactRaw = _asNullableObject(root['contact']) ??
              _asNullableObject(root['current_contact']);
          if (contactRaw == null) {
            throw const FormatException('Missing contact in widget config');
          }
          final contact = _parseContact(
            contactRaw,
            fallbackPubsubToken: _optionalString(root, 'pubsub_token'),
          );
          return (
            config: config,
            authToken: resolvedAuthToken,
            contact: contact,
          );
        },
      );

  @override
  Future<ChatwootContact?> updateContact({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  }) {
    final payload = <String, Object?>{
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (customAttributes != null && customAttributes.isNotEmpty)
        'custom_attributes': Map<String, Object?>.from(customAttributes),
    };
    return _request<ChatwootContact?>(
      baseUrl,
      '/api/v1/widget/contact',
      websiteToken: websiteToken,
      method: 'PATCH',
      authToken: authToken,
      requireAuthToken: true,
      data: payload,
      parse: (_, body) {
        if (body == null) return null;
        final root = _asNullableObject(body);
        if (root == null) return null;
        final candidate = _asNullableObject(root['contact']) ??
            _asNullableObject(root['payload']) ??
            root;
        if (candidate['id'] is int &&
            _optionalString(candidate, 'pubsub_token') != null) {
          return _parseContact(candidate);
        }
        return null;
      },
    );
  }

  @override
  Future<ChatwootConversation?> fetchConversation({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) =>
      _request<ChatwootConversation?>(
        baseUrl,
        '/api/v1/widget/conversations',
        websiteToken: websiteToken,
        authToken: authToken,
        requireAuthToken: true,
        parse: (status, body) {
          if (body == null) return null;
          final root = _asNullableObject(body);
          if (root == null || root.isEmpty) return null;
          final payload = _asNullableObject(root['payload']) ?? root;
          if (payload.isEmpty ||
              (payload['id'] == null && payload['status'] == null)) {
            return null;
          }
          return _parseConversation(payload);
        },
      );

  @override
  Future<List<ChatwootMessage>> fetchMessages({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    int? before,
    int? after,
  }) =>
      _request<List<ChatwootMessage>>(
        baseUrl,
        '/api/v1/widget/messages',
        websiteToken: websiteToken,
        authToken: authToken,
        requireAuthToken: true,
        query: {
          if (before != null) 'before': '$before',
          if (after != null) 'after': '$after',
        },
        parse: (_, body) {
          final List<Object?> rawList;
          if (body is List) {
            rawList = body.cast<Object?>();
          } else {
            final root = _asObject(body);
            final payload = root['payload'];
            if (payload is! List) {
              throw const FormatException('Missing messages payload list');
            }
            rawList = payload.cast<Object?>();
          }
          final messages = <ChatwootMessage>[];
          for (final item in rawList) {
            final map = _asObject(item);
            final parsed = _tryParseMessage(map);
            if (parsed != null && !parsed.isPrivate) {
              messages.add(parsed);
            }
          }
          return List<ChatwootMessage>.unmodifiable(messages);
        },
      );

  @override
  Future<ChatwootMessage> sendMessage({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
    required String content,
    required String echoId,
  }) =>
      _request<ChatwootMessage>(
        baseUrl,
        '/api/v1/widget/messages',
        websiteToken: websiteToken,
        method: 'POST',
        authToken: authToken,
        requireAuthToken: true,
        resolvedLockOnForbidden: true,
        nonIdempotent: true,
        data: {
          'message': {
            'content': content,
            'echo_id': echoId,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          },
        },
        parse: (_, body) {
          final root = _asObject(body);
          final payload = _asNullableObject(root['payload']) ??
              _asNullableObject(root['message']) ??
              root;
          final parsed = _parseMessage(
            payload,
            fallbackEchoId: echoId,
            fallbackContent: content,
          );
          return parsed.copyWith(deliveryState: ChatwootDeliveryState.sent);
        },
      );

  @override
  Future<void> updateLastSeen({
    required Uri baseUrl,
    required String websiteToken,
    required String authToken,
  }) async {
    if (_closed || authToken.trim().isEmpty) return;
    try {
      await _request<void>(
        baseUrl,
        '/api/v1/widget/conversations/update_last_seen',
        websiteToken: websiteToken,
        method: 'POST',
        authToken: authToken,
        requireAuthToken: true,
        data: {
          'contact_last_seen_at':
              DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        },
        parse: (_, __) {},
      );
    } on ChatwootException {
      // Best-effort presence/read-receipt update.
    }
  }
}

/// ActionCable WebSocket realtime client for Chatwoot `RoomChannel`.
class ActionCableChatwootRealtime implements ChatwootRealtimeConnection {
  ActionCableChatwootRealtime._(
    this._socket,
    this._pubsubToken,
    this._ownedClients, {
    Duration pingTimeout = const Duration(seconds: 20),
    Duration closeTimeout = const Duration(seconds: 2),
  })  : _pingTimeout = pingTimeout,
        _closeTimeout = closeTimeout {
    _identifier = jsonEncode({
      'channel': 'RoomChannel',
      'pubsub_token': _pubsubToken,
    });
    _subscription = _socket.listen(
      _handleFrame,
      onError: (Object _) => _handleDisconnect(),
      onDone: _handleDisconnect,
      cancelOnError: true,
    );
    _resetPingWatchdog();
  }

  final WebSocket _socket;
  final String _pubsubToken;
  final List<HttpClient> _ownedClients;
  final Duration _pingTimeout;
  final Duration _closeTimeout;
  late final String _identifier;
  late final StreamSubscription<dynamic> _subscription;
  final StreamController<ChatwootRealtimeEvent> _controller =
      StreamController<ChatwootRealtimeEvent>.broadcast();
  final Completer<void> _doneCompleter = Completer<void>();

  Timer? _pingWatchdogTimer;
  bool _closed = false;
  bool _disconnecting = false;
  bool _subscribeSent = false;

  /// Connects to `wss://<baseUrl.host>(:<port>)/cable` with strict TLS and
  /// optional proxy-to-DIRECT fallback on pre-handshake connection failures.
  static Future<ActionCableChatwootRealtime> connect({
    required Uri baseUrl,
    required String pubsubToken,
    bool Function()? shouldFallbackToDirect,
    Duration connectTimeout = const Duration(seconds: 8),
    Duration pingTimeout = const Duration(seconds: 20),
    Future<void>? cancelSignal,
    @visibleForTesting Duration closeTimeout = const Duration(seconds: 2),
    @visibleForTesting
    Future<WebSocket> Function(String url, HttpClient client)?
        webSocketConnector,
  }) async {
    final validBase = validateChatwootBaseUrl(baseUrl);
    final trimmedPubsub = pubsubToken.trim();
    if (trimmedPubsub.isEmpty) {
      throw ArgumentError.value(
        pubsubToken,
        'pubsubToken',
        'Chatwoot pubsubToken must not be empty',
      );
    }

    final basePath = validBase.path == '/' ? '' : validBase.path;
    final wsUri = Uri(
      scheme: 'wss',
      host: validBase.host,
      port: validBase.hasPort ? validBase.port : null,
      path: '$basePath/cable',
    );
    final connectFn = webSocketConnector ??
        (String url, HttpClient client) =>
            WebSocket.connect(url, customClient: client);

    Future<void> closeOrphanSocket(WebSocket socket) async {
      try {
        await socket.close().timeout(closeTimeout);
      } on Object {
        // Best-effort close for late-arriving socket after timeout/cancellation.
      }
    }

    var cancelled = false;
    HttpClient? activeClient;

    void triggerCancel() {
      cancelled = true;
      activeClient?.close(force: true);
    }

    Future<WebSocket> attemptConnect(HttpClient client) async {
      if (cancelled) {
        client.close(force: true);
        throw const ChatwootException(
          code: 'realtime_cancelled',
          message: '客服实时连接已取消',
        );
      }
      activeClient = client;
      var timedOut = false;
      final rawFuture = connectFn(wsUri.toString(), client);
      unawaited(
        rawFuture.then(
          (socket) {
            if (timedOut || cancelled) {
              unawaited(closeOrphanSocket(socket));
            }
          },
          onError: (Object _) {},
        ),
      );

      final guarded = rawFuture.timeout(
        connectTimeout,
        onTimeout: () {
          timedOut = true;
          client.close(force: true);
          throw TimeoutException(
            'ActionCable connect timed out',
            connectTimeout,
          );
        },
      );

      if (cancelSignal == null) {
        final socket = await guarded;
        if (cancelled) {
          unawaited(closeOrphanSocket(socket));
          client.close(force: true);
          throw const ChatwootException(
            code: 'realtime_cancelled',
            message: '客服实时连接已取消',
          );
        }
        return socket;
      }

      final race = Completer<WebSocket>();
      unawaited(
        guarded.then(
          (socket) {
            if (cancelled || timedOut || race.isCompleted) {
              unawaited(closeOrphanSocket(socket));
              return;
            }
            race.complete(socket);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!race.isCompleted) {
              race.completeError(error, stackTrace);
            }
          },
        ),
      );
      unawaited(
        cancelSignal.then(
          (_) {
            triggerCancel();
            if (!race.isCompleted) {
              race.completeError(
                const ChatwootException(
                  code: 'realtime_cancelled',
                  message: '客服实时连接已取消',
                ),
              );
            }
          },
          onError: (Object _) {},
        ),
      );
      return race.future;
    }

    final primaryClient = HttpClient()
      ..connectionTimeout = connectTimeout
      ..badCertificateCallback = ((_, __, ___) => false);

    try {
      // Closed by ActionCableChatwootRealtime.close().
      // ignore: close_sinks
      final socket = await attemptConnect(primaryClient);
      activeClient = null;
      return ActionCableChatwootRealtime._(
        socket,
        trimmedPubsub,
        [primaryClient],
        pingTimeout: pingTimeout,
        closeTimeout: closeTimeout,
      );
    } on Object catch (error) {
      activeClient = null;
      primaryClient.close(force: true);
      if (cancelled ||
          (error is ChatwootException && error.code == 'realtime_cancelled')) {
        throw const ChatwootException(
          code: 'realtime_cancelled',
          message: '客服实时连接已取消',
        );
      }
      if (isCertificateTransportError(error)) {
        throw const ChatwootException(
          code: 'certificate_error',
          message: '客服实时连接证书验证失败',
        );
      }
      if (!(shouldFallbackToDirect?.call() ?? false)) {
        throw const ChatwootException(
          code: 'realtime_connection_error',
          message: '无法建立客服实时连接',
        );
      }

      final directClient = HttpClient()
        ..connectionTimeout = connectTimeout
        ..findProxy = ((_) => 'DIRECT')
        ..badCertificateCallback = ((_, __, ___) => false);
      try {
        // Closed by ActionCableChatwootRealtime.close().
        // ignore: close_sinks
        final socket = await attemptConnect(directClient);
        activeClient = null;
        return ActionCableChatwootRealtime._(
          socket,
          trimmedPubsub,
          [directClient],
          pingTimeout: pingTimeout,
          closeTimeout: closeTimeout,
        );
      } on Object catch (directError) {
        activeClient = null;
        directClient.close(force: true);
        if (cancelled ||
            (directError is ChatwootException &&
                directError.code == 'realtime_cancelled')) {
          throw const ChatwootException(
            code: 'realtime_cancelled',
            message: '客服实时连接已取消',
          );
        }
        if (isCertificateTransportError(directError)) {
          throw const ChatwootException(
            code: 'certificate_error',
            message: '客服实时连接证书验证失败',
          );
        }
        throw const ChatwootException(
          code: 'realtime_connection_error',
          message: '无法建立客服实时连接',
        );
      }
    }
  }

  @override
  Stream<ChatwootRealtimeEvent> get events => _controller.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  bool get isClosed => _closed;

  void _resetPingWatchdog() {
    _pingWatchdogTimer?.cancel();
    if (_closed || _disconnecting || _pingTimeout <= Duration.zero) {
      return;
    }
    _pingWatchdogTimer = Timer(_pingTimeout, () {
      if (_closed || _disconnecting) return;
      _emitDisconnectedAndClose(reconnect: true, reason: 'ping_timeout');
    });
  }

  void _sendSubscribe() {
    if (_closed || _subscribeSent) return;
    _subscribeSent = true;
    _socket.add(
      jsonEncode({
        'command': 'subscribe',
        'identifier': _identifier,
      }),
    );
  }

  @override
  Future<void> sendPresence() async {
    if (_closed) return;
    try {
      _socket.add(
        jsonEncode({
          'command': 'message',
          'identifier': _identifier,
          'data': jsonEncode({'action': 'update_presence'}),
        }),
      );
    } on Object {
      // Ignore send failure when socket is tearing down.
    }
  }

  void _handleFrame(dynamic raw) {
    if (_closed || _disconnecting || raw is! String) return;
    _resetPingWatchdog();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final frame = decoded.cast<String, Object?>();
      final type = frame['type'];
      if (type is String) {
        switch (type) {
          case 'welcome':
            _sendSubscribe();
            return;
          case 'ping':
            return;
          case 'confirm_subscription':
            if (!_controller.isClosed) {
              _controller.add(const ChatwootSubscriptionConfirmedEvent());
            }
            return;
          case 'reject_subscription':
            if (!_controller.isClosed) {
              _controller.add(const ChatwootSubscriptionRejectedEvent());
            }
            return;
          case 'disconnect':
            final reconnectRaw = frame['reconnect'];
            final reconnect = reconnectRaw is bool ? reconnectRaw : true;
            final reasonRaw = frame['reason'];
            final reason = reasonRaw is String && reasonRaw.trim().isNotEmpty
                ? reasonRaw.trim()
                : null;
            _emitDisconnectedAndClose(reconnect: reconnect, reason: reason);
            return;
        }
      }

      final payload = _asNullableObject(frame['message']);
      if (payload == null) return;
      final eventName = _optionalString(payload, 'event');
      final data =
          _asNullableObject(payload['data']) ?? const <String, Object?>{};
      final conversationId = _extractConversationId(data);
      switch (eventName) {
        case 'message.created':
          final msg = _tryParseMessage(data);
          if (msg != null && !msg.isPrivate && !_controller.isClosed) {
            _controller.add(
              ChatwootMessageCreatedEvent(
                msg,
                conversationId: conversationId,
              ),
            );
          }
        case 'message.updated':
          final msg = _tryParseMessage(data);
          if (msg != null && !msg.isPrivate && !_controller.isClosed) {
            _controller.add(
              ChatwootMessageUpdatedEvent(
                msg,
                conversationId: conversationId,
              ),
            );
          }
        case 'conversation.typing_on':
          if (data['is_private'] == true || data['private'] == true) {
            return;
          }
          if (!_controller.isClosed) {
            _controller.add(
              ChatwootTypingEvent(
                isTyping: true,
                senderName: _extractActorName(data),
                conversationId: conversationId,
              ),
            );
          }
        case 'conversation.typing_off':
          if (data['is_private'] == true || data['private'] == true) {
            return;
          }
          if (!_controller.isClosed) {
            _controller.add(
              ChatwootTypingEvent(
                isTyping: false,
                senderName: _extractActorName(data),
                conversationId: conversationId,
              ),
            );
          }
        case 'conversation.status_changed':
          final status = _parseConversationStatus(data['status']);
          if (status != null && !_controller.isClosed) {
            final convId = _optionalInt(data, 'id') ?? conversationId;
            _controller.add(
              ChatwootConversationStatusChangedEvent(
                conversationId: convId,
                status: status,
              ),
            );
          }
        case 'contact.merged':
          if (!_controller.isClosed) {
            _controller.add(
              ChatwootContactMergedEvent(
                contactId: _optionalInt(data, 'id') ??
                    _optionalInt(data, 'contact_id'),
                pubsubToken: _optionalString(data, 'pubsub_token'),
              ),
            );
          }
      }
    } on FormatException {
      return;
    }
  }

  void _emitDisconnectedAndClose({
    required bool reconnect,
    String? reason,
  }) {
    if (_closed || _disconnecting) return;
    _disconnecting = true;
    _pingWatchdogTimer?.cancel();
    if (!_controller.isClosed) {
      _controller.add(
        ChatwootDisconnectedEvent(reconnect: reconnect, reason: reason),
      );
    }
    unawaited(close());
  }

  void _handleDisconnect() {
    _emitDisconnectedAndClose(reconnect: true);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pingWatchdogTimer?.cancel();
    _pingWatchdogTimer = null;
    try {
      await _subscription.cancel();
    } on Object {
      // Ignore stream subscription cancel errors during teardown.
    }
    try {
      await _socket.close().timeout(_closeTimeout);
    } on Object {
      // Ignore socket close failures or timeouts during teardown.
    }
    for (final client in _ownedClients) {
      client.close(force: true);
    }
    if (!_controller.isClosed) {
      await _controller.close();
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}

int? _extractConversationId(Map<String, Object?> data) {
  final direct = _optionalInt(data, 'conversation_id');
  if (direct != null) return direct;
  final conversation = _asNullableObject(data['conversation']);
  return conversation == null ? null : _optionalInt(conversation, 'id');
}

Object? _tryDecodeBodyIfJsonString(Object? body) {
  try {
    return _decodeBodyIfJsonString(body);
  } on FormatException {
    return null;
  }
}

Object? _decodeBodyIfJsonString(Object? body) {
  if (body is String) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    return jsonDecode(trimmed);
  }
  return body;
}

bool _looksLikeResolvedError(Object? body) {
  final map = _asNullableObject(body);
  if (map == null) return false;
  final text =
      '${map['error'] ?? ''} ${map['message'] ?? ''}'.toLowerCase();
  return text.contains('resolved') || text.contains('closed');
}

Map<String, Object?> _asObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected JSON object');
  }
  return value.cast<String, Object?>();
}

Map<String, Object?>? _asNullableObject(Object? value) {
  if (value is! Map) return null;
  return value.cast<String, Object?>();
}

String? _optionalString(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Expected string for $key');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optionalInt(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

bool? _optionalBool(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('Expected bool for $key');
}

ChatwootContact _parseContact(
  Map<String, Object?> data, {
  String? fallbackPubsubToken,
}) {
  final id = data['id'];
  if (id is! int || id <= 0) {
    throw const FormatException('Invalid contact id');
  }
  final pubsubToken =
      _optionalString(data, 'pubsub_token') ?? fallbackPubsubToken;
  if (pubsubToken == null) {
    throw const FormatException('Missing contact pubsub_token');
  }
  return ChatwootContact(
    id: id,
    name: _optionalString(data, 'name'),
    email: _optionalString(data, 'email'),
    pubsubToken: pubsubToken,
  );
}

String? _parseConversationStatus(Object? raw) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.trim().toLowerCase();
  }
  if (raw is int) {
    return switch (raw) {
      0 => 'open',
      1 => 'resolved',
      2 => 'pending',
      3 => 'snoozed',
      _ => null,
    };
  }
  return null;
}

ChatwootConversation _parseConversation(Map<String, Object?> data) {
  final status = _parseConversationStatus(data['status']) ?? 'open';
  final idValue = data['id'];
  final id = idValue is int ? idValue : null;
  final lastSeen = _optionalInt(data, 'contact_last_seen_at');
  return ChatwootConversation(
    id: id,
    status: status,
    contactLastSeenAt: lastSeen,
  );
}

DateTime _parseTimestamp(Object? value) {
  if (value is int) {
    final millis = value > 1000000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  if (value is double) {
    final millis = value > 1000000000000
        ? value.round()
        : (value * 1000).round();
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Invalid Chatwoot timestamp: $value');
}

ChatwootMessage? _tryParseMessage(Map<String, Object?> data) {
  try {
    return _parseMessage(data);
  } on FormatException {
    return null;
  }
}

ChatwootMessage _parseMessage(
  Map<String, Object?> data, {
  String? fallbackEchoId,
  String? fallbackContent,
}) {
  final idRaw = data['id'];
  final id = idRaw is int ? idRaw : null;
  final contentAttrs = _asNullableObject(data['content_attributes']);
  final echoId = _optionalString(data, 'echo_id') ??
      (contentAttrs == null ? null : _optionalString(contentAttrs, 'echo_id')) ??
      fallbackEchoId;
  final rawContent = data['content'];
  final content = rawContent is String
      ? rawContent
      : (fallbackContent ?? '');
  final type = ChatwootMessageType.parse(data['message_type']);
  final createdAt = data['created_at'] != null
      ? _parseTimestamp(data['created_at'])
      : DateTime.now().toUtc();
  final sender = _asNullableObject(data['sender']);
  final senderName = sender == null
      ? null
      : (_optionalString(sender, 'available_name') ??
          _optionalString(sender, 'name'));
  final isPrivate = (data['private'] == true) || (data['is_private'] == true);

  return ChatwootMessage(
    id: id,
    echoId: echoId,
    content: content,
    type: type,
    createdAt: createdAt,
    senderName: senderName,
    deliveryState: ChatwootDeliveryState.sent,
    isPrivate: isPrivate,
  );
}

String? _extractActorName(Map<String, Object?> data) {
  final user = _asNullableObject(data['user']) ??
      _asNullableObject(data['performer']) ??
      _asNullableObject(data['sender']);
  if (user == null) return null;
  return _optionalString(user, 'available_name') ??
      _optionalString(user, 'name');
}
