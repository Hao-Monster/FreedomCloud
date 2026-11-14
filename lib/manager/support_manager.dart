import 'dart:async';

import 'package:flclashx/models/chatwoot.dart';
import 'package:flclashx/services/chatwoot_service.dart';
import 'package:flclashx/services/chatwoot_storage.dart';
import 'package:flutter/foundation.dart';

typedef ChatwootRealtimeConnector = Future<ChatwootRealtimeConnection> Function(
  Uri baseUrl,
  String pubsubToken,
);

typedef ChatwootCancelableRealtimeConnector = Future<ChatwootRealtimeConnection>
    Function(
  Uri baseUrl,
  String pubsubToken,
  Future<void> cancelSignal,
);

/// Manages pure-Flutter Chatwoot support state with strict per-account session
/// isolation, lazy connection (zero active sockets/timers when closed),
/// optimistic message reconciliation, and bounded reconnect backoff.
class SupportManager extends ChangeNotifier {
  SupportManager({
    ChatwootService? service,
    ChatwootSessionStorage? storage,
    ChatwootRealtimeConnector? realtimeConnector,
    ChatwootCancelableRealtimeConnector? cancelableRealtimeConnector,
    this.presenceInterval = const Duration(seconds: 60),
    Duration typingExpiry = const Duration(seconds: 6),
    Duration lastSeenDebounce = const Duration(milliseconds: 500),
    String Function()? echoIdGenerator,
  })  : _service = service ?? DioChatwootService(),
        _ownsService = service == null,
        _storage = storage ?? SecureChatwootSessionStorage(),
        _cancelableRealtimeConnector = cancelableRealtimeConnector ??
            (realtimeConnector != null
                ? ((baseUrl, pubsubToken, _) =>
                    realtimeConnector(baseUrl, pubsubToken))
                : ((baseUrl, pubsubToken, cancelSignal) =>
                    ActionCableChatwootRealtime.connect(
                      baseUrl: baseUrl,
                      pubsubToken: pubsubToken,
                      cancelSignal: cancelSignal,
                    ))),
        _typingExpiry = typingExpiry,
        _lastSeenDebounce = lastSeenDebounce,
        _echoIdGenerator = echoIdGenerator;

  static const List<int> _reconnectBackoffSeconds = [1, 2, 4, 8, 15];
  static const int _maxConsecutiveSubscriptionRejections = 6;
  static const int _maxPostRecoverySubscriptionRejections = 2;
  static const int _maxConsecutiveUnauthorizedRecoveries = 2;

  final ChatwootService _service;
  final bool _ownsService;
  final ChatwootSessionStorage _storage;
  final ChatwootCancelableRealtimeConnector _cancelableRealtimeConnector;
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
  final Map<String, int> _localSequenceByKey = {};
  ChatwootException? _error;

  bool _isPanelOpen = false;
  bool _loading = false;
  bool _loadingOlder = false;
  bool _historyExhausted = false;
  bool _connecting = false;
  bool _realtimeConnected = false;
  bool _isAgentTyping = false;
  String? _typingAgentName;
  bool _resolvedLocked = false;
  bool _conversationLoaded = false;
  bool _needsContactSync = false;
  String? _contactSyncedScopeKey;
  String? _pendingDraft;

  int _epoch = 0;
  int _panelTokenCounter = 0;
  int _activePanelToken = 0;
  int _realtimeGeneration = 0;
  int _echoSequence = 0;
  int _localMessageSequence = 0;
  int _reconnectAttempt = 0;
  int _subscriptionRejectionCount = 0;
  bool _rejectionRecoveryAttempted = false;
  int _consecutiveUnauthorizedCount = 0;
  bool _disposed = false;

