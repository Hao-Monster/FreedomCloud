import 'dart:async';

import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flutter/foundation.dart';

typedef ChatwootRealtimeConnector = Future<ChatwootRealtimeConnection> Function(
  Uri baseUrl,
  String pubsubToken,
);

/// Manages pure-Flutter Chatwoot support state with strict per-account session
/// isolation, lazy connection (zero active sockets/timers when closed),
/// optimistic message reconciliation, and bounded reconnect backoff.
class SupportManager extends ChangeNotifier {
  SupportManager({
    ChatwootService? service,
    ChatwootSessionStorage? storage,
    ChatwootRealtimeConnector? realtimeConnector,
    this.presenceInterval = const Duration(seconds: 60),
    Duration typingExpiry = const Duration(seconds: 6),
    Duration lastSeenDebounce = const Duration(milliseconds: 500),
    String Function()? echoIdGenerator,
  })  : _service = service ?? DioChatwootService(),
        _ownsService = service == null,
        _storage = storage ?? SecureChatwootSessionStorage(),
        _realtimeConnector = realtimeConnector ??
            ((Uri baseUrl, String pubsubToken) =>
                ActionCableChatwootRealtime.connect(
                  baseUrl: baseUrl,
                  pubsubToken: pubsubToken,
                )),
        _typingExpiry = typingExpiry,
        _lastSeenDebounce = lastSeenDebounce,
        _echoIdGenerator = echoIdGenerator;

  static const List<int> _reconnectBackoffSeconds = [1, 2, 4, 8, 15];

  final ChatwootService _service;
  final bool _ownsService;
  final ChatwootSessionStorage _storage;
  final ChatwootRealtimeConnector _realtimeConnector;
  final Duration presenceInterval;
  final Duration _typingExpiry;
  final Duration _lastSeenDebounce;
  final String Function()? _echoIdGenerator;

  ChatwootChannelConfig? _channelConfig;
  String _scopeKey = 'guest';
  String? _boundEmail;
  String? _boundName;
  Map<String, Object?>? _boundCustomAttributes;

  ChatwootSession? _session;
  ChatwootContact? _contact;
  ChatwootConversation? _conversation;
  final List<ChatwootMessage> _messages = [];
  ChatwootException? _error;

  bool _isPanelOpen = false;
  bool _loading = false;
  bool _connecting = false;
  bool _realtimeConnected = false;
  bool _isAgentTyping = false;
  String? _typingAgentName;
  bool _resolvedLocked = false;
  bool _conversationLoaded = false;
  String? _contactSyncedScopeKey;
  String? _pendingDraft;

  int _epoch = 0;
  int _echoSequence = 0;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  Future<void>? _bootstrapInFlight;
  int? _bootstrapEpoch;

  ChatwootRealtimeConnection? _realtimeConnection;
  // Cancelled in _teardownRealtimeResourcesSync / _teardownRealtimeResourcesAsync.
  // ignore: cancel_subscriptions
  StreamSubscription<ChatwootRealtimeEvent>? _realtimeSub;
  Timer? _presenceTimer;
  Timer? _typingTimer;
  Timer? _reconnectTimer;
  Timer? _lastSeenTimer;

  ChatwootChannelConfig? get channelConfig => _channelConfig;
  bool get isConfigured => _channelConfig != null;
  String get scopeKey => _scopeKey;
  String? get boundEmail => _boundEmail;
  bool get isPanelOpen => _isPanelOpen;
  bool get isLoading => _loading;
  bool get isConnecting => _connecting;
  bool get isRealtimeConnected => _realtimeConnected;
  bool get isAgentTyping => _isAgentTyping;
  String? get typingAgentName => _typingAgentName;
  ChatwootContact? get contact => _contact;
  ChatwootConversation? get conversation => _conversation;
  bool get isConversationResolved => _conversation?.isResolved ?? false;
  bool get isConversationLocked =>
      _resolvedLocked ||
      (isConversationResolved &&
          !(_channelConfig?.allowMessagesAfterResolved ?? true));

  /// Chronological message list ordered oldest -> newest.
  List<ChatwootMessage> get messages => List<ChatwootMessage>.unmodifiable(_messages);

  ChatwootException? get error => _error;
  String? get pendingDraft => _pendingDraft;

