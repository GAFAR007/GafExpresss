/**
 * models/ChatMessage.js
 * ---------------------
 * WHAT:
 * - Stores individual messages within a conversation.
 *
 * WHY:
 * - Enables real-time chat history, audit trails, and receipts.
 * - Supports soft-hide while preserving records for disputes.
 *
 * HOW:
 * - Links to conversation + sender + attachments.
 * - Tracks hidden flags for soft-delete behavior.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const { CHAT_MESSAGE_TYPES, CHAT_LIMITS } = require("../utils/chat_constants");

debug("Loading ChatMessage model...");

const chatMessageSchema = new mongoose.Schema(
  {
    // WHY: Scopes messages to the conversation thread.
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ChatConversation",
      required: [true, "Conversation id is required"],
      index: true,
    },
    // WHY: Keep business scope for fast permission checks.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "Business id is required"],
      index: true,
    },
    // WHY: Track who sent the message for attribution.
    senderUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "Sender id is required"],
      index: true,
    },
    // WHY: Message type drives UI rendering.
    type: {
      type: String,
      enum: Object.values(CHAT_MESSAGE_TYPES),
      default: CHAT_MESSAGE_TYPES.TEXT,
    },
    // WHY: Text content for chat messages.
    body: {
      type: String,
      trim: true,
      maxlength: CHAT_LIMITS.MAX_TEXT_LENGTH,
      default: "",
    },
    // WHY: Attachment ids allow large files without bloating messages.
    attachmentIds: {
      type: [
        {
          type: mongoose.Schema.Types.ObjectId,
          ref: "ChatAttachment",
        },
      ],
      default: [],
    },
    // WHY: Client id helps dedupe optimistic UI sends.
    clientMessageId: {
      type: String,
      trim: true,
      default: "",
      index: true,
    },
    // WHY: Structured request/chat events render richer system affordances.
    eventType: {
      type: String,
      trim: true,
      default: "",
      index: true,
    },
    eventData: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    // WHY: Soft delete without losing audit history.
    isHidden: {
      type: Boolean,
      default: false,
      index: true,
    },
    // WHY: Per-user hide for “delete for me” scenarios.
    hiddenForUserIds: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: "User",
      default: [],
    },
  },
  {
    timestamps: true,
  },
);

// WHY: Speed up timeline listing by conversation.
chatMessageSchema.index({ conversationId: 1, createdAt: -1 });
// WHY: Speed up user-specific history searches.
chatMessageSchema.index({ senderUserId: 1, createdAt: -1 });

module.exports = mongoose.model("ChatMessage", chatMessageSchema);
