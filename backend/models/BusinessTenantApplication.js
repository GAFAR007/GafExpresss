/**
 * models/BusinessTenantApplication.js
 * ----------------------------------
 * WHAT:
 * - Stores tenant verification submissions for estate assets.
 *
 * WHY:
 * - Keeps tenant onboarding auditable and tied to a specific estate asset.
 * - Preserves submitted details even if user/profile changes later.
 *
 * HOW:
 * - Links to businessId, estateAssetId, and tenantUserId.
 * - Stores selected unit, rent period, references, guarantors, and agreement.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessTenantApplication model...');

// WHY: Reuse the same rent period values as estate unit mix.
const RENT_PERIODS = ['monthly', 'quarterly', 'yearly'];

// WHY: Keep application status explicit for review workflows.
const APPLICATION_STATUSES = ['pending', 'approved', 'rejected'];

const contactSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      trim: true,
      required: true,
    },
    phone: {
      type: String,
      trim: true,
    },
  },
  { _id: false }
);

const tenantSnapshotSchema = new mongoose.Schema(
  {
    name: { type: String, trim: true },
    email: { type: String, trim: true, lowercase: true },
    phone: { type: String, trim: true },
    ninLast4: { type: String, trim: true },
  },
  { _id: false }
);

const tenantRulesSnapshotSchema = new mongoose.Schema(
  {
    referencesMin: { type: Number, min: 1, default: 1 },
    referencesMax: { type: Number, min: 1, default: 2 },
    guarantorsMin: { type: Number, min: 1, default: 1 },
    guarantorsMax: { type: Number, min: 1, default: 2 },
    requiresAgreementSigned: { type: Boolean, default: true },
  },
  { _id: false }
);

const tenantApplicationSchema = new mongoose.Schema(
  {
    businessId: {
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
    tenantUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    tenantSnapshot: {
      type: tenantSnapshotSchema,
      default: () => ({}),
    },
    unitType: {
      type: String,
      trim: true,
      required: true,
    },
    unitCount: {
      type: Number,
      min: 1,
      default: 1,
    },
    rentAmount: {
      type: Number,
      min: 0,
      required: true,
    },
    rentPeriod: {
      type: String,
      enum: RENT_PERIODS,
      required: true,
    },
    moveInDate: {
      type: Date,
      required: true,
    },
    references: {
      type: [contactSchema],
      default: [],
    },
    guarantors: {
      type: [contactSchema],
      default: [],
    },
    agreementSigned: {
      type: Boolean,
      default: false,
    },
    tenantRulesSnapshot: {
      type: tenantRulesSnapshotSchema,
      default: () => ({}),
    },
    status: {
      type: String,
      enum: APPLICATION_STATUSES,
      default: 'pending',
      index: true,
    },
    reviewedAt: {
      type: Date,
      default: null,
    },
    reviewedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    reviewNotes: {
      type: String,
      trim: true,
    },
  },
  { timestamps: true }
);

// WHY: Speed up tenant + estate lookups for verification flows.
tenantApplicationSchema.index({
  businessId: 1,
  estateAssetId: 1,
  tenantUserId: 1,
  status: 1,
});

const BusinessTenantApplication = mongoose.model(
  'BusinessTenantApplication',
  tenantApplicationSchema
);

module.exports = BusinessTenantApplication;
