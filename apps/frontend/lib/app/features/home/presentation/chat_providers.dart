/// lib/app/features/home/presentation/chat_providers.dart
/// ------------------------------------------------------
/// WHAT:
/// - Riverpod providers + controllers for chat state.
///
/// WHY:
/// - Keeps socket + REST wiring out of widgets.
/// - Centralizes optimistic UI and message reconciliation.
///
/// HOW:
/// - Provides ChatApi + ChatSocketService instances.
/// - Exposes inbox + thread state via providers.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_api.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/chat_constants.dart';
import 'package:frontend/app/features/home/presentation/chat_socket_service.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

// WHY: Consistent logging for chat providers.
const String _logTag = "CHAT_PROVIDERS";
const String _apiProviderCreated = "chatApiProvider created";
const String _socketProviderCreated = "chatSocketProvider created";
const String _inboxFetchStart = "chatInboxProvider fetch start";
const String _contactsFetchStart = "chatContactsProvider fetch start";
const String _threadLoadStart = "chatThread load start";
const String _threadLoadSuccess = "chatThread load success";
const String _threadLoadFail = "chatThread load failed";
const String _detailLoadStart = "chatDetail load start";
const String _detailLoadSuccess = "chatDetail load success";
const String _detailLoadFail = "chatDetail load failed";
const String _threadSendStart = "chatThread send start";
const String _threadSendSuccess = "chatThread send success";
const String _threadSendFail = "chatThread send failed";
const String _threadAttachStart = "chatThread attach start";
const String _threadAttachSuccess = "chatThread attach success";
const String _threadAttachFail = "chatThread attach failed";
const String _sessionMissingMessage = "session missing";
const String _sessionExpiredMessage = "Session expired. Please sign in again.";
const String _nextActionSignIn = "Sign in and retry.";
const String _extraReasonKey = "reason";
const String _extraNextActionKey = "next_action";
const String _reasonInboxMissing = "chat_inbox_session_missing";
const String _reasonContactsMissing = "chat_contacts_session_missing";
const String _reasonThreadMissing = "chat_thread_session_missing";
const String _reasonDetailMissing = "chat_detail_session_missing";

final chatApiProvider = Provider<ChatApi>((ref) {
  AppDebug.log(_logTag, _apiProviderCreated);
  final dio = ref.read(dioProvider);
  return ChatApi(dio: dio);
});

final chatSocketProvider = Provider<ChatSocketService>((ref) {
  AppDebug.log(_logTag, _socketProviderCreated);
  final service = ChatSocketService();
  ref.onDispose(service.dispose);
  return service;
});

final chatInboxProvider = FutureProvider<List<ChatConversation>>((ref) async {
  AppDebug.log(_logTag, _inboxFetchStart);

  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log(
      _logTag,
      _sessionMissingMessage,
      extra: {
        _extraReasonKey: _reasonInboxMissing,
        _extraNextActionKey: _nextActionSignIn,
      },
    );
    throw Exception(_sessionExpiredMessage);
  }

  final api = ref.read(chatApiProvider);
  return api.fetchConversations(token: session.token);
});

final chatContactsProvider = FutureProvider<List<ChatContact>>((ref) async {
  AppDebug.log(_logTag, _contactsFetchStart);

  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log(
      _logTag,
      _sessionMissingMessage,
      extra: {
        _extraReasonKey: _reasonContactsMissing,
        _extraNextActionKey: _nextActionSignIn,
      },
    );
    throw Exception(_sessionExpiredMessage);
  }

  final api = ref.read(chatApiProvider);
  return api.fetchContacts(token: session.token);
});

final chatInboxRealtimeProvider = Provider.autoDispose<void>((ref) {
  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    return;
  }

  final socket = ref.watch(chatSocketProvider);
  socket.connect(token: session.token);

  final messageSub = socket.messageStream.listen((_) {
    ref.invalidate(chatInboxProvider);
  });
  final readSub = socket.readStream.listen((_) {
    ref.invalidate(chatInboxProvider);
  });

  ref.onDispose(() {
    messageSub.cancel();
    readSub.cancel();
  });
});

final chatUnreadCountProvider = Provider.autoDispose<int>((ref) {
  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    return 0;
  }

  ref.watch(chatInboxRealtimeProvider);
  final conversationsAsync = ref.watch(chatInboxProvider);
  return conversationsAsync.maybeWhen(
    data: (conversations) => conversations.fold<int>(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    ),
    orElse: () => 0,
  );
});

final chatConversationDetailProvider =
    FutureProvider.family<ChatConversationDetail, String>((ref, id) async {
      AppDebug.log(_logTag, _detailLoadStart, extra: {"id": id});

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonDetailMissing,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      try {
        final api = ref.read(chatApiProvider);
        final detail = await api.fetchConversationDetail(
          token: session.token,
          conversationId: id,
        );
        AppDebug.log(_logTag, _detailLoadSuccess, extra: {"id": id});
        return detail;
      } catch (error) {
        AppDebug.log(
          _logTag,
          _detailLoadFail,
          extra: {"error": error.toString()},
        );
        rethrow;
      }
    });

