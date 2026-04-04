/**
 * apps/backend/services/planner/taskPlanner.js
 * --------------------------------------------
 * WHAT:
 * - Generates semantic tasks for each lifecycle phase in planner V2.
 *
 * WHY:
 * - AI should describe production work structurally, while the backend owns calendar scheduling.
 * - Per-phase generation reduces schema drift and makes retries more targeted.
 *
 * HOW:
 * - Calls the shared AI client once per phase.
 * - Validates task JSON with AJV plus planner-specific lifecycle rules.
 * - Retries with correction hints before failing cleanly.
 */

const debug = require("../../utils/debug");
const {
  createAiChatCompletion,
} = require("../ai.service");
const {
  STAFF_ROLES,
} = require("../../utils/production_engine.config");
const {
  validateTaskPlan,
} = require("./validationEngine");
const {
  extractJsonObject,
} = require("./jsonExtraction");

const MAX_TASK_PLANNER_ATTEMPTS = 3;
const DEFAULT_FALLBACK_RECURRENCE_DAYS = 7;
const DEFAULT_FALLBACK_HEADCOUNT = 1;
const TASK_PLANNER_TEMPERATURE = 0.1;
const TASK_PLANNER_MAX_TOKENS = 400;

function tryParseJsonValue(rawValue) {
  const trimmed = (rawValue || "").toString().trim();
  if (!trimmed) {
    return null;
  }
  try {
    return JSON.parse(trimmed);
  } catch (_) {
    return null;
  }
}

function isTaskPlannerRateLimitError(error) {
  const classification = (error?.classification || "")
    .toString()
    .trim()
    .toUpperCase();
  const retryReason = (error?.retry_reason || "")
    .toString()
    .trim()
    .toLowerCase();
  const httpStatus =
    Number(error?.httpStatus || 0) || 0;

  if (
    classification === "RATE_LIMITED" ||
    retryReason === "provider_throttle_or_outage" ||
    httpStatus === 429
  ) {
    return true;
  }

  return false;
}

function shouldRetryTaskPlannerError(error) {
  return !isTaskPlannerRateLimitError(error);
}

function shouldShortCircuitTaskPlannerAttempt({
  attempt,
  error,
}) {
  const errorCode = (error?.errorCode || "")
    .toString()
    .trim();
  const message = (error?.message || "")
    .toString()
    .trim()
    .toLowerCase();

  if (isTaskPlannerRateLimitError(error)) {
    return true;
  }

  if (attempt < 2) {
    return false;
  }

  return (
    errorCode ===
      "PRODUCTION_AI_PLANNER_V2_TASK_SCHEMA_INVALID" ||
    errorCode ===
      "PRODUCTION_AI_PLANNER_V2_TASK_FORBIDDEN_FIELDS" ||
    errorCode ===
      "PRODUCTION_AI_PLANNER_V2_TASK_ROLE_INVALID" ||
    message ===
      "task planner did not return valid json."
  );
}

function firstDefinedString(...values) {
  for (const value of values) {
    if (typeof value !== "string") {
      continue;
    }
    const trimmed = value.trim();
    if (trimmed) {
      return trimmed;
    }
  }
  return "";
}

function normalizeTaskType(value) {
  const normalized = (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z]+/g, "_")
    .replace(/^_+|_+$/g, "");
  if (!normalized) {
    return "";
  }
  if (
    normalized === "workload" ||
    normalized === "work" ||
    normalized === "field_work" ||
    normalized === "workload_task"
  ) {
    return "workload";
  }
  if (
    normalized === "recurring" ||
    normalized === "recurrence" ||
    normalized === "repeat" ||
    normalized === "repeating" ||
    normalized === "routine"
  ) {
    return "recurring";
  }
  if (
    normalized === "event" ||
    normalized === "one_time" ||
    normalized === "milestone" ||
    normalized === "checkpoint"
  ) {
    return "event";
  }
  return normalized;
}

function normalizeOccurrence(value) {
  const normalized = (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z]+/g, "_")
    .replace(/^_+|_+$/g, "");
  if (!normalized) {
    return "";
  }
  if (
    normalized === "start" ||
    normalized === "phase_start" ||
    normalized === "beginning"
  ) {
    return "phase_start";
  }
  if (
    normalized === "middle" ||
    normalized === "mid_phase" ||
    normalized === "midpoint"
  ) {
    return "mid_phase";
  }
  if (
    normalized === "end" ||
    normalized === "phase_end" ||
    normalized === "finish"
  ) {
    return "phase_end";
  }
  return normalized;
}

