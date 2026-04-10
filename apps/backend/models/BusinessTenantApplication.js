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
 * - Links to businessId, estateAssetId, and optional tenantUserId.
 * - Stores selected unit, applicant identity, agreement, and review metadata.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessTenantApplication model...');

// WHY: Reuse the same rent period values as estate unit mix.
const RENT_PERIODS = ['monthly', 'quarterly', 'yearly'];

// WHY: Keep application status explicit for review + activation workflows.
const APPLICATION_STATUSES = ['pending', 'approved', 'active', 'rejected'];

// WHY: Track rent payment separately from approval status.
const PAYMENT_STATUSES = ['unpaid', 'paid'];

// WHY: Track agreement workflow distinctly from contact verification.
const AGREEMENT_STATUSES = ['pending', 'approved', 'rejected'];

const contactSchema = new mongoose.Schema(
  {
    // WHY: Store split names for verification checks + consistent review display.
    firstName: {
      type: String,
      trim: true,
    },
    // WHY: Keep middle name optional for compatibility with legacy data.
    middleName: {
      type: String,
      trim: true,
    },
    // WHY: Require last name for identity checks and audit clarity.
    lastName: {
      type: String,
      trim: true,
    },
    // WHY: Preserve legacy full name for backward compatibility.
    name: {
      type: String,
      trim: true,
      required: true,
    },
    // WHY: Contact phone stays available for verification calls.
    phone: {
      type: String,
      trim: true,
    },
    // WHY: Email is required for verifications and future contact flows.
    email: {
      type: String,
      trim: true,
      lowercase: true,
    },
    // WHY: Keep optional supporting document URL per contact.
    documentUrl: {
      type: String,
      trim: true,
    },
    // WHY: Track Cloudinary public id for possible cleanup later.
    documentPublicId: {
      type: String,
      trim: true,
    },
    relationship: {
      type: String,
      trim: true,
    },
    // WHY: Owners must verify each contact before approval.
    isVerified: {
      type: Boolean,
      default: false,
    },
    // WHY: Keep a status for audit + rejection history (not just boolean).
    status: {
      type: String,
      enum: ['pending', 'verified', 'rejected'],
      default: 'pending',
    },
    verifiedAt: {
      type: Date,
      default: null,
    },
    verifiedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    note: {
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
    referencesMin: { type: Number, min: 0, default: 1 },
    referencesMax: { type: Number, min: 0, default: 2 },
    guarantorsMin: { type: Number, min: 0, default: 1 },
    guarantorsMax: { type: Number, min: 0, default: 2 },
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
      default: null,
      index: true,
    },
    tenantSnapshot: {
      type: tenantSnapshotSchema,
      default: () => ({}),
    },
    applicantFirstName: {
      type: String,
      trim: true,
    },
    applicantMiddleName: {
      type: String,
      trim: true,
    },
    applicantLastName: {
      type: String,
      trim: true,
    },
    applicantDob: {
      type: Date,
      default: null,
    },
    applicantNinHash: {
      type: String,
      trim: true,
      select: false,
      default: null,
    },
    applicantNinLast4: {
      type: String,
      trim: true,
    },
    identityDocumentUrl: {
      type: String,
      trim: true,
    },
    identityDocumentPublicId: {
      type: String,
      trim: true,
      select: false,
    },
    requestSource: {
      type: String,
      enum: ['tenant_verification', 'public_request', 'invite'],
      default: 'tenant_verification',
      index: true,
    },
    requestLinkId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessTenantRequestLink',
      default: null,
      index: true,
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
      // WHY: Rent is stored in kobo; enforce integer to keep math safe.
      validate: {
        validator(value) {
          return Number.isInteger(value);
        },
        message: 'Rent amount must be an integer (kobo)',
      },
    },
    rentPeriod: {
      type: String,
      enum: RENT_PERIODS,
      required: true,
    },
    moveInDate: {
      type: Date,
      default: null,
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
    agreementText: {
      type: String,
      trim: true,
    },
    agreementAcceptedAt: {
      type: Date,
      default: null,
    },
    tenantRulesSnapshot: {
      type: tenantRulesSnapshotSchema,
      default: () => ({}),
    },
  agreementStatus: {
    type: String,
    enum: AGREEMENT_STATUSES,
    default: 'pending',
  },
  status: {
    type: String,
    enum: APPLICATION_STATUSES,
      default: 'pending',
      index: true,
    },
    paymentStatus: {
      type: String,
      enum: PAYMENT_STATUSES,
      default: 'unpaid',
      index: true,
    },
    paidThroughDate: {
      type: Date,
      default: null,
    },
    nextDueDate: {
      type: Date,
      default: null,
    },
    lastRentPaymentAt: {
      type: Date,
      default: null,
    },
    paidAt: {
      type: Date,
      default: null,
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