  /// Exposes whether any WebSocket connection, stream subscription, or active
  /// timer is currently alive (used by tests to assert zero idle resources).
  @visibleForTesting
  bool get hasActiveRealtimeResources =>
      _realtimeConnection != null ||
      _realtimeSub != null ||
      (_presenceTimer?.isActive ?? false) ||
      (_typingTimer?.isActive ?? false) ||
      (_reconnectTimer?.isActive ?? false) ||
      (_lastSeenTimer?.isActive ?? false);

  /// Updates the active Chatwoot channel configuration. Clears active channel
  /// and realtime resources if [baseUrl] or [websiteToken] is null or invalid.
  void configureChannel({
    Uri? baseUrl,
    String? websiteToken,
  }) {
    if (_disposed) return;
    final nextConfig = ChatwootChannelConfig.tryCreate(
      baseUrl: baseUrl,
      websiteToken: websiteToken,
    );
    if (nextConfig == null) {
      if (_channelConfig == null && !hasActiveRealtimeResources) return;
      _channelConfig = null;
      _resetScopeRuntimeState();
      _notify();
      return;
    }

    final current = _channelConfig;
    if (current != null &&
        current.baseUrl == nextConfig.baseUrl &&
        current.websiteToken == nextConfig.websiteToken) {
      return;
    }

    _channelConfig = nextConfig;
    _resetScopeRuntimeState();
    _notify();

    if (_isPanelOpen) {
      unawaited(_bootstrapSession());
    }
  }

  /// Binds support state to `'account:<accountId>'` or `'guest'`.
  ///
  /// Switching scopes immediately tears down any active realtime resources and
  /// clears in-memory messages from the previous scope. When the panel is
  /// closed, no network or socket work is started until [openPanel].
  void bindAccount({
    int? accountId,
    String? email,
    String? name,
    Map<String, Object?>? customAttributes,
  }) {
    if (_disposed) return;
    final nextScopeKey = accountId != null ? 'account:$accountId' : 'guest';
    final normalizedEmail = _normalizeOptionalString(email);
    final normalizedName = _normalizeOptionalString(name);

    if (nextScopeKey == _scopeKey) {
      final changed = _boundEmail != normalizedEmail ||
          _boundName != normalizedName ||
          !mapEquals(_boundCustomAttributes, customAttributes);
      _boundEmail = normalizedEmail;
      _boundName = normalizedName;
      _boundCustomAttributes = customAttributes == null
          ? null
          : Map<String, Object?>.unmodifiable(customAttributes);
      if (changed && _isPanelOpen && _session != null) {
        unawaited(_syncBoundContact(_epoch));
      }
      return;
    }

    _scopeKey = nextScopeKey;
    _boundEmail = normalizedEmail;
    _boundName = normalizedName;
    _boundCustomAttributes = customAttributes == null
        ? null
        : Map<String, Object?>.unmodifiable(customAttributes);
    _resetScopeRuntimeState();
    _notify();

    if (_isPanelOpen && _channelConfig != null) {
      unawaited(_bootstrapSession());
    }
  }

