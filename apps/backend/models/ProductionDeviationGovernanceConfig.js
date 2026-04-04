/**
 * apps/backend/models/ProductionDeviationGovernanceConfig.js
 * ----------------------------------------------------------
 * WHAT:
 * - Stores plan-scoped deviation governance thresholds for Stage 6 lifecycle control.
 *
 * WHY:
 * - Unit-level drift needs deterministic thresholds before lock/freeze actions can trigger.
 * - Thresholds must be configurable per crop template and per phase without hardcoding.
 *
 * HOW:
 * - Keeps one config row per plan.
 * - Persists default threshold days and optional phase-specific overrides.
 * - Tracks actor metadata for audit-safe governance updates.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug(
  "Loading ProductionDeviationGovernanceConfig model...",
);

const productionDeviationGovernanceConfigSchema =
  new mongoose.Schema(
    {
      // WHY: Plan scope keeps governance settings isolated per production cycle.
      planId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ProductionPlan",
        required: true,
        unique: true,
        index: true,
      },
      // WHY: Business scope supports tenant-safe configuration queries.
      businessId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Business",
        required: true,
        index: true,
      },
      // DEVIATION-GOVERNANCE
      // WHY: Product/crop template identity allows reusable threshold presets by crop type.
      cropTemplateId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Product",
        default: null,
        index: true,
      },
      // DEVIATION-GOVERNANCE
      // WHY: Default threshold provides safe fallback when phase-specific values are absent.
      defaultThresholdDays: {
        type: Number,
        min: 1,
        default: 3,
      },
      // DEVIATION-GOVERNANCE
      // WHY: Per-phase overrides keep risk policy aligned with biological phase sensitivity.
      phaseThresholdDays: {
        type: Map,
        of: Number,
        default: {},
      },
      // DEVIATION-GOVERNANCE
      // WHY: Phase-order thresholds enable crop-template carry-over even when phase ids change across plan cycles.
      phaseThresholdByOrder: {
        type: Map,
        of: Number,
        default: {},
      },
      // WHY: Created/updated actor metadata supports governance audit visibility.
      createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        required: true,
      },
      updatedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        required: true,
      },
    },
    {
      timestamps: true,
    },
  );

// DEVIATION-GOVERNANCE
// WHY: Crop template lookup helps preload phase thresholds for new plans.
productionDeviationGovernanceConfigSchema.index(
  {
    businessId: 1,
    cropTemplateId: 1,
  },
  {
    sparse: true,
  },
);

const ProductionDeviationGovernanceConfig =
  mongoose.model(
    "ProductionDeviationGovernanceConfig",
    productionDeviationGovernanceConfigSchema,
  );

module.exports =
  ProductionDeviationGovernanceConfig;
