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

const STAFF_ATTENDANCE_SESSION_STATUSES = [
  'open',
  'pending_proof',
  'completed',
];

const STAFF_ATTENDANCE_PROOF_STATUSES = [
  'not_required',
  'missing',
  'complete',
];

const staffAttendanceProofSchema = new mongoose.Schema(
  {
    unitIndex: {
      type: Number,
      min: 1,
      default: 1,
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

const staffAttendanceClockOutAuditSchema = new mongoose.Schema(
  {
    workDate: {
      type: Date,
      default: null,
    },
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionPlan',
      default: null,
    },
    taskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionTask',
      default: null,
    },
    taskTitle: {
      type: String,
      trim: true,
      default: '',
    },
    staffProfileId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessStaffProfile',
      default: null,
    },
    staffName: {
      type: String,
      trim: true,
      default: '',
    },
    unitId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'PlanUnit',
      default: null,
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
      default: 0,
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
    // WHY: Production attendance can be scoped to one plan when clocking from the workspace.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionPlan',
      default: null,
      index: true,
    },
    // WHY: Production workspace sessions must be scoped to one task/day.
    taskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionTask',
      default: null,
      index: true,
    },
    // WHY: Work date stays stable even when manual times are adjusted later.
    workDate: {
      type: Date,
      default: null,
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
    // WHY: Canonical proof storage keeps attendance truth independent of task progress rows.
    proofs: {
      type: [staffAttendanceProofSchema],
      default: [],
    },
    // WHY: Recovery and UI enforcement need a persisted proof requirement.
    requiredProofs: {
      type: Number,
      min: 0,
      default: 0,
      index: true,
    },
    // WHY: A small proof status enum keeps pending-proof recovery explicit.
    proofStatus: {
      type: String,
      enum: STAFF_ATTENDANCE_PROOF_STATUSES,
      default: 'not_required',
      index: true,
    },
    // WHY: Clock-out audit captures the production context that drove the proof requirement.
    clockOutAudit: {
      type: staffAttendanceClockOutAuditSchema,
      default: null,
    },
    // WHY: Session state distinguishes open shifts from closed rows that still need proof.
    sessionStatus: {
      type: String,
      enum: STAFF_ATTENDANCE_SESSION_STATUSES,
      default: 'open',
      index: true,
    },
  },
  {
    timestamps: true,
  },
);

staffAttendanceSchema.index({
  staffProfileId: 1,
  taskId: 1,
  workDate: 1,
  clockOutAt: 1,
});

const StaffAttendance = mongoose.model(
  'StaffAttendance',
  staffAttendanceSchema,
);

module.exports = StaffAttendance;
module.exports.STAFF_ATTENDANCE_SESSION_STATUSES =
  STAFF_ATTENDANCE_SESSION_STATUSES;
module.exports.STAFF_ATTENDANCE_PROOF_STATUSES =
  STAFF_ATTENDANCE_PROOF_STATUSES;
