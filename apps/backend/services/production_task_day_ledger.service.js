/**
 * apps/backend/services/production_task_day_ledger.service.js
 * -----------------------------------------------------------
 * WHAT:
 * - Shared aggregation and normalization helpers for daily production ledgers.
 *
 * WHY:
 * - Task/day completion is shared across multiple staff logs.
 * - Controllers need one deterministic place to validate and recompute shared totals.
 *
 * HOW:
 * - Normalizes activity types and activity target units.
 * - Aggregates valid contribution rows into one task/day ledger snapshot.
 * - Upserts the shared ledger inside the caller's persistence flow.
 */

const TaskProgress = require("../models/TaskProgress");
const ProductionTaskDayLedger = require("../models/ProductionTaskDayLedger");
const {
  SHARED_ACTIVITY_NONE,
  SHARED_ACTIVITY_PLANTED,
  SHARED_ACTIVITY_TRANSPLANTED,
  SHARED_ACTIVITY_HARVESTED,
  SHARED_TRACKED_ACTIVITY_TYPES,
} = require("../models/ProductionTaskDayLedger");

const TASK_PROGRESS_REJECTION_NOTE_PREFIX =
  "[TASK_PROGRESS_REJECTED]";

function parseNonNegativeNumber(value) {
  const parsed = Number(value || 0);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return 0;
  }
  return parsed;
}

function normalizeLedgerWorkDate(value) {
  const parsed =
    value instanceof Date ?
      new Date(value.getTime())
    : new Date(value);
  if (
    !(parsed instanceof Date) ||
    Number.isNaN(parsed.getTime())
  ) {
    return null;
  }
  return new Date(
    Date.UTC(
      parsed.getUTCFullYear(),
      parsed.getUTCMonth(),
      parsed.getUTCDate(),
      0,
      0,
      0,
      0,
    ),
  );
}

function normalizeProductionLedgerActivityType(
  value,
) {
  const normalized =
    (value || "")
      .toString()
      .trim()
      .toLowerCase();
  switch (normalized) {
    case "plant":
    case "planted":
    case "planting":
      return SHARED_ACTIVITY_PLANTED;
    case "transplant":
    case "transplanted":
    case "transplanting":
      return SHARED_ACTIVITY_TRANSPLANTED;
    case "harvest":
    case "harvested":
    case "harvesting":
      return SHARED_ACTIVITY_HARVESTED;
    default:
      return SHARED_ACTIVITY_NONE;
  }
}

function buildEmptyTrackedActivityTotals() {
  return {
    planted: 0,
    transplanted: 0,
    harvested: 0,
  };
}

function buildEmptyTrackedActivityTargets() {
  return {
    planted: null,
    transplanted: null,
    harvested: null,
  };
}

function buildEmptyTrackedActivityUnits() {
  return {
    planted: "",
    transplanted: "",
    harvested: "",
  };
}

function resolveLedgerActivityTargetsFromPlan({
  plan,
}) {
  const plantingTargets =
    plan?.plantingTargets || null;
  if (!plantingTargets) {
    return buildEmptyTrackedActivityTargets();
  }
  const plannedPlantingQuantity =
    plantingTargets
      ?.plannedPlantingQuantity;
  const estimatedHarvestQuantity =
    plantingTargets
      ?.estimatedHarvestQuantity;
  const hasPlannedPlantingQuantity =
    Number.isFinite(
      Number(plannedPlantingQuantity),
    ) &&
    Number(plannedPlantingQuantity) >= 0;
  const hasEstimatedHarvestQuantity =
    Number.isFinite(
      Number(estimatedHarvestQuantity),
    ) &&
    Number(estimatedHarvestQuantity) >= 0;

  return {
    planted:
      hasPlannedPlantingQuantity ?
        Number(plannedPlantingQuantity)
      : null,
    transplanted:
      hasPlannedPlantingQuantity ?
        Number(plannedPlantingQuantity)
      : null,
    harvested:
      hasEstimatedHarvestQuantity ?
        Number(estimatedHarvestQuantity)
      : null,
  };
}

function resolveLedgerActivityUnitsFromPlan({
  plan,
}) {
  const plantingTargets =
    plan?.plantingTargets || null;
  if (!plantingTargets) {
    return buildEmptyTrackedActivityUnits();
  }
  const plantingUnit =
    (
      plantingTargets
        ?.plannedPlantingUnit || ""
    )
      .toString()
      .trim();
  const harvestUnit =
    (
      plantingTargets
        ?.estimatedHarvestUnit || ""
    )
      .toString()
      .trim();

  return {
    planted: plantingUnit,
    transplanted: plantingUnit,
    harvested: harvestUnit,
  };
}

function resolveLedgerUnitType({
  plan,
}) {
  const explicitWorkUnitLabel =
    (
      plan?.workloadContext
        ?.resolvedWorkUnitLabel ||
      plan?.workloadContext
        ?.workUnitLabel ||
      ""
    )
      .toString()
      .trim();
  if (explicitWorkUnitLabel) {
    return explicitWorkUnitLabel;
  }
  return "work unit";
}

function isTaskProgressRejected(record) {
  const notes =
    record?.notes?.toString() || "";
  return notes.includes(
    TASK_PROGRESS_REJECTION_NOTE_PREFIX,
  );
}

function isTaskProgressCountedInSharedLedger(
  record,
) {
  return Boolean(
    record &&
      !isTaskProgressRejected(record),
  );
}

function resolveTaskProgressUnitContribution(
  record,
) {
  if (!record) {
    return 0;
  }
  const candidate =
    record.unitContribution ??
    record.actualPlots ??
    0;
  return parseNonNegativeNumber(
    candidate,
  );
}

