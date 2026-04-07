/// lib/app/features/home/presentation/chat_routes.dart
/// ---------------------------------------------------
/// WHAT:
/// - Route constants for chat screens.
///
/// WHY:
/// - Prevents inline route strings across the UI.
/// - Keeps navigation targets consistent and discoverable.
///
/// HOW:
/// - Exposes chat inbox + thread route patterns.
library;

// WHY: Chat inbox sits at the top-level for quick access.
const String chatInboxRoute = "/chat";

// WHY: Thread route embeds the conversation id.
const String chatThreadRouteBase = "/chat";
const String chatThreadRouteParam = "id";
const String chatProfileRouteSegment = "profile";
const String chatProfileUserQuery = "userId";

String buildChatThreadRoute(String conversationId) {
  return "$chatThreadRouteBase/$conversationId";
}

String buildChatProfileRoute(String conversationId, {String? userId}) {
  final base =
      "${buildChatThreadRoute(conversationId)}/$chatProfileRouteSegment";
  final normalizedUserId = userId?.trim() ?? "";
  if (normalizedUserId.isEmpty) {
    return base;
  }
  final query = Uri(
    queryParameters: {chatProfileUserQuery: normalizedUserId},
  ).query;
  return "$base?$query";
}
