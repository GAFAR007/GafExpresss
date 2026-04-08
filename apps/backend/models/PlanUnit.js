/**
 * apps/backend/models/PlanUnit.js
 * --------------------------------
 * WHAT:
 * - Stores canonical plan-scoped work units (for example Plot 1..N).
 *
 * WHY:
 * - Provides deterministic unit identity for lifecycle tracking and scheduling.
 * - Avoids relying on free-text unit labels from AI or UI payloads.
 *
 * HOW:
 * - Each unit belongs to one ProductionPlan.
 * - unitIndex is unique within a plan via compound unique index.
 * - Labels are human-readable but identity is based on the document id.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading PlanUnit model...");

// UNIT-LIFECYCLE
const planUnitSchema = new mongoose.Schema(
  {
    // WHY: Keeps units isolated per production plan.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ProductionPlan",
      required: true,
      index: true,
    },
    // WHY: Stable 1..N ordering allows deterministic assignment and display.
    unitIndex: {
      type: Number,
      min: 1,
      required: true,
    },
    // WHY: Human-readable label helps operators identify each plan unit quickly.
    label: {
      type: String,
      required: true,
      trim: true,
    },
    // DEVIATION-GOVERNANCE
    // WHY: Unit-level governance lock stops further automatic shifts after excessive variance.
    deviationLocked: {
      type: Boolean,
      default: false,
      index: true,
    },
    deviationLockedAt: {
      type: Date,
      default: null,
    },
    deviationLockReason: {
      type: String,
      trim: true,
      default: "",
    },
    deviationLockedByAlertId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "LifecycleDeviationAlert",
      default: null,
    },
    varianceAcceptedAt: {
      type: Date,
      default: null,
    },
    varianceAcceptedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    varianceAcceptedAlertId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "LifecycleDeviationAlert",
      default: null,
    },
  },
  {
    // WHY: Stage 1 only needs createdAt for lifecycle-safe audit breadcrumbs.
    timestamps: {
      createdAt: true,
      updatedAt: false,
    },
  },
);

// WHY: Prevent duplicate logical units inside the same plan.
planUnitSchema.index(
  { planId: 1, unitIndex: 1 },
  { unique: true },
);

const PlanUnit = mongoose.model(
  "PlanUnit",
  planUnitSchema,
);

module.exports = PlanUnit;
