/**
 * apps/backend/services/planner/validationEngine.js
 * -------------------------------------------------
 * WHAT:
 * - AJV-backed validation engine for planner V2 AI outputs and lifecycle rules.
 *
 * WHY:
 * - Planner V2 must reject malformed or biologically invalid AI payloads before scheduling.
 * - Explicit validation removes the need for synthetic fallback schedules.
 *
 * HOW:
 * - Validates phase and task payloads against JSON schema.
 * - Rejects forbidden AI fields such as startDate/dueDate/worker assignments.
 * - Enforces lifecycle order, dependency direction, recurrence safety, and range validity.
 */

const Ajv = require("ajv");
const debug = require("../../utils/debug");
const {
  STAFF_ROLES,
} = require("../../utils/production_engine.config");
const {
  phaseSchema,
} = require("./schemas/phaseSchema");
const {
  taskSchema,
} = require("./schemas/taskSchema");

const ajv = new Ajv({
  allErrors: true,
  strict: false,
});

const validatePhaseSchema = ajv.compile(phaseSchema);
const validateTaskSchema = ajv.compile(taskSchema);

const FORBIDDEN_AI_FIELDS = new Set([
  "startDate",
  "dueDate",
  "workerId",
  "workerIds",
  "assignedTo",
  "assignedStaffId",
  "assignedStaffProfileIds",
  "schedule",
  "scheduleBlocks",
]);

function buildPlannerValidationError({
  message,
  errorCode,
  details = {},
  resolutionHint,
  statusCode = 422,
  retryAllowed = true,
  retryReason = "provider_output_invalid",
  classification = "PROVIDER_REJECTED_FORMAT",
}) {
  const error = new Error(message);
  error.errorCode = errorCode;
  error.details = details;
  error.resolutionHint = resolutionHint;
  error.statusCode = statusCode;
  error.httpStatus = statusCode;
  error.retryAllowed = retryAllowed;
  error.retryReason = retryReason;
  error.classification = classification;
  error.retry_allowed = retryAllowed;
  error.retry_reason = retryReason;
  return error;
}

function findForbiddenFieldPaths(value, currentPath = "$") {
  if (Array.isArray(value)) {
    return value.flatMap((entry, index) =>
      findForbiddenFieldPaths(entry, `${currentPath}[${index}]`),
    );
  }
  if (!value || typeof value !== "object") {
    return [];
  }

  const matches = [];
  Object.entries(value).forEach(([key, nestedValue]) => {
    const nextPath = `${currentPath}.${key}`;
    if (FORBIDDEN_AI_FIELDS.has(key)) {
      matches.push(nextPath);
    }
    matches.push(
      ...findForbiddenFieldPaths(nestedValue, nextPath),
    );
  });
  return matches;
}

function mapAjvErrors(errors = []) {
  return errors.map((entry) => ({
    path: entry.instancePath || "$",
    message: entry.message || "schema validation failed",
  }));
}

