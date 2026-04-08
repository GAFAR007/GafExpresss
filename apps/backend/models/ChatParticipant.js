/**
 * models/ChatParticipant.js
 * -------------------------
 * WHAT:
 * - Tracks a user's membership inside a chat conversation.
 *
 * WHY:
 * - Controls access checks + read positions per participant.
 * - Enables staff/group membership within the same business.
 *
 * HOW:
 * - Stores conversationId + userId with a unique index.
 * - Tracks joinedAt and lastReadAt for read receipts.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading ChatParticipant model...');

const chatParticipantSchema = new mongoose.Schema(
  {
    // WHY: Links the participant to the conversation thread.
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ChatConversation',
      required: [true, 'Conversation id is required'],
      index: true,
    },
    // WHY: Links the participant to the user profile.
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User id is required'],
      index: true,
    },
    // WHY: Persist role-at-join for audit + filtering (optional).
    roleAtJoin: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Needed for initial ordering and audit checks.
    joinedAt: {
      type: Date,
      default: Date.now,
    },
    // WHY: Used to compute unread counts per conversation.
    lastReadAt: {
      type: Date,
      default: null,
    },
    // WHY: Allows soft hides without destroying membership history.
    isHidden: {
      type: Boolean,
      default: false,
      index: true,
    },
  },
  {
    timestamps: true,
  }
);

// WHY: Prevent duplicate membership rows per conversation/user.
chatParticipantSchema.index(
  { conversationId: 1, userId: 1 },
  { unique: true }
);

module.exports = mongoose.model(
  'ChatParticipant',
  chatParticipantSchema,
);
