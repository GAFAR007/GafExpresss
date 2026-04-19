/**
 * models/ChatCallSession.js
 * -------------------------
 * WHAT:
 * - Stores a single voice/video call attempt for a direct chat conversation.
 *
 * WHY:
 * - Persists call lifecycle state independently from message history.
 * - Supports ringing, active, and terminal states with audit metadata.
 *
 * HOW:
 * - Links the session to one direct conversation and two participants.
 * - Keeps one active/ringing session per conversation via a partial unique index.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const {
  CHAT_CALL_MEDIA_MODES,
  CHAT_CALL_STATES,
} = require("../utils/chat_constants");

debug("Loading ChatCallSession model...");

const DEFAULT_RING_TIMEOUT_MS = 45 * 1000;

const chatCallSessionSchema = new mongoose.Schema(
  {
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ChatConversation",
      required: [true, "Conversation id is required"],
    },
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "Business id is required"],
      index: true,
    },
    mediaMode: {
      type: String,
      enum: Object.values(CHAT_CALL_MEDIA_MODES),
      default: CHAT_CALL_MEDIA_MODES.AUDIO,
      index: true,
    },
    callerUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "Caller user id is required"],
      index: true,
    },
    calleeUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "Callee user id is required"],
      index: true,
    },
    state: {
      type: String,
      enum: Object.values(CHAT_CALL_STATES),
      default: CHAT_CALL_STATES.RINGING,
      index: true,
    },
    ringTimeoutAt: {
      type: Date,
      default: () => new Date(Date.now() + DEFAULT_RING_TIMEOUT_MS),
      index: true,
    },
    answeredAt: {
      type: Date,
      default: null,
    },
    endedAt: {
      type: Date,
      default: null,
    },
    endedByUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    endReason: {
      type: String,
      trim: true,
      default: "",
      index: true,
    },
    lastSignalAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

chatCallSessionSchema.index(
  { conversationId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      state: {
        $in: [
          CHAT_CALL_STATES.RINGING,
          CHAT_CALL_STATES.ACTIVE,
        ],
      },
    },
  },
);

chatCallSessionSchema.index({
  calleeUserId: 1,
  state: 1,
  createdAt: -1,
});

module.exports = mongoose.model(
  "ChatCallSession",
  chatCallSessionSchema,
);