function normalizePhaseName(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function normalizeTaskKey(value) {
  const normalized = normalizePhaseName(value);
  return normalized || "task";
}

function validateLifecyclePlanningWindow({
  lifecycle,
  requestedDays,
}) {
  const safeRequestedDays = Math.max(
    1,
    Math.floor(Number(requestedDays || 0)),
  );
  if (
    safeRequestedDays < Number(lifecycle.minDays || 0) ||
    safeRequestedDays > Number(lifecycle.maxDays || 0)
  ) {
    throw buildPlannerValidationError({
      message:
        "Requested planning range is outside the supported lifecycle window.",
      errorCode:
        "PRODUCTION_AI_PLANNER_V2_RANGE_OUTSIDE_LIFECYCLE",
      resolutionHint:
        "Use a planning range that stays within the product lifecycle bounds.",
      details: {
        requestedDays: safeRequestedDays,
        minDays: lifecycle.minDays,
        maxDays: lifecycle.maxDays,
      },
      retryAllowed: false,
      retryReason: "client_validation_failed",
      classification: "INVALID_INPUT",
      statusCode: 422,
    });
  }
}

function validatePhasePlan({
  lifecycle,
  payload,
}) {
  const forbiddenPaths = findForbiddenFieldPaths(payload);
  if (forbiddenPaths.length > 0) {
    throw buildPlannerValidationError({
      message:
        "Phase planner returned forbidden scheduling fields.",
      errorCode:
        "PRODUCTION_AI_PLANNER_V2_PHASE_FORBIDDEN_FIELDS",
      resolutionHint:
        "Return lifecycle phase names only. Do not include dates, staff, or schedule fields.",
      details: {
        forbiddenPaths,
      },
    });
  }

  if (!validatePhaseSchema(payload)) {
    throw buildPlannerValidationError({
      message:
        "Phase planner returned an invalid schema payload.",
      errorCode:
        "PRODUCTION_AI_PLANNER_V2_PHASE_SCHEMA_INVALID",
      resolutionHint:
        "Return only a JSON object with a phases array of phaseName strings.",
      details: {
        errors: mapAjvErrors(validatePhaseSchema.errors),
      },
    });
  }

  const lifecycleOrder = new Map(
    (lifecycle.phases || []).map((phaseName, index) => [
      normalizePhaseName(phaseName),
      index,
    ]),
  );
  const normalizedPhases = [];
  let previousIndex = -1;

  payload.phases.forEach((phaseEntry) => {
    const phaseName = normalizePhaseName(phaseEntry.phaseName);
    const lifecycleIndex = lifecycleOrder.get(phaseName);
    if (lifecycleIndex == null) {
      throw buildPlannerValidationError({
        message:
          "Phase planner returned a phase outside the lifecycle catalog.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_PHASE_OUTSIDE_LIFECYCLE",
        resolutionHint:
          "Return only phases that exist in the resolved lifecycle.",
        details: {
          phaseName,
          lifecyclePhases: lifecycle.phases,
        },
      });
    }
    if (lifecycleIndex <= previousIndex) {
      throw buildPlannerValidationError({
        message:
          "Phase planner returned phases out of lifecycle order.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_PHASE_ORDER_INVALID",
        resolutionHint:
          "Return lifecycle phases as an increasing ordered subset.",
        details: {
          phaseName,
          previousIndex,
          lifecycleIndex,
        },
      });
    }
    previousIndex = lifecycleIndex;
    normalizedPhases.push({
      phaseName,
      lifecycleIndex,
    });
  });

  return normalizedPhases;
}

function ensureDependenciesAreAcyclic(tasks) {
  const byKey = new Map(
    tasks.map((task, index) => [task.taskKey, { task, index }]),
  );

  tasks.forEach((task, index) => {
    (task.dependencies || []).forEach((dependencyKey) => {
      const dependency = byKey.get(dependencyKey);
      if (!dependency) {
        throw buildPlannerValidationError({
          message:
            "Task planner returned a dependency that does not exist.",
          errorCode:
            "PRODUCTION_AI_PLANNER_V2_TASK_DEPENDENCY_MISSING",
          resolutionHint:
            "Dependencies must reference an earlier taskKey in the same phase.",
          details: {
            taskKey: task.taskKey,
            dependencyKey,
          },
        });
      }
      if (dependency.index >= index) {
        throw buildPlannerValidationError({
          message:
            "Task planner returned a forward dependency.",
          errorCode:
            "PRODUCTION_AI_PLANNER_V2_TASK_DEPENDENCY_FORWARD",
          resolutionHint:
            "Dependencies must reference earlier tasks only.",
          details: {
            taskKey: task.taskKey,
            dependencyKey,
          },
        });
      }
    });
  });

  const visited = new Set();
  const active = new Set();

  function visit(taskKey) {
    if (active.has(taskKey)) {
      throw buildPlannerValidationError({
        message:
          "Task planner returned a cyclic dependency graph.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_TASK_DEPENDENCY_CYCLE",
        resolutionHint:
          "Remove cycles from the dependency graph.",
        details: {
          taskKey,
        },
      });
    }
    if (visited.has(taskKey)) {
      return;
    }
    visited.add(taskKey);
    active.add(taskKey);
    const task = byKey.get(taskKey)?.task;
    (task?.dependencies || []).forEach(visit);
    active.delete(taskKey);
  }

  tasks.forEach((task) => visit(task.taskKey));
}

function validateTaskPlan({
  phaseName,
  payload,
}) {
  const forbiddenPaths = findForbiddenFieldPaths(payload);
  if (forbiddenPaths.length > 0) {
    throw buildPlannerValidationError({
      message:
        "Task planner returned forbidden scheduling or assignment fields.",
      errorCode:
        "PRODUCTION_AI_PLANNER_V2_TASK_FORBIDDEN_FIELDS",
      resolutionHint:
        "Return semantic tasks only. Do not include dates, staff ids, or schedule blocks.",
      details: {
        forbiddenPaths,
        phaseName,
      },
    });
  }

  if (!validateTaskSchema(payload)) {
    throw buildPlannerValidationError({
      message:
        "Task planner returned an invalid schema payload.",
      errorCode:
        "PRODUCTION_AI_PLANNER_V2_TASK_SCHEMA_INVALID",
      resolutionHint:
        "Return only valid planner task fields for this phase.",
      details: {
        errors: mapAjvErrors(validateTaskSchema.errors),
        phaseName,
      },
    });
  }

  const normalizedTasks = payload.tasks.map((task, index) => {
    const taskType = (task.taskType || "").toString().trim();
    const roleRequired = (task.roleRequired || "")
      .toString()
      .trim()
      .toLowerCase();
    if (!STAFF_ROLES.includes(roleRequired)) {
      throw buildPlannerValidationError({
        message:
          "Task planner returned an unsupported staff role.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_TASK_ROLE_INVALID",
        resolutionHint:
          "Use one of the supported backend staff roles only.",
        details: {
          phaseName,
          roleRequired,
          supportedRoles: STAFF_ROLES,
        },
      });
    }
    if (
      taskType === "workload" &&
      !(Number(task.workloadUnits) > 0)
    ) {
      throw buildPlannerValidationError({
        message:
          "Workload tasks must include positive workloadUnits.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_TASK_WORKLOAD_UNITS_REQUIRED",
        resolutionHint:
          "Provide workloadUnits for workload task types.",
        details: {
          phaseName,
          taskKey: task.taskKey,
        },
      });
    }
    if (
      taskType === "recurring" &&
      !(Number(task.frequencyEveryDays) >= 1)
    ) {
      throw buildPlannerValidationError({
        message:
          "Recurring tasks must include a valid frequencyEveryDays value.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_TASK_RECURRENCE_INVALID",
        resolutionHint:
          "Use frequencyEveryDays >= 1 for recurring tasks.",
        details: {
          phaseName,
          taskKey: task.taskKey,
        },
      });
    }
    if (
      taskType === "event" &&
      !["phase_start", "mid_phase", "phase_end"].includes(
        (task.occurrence || "").toString().trim(),
      )
    ) {
      throw buildPlannerValidationError({
        message:
          "Event tasks must include a supported occurrence anchor.",
        errorCode:
          "PRODUCTION_AI_PLANNER_V2_TASK_EVENT_OCCURRENCE_INVALID",
        resolutionHint:
          "Use phase_start, mid_phase, or phase_end for event occurrence.",
        details: {
          phaseName,
          taskKey: task.taskKey,
        },
      });
    }

    return {
      taskKey: normalizeTaskKey(task.taskKey || `${phaseName}_${index + 1}`),
      taskName: (task.taskName || "").toString().trim(),
      taskType,
      roleRequired,
      requiredHeadcount: Math.max(
        1,
        Math.floor(Number(task.requiredHeadcount || 1)),
      ),
      unitType: (task.unitType || "").toString().trim(),
      workloadUnits: Number(task.workloadUnits || 0),
      frequencyEveryDays: Number(task.frequencyEveryDays || 0),
      firstOccurrenceOffsetDays: Math.max(
        0,
        Math.floor(Number(task.firstOccurrenceOffsetDays || 0)),
      ),
      occurrence: (task.occurrence || "mid_phase")
        .toString()
        .trim(),
      dependencies: Array.from(
        new Set(
          (Array.isArray(task.dependencies) ? task.dependencies : [])
            .map((entry) => normalizeTaskKey(entry))
            .filter(Boolean),
        ),
      ),
    };
  });

  ensureDependenciesAreAcyclic(normalizedTasks);

  debug(
    "PLANNER_V2_VALIDATION: task payload validated",
    {
      intent:
        "validated semantic task plan for planner V2",
      phaseName,
      taskCount: normalizedTasks.length,
    },
  );

  return normalizedTasks;
}

module.exports = {
  FORBIDDEN_AI_FIELDS,
  buildPlannerValidationError,
  normalizePhaseName,
  normalizeTaskKey,
  validateLifecyclePlanningWindow,
  validatePhasePlan,
  validateTaskPlan,
};
