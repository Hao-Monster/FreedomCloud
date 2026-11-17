import 'package:flutter/foundation.dart';

/// Returns `true` when [baseUrl] is a valid Chatwoot HTTPS origin/base URL.
bool isValidChatwootBaseUrl(Uri baseUrl) =>
    baseUrl.scheme == 'https' &&
    baseUrl.host.isNotEmpty &&
    baseUrl.userInfo.isEmpty &&
    !baseUrl.hasQuery &&
    !baseUrl.hasFragment;

/// Validates and normalizes a Chatwoot widget base URL.
///
/// Requires an `https` scheme, non-empty host, empty userInfo, and no query
/// string or fragment.
Uri validateChatwootBaseUrl(Uri baseUrl) {
  if (!isValidChatwootBaseUrl(baseUrl)) {
    throw ArgumentError.value(
      baseUrl,
      'baseUrl',
      'Chatwoot baseUrl must be a valid HTTPS URL without userInfo, query, or fragment',
    );
  }
  if (baseUrl.path.isEmpty || baseUrl.path == '/') {
    return Uri.parse(baseUrl.origin);
  }
  final normalizedPath = baseUrl.path.replaceAll(RegExp(r'/+$'), '');
  if (normalizedPath.isEmpty) {
    return Uri.parse(baseUrl.origin);
  }
  return baseUrl.replace(path: normalizedPath);
}

/// Immutable configuration for a Chatwoot website widget channel.
@immutable
class ChatwootChannelConfig {
  factory ChatwootChannelConfig({
    required Uri baseUrl,
    required String websiteToken,
    String? websiteName,
    String? welcomeTitle,
    String? welcomeTagline,
    String? replyTime,
    bool allowMessagesAfterResolved = true,
    String? outOfOfficeMessage,
  }) {
    final normalizedBaseUrl = validateChatwootBaseUrl(baseUrl);
    final trimmedToken = websiteToken.trim();
    if (trimmedToken.isEmpty) {
      throw ArgumentError.value(
        websiteToken,
        'websiteToken',
        'Chatwoot websiteToken must not be empty',
      );
    }
    return ChatwootChannelConfig._(
      baseUrl: normalizedBaseUrl,
      websiteToken: trimmedToken,
      websiteName: websiteName,
      welcomeTitle: welcomeTitle,
      welcomeTagline: welcomeTagline,
      replyTime: replyTime,
      allowMessagesAfterResolved: allowMessagesAfterResolved,
      outOfOfficeMessage: outOfOfficeMessage,
    );
  }

  const ChatwootChannelConfig._({
    required this.baseUrl,
    required this.websiteToken,
    this.websiteName,
    this.welcomeTitle,
    this.welcomeTagline,
    this.replyTime,
    this.allowMessagesAfterResolved = true,
    this.outOfOfficeMessage,
  });

  final Uri baseUrl;
  final String websiteToken;
  final String? websiteName;
  final String? welcomeTitle;
  final String? welcomeTagline;
  final String? replyTime;
  final bool allowMessagesAfterResolved;
  final String? outOfOfficeMessage;

  /// Returns a valid [ChatwootChannelConfig] or `null` if inputs are absent or invalid.
  static ChatwootChannelConfig? tryCreate({
    Uri? baseUrl,
    String? websiteToken,
    String? websiteName,
    String? welcomeTitle,
    String? welcomeTagline,
    String? replyTime,
    bool allowMessagesAfterResolved = true,
    String? outOfOfficeMessage,
  }) {
    if (baseUrl == null ||
        websiteToken == null ||
        websiteToken.trim().isEmpty ||
        !isValidChatwootBaseUrl(baseUrl)) {
      return null;
    }
    return ChatwootChannelConfig(
      baseUrl: baseUrl,
      websiteToken: websiteToken,
      websiteName: websiteName,
      welcomeTitle: welcomeTitle,
      welcomeTagline: welcomeTagline,
      replyTime: replyTime,
      allowMessagesAfterResolved: allowMessagesAfterResolved,
      outOfOfficeMessage: outOfOfficeMessage,
    );
  }