class ChatThreadState {
  final List<ChatMessage> messages;
  final List<ChatAttachment> pendingAttachments;
  final bool isLoading;
  final bool isSending;
  final String? error;

  const ChatThreadState({
    required this.messages,
    required this.pendingAttachments,
    required this.isLoading,
    required this.isSending,
    required this.error,
  });

  factory ChatThreadState.initial() {
    return const ChatThreadState(
      messages: [],
      pendingAttachments: [],
      isLoading: true,
      isSending: false,
      error: null,
    );
  }

  ChatThreadState copyWith({
    List<ChatMessage>? messages,
    List<ChatAttachment>? pendingAttachments,
    bool? isLoading,
    bool? isSending,
    String? error,
  }) {
    return ChatThreadState(
      messages: messages ?? this.messages,
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}

class ChatThreadController extends StateNotifier<ChatThreadState> {
  final Ref _ref;
  final String conversationId;
  StreamSubscription? _messageSub;
  StreamSubscription? _readSub;

  ChatThreadController({required Ref ref, required this.conversationId})
    : _ref = ref,
      super(ChatThreadState.initial()) {
    _init();
  }

  void _init() {
    // WHY: Load initial messages then wire socket listeners.
    _loadInitial();
    _listenSocket();
  }

  Future<void> _loadInitial() async {
    AppDebug.log(_logTag, _threadLoadStart, extra: {"id": conversationId});

    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonThreadMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      state = state.copyWith(isLoading: false, error: _sessionExpiredMessage);
      return;
    }

    try {
      final api = _ref.read(chatApiProvider);
      final messages = await api.fetchMessages(
        token: session.token,
        conversationId: conversationId,
      );

      state = state.copyWith(
        isLoading: false,
        messages: messages.reversed.map(_normalizeServerMessage).toList(),
        error: null,
      );

      await _markRead(messages);

      AppDebug.log(
        _logTag,
        _threadLoadSuccess,
        extra: {"count": messages.length},
      );
    } catch (error) {
      AppDebug.log(
        _logTag,
        _threadLoadFail,
        extra: {"error": error.toString()},
      );
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void _listenSocket() {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) return;

    final socket = _ref.read(chatSocketProvider);
    socket.connect(token: session.token);
    socket.joinConversation(conversationId);

    _messageSub = socket.messageStream.listen((event) {
      if (event.conversationId != conversationId) return;
      final updated = _mergeMessage(
        state.messages,
        _normalizeServerMessage(event.message),
      );
      state = state.copyWith(messages: updated);
      _ref.invalidate(chatInboxProvider);
      _ref.invalidate(chatConversationDetailProvider(conversationId));
      if (event.message.eventType.trim().isNotEmpty) {
        _ref.invalidate(chatConversationDetailProvider(conversationId));
      }
      _markRead([event.message]);
    });

    _readSub = socket.readStream.listen((event) {
      if (event.conversationId != conversationId) return;
      _ref.invalidate(chatConversationDetailProvider(conversationId));
    });
  }

  Future<void> _markRead(List<ChatMessage> messages) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) return;

    final currentUserId = session.user.id;
    final unread = messages
        .where((msg) => msg.senderUserId != currentUserId)
        .map((msg) => msg.id)
        .toList();

    if (unread.isEmpty) return;

    try {
      final api = _ref.read(chatApiProvider);
      await api.markMessagesRead(
        token: session.token,
        conversationId: conversationId,
        messageIds: unread,
      );
      _ref.invalidate(chatInboxProvider);
    } catch (_) {
      // WHY: Read receipts are non-blocking; ignore failures.
    }
  }