  Future<void>? _bootstrapInFlight;
  int? _bootstrapEpoch;
  Future<void>? _loadOlderInFlight;
  int? _loadOlderEpoch;
  Completer<void>? _pendingConnectCancel;

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
  bool get isLoadingOlder => _loadingOlder;
  bool get hasMoreHistory =>
      !_historyExhausted && _firstServerMessageId() != null;
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
      if (changed) {
        if (_isPanelOpen && _session != null) {
          unawaited(_syncBoundContact(_epoch));
        } else if (_session != null) {
          _needsContactSync = true;
        }
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

  /// Acquires a monotonic panel-session token used to guard [openPanel] and
  /// [closePanel] against stale concurrent lifecycle transitions.
  int acquirePanelToken() {
    _activePanelToken = ++_panelTokenCounter;
    return _activePanelToken;
  }

  /// Opens the support panel, lazily bootstrapping the session, loading
  /// messages, and connecting the ActionCable WebSocket.
  Future<void> openPanel({String? initialDraft, int? panelToken}) async {
    if (_disposed) return;
    if (panelToken != null && panelToken < _activePanelToken) {
      return;
    }
    if (panelToken == null) {
      _activePanelToken = ++_panelTokenCounter;
    }
    final wasOpen = _isPanelOpen;
    _isPanelOpen = true;
    if (!wasOpen) {
      _subscriptionRejectionCount = 0;
      _rejectionRecoveryAttempted = false;
      _consecutiveUnauthorizedCount = 0;
    }
    if (initialDraft != null && initialDraft.trim().isNotEmpty) {
      _pendingDraft = initialDraft;
    }
    _error = null;
    _notify();

    final config = _channelConfig;
    if (config == null) return;

    if (_session != null && _conversationLoaded) {
      final startEpoch = _epoch;
      if (_needsContactSync) {
        await _syncBoundContact(startEpoch);
        if (_disposed || !_isPanelOpen || _epoch != startEpoch) return;
      }
      if (_realtimeConnection == null && _contact != null) {
        await _connectRealtime(startEpoch);
      }
      if (!_disposed && _isPanelOpen && _epoch == startEpoch) {
        await _reconcileConversationAndMessages(startEpoch);
        if (!_disposed && _isPanelOpen && _epoch == startEpoch) {
          _scheduleLastSeen();
        }
      }
      return;
    }

    await _bootstrapSession();
  }

  /// Closes the support panel and immediately destroys all sockets and timers
  /// so idle resource usage is zero.
  Future<void> closePanel({int? panelToken}) async {
    if (_disposed) return;
    if (panelToken != null && panelToken != _activePanelToken) {
      return;
    }
    _activePanelToken = ++_panelTokenCounter;
    _realtimeGeneration++;
    _isPanelOpen = false;
    _cancelPendingConnect();
    try {
      await _teardownRealtimeResourcesAsync();
    } on Object {
      // Ensure panel state still notifies even if socket close throws.
    }
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
    _preserveOrAssignSequence(null, optimistic);
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
      _consecutiveUnauthorizedCount = 0;
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
      if (e.isUnauthorized || e.statusCode == 404 || e.code == 'not_found') {
        await _handleUnauthorized(startEpoch, error: e);
        return;
      }
      _error = e;
      _notify();
    }
  }

  /// Loads an older page of messages (`before: oldestServerMessageId`),
  /// deduplicating overlapping messages and concurrent calls.
  Future<void> loadOlderMessages() {
    final existing = _loadOlderInFlight;
    if (existing != null && _loadOlderEpoch == _epoch) {
      return existing;
    }
    if (_disposed || !hasMoreHistory) {
      return Future<void>.value();
    }
    final startEpoch = _epoch;
    late final Future<void> future;
    future = _runLoadOlderMessages(startEpoch).whenComplete(() {
      if (identical(_loadOlderInFlight, future)) {
        _loadOlderInFlight = null;
        _loadOlderEpoch = null;
      }
    });
    _loadOlderInFlight = future;
    _loadOlderEpoch = startEpoch;
    return future;
  }

