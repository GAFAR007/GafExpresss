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

// WHY: Default phase list keeps production plans consistent.
const DEFAULT_PRODUCTION_PHASES = [
  { name: "Planning", order: 1 },
  { name: "Planting", order: 2 },
  { name: "Irrigation", order: 3 },
  { name: "Harvest", order: 4 },
  { name: "Storage", order: 5 },
];

module.exports = {
  DEFAULT_PRODUCTION_PHASES,
};
