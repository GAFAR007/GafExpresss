/// lib/app/features/home/presentation/chat_constants.dart
/// ------------------------------------------------------
/// WHAT:
/// - Shared constants for chat UI + socket events.
///
/// WHY:
/// - Prevents magic strings across chat widgets and services.
/// - Keeps event names aligned with backend expectations.
///
/// HOW:
/// - Exposes event names, message types, and UI copy tokens.
library;

// WHY: Socket event names must match backend chat constants.
const String chatEventMessageNew = "message:new";
const String chatEventMessageRead = "message:read";
const String chatEventConversationJoin = "conversation:join";
const String chatEventConversationLeave = "conversation:leave";
const String chatEventError = "chat:error";

// WHY: Message types map to rendering logic.
const String chatMessageTypeText = "text";
const String chatMessageTypeAttachment = "attachment";
const String chatMessageTypeSystem = "system";

// WHY: Conversation types map to UI labels.
const String chatConversationTypeDirect = "direct";
const String chatConversationTypeGroup = "group";
