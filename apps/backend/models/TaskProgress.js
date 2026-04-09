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
  PLOT_UNIT_SCALE,
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS,
} = require("../utils/production_engine.config");

const PRODUCTION_QUANTITY_ACTIVITY_TYPES = [
  "none",
  "planting",
  "transplant",
  "harvest",
];

const taskProgressProofSchema =
  new mongoose.Schema(
    {
      url: {
        type: String,
        trim: true,
        default: "",
      },
      publicId: {
        type: String,
        trim: true,
        default: "",
      },
      filename: {
        type: String,
        trim: true,
        default: "",
      },
      mimeType: {
        type: String,
        trim: true,
        default: "",
      },
      sizeBytes: {
        type: Number,
        min: 0,
        default: 0,
      },
      uploadedAt: {
        type: Date,
        default: null,
      },
      uploadedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        default: null,
      },
    },
    { _id: false },
  );

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
    // UNIT-LIFECYCLE
    // WHY: Unit context keeps delay truth scoped to the exact plan unit affected.
    unitId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "PlanUnit",
      default: null,
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
    // WHY: Canonical integer units make partial-plot math deterministic and reversible.
    expectedPlotUnits: {
      type: Number,
      min: 0,
      required: true,
      index: true,
    },
    // WHY: Actual output must stay non-negative and humane.
    actualPlots: {
      type: Number,
      min: 0,
      max: HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay,
      required: true,
    },
    // WHY: Integer unit storage avoids float drift for 0.5/0.25 plot progress entries.
    actualPlotUnits: {
      type: Number,
      min: 0,
      max:
        HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay *
        PLOT_UNIT_SCALE,
      required: true,
      index: true,
    },
    // WHY: Farm execution also tracks planting, transplant, and harvest quantities per day.
    quantityActivityType: {
      type: String,
      enum: PRODUCTION_QUANTITY_ACTIVITY_TYPES,
      default: "none",
      index: true,
    },
    quantityAmount: {
      type: Number,
      min: 0,
      default: 0,
    },
    quantityUnit: {
      type: String,
      trim: true,
      default: "",
    },
    // WHY: Execution proof images keep each progress row auditable.
    proofs: {
      type: [taskProgressProofSchema],
      default: [],
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

// UNIT-LIFECYCLE
// WHY: Prevent duplicate daily records for the same task/staff/day/unit while allowing multi-unit logging.
taskProgressSchema.index(
  {
    taskId: 1,
    staffId: 1,
    workDate: 1,
    unitId: 1,
  },
  { unique: true },
);

const TaskProgress = mongoose.model(
  "TaskProgress",
  taskProgressSchema,
);

module.exports = TaskProgress;
module.exports.PRODUCTION_TASK_PROGRESS_DELAY_REASONS =
  PRODUCTION_TASK_PROGRESS_DELAY_REASONS;
module.exports.PLOT_UNIT_SCALE =
  PLOT_UNIT_SCALE;
module.exports.PRODUCTION_QUANTITY_ACTIVITY_TYPES =
  PRODUCTION_QUANTITY_ACTIVITY_TYPES;
