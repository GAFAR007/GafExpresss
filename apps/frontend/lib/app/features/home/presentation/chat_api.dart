/// lib/app/features/home/presentation/chat_api.dart
/// -----------------------------------------------
/// WHAT:
/// - REST client for chat conversations, messages, and attachments.
///
/// WHY:
/// - Keeps chat networking out of widgets.
/// - Centralizes auth + response parsing + logging.
///
/// HOW:
/// - Uses Dio for HTTP calls with Bearer tokens.
/// - Maps responses into chat models.
/// - Logs request start/success/failure for traceability.
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_constants.dart';
import 'chat_models.dart';

// WHY: Centralize endpoint paths to avoid magic strings.
const String _conversationsPath = "/chat/conversations";
const String _contactsPath = "/chat/contacts";
const String _messagesPath = "/chat/messages";
const String _messageReadPath = "/chat/messages/read";
const String _attachmentsPath = "/chat/attachments";
const String _callsPath = "/chat/calls";

// WHY: Consistent logs for chat requests.
const String _logTag = "CHAT_API";
const String _serviceName = "chat_api";
const String _intentList = "load conversations";
const String _intentCreate = "create conversation";
const String _intentContacts = "load chat contacts";
const String _intentMessages = "load messages";
const String _intentDetail = "load conversation detail";
const String _intentSend = "send message";
const String _intentRead = "mark messages read";
const String _intentUpload = "upload attachment";
const String _intentStartCall = "start voice call";
const String _intentFetchCall = "load call";
const String _intentAcceptCall = "accept call";
const String _intentDeclineCall = "decline call";
const String _intentEndCall = "end call";
const String _operationList = "fetchConversations";
const String _operationCreate = "createConversation";
const String _operationContacts = "fetchContacts";
const String _operationMessages = "fetchMessages";
const String _operationDetail = "fetchConversationDetail";
const String _operationSend = "sendMessage";
const String _operationRead = "markMessagesRead";
const String _operationUpload = "uploadAttachment";
const String _operationStartCall = "startCall";
const String _operationFetchCall = "fetchCall";
const String _operationAcceptCall = "acceptCall";
const String _operationDeclineCall = "declineCall";
const String _operationEndCall = "endCall";
const String _nextActionRetry = "Retry the request or contact support.";
const String _missingTokenMessage = "Missing auth token";
const String _missingTokenLog = "auth token missing";
const String _authHeaderKey = "Authorization";
const String _extraServiceKey = "service";
const String _extraOperationKey = "operation";
const String _extraIntentKey = "intent";
const String _extraNextActionKey = "next_action";
const String _extraStatusKey = "status";
const String _extraReasonKey = "reason";
const String _extraCountKey = "count";

// WHY: Shared fallback values for failed requests.
const int _fallbackStatusCode = 0;
const String _fallbackErrorReason = "unknown_error";

class ChatApi {
  final Dio _dio;

  ChatApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log(
        _logTag,
        _missingTokenLog,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: "authOptions",
          _extraIntentKey: "ensure auth headers",
          _extraNextActionKey: _nextActionRetry,
        },
      );
      throw Exception(_missingTokenMessage);
    }
    return Options(headers: {_authHeaderKey: "Bearer $token"});
  }

  Future<List<ChatConversation>> fetchConversations({
    required String? token,
    String? businessId,
  }) async {
    AppDebug.log(
      _logTag,
      "fetchConversations() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationList,
        _extraIntentKey: _intentList,
      },
    );

    try {
      final resp = await _dio.get(
        _conversationsPath,
        queryParameters: {
          if (businessId != null && businessId.trim().isNotEmpty)
            "businessId": businessId.trim(),
        },
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final rawList = (data["conversations"] ?? []) as List<dynamic>;
      final conversations = rawList
          .whereType<Map<String, dynamic>>()
          .map(ChatConversation.fromJson)
          .toList();

      AppDebug.log(
        _logTag,
        "fetchConversations() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationList,
          _extraIntentKey: _intentList,
          _extraCountKey: conversations.length,
        },
      );

      return conversations;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchConversations() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationList,
          _extraIntentKey: _intentList,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatConversation> createConversation({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      "createConversation() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationCreate,
        _extraIntentKey: _intentCreate,
      },
    );

    try {
      final resp = await _dio.post(
        _conversationsPath,
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final convoMap = (data["conversation"] ?? {}) as Map<String, dynamic>;
      final conversation = ChatConversation.fromJson(convoMap);

      AppDebug.log(
        _logTag,
        "createConversation() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationCreate,
          _extraIntentKey: _intentCreate,
        },
      );

      return conversation;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "createConversation() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationCreate,
          _extraIntentKey: _intentCreate,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<List<ChatContact>> fetchContacts({required String? token}) async {
    AppDebug.log(
      _logTag,
      "fetchContacts() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationContacts,
        _extraIntentKey: _intentContacts,
      },
    );

    try {
      final resp = await _dio.get(_contactsPath, options: _authOptions(token));

      final data = resp.data as Map<String, dynamic>;
      final rawList = (data["contacts"] ?? []) as List<dynamic>;
      final contacts = rawList
          .whereType<Map<String, dynamic>>()
          .map(ChatContact.fromJson)
          .toList();

      AppDebug.log(
        _logTag,
        "fetchContacts() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationContacts,
          _extraIntentKey: _intentContacts,
          _extraCountKey: contacts.length,
        },
      );

      return contacts;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchContacts() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationContacts,
          _extraIntentKey: _intentContacts,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatConversationDetail> fetchConversationDetail({
    required String? token,
    required String conversationId,
  }) async {
    AppDebug.log(
      _logTag,
      "fetchConversationDetail() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationDetail,
        _extraIntentKey: _intentDetail,
      },
    );

    try {
      final resp = await _dio.get(
        "$_conversationsPath/$conversationId",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final detail = ChatConversationDetail.fromJson(data);

      AppDebug.log(
        _logTag,
        "fetchConversationDetail() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDetail,
          _extraIntentKey: _intentDetail,
        },
      );

      return detail;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchConversationDetail() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDetail,
          _extraIntentKey: _intentDetail,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<List<ChatMessage>> fetchMessages({
    required String? token,
    required String conversationId,
    int limit = 30,
    String? cursor,
  }) async {
    AppDebug.log(
      _logTag,
      "fetchMessages() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationMessages,
        _extraIntentKey: _intentMessages,
      },
    );

    try {
      final resp = await _dio.get(
        "$_conversationsPath/$conversationId/messages",
        queryParameters: {
          "limit": limit,
          if (cursor != null && cursor.trim().isNotEmpty)
            "cursor": cursor.trim(),
        },
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final rawList = (data["messages"] ?? []) as List<dynamic>;
      final messages = rawList
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();

      AppDebug.log(
        _logTag,
        "fetchMessages() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationMessages,
          _extraIntentKey: _intentMessages,
          _extraCountKey: messages.length,
        },
      );

      return messages;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchMessages() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationMessages,
          _extraIntentKey: _intentMessages,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatMessage> sendMessage({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      "sendMessage() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationSend,
        _extraIntentKey: _intentSend,
      },
    );

    try {
      final resp = await _dio.post(
        _messagesPath,
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final messageMap = (data["messageData"] ?? {}) as Map<String, dynamic>;
      final message = ChatMessage.fromJson(messageMap);

      AppDebug.log(
        _logTag,
        "sendMessage() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationSend,
          _extraIntentKey: _intentSend,
        },
      );

      return message;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "sendMessage() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationSend,
          _extraIntentKey: _intentSend,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<void> markMessagesRead({
    required String? token,
    required String conversationId,
    required List<String> messageIds,
  }) async {
    AppDebug.log(
      _logTag,
      "markMessagesRead() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationRead,
        _extraIntentKey: _intentRead,
      },
    );

    try {
      await _dio.post(
        _messageReadPath,
        data: {"conversationId": conversationId, "messageIds": messageIds},
        options: _authOptions(token),
      );

      AppDebug.log(
        _logTag,
        "markMessagesRead() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationRead,
          _extraIntentKey: _intentRead,
        },
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "markMessagesRead() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationRead,
          _extraIntentKey: _intentRead,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatAttachment> uploadAttachment({
    required String? token,
    required String conversationId,
    required List<int> bytes,
    required String filename,
  }) async {
    AppDebug.log(
      _logTag,
      "uploadAttachment() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationUpload,
        _extraIntentKey: _intentUpload,
      },
    );

    try {
      final formData = FormData.fromMap({
        "conversationId": conversationId,
        "file": MultipartFile.fromBytes(bytes, filename: filename),
      });

      final resp = await _dio.post(
        _attachmentsPath,
        data: formData,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final attachmentMap = (data["attachment"] ?? {}) as Map<String, dynamic>;
      final attachment = ChatAttachment.fromJson(attachmentMap);

      AppDebug.log(
        _logTag,
        "uploadAttachment() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationUpload,
          _extraIntentKey: _intentUpload,
        },
      );

      return attachment;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "uploadAttachment() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationUpload,
          _extraIntentKey: _intentUpload,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatCallSession> startCall({
    required String? token,
    required String conversationId,
    String mediaMode = chatCallMediaModeAudio,
  }) async {
    AppDebug.log(
      _logTag,
      "startCall() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationStartCall,
        _extraIntentKey: _intentStartCall,
      },
    );

    try {
      final resp = await _dio.post(
        _callsPath,
        data: {"conversationId": conversationId, "mediaMode": mediaMode},
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final callMap = (data["call"] ?? {}) as Map<String, dynamic>;
      final call = ChatCallSession.fromJson(callMap);

      AppDebug.log(
        _logTag,
        "startCall() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationStartCall,
          _extraIntentKey: _intentStartCall,
        },
      );

      return call;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "startCall() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationStartCall,
          _extraIntentKey: _intentStartCall,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatCallSession> fetchCall({
    required String? token,
    required String callId,
  }) async {
    AppDebug.log(
      _logTag,
      "fetchCall() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationFetchCall,
        _extraIntentKey: _intentFetchCall,
      },
    );

    try {
      final resp = await _dio.get(
        "$_callsPath/$callId",
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final callMap = (data["call"] ?? {}) as Map<String, dynamic>;
      final call = ChatCallSession.fromJson(callMap);

      AppDebug.log(
        _logTag,
        "fetchCall() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationFetchCall,
          _extraIntentKey: _intentFetchCall,
        },
      );

      return call;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchCall() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationFetchCall,
          _extraIntentKey: _intentFetchCall,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatCallSession> acceptCall({
    required String? token,
    required String callId,
  }) async {
    AppDebug.log(
      _logTag,
      "acceptCall() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationAcceptCall,
        _extraIntentKey: _intentAcceptCall,
      },
    );

    try {
      final resp = await _dio.post(
        "$_callsPath/$callId/accept",
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final callMap = (data["call"] ?? {}) as Map<String, dynamic>;
      final call = ChatCallSession.fromJson(callMap);

      AppDebug.log(
        _logTag,
        "acceptCall() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAcceptCall,
          _extraIntentKey: _intentAcceptCall,
        },
      );

      return call;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "acceptCall() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAcceptCall,
          _extraIntentKey: _intentAcceptCall,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatCallSession> declineCall({
    required String? token,
    required String callId,
    String reason = "declined",
  }) async {
    AppDebug.log(
      _logTag,
      "declineCall() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationDeclineCall,
        _extraIntentKey: _intentDeclineCall,
      },
    );

    try {
      final resp = await _dio.post(
        "$_callsPath/$callId/decline",
        data: {"reason": reason},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final callMap = (data["call"] ?? {}) as Map<String, dynamic>;
      final call = ChatCallSession.fromJson(callMap);

      AppDebug.log(
        _logTag,
        "declineCall() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDeclineCall,
          _extraIntentKey: _intentDeclineCall,
        },
      );

      return call;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "declineCall() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDeclineCall,
          _extraIntentKey: _intentDeclineCall,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ChatCallSession> endCall({
    required String? token,
    required String callId,
    String reason = "ended",
  }) async {
    AppDebug.log(
      _logTag,
      "endCall() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationEndCall,
        _extraIntentKey: _intentEndCall,
      },
    );

    try {
      final resp = await _dio.post(
        "$_callsPath/$callId/end",
        data: {"reason": reason},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final callMap = (data["call"] ?? {}) as Map<String, dynamic>;
      final call = ChatCallSession.fromJson(callMap);

      AppDebug.log(
        _logTag,
        "endCall() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationEndCall,
          _extraIntentKey: _intentEndCall,
        },
      );

      return call;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "endCall() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationEndCall,
          _extraIntentKey: _intentEndCall,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }
}