  ChatwootChannelConfig copyWith({
    Uri? baseUrl,
    String? websiteToken,
    String? websiteName,
    String? welcomeTitle,
    String? welcomeTagline,
    String? replyTime,
    bool? allowMessagesAfterResolved,
    String? outOfOfficeMessage,
  }) =>
      ChatwootChannelConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        websiteToken: websiteToken ?? this.websiteToken,
        websiteName: websiteName ?? this.websiteName,
        welcomeTitle: welcomeTitle ?? this.welcomeTitle,
        welcomeTagline: welcomeTagline ?? this.welcomeTagline,
        replyTime: replyTime ?? this.replyTime,
        allowMessagesAfterResolved:
            allowMessagesAfterResolved ?? this.allowMessagesAfterResolved,
        outOfOfficeMessage: outOfOfficeMessage ?? this.outOfOfficeMessage,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatwootChannelConfig &&
          other.baseUrl == baseUrl &&
          other.websiteToken == websiteToken &&
          other.websiteName == websiteName &&
          other.welcomeTitle == welcomeTitle &&
          other.welcomeTagline == welcomeTagline &&
          other.replyTime == replyTime &&
          other.allowMessagesAfterResolved == allowMessagesAfterResolved &&
          other.outOfOfficeMessage == outOfOfficeMessage;

  @override
  int get hashCode => Object.hash(
        baseUrl,
        websiteToken,
        websiteName,
        welcomeTitle,
        welcomeTagline,
        replyTime,
        allowMessagesAfterResolved,
        outOfOfficeMessage,
      );
}

/// Immutable Chatwoot widget contact identity.
@immutable
class ChatwootContact {
  const ChatwootContact({
    required this.id,
    this.name,
    this.email,
    required this.pubsubToken,
  });

  final int id;
  final String? name;
  final String? email;
  final String pubsubToken;

  ChatwootContact copyWith({
    int? id,
    String? name,
    String? email,
    String? pubsubToken,
  }) =>
      ChatwootContact(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        pubsubToken: pubsubToken ?? this.pubsubToken,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatwootContact &&
          other.id == id &&
          other.name == name &&
          other.email == email &&
          other.pubsubToken == pubsubToken;

  @override
  int get hashCode => Object.hash(id, name, email, pubsubToken);
}

/// Immutable Chatwoot conversation metadata.
@immutable
class ChatwootConversation {
  const ChatwootConversation({
    this.id,
    required this.status,
    this.contactLastSeenAt,
  });

  final int? id;
  final String status;
  final int? contactLastSeenAt;

  bool get isResolved => status.toLowerCase() == 'resolved';

  ChatwootConversation copyWith({
    int? id,
    String? status,
    int? contactLastSeenAt,
  }) =>
      ChatwootConversation(
        id: id ?? this.id,
        status: status ?? this.status,
        contactLastSeenAt: contactLastSeenAt ?? this.contactLastSeenAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatwootConversation &&
          other.id == id &&
          other.status == status &&
          other.contactLastSeenAt == contactLastSeenAt;

  @override
  int get hashCode => Object.hash(id, status, contactLastSeenAt);
}

/// Message sender/category classification in Chatwoot.
enum ChatwootMessageType {
  visitor,
  agent,
  activity,
  template;

  static ChatwootMessageType parse(Object? value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('Unsupported Chatwoot message_type: $value');
    }
    return parsed;
  }

  static ChatwootMessageType? tryParse(Object? value) {
    if (value is int) {
      return switch (value) {
        0 => ChatwootMessageType.visitor,
        1 => ChatwootMessageType.agent,
        2 => ChatwootMessageType.activity,
        3 => ChatwootMessageType.template,
        _ => null,
      };
    }
    if (value is String) {
      return switch (value.trim().toLowerCase()) {
        '0' || 'incoming' || 'visitor' => ChatwootMessageType.visitor,
        '1' || 'outgoing' || 'agent' => ChatwootMessageType.agent,
        '2' || 'activity' => ChatwootMessageType.activity,
        '3' || 'template' => ChatwootMessageType.template,
        _ => null,
      };
    }
    return null;
  }
}

/// Delivery lifecycle state for an outgoing message.
enum ChatwootDeliveryState { sending, sent, failed }

/// Immutable Chatwoot chat message.
@immutable
class ChatwootMessage {
  const ChatwootMessage({
    this.id,
    this.echoId,
    required this.content,
    required this.type,
    required this.createdAt,
    this.senderName,
    this.deliveryState = ChatwootDeliveryState.sent,
    this.isPrivate = false,
  });

