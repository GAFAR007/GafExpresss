/**
 * apps/backend/models/ProductionPhaseUnitCompletion.js
 * ----------------------------------------------------
 * WHAT:
 * - Stores immutable phase-level completion truth per canonical plan unit.
 *
 * WHY:
 * - Stage 3 requires deterministic unit completion that is idempotent and approval-respected.
 * - Prevents duplicate completion rows for the same (plan, phase, unit) lifecycle checkpoint.
 *
 * HOW:
 * - Inserts one document per completed unit within a phase.
 * - Uses a compound unique index on (planId, phaseId, unitId) for idempotency.
 * - Keeps actor/task metadata for auditability and downstream lifecycle analytics.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug(
  "Loading ProductionPhaseUnitCompletion model...",
);

// UNIT-LIFECYCLE
const productionPhaseUnitCompletionSchema =
  new mongoose.Schema(
    {
      // WHY: Keeps completion rows scoped to one plan lifecycle.
      planId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPlan",
        required: true,
        index: true,
      },
      // WHY: Completion is phase-specific and must be queryable quickly.
      phaseId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPhase",
        required: true,
        index: true,
      },
      // WHY: Canonical unit identity links completion truth to PlanUnit.
      unitId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "PlanUnit",
        required: true,
        index: true,
      },
      // WHY: Audit trail requires knowing who approved/completed the unit checkpoint.
      completedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        required: true,
      },
      // WHY: Timestamp preserves when lifecycle truth was accepted.
      completedAt: {
        type: Date,
        required: true,
      },
      // WHY: Source task id allows deterministic trace-back to the completion event.
      sourceTaskId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionTask",
        required: true,
      },
    },
    {
      timestamps: true,
    },
  );

// UNIT-LIFECYCLE
// WHY: Guarantees idempotent completion writes for the same phase-unit checkpoint.
productionPhaseUnitCompletionSchema.index(
  {
    planId: 1,
    phaseId: 1,
    unitId: 1,
  },
  { unique: true },
);

const ProductionPhaseUnitCompletion =
  mongoose.model(
    "ProductionPhaseUnitCompletion",
    productionPhaseUnitCompletionSchema,
  );

module.exports =
  ProductionPhaseUnitCompletion;
