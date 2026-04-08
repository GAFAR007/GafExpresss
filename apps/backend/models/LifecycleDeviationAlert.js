/**
 * apps/backend/models/LifecycleDeviationAlert.js
 * ----------------------------------------------
 * WHAT:
 * - Stores deviation-governance alerts raised when unit drift exceeds configured thresholds.
 *
 * WHY:
 * - Stage 6 requires freeze + manager intervention when cumulative schedule drift becomes unsafe.
 * - Alerts provide a durable audit trail for variance acceptance and manual replanning actions.
 *
 * HOW:
 * - Creates one alert per threshold breach event.
 * - Tracks status transitions (open, variance accepted, replanned).
 * - Persists lock context and resolution metadata for analytics and review.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug(
  "Loading LifecycleDeviationAlert model...",
);

const LIFECYCLE_DEVIATION_ALERT_STATUSES = [
  "open",
  "variance_accepted",
  "replanned",
];
const LIFECYCLE_DEVIATION_ALERT_ACTION_TYPES =
  [
    "triggered",
    "accept_variance",
    "replan_unit",
  ];

const lifecycleDeviationAlertSchema =
  new mongoose.Schema(
    {
      // WHY: Plan scope keeps alerts attached to one production lifecycle.
      planId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPlan",
        required: true,
        index: true,
      },
      // WHY: Business scope enables tenant-safe alert listings.
      businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Business",
        required: true,
        index: true,
      },
      // DEVIATION-GOVERNANCE
      // WHY: Unit-level governance decisions are made per canonical plan unit.
      unitId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "PlanUnit",
        required: true,
        index: true,
      },
      sourceProgressId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "TaskProgress",
        default: null,
        index: true,
      },
      sourceTaskId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionTask",
        default: null,
        index: true,
      },
      // DEVIATION-GOVERNANCE
      // WHY: Cumulative deviation is compared to threshold to justify freeze decisions.
      cumulativeDeviationDays: {
        type: Number,
        min: 0,
        required: true,
      },
      thresholdDays: {
        type: Number,
        min: 1,
        required: true,
      },
      status: {
        type: String,
        enum:
          LIFECYCLE_DEVIATION_ALERT_STATUSES,
        default: "open",
        index: true,
      },
      message: {
        type: String,
        trim: true,
        required: true,
      },
      triggeredAt: {
        type: Date,
        required: true,
      },
      resolvedAt: {
        type: Date,
        default: null,
      },
      resolvedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        default: null,
      },
      resolutionNote: {
        type: String,
        trim: true,
        default: "",
      },
      // WHY: Action history stores clear intervention timeline for governance audits.
      actionHistory: {
        type: [
          {
            actionType: {
              type: String,
              enum:
                LIFECYCLE_DEVIATION_ALERT_ACTION_TYPES,
              required: true,
            },
            actorId: {
              type: mongoose.Schema.Types.ObjectId,
              ref: "User",
              default: null,
            },
            actedAt: {
              type: Date,
              required: true,
            },
            note: {
              type: String,
              trim: true,
              default: "",
            },
            metadata: {
              type: mongoose.Schema.Types.Mixed,
              default: null,
            },
          },
        ],
        default: [],
      },
    },
    {
      timestamps: true,
    },
  );

// DEVIATION-GOVERNANCE
// WHY: Manager dashboards need fast open-alert scans per plan and unit.
lifecycleDeviationAlertSchema.index({
  planId: 1,
  unitId: 1,
  status: 1,
  createdAt: -1,
});

const LifecycleDeviationAlert =
  mongoose.model(
    "LifecycleDeviationAlert",
    lifecycleDeviationAlertSchema,
  );

module.exports = LifecycleDeviationAlert;
module.exports.LIFECYCLE_DEVIATION_ALERT_STATUSES =
  LIFECYCLE_DEVIATION_ALERT_STATUSES;
module.exports.LIFECYCLE_DEVIATION_ALERT_ACTION_TYPES =
  LIFECYCLE_DEVIATION_ALERT_ACTION_TYPES;
