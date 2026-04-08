/**
 * controllers/chat.controller.js
 * ------------------------------
 * WHAT:
 * - REST controllers for chat conversations, messages, and attachments.
 *
 * WHY:
 * - Keeps HTTP concerns separate from chat domain logic.
 * - Provides consistent error handling and diagnostics.
 *
 * HOW:
 * - Delegates validation + persistence to chat.service.
 * - Emits socket events via chat_socket.service after persistence.
 */

const debug = require("../utils/debug");
const ChatConversation = require("../models/ChatConversation");
const chatService = require("../services/chat.service");
const purchaseRequestService = require("../services/purchase_request.service");
const {
  emitMessageCreated,
  emitMessageRead,
} = require("../services/chat_socket.service");
const { CHAT_CONVERSATION_TYPES } = require("../utils/chat_constants");

// WHY: Keep controller log tags consistent.
const LOG_TAG = "CHAT_CONTROLLER";

// WHY: Centralize response copy to avoid inline strings.
const CHAT_COPY = {
  CONVERSATIONS_OK: "Conversations loaded successfully",
  CONVERSATION_CREATED: "Conversation created successfully",
  CONVERSATION_DETAIL_OK: "Conversation loaded successfully",
  MESSAGES_OK: "Messages loaded successfully",
  MESSAGE_SENT: "Message sent successfully",
  MESSAGE_READ: "Messages marked as read",
  ATTACHMENT_OK: "Attachment uploaded successfully",
  CONVERSATION_REQUIRED: "Conversation id is required",
  UNKNOWN_ERROR: "Unable to complete chat request",
};

function buildContext(req, operation, intent) {
  // WHY: Normalize log context for diagnostics.
  return {
    route: req.originalUrl,
    requestId: req.id,
    userRole: req.user?.role,
    operation,
    intent,
  };
}

function logError(action, error, context) {
  // WHY: Provide actionable error logs that follow debug rules.
  debug(`${LOG_TAG}: ${action} - error`, {
    error: error?.message,
    classification: error?.classification,
    error_code: error?.errorCode,
    resolution_hint: error?.resolutionHint,
    http_status: error?.httpStatus,
    route: context.route,
    requestId: context.requestId,
  });
}

function emitMessages(conversationId, messages = []) {
  messages.filter(Boolean).forEach((message) => {
    emitMessageCreated({
      conversationId:
        message.conversationId?.toString() || conversationId?.toString(),
      message,
    });
  });
}