  Future<void> _runLoadOlderMessages(int startEpoch) async {
    final config = _channelConfig;
    final session = _session;
    final beforeId = _firstServerMessageId();
    if (_disposed ||
        config == null ||
        session == null ||
        beforeId == null ||
        _historyExhausted ||
        _epoch != startEpoch) {
      return;
    }

    _loadingOlder = true;
    _notify();

    try {
      final fetched = await _service.fetchMessages(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        authToken: session.authToken,
        before: beforeId,
      );
      if (_disposed || _epoch != startEpoch) return;

      _consecutiveUnauthorizedCount = 0;
      _loadingOlder = false;
      var addedOlder = false;
      for (final msg in fetched) {
        if (msg.isPrivate) continue;
        final id = msg.id;
        final alreadyExists =
            _findMatchingMessageIndex(id: id, echoId: msg.echoId) != -1;
        if (!alreadyExists && id != null && id < beforeId) {
          addedOlder = true;
        }
        _upsertMessage(msg);
      }
      if (fetched.isEmpty || !addedOlder) {
        _historyExhausted = true;
      }
      _sortMessages();
      _error = null;
      _notify();
    } on ChatwootException catch (e) {
      if (_disposed || _epoch != startEpoch) return;
      _loadingOlder = false;
      if (e.isUnauthorized || e.statusCode == 404 || e.code == 'not_found') {
        await _handleUnauthorized(startEpoch, error: e);
        return;
      }
      _error = e;
      _notify();
    } on Object {
      if (_disposed || _epoch != startEpoch) return;
      _loadingOlder = false;
      _notify();
    }
  }

