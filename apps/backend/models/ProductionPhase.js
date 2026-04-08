/**
 * apps/backend/models/ProductionPhase.js
 * ------------------------------------------------
 * WHAT:
 * - Stores phases within a production plan.
 *
 * WHY:
 * - Phases group tasks by lifecycle stage (planning, planting, etc.).
 * - Enables phase-level KPI tracking and scheduling.
 *
 * HOW:
 * - Each phase references a ProductionPlan.
 * - Tracks dates, order, and completion status.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading ProductionPhase model...');

// WHY: Phase status drives progress tracking and KPIs.
const PRODUCTION_PHASE_STATUSES = [
  'pending',
  'in_progress',
  'done',
];
const PRODUCTION_PHASE_TYPES = [
  'finite',
  'monitoring',
];

const productionPhaseSchema = new mongoose.Schema(
  {
    // WHY: Phase must belong to a plan.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionPlan',
      required: true,
      index: true,
    },
    // WHY: Name matches default phase labels.
    name: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },
    // WHY: Order controls phase sequencing.
    order: {
      type: Number,
      min: 1,
      required: true,
    },
    // WHY: Phase dates are auto-calculated from plan duration.
    startDate: {
      type: Date,
      required: true,
    },
    endDate: {
      type: Date,
      required: true,
    },
    // WHY: Status supports phase-level completion tracking.
    status: {
      type: String,
      enum: PRODUCTION_PHASE_STATUSES,
      default: 'pending',
      index: true,
    },
    // WHY: KPI targets allow owners to set expectations per phase.
    kpiTarget: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    // PHASE-GATE-LAYER
    // WHY: Finite phases consume unit budget while monitoring phases remain lifecycle-neutral.
    phaseType: {
      type: String,
      enum: PRODUCTION_PHASE_TYPES,
      default: 'finite',
      required: true,
      index: true,
    },
    // PHASE-GATE-LAYER
    // WHY: Required units define the finite completion budget used by phase locking.
    requiredUnits: {
      type: Number,
      min: 0,
      default: 0,
    },
    // PHASE-GATE-LAYER
    // WHY: Minimum throughput per farmer-hour drives deterministic finite execution-day estimates.
    minRatePerFarmerHour: {
      type: Number,
      min: 0,
      default: 0.1,
    },
    // PHASE-GATE-LAYER
    // WHY: Target throughput supports manager guidance while minimum rate remains the planning floor.
    targetRatePerFarmerHour: {
      type: Number,
      min: 0,
      default: 0.2,
    },
    // PHASE-GATE-LAYER
    // WHY: Planned daily execution hours convert hourly throughput into daily unit coverage.
    plannedHoursPerDay: {
      type: Number,
      min: 0,
      default: 3,
    },
    // PHASE-GATE-LAYER
    // WHY: Biological minimum days preserve crop lifecycle windows even when finite labor completes earlier.
    biologicalMinDays: {
      type: Number,
      min: 0,
      default: 0,
    },
  },
  {
    timestamps: true,
  },
);

const ProductionPhase = mongoose.model(
  'ProductionPhase',
  productionPhaseSchema,
);

module.exports = ProductionPhase;
module.exports.PRODUCTION_PHASE_STATUSES =
  PRODUCTION_PHASE_STATUSES;
module.exports.PRODUCTION_PHASE_TYPES =
  PRODUCTION_PHASE_TYPES;
