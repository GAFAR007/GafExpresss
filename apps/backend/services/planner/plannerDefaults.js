/**
 * apps/backend/services/planner/plannerDefaults.js
 * ------------------------------------------------
 * WHAT:
 * - Stores deterministic defaults for planner V2 throughput and phase duration assumptions.
 *
 * WHY:
 * - The scheduler must remain stable even when AI omits productivity hints.
 * - Farm-first rollout needs conservative defaults for recurring and workload expansion.
 *
 * HOW:
 * - Exposes per-role/per-task throughput values.
 * - Exposes canonical phase duration weights for lifecycle window allocation.
 * - Exposes default event/recurrence timing hints used by scheduleBuilder.
 */

const DEFAULT_THROUGHPUT = Object.freeze({
  farmer: Object.freeze({
    land_preparation: 2,
    planting: 2,
    irrigation: 5,
    weeding: 4,
    pest_inspection: 6,
    fertilizer_application: 4,
    harvesting: 3,
    default: 2,
  }),
  field_agent: Object.freeze({
    fertilizer_application: 5,
    pest_inspection: 7,
    crop_health_check: 6,
    default: 4,
  }),
  farm_manager: Object.freeze({
    supervision: 10,
    monitoring: 10,
    default: 8,
  }),
  estate_manager: Object.freeze({
    oversight: 12,
    compliance_review: 12,
    default: 10,
  }),
});

const DEFAULT_PHASE_DURATIONS = Object.freeze({
  land_preparation: 7,
  planting: 5,
  early_growth: 14,
  vegetative_growth: 21,
  flowering: 14,
  grain_fill: 24,
  pod_development: 18,
  harvest: 7,
  post_harvest: 7,
});

const DEFAULT_EVENT_OCCURRENCE = Object.freeze({
  phase_start: 0,
  mid_phase: 0.5,
  phase_end: 1,
});

const DEFAULT_RECURRING_OFFSET_DAYS = 1;
const DEFAULT_WORKLOAD_UNITS_PER_ROW = 1;

module.exports = {
  DEFAULT_THROUGHPUT,
  DEFAULT_PHASE_DURATIONS,
  DEFAULT_EVENT_OCCURRENCE,
  DEFAULT_RECURRING_OFFSET_DAYS,
  DEFAULT_WORKLOAD_UNITS_PER_ROW,
};
