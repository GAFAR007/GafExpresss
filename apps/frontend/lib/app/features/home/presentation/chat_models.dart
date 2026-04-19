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
const String _keyAccountRole = "accountRole";
const String _keyCanJoinGroup = "canJoinGroup";
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
const String _keyMediaMode = "mediaMode";
const String _keyState = "state";
const String _keyCallerUserId = "callerUserId";
const String _keyCalleeUserId = "calleeUserId";
const String _keyCallerName = "callerName";
const String _keyCalleeName = "calleeName";
const String _keyCallerRole = "callerRole";
const String _keyCalleeRole = "calleeRole";
const String _keyCallerProfileImageUrl = "callerProfileImageUrl";
const String _keyCalleeProfileImageUrl = "calleeProfileImageUrl";
const String _keyRingTimeoutAt = "ringTimeoutAt";
const String _keyAnsweredAt = "answeredAt";
const String _keyEndedAt = "endedAt";
const String _keyEndedByUserId = "endedByUserId";
const String _keyEndedByName = "endedByName";
const String _keyEndReason = "endReason";
const String _keyDurationSeconds = "durationSeconds";
const String _keyCallId = "callId";
const String _keySdp = "sdp";
const String _keyCandidate = "candidate";
const String _keySdpMid = "sdpMid";
const String _keySdpMLineIndex = "sdpMLineIndex";