function normalizeDependencies(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((entry) =>
      typeof entry === "string" ? entry.trim() : "",
    )
    .filter(Boolean);
}

function normalizeHeadcount(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return undefined;
  }
  return Math.max(1, Math.floor(numeric));
}

function normalizeWholeNumber(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return undefined;
  }
  return Math.max(0, Math.floor(numeric));
}

function normalizePositiveNumber(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return undefined;
  }
  return numeric;
}

function coerceTaskPlannerPayload({
  phaseName,
  rawContent,
}) {
  const candidates = [];
  const content = (rawContent || "").toString().trim();
  if (!content) {
    return null;
  }

  const direct = tryParseJsonValue(content);
  if (direct != null) {
    candidates.push(direct);
  }

  const fencedMatch = content.match(
    /```(?:json)?\s*([\s\S]*?)```/i,
  );
  if (fencedMatch?.[1]) {
    const fenced = tryParseJsonValue(fencedMatch[1]);
    if (fenced != null) {
      candidates.push(fenced);
    }
  }

  let objectDepth = 0;
  let objectStartIndex = -1;
  let arrayDepth = 0;
  let arrayStartIndex = -1;
  for (let index = 0; index < content.length; index += 1) {
    const char = content[index];
    if (char === "{") {
      if (objectDepth === 0) {
        objectStartIndex = index;
      }
      objectDepth += 1;
    } else if (char === "}") {
      if (objectDepth > 0) {
        objectDepth -= 1;
        if (objectDepth === 0 && objectStartIndex >= 0) {
          const parsed = tryParseJsonValue(
            content.slice(objectStartIndex, index + 1),
          );
          if (parsed != null) {
            candidates.push(parsed);
          }
        }
      }
    } else if (char === "[") {
      if (arrayDepth === 0) {
        arrayStartIndex = index;
      }
      arrayDepth += 1;
    } else if (char === "]") {
      if (arrayDepth > 0) {
        arrayDepth -= 1;
        if (arrayDepth === 0 && arrayStartIndex >= 0) {
          const parsed = tryParseJsonValue(
            content.slice(arrayStartIndex, index + 1),
          );
          if (parsed != null) {
            candidates.push(parsed);
          }
        }
      }
    }
  }

  for (const candidate of candidates) {
    const coerced = coerceTaskPlannerCandidate({
      phaseName,
      candidate,
    });
    if (coerced) {
      return coerced;
    }
  }

  return null;
}

function coerceTaskPlannerCandidate({
  phaseName,
  candidate,
}) {
  if (Array.isArray(candidate)) {
    return {
      tasks: candidate
        .map((entry, index) =>
          coerceTaskPlannerTask({
            phaseName,
            entry,
            index,
          }),
        )
        .filter(Boolean),
    };
  }

  if (!candidate || typeof candidate !== "object") {
    return null;
  }

  const taskList =
    Array.isArray(candidate.tasks) ? candidate.tasks
    : Array.isArray(candidate.phaseTasks) ? candidate.phaseTasks
    : Array.isArray(candidate.items) ? candidate.items
    : Array.isArray(candidate.payload?.tasks) ? candidate.payload.tasks
    : Array.isArray(candidate.data?.tasks) ? candidate.data.tasks
    : null;

  if (!Array.isArray(taskList)) {
    return null;
  }

  return {
    tasks: taskList
      .map((entry, index) =>
        coerceTaskPlannerTask({
          phaseName,
          entry,
          index,
        }),
      )
      .filter(Boolean),
  };
}

