/**
 * apps/backend/config/production_feature_flags.js
 * -----------------------------------------------
 * WHAT:
 * - Centralizes server-side feature flags for staged production lifecycle rollout.
 *
 * WHY:
 * - Keeps risky lifecycle upgrades disabled by default while allowing safe incremental enablement.
 * - Prevents scattered env parsing and inconsistent defaults across controllers/services.
 *
 * HOW:
 * - Parses boolean-like environment variables into strict true/false values.
 * - Exposes a single immutable flag object for backend modules.
 * - Logs a safe startup snapshot so operators can verify rollout state.
 */

const debug = require("../utils/debug");

// WHY: Accepted truthy values are intentionally strict to avoid accidental opt-in.
const BOOLEAN_TRUE_VALUES = new Set([
  "1",
  "true",
  "yes",
  "on",
]);

function readFlag(value) {
  const normalized =
    (value || "")
      .toString()
      .trim()
      .toLowerCase();
  return BOOLEAN_TRUE_VALUES.has(
    normalized,
  );
}

// WHY: All lifecycle upgrade flags default OFF for Stage 0 no-behavior-change rollout.
const PRODUCTION_FEATURE_FLAGS = Object.freeze(
  {
    enableAiPlannerV2: readFlag(
      process.env.PRODUCTION_ENABLE_AI_PLANNER_V2,
    ),
    enablePlanUnits: readFlag(
      process.env.PRODUCTION_ENABLE_PLAN_UNITS,
    ),
    enableUnitAssignments: readFlag(
      process.env.PRODUCTION_ENABLE_UNIT_ASSIGNMENTS,
    ),
    enablePhaseUnitCompletion:
      readFlag(
        process.env.PRODUCTION_ENABLE_PHASE_UNIT_COMPLETION,
      ),
    enablePhaseGate: readFlag(
      process.env.PRODUCTION_ENABLE_PHASE_GATE,
    ),
    enableDeviationGovernance:
      readFlag(
        process.env.PRODUCTION_ENABLE_DEVIATION_GOVERNANCE,
      ),
    enableConfidenceScore: readFlag(
      process.env.PRODUCTION_ENABLE_CONFIDENCE_SCORE,
    ),
  },
);

debug(
  "PRODUCTION_FEATURE_FLAGS: loaded",
  PRODUCTION_FEATURE_FLAGS,
);

module.exports = {
  PRODUCTION_FEATURE_FLAGS,
};