  Future<void> addAttachment({
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) async {
    AppDebug.log(_logTag, _threadAttachStart);
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      state = state.copyWith(error: _sessionExpiredMessage);
      return;
    }

    try {
      final api = _ref.read(chatApiProvider);
      final attachment = await api.uploadAttachment(
        token: session.token,
        conversationId: conversationId,
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      final updated = [...state.pendingAttachments, attachment];
      state = state.copyWith(pendingAttachments: updated, error: null);
      AppDebug.log(_logTag, _threadAttachSuccess);
    } catch (error) {
      AppDebug.log(
        _logTag,
        _threadAttachFail,
        extra: {"error": error.toString()},
      );
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> addAttachmentFile({
    required String filePath,
    required String filename,
    String? mimeType,
  }) async {
    AppDebug.log(_logTag, _threadAttachStart);
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      state = state.copyWith(error: _sessionExpiredMessage);
      return;
    }

    try {
      final api = _ref.read(chatApiProvider);
      final attachment = await api.uploadAttachmentFile(
        token: session.token,
        conversationId: conversationId,
        filePath: filePath,
        filename: filename,
        mimeType: mimeType,
      );
      final updated = [...state.pendingAttachments, attachment];
      state = state.copyWith(pendingAttachments: updated, error: null);
      AppDebug.log(_logTag, _threadAttachSuccess);
    } catch (error) {
      AppDebug.log(
        _logTag,
        _threadAttachFail,
        extra: {"error": error.toString()},
      );
      state = state.copyWith(error: error.toString());
    }
  }

  void removeAttachment(String attachmentId) {
    final updated = state.pendingAttachments
        .where((attachment) => attachment.id != attachmentId)
        .toList();
    state = state.copyWith(pendingAttachments: updated);
  }

  Future<void> sendMessage({required String body}) async {
    final attachments = [...state.pendingAttachments];
    await _submitMessage(body: body, attachments: attachments);
  }

  Future<void> retryMessage(String messageId) async {
    final failedMessage = state.messages.firstWhere(
      (message) => message.id == messageId,
    );
    await _submitMessage(
      body: failedMessage.body,
      attachments: failedMessage.attachments,
      replaceMessageId: failedMessage.id,
    );
  }

  Future<void> _submitMessage({
    required String body,
    required List<ChatAttachment> attachments,
    String? replaceMessageId,
  }) async {
    AppDebug.log(_logTag, _threadSendStart);
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      state = state.copyWith(error: _sessionExpiredMessage);
      return;
    }

    final clientMessageId = "client-${DateTime.now().microsecondsSinceEpoch}";
    final tempMessage = ChatMessage(
      id: "temp-${DateTime.now().millisecondsSinceEpoch}",
      conversationId: conversationId,
      businessId: session.user.businessId ?? "",
      senderUserId: session.user.id,
      type: body.trim().isEmpty
          ? chatMessageTypeAttachment
          : chatMessageTypeText,
      body: body.trim(),
      senderName: "",
      senderRole: session.user.role,
      clientMessageId: clientMessageId,
      eventType: "",
      eventData: null,
      status: ChatMessageStatus.sending,
      deliveredAt: null,
      seenAt: null,
      createdAt: DateTime.now(),
      isInternalNote: false,
      failureMessage: "",
      attachments: attachments,
    );

    final baseMessages = replaceMessageId == null
        ? state.messages
        : state.messages.where((msg) => msg.id != replaceMessageId).toList();

    state = state.copyWith(
      isSending: true,
      pendingAttachments: [],
      messages: [...baseMessages, tempMessage],
    );

    try {
      final api = _ref.read(chatApiProvider);
      final message = await api.sendMessage(
        token: session.token,
        payload: {
          "conversationId": conversationId,
          "body": body.trim(),
          "clientMessageId": clientMessageId,
          "attachmentIds": attachments.map((att) => att.id).toList(),
        },
      );

      final updated = _mergeMessage(
        state.messages.where((msg) => msg.id != tempMessage.id).toList(),
        _normalizeServerMessage(message),
      );

      state = state.copyWith(isSending: false, messages: updated, error: null);
      _ref.invalidate(chatInboxProvider);
      _ref.invalidate(chatConversationDetailProvider(conversationId));

      AppDebug.log(_logTag, _threadSendSuccess);
    } catch (error) {
      AppDebug.log(
        _logTag,
        _threadSendFail,
        extra: {"error": error.toString()},
      );
      final failedMessages = state.messages
          .map(
            (message) => message.id == tempMessage.id
                ? message.copyWith(
                    status: ChatMessageStatus.failed,
                    failureMessage: error.toString(),
                  )
                : message,
          )
          .toList();
      state = state.copyWith(
        isSending: false,
        messages: failedMessages,
        error: error.toString(),
      );
    }
  }

  @override
  void dispose() {
    final socket = _ref.read(chatSocketProvider);
    socket.leaveConversation(conversationId);
    _messageSub?.cancel();
    _readSub?.cancel();
    super.dispose();
  }
}

ChatMessage _normalizeServerMessage(ChatMessage message) {
  final deliveredAt = message.deliveredAt ?? message.createdAt;
  final status = message.status ?? ChatMessageStatus.delivered;
  return message.copyWith(
    status: status,
    deliveredAt: deliveredAt,
    failureMessage: "",
  );
}

List<ChatMessage> _mergeMessage(
  List<ChatMessage> current,
  ChatMessage incoming,
) {
  final updated =
      current
          .where(
            (message) =>
                message.id != incoming.id &&
                !(message.clientMessageId.trim().isNotEmpty &&
                    message.clientMessageId == incoming.clientMessageId),
          )
          .toList()
        ..add(incoming);

  updated.sort((left, right) {
    final leftTime = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightTime = right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timeCompare = leftTime.compareTo(rightTime);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return left.id.compareTo(right.id);
  });
  return updated;
}

final chatThreadProvider =
    StateNotifierProvider.family<ChatThreadController, ChatThreadState, String>(
      (ref, conversationId) {
        return ChatThreadController(ref: ref, conversationId: conversationId);
      },
    );