function coerceTaskPlannerTask({
  phaseName,
  entry,
  index,
}) {
  if (!entry || typeof entry !== "object") {
    return null;
  }

  const taskType = normalizeTaskType(
    firstDefinedString(
      entry.taskType,
      entry.type,
      entry.kind,
      entry.category,
      entry.taskKind,
    ),
  );
  const roleRequired = firstDefinedString(
    entry.roleRequired,
    entry.role,
    entry.roleKey,
    entry.ownerRole,
    entry.assigneeRole,
    entry.responsibleRole,
  )
    .toLowerCase()
    .replace(/\s+/g, "_");

  const normalized = {
    taskKey:
      firstDefinedString(
        entry.taskKey,
        entry.key,
        entry.id,
        entry.slug,
      ) || `${phaseName}_${index + 1}`,
    taskName:
      firstDefinedString(
        entry.taskName,
        entry.title,
        entry.name,
        entry.label,
      ) || `Task ${index + 1}`,
    taskType,
    roleRequired,
  };

  const requiredHeadcount = normalizeHeadcount(
    entry.requiredHeadcount ??
      entry.headcount ??
      entry.staffCount,
  );
  const unitType = firstDefinedString(
    entry.unitType,
    entry.workUnitType,
    entry.unit,
  );
  const workloadUnits = normalizePositiveNumber(
    entry.workloadUnits ??
      entry.units ??
      entry.workUnits,
  );
  const frequencyEveryDays = normalizeWholeNumber(
    entry.frequencyEveryDays ??
      entry.everyDays ??
      entry.intervalDays,
  );
  const firstOccurrenceOffsetDays =
    normalizeWholeNumber(
      entry.firstOccurrenceOffsetDays ??
        entry.offsetDays,
    );
  const occurrence = normalizeOccurrence(
    firstDefinedString(
      entry.occurrence,
      entry.anchor,
      entry.when,
    ),
  );
  const dependencies = normalizeDependencies(
    entry.dependencies ??
      entry.dependsOn ??
      entry.prerequisites,
  );

  if (requiredHeadcount != null) {
    normalized.requiredHeadcount = requiredHeadcount;
  }
  if (unitType) {
    normalized.unitType = unitType;
  }
  if (workloadUnits != null) {
    normalized.workloadUnits = workloadUnits;
  }
  if (frequencyEveryDays != null) {
    normalized.frequencyEveryDays =
      frequencyEveryDays;
  }
  if (firstOccurrenceOffsetDays != null) {
    normalized.firstOccurrenceOffsetDays =
      firstOccurrenceOffsetDays;
  }
  if (occurrence) {
    normalized.occurrence = occurrence;
  }
  if (dependencies.length > 0) {
    normalized.dependencies = dependencies;
  }

  return normalized;
}

function buildAllowedRolesPrompt(planningContext) {
  const focusedRoles =
    Array.isArray(planningContext?.focusedRoles) ?
      planningContext.focusedRoles.filter(Boolean)
    : [];
  const allowedRoles =
    focusedRoles.length > 0 ? focusedRoles : STAFF_ROLES;
  return `Use only these backend roleRequired values (snake_case): ${allowedRoles.join(", ")}.`;
}

function buildRoleHintsPrompt(planningContext) {
  const roleHints =
    (
      planningContext?.focusedRoleTaskHints &&
      typeof planningContext.focusedRoleTaskHints === "object"
    ) ?
      planningContext.focusedRoleTaskHints
    : {};
  const hintLines = Object.entries(roleHints)
    .map(([roleKey, hints]) => {
      const safeHints =
        Array.isArray(hints) ?
          hints.filter(Boolean)
        : [];
      if (!roleKey || safeHints.length === 0) {
        return "";
      }
      return `${roleKey}: ${safeHints.join(", ")}`;
    })
    .filter(Boolean);
  if (hintLines.length === 0) {
    return "";
  }
  return `Role/task fit hints: ${hintLines.join(" | ")}.`;
}

function resolveAllowedRoles(planningContext) {
  const focusedRoles =
    Array.isArray(planningContext?.focusedRoles) ?
      planningContext.focusedRoles.filter(Boolean)
    : [];
  return focusedRoles.length > 0 ?
      focusedRoles
    : STAFF_ROLES;
}

function resolveFallbackRole({
  allowedRoles,
  preferredRoles,
}) {
  for (const roleKey of preferredRoles) {
    if (allowedRoles.includes(roleKey)) {
      return roleKey;
    }
  }
  return allowedRoles[0] || "farmer";
}

