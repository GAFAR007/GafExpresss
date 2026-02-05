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
