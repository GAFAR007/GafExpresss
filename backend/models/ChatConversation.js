/**
 * models/ChatConversation.js
 * --------------------------
 * WHAT:
 * - Defines a conversation thread for real-time chat.
 *
 * WHY:
 * - Groups messages + participants under a single business-scoped container.
 * - Supports direct and group conversations with consistent metadata.
 *
 * HOW:
 * - Stores businessId, type, and optional title.
 * - Tracks lastMessageAt + preview for fast inbox rendering.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');
const {
  CHAT_CONVERSATION_TYPES,
  CHAT_LIMITS,
} = require('../utils/chat_constants');

debug('Loading ChatConversation model...');

const chatConversationSchema = new mongoose.Schema(
  {
    // WHY: Every conversation is scoped to a single business.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Business id is required'],
      index: true,
    },
    // WHY: Direct vs group drives UI + membership rules.
    type: {
      type: String,
      enum: Object.values(CHAT_CONVERSATION_TYPES),
      default: CHAT_CONVERSATION_TYPES.DIRECT,
      index: true,
    },
    // WHY: Title is required for group chats and optional for direct chats.
    title: {
      type: String,
      trim: true,
      maxlength: CHAT_LIMITS.MAX_TITLE_LENGTH,
      default: '',
    },
    // WHY: Keep an audit trail of who opened the conversation.
    createdByUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    // WHY: Used for inbox sorting without scanning messages.
    lastMessageAt: {
      type: Date,
      default: null,
      index: true,
    },
    // WHY: Store a tiny preview for fast list rendering.
    lastMessagePreview: {
      type: String,
      trim: true,
      maxlength: CHAT_LIMITS.MAX_TEXT_LENGTH,
      default: '',
    },
  },
  {
    timestamps: true,
  }
);

// WHY: Support fast inbox listings by business and recency.
chatConversationSchema.index({ businessId: 1, lastMessageAt: -1 });

module.exports = mongoose.model(
  'ChatConversation',
  chatConversationSchema,
);