function buildFallbackTasksForPhase({
  phaseName,
  planningContext,
}) {
  const allowedRoles =
    resolveAllowedRoles(planningContext);
  const safeWorkUnitType =
    (planningContext?.workUnitType || "plot")
      .toString()
      .trim() || "plot";
  const safeWorkloadUnits = Math.max(
    1,
    Number(planningContext?.totalUnits || 1),
  );
  const safeHeadcount = Math.max(
    DEFAULT_FALLBACK_HEADCOUNT,
    Number(planningContext?.minStaffPerUnit || 1),
  );
  const executionRole =
    resolveFallbackRole({
      allowedRoles,
      preferredRoles: [
        "farmer",
        "field_agent",
        "farm_manager",
        "estate_manager",
      ],
    });
  const oversightRole =
    resolveFallbackRole({
      allowedRoles,
      preferredRoles: [
        "farm_manager",
        "estate_manager",
        "field_agent",
        "farmer",
      ],
    });
  const monitoringRole =
    resolveFallbackRole({
      allowedRoles,
      preferredRoles: [
        "field_agent",
        "farm_manager",
        "farmer",
        "estate_manager",
      ],
    });

  switch (phaseName) {
    case "land_preparation":
      return [
        {
          taskKey: "land_preparation",
          taskName: "Land preparation",
          taskType: "workload",
          roleRequired: executionRole,
          requiredHeadcount: safeHeadcount,
          unitType: safeWorkUnitType,
          workloadUnits: safeWorkloadUnits,
          dependencies: [],
        },
        {
          taskKey: "supervision",
          taskName: "Preparation review",
          taskType: "event",
          roleRequired: oversightRole,
          requiredHeadcount: 1,
          occurrence: "phase_end",
          dependencies: ["land_preparation"],
        },
      ];
    case "planting":
      return [
        {
          taskKey: "planting",
          taskName: "Planting",
          taskType: "workload",
          roleRequired: executionRole,
          requiredHeadcount: safeHeadcount,
          unitType: safeWorkUnitType,
          workloadUnits: safeWorkloadUnits,
          dependencies: [],
        },
        {
          taskKey: "supervision",
          taskName: "Planting supervision",
          taskType: "event",
          roleRequired: oversightRole,
          requiredHeadcount: 1,
          occurrence: "mid_phase",
          dependencies: ["planting"],
        },
      ];
    case "vegetative_growth":
    case "early_growth":
      return [
        {
          taskKey: "crop_health_check",
          taskName: "Crop health check",
          taskType: "recurring",
          roleRequired: monitoringRole,
          requiredHeadcount: 1,
          frequencyEveryDays:
            DEFAULT_FALLBACK_RECURRENCE_DAYS,
          firstOccurrenceOffsetDays: 1,
          dependencies: [],
        },
        {
          taskKey: "weeding",
          taskName: "Field upkeep",
          taskType: "workload",
          roleRequired: executionRole,
          requiredHeadcount: safeHeadcount,
          unitType: safeWorkUnitType,
          workloadUnits: safeWorkloadUnits,
          dependencies: [],
        },
      ];
    case "flowering":
      return [
        {
          taskKey: "pest_inspection",
          taskName: "Flowering inspection",
          taskType: "recurring",
          roleRequired: monitoringRole,
          requiredHeadcount: 1,
          frequencyEveryDays:
            DEFAULT_FALLBACK_RECURRENCE_DAYS,
          firstOccurrenceOffsetDays: 1,
          dependencies: [],
        },
        {
          taskKey: "fertilizer_application",
          taskName: "Flowering nutrient review",
          taskType: "event",
          roleRequired: oversightRole,
          requiredHeadcount: 1,
          occurrence: "mid_phase",
          dependencies: [],
        },
      ];
    case "grain_fill":
      return [
        {
          taskKey: "crop_health_check",
          taskName: "Grain fill monitoring",
          taskType: "recurring",
          roleRequired: monitoringRole,
          requiredHeadcount: 1,
          frequencyEveryDays:
            DEFAULT_FALLBACK_RECURRENCE_DAYS,
          firstOccurrenceOffsetDays: 1,
          dependencies: [],
        },
        {
          taskKey: "irrigation",
          taskName: "Water management",
          taskType: "event",
          roleRequired: executionRole,
          requiredHeadcount: 1,
          occurrence: "mid_phase",
          dependencies: [],
        },
      ];
    case "harvest":
      return [
        {
          taskKey: "harvesting",
          taskName: "Harvesting",
          taskType: "workload",
          roleRequired: executionRole,
          requiredHeadcount: safeHeadcount,
          unitType: safeWorkUnitType,
          workloadUnits: safeWorkloadUnits,
          dependencies: [],
        },
        {
          taskKey: "supervision",
          taskName: "Harvest verification",
          taskType: "event",
          roleRequired: oversightRole,
          requiredHeadcount: 1,
          occurrence: "phase_end",
          dependencies: ["harvesting"],
        },
      ];
    case "post_harvest":
      return [
        {
          taskKey: "post_harvest_handling",
          taskName: "Post-harvest handling",
          taskType: "workload",
          roleRequired: executionRole,
          requiredHeadcount: safeHeadcount,
          unitType: safeWorkUnitType,
          workloadUnits: safeWorkloadUnits,
          dependencies: [],
        },
        {
          taskKey: "crop_health_check",
          taskName: "Storage readiness check",
          taskType: "event",
          roleRequired: oversightRole,
          requiredHeadcount: 1,
          occurrence: "phase_end",
          dependencies: ["post_harvest_handling"],
        },
      ];
    default:
      return [
        {
          taskKey: normalizeFallbackTaskKey(
            `${phaseName}_work`,
          ),
          taskName: "Phase execution",
          taskType: "workload",
          roleRequired: executionRole,
          requiredHeadcount: safeHeadcount,
          unitType: safeWorkUnitType,
          workloadUnits: safeWorkloadUnits,
          dependencies: [],
        },
        {
          taskKey: normalizeFallbackTaskKey(
            `${phaseName}_monitoring`,
          ),
          taskName: "Phase monitoring",
          taskType: "event",
          roleRequired: monitoringRole,
          requiredHeadcount: 1,
          occurrence: "mid_phase",
          dependencies: [],
        },
      ];
  }
}

