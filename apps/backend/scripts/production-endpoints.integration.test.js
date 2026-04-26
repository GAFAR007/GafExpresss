/**
 * backend/scripts/production-endpoints.integration.test.js
 * --------------------------------------------------------
 * WHAT:
 * - Provides a lightweight integration harness scaffold for production endpoints.
 *
 * WHY:
 * - Stage 0 needs a shippable safety net before lifecycle behavior changes.
 * - Verifies critical production routes and feature-flag defaults without DB/network setup.
 *
 * HOW:
 * - Loads router definitions and inspects registered production route signatures.
 * - Reloads feature-flag config with controlled env values to verify default-off behavior.
 */

const path = require("node:path");
const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const debug = require("../utils/debug");

const TEST_LOG_TAG = "PRODUCTION_ENDPOINTS_STAGE0_TEST";
const FEATURE_FLAG_ENV_KEYS = [
  "PRODUCTION_ENABLE_PLAN_UNITS",
  "PRODUCTION_ENABLE_UNIT_ASSIGNMENTS",
  "PRODUCTION_ENABLE_PHASE_UNIT_COMPLETION",
  "PRODUCTION_ENABLE_PHASE_GATE",
  "PRODUCTION_ENABLE_DEVIATION_GOVERNANCE",
  "PRODUCTION_ENABLE_CONFIDENCE_SCORE",
];
const FEATURE_FLAG_ENV_TO_CONFIG_KEY = Object.freeze({
  PRODUCTION_ENABLE_PLAN_UNITS: "enablePlanUnits",
  PRODUCTION_ENABLE_UNIT_ASSIGNMENTS: "enableUnitAssignments",
  PRODUCTION_ENABLE_PHASE_UNIT_COMPLETION: "enablePhaseUnitCompletion",
  PRODUCTION_ENABLE_PHASE_GATE: "enablePhaseGate",
  PRODUCTION_ENABLE_DEVIATION_GOVERNANCE: "enableDeviationGovernance",
  PRODUCTION_ENABLE_CONFIDENCE_SCORE: "enableConfidenceScore",
});

function buildProgressiveFlagEnv({ enabledEnvKeys = [] }) {
  const enabledSet = new Set(enabledEnvKeys);
  return FEATURE_FLAG_ENV_KEYS.reduce((acc, envKey) => {
    acc[envKey] = enabledSet.has(envKey) ? "true" : "";
    return acc;
  }, {});
}

function resolvePhaseGateState({
  phaseType,
  requiredUnits,
  completedUnitCount,
}) {
  const normalizedPhaseType = (phaseType || "").toString().trim().toLowerCase();
  const normalizedRequiredUnits = Math.max(0, Number(requiredUnits || 0));
  const normalizedCompletedUnits = Math.max(0, Number(completedUnitCount || 0));
  const remainingUnits = Math.max(
    0,
    normalizedRequiredUnits - normalizedCompletedUnits,
  );
  const isLocked = normalizedPhaseType === "finite" && remainingUnits <= 0;

  return {
    remainingUnits,
    isLocked,
  };
}

function hasIndexPrefix({ schemaIndexes, prefixFields }) {
  return schemaIndexes.some(([fields]) =>
    Object.entries(prefixFields).every(
      ([key, value]) => fields?.[key] === value,
    ),
  );
}

function collectProductionRouteSignatures(router) {
  const stack = Array.isArray(router?.stack) ? router.stack : [];
  const signatures = [];

  // WHY: Route stack inspection is enough for Stage 0 coverage and keeps tests fast.
  stack.forEach((layer) => {
    const route = layer?.route;
    if (!route) {
      return;
    }
    const routePath = typeof route.path === "string" ? route.path : "";
    if (!routePath.startsWith("/production")) {
      return;
    }
    const routeMethods = Object.entries(route.methods || {})
      .filter(([, enabled]) => enabled)
      .map(([method]) => method.toUpperCase());
    routeMethods.forEach((method) => {
      signatures.push(`${method} ${routePath}`);
    });
  });

  return signatures.sort();
}

function loadFeatureFlagsWithEnv({ forcedEnv = {} }) {
  const modulePath = require.resolve("../config/production_feature_flags");
  const previousValues = {};
  FEATURE_FLAG_ENV_KEYS.forEach((key) => {
    previousValues[key] = process.env[key];
    // WHY: Force explicit env values so default behavior can be asserted deterministically.
    process.env[key] = Object.prototype.hasOwnProperty.call(forcedEnv, key)
      ? forcedEnv[key]
      : "";
  });

  const previousCache = require.cache[modulePath];
  delete require.cache[modulePath];

  try {
    return require("../config/production_feature_flags");
  } finally {
    if (previousCache) {
      require.cache[modulePath] = previousCache;
    } else {
      delete require.cache[modulePath];
    }
    FEATURE_FLAG_ENV_KEYS.forEach((key) => {
      if (typeof previousValues[key] === "undefined") {
        delete process.env[key];
        return;
      }
      process.env[key] = previousValues[key];
    });
  }
}

test("stage0 production lifecycle feature flags default to false when env is unset", () => {
  debug(TEST_LOG_TAG, "Checking default-off feature flags");
  const { PRODUCTION_FEATURE_FLAGS } = loadFeatureFlagsWithEnv({
    forcedEnv: {},
  });

  assert.deepEqual(PRODUCTION_FEATURE_FLAGS, {
    enableAiPlannerV2: true,
    enablePlanUnits: false,
    enableUnitAssignments: false,
    enablePhaseUnitCompletion: false,
    enablePhaseGate: false,
    enableDeviationGovernance: false,
    enableConfidenceScore: false,
  });
});