  /// Returns and clears any queued draft text for the support composer.
  String? takePendingDraft() {
    final draft = _pendingDraft;
    _pendingDraft = null;
    return draft;
  }

  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    _notify();
  }

  /// Opens the support panel, lazily bootstrapping the session, loading
  /// messages, and connecting the ActionCable WebSocket.
  Future<void> openPanel({String? initialDraft}) async {
    if (_disposed) return;
    _isPanelOpen = true;
    if (initialDraft != null && initialDraft.trim().isNotEmpty) {
      _pendingDraft = initialDraft;
    }
    _error = null;
    _notify();

    final config = _channelConfig;
    if (config == null) return;

    if (_session != null && _conversationLoaded) {
      final startEpoch = _epoch;
      if (_realtimeConnection == null && _contact != null) {
        await _connectRealtime(startEpoch);
      }
      if (!_disposed && _isPanelOpen && _epoch == startEpoch) {
        await refreshMessages();
        _scheduleLastSeen();
      }
      return;
    }

    await _bootstrapSession();
  }

  /// Closes the support panel and immediately destroys all sockets and timers
  /// so idle resource usage is zero.
  Future<void> closePanel() async {
    if (_disposed) return;
    _isPanelOpen = false;
    await _teardownRealtimeResourcesAsync();
    _notify();
  }

  /// Optimistically inserts a visitor message and reconciles it against REST
  /// and ActionCable responses using `echo_id` and `id`.
  Future<void> sendMessage(String text) async {
    if (_disposed) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final config = _channelConfig;
    if (config == null) {
      _error = const ChatwootException(
        code: 'not_configured',
        message: '在线客服暂未配置',
      );
      _notify();
      return;
    }

    if (_session == null) {
      await _bootstrapSession();
      if (_disposed || _session == null) return;
    }

    final startEpoch = _epoch;
    final echoId = _nextEchoId();
    final optimistic = ChatwootMessage(
      echoId: echoId,
      content: text,
      type: ChatwootMessageType.visitor,
      createdAt: DateTime.now().toUtc(),
      deliveryState: ChatwootDeliveryState.sending,
    );
    _error = null;
    _messages.add(optimistic);
    _sortMessages();
    _notify();

    await _dispatchSend(
      echoId: echoId,
      content: text,
      startEpoch: startEpoch,
    );
  }

  /// Retries a previously failed outgoing message identified by [echoId].
  Future<void> retryMessage(String echoId) async {
    if (_disposed) return;
    final index = _messages.indexWhere(
      (m) => m.echoId == echoId && m.deliveryState == ChatwootDeliveryState.failed,
    );
    if (index == -1) return;
    final failed = _messages[index];
    final startEpoch = _epoch;

    _error = null;
    _messages[index] = failed.copyWith(
      deliveryState: ChatwootDeliveryState.sending,
    );
    _notify();

    await _dispatchSend(
      echoId: echoId,
      content: failed.content,
      startEpoch: startEpoch,
    );
  }

  /// Fetches incremental messages (`after: lastServerMessageId`) when prior
  /// server messages exist, or performs a full initial load otherwise.
  Future<void> refreshMessages() async {
    if (_disposed) return;
    final config = _channelConfig;
    final session = _session;
    if (config == null || session == null) return;

    final startEpoch = _epoch;
    final afterId = _lastServerMessageId();
    try {
      final fetched = await _service.fetchMessages(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        authToken: session.authToken,
        after: afterId,
      );
      if (_disposed || _epoch != startEpoch) return;
      fetched.forEach(_upsertMessage);
      _sortMessages();
      _conversationLoaded = true;
      _error = null;
      _notify();
      if (fetched.isNotEmpty) {
        _scheduleLastSeen();
      }
    } on ChatwootException catch (e) {
      if (_disposed || _epoch != startEpoch) return;
      if (e.isUnauthorized) {
        await _handleUnauthorized(startEpoch);
        return;
      }
      _error = e;
      _notify();
    }
  }

  /// Clears the stored session for the active scope, resets conversation state,
  /// and bootstraps a fresh session when the panel is open.
  Future<void> startNewConversation() async {
    if (_disposed) return;
    final config = _channelConfig;
    if (config == null) return;

    final currentScope = _scopeKey;
    await _teardownRealtimeResourcesAsync();
    _resetScopeRuntimeState();
    _notify();

    await _storage.clearSession(
      baseUrl: config.baseUrl,
      websiteToken: config.websiteToken,
      scopeKey: currentScope,
    );

    if (!_disposed && _isPanelOpen && _scopeKey == currentScope) {
      await _bootstrapSession();
    }
  }

  Future<void> _bootstrapSession() {
    final existing = _bootstrapInFlight;
    if (existing != null && _bootstrapEpoch == _epoch) {
      return existing;
    }
    final startEpoch = _epoch;
    late final Future<void> future;
    future = _runBootstrap(startEpoch).whenComplete(() {
      if (identical(_bootstrapInFlight, future)) {
        _bootstrapInFlight = null;
        _bootstrapEpoch = null;
      }
    });
    _bootstrapInFlight = future;
    _bootstrapEpoch = startEpoch;
    return future;
  }

  Future<void> _runBootstrap(int startEpoch) async {
    final config = _channelConfig;
    if (config == null || _disposed || _epoch != startEpoch) return;

    _loading = true;
    _error = null;
    _notify();

    try {
      final scopeAtStart = _scopeKey;
      final stored = await _storage.readSession(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        scopeKey: scopeAtStart,
      );
      if (_disposed || _epoch != startEpoch) return;

      ({
        ChatwootChannelConfig config,
        String authToken,
        ChatwootContact contact,
      }) init;
      try {
        init = await _service.initializeSession(
          baseUrl: config.baseUrl,
          websiteToken: config.websiteToken,
          authToken: stored?.authToken,
        );
      } on ChatwootException catch (e) {
        if (!e.isUnauthorized || stored?.authToken == null) rethrow;
        await _storage.clearSession(
          baseUrl: config.baseUrl,
          websiteToken: config.websiteToken,
          scopeKey: scopeAtStart,
        );
        if (_disposed || _epoch != startEpoch) return;
        init = await _service.initializeSession(
          baseUrl: config.baseUrl,
          websiteToken: config.websiteToken,
        );
      }
      if (_disposed || _epoch != startEpoch) return;

      _channelConfig = init.config;
      _contact = init.contact;
      _session = ChatwootSession(
        authToken: init.authToken,
        pubsubToken: init.contact.pubsubToken,
        contactId: init.contact.id,
        scopeKey: scopeAtStart,
        boundEmail: _boundEmail ?? init.contact.email,
      );

      await _storage.saveSession(
        baseUrl: init.config.baseUrl,
        websiteToken: init.config.websiteToken,
        session: _session!,
      );
      if (_disposed || _epoch != startEpoch) return;

      await _syncBoundContact(startEpoch);
      if (_disposed || _epoch != startEpoch) return;

      final currentAuthToken = _session!.authToken;
      final convFuture = _service.fetchConversation(
        baseUrl: init.config.baseUrl,
        websiteToken: init.config.websiteToken,
        authToken: currentAuthToken,
      );
      final msgsFuture = _service.fetchMessages(
        baseUrl: init.config.baseUrl,
        websiteToken: init.config.websiteToken,
        authToken: currentAuthToken,
      );

      final conversation = await convFuture;
      final initialMessages = await msgsFuture;
      if (_disposed || _epoch != startEpoch) return;

      _conversation = conversation;
      _resolvedLocked =
          (conversation?.isResolved ?? false) &&
          !init.config.allowMessagesAfterResolved;
      initialMessages.forEach(_upsertMessage);
      _sortMessages();
      _conversationLoaded = true;
      _loading = false;
      _notify();

      if (!_isPanelOpen || _disposed || _epoch != startEpoch) return;

      final pubsub = _contact?.pubsubToken;
      if (pubsub != null && pubsub.isNotEmpty) {
        await _connectRealtime(startEpoch);
      }
      if (_isPanelOpen && !_disposed && _epoch == startEpoch && _messages.isNotEmpty) {
        _scheduleLastSeen();
      }
    } on ChatwootException catch (e) {
      if (_disposed || _epoch != startEpoch) return;
      _loading = false;
      _error = e;
      _notify();
    } on Object {
      if (_disposed || _epoch != startEpoch) return;
      _loading = false;
      _error = const ChatwootException(
        code: 'bootstrap_failed',
        message: '客服初始化失败，请稍后重试',
      );
      _notify();
    }
  }

  Future<void> _syncBoundContact(int startEpoch) async {
    final config = _channelConfig;
    final session = _session;
    if (config == null || session == null) return;
    if (_scopeKey == 'guest') return;
    final needsEmailSync = _boundEmail != null && _contact?.email != _boundEmail;
    final needsAttrSync = _boundCustomAttributes != null &&
        _boundCustomAttributes!.isNotEmpty &&
        _contactSyncedScopeKey != _scopeKey;
    final needsNameSync = _boundName != null && _contact?.name != _boundName;
    if (!needsEmailSync && !needsAttrSync && !needsNameSync && _contactSyncedScopeKey == _scopeKey) {
      return;
    }
    if (_boundEmail == null &&
        _boundName == null &&
        (_boundCustomAttributes == null || _boundCustomAttributes!.isEmpty)) {
      return;
    }

    try {
      final updated = await _service.updateContact(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        authToken: session.authToken,
        email: _boundEmail,
        name: _boundName,
        customAttributes: _boundCustomAttributes,
      );
      if (_disposed || _epoch != startEpoch) return;
      _contactSyncedScopeKey = _scopeKey;
      if (updated != null) {
        _contact = updated;
        _session = session.copyWith(
          pubsubToken: updated.pubsubToken,
          contactId: updated.id,
          boundEmail: _boundEmail ?? updated.email,
        );
        await _storage.saveSession(
          baseUrl: config.baseUrl,
          websiteToken: config.websiteToken,
          session: _session!,
        );
      }
    } on ChatwootException {
      // Do not block panel opening if optional contact metadata sync fails.
    }
  }

  Future<void> _dispatchSend({
    required String echoId,
    required String content,
    required int startEpoch,
  }) async {
    final config = _channelConfig;
    final session = _session;
    if (config == null || session == null) return;

    try {
      final serverMessage = await _service.sendMessage(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        authToken: session.authToken,
        content: content,
        echoId: echoId,
      );
      if (_disposed || _epoch != startEpoch) return;
      _reconcileSentMessage(echoId, serverMessage);
      _sortMessages();
      _error = null;
      _notify();
      _scheduleLastSeen();
    } on ChatwootException catch (e) {
      if (_disposed || _epoch != startEpoch) return;
      _markMessageFailed(echoId);
      if (e.isResolvedLocked) {
        _resolvedLocked = true;
        _conversation = (_conversation ?? const ChatwootConversation(status: 'resolved'))
            .copyWith(status: 'resolved');
      }
      if (e.isUnauthorized) {
        await _storage.clearSession(
          baseUrl: config.baseUrl,
          websiteToken: config.websiteToken,
          scopeKey: _scopeKey,
        );
      }
      _error = e;
      _notify();
    } on Object {
      if (_disposed || _epoch != startEpoch) return;
      _markMessageFailed(echoId);
      _error = const ChatwootException(
        code: 'send_failed',
        message: '消息发送失败，请重试',
      );
      _notify();
    }
  }

  Future<void> _connectRealtime(int startEpoch) async {
    final config = _channelConfig;
    final pubsubToken = _contact?.pubsubToken ?? _session?.pubsubToken;
    if (config == null ||
        pubsubToken == null ||
        pubsubToken.isEmpty ||
        !_isPanelOpen ||
        _disposed ||
        _epoch != startEpoch) {
      return;
    }

    await _teardownRealtimeResourcesAsync();
    if (!_isPanelOpen || _disposed || _epoch != startEpoch) return;

    _connecting = true;
    _notify();

    try {
      final connection = await _realtimeConnector(config.baseUrl, pubsubToken);
      if (!_isPanelOpen || _disposed || _epoch != startEpoch) {
        await connection.close();
        _connecting = false;
        _notify();
        return;
      }

      _realtimeConnection = connection;
      _connecting = false;
      _realtimeConnected = true;
      _reconnectAttempt = 0;

      _realtimeSub = connection.events.listen(
        (event) => _handleRealtimeEvent(event, startEpoch),
        onError: (Object _) => _handleRealtimeDropped(startEpoch),
        onDone: () => _handleRealtimeDropped(startEpoch),
      );

      _presenceTimer = Timer.periodic(presenceInterval, (_) {
        if (_isPanelOpen && !_disposed && _epoch == startEpoch) {
          unawaited(_realtimeConnection?.sendPresence());
        }
      });

      _notify();
    } on Object {
      if (_disposed || _epoch != startEpoch) return;
      _connecting = false;
      _realtimeConnected = false;
      _notify();
      if (_isPanelOpen) {
        _scheduleReconnect(startEpoch);
      }
    }
  }

  void _handleRealtimeEvent(ChatwootRealtimeEvent event, int startEpoch) {
    if (_disposed || _epoch != startEpoch) return;
    switch (event) {
      case ChatwootMessageCreatedEvent(:final message):
        if (message.isPrivate) return;
        _upsertMessage(message);
        _sortMessages();
        if (message.type == ChatwootMessageType.agent) {
          _typingTimer?.cancel();
          _typingTimer = null;
          _isAgentTyping = false;
          _typingAgentName = null;
        }
        _notify();
        _scheduleLastSeen();

      case ChatwootMessageUpdatedEvent(:final message):
        if (message.isPrivate) return;
        _upsertMessage(message);
        _sortMessages();
        _notify();

      case ChatwootTypingEvent(:final isTyping, :final senderName):
        _typingTimer?.cancel();
        _typingTimer = null;
        if (isTyping) {
          _isAgentTyping = true;
          _typingAgentName = senderName;
          _typingTimer = Timer(_typingExpiry, () {
            if (_disposed || _epoch != startEpoch) return;
            _isAgentTyping = false;
            _typingAgentName = null;
            _typingTimer = null;
            _notify();
          });
        } else {
          _isAgentTyping = false;
          _typingAgentName = null;
        }
        _notify();

      case ChatwootConversationStatusChangedEvent(
          :final conversationId,
          :final status,
        ):
        _conversation = ChatwootConversation(
          id: conversationId ?? _conversation?.id,
          status: status,
          contactLastSeenAt: _conversation?.contactLastSeenAt,
        );
        _resolvedLocked = status == 'resolved' &&
            !(_channelConfig?.allowMessagesAfterResolved ?? true);
        _notify();

      case ChatwootContactMergedEvent(:final contactId, :final pubsubToken):
        unawaited(_handleContactMerged(contactId, pubsubToken, startEpoch));

      case ChatwootSubscriptionRejectedEvent():
        _handleRealtimeDropped(startEpoch);
    }
  }

  Future<void> _handleContactMerged(
    int? contactId,
    String? pubsubToken,
    int startEpoch,
  ) async {
    if (_disposed || _epoch != startEpoch) return;
    final config = _channelConfig;
    final session = _session;
    if (config == null || session == null) return;

    final nextPubsub = (pubsubToken != null && pubsubToken.isNotEmpty)
        ? pubsubToken
        : (_contact?.pubsubToken ?? session.pubsubToken);
    final nextContactId = contactId ?? _contact?.id ?? session.contactId;

    if (nextContactId != null && nextPubsub != null) {
      _contact = (_contact ??
              ChatwootContact(
                id: nextContactId,
                pubsubToken: nextPubsub,
              ))
          .copyWith(id: nextContactId, pubsubToken: nextPubsub);
    }
    _session = session.copyWith(
      contactId: nextContactId,
      pubsubToken: nextPubsub,
    );
    await _storage.saveSession(
      baseUrl: config.baseUrl,
      websiteToken: config.websiteToken,
      session: _session!,
    );
    if (_disposed || _epoch != startEpoch) return;

    if (_isPanelOpen && pubsubToken != null && pubsubToken.isNotEmpty) {
      await _connectRealtime(startEpoch);
      if (!_disposed && _epoch == startEpoch) {
        await refreshMessages();
      }
    } else {
      _notify();
    }
  }

  void _handleRealtimeDropped(int startEpoch) {
    if (_disposed || _epoch != startEpoch) return;
    final conn = _realtimeConnection;
    final sub = _realtimeSub;
    _realtimeConnection = null;
    _realtimeSub = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _realtimeConnected = false;
    _connecting = false;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    if (conn != null) {
      unawaited(conn.close());
    }
    _notify();
    if (_isPanelOpen) {
      _scheduleReconnect(startEpoch);
    }
  }

  void _scheduleReconnect(int startEpoch) {
    if (_disposed || !_isPanelOpen || _epoch != startEpoch) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final clampedIndex = _reconnectAttempt.clamp(
      0,
      _reconnectBackoffSeconds.length - 1,
    );
    final delay = Duration(seconds: _reconnectBackoffSeconds[clampedIndex]);
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_disposed || !_isPanelOpen || _epoch != startEpoch) return;
      unawaited(() async {
        await _connectRealtime(startEpoch);
        if (!_disposed &&
            _isPanelOpen &&
            _epoch == startEpoch &&
            _realtimeConnected) {
          await refreshMessages();
        }
      }());
    });
  }

  Future<void> _handleUnauthorized(int startEpoch) async {
    final config = _channelConfig;
    if (config != null) {
      await _storage.clearSession(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        scopeKey: _scopeKey,
      );
    }
    if (_disposed || _epoch != startEpoch) return;
    _session = null;
    _contact = null;
    _conversationLoaded = false;
    await _teardownRealtimeResourcesAsync();
    if (!_disposed && _isPanelOpen && _epoch == startEpoch) {
      await _bootstrapSession();
    }
  }

  void _scheduleLastSeen() {
    if (_disposed || !_isPanelOpen) return;
    _lastSeenTimer?.cancel();
    final startEpoch = _epoch;
    _lastSeenTimer = Timer(_lastSeenDebounce, () {
      _lastSeenTimer = null;
      if (_disposed || !_isPanelOpen || _epoch != startEpoch) return;
      final config = _channelConfig;
      final session = _session;
      if (config == null || session == null) return;
      unawaited(
        _service.updateLastSeen(
          baseUrl: config.baseUrl,
          websiteToken: config.websiteToken,
          authToken: session.authToken,
        ),
      );
    });
  }

  void _upsertMessage(ChatwootMessage message) {
    if (message.isPrivate) return;
    final idx = _findMatchingMessageIndex(
      id: message.id,
      echoId: message.echoId,
    );
    if (idx != -1) {
      final existing = _messages[idx];
      _messages[idx] = message.copyWith(
        echoId: message.echoId ?? existing.echoId,
        deliveryState: ChatwootDeliveryState.sent,
      );
    } else {
      _messages.add(message);
    }
  }

  void _reconcileSentMessage(String echoId, ChatwootMessage serverMessage) {
    final echoIdx = _messages.indexWhere((m) => m.echoId == echoId);
    final idIdx = serverMessage.id == null
        ? -1
        : _messages.indexWhere((m) => m.id == serverMessage.id);

    final reconciled = serverMessage.copyWith(
      echoId: serverMessage.echoId ?? echoId,
      deliveryState: ChatwootDeliveryState.sent,
    );

    if (echoIdx != -1 && idIdx != -1 && echoIdx != idIdx) {
      _messages[echoIdx] = reconciled;
      _messages.removeAt(idIdx);
    } else if (echoIdx != -1) {
      _messages[echoIdx] = reconciled;
    } else if (idIdx != -1) {
      _messages[idIdx] = reconciled;
    } else {
      _messages.add(reconciled);
    }
  }

  void _markMessageFailed(String echoId) {
    final idx = _messages.indexWhere((m) => m.echoId == echoId);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].copyWith(
      deliveryState: ChatwootDeliveryState.failed,
    );
  }

  int _findMatchingMessageIndex({int? id, String? echoId}) {
    if (echoId != null && echoId.isNotEmpty) {
      final byEcho = _messages.indexWhere((m) => m.echoId == echoId);
      if (byEcho != -1) return byEcho;
    }
    if (id != null) {
      return _messages.indexWhere((m) => m.id == id);
    }
    return -1;
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final timeCmp = a.createdAt.compareTo(b.createdAt);
      if (timeCmp != 0) return timeCmp;
      final aId = a.id ?? 0x7fffffffffffffff;
      final bId = b.id ?? 0x7fffffffffffffff;
      return aId.compareTo(bId);
    });
  }

  int? _lastServerMessageId() {
    int? maxId;
    for (final msg in _messages) {
      final id = msg.id;
      if (id != null && (maxId == null || id > maxId)) {
        maxId = id;
      }
    }
    return maxId;
  }

  String _nextEchoId() {
    final generator = _echoIdGenerator;
    if (generator != null) return generator();
    _echoSequence++;
    return 'echo_${DateTime.now().microsecondsSinceEpoch}_$_echoSequence';
  }

  void _resetScopeRuntimeState() {
    _epoch++;
    _teardownRealtimeResourcesSync();
    _session = null;
    _contact = null;
    _conversation = null;
    _messages.clear();
    _error = null;
    _loading = false;
    _resolvedLocked = false;
    _conversationLoaded = false;
    _contactSyncedScopeKey = null;
    _reconnectAttempt = 0;
  }

  void _teardownRealtimeResourcesSync() {
    _cancelTimers();
    _realtimeConnected = false;
    _connecting = false;
    _isAgentTyping = false;
    _typingAgentName = null;
    final sub = _realtimeSub;
    _realtimeSub = null;
    final conn = _realtimeConnection;
    _realtimeConnection = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    if (conn != null) {
      unawaited(conn.close());
    }
  }

  Future<void> _teardownRealtimeResourcesAsync() async {
    _cancelTimers();
    _realtimeConnected = false;
    _connecting = false;
    _isAgentTyping = false;
    _typingAgentName = null;
    final sub = _realtimeSub;
    _realtimeSub = null;
    final conn = _realtimeConnection;
    _realtimeConnection = null;
    if (sub != null) {
      await sub.cancel();
    }
    if (conn != null) {
      await conn.close();
    }
  }

  void _cancelTimers() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _typingTimer?.cancel();
    _typingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lastSeenTimer?.cancel();
    _lastSeenTimer = null;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _isPanelOpen = false;
    _epoch++;
    _teardownRealtimeResourcesSync();
    if (_ownsService) {
      _service.close();
    }
    super.dispose();
  }
}

String? _normalizeOptionalString(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