function resolveTaskProgressActivityQuantity(
  record,
) {
  if (!record) {
    return 0;
  }
  const candidate =
    record.activityQuantity ??
    record.quantityAmount ??
    0;
  return parseNonNegativeNumber(
    candidate,
  );
}

function resolveTaskProgressActivityType(
  record,
) {
  if (!record) {
    return SHARED_ACTIVITY_NONE;
  }
  return normalizeProductionLedgerActivityType(
    record.activityType ??
      record.quantityActivityType,
  );
}

function aggregateProductionTaskDayLedger({
  progressRecords,
  unitTarget,
  unitType,
  activityTargets,
  activityUnits,
}) {
  const safeActivityTargets = {
    ...buildEmptyTrackedActivityTargets(),
    ...(activityTargets || {}),
  };
  const safeActivityUnits = {
    ...buildEmptyTrackedActivityUnits(),
    ...(activityUnits || {}),
  };
  const activityCompleted =
    buildEmptyTrackedActivityTotals();

  let unitCompleted = 0;

  (Array.isArray(progressRecords) ?
      progressRecords
    : []
  ).forEach((record) => {
    if (
      !isTaskProgressCountedInSharedLedger(
        record,
      )
    ) {
      return;
    }

    const unitContribution =
      resolveTaskProgressUnitContribution(
        record,
      );
    unitCompleted += unitContribution;

    const activityType =
      resolveTaskProgressActivityType(
        record,
      );
    const activityQuantity =
      resolveTaskProgressActivityQuantity(
        record,
      );
    if (
      SHARED_TRACKED_ACTIVITY_TYPES.includes(
        activityType,
      ) &&
      activityQuantity > 0
    ) {
      activityCompleted[
        activityType
      ] += activityQuantity;
    }
  });

  const normalizedUnitTarget =
    parseNonNegativeNumber(
      unitTarget,
    );
  const unitRemaining = Math.max(
    0,
    normalizedUnitTarget -
      unitCompleted,
  );
  const activityRemaining =
    buildEmptyTrackedActivityTargets();

  SHARED_TRACKED_ACTIVITY_TYPES.forEach(
    (activityType) => {
      const targetValue =
        safeActivityTargets[
          activityType
        ];
      if (
        !Number.isFinite(
          Number(targetValue),
        )
      ) {
        activityRemaining[
          activityType
        ] = null;
        return;
      }
      activityRemaining[
        activityType
      ] = Math.max(
        0,
        Number(targetValue) -
          activityCompleted[
            activityType
          ],
      );
    },
  );

  let status = "not_started";
  if (unitCompleted > 0) {
    status =
      unitRemaining <= 0 ?
        "completed"
      : "in_progress";
  }

  return {
    unitType:
      (unitType || "")
        .toString()
        .trim() || "work unit",
    unitTarget:
      normalizedUnitTarget,
    unitCompleted,
    unitRemaining,
    status,
    activityTargets:
      safeActivityTargets,
    activityCompleted,
    activityRemaining,
    activityUnits:
      safeActivityUnits,
  };
}

async function recomputeProductionTaskDayLedger({
  session = null,
  planId,
  taskId,
  workDate,
  unitTarget,
  unitType,
  activityTargets,
  activityUnits,
}) {
  const normalizedWorkDate =
    normalizeLedgerWorkDate(workDate);
  if (
    !taskId ||
    !planId ||
    !normalizedWorkDate
  ) {
    throw new Error(
      "Task/day ledger scope is required",
    );
  }

  const progressQuery =
    TaskProgress.find({
      taskId,
      workDate:
        normalizedWorkDate,
    }).lean();
  if (session) {
    progressQuery.session(session);
  }
  const progressRecords =
    await progressQuery;
  const snapshot =
    aggregateProductionTaskDayLedger({
      progressRecords,
      unitTarget,
      unitType,
      activityTargets,
      activityUnits,
    });

  const update = {
    $set: {
      planId,
      taskId,
      workDate:
        normalizedWorkDate,
      unitType:
        snapshot.unitType,
      unitTarget:
        snapshot.unitTarget,
      unitCompleted:
        snapshot.unitCompleted,
      unitRemaining:
        snapshot.unitRemaining,
      status: snapshot.status,
      activityTargets:
        snapshot.activityTargets,
      activityCompleted:
        snapshot.activityCompleted,
      activityRemaining:
        snapshot.activityRemaining,
      activityUnits:
        snapshot.activityUnits,
    },
  };

  const updateQuery =
    ProductionTaskDayLedger.findOneAndUpdate(
      {
        taskId,
        workDate:
          normalizedWorkDate,
      },
      update,
      {
        new: true,
        upsert: true,
        setDefaultsOnInsert: true,
      },
    );
  if (session) {
    updateQuery.session(session);
  }
  return updateQuery.lean();
}

module.exports = {
  SHARED_ACTIVITY_NONE,
  SHARED_ACTIVITY_PLANTED,
  SHARED_ACTIVITY_TRANSPLANTED,
  SHARED_ACTIVITY_HARVESTED,
  SHARED_TRACKED_ACTIVITY_TYPES,
  TASK_PROGRESS_REJECTION_NOTE_PREFIX,
  normalizeLedgerWorkDate,
  normalizeProductionLedgerActivityType,
  resolveLedgerActivityTargetsFromPlan,
  resolveLedgerActivityUnitsFromPlan,
  resolveLedgerUnitType,
  isTaskProgressRejected,
  isTaskProgressCountedInSharedLedger,
  resolveTaskProgressUnitContribution,
  resolveTaskProgressActivityQuantity,
  resolveTaskProgressActivityType,
  aggregateProductionTaskDayLedger,
  recomputeProductionTaskDayLedger,
  buildEmptyTrackedActivityTargets,
  buildEmptyTrackedActivityTotals,
  buildEmptyTrackedActivityUnits,
};