function normalizeFallbackTaskKey(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "") || "phase_task";
}

function buildTaskPlannerPrompt({
  phaseName,
  lifecycle,
  planningContext,
  previousError = null,
  simplified = false,
}) {
  return [
    "Design semantic production tasks for one farm lifecycle phase.",
    "Return JSON only with: {\"tasks\":[...]}",
    "Tasks must be classified as workload, recurring, or event.",
    "Never include dates, workers, assignedStaffProfileIds, or schedule blocks.",
    "Allowed task fields: taskKey, taskName, taskType, roleRequired, requiredHeadcount, unitType, workloadUnits, frequencyEveryDays, firstOccurrenceOffsetDays, occurrence, dependencies.",
    "Each task must include taskKey, taskName, taskType, and roleRequired.",
    "Return 2 to 4 tasks only. Keep task names short and operational.",
    "Do not add wrappers like payload, data, explanation, notes, or markdown.",
    buildAllowedRolesPrompt(planningContext),
    buildRoleHintsPrompt(planningContext),
    simplified ?
      "Keep the task set minimal but sufficient. Use the exact field names only."
    : "Return realistic recurring and event work when biologically appropriate.",
    `Current phase: ${phaseName}`,
    `Lifecycle phases: ${lifecycle.phases.join(", ")}`,
    `Planning context: ${JSON.stringify(planningContext)}`,
    previousError ?
      `Previous validation error: ${previousError}`
    : "",
  ]
    .filter(Boolean)
    .join("\n");
}

