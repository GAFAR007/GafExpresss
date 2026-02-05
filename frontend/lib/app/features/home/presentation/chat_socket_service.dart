/// lib/app/features/home/presentation/chat_socket_service.dart
/// -----------------------------------------------------------
/// WHAT:
/// - Socket.IO client wrapper for chat realtime events.
///
/// WHY:
/// - Keeps socket setup out of widgets.
/// - Centralizes join/leave and message stream handling.
///
/// HOW:
/// - Connects to backend Socket.IO with auth token.
/// - Emits join/leave/read events.
/// - Exposes message/read streams for UI to subscribe.
library;

import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/constants/app_constants.dart';
import 'package:frontend/app/features/home/presentation/chat_constants.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';

// WHY: Keep log tag consistent for socket events.
const String _logTag = "CHAT_SOCKET";
const String _logConnectStart = "connect_start";
const String _logConnectOk = "connect_ok";
const String _logConnectFail = "connect_fail";
const String _logDisconnect = "disconnect";
const String _logJoin = "join";
const String _logLeave = "leave";
const String _logReadEmit = "read_emit";
const String _logMessageEvent = "message_event";
const String _logErrorEvent = "error_event";

class ChatSocketMessageEvent {
  final String conversationId;
  final ChatMessage message;

  const ChatSocketMessageEvent({
    required this.conversationId,
    required this.message,
  });
}

class ChatSocketReadEvent {
  final String conversationId;
  final List<String> messageIds;
  final String readBy;
  final DateTime? readAt;

  const ChatSocketReadEvent({
    required this.conversationId,
    required this.messageIds,
    required this.readBy,
    required this.readAt,
  });
}

class ChatSocketService {
  io.Socket? _socket;
  final _messageController =
      StreamController<ChatSocketMessageEvent>.broadcast();
  final _readController =
      StreamController<ChatSocketReadEvent>.broadcast();

  Stream<ChatSocketMessageEvent> get messageStream =>
      _messageController.stream;
  Stream<ChatSocketReadEvent> get readStream => _readController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect({required String token}) {
    if (isConnected) return;

    AppDebug.log(_logTag, _logConnectStart);

    _socket = io.io(
      AppConstants.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({"token": "Bearer $token"})
          .enableForceNew()
          .build(),
    );

    _socket?.onConnect((_) {
      AppDebug.log(_logTag, _logConnectOk);
    });

    _socket?.onDisconnect((_) {
      AppDebug.log(_logTag, _logDisconnect);
    });

    _socket?.onConnectError((error) {
      AppDebug.log(
        _logTag,
        _logConnectFail,
        extra: {"error": error.toString()},
      );
    });

    _socket?.on(chatEventMessageNew, (payload) {
      AppDebug.log(_logTag, _logMessageEvent);
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      final conversationId = map["conversationId"]?.toString() ?? "";
      final messageMap = map["message"] as Map<String, dynamic>?;
      if (conversationId.isEmpty || messageMap == null) return;

      _messageController.add(
        ChatSocketMessageEvent(
          conversationId: conversationId,
          message: ChatMessage.fromJson(messageMap),
        ),
      );
    });

    _socket?.on(chatEventMessageRead, (payload) {
      AppDebug.log(_logTag, _logMessageEvent);
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      final conversationId = map["conversationId"]?.toString() ?? "";
      final messageIds = (map["messageIds"] as List<dynamic>? ?? [])
          .map((id) => id.toString())
          .toList();
      final readBy = map["readBy"]?.toString() ?? "";
      final readAt = DateTime.tryParse(map["readAt"]?.toString() ?? "");
      if (conversationId.isEmpty || readBy.isEmpty) return;

      _readController.add(
        ChatSocketReadEvent(
          conversationId: conversationId,
          messageIds: messageIds,
          readBy: readBy,
          readAt: readAt,
        ),
      );
    });

    _socket?.on(chatEventError, (payload) {
      AppDebug.log(
        _logTag,
        _logErrorEvent,
        extra: {"payload": payload.toString()},
      );
    });
  }

  void joinConversation(String conversationId) {
    if (!isConnected || conversationId.trim().isEmpty) return;
    AppDebug.log(_logTag, _logJoin, extra: {"conversationId": conversationId});
    _socket?.emit(
      chatEventConversationJoin,
      {"conversationId": conversationId},
    );
  }

  void leaveConversation(String conversationId) {
    if (!isConnected || conversationId.trim().isEmpty) return;
    AppDebug.log(_logTag, _logLeave, extra: {"conversationId": conversationId});
    _socket?.emit(
      chatEventConversationLeave,
      {"conversationId": conversationId},
    );
  }

  void emitRead({
    required String conversationId,
    required List<String> messageIds,
  }) {
    if (!isConnected || conversationId.trim().isEmpty) return;
    AppDebug.log(_logTag, _logReadEmit, extra: {"count": messageIds.length});
    _socket?.emit(
      chatEventMessageRead,
      {
        "conversationId": conversationId,
        "messageIds": messageIds,
      },
    );
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    _messageController.close();
    _readController.close();
    disconnect();
  }
}
