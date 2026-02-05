/**
 * apps/backend/models/StaffCompensation.js
 * ------------------------------------------------
 * WHAT:
 * - Stores salary/compensation details for staff profiles.
 *
 * WHY:
 * - Keeps sensitive payroll data separate from general staff metadata.
 * - Supports payroll reporting with clear owner/manager access control.
 *
 * HOW:
 * - Links each record to a BusinessStaffProfile + Business.
 * - Tracks cadence, amount, and last update metadata.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading StaffCompensation model...");

// WHY: Limit cadence to known payroll cycles.
const COMPENSATION_CADENCE = [
  "weekly",
  "monthly",
];

const staffCompensationSchema = new mongoose.Schema(
  {
    // WHY: Link compensation to a staff profile.
    staffProfileId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "BusinessStaffProfile",
      required: true,
    },
    // WHY: Keep compensation scoped to a business.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Business",
      required: true,
      index: true,
    },
    // WHY: Store salary in kobo to match payment precision.
    salaryAmountKobo: {
      type: Number,
      min: 0,
      required: true,
    },
    // WHY: Cadence defines how often salary is paid.
    salaryCadence: {
      type: String,
      enum: COMPENSATION_CADENCE,
      required: true,
      index: true,
    },
    // WHY: Optional payday helps scheduling for payroll.
    payDay: {
      type: String,
      trim: true,
      default: "",
    },
    // WHY: Track last editor for audit trails.
    lastUpdatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    lastUpdatedAt: {
      type: Date,
      default: null,
    },
    // WHY: Notes allow internal context without exposing to staff.
    notes: {
      type: String,
      trim: true,
      default: "",
    },
  },
  {
    timestamps: true,
  },
);

// WHY: Enforce one compensation record per staff profile.
staffCompensationSchema.index(
  { staffProfileId: 1 },
  { unique: true },
);

const StaffCompensation = mongoose.model(
  "StaffCompensation",
  staffCompensationSchema,
);

module.exports = StaffCompensation;
module.exports.COMPENSATION_CADENCE =
  COMPENSATION_CADENCE;
