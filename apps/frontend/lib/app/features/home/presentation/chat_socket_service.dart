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
  String? _token;
  final Map<String, int> _conversationRefs = <String, int>{};
  final _messageController =
      StreamController<ChatSocketMessageEvent>.broadcast();
  final _readController = StreamController<ChatSocketReadEvent>.broadcast();

  Stream<ChatSocketMessageEvent> get messageStream => _messageController.stream;
  Stream<ChatSocketReadEvent> get readStream => _readController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect({required String token}) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return;

    if (_socket != null && _token == normalizedToken) {
      if (isConnected) {
        _rejoinTrackedConversations();
        return;
      }
      _socket?.connect();
      return;
    }

    final tokenChanged = _token != null && _token != normalizedToken;
    _disposeSocket(clearTrackedConversations: tokenChanged);
    _token = normalizedToken;

    AppDebug.log(_logTag, _logConnectStart);

    _socket = io.io(
      AppConstants.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({"token": "Bearer $normalizedToken"})
          .enableForceNew()
          .build(),
    );

    _socket?.onConnect((_) {
      AppDebug.log(_logTag, _logConnectOk);
      _rejoinTrackedConversations();
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

    _socket?.connect();
  }

  void _rejoinTrackedConversations() {
    if (!isConnected) return;
    for (final conversationId in _conversationRefs.keys) {
      _emitJoin(conversationId);
    }
  }

  void _emitJoin(String conversationId) {
    _socket?.emit(chatEventConversationJoin, {
      "conversationId": conversationId,
    });
  }

  void joinConversation(String conversationId) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return;

    final currentCount = _conversationRefs[normalizedId] ?? 0;
    _conversationRefs[normalizedId] = currentCount + 1;

    if (currentCount > 0) {
      return;
    }

    AppDebug.log(_logTag, _logJoin, extra: {"conversationId": normalizedId});

    if (isConnected) {
      _emitJoin(normalizedId);
      return;
    }

    _socket?.connect();
  }

  void leaveConversation(String conversationId) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return;

    final currentCount = _conversationRefs[normalizedId] ?? 0;
    if (currentCount <= 1) {
      _conversationRefs.remove(normalizedId);
      AppDebug.log(_logTag, _logLeave, extra: {"conversationId": normalizedId});
      if (isConnected) {
        _socket?.emit(chatEventConversationLeave, {
          "conversationId": normalizedId,
        });
      }
      return;
    }

    _conversationRefs[normalizedId] = currentCount - 1;
  }

  void emitRead({
    required String conversationId,
    required List<String> messageIds,
  }) {
    if (!isConnected || conversationId.trim().isEmpty) return;
    AppDebug.log(_logTag, _logReadEmit, extra: {"count": messageIds.length});
    _socket?.emit(chatEventMessageRead, {
      "conversationId": conversationId,
      "messageIds": messageIds,
    });
  }

  void disconnect() {
    _token = null;
    _disposeSocket(clearTrackedConversations: true);
  }

  void _disposeSocket({required bool clearTrackedConversations}) {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    if (clearTrackedConversations) {
      _conversationRefs.clear();
    }
  }

  void dispose() {
    _messageController.close();
    _readController.close();
    disconnect();
  }
}
