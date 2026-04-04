/**
 * apps/backend/models/ProductionUnitTaskSchedule.js
 * -------------------------------------------------
 * WHAT:
 * - Stores per-unit task timing state for lifecycle-aware schedule propagation.
 *
 * WHY:
 * - Stage 5 requires shifting downstream work for one delayed unit without moving other units.
 * - Monitoring tasks need relative offsets to finite lifecycle events instead of fixed dates only.
 *
 * HOW:
 * - Persists one row per (planId, taskId, unitId) with baseline and current windows.
 * - Supports `absolute` and `relative` timing modes with reference phase events.
 * - Adds plan/unit/date indexes for fast divergence and conflict queries.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug(
  "Loading ProductionUnitTaskSchedule model...",
);

const PRODUCTION_TASK_TIMING_MODES = [
  "absolute",
  "relative",
];
const PRODUCTION_TASK_TIMING_REFERENCE_EVENTS =
  [
    "phase_start",
    "phase_completion",
  ];

const productionUnitTaskScheduleSchema =
  new mongoose.Schema(
    {
      // WHY: Plan scoping keeps schedule state multi-tenant safe.
      planId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPlan",
        required: true,
        index: true,
      },
      // WHY: Each unit schedule row maps to one canonical task.
      taskId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionTask",
        required: true,
        index: true,
      },
      // WHY: Phase context supports downstream ordering and lifecycle filtering.
      phaseId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPhase",
        required: true,
        index: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Unit-level delays must move only that unit's task timeline.
      unitId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "PlanUnit",
        required: true,
        index: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Finite work uses absolute timestamps; monitoring may use relative offsets.
      timingMode: {
        type: String,
        enum: PRODUCTION_TASK_TIMING_MODES,
        required: true,
        default: "absolute",
        index: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Relative timing references a finite phase lifecycle event.
      referencePhaseId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPhase",
        default: null,
        index: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Monitoring offsets can anchor to phase start or completion.
      referenceEvent: {
        type: String,
        enum:
          PRODUCTION_TASK_TIMING_REFERENCE_EVENTS,
        default: "phase_start",
      },
      // UNIT-LIFECYCLE
      // WHY: Baseline dates stay immutable for divergence analytics.
      baselineStartDate: {
        type: Date,
        required: true,
      },
      baselineDueDate: {
        type: Date,
        required: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Current dates are mutable and reflect unit-specific propagation.
      currentStartDate: {
        type: Date,
        required: true,
      },
      currentDueDate: {
        type: Date,
        required: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Relative tasks store offsets so dates can be recalculated from reference events.
      startOffsetDays: {
        type: Number,
        default: 0,
      },
      dueOffsetDays: {
        type: Number,
        default: 0,
      },
      // WHY: Shift metadata supports diagnostics and manager traceability.
      lastShiftDays: {
        type: Number,
        default: 0,
      },
      lastShiftReason: {
        type: String,
        trim: true,
        default: "",
      },
      lastShiftedByProgressId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "TaskProgress",
        default: null,
      },
    },
    {
      timestamps: true,
    },
  );

// UNIT-LIFECYCLE
// WHY: Each task/unit pair should have exactly one mutable timing row.
productionUnitTaskScheduleSchema.index(
  {
    planId: 1,
    taskId: 1,
    unitId: 1,
  },
  { unique: true },
);

// UNIT-LIFECYCLE
// WHY: Unit divergence and downstream scans require fast date filtering by plan/unit.
productionUnitTaskScheduleSchema.index({
  planId: 1,
  unitId: 1,
  currentStartDate: 1,
});

const ProductionUnitTaskSchedule =
  mongoose.model(
    "ProductionUnitTaskSchedule",
    productionUnitTaskScheduleSchema,
  );

module.exports =
  ProductionUnitTaskSchedule;
module.exports.PRODUCTION_TASK_TIMING_MODES =
  PRODUCTION_TASK_TIMING_MODES;
module.exports.PRODUCTION_TASK_TIMING_REFERENCE_EVENTS =
  PRODUCTION_TASK_TIMING_REFERENCE_EVENTS;