  Future<void> _reconcileConversationAndMessages(int startEpoch) async {
    if (_disposed || _epoch != startEpoch || !_isPanelOpen) return;
    final config = _channelConfig;
    final session = _session;
    if (config == null || session == null) return;

    final afterId = _lastServerMessageId();
    try {
      final convFuture = _service.fetchConversation(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        authToken: session.authToken,
      );
      final msgsFuture = _service.fetchMessages(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        authToken: session.authToken,
        after: afterId,
      );
      final conversation = await convFuture;
      final fetched = await msgsFuture;
      if (_disposed || _epoch != startEpoch) return;

      _consecutiveUnauthorizedCount = 0;
      _conversation = conversation;
      _resolvedLocked = (conversation?.isResolved ?? false) &&
          !config.allowMessagesAfterResolved;
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
      if (e.isUnauthorized || e.statusCode == 404 || e.code == 'not_found') {
        await _handleUnauthorized(startEpoch, error: e);
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
    _epoch++;
    _realtimeGeneration++;
    _cancelPendingConnect();
    _clearScopeStateFields();
    final startEpoch = _epoch;
    _notify();

    try {
      await _teardownRealtimeResourcesAsync();
    } on Object {
      // Proceed to clear stored session even if old socket close throws.
    }
    await _safeClearSession(
      baseUrl: config.baseUrl,
      websiteToken: config.websiteToken,
      scopeKey: currentScope,
    );

    if (!_disposed && _isPanelOpen && _epoch == startEpoch) {
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
      final stored = await _safeReadSession(
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
        final canRetryAnonymous = stored?.authToken != null &&
            (e.isUnauthorized || e.statusCode == 404 || e.code == 'not_found');
        if (!canRetryAnonymous) rethrow;
        await _safeClearSession(
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

      await _safeSaveSession(
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
      _resolvedLocked = (conversation?.isResolved ?? false) &&
          !init.config.allowMessagesAfterResolved;
      initialMessages.forEach(_upsertMessage);
      _sortMessages();
      _conversationLoaded = true;
      _loading = false;
      _consecutiveUnauthorizedCount = 0;
      _notify();

      if (!_isPanelOpen || _disposed || _epoch != startEpoch) return;

      final pubsub = _contact?.pubsubToken;
      if (pubsub != null && pubsub.isNotEmpty) {
        await _connectRealtime(startEpoch);
      }
      if (_isPanelOpen &&
          !_disposed &&
          _epoch == startEpoch &&
          _messages.isNotEmpty) {
        _scheduleLastSeen();
      }
    } on ChatwootException catch (e) {
      if (_disposed || _epoch != startEpoch) return;
      if (e.isUnauthorized || e.statusCode == 404 || e.code == 'not_found') {
        _loading = false;
        await _handleUnauthorized(startEpoch, error: e);
        return;
      }
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
    if (_scopeKey == 'guest') {
      _needsContactSync = false;
      return;
    }
    final needsEmailSync = _boundEmail != null && _contact?.email != _boundEmail;
    final needsAttrSync = _boundCustomAttributes != null &&
        _boundCustomAttributes!.isNotEmpty &&
        (_needsContactSync || _contactSyncedScopeKey != _scopeKey);
    final needsNameSync = _boundName != null && _contact?.name != _boundName;
    if (!_needsContactSync &&
        !needsEmailSync &&
        !needsAttrSync &&
        !needsNameSync &&
        _contactSyncedScopeKey == _scopeKey) {
      return;
    }
    if (_boundEmail == null &&
        _boundName == null &&
        (_boundCustomAttributes == null || _boundCustomAttributes!.isEmpty)) {
      _needsContactSync = false;
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
      _needsContactSync = false;
      _contactSyncedScopeKey = _scopeKey;
      if (updated != null) {
        _contact = updated;
        _session = session.copyWith(
          pubsubToken: updated.pubsubToken,
          contactId: updated.id,
          boundEmail: _boundEmail ?? updated.email,
        );
        await _safeSaveSession(
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
      _consecutiveUnauthorizedCount = 0;
      _reconcileSentMessage(echoId, serverMessage);
      _sortMessages();
      _error = null;
      _notify();
      _scheduleLastSeen();
    } on ChatwootException catch (e) {
      if (_disposed || _epoch != startEpoch) return;
      if (_isMessageConfirmed(echoId)) return;
      _markMessageFailed(echoId);
      if (e.isResolvedLocked) {
        _resolvedLocked = true;
        _conversation =
            (_conversation ?? const ChatwootConversation(status: 'resolved'))
                .copyWith(status: 'resolved');
      }
      if (e.isUnauthorized || e.statusCode == 404 || e.code == 'not_found') {
        _error = e;
        _notify();
        await _handleUnauthorized(startEpoch, error: e);
        return;
      }
      _error = e;
      _notify();
    } on Object {
      if (_disposed || _epoch != startEpoch) return;
      if (_isMessageConfirmed(echoId)) return;
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

    final myGen = ++_realtimeGeneration;
    _cancelPendingConnect();
    final cancelCompleter = Completer<void>();
    _pendingConnectCancel = cancelCompleter;

    try {
      _connecting = true;
      await _teardownRealtimeResourcesAsync(clearConnecting: false);
      if (!_isPanelOpen ||
          _disposed ||
          _epoch != startEpoch ||
          _realtimeGeneration != myGen) {
        return;
      }

      _connecting = true;
      _notify();

      final connectFuture = _cancelableRealtimeConnector(
        config.baseUrl,
        pubsubToken,
        cancelCompleter.future,
      );
      unawaited(
        connectFuture.then(
          (lateConn) {
            if (_disposed ||
                !_isPanelOpen ||
                _epoch != startEpoch ||
                _realtimeGeneration != myGen) {
              unawaited(lateConn.close().catchError((Object _) {}));
            }
          },
          onError: (Object _) {},
        ),
      );

      final connection = await Future.any<ChatwootRealtimeConnection?>([
        connectFuture,
        cancelCompleter.future.then<ChatwootRealtimeConnection?>((_) => null),
      ]);
      if (identical(_pendingConnectCancel, cancelCompleter)) {
        _pendingConnectCancel = null;
      }

      if (connection == null) {
        return;
      }
      if (!_isPanelOpen ||
          _disposed ||
          _epoch != startEpoch ||
          _realtimeGeneration != myGen) {
        await connection.close();
        return;
      }

      _realtimeConnection = connection;
      _realtimeConnected = false;
      _connecting = true;

      _realtimeSub = connection.events.listen(
        (event) => _handleRealtimeEvent(event, startEpoch),
        onError: (Object _) => _handleRealtimeDropped(startEpoch),
        onDone: () => _handleRealtimeDropped(startEpoch),
      );

      _notify();
    } on Object {
      if (identical(_pendingConnectCancel, cancelCompleter)) {
        _pendingConnectCancel = null;
      }
      if (_disposed ||
          _epoch != startEpoch ||
          _realtimeGeneration != myGen) {
        return;
      }
      _connecting = false;
      _realtimeConnected = false;
      _notify();
      if (_isPanelOpen) {
        _scheduleReconnect(startEpoch);
      }
    }
  }

  bool _matchesActiveConversation(int? conversationId) {
    final activeId = _conversation?.id;
    if (conversationId == null || activeId == null) return true;
    return conversationId == activeId;
  }

  void _handleRealtimeEvent(ChatwootRealtimeEvent event, int startEpoch) {
    if (_disposed || _epoch != startEpoch) return;
    switch (event) {
      case ChatwootMessageCreatedEvent(:final message, :final conversationId):
        if (message.isPrivate || !_matchesActiveConversation(conversationId)) {
          return;
        }
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

      case ChatwootMessageUpdatedEvent(:final message, :final conversationId):
        if (message.isPrivate || !_matchesActiveConversation(conversationId)) {
          return;
        }
        _upsertMessage(message);
        _sortMessages();
        _notify();

      case ChatwootTypingEvent(
          :final isTyping,
          :final senderName,
          :final conversationId,
        ):
        if (!_matchesActiveConversation(conversationId)) return;
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
        if (!_matchesActiveConversation(conversationId)) return;
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

      case ChatwootSubscriptionConfirmedEvent():
        _connecting = false;
        _realtimeConnected = true;
        _reconnectAttempt = 0;
        _subscriptionRejectionCount = 0;
        _rejectionRecoveryAttempted = false;
        _presenceTimer?.cancel();
        _presenceTimer = Timer.periodic(presenceInterval, (_) {
          if (_isPanelOpen && !_disposed && _epoch == startEpoch) {
            unawaited(_realtimeConnection?.sendPresence());
          }
        });
        _notify();
        unawaited(_reconcileConversationAndMessages(startEpoch));

      case ChatwootSubscriptionRejectedEvent():
        _handleSubscriptionRejected(startEpoch);

      case ChatwootDisconnectedEvent(:final reconnect):
        _handleRealtimeDropped(startEpoch, reconnect: reconnect);
    }
  }

  void _handleSubscriptionRejected(int startEpoch) {
    if (_disposed || _epoch != startEpoch) return;
    _subscriptionRejectionCount++;
    if (!_rejectionRecoveryAttempted &&
        _subscriptionRejectionCount >= _maxConsecutiveSubscriptionRejections) {
      _rejectionRecoveryAttempted = true;
      _subscriptionRejectionCount = 0;
      _teardownRealtimeResourcesSync();
      _notify();
      unawaited(_handleUnauthorized(startEpoch));
      return;
    }
    if (_rejectionRecoveryAttempted &&
        _subscriptionRejectionCount >= _maxPostRecoverySubscriptionRejections) {
      _handleRealtimeDropped(
        startEpoch,
        reconnect: false,
        error: const ChatwootException(
          code: 'realtime_rejected',
          message: '客服实时连接被拒绝，请稍后重试',
        ),
      );
      return;
    }
    _handleRealtimeDropped(startEpoch, reconnect: true);
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
    await _safeSaveSession(
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

  void _handleRealtimeDropped(
    int startEpoch, {
    bool reconnect = true,
    ChatwootException? error,
  }) {
    if (_disposed || _epoch != startEpoch) return;
    _realtimeGeneration++;
    final conn = _realtimeConnection;
    final sub = _realtimeSub;
    _realtimeConnection = null;
    _realtimeSub = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _realtimeConnected = false;
    _connecting = false;
    if (error != null) {
      _error = error;
    }
    if (sub != null) {
      unawaited(sub.cancel());
    }
    if (conn != null) {
      unawaited(conn.close().catchError((Object _) {}));
    }
    _notify();
    if (_isPanelOpen && reconnect) {
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
      unawaited(_connectRealtime(startEpoch));
    });
  }

  Future<void> _handleUnauthorized(
    int startEpoch, {
    ChatwootException? error,
  }) async {
    if (_disposed || _epoch != startEpoch) return;
    if (_consecutiveUnauthorizedCount >= _maxConsecutiveUnauthorizedRecoveries) {
      _session = null;
      _contact = null;
      _conversationLoaded = false;
      _loading = false;
      if (error != null) {
        _error = error;
      }
      _notify();
      return;
    }
    _consecutiveUnauthorizedCount++;
    _session = null;
    _contact = null;
    _conversationLoaded = false;
    final config = _channelConfig;
    if (config != null) {
      await _safeClearSession(
        baseUrl: config.baseUrl,
        websiteToken: config.websiteToken,
        scopeKey: _scopeKey,
      );
    }
    if (_disposed || _epoch != startEpoch) return;
    try {
      await _teardownRealtimeResourcesAsync();
    } on Object {
      // Proceed with session bootstrap even if socket close fails.
    }
    if (!_disposed && _isPanelOpen && _epoch == startEpoch) {
      await _bootstrapSession();
    } else {
      _notify();
    }
  }

  Future<ChatwootSession?> _safeReadSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async {
    try {
      return await _storage.readSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: scopeKey,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _safeSaveSession({
    required Uri baseUrl,
    required String websiteToken,
    required ChatwootSession session,
  }) async {
    try {
      await _storage.saveSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        session: session,
      );
    } on Object {
      // Degrade cleanly to in-memory session when secure storage write fails.
    }
  }

  Future<void> _safeClearSession({
    required Uri baseUrl,
    required String websiteToken,
    required String scopeKey,
  }) async {
    try {
      await _storage.clearSession(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        scopeKey: scopeKey,
      );
    } on Object {
      // Degrade cleanly when secure storage deletion fails.
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
      final next = message.copyWith(
        echoId: message.echoId ?? existing.echoId,
        deliveryState: ChatwootDeliveryState.sent,
      );
      _preserveOrAssignSequence(existing, next);
      _messages[idx] = next;
    } else {
      _preserveOrAssignSequence(null, message);
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
      _preserveOrAssignSequence(_messages[echoIdx], reconciled);
      _messages[echoIdx] = reconciled;
      _messages.removeAt(idIdx);
    } else if (echoIdx != -1) {
      _preserveOrAssignSequence(_messages[echoIdx], reconciled);
      _messages[echoIdx] = reconciled;
    } else if (idIdx != -1) {
      _preserveOrAssignSequence(_messages[idIdx], reconciled);
      _messages[idIdx] = reconciled;
    } else {
      _preserveOrAssignSequence(null, reconciled);
      _messages.add(reconciled);
    }
  }

  bool _isMessageConfirmed(String echoId) {
    final idx = _messages.indexWhere((m) => m.echoId == echoId);
    if (idx == -1) return false;
    final current = _messages[idx];
    return current.id != null ||
        current.deliveryState == ChatwootDeliveryState.sent;
  }

  void _markMessageFailed(String echoId) {
    final idx = _messages.indexWhere((m) => m.echoId == echoId);
    if (idx == -1) return;
    final current = _messages[idx];
    if (current.id != null ||
        current.deliveryState == ChatwootDeliveryState.sent) {
      return;
    }
    _messages[idx] = current.copyWith(
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

  String _messageSeqKey(ChatwootMessage message) {
    final echoId = message.echoId;
    if (echoId != null && echoId.isNotEmpty) {
      return 'echo:$echoId';
    }
    final id = message.id;
    if (id != null) {
      return 'id:$id';
    }
    return 'obj:${identityHashCode(message)}';
  }

  void _preserveOrAssignSequence(
    ChatwootMessage? existing,
    ChatwootMessage next,
  ) {
    int? seq;
    if (existing != null) {
      seq = _localSequenceByKey[_messageSeqKey(existing)] ??
          (existing.id != null
              ? _localSequenceByKey['id:${existing.id}']
              : null);
    }
    seq ??= (next.id != null ? _localSequenceByKey['id:${next.id}'] : null) ??
        _localSequenceByKey[_messageSeqKey(next)];
    seq ??= ++_localMessageSequence;
    _localSequenceByKey[_messageSeqKey(next)] = seq;
    if (next.id != null) {
      _localSequenceByKey['id:${next.id}'] = seq;
    }
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final aSec = a.createdAt.millisecondsSinceEpoch ~/ 1000;
      final bSec = b.createdAt.millisecondsSinceEpoch ~/ 1000;
      final secCmp = aSec.compareTo(bSec);
      if (secCmp != 0) return secCmp;
      final aId = a.id;
      final bId = b.id;
      if (aId != null && bId != null) {
        final timeCmp = a.createdAt.compareTo(b.createdAt);
        if (timeCmp != 0) return timeCmp;
        return aId.compareTo(bId);
      }
      final aSeq = _localSequenceByKey[_messageSeqKey(a)] ??
          (aId != null ? _localSequenceByKey['id:$aId'] : null) ??
          0x7fffffffffffffff;
      final bSeq = _localSequenceByKey[_messageSeqKey(b)] ??
          (bId != null ? _localSequenceByKey['id:$bId'] : null) ??
          0x7fffffffffffffff;
      final seqCmp = aSeq.compareTo(bSeq);
      if (seqCmp != 0) return seqCmp;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  int? _firstServerMessageId() {
    int? minId;
    for (final msg in _messages) {
      final id = msg.id;
      if (id != null && (minId == null || id < minId)) {
        minId = id;
      }
    }
    return minId;
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

  void _clearScopeStateFields() {
    _session = null;
    _contact = null;
    _conversation = null;
    _messages.clear();
    _localSequenceByKey.clear();
    _localMessageSequence = 0;
    _error = null;
    _loading = false;
    _loadingOlder = false;
    _historyExhausted = false;
    _loadOlderInFlight = null;
    _loadOlderEpoch = null;
    _resolvedLocked = false;
    _conversationLoaded = false;
    _needsContactSync = false;
    _contactSyncedScopeKey = null;
    _pendingDraft = null;
    _reconnectAttempt = 0;
    _subscriptionRejectionCount = 0;
    _rejectionRecoveryAttempted = false;
    _consecutiveUnauthorizedCount = 0;
  }

  void _resetScopeRuntimeState() {
    _epoch++;
    _realtimeGeneration++;
    _cancelPendingConnect();
    _teardownRealtimeResourcesSync();
    _clearScopeStateFields();
  }

  void _cancelPendingConnect() {
    final pending = _pendingConnectCancel;
    _pendingConnectCancel = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
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
      unawaited(conn.close().catchError((Object _) {}));
    }
  }

  Future<void> _teardownRealtimeResourcesAsync({
    bool clearConnecting = true,
  }) async {
    _cancelTimers();
    _realtimeConnected = false;
    if (clearConnecting) {
      _connecting = false;
    }
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
    _realtimeGeneration++;
    _cancelPendingConnect();
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
