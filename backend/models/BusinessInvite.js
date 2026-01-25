/**
 * apps/backend/models/BusinessInvite.js
 * ------------------------------------------------
 * WHAT:
 * - Stores business invitation tokens for staff/tenant onboarding.
 *
 * WHY:
 * - Allows secure, auditable role assignment via email invite links.
 * - Keeps invite history for support + compliance.
 *
 * HOW:
 * - Persists hashed tokens, expiry timestamps, and acceptance metadata.
 * - Links each invite to a business + inviter + target email.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessInvite model...');

const INVITE_STATUSES = [
  'pending',
  'accepted',
  'expired',
  'cancelled',
];

const businessInviteSchema = new mongoose.Schema(
  {
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true,
    },
    inviterId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    inviteeEmail: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    role: {
      type: String,
      enum: ['staff', 'tenant'],
      required: true,
    },
    estateAssetId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessAsset',
      default: null,
    },
    tokenHash: {
      type: String,
      required: true,
      index: true,
    },
    tokenExpiresAt: {
      type: Date,
      required: true,
    },
    status: {
      type: String,
      enum: INVITE_STATUSES,
      default: 'pending',
      index: true,
    },
    acceptedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    acceptedAt: {
      type: Date,
      default: null,
    },
    cancelledAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

const BusinessInvite = mongoose.model(
  'BusinessInvite',
  businessInviteSchema,
);

module.exports = BusinessInvite;
module.exports.INVITE_STATUSES = INVITE_STATUSES;