async function listConversations(req, res) {
  const context = buildContext(req, "ListConversations", "load chat inbox");
  debug(`${LOG_TAG}: listConversations - entry`, {
    actorId: req.user?.sub,
  });

  try {
    const actor = await chatService.loadActor(req.user?.sub, context);
    const businessIdHint = req.query?.businessId
      ? req.query.businessId.toString()
      : null;

    const conversations = await chatService.listConversations({
      userId: actor._id,
      businessId: businessIdHint,
      limit: Number.parseInt(req.query?.limit, 10) || 50,
      context,
    });

    debug(`${LOG_TAG}: listConversations - success`, {
      count: conversations.length,
    });

    return res.status(200).json({
      message: CHAT_COPY.CONVERSATIONS_OK,
      conversations,
    });
  } catch (error) {
    logError("listConversations", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

async function createConversation(req, res) {
  const context = buildContext(req, "CreateConversation", "start chat");
  debug(`${LOG_TAG}: createConversation - entry`, {
    actorId: req.user?.sub,
    hasParticipants: Array.isArray(req.body?.participantUserIds),
  });

  try {
    const actor = await chatService.loadActor(req.user?.sub, context);
    const businessId = await chatService.resolveBusinessScope({
      actor,
      businessIdHint: req.body?.businessId?.toString(),
      context,
    });

    const conversation = await chatService.createConversation({
      actor,
      businessId,
      type: req.body?.type || CHAT_CONVERSATION_TYPES.DIRECT,
      title: req.body?.title,
      participantUserIds: req.body?.participantUserIds || [],
      context,
    });

    debug(`${LOG_TAG}: createConversation - success`, {
      conversationId: conversation._id,
    });

    return res.status(201).json({
      message: CHAT_COPY.CONVERSATION_CREATED,
      conversation,
    });
  } catch (error) {
    logError("createConversation", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

async function getConversationDetail(req, res) {
  const context = buildContext(
    req,
    "GetConversationDetail",
    "load conversation detail",
  );
  const conversationId = req.params?.conversationId;

  if (!conversationId) {
    return res.status(400).json({
      error: CHAT_COPY.CONVERSATION_REQUIRED,
    });
  }

  try {
    const detail = await chatService.getConversationDetail({
      userId: req.user?.sub,
      conversationId,
      context,
    });

    return res.status(200).json({
      message: CHAT_COPY.CONVERSATION_DETAIL_OK,
      conversation: detail.conversation,
      participants: detail.participants,
      purchaseRequest: detail.purchaseRequest || null,
    });
  } catch (error) {
    logError("getConversationDetail", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

async function listMessages(req, res) {
  const context = buildContext(
    req,
    "ListMessages",
    "load conversation messages",
  );
  const conversationId = req.params?.conversationId;

  if (!conversationId) {
    return res.status(400).json({
      error: CHAT_COPY.CONVERSATION_REQUIRED,
    });
  }

  try {
    const messages = await chatService.listMessages({
      userId: req.user?.sub,
      conversationId,
      limit: Number.parseInt(req.query?.limit, 10) || 30,
      cursor: req.query?.cursor,
      context,
    });

    return res.status(200).json({
      message: CHAT_COPY.MESSAGES_OK,
      messages,
    });
  } catch (error) {
    logError("listMessages", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

async function sendMessage(req, res) {
  const context = buildContext(req, "SendMessage", "send chat message");
  const conversationId = req.body?.conversationId;

  if (!conversationId) {
    return res.status(400).json({
      error: CHAT_COPY.CONVERSATION_REQUIRED,
    });
  }

  try {
    const actor = await chatService.loadActor(req.user?.sub, context);
    const conversation =
      await ChatConversation.findById(conversationId).select("businessId");

    if (!conversation) {
      return res.status(404).json({
        error: "Conversation not found",
      });
    }

    const message = await chatService.sendMessage({
      actor,
      businessId: conversation.businessId.toString(),
      conversationId,
      body: req.body?.body,
      attachmentIds: req.body?.attachmentIds,
      clientMessageId: req.body?.clientMessageId,
      context,
    });

    emitMessages(conversationId, [message]);

    let followUpMessages = [];
    try {
      followUpMessages = await purchaseRequestService.handleConversationMessageEffects({
        actor,
        conversationId,
        message,
        context,
      });
      emitMessages(conversationId, followUpMessages);
    } catch (followUpError) {
      debug(`${LOG_TAG}: sendMessage - purchase request follow-up error`, {
        conversationId,
        error: followUpError?.message || "unknown_error",
      });
    }

    return res.status(200).json({
      message: CHAT_COPY.MESSAGE_SENT,
      messageData: message,
      followUpMessages,
    });
  } catch (error) {
    logError("sendMessage", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

async function markMessagesRead(req, res) {
  const context = buildContext(
    req,
    "MarkMessagesRead",
    "mark chat messages read",
  );
  const conversationId = req.body?.conversationId;
  const messageIds = req.body?.messageIds || [];

  if (!conversationId) {
    return res.status(400).json({
      error: CHAT_COPY.CONVERSATION_REQUIRED,
    });
  }

  try {
    const result = await chatService.markMessagesRead({
      userId: req.user?.sub,
      conversationId,
      messageIds,
      context,
    });

    emitMessageRead({
      conversationId,
      messageIds,
      readBy: req.user?.sub,
    });

    return res.status(200).json({
      message: CHAT_COPY.MESSAGE_READ,
      updated: result.updated,
    });
  } catch (error) {
    logError("markMessagesRead", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

async function uploadChatAttachment(req, res) {
  const context = buildContext(
    req,
    "UploadChatAttachment",
    "upload chat attachment",
  );
  const conversationId = req.body?.conversationId;

  if (!conversationId) {
    return res.status(400).json({
      error: CHAT_COPY.CONVERSATION_REQUIRED,
    });
  }

  try {
    const actor = await chatService.loadActor(req.user?.sub, context);
    const conversation =
      await ChatConversation.findById(conversationId).select("businessId");

    if (!conversation) {
      return res.status(404).json({
        error: "Conversation not found",
      });
    }

    const attachment = await chatService.uploadChatAttachment({
      actor,
      businessId: conversation.businessId.toString(),
      conversationId,
      file: req.file,
      context,
    });

    return res.status(200).json({
      message: CHAT_COPY.ATTACHMENT_OK,
      attachment,
    });
  } catch (error) {
    logError("uploadChatAttachment", error, context);
    return res.status(error?.httpStatus || 400).json({
      error: error?.message || CHAT_COPY.UNKNOWN_ERROR,
    });
  }
}

module.exports = {
  listConversations,
  createConversation,
  getConversationDetail,
  listMessages,
  sendMessage,
  markMessagesRead,
  uploadChatAttachment,
};
