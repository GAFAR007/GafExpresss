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