test("business routes expose core production lifecycle endpoints", () => {
  debug(TEST_LOG_TAG, "Checking production endpoint scaffold");
  const businessRoutes = require("../routes/business.routes");
  const routeSignatures = collectProductionRouteSignatures(businessRoutes);

  const requiredRoutes = [
    "POST /production/plans/assistant-turn",
    "POST /production/plans/ai-draft",
    "POST /production/plans",
    "GET /production/confidence/portfolio",
    "GET /production/plans/:planId/confidence",
    "GET /production/plans/:planId/units",
    "GET /production/plans/:planId/deviation-alerts",
    "POST /production/plans/:planId/tasks",
    "DELETE /production/tasks/:taskId",
    "POST /production/plans/:planId/deviation-alerts/:alertId/accept-variance",
    "POST /production/plans/:planId/deviation-alerts/:alertId/replan-unit",
    "PATCH /production/tasks/:id/status",
    "POST /production/tasks/:taskId/progress",
    "POST /production/task-progress/:id/approve",
  ];

  requiredRoutes.forEach((signature) => {
    assert.equal(
      routeSignatures.includes(signature),
      true,
      `Missing required production route: ${signature}`,
    );
  });
});

test("phase day task creation can explicitly extend plan and phase windows", () => {
  debug(TEST_LOG_TAG, "Checking phase day extension task wiring");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.match(
    controllerSource,
    /allowWindowExtension\s*=\s*req\.body\?\.allowWindowExtension\s*===\s*true/,
    "createProductionPlanTask should require an explicit allowWindowExtension flag",
  );
  assert.match(
    controllerSource,
    /!allowWindowExtension\s*&&\s*\(endsAfterPlanWindow\s*\|\|\s*endsAfterPhaseWindow\)/,
    "outside-window task creation should remain blocked unless extension is explicit",
  );
  assert.match(
    controllerSource,
    /ProductionPhase\.updateOne\([\s\S]*\$max:\s*\{[\s\S]*endDate:\s*dueDate/,
    "phase endDate should extend with $max when the new task lands after the phase",
  );
  assert.match(
    controllerSource,
    /ProductionPlan\.updateOne\([\s\S]*\$max:\s*\{[\s\S]*endDate:\s*dueDate/,
    "plan endDate should extend with $max when the new task lands after the plan",
  );
});

test("PlanUnit schema enforces unique unit index within each plan", () => {
  debug(TEST_LOG_TAG, "Checking PlanUnit schema indexes");
  const PlanUnit = require("../models/PlanUnit");
  const schemaIndexes = PlanUnit.schema.indexes();
  const hasUniquePlanUnitIndex = schemaIndexes.some(
    ([fields, options]) =>
      fields?.planId === 1 &&
      fields?.unitIndex === 1 &&
      options?.unique === true,
  );

  assert.equal(
    hasUniquePlanUnitIndex,
    true,
    "PlanUnit unique index (planId, unitIndex) is missing",
  );
});

test("ProductionTask schema supports indexed assigned unit ids", () => {
  debug(TEST_LOG_TAG, "Checking ProductionTask unit assignment schema indexes");
  const ProductionTask = require("../models/ProductionTask");
  const assignedUnitPath = ProductionTask.schema.path("assignedUnitIds");
  assert.ok(assignedUnitPath, "ProductionTask.assignedUnitIds path is missing");

  const schemaIndexes = ProductionTask.schema.indexes();
  const hasAssignmentIndex = schemaIndexes.some(
    ([fields]) =>
      fields?.planId === 1 &&
      fields?.phaseId === 1 &&
      fields?.assignedUnitIds === 1,
  );

  assert.equal(
    hasAssignmentIndex,
    true,
    "ProductionTask index (planId, phaseId, assignedUnitIds) is missing",
  );
});

test("ProductionPhaseUnitCompletion schema is idempotent per phase unit", () => {
  debug(TEST_LOG_TAG, "Checking ProductionPhaseUnitCompletion schema indexes");
  const ProductionPhaseUnitCompletion = require("../models/ProductionPhaseUnitCompletion");
  const schemaIndexes = ProductionPhaseUnitCompletion.schema.indexes();
  const hasUniquePhaseUnitIndex = schemaIndexes.some(
    ([fields, options]) =>
      fields?.planId === 1 &&
      fields?.phaseId === 1 &&
      fields?.unitId === 1 &&
      options?.unique === true,
  );

  assert.equal(
    hasUniquePhaseUnitIndex,
    true,
    "ProductionPhaseUnitCompletion unique index (planId, phaseId, unitId) is missing",
  );
});

test("ProductionPhase schema supports explicit phase gate fields", () => {
  debug(TEST_LOG_TAG, "Checking ProductionPhase phase gate schema fields");
  const ProductionPhase = require("../models/ProductionPhase");
  const phaseTypePath = ProductionPhase.schema.path("phaseType");
  const requiredUnitsPath = ProductionPhase.schema.path("requiredUnits");
  const minRatePerFarmerHourPath = ProductionPhase.schema.path(
    "minRatePerFarmerHour",
  );
  const targetRatePerFarmerHourPath = ProductionPhase.schema.path(
    "targetRatePerFarmerHour",
  );
  const plannedHoursPerDayPath =
    ProductionPhase.schema.path("plannedHoursPerDay");
  const biologicalMinDaysPath =
    ProductionPhase.schema.path("biologicalMinDays");

  assert.ok(phaseTypePath, "ProductionPhase.phaseType path is missing");
  assert.deepEqual(
    phaseTypePath?.enumValues || [],
    ["finite", "monitoring"],
    "ProductionPhase.phaseType enum values are invalid",
  );
  assert.equal(
    phaseTypePath?.defaultValue,
    "finite",
    "ProductionPhase.phaseType default should be finite",
  );

  assert.ok(requiredUnitsPath, "ProductionPhase.requiredUnits path is missing");
  assert.equal(
    requiredUnitsPath?.defaultValue,
    0,
    "ProductionPhase.requiredUnits default should be 0",
  );
  assert.ok(
    minRatePerFarmerHourPath,
    "ProductionPhase.minRatePerFarmerHour path is missing",
  );
  assert.equal(
    minRatePerFarmerHourPath?.defaultValue,
    0.1,
    "ProductionPhase.minRatePerFarmerHour default should be 0.1",
  );
  assert.ok(
    targetRatePerFarmerHourPath,
    "ProductionPhase.targetRatePerFarmerHour path is missing",
  );
  assert.equal(
    targetRatePerFarmerHourPath?.defaultValue,
    0.2,
    "ProductionPhase.targetRatePerFarmerHour default should be 0.2",
  );
  assert.ok(
    plannedHoursPerDayPath,
    "ProductionPhase.plannedHoursPerDay path is missing",
  );
  assert.equal(
    plannedHoursPerDayPath?.defaultValue,
    3,
    "ProductionPhase.plannedHoursPerDay default should be 3",
  );
  assert.ok(
    biologicalMinDaysPath,
    "ProductionPhase.biologicalMinDays path is missing",
  );
  assert.equal(
    biologicalMinDaysPath?.defaultValue,
    0,
    "ProductionPhase.biologicalMinDays default should be 0",
  );
});

test("ProductionUnitTaskSchedule schema supports per-unit timing rows", () => {
  debug(
    TEST_LOG_TAG,
    "Checking ProductionUnitTaskSchedule schema indexes and enums",
  );
  const ProductionUnitTaskSchedule = require("../models/ProductionUnitTaskSchedule");
  const timingModePath = ProductionUnitTaskSchedule.schema.path("timingMode");
  const referenceEventPath =
    ProductionUnitTaskSchedule.schema.path("referenceEvent");
  assert.ok(
    timingModePath,
    "ProductionUnitTaskSchedule.timingMode path is missing",
  );
  assert.deepEqual(
    timingModePath?.enumValues || [],
    ["absolute", "relative"],
    "ProductionUnitTaskSchedule.timingMode enum values are invalid",
  );
  assert.ok(
    referenceEventPath,
    "ProductionUnitTaskSchedule.referenceEvent path is missing",
  );
  assert.deepEqual(
    referenceEventPath?.enumValues || [],
    ["phase_start", "phase_completion"],
    "ProductionUnitTaskSchedule.referenceEvent enum values are invalid",
  );

  const schemaIndexes = ProductionUnitTaskSchedule.schema.indexes();
  const hasUniqueTaskUnitIndex = schemaIndexes.some(
    ([fields, options]) =>
      fields?.planId === 1 &&
      fields?.taskId === 1 &&
      fields?.unitId === 1 &&
      options?.unique === true,
  );
  assert.equal(
    hasUniqueTaskUnitIndex,
    true,
    "ProductionUnitTaskSchedule unique index (planId, taskId, unitId) is missing",
  );
});

test("ProductionUnitScheduleWarning schema supports manager review warnings", () => {
  debug(
    TEST_LOG_TAG,
    "Checking ProductionUnitScheduleWarning schema indexes and enums",
  );
  const ProductionUnitScheduleWarning = require("../models/ProductionUnitScheduleWarning");
  const warningTypePath =
    ProductionUnitScheduleWarning.schema.path("warningType");
  const severityPath = ProductionUnitScheduleWarning.schema.path("severity");
  assert.ok(
    warningTypePath,
    "ProductionUnitScheduleWarning.warningType path is missing",
  );
  assert.deepEqual(
    warningTypePath?.enumValues || [],
    ["MISSING_UNIT_CONTEXT", "SHIFT_CONFLICT"],
    "ProductionUnitScheduleWarning.warningType enum values are invalid",
  );
  assert.ok(
    severityPath,
    "ProductionUnitScheduleWarning.severity path is missing",
  );
  assert.deepEqual(
    severityPath?.enumValues || [],
    ["info", "warning"],
    "ProductionUnitScheduleWarning.severity enum values are invalid",
  );

  const schemaIndexes = ProductionUnitScheduleWarning.schema.indexes();
  const hasPlanUnitCreatedAtIndex = schemaIndexes.some(
    ([fields]) =>
      fields?.planId === 1 && fields?.unitId === 1 && fields?.createdAt === -1,
  );
  assert.equal(
    hasPlanUnitCreatedAtIndex,
    true,
    "ProductionUnitScheduleWarning index (planId, unitId, createdAt) is missing",
  );
});

test("TaskProgress schema supports unit-scoped daily records", () => {
  debug(TEST_LOG_TAG, "Checking TaskProgress unit-scoped unique index");
  const TaskProgress = require("../models/TaskProgress");
  const unitIdPath = TaskProgress.schema.path("unitId");
  const expectedPlotUnitsPath = TaskProgress.schema.path("expectedPlotUnits");
  const actualPlotUnitsPath = TaskProgress.schema.path("actualPlotUnits");
  const entryIndexPath = TaskProgress.schema.path("entryIndex");
  assert.ok(unitIdPath, "TaskProgress.unitId path is missing");
  assert.ok(
    expectedPlotUnitsPath,
    "TaskProgress.expectedPlotUnits path is missing",
  );
  assert.ok(
    actualPlotUnitsPath,
    "TaskProgress.actualPlotUnits path is missing",
  );
  assert.ok(entryIndexPath, "TaskProgress.entryIndex path is missing");
  assert.equal(
    expectedPlotUnitsPath?.instance,
    "Number",
    "TaskProgress.expectedPlotUnits must be numeric",
  );
  assert.equal(
    actualPlotUnitsPath?.instance,
    "Number",
    "TaskProgress.actualPlotUnits must be numeric",
  );

  const schemaIndexes = TaskProgress.schema.indexes();
  const hasTaskStaffWorkDateUnitIndex = schemaIndexes.some(
    ([fields, options]) =>
      fields?.taskId === 1 &&
      fields?.staffId === 1 &&
      fields?.workDate === 1 &&
      fields?.unitId === 1 &&
      fields?.entryIndex === 1 &&
      options?.unique === true,
  );
  assert.equal(
    hasTaskStaffWorkDateUnitIndex,
    true,
    "TaskProgress unique index (taskId, staffId, workDate, unitId, entryIndex) is missing",
  );
});

test("ProductionDeviationGovernanceConfig schema supports phase-order thresholds", () => {
  debug(
    TEST_LOG_TAG,
    "Checking ProductionDeviationGovernanceConfig schema fields and indexes",
  );
  const ProductionDeviationGovernanceConfig = require("../models/ProductionDeviationGovernanceConfig");
  const phaseThresholdByOrderPath =
    ProductionDeviationGovernanceConfig.schema.path("phaseThresholdByOrder");
  assert.ok(
    phaseThresholdByOrderPath,
    "ProductionDeviationGovernanceConfig.phaseThresholdByOrder path is missing",
  );

  const schemaIndexes = ProductionDeviationGovernanceConfig.schema.indexes();
  const hasUniquePlanIdIndex = schemaIndexes.some(
    ([fields, options]) => fields?.planId === 1 && options?.unique === true,
  );
  const hasTemplateLookupIndex = schemaIndexes.some(
    ([fields, options]) =>
      fields?.businessId === 1 &&
      fields?.cropTemplateId === 1 &&
      options?.sparse === true,
  );
  assert.equal(
    hasUniquePlanIdIndex,
    true,
    "ProductionDeviationGovernanceConfig unique index on planId is missing",
  );
  assert.equal(
    hasTemplateLookupIndex,
    true,
    "ProductionDeviationGovernanceConfig index (businessId, cropTemplateId) is missing",
  );
});

test("LifecycleDeviationAlert schema supports governance statuses and plan-unit status index", () => {
  debug(
    TEST_LOG_TAG,
    "Checking LifecycleDeviationAlert schema enums and indexes",
  );
  const LifecycleDeviationAlert = require("../models/LifecycleDeviationAlert");
  const statusPath = LifecycleDeviationAlert.schema.path("status");
  assert.ok(statusPath, "LifecycleDeviationAlert.status path is missing");
  assert.deepEqual(
    statusPath?.enumValues || [],
    ["open", "variance_accepted", "replanned"],
    "LifecycleDeviationAlert.status enum values are invalid",
  );

  const schemaIndexes = LifecycleDeviationAlert.schema.indexes();
  const hasPlanUnitStatusIndex = schemaIndexes.some(
    ([fields]) =>
      fields?.planId === 1 &&
      fields?.unitId === 1 &&
      fields?.status === 1 &&
      fields?.createdAt === -1,
  );
  assert.equal(
    hasPlanUnitStatusIndex,
    true,
    "LifecycleDeviationAlert index (planId, unitId, status, createdAt) is missing",
  );
});

test("ProductionPlan schema supports deterministic confidence fields", () => {
  debug(TEST_LOG_TAG, "Checking ProductionPlan confidence schema fields");
  const ProductionPlan = require("../models/ProductionPlan");
  const baselineScorePath = ProductionPlan.schema.path(
    "baselineConfidenceScore",
  );
  const currentScorePath = ProductionPlan.schema.path("currentConfidenceScore");
  const baselineBreakdownPath = ProductionPlan.schema.path(
    "baselineConfidenceBreakdown",
  );
  const currentBreakdownPath = ProductionPlan.schema.path(
    "currentConfidenceBreakdown",
  );
  const lastTriggerPath = ProductionPlan.schema.path("confidenceLastTrigger");
  const recomputeCountPath = ProductionPlan.schema.path(
    "confidenceRecomputeCount",
  );

  assert.ok(
    baselineScorePath,
    "ProductionPlan.baselineConfidenceScore path is missing",
  );
  assert.equal(
    baselineScorePath?.options?.min,
    0,
    "baselineConfidenceScore min should be 0",
  );
  assert.equal(
    baselineScorePath?.options?.max,
    1,
    "baselineConfidenceScore max should be 1",
  );
  assert.ok(
    currentScorePath,
    "ProductionPlan.currentConfidenceScore path is missing",
  );
  assert.equal(
    currentScorePath?.options?.min,
    0,
    "currentConfidenceScore min should be 0",
  );
  assert.equal(
    currentScorePath?.options?.max,
    1,
    "currentConfidenceScore max should be 1",
  );
  assert.ok(
    baselineBreakdownPath,
    "ProductionPlan.baselineConfidenceBreakdown path is missing",
  );
  assert.ok(
    currentBreakdownPath,
    "ProductionPlan.currentConfidenceBreakdown path is missing",
  );
  assert.ok(
    lastTriggerPath,
    "ProductionPlan.confidenceLastTrigger path is missing",
  );
  assert.ok(
    recomputeCountPath,
    "ProductionPlan.confidenceRecomputeCount path is missing",
  );
  assert.equal(
    recomputeCountPath?.defaultValue,
    0,
    "confidenceRecomputeCount default should be 0",
  );
});

test("production confidence service exposes deterministic trigger constants", () => {
  debug(TEST_LOG_TAG, "Checking production confidence service exports");
  const confidenceService = require("../services/production_confidence.service");

  assert.ok(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS,
    "CONFIDENCE_RECOMPUTE_TRIGGERS export is missing",
  );
  assert.equal(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS.SCHEDULE_COMMIT,
    "schedule_commit",
    "SCHEDULE_COMMIT trigger constant is invalid",
  );
  assert.equal(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS.UNIT_COMPLETION_INSERT,
    "unit_completion_insert",
    "UNIT_COMPLETION_INSERT trigger constant is invalid",
  );
  assert.equal(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS.DEVIATION_ALERT_TRIGGERED,
    "deviation_alert_triggered",
    "DEVIATION_ALERT_TRIGGERED trigger constant is invalid",
  );
  assert.equal(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS.VARIANCE_ACCEPTED,
    "variance_accepted",
    "VARIANCE_ACCEPTED trigger constant is invalid",
  );
  assert.equal(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS.STAFF_AVAILABILITY_CHANGED,
    "staff_availability_changed",
    "STAFF_AVAILABILITY_CHANGED trigger constant is invalid",
  );
  assert.equal(
    confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS.PLAN_WINDOW_CHANGED,
    "plan_window_changed",
    "PLAN_WINDOW_CHANGED trigger constant is invalid",
  );
  assert.equal(
    Object.keys(confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS).length,
    6,
    "Confidence trigger set should remain fixed at six deterministic triggers",
  );
  assert.deepEqual(
    confidenceService.CONFIDENCE_ACTIVE_PLAN_STATUSES,
    ["draft", "active", "paused"],
    "CONFIDENCE_ACTIVE_PLAN_STATUSES should remain deterministic",
  );
});

test("stage7 confidence visibility remains manager-only across confidence endpoints and plan payload shaping", () => {
  debug(
    TEST_LOG_TAG,
    "Checking stage7 manager-only confidence visibility guardrails",
  );
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /function\s+canViewConfidenceScores\s*\(/.test(controllerSource),
    true,
    "Missing canViewConfidenceScores guard helper",
  );
  assert.equal(
    /getProductionPlanConfidence[\s\S]*!canViewConfidenceScores[\s\S]*CONFIDENCE_FORBIDDEN/.test(
      controllerSource,
    ),
    true,
    "Plan confidence endpoint must enforce manager-only visibility",
  );
  assert.equal(
    /getProductionPortfolioConfidence[\s\S]*!canViewConfidenceScores[\s\S]*CONFIDENCE_FORBIDDEN/.test(
      controllerSource,
    ),
    true,
    "Portfolio confidence endpoint must enforce manager-only visibility",
  );
  assert.equal(
    /stripPlanConfidenceFields/.test(controllerSource),
    true,
    "Plan list/detail responses must support confidence field stripping for non-manager viewers",
  );
  assert.equal(
    /const\s+canViewTeamKpis\s*=\s*canAssignProductionTasks\s*\(/.test(
      controllerSource,
    ),
    true,
    "Plan detail must derive manager-scope KPI visibility from role guard",
  );
  assert.equal(
    /actor\.role\s*===\s*"staff"\s*&&\s*!canViewTeamKpis/.test(
      controllerSource,
    ),
    true,
    "Non-manager staff path must be explicitly gated before returning KPI payloads",
  );
  assert.equal(
    /visibleKpis\s*=\s*null/.test(controllerSource) &&
      /visibleStaffProgressScores\s*=\s*[\s\S]*filter\s*\(/.test(
        controllerSource,
      ),
    true,
    "Non-manager staff should receive only personal KPI rows, not plan-level KPI aggregates",
  );
});

test("stage8 feature flags support progressive enablement without coupling", () => {
  debug(TEST_LOG_TAG, "Checking progressive feature-flag enablement");

  FEATURE_FLAG_ENV_KEYS.forEach((envKeyToEnable) => {
    const { PRODUCTION_FEATURE_FLAGS } = loadFeatureFlagsWithEnv({
      forcedEnv: buildProgressiveFlagEnv({
        enabledEnvKeys: [envKeyToEnable],
      }),
    });

    Object.entries(FEATURE_FLAG_ENV_TO_CONFIG_KEY).forEach(
      ([envKey, flagKey]) => {
        assert.equal(
          PRODUCTION_FEATURE_FLAGS[flagKey],
          envKey === envKeyToEnable,
          `Flag coupling detected: ${envKeyToEnable} should not toggle ${flagKey}`,
        );
      },
    );
  });

  const { PRODUCTION_FEATURE_FLAGS: allEnabledFlags } = loadFeatureFlagsWithEnv(
    {
      forcedEnv: buildProgressiveFlagEnv({
        enabledEnvKeys: FEATURE_FLAG_ENV_KEYS,
      }),
    },
  );
  Object.values(FEATURE_FLAG_ENV_TO_CONFIG_KEY).forEach((flagKey) => {
    assert.equal(
      allEnabledFlags[flagKey],
      true,
      `Expected ${flagKey} to be enabled when all feature flags are on`,
    );
  });
});

test("stage8 phase gate contract locks finite phases only after required units complete", () => {
  debug(TEST_LOG_TAG, "Checking phase gate finite-lock contract");

  const finiteLockedState = resolvePhaseGateState({
    phaseType: "finite",
    requiredUnits: 8,
    completedUnitCount: 8,
  });
  assert.equal(
    finiteLockedState.isLocked,
    true,
    "Finite phase should lock when completed units reach required units",
  );
  assert.equal(
    finiteLockedState.remainingUnits,
    0,
    "Remaining units should be zero after finite phase completion",
  );

  const finiteOpenState = resolvePhaseGateState({
    phaseType: "finite",
    requiredUnits: 8,
    completedUnitCount: 5,
  });
  assert.equal(
    finiteOpenState.isLocked,
    false,
    "Finite phase should remain schedulable while remaining units exist",
  );
  assert.equal(
    finiteOpenState.remainingUnits,
    3,
    "Finite phase remaining units should track required-completed",
  );
});

test("stage8 monitoring phases remain lifecycle-neutral even when completion counts are high", () => {
  debug(TEST_LOG_TAG, "Checking monitoring phase lifecycle-neutral contract");

  const monitoringState = resolvePhaseGateState({
    phaseType: "monitoring",
    requiredUnits: 6,
    completedUnitCount: 6,
  });
  assert.equal(
    monitoringState.isLocked,
    false,
    "Monitoring phases must never lock scheduling",
  );
  assert.equal(
    monitoringState.remainingUnits,
    0,
    "Monitoring phase remaining units should be derived without imposing locks",
  );
});

test("stage8 phase gate snapshot maps persisted phases by planId+phaseOrder and trims locked draft tasks", () => {
  debug(
    TEST_LOG_TAG,
    "Checking phase-order mapping and locked-phase draft trim contract",
  );
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /const\s+persistedByOrder\s*=\s*new\s+Map/.test(controllerSource),
    true,
    "Phase gate snapshot must materialize a persisted phase-order map",
  );
  assert.equal(
    /persistedByOrder\.get\(\s*phaseOrder\s*\)/.test(controllerSource),
    true,
    "Phase gate snapshot must resolve persisted phases deterministically by phaseOrder",
  );
  assert.equal(
    /ProductionPhase\.find\(\s*\{\s*planId:\s*persistedPlan\._id/.test(
      controllerSource,
    ),
    true,
    "Phase gate snapshot must be scoped by persisted planId before phase-order mapping",
  );
  assert.equal(
    /const\s+shouldLockFinitePhase\s*=\s*[\s\S]*phaseType\s*===\s*PRODUCTION_PHASE_TYPE_FINITE[\s\S]*remainingUnits\s*<=\s*0/.test(
      controllerSource,
    ),
    true,
    "Finite phases must lock only when remaining units are exhausted",
  );
  assert.equal(
    /if\s*\(\s*shouldLockFinitePhase\s*\)[\s\S]*phaseTasks\s*=\s*\[\s*\]/.test(
      controllerSource,
    ),
    true,
    "Locked finite phases must drop draft tasks before scheduler/rank logic runs",
  );
  assert.equal(
    /PHASE_GATE_WARNING_LOCKED_MESSAGE[\s\S]*Phase locked - unit budget exhausted/.test(
      controllerSource,
    ),
    true,
    "Phase lock warning text must remain explicit for manager preview",
  );
  assert.equal(
    /PHASE_GATE_WARNING_CAPPED_MESSAGE[\s\S]*Draft capped to remaining units/.test(
      controllerSource,
    ),
    true,
    "Draft cap warning text must remain explicit for manager preview",
  );
});

test("stage8 completion count performance guard relies on planId+phaseId index prefix", () => {
  debug(TEST_LOG_TAG, "Checking completion count query index guard");
  const ProductionPhaseUnitCompletion = require("../models/ProductionPhaseUnitCompletion");
  const schemaIndexes = ProductionPhaseUnitCompletion.schema.indexes();

  assert.equal(
    hasIndexPrefix({
      schemaIndexes,
      prefixFields: {
        planId: 1,
        phaseId: 1,
      },
    }),
    true,
    "Completed-unit count queries require planId+phaseId index coverage",
  );
});

test("stage8 duplicate completion writes remain idempotent via unique phase-unit index", () => {
  debug(TEST_LOG_TAG, "Checking duplicate completion idempotency contract");
  const ProductionPhaseUnitCompletion = require("../models/ProductionPhaseUnitCompletion");
  const schemaIndexes = ProductionPhaseUnitCompletion.schema.indexes();
  const idempotentUniqueIndex = schemaIndexes.some(
    ([fields, options]) =>
      fields?.planId === 1 &&
      fields?.phaseId === 1 &&
      fields?.unitId === 1 &&
      options?.unique === true,
  );

  assert.equal(
    idempotentUniqueIndex,
    true,
    "Duplicate completion writes must remain idempotent per (planId, phaseId, unitId)",
  );
});

test("stage8 approval-time phase unit completion sync is wired and flag-gated", () => {
  debug(TEST_LOG_TAG, "Checking phase unit completion write-path wiring");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /function\s+syncPhaseUnitCompletionsForApprovedProgress\s*\(/.test(
      controllerSource,
    ),
    true,
    "Missing syncPhaseUnitCompletionsForApprovedProgress helper",
  );
  assert.equal(
    /enablePhaseUnitCompletion/.test(controllerSource),
    true,
    "Phase unit completion sync must be protected by enablePhaseUnitCompletion flag",
  );
  assert.equal(
    /ProductionPhaseUnitCompletion\.bulkWrite\s*\(/.test(controllerSource),
    true,
    "Phase unit completion helper must persist idempotent writes via bulk upsert",
  );
  assert.equal(
    /syncPhaseUnitCompletionsForApprovedProgress\s*\(\s*\{[\s\S]*approveTaskProgress/.test(
      controllerSource,
    ),
    true,
    "approveTaskProgress must invoke phase-unit completion sync",
  );
  assert.equal(
    /task\?\.\s*status\s*!==\s*PRODUCTION_TASK_STATUS_DONE/.test(
      controllerSource,
    ),
    true,
    "Phase unit completion sync must enforce done-task boundary before writing completions",
  );
  assert.equal(
    /let\s+scopedAssignedUnitIds\s*=\s*\[\s*\.\.\.taskAssignedUnitIds\s*,?\s*\]/.test(
      controllerSource,
    ),
    true,
    "Phase unit completion sync must fan-out idempotent writes across all task-assigned units",
  );
  assert.equal(
    /approved_progress_has_no_actual_work/.test(controllerSource),
    false,
    "Phase unit completion sync must not block completion writes on missing actualPlotUnits once approval+done boundary is reached",
  );
  assert.equal(
    /progress_unit_context_missing/.test(controllerSource),
    false,
    "Phase unit completion sync must not require progress.unitId when task-level completion truth is approved",
  );
  assert.equal(
    /function\s+getCompletedUnitCount\s*\(/.test(controllerSource),
    true,
    "Missing getCompletedUnitCount helper",
  );
  assert.equal(
    /function\s+getCompletedUnits\s*\(/.test(controllerSource),
    true,
    "Missing getCompletedUnits helper",
  );
  assert.equal(
    /phaseUnitProgress/.test(controllerSource),
    true,
    "Plan detail response should expose phaseUnitProgress for manager lifecycle visibility",
  );
});

test("stage8 deviation governance contract supports alert trigger status and unit freeze state", () => {
  debug(
    TEST_LOG_TAG,
    "Checking deviation governance trigger + freeze contract",
  );

  const PlanUnit = require("../models/PlanUnit");
  const LifecycleDeviationAlert = require("../models/LifecycleDeviationAlert");

  const deviationLockedPath = PlanUnit.schema.path("deviationLocked");
  assert.ok(deviationLockedPath, "PlanUnit.deviationLocked path is missing");
  assert.equal(
    deviationLockedPath?.defaultValue,
    false,
    "PlanUnit.deviationLocked must default to false before alert trigger",
  );

  const statusPath = LifecycleDeviationAlert.schema.path("status");
  assert.ok(statusPath, "LifecycleDeviationAlert.status path is missing");
  assert.equal(
    statusPath?.defaultValue,
    "open",
    "LifecycleDeviationAlert default status must remain open at trigger time",
  );
  assert.equal(
    Array.isArray(
      LifecycleDeviationAlert.LIFECYCLE_DEVIATION_ALERT_ACTION_TYPES,
    ) &&
      LifecycleDeviationAlert.LIFECYCLE_DEVIATION_ALERT_ACTION_TYPES.includes(
        "triggered",
      ),
    true,
    "LifecycleDeviationAlert action types must include triggered",
  );
});

test("stage8 deviation governance runtime wiring seeds config, evaluates threshold breaches, and applies manual replan writes", () => {
  debug(TEST_LOG_TAG, "Checking deviation governance runtime wiring");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /deviationGovernanceConfigSeed\s*=\s*await\s*loadOrCreateDeviationGovernanceConfigForPlan\s*\(/.test(
      controllerSource,
    ),
    true,
    "createProductionPlan must seed/load plan-scoped deviation governance config",
  );
  assert.equal(
    /deviationGovernance\s*=\s*await\s*evaluateDeviationGovernanceAfterUnitShift\s*\(/.test(
      controllerSource,
    ),
    true,
    "shiftUnitScheduleForApprovedProgress must evaluate deviation thresholds after approved shifts",
  );
  assert.equal(
    /await\s+ProductionUnitTaskSchedule\.bulkWrite\s*\(\s*replanWriteOps/.test(
      controllerSource,
    ),
    true,
    "replanProductionPlanDeviationUnit must persist manual task adjustments to unit schedule rows",
  );
  assert.equal(
    /DEVIATION_REPLAN_TASKS_INVALID/.test(controllerSource),
    true,
    "replanProductionPlanDeviationUnit must validate taskAdjustments payload shape",
  );
});

test("stage8 confidence recompute remains trigger-driven through controller wrappers", () => {
  debug(
    TEST_LOG_TAG,
    "Checking confidence recompute trigger-only controller wiring",
  );

  const confidenceService = require("../services/production_confidence.service");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  const directPlanRecomputeCalls = [
    ...controllerSource.matchAll(/recomputePlanConfidenceSnapshot\s*\(/g),
  ].length;
  const directScopedRecomputeCalls = [
    ...controllerSource.matchAll(/recomputeConfidenceForActivePlans\s*\(/g),
  ].length;
  assert.equal(
    directPlanRecomputeCalls,
    1,
    "recomputePlanConfidenceSnapshot should remain centralized in one controller wrapper",
  );
  assert.equal(
    directScopedRecomputeCalls,
    1,
    "recomputeConfidenceForActivePlans should remain centralized in one controller wrapper",
  );

  const usedTriggerNames = [
    ...controllerSource.matchAll(/CONFIDENCE_RECOMPUTE_TRIGGERS\.([A-Z_]+)/g),
  ].map((match) => match[1]);
  const allowedTriggerNames = new Set(
    Object.keys(confidenceService.CONFIDENCE_RECOMPUTE_TRIGGERS),
  );
  usedTriggerNames.forEach((triggerName) => {
    assert.equal(
      allowedTriggerNames.has(triggerName),
      true,
      `Controller references unknown confidence trigger constant: ${triggerName}`,
    );
  });
});

test("stage5 unit delay propagation is wired to approval and manager detail insights", () => {
  debug(TEST_LOG_TAG, "Checking stage5 per-unit delay propagation wiring");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /function\s+seedUnitTaskScheduleRows\s*\(/.test(controllerSource),
    true,
    "Missing seedUnitTaskScheduleRows helper for Stage 5 unit timing persistence",
  );
  assert.equal(
    /function\s+shiftUnitScheduleForApprovedProgress\s*\(/.test(
      controllerSource,
    ),
    true,
    "Missing shiftUnitScheduleForApprovedProgress helper for Stage 5 downstream shifts",
  );
  assert.equal(
    /function\s+buildUnitScheduleInsightsForPlan\s*\(/.test(controllerSource),
    true,
    "Missing buildUnitScheduleInsightsForPlan helper for manager divergence visibility",
  );
  assert.equal(
    /shiftUnitScheduleForApprovedProgress\s*\(\s*\{[\s\S]*approveTaskProgress/.test(
      controllerSource,
    ),
    true,
    "approveTaskProgress must invoke Stage 5 unit downstream shift propagation",
  );
  assert.equal(
    /unitDivergence/.test(controllerSource) &&
      /unitScheduleWarnings/.test(controllerSource),
    true,
    "Plan detail response must expose unit divergence and warning rows",
  );
});

test("stage6 plan detail payload exposes governance rows for managers and redacts risk for non-managers", () => {
  debug(TEST_LOG_TAG, "Checking stage6 manager-only risk payload shaping");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /const\s+canViewPlanRiskSignals\s*=\s*(?:canAssignProductionTasks|canViewTeamKpis)/.test(
      controllerSource,
    ),
    true,
    "getProductionPlanDetail must derive a manager-only risk visibility guard",
  );
  assert.equal(
    /enableUnitAssignments\s*&&\s*canViewPlanRiskSignals/.test(
      controllerSource,
    ),
    true,
    "Unit divergence/warnings must only load for manager-capable roles",
  );
  assert.equal(
    /enableDeviationGovernance\s*&&\s*canViewPlanRiskSignals/.test(
      controllerSource,
    ),
    true,
    "Deviation governance summary/alerts must only load for manager-capable roles",
  );
  assert.equal(
    /function\s+normalizeDeviationAlertForResponse\s*\(/.test(controllerSource),
    true,
    "Missing deviation alert response normalizer for stable plan-detail payload shape",
  );
  assert.equal(
    /deviationGovernanceSummary,\s*deviationAlerts/.test(controllerSource),
    true,
    "Plan detail response must expose deviationGovernanceSummary and deviationAlerts keys",
  );
});

test("stage5 task progress unit context is enforced for deterministic per-unit shifts", () => {
  debug(TEST_LOG_TAG, "Checking stage5 task-progress unit context enforcement");
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /TASK_PROGRESS_UNIT_REQUIRED_FOR_MULTI_ASSIGN/.test(controllerSource),
    true,
    "Missing multi-unit progress validation copy key",
  );
  assert.equal(
    /TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_ID_REQUIRED/.test(controllerSource) &&
      /TASK_PROGRESS_BATCH_ENTRY_CODE_UNIT_SCOPE_INVALID/.test(
        controllerSource,
      ),
    true,
    "Batch progress flow must classify unit-id errors",
  );
  assert.equal(
    /unitId:\s*effectiveUnitId\s*\|\|\s*null/.test(controllerSource),
    true,
    "Task progress writes must persist deterministic unitId context",
  );
  assert.equal(
    /buildBatchTaskProgressError\s*\(\s*\{[\s\S]*unitId/.test(controllerSource),
    true,
    "Batch progress errors must preserve unitId diagnostics",
  );
});

test("assistant-turn degrades retryable provider failures into a safe 200 assistant turn", () => {
  debug(
    TEST_LOG_TAG,
    "Checking assistant-turn provider failure degradation path",
  );
  const controllerSource = fs.readFileSync(
    path.resolve(__dirname, "../controllers/business.controller.js"),
    "utf8",
  );

  assert.equal(
    /shouldReturnAssistantRetryTurn/.test(controllerSource),
    true,
    "Assistant-turn must classify retryable provider failures",
  );
  assert.equal(
    /buildAssistantTurnSuggestions\s*\(\s*\{[\s\S]*providerFailureMessage/.test(
      controllerSource,
    ),
    true,
    "Assistant-turn must build a conversational retry turn for provider failures",
  );
  assert.equal(
    /provider failure degraded to assistant retry turn/.test(controllerSource),
    true,
    "Assistant-turn should log degradation boundary for provider failures",
  );
});
