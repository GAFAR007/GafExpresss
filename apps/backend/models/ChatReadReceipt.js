/**
 * models/ChatReadReceipt.js
 * -------------------------
 * WHAT:
 * - Stores per-user read receipts for chat messages.
 *
 * WHY:
 * - Enables accurate unread counts and “seen” indicators.
 * - Keeps receipts decoupled from messages for scalability.
 *
 * HOW:
 * - Links user + message + conversation with a unique index.
 * - Stores readAt for chronological reporting.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading ChatReadReceipt model...');

const chatReadReceiptSchema = new mongoose.Schema(
  {
    // WHY: Scopes receipts to a conversation for faster queries.
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ChatConversation',
      required: [true, 'Conversation id is required'],
      index: true,
    },
    // WHY: Links to the specific message read.
    messageId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ChatMessage',
      required: [true, 'Message id is required'],
      index: true,
    },
    // WHY: Indicates which user read the message.
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User id is required'],
      index: true,
    },
    // WHY: Timestamp required to compute read states.
    readAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    timestamps: true,
  }
);

// WHY: Ensure one receipt per user per message.
chatReadReceiptSchema.index(
  { messageId: 1, userId: 1 },
  { unique: true }
);

module.exports = mongoose.model(
  'ChatReadReceipt',
  chatReadReceiptSchema,
);