  final int? id;
  final String? echoId;
  final String content;
  final ChatwootMessageType type;
  final DateTime createdAt;
  final String? senderName;
  final ChatwootDeliveryState deliveryState;
  final bool isPrivate;

  /// Stable UI/reconciliation key (`'echo:$echoId'` or `'id:$id'`).
  String get stableKey {
    final echo = echoId;
    if (echo != null && echo.isNotEmpty) {
      return 'echo:$echo';
    }
    if (id != null) {
      return 'id:$id';
    }
    return 'local:${createdAt.microsecondsSinceEpoch}';
  }

  ChatwootMessage copyWith({
    int? id,
    String? echoId,
    String? content,
    ChatwootMessageType? type,
    DateTime? createdAt,
    String? senderName,
    ChatwootDeliveryState? deliveryState,
    bool? isPrivate,
  }) =>
      ChatwootMessage(
        id: id ?? this.id,
        echoId: echoId ?? this.echoId,
        content: content ?? this.content,
        type: type ?? this.type,
        createdAt: createdAt ?? this.createdAt,
        senderName: senderName ?? this.senderName,
        deliveryState: deliveryState ?? this.deliveryState,
        isPrivate: isPrivate ?? this.isPrivate,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatwootMessage &&
          other.id == id &&
          other.echoId == echoId &&
          other.content == content &&
          other.type == type &&
          other.createdAt == createdAt &&
          other.senderName == senderName &&
          other.deliveryState == deliveryState &&
          other.isPrivate == isPrivate;

  @override
  int get hashCode => Object.hash(
        id,
        echoId,
        content,
        type,
        createdAt,
        senderName,
        deliveryState,
        isPrivate,
      );
}

/// Sanitized exception thrown by Chatwoot REST and realtime transport layers.
class ChatwootException implements Exception {
  const ChatwootException({
    required this.code,
    required this.message,
    this.statusCode,
    this.isResolvedLocked = false,
    this.isUnauthorized = false,
  });

  final String code;
  final String message;
  final int? statusCode;
  final bool isResolvedLocked;
  final bool isUnauthorized;

  @override
  String toString() => 'ChatwootException($code): $message';
}

/// Typed ActionCable realtime events emitted by a Chatwoot widget connection.
@immutable
sealed class ChatwootRealtimeEvent {
  const ChatwootRealtimeEvent();
}

final class ChatwootMessageCreatedEvent extends ChatwootRealtimeEvent {
  const ChatwootMessageCreatedEvent(this.message, {this.conversationId});

  final ChatwootMessage message;
  final int? conversationId;
}

final class ChatwootMessageUpdatedEvent extends ChatwootRealtimeEvent {
  const ChatwootMessageUpdatedEvent(this.message, {this.conversationId});

  final ChatwootMessage message;
  final int? conversationId;
}

final class ChatwootTypingEvent extends ChatwootRealtimeEvent {
  const ChatwootTypingEvent({
    required this.isTyping,
    this.senderName,
    this.conversationId,
  });

  final bool isTyping;
  final String? senderName;
  final int? conversationId;
}

final class ChatwootConversationStatusChangedEvent extends ChatwootRealtimeEvent {
  const ChatwootConversationStatusChangedEvent({
    this.conversationId,
    required this.status,
  });

  final int? conversationId;
  final String status;
}

final class ChatwootContactMergedEvent extends ChatwootRealtimeEvent {
  const ChatwootContactMergedEvent({
    this.contactId,
    this.pubsubToken,
  });

  final int? contactId;
  final String? pubsubToken;
}

final class ChatwootSubscriptionConfirmedEvent extends ChatwootRealtimeEvent {
  const ChatwootSubscriptionConfirmedEvent();
}

final class ChatwootSubscriptionRejectedEvent extends ChatwootRealtimeEvent {
  const ChatwootSubscriptionRejectedEvent();
}

final class ChatwootDisconnectedEvent extends ChatwootRealtimeEvent {
  const ChatwootDisconnectedEvent({
    this.reconnect = true,
    this.reason,
  });

  final bool reconnect;
  final String? reason;
}