DateTime? _parseDate(dynamic value) {
  // WHY: Prevent crashes on invalid timestamps.
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
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

class ChatContact {
  final String userId;
  final String name;
  final String email;
  final String profileImageUrl;
  final String role;
  final String accountRole;
  final String businessId;
  final String businessName;
  final String estateAssetId;
  final String estateName;
  final bool canJoinGroup;

  const ChatContact({
    required this.userId,
    required this.name,
    required this.email,
    required this.profileImageUrl,
    required this.role,
    required this.accountRole,
    required this.businessId,
    required this.businessName,
    required this.estateAssetId,
    required this.estateName,
    required this.canJoinGroup,
  });

  factory ChatContact.fromJson(Map<String, dynamic> json) {
    return ChatContact(
      userId: (json[_keyUserId] ?? "").toString(),
      name: (json[_keyName] ?? "").toString(),
      email: (json[_keyEmail] ?? "").toString(),
      profileImageUrl: (json[_keyProfileImageUrl] ?? "").toString(),
      role: (json[_keyRole] ?? "").toString(),
      accountRole: (json[_keyAccountRole] ?? "").toString(),
      businessId: (json[_keyBusinessId] ?? "").toString(),
      businessName: (json[_keyBusinessName] ?? "").toString(),
      estateAssetId: (json[_keyEstateAssetId] ?? "").toString(),
      estateName: (json[_keyEstateName] ?? "").toString(),
      canJoinGroup: json[_keyCanJoinGroup] == true,
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

class ChatCallSession {
  final String id;
  final String conversationId;
  final String businessId;
  final String mediaMode;
  final String state;
  final String callerUserId;
  final String callerName;
  final String callerRole;
  final String callerProfileImageUrl;
  final String calleeUserId;
  final String calleeName;
  final String calleeRole;
  final String calleeProfileImageUrl;
  final DateTime? ringTimeoutAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String endedByUserId;
  final String endedByName;
  final String endReason;
  final int durationSeconds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ChatCallSession({
    required this.id,
    required this.conversationId,
    required this.businessId,
    required this.mediaMode,
    required this.state,
    required this.callerUserId,
    required this.callerName,
    required this.callerRole,
    required this.callerProfileImageUrl,
    required this.calleeUserId,
    required this.calleeName,
    required this.calleeRole,
    required this.calleeProfileImageUrl,
    required this.ringTimeoutAt,
    required this.answeredAt,
    required this.endedAt,
    required this.endedByUserId,
    required this.endedByName,
    required this.endReason,
    required this.durationSeconds,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isRinging => state == "ringing";
  bool get isActive => state == "active";
  bool get isTerminal =>
      state == "declined" ||
      state == "ended" ||
      state == "missed" ||
      state == "cancelled";

  bool isIncomingFor(String currentUserId) => calleeUserId == currentUserId;

  String peerUserIdFor(String currentUserId) {
    return currentUserId == callerUserId ? calleeUserId : callerUserId;
  }

  String peerNameFor(String currentUserId) {
    return currentUserId == callerUserId ? calleeName : callerName;
  }

  String peerProfileImageUrlFor(String currentUserId) {
    return currentUserId == callerUserId
        ? calleeProfileImageUrl
        : callerProfileImageUrl;
  }

  ChatCallSession copyWith({
    String? id,
    String? conversationId,
    String? businessId,
    String? mediaMode,
    String? state,
    String? callerUserId,
    String? callerName,
    String? callerRole,
    String? callerProfileImageUrl,
    String? calleeUserId,
    String? calleeName,
    String? calleeRole,
    String? calleeProfileImageUrl,
    DateTime? ringTimeoutAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endedByUserId,
    String? endedByName,
    String? endReason,
    int? durationSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatCallSession(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      businessId: businessId ?? this.businessId,
      mediaMode: mediaMode ?? this.mediaMode,
      state: state ?? this.state,
      callerUserId: callerUserId ?? this.callerUserId,
      callerName: callerName ?? this.callerName,
      callerRole: callerRole ?? this.callerRole,
      callerProfileImageUrl:
          callerProfileImageUrl ?? this.callerProfileImageUrl,
      calleeUserId: calleeUserId ?? this.calleeUserId,
      calleeName: calleeName ?? this.calleeName,
      calleeRole: calleeRole ?? this.calleeRole,
      calleeProfileImageUrl:
          calleeProfileImageUrl ?? this.calleeProfileImageUrl,
      ringTimeoutAt: ringTimeoutAt ?? this.ringTimeoutAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      endedByUserId: endedByUserId ?? this.endedByUserId,
      endedByName: endedByName ?? this.endedByName,
      endReason: endReason ?? this.endReason,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ChatCallSession.fromJson(Map<String, dynamic> json) {
    return ChatCallSession(
      id: (json[_keyId] ?? json[_keyCallId] ?? "").toString(),
      conversationId: (json[_keyConversationId] ?? "").toString(),
      businessId: (json[_keyBusinessId] ?? "").toString(),
      mediaMode: (json[_keyMediaMode] ?? "").toString(),
      state: (json[_keyState] ?? "").toString(),
      callerUserId: (json[_keyCallerUserId] ?? "").toString(),
      callerName: (json[_keyCallerName] ?? "").toString(),
      callerRole: (json[_keyCallerRole] ?? "").toString(),
      callerProfileImageUrl: (json[_keyCallerProfileImageUrl] ?? "").toString(),
      calleeUserId: (json[_keyCalleeUserId] ?? "").toString(),
      calleeName: (json[_keyCalleeName] ?? "").toString(),
      calleeRole: (json[_keyCalleeRole] ?? "").toString(),
      calleeProfileImageUrl: (json[_keyCalleeProfileImageUrl] ?? "").toString(),
      ringTimeoutAt: _parseDate(json[_keyRingTimeoutAt]),
      answeredAt: _parseDate(json[_keyAnsweredAt]),
      endedAt: _parseDate(json[_keyEndedAt]),
      endedByUserId: (json[_keyEndedByUserId] ?? "").toString(),
      endedByName: (json[_keyEndedByName] ?? "").toString(),
      endReason: (json[_keyEndReason] ?? "").toString(),
      durationSeconds: _parseInt(json[_keyDurationSeconds]) ?? 0,
      createdAt: _parseDate(json[_keyCreatedAt]),
      updatedAt: _parseDate(json["updatedAt"]),
    );
  }
}

class ChatCallSignalPayload {
  final String type;
  final String sdp;
  final String candidate;
  final String sdpMid;
  final int? sdpMLineIndex;

  const ChatCallSignalPayload({
    required this.type,
    required this.sdp,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  bool get isOffer => type == "offer";
  bool get isAnswer => type == "answer";
  bool get isCandidate => type == "candidate";

  Map<String, dynamic> toJson() {
    return {
      _keyType: type,
      if (sdp.isNotEmpty) _keySdp: sdp,
      if (candidate.isNotEmpty) _keyCandidate: candidate,
      if (sdpMid.isNotEmpty) _keySdpMid: sdpMid,
      if (sdpMLineIndex != null) _keySdpMLineIndex: sdpMLineIndex,
    };
  }

  factory ChatCallSignalPayload.fromJson(Map<String, dynamic> json) {
    return ChatCallSignalPayload(
      type: (json[_keyType] ?? "").toString(),
      sdp: (json[_keySdp] ?? "").toString(),
      candidate: (json[_keyCandidate] ?? "").toString(),
      sdpMid: (json[_keySdpMid] ?? "").toString(),
      sdpMLineIndex: _parseInt(json[_keySdpMLineIndex]),
    );
  }
}
