/**
 * apps/backend/services/planner/schemas/phaseSchema.js
 * ----------------------------------------------------
 * WHAT:
 * - JSON schema for planner V2 phase-planner output.
 *
 * WHY:
 * - AJV validation must reject malformed AI payloads before scheduling begins.
 *
 * HOW:
 * - Requires a root object with a non-empty phases array.
 * - Each phase entry may only contain the canonical phaseName field.
 */

const phaseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["phases"],
  properties: {
    phases: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["phaseName"],
        properties: {
          phaseName: {
            type: "string",
            minLength: 1,
          },
        },
      },
    },
  },
};

module.exports = {
  phaseSchema,
};
