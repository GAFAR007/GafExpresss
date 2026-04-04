/**
 * apps/backend/models/ProductionPlan.js
 * ------------------------------------------------
 * WHAT:
 * - Stores domain-agnostic production plans (inputs -> outputs over time).
 *
 * WHY:
 * - Gives owners/managers a single record for product production cycles.
 * - Anchors phases, tasks, and KPI reporting to a plan.
 *
 * HOW:
 * - Each plan references a business, estate, and product.
 * - Tracks plan status, duration, and AI draft metadata.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');
const {
  PRODUCTION_DOMAIN_CONTEXTS,
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
} = require('../utils/production_engine.config');

debug('Loading ProductionPlan model...');

// WHY: Keep plan statuses consistent across UI and reporting.
const PRODUCTION_PLAN_STATUSES = [
  'draft',
  'active',
  'paused',
  'completed',
  'archived',
];

const productionPlanSchema = new mongoose.Schema(
  {
    // WHY: Business scope keeps plans isolated per owner.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true,
    },
    // WHY: Plans may be tied to a specific estate asset.
    estateAssetId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessAsset',
      required: true,
      index: true,
    },
    // WHY: Product links plan output to sellable inventory.
    productId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Product',
      required: true,
      index: true,
    },
    // WHY: Title provides human-friendly identification.
    title: {
      type: String,
      required: true,
      trim: true,
    },
    // WHY: Plan duration drives auto-scheduling for phases/tasks.
    startDate: {
      type: Date,
      required: true,
    },
    endDate: {
      type: Date,
      required: true,
    },
    // WHY: Status supports lifecycle management.
    status: {
      type: String,
      enum: PRODUCTION_PLAN_STATUSES,
      default: 'draft',
      index: true,
    },
    // WHY: Audits need to know who created the plan.
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    // WHY: Notes capture plan-specific details.
    notes: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Flags AI-generated drafts for review workflows.
    aiGenerated: {
      type: Boolean,
      default: false,
    },
    // WHY: Optional domain context biases AI planning without changing engine rules.
    domainContext: {
      type: String,
      enum: PRODUCTION_DOMAIN_CONTEXTS,
      default: DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
      index: true,
    },
    // DEVIATION-GOVERNANCE
    // WHY: Plan-level analytics summary gives managers a quick governance risk snapshot.
    deviationGovernanceSummary: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    // CONFIDENCE-SCORE
    // WHY: Baseline confidence is computed once at plan creation to preserve original execution assumptions.
    baselineConfidenceScore: {
      type: Number,
      min: 0,
      max: 1,
      default: null,
      index: true,
    },
    // CONFIDENCE-SCORE
    // WHY: Current confidence is recomputed only on deterministic lifecycle triggers.
    currentConfidenceScore: {
      type: Number,
      min: 0,
      max: 1,
      default: null,
      index: true,
    },
    // CONFIDENCE-SCORE
    // WHY: Baseline breakdown explains the starting confidence composition.
    baselineConfidenceBreakdown: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    // CONFIDENCE-SCORE
    // WHY: Current breakdown explains what is driving the latest score for manager actionability.
    currentConfidenceBreakdown: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    // CONFIDENCE-SCORE
    // WHY: Delta helps managers quickly understand confidence drift vs baseline.
    confidenceScoreDelta: {
      type: Number,
      default: null,
    },
    // CONFIDENCE-SCORE
    // WHY: Trigger metadata keeps recomputations auditable and avoids hidden score changes.
    confidenceLastTrigger: {
      type: String,
      trim: true,
      default: '',
    },
    confidenceLastComputedAt: {
      type: Date,
      default: null,
    },
    confidenceLastComputedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    confidenceRecomputeCount: {
      type: Number,
      min: 0,
      default: 0,
    },
  },
  {
    timestamps: true,
  },
);

const ProductionPlan = mongoose.model(
  'ProductionPlan',
  productionPlanSchema,
);

module.exports = ProductionPlan;
module.exports.PRODUCTION_PLAN_STATUSES =
  PRODUCTION_PLAN_STATUSES;
