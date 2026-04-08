/**
 * apps/backend/models/BusinessStaffProfile.js
 * ------------------------------------------------
 * WHAT:
 * - Stores staff profiles linked to business users.
 *
 * WHY:
 * - Separates staff metadata (role, estate scope, status) from core user auth.
 * - Keeps staff-specific data auditable and scoped to a business.
 *
 * HOW:
 * - Each profile references a User and Business.
 * - Enforces staffRole enums so permissions stay consistent.
 * - Supports optional estate scoping for estate-based staff.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');
const {
  STAFF_ROLES,
} = require('../utils/production_engine.config');

debug('Loading BusinessStaffProfile model...');

// WHY: Track staff lifecycle states without deleting profiles.
const STAFF_STATUSES = [
  'active',
  'suspended',
  'terminated',
];

const businessStaffProfileSchema = new mongoose.Schema(
  {
    // WHY: Link profile to the user account.
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    // WHY: Enforce business scoping for staff access.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true,
    },
    // WHY: Staff role drives permissions in business flows.
    staffRole: {
      type: String,
      enum: STAFF_ROLES,
      required: true,
      trim: true,
      index: true,
    },
    // WHY: Allow estate-scoped staff to operate within a single estate.
    estateAssetId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessAsset',
      default: null,
      index: true,
    },
    // WHY: Keep staff statuses without deleting historical records.
    status: {
      type: String,
      enum: STAFF_STATUSES,
      default: 'active',
      index: true,
    },
    // WHY: Optional start/end dates help HR and scheduling.
    startDate: {
      type: Date,
      default: null,
    },
    endDate: {
      type: Date,
      default: null,
    },
    // WHY: Notes support internal context without affecting permissions.
    notes: {
      type: String,
      trim: true,
      default: '',
    },
  },
  {
    timestamps: true,
  },
);

// WHY: Prevent duplicate profiles for the same user within a business.
businessStaffProfileSchema.index(
  { userId: 1, businessId: 1 },
  { unique: true },
);

const BusinessStaffProfile = mongoose.model(
  'BusinessStaffProfile',
  businessStaffProfileSchema,
);

module.exports = BusinessStaffProfile;
module.exports.STAFF_ROLES = STAFF_ROLES;
module.exports.STAFF_STATUSES = STAFF_STATUSES;
