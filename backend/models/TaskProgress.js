/**
 * apps/backend/models/TaskProgress.js
 * ------------------------------------------------
 * WHAT:
 * - Stores daily production execution records per task/staff/day.
 *
 * WHY:
 * - Replaces placeholder timeline values with real operational truth.
 * - Enables manager visibility on expected vs actual field output.
 *
 * HOW:
 * - Links each row to task, plan, and assigned staff profile.
 * - Enforces one row per (taskId + staffId + workDate).
 * - Guards humane workload limits via schema validation.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const {
  HUMANE_WORKLOAD_LIMITS,
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS,
} = require("../utils/production_engine.config");

debug("Loading TaskProgress model...");

const taskProgressSchema = new mongoose.Schema(
  {
    // WHY: Task link anchors execution to planned work.
    taskId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ProductionTask",
      required: true,
      index: true,
    },
    // WHY: Plan link enables fast timeline queries per plan.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ProductionPlan",
      required: true,
      index: true,
    },
    // WHY: Staff link is required for per-farmer accountability.
    staffId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "BusinessStaffProfile",
      required: true,
      index: true,
    },
    // WHY: Every record is a day-level fact for execution tracking.
    workDate: {
      type: Date,
      required: true,
      index: true,
    },
    // WHY: Expected plots are copied at log-time to preserve audit history.
    expectedPlots: {
      type: Number,
      min: 0,
      required: true,
    },
    // WHY: Actual output must stay non-negative and humane.
    actualPlots: {
      type: Number,
      min: 0,
      max: HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay,
      required: true,
    },
    // WHY: Structured delay reasons avoid vague "task failed" records.
    delayReason: {
      type: String,
      enum: PRODUCTION_TASK_PROGRESS_DELAY_REASONS,
      default: "none",
      index: true,
    },
    // WHY: Notes store human context for manager review.
    notes: {
      type: String,
      trim: true,
      default: "",
    },
    // WHY: Created-by tracks who logged the daily fact.
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    // WHY: Approval metadata supports supervisor review without blocking logging.
    approvedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    approvedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

// WHY: Prevent duplicate daily records for the same task/staff/day.
taskProgressSchema.index(
  { taskId: 1, staffId: 1, workDate: 1 },
  { unique: true },
);

const TaskProgress = mongoose.model(
  "TaskProgress",
  taskProgressSchema,
);

module.exports = TaskProgress;
module.exports.PRODUCTION_TASK_PROGRESS_DELAY_REASONS =
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS;
