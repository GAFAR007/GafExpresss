/// lib/app/features/home/presentation/chat_models.dart
/// ---------------------------------------------------
/// WHAT:
/// - Data models for chat conversations, messages, and attachments.
///
/// WHY:
/// - Keeps JSON parsing centralized and reusable across chat UI.
/// - Prevents raw JSON access inside widgets.
///
/// HOW:
/// - Provides typed model classes with fromJson helpers.
/// - Normalizes nullable fields and parses timestamps safely.
library;

import 'package:frontend/app/features/home/presentation/purchase_request_models.dart';

// WHY: Keep model keys centralized to avoid magic strings.
const String _keyId = "_id";
const String _keyConversationId = "conversationId";
const String _keyBusinessId = "businessId";
const String _keyType = "type";
const String _keyTitle = "title";
const String _keyLastMessageAt = "lastMessageAt";
const String _keyLastMessagePreview = "lastMessagePreview";
const String _keyDisplayName = "displayName";
const String _keyDisplayAvatar = "displayAvatar";
const String _keyParticipantsCount = "participantsCount";
const String _keyUnreadCount = "unreadCount";
const String _keyCreatedAt = "createdAt";
const String _keySenderUserId = "senderUserId";
const String _keyBody = "body";
const String _keyAttachmentIds = "attachmentIds";
const String _keyClientMessageId = "clientMessageId";
const String _keyParticipants = "participants";
const String _keyConversation = "conversation";
const String _keyUserId = "userId";
const String _keyName = "name";
const String _keyEmail = "email";
const String _keyRole = "role";
const String _keyRoleAtJoin = "roleAtJoin";
const String _keyBusinessName = "businessName";
const String _keyEstateAssetId = "estateAssetId";
const String _keyEstateName = "estateName";
const String _keyProfileImageUrl = "profileImageUrl";
const String _keyJoinedAt = "joinedAt";
const String _keyLastReadAt = "lastReadAt";
const String _keyUrl = "url";
const String _keyFilename = "filename";
const String _keyMimeType = "mimeType";
const String _keySizeBytes = "sizeBytes";
const String _keyPublicId = "publicId";
const String _keyPurchaseRequest = "purchaseRequest";
const String _keyEventType = "eventType";
const String _keyEventData = "eventData";

