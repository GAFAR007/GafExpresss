/**
 * apps/backend/models/StaffAttendance.js
 * ------------------------------------------------
 * WHAT:
 * - Stores clock-in / clock-out records for staff.
 *
 * WHY:
 * - Tracks attendance for payroll, accountability, and performance KPIs.
 * - Keeps time logs scoped to a staff profile.
 *
 * HOW:
 * - Each record references a BusinessStaffProfile.
 * - Records clock-in/out timestamps and optional notes/location.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading StaffAttendance model...');

const attendanceProofSchema = new mongoose.Schema(
  {
    unitIndex: {
      type: Number,
      min: 1,
      required: true,
    },
    url: {
      type: String,
      trim: true,
      default: '',
    },
    publicId: {
      type: String,
      trim: true,
      default: '',
    },
    filename: {
      type: String,
      trim: true,
      default: '',
    },
    mimeType: {
      type: String,
      trim: true,
      default: '',
    },
    type: {
      type: String,
      trim: true,
      default: '',
    },
    sizeBytes: {
      type: Number,
      min: 0,
      default: null,
    },
    uploadedAt: {
      type: Date,
      default: null,
    },
    uploadedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
  },
  { _id: false },
);

const clockOutAuditSchema = new mongoose.Schema(
  {
    workDate: {
      type: Date,
      default: null,
    },
    planId: {
      type: String,
      trim: true,
      default: '',
    },
    taskId: {
      type: String,
      trim: true,
      default: '',
    },
    taskTitle: {
      type: String,
      trim: true,
      default: '',
    },
    staffProfileId: {
      type: String,
      trim: true,
      default: '',
    },
    staffName: {
      type: String,
      trim: true,
      default: '',
    },
    unitId: {
      type: String,
      trim: true,
      default: '',
    },
    unitLabel: {
      type: String,
      trim: true,
      default: '',
    },
    progressUnitLabel: {
      type: String,
      trim: true,
      default: '',
    },
    unitsCompleted: {
      type: Number,
      min: 0,
      default: null,
    },
    unitsRemaining: {
      type: Number,
      min: 0,
      default: null,
    },
    requiredProofs: {
      type: Number,
      min: 0,
      default: null,
    },
    unitType: {
      type: String,
      trim: true,
      default: '',
    },
    quantityActivityType: {
      type: String,
      trim: true,
      default: '',
    },
    quantityAmount: {
      type: Number,
      min: 0,
      default: null,
    },
    quantityUnit: {
      type: String,
      trim: true,
      default: '',
    },
    notes: {
      type: String,
      trim: true,
      default: '',
    },
    capturedAt: {
      type: Date,
      default: null,
    },
  },
  { _id: false },
);

const staffAttendanceSchema = new mongoose.Schema(
  {
    // WHY: Connect attendance to a staff profile.
    staffProfileId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessStaffProfile',
      required: true,
      index: true,
    },
    // WHY: Clock-in time anchors the attendance session.
    clockInAt: {
      type: Date,
      required: true,
      index: true,
    },
    // WHY: Clock-out is optional until staff completes their session.
    clockOutAt: {
      type: Date,
      default: null,
    },
    // WHY: Duration is derived for reporting and payroll.
    durationMinutes: {
      type: Number,
      min: 0,
      default: null,
    },
    // WHY: Track who initiated the clock-in action.
    clockInBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    // WHY: Track who closed the clock-out action.
    clockOutBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    // WHY: Optional location supports field operations audits.
    location: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Notes allow managers to capture exceptions or explanations.
    notes: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Proof keeps clock-out actions auditable and verifiable.
    proofUrl: {
      type: String,
      trim: true,
      default: '',
    },
    proofPublicId: {
      type: String,
      trim: true,
      default: '',
    },
    proofFilename: {
      type: String,
      trim: true,
      default: '',
    },
    proofMimeType: {
      type: String,
      trim: true,
      default: '',
    },
    proofSizeBytes: {
      type: Number,
      min: 0,
      default: null,
    },
    proofUploadedAt: {
      type: Date,
      default: null,
    },
    proofUploadedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    proofs: {
      type: [attendanceProofSchema],
      default: [],
    },
    clockOutAudit: {
      type: clockOutAuditSchema,
      default: null,
    },
    sessionStatus: {
      type: String,
      enum: ['active', 'completed'],
      default: 'active',
      index: true,
    },
    numberOfUnitsCompleted: {
      type: Number,
      min: 0,
      default: null,
    },
    requiredProofs: {
      type: Number,
      min: 0,
      default: null,
    },
    unitType: {
      type: String,
      trim: true,
      default: '',
    },
  },
  {
    timestamps: true,
  },
);

const StaffAttendance = mongoose.model(
  'StaffAttendance',
  staffAttendanceSchema,
);

module.exports = StaffAttendance;
