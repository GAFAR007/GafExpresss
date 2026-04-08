/**
 * apps/backend/services/planner/schemas/taskSchema.js
 * ---------------------------------------------------
 * WHAT:
 * - JSON schema for planner V2 task-planner output.
 *
 * WHY:
 * - Structured semantic tasks must be validated before recurring/workload expansion.
 *
 * HOW:
 * - Requires a root object with a tasks array.
 * - Restricts AI output to planner-safe task fields only.
 */

const taskSchema = {
  type: "object",
  additionalProperties: false,
  required: ["tasks"],
  properties: {
    tasks: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "taskKey",
          "taskName",
          "taskType",
          "roleRequired",
        ],
        properties: {
          taskKey: {
            type: "string",
            minLength: 1,
          },
          taskName: {
            type: "string",
            minLength: 1,
          },
          taskType: {
            type: "string",
            enum: ["workload", "recurring", "event"],
          },
          roleRequired: {
            type: "string",
            minLength: 1,
          },
          requiredHeadcount: {
            type: "integer",
            minimum: 1,
          },
          unitType: {
            type: "string",
          },
          workloadUnits: {
            type: "number",
            minimum: 0,
          },
          frequencyEveryDays: {
            type: "integer",
            minimum: 1,
          },
          firstOccurrenceOffsetDays: {
            type: "integer",
            minimum: 0,
          },
          occurrence: {
            type: "string",
            enum: ["phase_start", "mid_phase", "phase_end"],
          },
          dependencies: {
            type: "array",
            items: {
              type: "string",
              minLength: 1,
            },
          },
        },
      },
    },
  },
};

module.exports = {
  taskSchema,
};
