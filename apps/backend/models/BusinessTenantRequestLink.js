/**
 * models/BusinessTenantRequestLink.js
 * -----------------------------------
 * WHAT:
 * - Stores public tenant-request link tokens for business owners and staff.
 *
 * WHY:
 * - Lets approved business actors create a shareable tenant intake link.
 * - Keeps link lifecycle auditable without exposing raw tokens in the DB.
 *
 * HOW:
 * - Persists a hashed token, expiry, and estate scope.
 * - Marks the link consumed once a public tenant request is submitted.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessTenantRequestLink model...');

const REQUEST_LINK_STATUSES = [
  'pending',
  'consumed',
  'expired',
  'cancelled',
];

const businessTenantRequestLinkSchema = new mongoose.Schema(
  {
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    inviterId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    estateAssetId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessAsset',
      required: true,
      index: true,
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
      enum: REQUEST_LINK_STATUSES,
      default: 'pending',
      index: true,
    },
    submittedApplicationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessTenantApplication',
      default: null,
      index: true,
    },
  },
  { timestamps: true },
);

const BusinessTenantRequestLink = mongoose.model(
  'BusinessTenantRequestLink',
  businessTenantRequestLinkSchema,
);

module.exports = BusinessTenantRequestLink;
module.exports.REQUEST_LINK_STATUSES = REQUEST_LINK_STATUSES;
