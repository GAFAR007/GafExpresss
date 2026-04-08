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

const productionPlantingTargetsSchema = new mongoose.Schema(
  {
    materialType: {
      type: String,
      trim: true,
      default: '',
    },
    plannedPlantingQuantity: {
      type: Number,
      min: 0,
      default: null,
    },
    plannedPlantingUnit: {
      type: String,
      trim: true,
      default: '',
    },
    estimatedHarvestQuantity: {
      type: Number,
      min: 0,
      default: null,
    },
    estimatedHarvestUnit: {
      type: String,
      trim: true,
      default: '',
    },
  },
  {
    _id: false,
  },
);

const productionWorkloadContextSchema = new mongoose.Schema(
  {
    workUnitLabel: {
      type: String,
      trim: true,
      default: '',
    },
    workUnitType: {
      type: String,
      trim: true,
      default: '',
    },
    totalWorkUnits: {
      type: Number,
      min: 0,
      default: 0,
    },
    minStaffPerUnit: {
      type: Number,
      min: 0,
      default: 0,
    },
    maxStaffPerUnit: {
      type: Number,
      min: 0,
      default: 0,
    },
    activeStaffAvailabilityPercent: {
      type: Number,
      min: 0,
      max: 100,
      default: 0,
    },
    hasConfirmedWorkloadContext: {
      type: Boolean,
      default: false,
    },
  },
  {
    _id: false,
  },
);

const productionDraftActorSchema = new mongoose.Schema(
  {
    actorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    actorName: {
      type: String,
      trim: true,
      default: '',
    },
    actorEmail: {
      type: String,
      trim: true,
      default: '',
    },
    actorRole: {
      type: String,
      trim: true,
      default: '',
    },
    actorStaffRole: {
      type: String,
      trim: true,
      default: '',
    },
  },
  {
    _id: false,
  },
);

const productionDraftRevisionSummarySchema = new mongoose.Schema(
  {
    title: {
      type: String,
      trim: true,
      default: '',
    },
    status: {
      type: String,
      trim: true,
      default: 'draft',
    },
    phaseCount: {
      type: Number,
      min: 0,
      default: 0,
    },
    taskCount: {
      type: Number,
      min: 0,
      default: 0,
    },
    startDate: {
      type: Date,
      default: null,
    },
    endDate: {
      type: Date,
      default: null,
    },
  },
  {
    _id: false,
  },
);

const productionDraftRevisionSchema = new mongoose.Schema(
  {
    revisionNumber: {
      type: Number,
      min: 1,
      required: true,
    },
    action: {
      type: String,
      trim: true,
      default: 'updated',
    },
    note: {
      type: String,
      trim: true,
      default: '',
    },
    actor: {
      type: productionDraftActorSchema,
      default: null,
    },
    savedAt: {
      type: Date,
      default: Date.now,
    },
    summary: {
      type: productionDraftRevisionSummarySchema,
      default: () => ({}),
    },
    snapshot: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
  },
  {
    timestamps: false,
  },
);

const productionDraftAuditEntrySchema = new mongoose.Schema(
  {
    action: {
      type: String,
      trim: true,
      default: 'updated',
    },
    note: {
      type: String,
      trim: true,
      default: '',
    },
    revisionNumber: {
      type: Number,
      min: 0,
      default: 0,
    },
    actor: {
      type: productionDraftActorSchema,
      default: null,
    },
    createdAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    timestamps: false,
  },
);

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
    // WHY: Farm plans need explicit planting and expected harvest targets before execution starts.
    plantingTargets: {
      type: productionPlantingTargetsSchema,
      default: null,
    },
    // WHY: Execution screens need the saved unit model (for example greenhouse vs plot), not only phase budgets.
    workloadContext: {
      type: productionWorkloadContextSchema,
      default: null,
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
    // WHY: Draft saves must track who last changed the plan before activation.
    lastDraftSavedAt: {
      type: Date,
      default: null,
    },
    lastDraftSavedBy: {
      type: productionDraftActorSchema,
      default: null,
    },
    draftRevisionCount: {
      type: Number,
      min: 0,
      default: 0,
    },
    draftAuditTrailCount: {
      type: Number,
      min: 0,
      default: 0,
    },
    draftAuditLog: {
      type: [productionDraftAuditEntrySchema],
      default: [],
    },
    draftRevisions: {
      type: [productionDraftRevisionSchema],
      default: [],
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
