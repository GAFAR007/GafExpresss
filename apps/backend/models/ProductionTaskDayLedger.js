/**
 * apps/backend/models/ProductionTaskDayLedger.js
 * ------------------------------------------------
 * WHAT:
 * - Stores the shared daily production ledger for one task on one work date.
 *
 * WHY:
 * - Production completion is shared across staff assigned to the same task/day.
 * - Keeps shared unit totals separate from personal session and proof logs.
 *
 * HOW:
 * - One ledger row per (taskId + workDate).
 * - Persists primary shared unit totals and secondary shared activity totals.
 * - Supports deterministic refresh after each valid contribution save.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading ProductionTaskDayLedger model...");

const SHARED_ACTIVITY_NONE = "none";
const SHARED_ACTIVITY_PLANTED = "planted";
const SHARED_ACTIVITY_TRANSPLANTED =
  "transplanted";
const SHARED_ACTIVITY_HARVESTED =
  "harvested";
const SHARED_TRACKED_ACTIVITY_TYPES = [
  SHARED_ACTIVITY_PLANTED,
  SHARED_ACTIVITY_TRANSPLANTED,
  SHARED_ACTIVITY_HARVESTED,
];

const PRODUCTION_TASK_DAY_LEDGER_STATUSES = [
  "not_started",
  "in_progress",
  "completed",
];

const sharedActivityTargetsSchema =
  new mongoose.Schema(
    {
      planted: {
        type: Number,
        min: 0,
        default: null,
      },
      transplanted: {
        type: Number,
        min: 0,
        default: null,
      },
      harvested: {
        type: Number,
        min: 0,
        default: null,
      },
    },
    { _id: false },
  );

const sharedActivityTotalsSchema =
  new mongoose.Schema(
    {
      planted: {
        type: Number,
        min: 0,
        default: 0,
      },
      transplanted: {
        type: Number,
        min: 0,
        default: 0,
      },
      harvested: {
        type: Number,
        min: 0,
        default: 0,
      },
    },
    { _id: false },
  );

const sharedActivityUnitsSchema =
  new mongoose.Schema(
    {
      planted: {
        type: String,
        trim: true,
        default: "",
      },
      transplanted: {
        type: String,
        trim: true,
        default: "",
      },
      harvested: {
        type: String,
        trim: true,
        default: "",
      },
    },
    { _id: false },
  );

const productionTaskDayLedgerSchema =
  new mongoose.Schema(
    {
      planId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPlan",
        required: true,
        index: true,
      },
      taskId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionTask",
        required: true,
        index: true,
      },
      workDate: {
        type: Date,
        required: true,
        index: true,
      },
      unitType: {
        type: String,
        trim: true,
        default: "work unit",
      },
      unitTarget: {
        type: Number,
        min: 0,
        required: true,
      },
      unitCompleted: {
        type: Number,
        min: 0,
        default: 0,
      },
      unitRemaining: {
        type: Number,
        min: 0,
        default: 0,
      },
      status: {
        type: String,
        enum: PRODUCTION_TASK_DAY_LEDGER_STATUSES,
        default: "not_started",
        index: true,
      },
      activityTargets: {
        type: sharedActivityTargetsSchema,
        default: () => ({}),
      },
      activityCompleted: {
        type: sharedActivityTotalsSchema,
        default: () => ({}),
      },
      activityRemaining: {
        type: sharedActivityTargetsSchema,
        default: () => ({}),
      },
      activityUnits: {
        type: sharedActivityUnitsSchema,
        default: () => ({}),
      },
    },
    {
      timestamps: true,
    },
  );

productionTaskDayLedgerSchema.index(
  {
    taskId: 1,
    workDate: 1,
  },
  { unique: true },
);

const ProductionTaskDayLedger =
  mongoose.model(
    "ProductionTaskDayLedger",
    productionTaskDayLedgerSchema,
  );

module.exports = ProductionTaskDayLedger;
module.exports.SHARED_ACTIVITY_NONE =
  SHARED_ACTIVITY_NONE;
module.exports.SHARED_ACTIVITY_PLANTED =
  SHARED_ACTIVITY_PLANTED;
module.exports.SHARED_ACTIVITY_TRANSPLANTED =
  SHARED_ACTIVITY_TRANSPLANTED;
module.exports.SHARED_ACTIVITY_HARVESTED =
  SHARED_ACTIVITY_HARVESTED;
module.exports.SHARED_TRACKED_ACTIVITY_TYPES =
  SHARED_TRACKED_ACTIVITY_TYPES;
module.exports.PRODUCTION_TASK_DAY_LEDGER_STATUSES =
  PRODUCTION_TASK_DAY_LEDGER_STATUSES;
