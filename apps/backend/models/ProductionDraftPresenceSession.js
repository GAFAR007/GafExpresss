/**
 * apps/backend/models/ProductionDraftPresenceSession.js
 * ------------------------------------------------------
 * WHAT:
 * - Stores join/leave sessions for draft room presence.
 *
 * WHY:
 * - Tracks when a user entered a draft room and how long they stayed.
 * - Gives production planning screens durable usage history for reporting.
 *
 * HOW:
 * - Each session is scoped to a business, plan, and user.
 * - Open sessions stay active until the user leaves or disconnects.
 * - Closed sessions preserve duration history for daily/monthly/yearly rollups.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading ProductionDraftPresenceSession model...");

const productionDraftPresenceSessionSchema = new mongoose.Schema(
  {
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Business",
      required: true,
      index: true,
    },
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ProductionPlan",
      required: true,
      index: true,
    },
    roomId: {
      type: String,
      trim: true,
      required: true,
      index: true,
    },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    displayName: {
      type: String,
      trim: true,
      default: "",
    },
    email: {
      type: String,
      trim: true,
      default: "",
    },
    accountRole: {
      type: String,
      trim: true,
      default: "",
      index: true,
    },
    staffRole: {
      type: String,
      trim: true,
      default: "",
      index: true,
    },
    enteredAt: {
      type: Date,
      required: true,
      index: true,
    },
    lastSeenAt: {
      type: Date,
      default: null,
      index: true,
    },
    leftAt: {
      type: Date,
      default: null,
      index: true,
    },
    durationSeconds: {
      type: Number,
      min: 0,
      default: 0,
    },
    activeSocketCount: {
      type: Number,
      min: 0,
      default: 0,
    },
    lastEventAt: {
      type: Date,
      default: null,
      index: true,
    },
  },
  {
    timestamps: true,
  },
);

// WHY: Only one open session should exist per user in a given room at a time.
productionDraftPresenceSessionSchema.index(
  {
    businessId: 1,
    planId: 1,
    userId: 1,
    leftAt: 1,
  },
  {
    unique: true,
    partialFilterExpression: {
      leftAt: null,
    },
  },
);

const ProductionDraftPresenceSession = mongoose.model(
  "ProductionDraftPresenceSession",
  productionDraftPresenceSessionSchema,
);

module.exports = ProductionDraftPresenceSession;
