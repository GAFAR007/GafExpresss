/**
 * apps/backend/utils/production_defaults.js
 * ----------------------------------------
 * WHAT:
 * - Shared defaults for production planning.
 *
 * WHY:
 * - Prevents duplicated phase lists across services/controllers.
 * - Keeps AI + manual plan creation aligned.
 *
 * HOW:
 * - Exports the default ordered phase list used by scheduling.
 */

// WHY: Generic engine phases avoid domain lock-in when users start manually.
const DEFAULT_PRODUCTION_PHASES = [
  { name: "Planning", order: 1 },
  { name: "Execution", order: 2 },
  { name: "Quality Control", order: 3 },
  { name: "Output Preparation", order: 4 },
  { name: "Distribution", order: 5 },
];

module.exports = {
  DEFAULT_PRODUCTION_PHASES,
};
