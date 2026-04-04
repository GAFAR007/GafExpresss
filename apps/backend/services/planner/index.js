/**
 * apps/backend/services/planner/index.js
 * --------------------------------------
 * WHAT:
 * - Orchestrates planner V2 lifecycle resolution, AI planning, validation, and schedule building.
 *
 * WHY:
 * - The controller needs one safe entrypoint that preserves the existing draft response contract.
 * - Central orchestration keeps planner V2 feature-flagged and isolated from the legacy path.
 *
 * HOW:
 * - Resolves lifecycle data first.
 * - Generates phases and per-phase semantic tasks through strict AI planners.
 * - Builds the dated draft schedule in the backend.
 * - Returns the same preview payload shape used by the current frontend.
 */

const debug = require("../../utils/debug");
const {
  resolveLifecycleProfile,
} = require("./lifecycleResolver");
const {
  generatePhasePlan,
} = require("./phasePlanner");
const {
  generatePhaseTasks,
} = require("./taskPlanner");
const {
  buildDraftSchedule,
  resolvePlanningWindow,
} = require("./scheduleBuilder");
const {
  validateLifecyclePlanningWindow,
} = require("./validationEngine");

const DEFAULT_WORK_UNIT_TYPE = "plot";
const MAX_ASSISTANT_DIRECTIVE_CHARS = 600;
const MAX_ROLE_HINTS_PER_ROLE = 4;

function normalizeStringList(values) {
  if (!Array.isArray(values)) {
    return [];
  }
  return Array.from(
    new Set(
      values
        .map((value) => (value == null ? "" : value.toString().trim()))
        .filter(Boolean),
    ),
  ).sort();
}

function normalizeMapOfStringLists(source) {
  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return {};
  }
  const normalizedEntries = Object.entries(source)
    .map(([key, values]) => {
      const normalizedKey = (key || "").toString().trim();
      const normalizedValues = normalizeStringList(values);
      if (!normalizedKey || normalizedValues.length === 0) {
        return null;
      }
      return [normalizedKey, normalizedValues];
    })
    .filter(Boolean)
    .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey));
  return Object.fromEntries(normalizedEntries);
}

// WHY: V2 already receives structured workload/role context, so we only keep a
// short directive excerpt instead of replaying the full frontend prose wall.
function truncateAssistantDirective(value) {
  const normalized = (value || "")
    .toString()
    .replace(/\s+/g, " ")
    .trim();
  if (!normalized) {
    return "";
  }
  return normalized.length <= MAX_ASSISTANT_DIRECTIVE_CHARS ?
      normalized
    : `${normalized.slice(0, MAX_ASSISTANT_DIRECTIVE_CHARS).trim()}...`;
}

function buildPlanningContext({
  estateAssetId,
  product,
  cropSubtype,
  workloadContext,
  capacitySummary,
  assistantPrompt,
}) {
  const focusedRoles = normalizeStringList(workloadContext?.focusedRoles);
  const focusedStaffProfileIds = normalizeStringList(
    workloadContext?.focusedStaffProfileIds,
  );
  const focusedStaffByRole = normalizeMapOfStringLists(
    workloadContext?.focusedStaffByRole,
  );
  const focusedRoleTaskHintsRaw = normalizeMapOfStringLists(
    workloadContext?.focusedRoleTaskHints,
  );
  const focusedRoleTaskHints = Object.fromEntries(
    Object.entries(focusedRoleTaskHintsRaw).map(([roleKey, hints]) => [
      roleKey,
      hints.slice(0, MAX_ROLE_HINTS_PER_ROLE),
    ]),
  );

  return {
    businessType: "Farm",
    estateAssetId: estateAssetId?.toString?.() || "",
    productId: product?._id?.toString?.() || "",
    product: product?.name || "",
    cropSubtype,
    workUnitType:
      workloadContext?.workUnitType ||
      workloadContext?.workUnitLabel ||
      DEFAULT_WORK_UNIT_TYPE,
    totalUnits:
      Number(
        workloadContext?.totalWorkUnits ||
          workloadContext?.requiredUnits ||
          workloadContext?.units ||
          0,
      ) || 0,
    minStaffPerUnit:
      Number(workloadContext?.minStaffPerUnit || 0) || 0,
    maxStaffPerUnit:
      Number(workloadContext?.maxStaffPerUnit || 0) || 0,
    expectedActivePercent:
      Number(
        workloadContext?.expectedActivePercent ||
          workloadContext?.activeStaffAvailabilityPercent ||
          0,
      ) || 0,
    focusedRoles,
    focusedStaffCount: focusedStaffProfileIds.length,
    focusedStaffCountByRole: Object.fromEntries(
      Object.entries(focusedStaffByRole).map(([roleKey, ids]) => [
        roleKey,
        ids.length,
      ]),
    ),
    focusedRoleTaskHints,
    availableStaff: Object.values(
      capacitySummary?.roles || {},
    ).reduce(
      (sum, role) =>
        sum + Number(role?.available || 0),
      0,
    ),
    assistantDirective:
      truncateAssistantDirective(assistantPrompt),
    forceDeterministicTaskPlanning: false,
    forceDeterministicTaskPlanningReason: "",
  };
}