async function generatePhaseTasks({
  phaseName,
  lifecycle,
  planningContext,
  useReasoning = false,
  context = {},
}) {
  let lastError = null;
  let attemptsMade = 0;

  if (planningContext?.forceDeterministicTaskPlanning) {
    const fallbackTasks =
      buildFallbackTasksForPhase({
        phaseName,
        planningContext,
      });
    debug(
      "PLANNER_V2_TASK: ai skipped",
      {
        intent:
          "task planner will skip AI because deterministic fallback mode is already active for this draft request",
        phaseName,
        reason:
          planningContext?.forceDeterministicTaskPlanningReason ||
          "request_scoped_deterministic_fallback",
        fallbackTaskCount:
          fallbackTasks.length,
      },
    );
    return {
      tasks: fallbackTasks,
      retryCount: 0,
      fallbackUsed: true,
      fallbackReason:
        planningContext?.forceDeterministicTaskPlanningReason ||
        "request_scoped_deterministic_fallback",
      fallbackClassification:
        "RATE_LIMITED",
      fallbackRetryReason:
        "provider_throttle_or_outage",
      aiSkipped: true,
    };
  }

  for (
    let attempt = 1;
    attempt <= MAX_TASK_PLANNER_ATTEMPTS;
    attempt += 1
  ) {
    attemptsMade = attempt;
    try {
      const response = await createAiChatCompletion({
        systemPrompt: [
          "You are a professional production planning assistant.",
          "Your job is to design production phases and tasks.",
          "Never generate calendar dates.",
          "Never assign specific workers.",
          "Never create daily schedules.",
          "Instead return production phases, tasks within phases, task classification, workload units, and task dependencies.",
          "Tasks must be one of workload, recurring, or event.",
          "Output must be valid JSON only.",
          "Do not include markdown fences or prose.",
        ].join(" "),
        messages: [
          {
            role: "user",
            content: buildTaskPlannerPrompt({
              phaseName,
              lifecycle,
              planningContext,
              previousError:
                lastError?.message || null,
              simplified: attempt === 3,
            }),
          },
        ],
        temperature:
          TASK_PLANNER_TEMPERATURE,
        maxTokens: TASK_PLANNER_MAX_TOKENS,
        useReasoning,
        context: {
          ...context,
          operation: "PlannerV2TaskPlanner",
          intent:
            "generate semantic tasks for one lifecycle phase",
          source: "planner_v2_task_planner",
        },
      });

      const parsed =
        coerceTaskPlannerPayload({
          phaseName,
          rawContent: response?.content,
        }) || extractJsonObject(response?.content);
      if (!parsed) {
        throw new Error(
          "Task planner did not return valid JSON.",
        );
      }
      const tasks = validateTaskPlan({
        phaseName,
        payload: parsed,
      });
      return {
        tasks,
        retryCount: attempt - 1,
      };
    } catch (error) {
      lastError = error;
      debug(
        "PLANNER_V2_TASK: retry",
        {
          intent:
            "task planner validation failed and will retry",
          phaseName,
          attempt,
          error: error?.message || "unknown",
          errorCode:
            error?.errorCode || null,
        },
      );
      if (
        isTaskPlannerRateLimitError(error) &&
        planningContext &&
        typeof planningContext === "object"
      ) {
        planningContext.forceDeterministicTaskPlanning =
          true;
        planningContext.forceDeterministicTaskPlanningReason =
          error?.provider_error_code ||
          error?.errorCode ||
          error?.message ||
          "rate_limited";
        debug(
          "PLANNER_V2_TASK: deterministic mode enabled",
          {
            intent:
              "task planner hit provider throttling and will use deterministic fallback tasks for the remaining phases in this request",
            phaseName,
            reason:
              planningContext.forceDeterministicTaskPlanningReason,
          },
        );
      }
      if (
        shouldShortCircuitTaskPlannerAttempt({
          attempt,
          error,
        }) &&
        planningContext &&
        typeof planningContext === "object" &&
        !planningContext.forceDeterministicTaskPlanning
      ) {
        planningContext.forceDeterministicTaskPlanning =
          true;
        planningContext.forceDeterministicTaskPlanningReason =
          error?.errorCode ||
          error?.message ||
          "task_planner_repeated_structural_failure";
        debug(
          "PLANNER_V2_TASK: deterministic mode enabled",
          {
            intent:
              "task planner will use deterministic fallback tasks for the remaining phases in this request after repeated structural failures",
            phaseName,
            reason:
              planningContext.forceDeterministicTaskPlanningReason,
          },
        );
      }
      if (
        shouldShortCircuitTaskPlannerAttempt({
          attempt,
          error,
        }) ||
        !shouldRetryTaskPlannerError(error)
      ) {
        break;
      }
    }
  }

  const fallbackTasks =
    buildFallbackTasksForPhase({
      phaseName,
      planningContext,
    });
  debug(
    "PLANNER_V2_TASK: fallback",
    {
      intent:
        "task planner exhausted retries and will use deterministic fallback tasks",
      phaseName,
      fallbackTaskCount:
        fallbackTasks.length,
      retriesAttempted:
        Math.max(0, attemptsMade - 1),
      reason:
        lastError?.errorCode ||
        lastError?.message ||
        "unknown",
    },
  );
  return {
    tasks: fallbackTasks,
    retryCount:
      Math.max(0, attemptsMade - 1),
    fallbackUsed: true,
    fallbackReason:
      lastError?.errorCode ||
      lastError?.message ||
      "unknown",
    fallbackClassification:
      lastError?.classification || null,
    fallbackRetryReason:
      lastError?.retry_reason || null,
  };
}

module.exports = {
  generatePhaseTasks,
};
