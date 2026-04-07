/**
 * apps/backend/models/ProductionTask.js
 * ------------------------------------------------
 * WHAT:
 * - Stores tasks within production phases.
 *
 * WHY:
 * - Tasks define who does what and when within each phase.
 * - Supports role-based assignment and owner approvals.
 *
 * HOW:
 * - Each task references a plan + phase.
 * - Requires staff role with optional assignment metadata.
 * - Tracks approval status, timing, and completion.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');
const {
  STAFF_ROLES,
} = require('./BusinessStaffProfile');

debug('Loading ProductionTask model...');

// WHY: Task lifecycle states must be consistent for KPI tracking.
const PRODUCTION_TASK_STATUSES = [
  'pending',
  'in_progress',
  'done',
];

// WHY: Owner approval is required before assignments become active.
const TASK_APPROVAL_STATUSES = [
  'pending_approval',
  'approved',
  'rejected',
];

// WHY: Planner V2 expands semantic task types into concrete scheduled rows while preserving source intent.
const PRODUCTION_TASK_TYPES = [
  'workload',
  'recurring',
  'event',
];

const productionTaskSchema = new mongoose.Schema(
  {
    // WHY: Tasks must be linked to the plan for reporting.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionPlan',
      required: true,
      index: true,
    },
    // WHY: Phase groups tasks by lifecycle stage.
    phaseId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'ProductionPhase',
      required: true,
      index: true,
    },
    // WHY: Title names the work to be done.
    title: {
      type: String,
      required: true,
      trim: true,
    },
    // WHY: Role-based constraints ensure correct staff assignment.
    roleRequired: {
      type: String,
      enum: STAFF_ROLES,
      required: true,
      trim: true,
      index: true,
    },
    // WHY: Keep single-assignee compatibility for existing flows.
    assignedStaffId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessStaffProfile',
      default: null,
      index: true,
    },
    // WHY: Multi-assign support lets managers fulfill required headcount over time.
    assignedStaffProfileIds: {
      type: [
        {
          type: mongoose.Schema.Types.ObjectId,
          ref: 'BusinessStaffProfile',
        },
      ],
      default: [],
    },
    // UNIT-LIFECYCLE
    // WHY: Canonical plan-unit ids keep unit coverage deterministic and server-owned.
    assignedUnitIds: {
      type: [
        {
          type: mongoose.Schema.Types.ObjectId,
          ref: 'PlanUnit',
        },
      ],
      default: [],
    },
    // WHY: Headcount keeps staffing intent explicit before assignment is complete.
    requiredHeadcount: {
      type: Number,
      min: 1,
      default: 1,
    },
    // WHY: Planner V2 keeps semantic task type for downstream reporting and export grouping.
    taskType: {
      type: String,
      enum: PRODUCTION_TASK_TYPES,
      default: null,
      index: true,
    },
    // WHY: Semantic template keys let recurring/event rows trace back to one planner-generated template.
    sourceTemplateKey: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Recurrence grouping keeps all expanded occurrences linked for review/export behavior.
    recurrenceGroupKey: {
      type: String,
      trim: true,
      default: '',
      index: true,
    },
    // WHY: Occurrence order preserves recurring/event expansion sequence for deterministic rendering.
    occurrenceIndex: {
      type: Number,
      min: 0,
      default: 0,
    },
    // WHY: Weight drives auto-scheduling within a phase.
    weight: {
      type: Number,
      min: 1,
      default: 1,
    },
    // WHY: Manual sort order keeps same-slot draft ordering stable after rescheduling.
    manualSortOrder: {
      type: Number,
      min: 0,
      default: 0,
      index: true,
    },
    // WHY: Auto-calculated dates keep schedules consistent.
    startDate: {
      type: Date,
      required: true,
    },
    dueDate: {
      type: Date,
      required: true,
    },
    // WHY: Status captures progress for KPIs.
    status: {
      type: String,
      enum: PRODUCTION_TASK_STATUSES,
      default: 'pending',
      index: true,
    },
    // WHY: Completion time is used to calculate delays.
    completedAt: {
      type: Date,
      default: null,
    },
    // WHY: Instructions guide staff on task requirements.
    instructions: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Dependencies prevent invalid task ordering.
    dependencies: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ProductionTask',
      },
    ],
    // WHY: Track who created the task for accountability.
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    // WHY: Owner approval is required before assignments activate.
    approvalStatus: {
      type: String,
      enum: TASK_APPROVAL_STATUSES,
      default: 'pending_approval',
      index: true,
    },
    // WHY: Track who assigned the task.
    assignedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    // WHY: Track owner review on approval or rejection.
    reviewedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    reviewedAt: {
      type: Date,
      default: null,
    },
    // WHY: Capture rejection reason for transparency.
    rejectionReason: {
      type: String,
      trim: true,
      default: '',
    },
  },
  {
    timestamps: true,
  },
);

// UNIT-LIFECYCLE
// WHY: Phase-level unit assignment queries need a scoped multikey index for fast filtering.
productionTaskSchema.index({
  planId: 1,
  phaseId: 1,
  assignedUnitIds: 1,
});

// WHY: Calendar/detail views need deterministic ordering for tasks that share the same time window.
productionTaskSchema.index({
  planId: 1,
  startDate: 1,
  dueDate: 1,
  manualSortOrder: 1,
});

const ProductionTask = mongoose.model(
  'ProductionTask',
  productionTaskSchema,
);

module.exports = ProductionTask;
module.exports.PRODUCTION_TASK_STATUSES =
  PRODUCTION_TASK_STATUSES;
module.exports.TASK_APPROVAL_STATUSES =
  TASK_APPROVAL_STATUSES;
module.exports.PRODUCTION_TASK_TYPES =
  PRODUCTION_TASK_TYPES;