async function generateProductionPlanDraftV2({
  businessId,
  estateAssetId,
  product,
  domainContext,
  cropSubtype = "",
  startDate = null,
  endDate = null,
  assistantPrompt = "",
  useReasoning = false,
  capacitySummary,
  schedulePolicy,
  workloadContext = {},
  context = {},
}) {
  debug(
    "PLANNER_V2: start",
    {
      intent:
        "generate planner V2 production draft without AI-authored dates",
      businessId: businessId?.toString?.() || null,
      estateAssetId:
        estateAssetId?.toString?.() || null,
      productId: product?._id?.toString?.() || null,
      productName: product?.name || "",
      domainContext,
      cropSubtype,
      hasStartDate: Boolean(startDate),
      hasEndDate: Boolean(endDate),
      hasAssistantPrompt: Boolean(assistantPrompt),
    },
  );

  const planningContext = buildPlanningContext({
    estateAssetId,
    product,
    cropSubtype,
    workloadContext,
    capacitySummary,
    assistantPrompt,
  });

  const {
    lifecycle,
    lifecycleSource,
  } = await resolveLifecycleProfile({
    businessId,
    productName: product?.name || "",
    cropSubtype,
    domainContext,
    productDescription: product?.description || "",
    useReasoning,
    context,
  });

  if (startDate && endDate) {
    const requestedDays = Math.max(
      1,
      Math.floor(
        (
          new Date(endDate).getTime() -
            new Date(startDate).getTime()
        ) / 86400000,
      ) + 1,
    );
    validateLifecyclePlanningWindow({
      lifecycle,
      requestedDays,
    });
  }

  const phasePlan = await generatePhasePlan({
    lifecycle,
    planningContext,
    useReasoning,
    context,
  });
  if (
    phasePlan?.fallbackUsed &&
    phasePlan?.fallbackClassification ===
      "RATE_LIMITED"
  ) {
    planningContext.forceDeterministicTaskPlanning =
      true;
    planningContext.forceDeterministicTaskPlanningReason =
      phasePlan?.fallbackReason ||
      "phase_planner_rate_limited";
    debug(
      "PLANNER_V2: deterministic task mode enabled",
      {
        intent:
          "phase planner was rate limited, so the remaining per-phase task generation will use deterministic fallback tasks for this request",
        businessId:
          businessId?.toString?.() || null,
        productId:
          product?._id?.toString?.() || null,
        reason:
          planningContext.forceDeterministicTaskPlanningReason,
      },
    );
  }
  const tasksByPhase = new Map();
  let totalRetryCount = Number(phasePlan.retryCount || 0);

  for (const phase of phasePlan.phases) {
    const taskPlan = await generatePhaseTasks({
      phaseName: phase.phaseName,
      lifecycle,
      planningContext,
      useReasoning,
      context,
    });
    totalRetryCount += Number(taskPlan.retryCount || 0);
    tasksByPhase.set(phase.phaseName, taskPlan.tasks);
  }

  const planningWindow = resolvePlanningWindow({
    lifecycle,
    startDate,
    endDate,
  });
  validateLifecyclePlanningWindow({
    lifecycle,
    requestedDays: planningWindow.days,
  });

  const scheduledDraft = buildDraftSchedule({
    lifecycle,
    phases: phasePlan.phases,
    tasksByPhase,
    schedulePolicy,
    capacitySummary,
    workloadContext,
    productId: product?._id?.toString?.() || "",
    productName: product?.name || "",
    estateAssetId,
    startDate,
    endDate,
  });

  const plannerMeta = {
    version: "v2",
    lifecycleSource,
    retryCount: totalRetryCount,
    scheduleSource: "backend",
  };

  const response = {
    status: "ai_draft_success",
    message:
      "Planner V2 generated a lifecycle-safe production draft.",
    summary: scheduledDraft.summary,
    schedulePolicy,
    capacity: capacitySummary,
    phases: scheduledDraft.phases,
    tasks: scheduledDraft.tasks,
    draft: {
      ...scheduledDraft.draft,
      plannerMeta,
      lifecycle,
    },
    plannerMeta,
    lifecycle,
    warnings: scheduledDraft.warnings,
    diagnostics: {
      provider: "planner_v2",
      model: null,
      requestId:
        context?.requestId ||
        context?.id ||
        "unknown",
    },
  };

  debug(
    "PLANNER_V2: success",
    {
      intent:
        "completed planner V2 draft generation",
      businessId: businessId?.toString?.() || null,
      productId: product?._id?.toString?.() || null,
      startDate: response.summary.startDate,
      endDate: response.summary.endDate,
      phaseCount: response.phases.length,
      taskCount: response.tasks.length,
      retryCount: totalRetryCount,
      lifecycleSource,
    },
  );

  return response;
}

module.exports = {
  generateProductionPlanDraftV2,
};
