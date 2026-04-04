/**
 * apps/backend/models/ProductionUnitScheduleWarning.js
 * ----------------------------------------------------
 * WHAT:
 * - Stores manager-facing warnings detected during per-unit schedule propagation.
 *
 * WHY:
 * - Stage 5 requires conflict detection when unit-level shifts can create timeline risk.
 * - Warnings must be persisted for review instead of silently auto-rebalancing staff.
 *
 * HOW:
 * - Writes one warning row per detected issue (missing unit context, overlap conflict, etc.).
 * - Keeps source progress and metadata for explainable diagnostics.
 * - Supports open-warning queries by plan/unit/date.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug(
  "Loading ProductionUnitScheduleWarning model...",
);

const PRODUCTION_UNIT_WARNING_TYPES = [
  "MISSING_UNIT_CONTEXT",
  "SHIFT_CONFLICT",
];
const PRODUCTION_UNIT_WARNING_SEVERITIES =
  ["info", "warning"];

const productionUnitScheduleWarningSchema =
  new mongoose.Schema(
    {
      // WHY: Plan scoping keeps warning data isolated per lifecycle.
      planId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPlan",
        required: true,
        index: true,
      },
      // WHY: Optional task linkage helps managers locate where conflict happened.
      taskId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionTask",
        default: null,
        index: true,
      },
      // WHY: Phase linkage keeps warnings traceable to lifecycle stage.
      phaseId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPhase",
        default: null,
        index: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Unit-level conflicts must map directly to canonical PlanUnit ids.
      unitId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "PlanUnit",
        required: true,
        index: true,
      },
      // UNIT-LIFECYCLE
      // WHY: Warning type normalizes conflict handling and manager triage.
      warningType: {
        type: String,
        enum: PRODUCTION_UNIT_WARNING_TYPES,
        required: true,
        index: true,
      },
      // WHY: Severity allows UI prioritization without hardcoding risk logic.
      severity: {
        type: String,
        enum:
          PRODUCTION_UNIT_WARNING_SEVERITIES,
        default: "warning",
        required: true,
      },
      // WHY: Message must be actionable for manager intervention.
      message: {
        type: String,
        trim: true,
        required: true,
      },
      // WHY: Shift size gives quick context on delay impact.
      shiftDays: {
        type: Number,
        default: 0,
      },
      // WHY: Source linkage allows exact trace-back to approved progress rows.
      sourceProgressId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "TaskProgress",
        default: null,
        index: true,
      },
      // WHY: Structured metadata stores non-PII conflict details for diagnostics.
      metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: null,
      },
      // WHY: Resolved timestamp supports manager acknowledgment workflows.
      resolvedAt: {
        type: Date,
        default: null,
        index: true,
      },
    },
    {
      timestamps: true,
    },
  );

// UNIT-LIFECYCLE
// WHY: Manager dashboards query recent open warnings per plan + unit.
productionUnitScheduleWarningSchema.index({
  planId: 1,
  unitId: 1,
  createdAt: -1,
});

const ProductionUnitScheduleWarning =
  mongoose.model(
    "ProductionUnitScheduleWarning",
    productionUnitScheduleWarningSchema,
  );

module.exports =
  ProductionUnitScheduleWarning;
module.exports.PRODUCTION_UNIT_WARNING_TYPES =
  PRODUCTION_UNIT_WARNING_TYPES;
module.exports.PRODUCTION_UNIT_WARNING_SEVERITIES =
  PRODUCTION_UNIT_WARNING_SEVERITIES;
