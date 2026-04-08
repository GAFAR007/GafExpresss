/**
 * apps/backend/services/production_confidence.service.js
 * ------------------------------------------------------
 * WHAT:
 * - Computes deterministic production lifecycle confidence for individual plans and portfolios.
 *
 * WHY:
 * - Stage 7 requires explainable baseline/current confidence that is server-owned and trigger-driven.
 * - Confidence must not depend on AI output and must remain reproducible from persisted execution data.
 *
 * HOW:
 * - Loads plan lifecycle metrics (capacity, schedule stability, reliability, complexity) from MongoDB.
 * - Builds weighted scores with deterministic formulas and bounded rounding.
 * - Persists recomputations only when callers invoke explicit trigger paths.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const ProductionPlan = require("../models/ProductionPlan");
const ProductionPhase = require("../models/ProductionPhase");
const ProductionTask = require("../models/ProductionTask");
const TaskProgress = require("../models/TaskProgress");
const PlanUnit = require("../models/PlanUnit");
const ProductionUnitTaskSchedule = require("../models/ProductionUnitTaskSchedule");
const ProductionUnitScheduleWarning = require("../models/ProductionUnitScheduleWarning");
const LifecycleDeviationAlert = require("../models/LifecycleDeviationAlert");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");

const CONFIDENCE_DECIMALS = 4;
const SCORE_MIN = 0;
const SCORE_MAX = 1;
const DELTA_MIN = -1;
const DELTA_MAX = 1;
const DEFAULT_HISTORICAL_RELIABILITY = 0.75;
const DEFAULT_CONFIDENCE_SCORE = 0.75;
const MS_PER_DAY = 86400000;
const OPEN_DEVIATION_STATUS = "open";
const STAFF_STATUS_ACTIVE = "active";
const WARNING_SEVERITY_WARNING = "warning";
const PHASE_TYPE_MONITORING = "monitoring";

const CONFIDENCE_BREAKDOWN_KEYS = Object.freeze({
  capacity: "capacity",
  scheduleStability: "scheduleStability",
  historicalReliability: "historicalReliability",
  complexityRisk: "complexityRisk",
});

const CONFIDENCE_RECOMPUTE_TRIGGERS = Object.freeze({
  SCHEDULE_COMMIT: "schedule_commit",
  UNIT_COMPLETION_INSERT: "unit_completion_insert",
  DEVIATION_ALERT_TRIGGERED: "deviation_alert_triggered",
  VARIANCE_ACCEPTED: "variance_accepted",
  STAFF_AVAILABILITY_CHANGED: "staff_availability_changed",
  PLAN_WINDOW_CHANGED: "plan_window_changed",
});

const CONFIDENCE_ACTIVE_PLAN_STATUSES = Object.freeze([
  "draft",
  "active",
  "paused",
]);

function isValidObjectId(value) {
  return mongoose.Types.ObjectId.isValid(value);
}

function clamp(value, min, max) {
  if (!Number.isFinite(value)) {
    return min;
  }
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

function roundScore(value) {
  return Number(
    clamp(value, SCORE_MIN, SCORE_MAX).toFixed(
      CONFIDENCE_DECIMALS,
    ),
  );
}

function roundDelta(value) {
  return Number(
    clamp(value, DELTA_MIN, DELTA_MAX).toFixed(
      CONFIDENCE_DECIMALS,
    ),
  );
}

function normalizeScore(value, fallback = null) {
  if (!Number.isFinite(Number(value))) {
    return fallback;
  }
  return roundScore(Number(value));
}

function resolveTaskAssignedStaffIds(task) {
  const assignedStaffProfileIds = Array.isArray(
    task?.assignedStaffProfileIds,
  )
    ? task.assignedStaffProfileIds
    : [];
  if (assignedStaffProfileIds.length > 0) {
    return assignedStaffProfileIds
      .map((value) =>
        value?.toString().trim(),
      )
      .filter((value) =>
        isValidObjectId(value),
      );
  }

  const fallbackAssignedStaffId =
    task?.assignedStaffId
      ?.toString()
      .trim() || "";
  if (isValidObjectId(fallbackAssignedStaffId)) {
    return [fallbackAssignedStaffId];
  }
  return [];
}

function buildBreakdown({
  capacity,
  scheduleStability,
  historicalReliability,
  complexityRisk,
}) {
  return {
    [CONFIDENCE_BREAKDOWN_KEYS.capacity]: roundScore(
      capacity,
    ),
    [CONFIDENCE_BREAKDOWN_KEYS.scheduleStability]:
      roundScore(scheduleStability),
    [CONFIDENCE_BREAKDOWN_KEYS.historicalReliability]:
      roundScore(
        historicalReliability,
      ),
    [CONFIDENCE_BREAKDOWN_KEYS.complexityRisk]:
      roundScore(complexityRisk),
  };
}

function buildFallbackBreakdown(score) {
  return buildBreakdown({
    capacity: score,
    scheduleStability: score,
    historicalReliability: score,
    complexityRisk: score,
  });
}

function normalizeBreakdown(raw, fallbackScore) {
  if (!raw || typeof raw !== "object") {
    return buildFallbackBreakdown(
      fallbackScore,
    );
  }
  return buildBreakdown({
    capacity: Number(raw.capacity),
    scheduleStability: Number(
      raw.scheduleStability,
    ),
    historicalReliability: Number(
      raw.historicalReliability,
    ),
    complexityRisk: Number(
      raw.complexityRisk,
    ),
  });
}

function buildConfidencePayload({
  baselineConfidenceScore,
  currentConfidenceScore,
  baselineBreakdown,
  currentBreakdown,
  confidenceScoreDelta,
  confidenceLastComputedAt,
  confidenceLastTrigger,
  confidenceRecomputeCount,
  transient = false,
}) {
  return {
    baselineConfidenceScore:
      roundScore(
        baselineConfidenceScore,
      ),
    currentConfidenceScore:
      roundScore(
        currentConfidenceScore,
      ),
    confidenceScoreDelta: roundDelta(
      confidenceScoreDelta,
    ),
    baselineBreakdown:
      normalizeBreakdown(
        baselineBreakdown,
        baselineConfidenceScore,
      ),
    currentBreakdown:
      normalizeBreakdown(
        currentBreakdown,
        currentConfidenceScore,
      ),
    confidenceLastComputedAt:
      confidenceLastComputedAt || null,
    confidenceLastTrigger:
      confidenceLastTrigger || "",
    confidenceRecomputeCount: Math.max(
      0,
      Number(
        confidenceRecomputeCount || 0,
      ),
    ),
    transient,
  };
}

function buildPlanConfidenceFromStoredPlan(
  plan,
) {
  const baselineConfidenceScore =
    normalizeScore(
      Number(
        plan?.baselineConfidenceScore,
      ),
    );
  const currentConfidenceScore =
    normalizeScore(
      Number(
        plan?.currentConfidenceScore,
      ),
    );

  const effectiveBaseline =
    baselineConfidenceScore ??
    currentConfidenceScore;
  const effectiveCurrent =
    currentConfidenceScore ??
    baselineConfidenceScore;

  if (
    !Number.isFinite(
      Number(effectiveBaseline),
    ) ||
    !Number.isFinite(
      Number(effectiveCurrent),
    )
  ) {
    return null;
  }

  const deltaFromPlan = Number(
    plan?.confidenceScoreDelta,
  );
  const delta = Number.isFinite(
    deltaFromPlan,
  )
    ? deltaFromPlan
    : Number(effectiveCurrent) -
      Number(effectiveBaseline);

  return buildConfidencePayload({
    baselineConfidenceScore:
      Number(effectiveBaseline),
    currentConfidenceScore:
      Number(effectiveCurrent),
    baselineBreakdown:
      plan?.baselineConfidenceBreakdown,
    currentBreakdown:
      plan?.currentConfidenceBreakdown,
    confidenceScoreDelta: delta,
    confidenceLastComputedAt:
      plan?.confidenceLastComputedAt ||
      null,
    confidenceLastTrigger:
      plan?.confidenceLastTrigger || "",
    confidenceRecomputeCount:
      plan?.confidenceRecomputeCount ||
      0,
    transient: false,
  });
}

async function loadPlanConfidenceMetrics({
  plan,
}) {
  const planId = plan?._id;
  const businessId = plan?.businessId;

  if (
    !isValidObjectId(planId) ||
    !isValidObjectId(businessId)
  ) {
    throw new Error(
      "Invalid plan context for confidence metrics",
    );
  }

  const staffScopeFilter = {
    businessId,
    status: STAFF_STATUS_ACTIVE,
  };
  if (isValidObjectId(plan?.estateAssetId)) {
    staffScopeFilter.estateAssetId =
      plan.estateAssetId;
  }

  // WHY: Load all deterministic score ingredients in one parallel boundary to keep recompute latency bounded.
  const [
    phaseRows,
    taskRows,
    activeStaffRows,
    totalProgressCount,
    approvedProgressCount,
    approvedProgressQualityRows,
    planUnitCount,
    openDeviationAlertCount,
    warningCount,
    lockedUnitCount,
    unitDelayRows,
  ] = await Promise.all([
    ProductionPhase.find({
      planId,
    })
      .select({
        phaseType: 1,
      })
      .lean(),
    ProductionTask.find({
      planId,
    })
      .select({
        roleRequired: 1,
        requiredHeadcount: 1,
        assignedStaffId: 1,
        assignedStaffProfileIds: 1,
      })
      .lean(),
    BusinessStaffProfile.find(
      staffScopeFilter,
    )
      .select({
        staffRole: 1,
      })
      .lean(),
    TaskProgress.countDocuments({
      planId,
    }),
    TaskProgress.countDocuments({
      planId,
      approvedAt: { $ne: null },
    }),
    TaskProgress.aggregate([
      {
        $match: {
          planId: new mongoose.Types.ObjectId(
            planId,
          ),
          approvedAt: { $ne: null },
        },
      },
      {
        $group: {
          _id: null,
          approvedOnTargetCount: {
            $sum: {
              $cond: [
                {
                  $gte: [
                    "$actualPlots",
                    "$expectedPlots",
                  ],
                },
                1,
                0,
              ],
            },
          },
        },
      },
    ]),
    PlanUnit.countDocuments({
      planId,
    }),
    LifecycleDeviationAlert.countDocuments({
      planId,
      status: OPEN_DEVIATION_STATUS,
    }),
    ProductionUnitScheduleWarning.countDocuments(
      {
        planId,
        severity:
          WARNING_SEVERITY_WARNING,
      },
    ),
    PlanUnit.countDocuments({
      planId,
      deviationLocked: true,
    }),
    ProductionUnitTaskSchedule.aggregate([
      {
        $match: {
          planId: new mongoose.Types.ObjectId(
            planId,
          ),
        },
      },
      {
        $project: {
          delayDays: {
            $divide: [
              {
                $max: [
                  {
                    $subtract: [
                      "$currentDueDate",
                      "$baselineDueDate",
                    ],
                  },
                  0,
                ],
              },
              MS_PER_DAY,
            ],
          },
        },
      },
      {
        $group: {
          _id: null,
          averageDelayDays: {
            $avg: "$delayDays",
          },
          delayedRowCount: {
            $sum: {
              $cond: [
                {
                  $gt: ["$delayDays", 0],
                },
                1,
                0,
              ],
            },
          },
        },
      },
    ]),
  ]);

  const requiredRoleSet = new Set();
  const assignedStaffSet = new Set();
  let requiredHeadcountTotal = 0;

  taskRows.forEach((task) => {
    const taskRole =
      task?.roleRequired
        ?.toString()
        .trim() || "";
    if (taskRole) {
      requiredRoleSet.add(taskRole);
    }

    const requiredHeadcount = Math.max(
      1,
      Math.floor(
        Number(
          task?.requiredHeadcount || 1,
        ),
      ),
    );
    requiredHeadcountTotal +=
      requiredHeadcount;

    resolveTaskAssignedStaffIds(
      task,
    ).forEach((staffId) => {
      assignedStaffSet.add(staffId);
    });
  });

  const activeStaffByRole = new Map();
  activeStaffRows.forEach((profile) => {
    const role =
      profile?.staffRole
        ?.toString()
        .trim() || "";
    if (!role) {
      return;
    }
    activeStaffByRole.set(
      role,
      Number(
        activeStaffByRole.get(role) ||
          0,
      ) + 1,
    );
  });

  const coveredRoleCount = Array.from(
    requiredRoleSet,
  ).reduce(
    (count, role) =>
      count +
      (Number(
        activeStaffByRole.get(role) ||
          0,
      ) > 0
        ? 1
        : 0),
    0,
  );

  const requiredRoleCount =
    requiredRoleSet.size;
  const roleCoverageRatio =
    requiredRoleCount > 0
      ? coveredRoleCount /
        requiredRoleCount
      : 1;

  const staffingDemand = Math.max(
    assignedStaffSet.size,
    Math.min(
      requiredHeadcountTotal,
      Math.max(requiredRoleCount, 1),
    ),
  );
  const staffingDepthRatio =
    staffingDemand > 0
      ? Math.min(
          activeStaffRows.length /
            staffingDemand,
          1,
        )
      : 1;

  const monitoringPhaseCount =
    phaseRows.filter((phase) => {
      const phaseType =
        phase?.phaseType
          ?.toString()
          .trim()
          .toLowerCase() || "";
      return (
        phaseType ===
        PHASE_TYPE_MONITORING
      );
    }).length;

  const approvedOnTargetCount = Number(
    approvedProgressQualityRows?.[0]
      ?.approvedOnTargetCount || 0,
  );
  const averageDelayDays = Number(
    unitDelayRows?.[0]
      ?.averageDelayDays || 0,
  );

  return {
    phaseCount: phaseRows.length,
    monitoringPhaseCount,
    taskCount: taskRows.length,
    requiredHeadcountTotal,
    requiredRoleCount,
    coveredRoleCount,
    roleCoverageRatio,
    staffingDemand,
    staffingDepthRatio,
    activeStaffCount:
      activeStaffRows.length,
    totalProgressCount: Number(
      totalProgressCount || 0,
    ),
    approvedProgressCount: Number(
      approvedProgressCount || 0,
    ),
    approvedOnTargetCount,
    planUnitCount: Number(
      planUnitCount || 0,
    ),
    openDeviationAlertCount:
      Number(
        openDeviationAlertCount || 0,
      ),
    warningCount: Number(
      warningCount || 0,
    ),
    lockedUnitCount: Number(
      lockedUnitCount || 0,
    ),
    averageDelayDays: Number.isFinite(
      averageDelayDays,
    )
      ? averageDelayDays
      : 0,
  };
}

function buildConfidenceFromMetrics({
  metrics,
  baselineMode,
}) {
  const capacityScore = roundScore(
    Number(
      metrics.roleCoverageRatio || 0,
    ) *
      0.6 +
      Number(
        metrics.staffingDepthRatio || 0,
      ) *
        0.4,
  );

  const scheduleAlertPenalty = baselineMode
    ? 0
    : clamp(
        (Number(
          metrics.openDeviationAlertCount ||
            0,
        ) +
          Number(
            metrics.lockedUnitCount || 0,
          )) /
          Math.max(
            Number(
              metrics.planUnitCount || 0,
            ),
            1,
          ),
        SCORE_MIN,
        SCORE_MAX,
      );
  const scheduleDelayPenalty = baselineMode
    ? 0
    : clamp(
        Number(
          metrics.averageDelayDays || 0,
        ) / 7,
        SCORE_MIN,
        SCORE_MAX,
      );
  const scheduleWarningPenalty = baselineMode
    ? 0
    : clamp(
        Number(
          metrics.warningCount || 0,
        ) /
          Math.max(
            Number(metrics.taskCount || 0),
            1,
          ),
        SCORE_MIN,
        SCORE_MAX,
      );
  const scheduleStabilityScore = roundScore(
    1 -
      (scheduleAlertPenalty * 0.5 +
        scheduleDelayPenalty * 0.3 +
        scheduleWarningPenalty * 0.2),
  );

  const approvedProgressCoverage =
    Number(metrics.totalProgressCount || 0) >
    0
      ? Number(
          metrics.approvedProgressCount || 0,
        ) /
        Number(
          metrics.totalProgressCount || 1,
        )
      : 0;
  const approvedQualityRatio =
    Number(
      metrics.approvedProgressCount || 0,
    ) > 0
      ? Number(
          metrics.approvedOnTargetCount ||
            0,
        ) /
        Number(
          metrics.approvedProgressCount ||
            1,
        )
      : 0;

  const historicalReliabilityScore =
    baselineMode
      ? roundScore(
          DEFAULT_HISTORICAL_RELIABILITY,
        )
      : Number(
            metrics.totalProgressCount || 0,
          ) === 0
      ? roundScore(
          DEFAULT_HISTORICAL_RELIABILITY,
        )
      : roundScore(
          approvedProgressCoverage * 0.7 +
            approvedQualityRatio * 0.3,
        );

  const phaseCountForComplexity =
    Math.max(
      Number(metrics.phaseCount || 0),
      1,
    );
  const taskDensityPenalty = clamp(
    Number(metrics.taskCount || 0) /
      phaseCountForComplexity /
      8,
    SCORE_MIN,
    SCORE_MAX,
  );
  const unitLoadPenalty = clamp(
    Number(metrics.taskCount || 0) /
      Math.max(
        Number(metrics.planUnitCount || 0),
        1,
      ) /
      12,
    SCORE_MIN,
    SCORE_MAX,
  );
  const monitoringPenalty = clamp(
    Number(
      metrics.monitoringPhaseCount || 0,
    ) /
      phaseCountForComplexity /
      0.6,
    SCORE_MIN,
    SCORE_MAX,
  );
  const complexityRiskScore = roundScore(
    1 -
      (taskDensityPenalty * 0.45 +
        unitLoadPenalty * 0.35 +
        monitoringPenalty * 0.2),
  );

  const overallScore = roundScore(
    capacityScore * 0.3 +
      scheduleStabilityScore * 0.3 +
      historicalReliabilityScore * 0.25 +
      complexityRiskScore * 0.15,
  );

  return {
    score: overallScore,
    breakdown: buildBreakdown({
      capacity: capacityScore,
      scheduleStability:
        scheduleStabilityScore,
      historicalReliability:
        historicalReliabilityScore,
      complexityRisk:
        complexityRiskScore,
    }),
  };
}

async function buildTransientPlanConfidenceSnapshot(
  {
    plan,
  },
) {
  const metrics =
    await loadPlanConfidenceMetrics({
      plan,
    });
  const baselineConfidence =
    buildConfidenceFromMetrics({
      metrics,
      baselineMode: true,
    });
  const currentConfidence =
    buildConfidenceFromMetrics({
      metrics,
      baselineMode: false,
    });

  return buildConfidencePayload({
    baselineConfidenceScore:
      baselineConfidence.score,
    currentConfidenceScore:
      currentConfidence.score,
    baselineBreakdown:
      baselineConfidence.breakdown,
    currentBreakdown:
      currentConfidence.breakdown,
    confidenceScoreDelta:
      currentConfidence.score -
      baselineConfidence.score,
    confidenceLastComputedAt: null,
    confidenceLastTrigger: "",
    confidenceRecomputeCount:
      Number(
        plan?.confidenceRecomputeCount ||
          0,
      ),
    transient: true,
  });
}

async function resolvePlanConfidenceSnapshot({
  plan,
}) {
  const storedSnapshot =
    buildPlanConfidenceFromStoredPlan(plan);
  if (storedSnapshot) {
    return storedSnapshot;
  }

  return buildTransientPlanConfidenceSnapshot(
    {
      plan,
    },
  );
}

async function recomputePlanConfidenceSnapshot({
  planId,
  trigger,
  actorId = null,
}) {
  if (!isValidObjectId(planId)) {
    return {
      applied: false,
      skippedReason:
        "plan_id_invalid",
    };
  }

  const plan =
    await ProductionPlan.findById(
      planId,
    )
      .select({
        _id: 1,
        businessId: 1,
        estateAssetId: 1,
        baselineConfidenceScore: 1,
        currentConfidenceScore: 1,
        baselineConfidenceBreakdown: 1,
        currentConfidenceBreakdown: 1,
        confidenceRecomputeCount: 1,
      })
      .lean();
  if (!plan) {
    return {
      applied: false,
      skippedReason:
        "plan_not_found",
    };
  }

  debug(
    "PRODUCTION CONFIDENCE: recompute start",
    {
      planId: plan._id,
      businessId: plan.businessId,
      trigger:
        trigger ||
        CONFIDENCE_RECOMPUTE_TRIGGERS.SCHEDULE_COMMIT,
    },
  );

  const metrics =
    await loadPlanConfidenceMetrics({
      plan,
    });
  const currentConfidence =
    buildConfidenceFromMetrics({
      metrics,
      baselineMode: false,
    });

  const existingBaselineScore =
    normalizeScore(
      Number(
        plan.baselineConfidenceScore,
      ),
    );
  const existingBaselineBreakdown =
    plan.baselineConfidenceBreakdown;

  const baselineConfidence =
    Number.isFinite(
      Number(existingBaselineScore),
    )
      ? {
          score: Number(
            existingBaselineScore,
          ),
          breakdown:
            normalizeBreakdown(
              existingBaselineBreakdown,
              Number(
                existingBaselineScore,
              ),
            ),
        }
      : buildConfidenceFromMetrics({
          metrics,
          baselineMode: true,
        });

  const confidenceLastComputedAt =
    new Date();
  const confidenceLastTrigger =
    (trigger || "")
      .toString()
      .trim() ||
    CONFIDENCE_RECOMPUTE_TRIGGERS.SCHEDULE_COMMIT;
  const confidenceScoreDelta =
    currentConfidence.score -
    baselineConfidence.score;

  const updatePayload = {
    baselineConfidenceScore:
      baselineConfidence.score,
    currentConfidenceScore:
      currentConfidence.score,
    baselineConfidenceBreakdown:
      baselineConfidence.breakdown,
    currentConfidenceBreakdown:
      currentConfidence.breakdown,
    confidenceScoreDelta: roundDelta(
      confidenceScoreDelta,
    ),
    confidenceLastComputedAt,
    confidenceLastTrigger,
    confidenceLastComputedBy:
      isValidObjectId(actorId)
        ? actorId
        : null,
  };

  await ProductionPlan.updateOne(
    {
      _id: plan._id,
    },
    {
      $set: updatePayload,
      $inc: {
        confidenceRecomputeCount: 1,
      },
    },
  );

  const snapshot =
    buildConfidencePayload({
      baselineConfidenceScore:
        baselineConfidence.score,
      currentConfidenceScore:
        currentConfidence.score,
      baselineBreakdown:
        baselineConfidence.breakdown,
      currentBreakdown:
        currentConfidence.breakdown,
      confidenceScoreDelta,
      confidenceLastComputedAt,
      confidenceLastTrigger,
      confidenceRecomputeCount:
        Number(
          plan.confidenceRecomputeCount ||
            0,
        ) + 1,
      transient: false,
    });

  debug(
    "PRODUCTION CONFIDENCE: recompute success",
    {
      planId: plan._id,
      trigger: confidenceLastTrigger,
      baselineConfidenceScore:
        snapshot
          .baselineConfidenceScore,
      currentConfidenceScore:
        snapshot
          .currentConfidenceScore,
      confidenceScoreDelta:
        snapshot
          .confidenceScoreDelta,
      confidenceRecomputeCount:
        snapshot
          .confidenceRecomputeCount,
    },
  );

  return {
    applied: true,
    planId: plan._id,
    trigger: confidenceLastTrigger,
    snapshot,
  };
}

async function recomputeConfidenceForActivePlans(
  {
    businessId,
    estateAssetId = null,
    trigger,
    actorId = null,
  },
) {
  if (!isValidObjectId(businessId)) {
    return {
      attemptedPlans: 0,
      appliedPlans: 0,
      skippedPlans: 0,
      skippedReason:
        "business_id_invalid",
      results: [],
    };
  }

  const filter = {
    businessId,
    status: {
      $in: CONFIDENCE_ACTIVE_PLAN_STATUSES,
    },
  };
  if (isValidObjectId(estateAssetId)) {
    filter.estateAssetId =
      estateAssetId;
  }

  const plans =
    await ProductionPlan.find(filter)
      .select({ _id: 1 })
      .lean();
  const results = [];

  // WHY: Apply deterministic recompute per plan id so one failure does not block the full scope refresh.
  for (const plan of plans) {
    try {
      const result =
        await recomputePlanConfidenceSnapshot(
          {
            planId: plan._id,
            trigger,
            actorId,
          },
        );
      results.push(result);
    } catch (error) {
      debug(
        "PRODUCTION CONFIDENCE: scoped recompute failure",
        {
          planId: plan?._id || null,
          businessId,
          trigger,
          reason: error.message,
        },
      );
      results.push({
        applied: false,
        planId: plan?._id || null,
        skippedReason:
          "recompute_failed",
      });
    }
  }

  const appliedPlans = results.filter(
    (entry) => entry?.applied,
  ).length;
  return {
    attemptedPlans: plans.length,
    appliedPlans,
    skippedPlans:
      plans.length - appliedPlans,
    skippedReason: "",
    results,
  };
}

async function buildPortfolioConfidenceSummary({
  businessId,
  estateAssetId = null,
}) {
  if (!isValidObjectId(businessId)) {
    return {
      planCount: 0,
      weightedUnitCount: 0,
      baselineConfidenceScore: roundScore(
        DEFAULT_CONFIDENCE_SCORE,
      ),
      currentConfidenceScore: roundScore(
        DEFAULT_CONFIDENCE_SCORE,
      ),
      confidenceScoreDelta: 0,
      baselineBreakdown:
        buildFallbackBreakdown(
          DEFAULT_CONFIDENCE_SCORE,
        ),
      currentBreakdown:
        buildFallbackBreakdown(
          DEFAULT_CONFIDENCE_SCORE,
        ),
    };
  }

  const filter = {
    businessId,
    status: {
      $in: CONFIDENCE_ACTIVE_PLAN_STATUSES,
    },
  };
  if (isValidObjectId(estateAssetId)) {
    filter.estateAssetId =
      estateAssetId;
  }

  const plans =
    await ProductionPlan.find(filter)
      .select({
        _id: 1,
        baselineConfidenceScore: 1,
        currentConfidenceScore: 1,
        baselineConfidenceBreakdown: 1,
        currentConfidenceBreakdown: 1,
        confidenceScoreDelta: 1,
      })
      .lean();

  if (plans.length === 0) {
    return {
      planCount: 0,
      weightedUnitCount: 0,
      baselineConfidenceScore: roundScore(
        DEFAULT_CONFIDENCE_SCORE,
      ),
      currentConfidenceScore: roundScore(
        DEFAULT_CONFIDENCE_SCORE,
      ),
      confidenceScoreDelta: 0,
      baselineBreakdown:
        buildFallbackBreakdown(
          DEFAULT_CONFIDENCE_SCORE,
        ),
      currentBreakdown:
        buildFallbackBreakdown(
          DEFAULT_CONFIDENCE_SCORE,
        ),
    };
  }

  const planIds = plans
    .map((plan) => plan?._id)
    .filter((planId) =>
      isValidObjectId(planId),
    );

  const unitRows =
    planIds.length > 0
      ? await PlanUnit.aggregate([
          {
            $match: {
              planId: {
                $in: planIds.map(
                  (planId) =>
                    new mongoose.Types.ObjectId(
                      planId,
                    ),
                ),
              },
            },
          },
          {
            $group: {
              _id: "$planId",
              unitCount: {
                $sum: 1,
              },
            },
          },
        ])
      : [];

  const unitCountByPlanId = new Map(
    unitRows.map((row) => [
      row?._id?.toString(),
      Number(row?.unitCount || 0),
    ]),
  );

  let weightedUnitCount = 0;
  let weightedBaselineScore = 0;
  let weightedCurrentScore = 0;
  let weightedDelta = 0;
  let weightedBaselineCapacity = 0;
  let weightedBaselineSchedule = 0;
  let weightedBaselineReliability = 0;
  let weightedBaselineComplexity = 0;
  let weightedCurrentCapacity = 0;
  let weightedCurrentSchedule = 0;
  let weightedCurrentReliability = 0;
  let weightedCurrentComplexity = 0;

  plans.forEach((plan) => {
    const snapshot =
      buildPlanConfidenceFromStoredPlan(
        plan,
      ) ||
      buildConfidencePayload({
        baselineConfidenceScore:
          DEFAULT_CONFIDENCE_SCORE,
        currentConfidenceScore:
          DEFAULT_CONFIDENCE_SCORE,
        baselineBreakdown:
          buildFallbackBreakdown(
            DEFAULT_CONFIDENCE_SCORE,
          ),
        currentBreakdown:
          buildFallbackBreakdown(
            DEFAULT_CONFIDENCE_SCORE,
          ),
        confidenceScoreDelta: 0,
        confidenceLastComputedAt:
          null,
        confidenceLastTrigger: "",
        confidenceRecomputeCount: 0,
        transient: true,
      });

    const unitWeight = Math.max(
      1,
      Number(
        unitCountByPlanId.get(
          plan?._id?.toString() || "",
        ) || 0,
      ),
    );
    weightedUnitCount += unitWeight;
    weightedBaselineScore +=
      snapshot
        .baselineConfidenceScore *
      unitWeight;
    weightedCurrentScore +=
      snapshot
        .currentConfidenceScore *
      unitWeight;
    weightedDelta +=
      snapshot
        .confidenceScoreDelta *
      unitWeight;

    weightedBaselineCapacity +=
      Number(
        snapshot
          .baselineBreakdown
          .capacity || 0,
      ) * unitWeight;
    weightedBaselineSchedule +=
      Number(
        snapshot
          .baselineBreakdown
          .scheduleStability || 0,
      ) * unitWeight;
    weightedBaselineReliability +=
      Number(
        snapshot
          .baselineBreakdown
          .historicalReliability || 0,
      ) * unitWeight;
    weightedBaselineComplexity +=
      Number(
        snapshot
          .baselineBreakdown
          .complexityRisk || 0,
      ) * unitWeight;

    weightedCurrentCapacity +=
      Number(
        snapshot
          .currentBreakdown
          .capacity || 0,
      ) * unitWeight;
    weightedCurrentSchedule +=
      Number(
        snapshot
          .currentBreakdown
          .scheduleStability || 0,
      ) * unitWeight;
    weightedCurrentReliability +=
      Number(
        snapshot
          .currentBreakdown
          .historicalReliability || 0,
      ) * unitWeight;
    weightedCurrentComplexity +=
      Number(
        snapshot
          .currentBreakdown
          .complexityRisk || 0,
      ) * unitWeight;
  });

  const safeWeight = Math.max(
    weightedUnitCount,
    1,
  );

  return {
    planCount: plans.length,
    weightedUnitCount,
    baselineConfidenceScore:
      roundScore(
        weightedBaselineScore /
          safeWeight,
      ),
    currentConfidenceScore:
      roundScore(
        weightedCurrentScore /
          safeWeight,
      ),
    confidenceScoreDelta: roundDelta(
      weightedDelta / safeWeight,
    ),
    baselineBreakdown:
      buildBreakdown({
        capacity:
          weightedBaselineCapacity /
          safeWeight,
        scheduleStability:
          weightedBaselineSchedule /
          safeWeight,
        historicalReliability:
          weightedBaselineReliability /
          safeWeight,
        complexityRisk:
          weightedBaselineComplexity /
          safeWeight,
      }),
    currentBreakdown:
      buildBreakdown({
        capacity:
          weightedCurrentCapacity /
          safeWeight,
        scheduleStability:
          weightedCurrentSchedule /
          safeWeight,
        historicalReliability:
          weightedCurrentReliability /
          safeWeight,
        complexityRisk:
          weightedCurrentComplexity /
          safeWeight,
      }),
  };
}

module.exports = {
  CONFIDENCE_BREAKDOWN_KEYS,
  CONFIDENCE_RECOMPUTE_TRIGGERS,
  CONFIDENCE_ACTIVE_PLAN_STATUSES,
  DEFAULT_CONFIDENCE_SCORE,
  buildPlanConfidenceFromStoredPlan,
  resolvePlanConfidenceSnapshot,
  recomputePlanConfidenceSnapshot,
  recomputeConfidenceForActivePlans,
  buildPortfolioConfidenceSummary,
};