DateTime? _parseDate(dynamic value) {
  // WHY: Prevent crashes on invalid timestamps.
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

enum ChatMessageStatus { sending, sent, delivered, seen, failed }

ChatMessageStatus? _parseMessageStatus(dynamic value) {
  switch ((value ?? "").toString().trim().toLowerCase()) {
    case "sending":
      return ChatMessageStatus.sending;
    case "sent":
      return ChatMessageStatus.sent;
    case "delivered":
      return ChatMessageStatus.delivered;
    case "seen":
      return ChatMessageStatus.seen;
    case "failed":
      return ChatMessageStatus.failed;
    default:
      return null;
  }
}

class ChatConversation {
  final String id;
  final String businessId;
  final String type;
  final String title;
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final DateTime? createdAt;
  final String displayName;
  final String displayAvatar;
  final int participantsCount;
  final int unreadCount;

  const ChatConversation({
    required this.id,
    required this.businessId,
    required this.type,
    required this.title,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.createdAt,
    required this.displayName,
    required this.displayAvatar,
    required this.participantsCount,
    required this.unreadCount,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    // WHY: Defend against numeric types coming back as strings.
    final rawCount = json[_keyParticipantsCount];
    final participantsCount = rawCount is int
        ? rawCount
        : int.tryParse(rawCount?.toString() ?? '') ?? 0;
    final rawUnreadCount = json[_keyUnreadCount];
    final unreadCount = rawUnreadCount is int
        ? rawUnreadCount
        : int.tryParse(rawUnreadCount?.toString() ?? '') ?? 0;
    return ChatConversation(
      id: (json[_keyId] ?? "").toString(),
      businessId: (json[_keyBusinessId] ?? "").toString(),
      type: (json[_keyType] ?? "").toString(),
      title: (json[_keyTitle] ?? "").toString(),
      lastMessageAt: _parseDate(json[_keyLastMessageAt]),
      lastMessagePreview: (json[_keyLastMessagePreview] ?? "").toString(),
      createdAt: _parseDate(json[_keyCreatedAt]),
      displayName: (json[_keyDisplayName] ?? "").toString(),
      displayAvatar: (json[_keyDisplayAvatar] ?? "").toString(),
      participantsCount: participantsCount,
      unreadCount: unreadCount,
    );
  }
}

class ChatParticipantSummary {
  final String userId;
  final String name;
  final String email;
  final String profileImageUrl;
  final String role;
  final String roleAtJoin;
  final String businessId;
  final String businessName;
  final String estateAssetId;
  final String estateName;
  final DateTime? joinedAt;
  final DateTime? lastReadAt;

  const ChatParticipantSummary({
    required this.userId,
    required this.name,
    required this.email,
    required this.profileImageUrl,
    required this.role,
    required this.roleAtJoin,
    required this.businessId,
    required this.businessName,
    required this.estateAssetId,
    required this.estateName,
    required this.joinedAt,
    required this.lastReadAt,
  });

  factory ChatParticipantSummary.fromJson(Map<String, dynamic> json) {
    return ChatParticipantSummary(
      userId: (json[_keyUserId] ?? "").toString(),
      name: (json[_keyName] ?? "").toString(),
      email: (json[_keyEmail] ?? "").toString(),
      // WHY: Avatar is optional but improves recognition in chat UI.
      profileImageUrl: (json[_keyProfileImageUrl] ?? "").toString(),
      role: (json[_keyRole] ?? "").toString(),
      roleAtJoin: (json[_keyRoleAtJoin] ?? "").toString(),
      businessId: (json[_keyBusinessId] ?? "").toString(),
      businessName: (json[_keyBusinessName] ?? "").toString(),
      estateAssetId: (json[_keyEstateAssetId] ?? "").toString(),
      estateName: (json[_keyEstateName] ?? "").toString(),
      joinedAt: _parseDate(json[_keyJoinedAt]),
      lastReadAt: _parseDate(json[_keyLastReadAt]),
    );
  }
}

class ChatConversationDetail {
  final ChatConversation conversation;
  final List<ChatParticipantSummary> participants;
  final PurchaseRequest? purchaseRequest;

  const ChatConversationDetail({
    required this.conversation,
    required this.participants,
    required this.purchaseRequest,
  });

  factory ChatConversationDetail.fromJson(Map<String, dynamic> json) {
    final convoMap = (json[_keyConversation] ?? {}) as Map<String, dynamic>;
    final rawParticipants = (json[_keyParticipants] ?? []) as List<dynamic>;
    final participants = rawParticipants
        .whereType<Map<String, dynamic>>()
        .map(ChatParticipantSummary.fromJson)
        .toList();

    return ChatConversationDetail(
      conversation: ChatConversation.fromJson(convoMap),
      participants: participants,
      purchaseRequest: json[_keyPurchaseRequest] is Map<String, dynamic>
          ? PurchaseRequest.fromJson(
              json[_keyPurchaseRequest] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class ChatAttachment {
  final String id;
  final String type;
  final String url;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String publicId;

  const ChatAttachment({
    required this.id,
    required this.type,
    required this.url,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.publicId,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: (json[_keyId] ?? "").toString(),
      type: (json[_keyType] ?? "").toString(),
      url: (json[_keyUrl] ?? "").toString(),
      filename: (json[_keyFilename] ?? "").toString(),
      mimeType: (json[_keyMimeType] ?? "").toString(),
      sizeBytes: (json[_keySizeBytes] ?? 0) as int,
      publicId: (json[_keyPublicId] ?? "").toString(),
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String businessId;
  final String senderUserId;
  final String type;
  final String body;
  final String senderName;
  final String senderRole;
  final String clientMessageId;
  final String eventType;
  final Map<String, dynamic>? eventData;
  final ChatMessageStatus? status;
  final DateTime? deliveredAt;
  final DateTime? seenAt;
  final DateTime? createdAt;
  final bool isInternalNote;
  final String failureMessage;
  final List<ChatAttachment> attachments;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.businessId,
    required this.senderUserId,
    required this.type,
    required this.body,
    required this.senderName,
    required this.senderRole,
    required this.clientMessageId,
    required this.eventType,
    required this.eventData,
    required this.status,
    required this.deliveredAt,
    required this.seenAt,
    required this.createdAt,
    required this.isInternalNote,
    required this.failureMessage,
    required this.attachments,
  });

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? businessId,
    String? senderUserId,
    String? type,
    String? body,
    String? senderName,
    String? senderRole,
    String? clientMessageId,
    String? eventType,
    Map<String, dynamic>? eventData,
    ChatMessageStatus? status,
    bool clearStatus = false,
    DateTime? deliveredAt,
    bool clearDeliveredAt = false,
    DateTime? seenAt,
    bool clearSeenAt = false,
    DateTime? createdAt,
    bool? isInternalNote,
    String? failureMessage,
    List<ChatAttachment>? attachments,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      businessId: businessId ?? this.businessId,
      senderUserId: senderUserId ?? this.senderUserId,
      type: type ?? this.type,
      body: body ?? this.body,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      eventType: eventType ?? this.eventType,
      eventData: eventData ?? this.eventData,
      status: clearStatus ? null : (status ?? this.status),
      deliveredAt: clearDeliveredAt ? null : (deliveredAt ?? this.deliveredAt),
      seenAt: clearSeenAt ? null : (seenAt ?? this.seenAt),
      createdAt: createdAt ?? this.createdAt,
      isInternalNote: isInternalNote ?? this.isInternalNote,
      failureMessage: failureMessage ?? this.failureMessage,
      attachments: attachments ?? this.attachments,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json[_keyAttachmentIds];
    final attachments = (rawAttachments is List)
        ? rawAttachments
              .whereType<Map<String, dynamic>>()
              .map(ChatAttachment.fromJson)
              .toList()
        : <ChatAttachment>[];

    return ChatMessage(
      id: (json[_keyId] ?? "").toString(),
      conversationId: (json[_keyConversationId] ?? "").toString(),
      businessId: (json[_keyBusinessId] ?? "").toString(),
      senderUserId: (json[_keySenderUserId] ?? "").toString(),
      type: (json[_keyType] ?? "").toString(),
      body: (json[_keyBody] ?? "").toString(),
      senderName: (json["senderName"] ?? "").toString(),
      senderRole: (json["senderRole"] ?? "").toString(),
      clientMessageId: (json[_keyClientMessageId] ?? "").toString(),
      eventType: (json[_keyEventType] ?? "").toString(),
      eventData: json[_keyEventData] is Map<String, dynamic>
          ? json[_keyEventData] as Map<String, dynamic>
          : null,
      status: _parseMessageStatus(json["status"]),
      deliveredAt: _parseDate(json["deliveredAt"]),
      seenAt: _parseDate(json["seenAt"]),
      createdAt: _parseDate(json[_keyCreatedAt]),
      isInternalNote: json["isInternalNote"] == true,
      failureMessage: (json["failureMessage"] ?? "").toString(),
      attachments: attachments,
    );
  }
}
