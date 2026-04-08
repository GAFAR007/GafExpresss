/**
 * apps/backend/services/planner/scheduleBuilder.js
 * ------------------------------------------------
 * WHAT:
 * - Deterministically converts planner V2 semantic tasks into dated draft rows.
 *
 * WHY:
 * - AI must never produce the final calendar schedule.
 * - Draft preview and exports still need the legacy scheduled-task contract.
 *
 * HOW:
 * - Resolves a lifecycle-safe planning window.
 * - Allocates phase windows from lifecycle weights.
 * - Expands workload, recurring, and event tasks into row templates.
 * - Uses policy-aware block scheduling to assign final start/due timestamps.
 */

const debug = require("../../utils/debug");
const {
  DEFAULT_PHASE_DURATIONS,
  DEFAULT_THROUGHPUT,
  DEFAULT_EVENT_OCCURRENCE,
  DEFAULT_RECURRING_OFFSET_DAYS,
  DEFAULT_WORKLOAD_UNITS_PER_ROW,
} = require("./plannerDefaults");
const {
  expandRecurringTaskDates,
} = require("./expandRecurringTasks");

const MS_PER_MINUTE = 60000;
const MS_PER_HOUR = 60 * MS_PER_MINUTE;
const MS_PER_DAY = 86400000;
const WORK_SCHEDULE_FALLBACK_WEEK_DAYS = [
  1,
  2,
  3,
  4,
  5,
  6,
];
const WORK_SCHEDULE_FALLBACK_BLOCKS = [
  { start: "08:00", end: "12:00" },
  { start: "14:00", end: "17:00" },
];
const WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES = 30;
const WORK_SCHEDULE_FALLBACK_TIMEZONE = "Africa/Lagos";
const WORK_SCHEDULE_MIN_SLOT_MINUTES = 15;
const WORK_SCHEDULE_MAX_SLOT_MINUTES = 240;
const DEFAULT_ACTIVE_STAFF_PERCENT = 100;
const WORKLOAD_COMPLETION_WINDOW_EXTENDED_WARNING_CODE =
  "WORKLOAD_COMPLETION_WINDOW_EXTENDED";

function startOfDayLocal(date) {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    0,
    0,
    0,
    0,
  );
}

function isStartOfDayTimestamp(value) {
  return (
    value.getHours() === 0 &&
    value.getMinutes() === 0 &&
    value.getSeconds() === 0 &&
    value.getMilliseconds() === 0
  );
}

function normalizeInclusiveRangeEnd(value) {
  if (!(value instanceof Date)) {
    return value;
  }
  if (!isStartOfDayTimestamp(value)) {
    return value;
  }
  return new Date(
    value.getTime() + MS_PER_DAY - 1,
  );
}

function normalizeScheduleRangeBounds({
  phaseStart,
  phaseEnd,
}) {
  return {
    phaseStart: new Date(phaseStart),
    phaseEnd: normalizeInclusiveRangeEnd(
      new Date(phaseEnd),
    ),
  };
}

function buildDefaultSchedulePolicy() {
  return {
    workWeekDays: [...WORK_SCHEDULE_FALLBACK_WEEK_DAYS],
    blocks: WORK_SCHEDULE_FALLBACK_BLOCKS.map((block) => ({
      ...block,
    })),
    minSlotMinutes:
      WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES,
    timezone: WORK_SCHEDULE_FALLBACK_TIMEZONE,
  };
}

function parseTimeBlockClock(value) {
  const raw = (value || "").toString().trim();
  const match = /^(\d{2}):(\d{2})$/.exec(raw);
  if (!match) {
    return null;
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return {
    raw: `${match[1]}:${match[2]}`,
    hour,
    minute,
    totalMinutes: hour * 60 + minute,
  };
}

function normalizeSchedulePolicyInput(rawPolicy) {
  const source =
    rawPolicy && typeof rawPolicy === "object" ?
      rawPolicy
    : {};
  const basePolicy = buildDefaultSchedulePolicy();
  const workWeekDays = Array.from(
    new Set(
      (Array.isArray(source.workWeekDays) ? source.workWeekDays : [])
        .map((day) => Number(day))
        .filter(
          (day) =>
            Number.isInteger(day) && day >= 1 && day <= 7,
        ),
    ),
  ).sort((left, right) => left - right);
  const blocks = (Array.isArray(source.blocks) ? source.blocks : [])
    .map((block) => ({
      start: parseTimeBlockClock(block?.start)?.raw,
      end: parseTimeBlockClock(block?.end)?.raw,
    }))
    .filter(
      (block) =>
        block.start &&
        block.end &&
        parseTimeBlockClock(block.end).totalMinutes >
          parseTimeBlockClock(block.start).totalMinutes,
    );

  return {
    workWeekDays:
      workWeekDays.length > 0 ?
        workWeekDays
      : basePolicy.workWeekDays,
    blocks: blocks.length > 0 ? blocks : basePolicy.blocks,
    minSlotMinutes: Math.max(
      WORK_SCHEDULE_MIN_SLOT_MINUTES,
      Math.min(
        WORK_SCHEDULE_MAX_SLOT_MINUTES,
        Number(
          source.minSlotMinutes ||
            basePolicy.minSlotMinutes,
        ) || WORK_SCHEDULE_FALLBACK_MIN_SLOT_MINUTES,
      ),
    ),
    timezone:
      (source.timezone || basePolicy.timezone)
        .toString()
        .trim() || WORK_SCHEDULE_FALLBACK_TIMEZONE,
  };
}

function resolveWeekDayNumber(date) {
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

function buildPhaseWorkBlocks({
  phaseStart,
  phaseEnd,
  schedulePolicy,
}) {
  const {
    phaseStart: normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart,
    phaseEnd,
  });
  const effectivePolicy =
    normalizeSchedulePolicyInput(schedulePolicy);
  const workDaySet = new Set(
    effectivePolicy.workWeekDays,
  );
  const parsedBlocks = effectivePolicy.blocks
    .map((block) => {
      const parsedStart =
        parseTimeBlockClock(block?.start);
      const parsedEnd =
        parseTimeBlockClock(block?.end);
      if (
        !parsedStart ||
        !parsedEnd ||
        parsedEnd.totalMinutes <= parsedStart.totalMinutes
      ) {
        return null;
      }
      return {
        startHour: parsedStart.hour,
        startMinute: parsedStart.minute,
        endHour: parsedEnd.hour,
        endMinute: parsedEnd.minute,
      };
    })
    .filter(Boolean);
  const blocks = [];
  const cursor = startOfDayLocal(normalizedPhaseStart);
  const finalDay = startOfDayLocal(normalizedPhaseEnd);

  while (cursor <= finalDay) {
    if (!workDaySet.has(resolveWeekDayNumber(cursor))) {
      cursor.setDate(cursor.getDate() + 1);
      continue;
    }

    parsedBlocks.forEach((template) => {
      const blockStart = new Date(
        cursor.getFullYear(),
        cursor.getMonth(),
        cursor.getDate(),
        template.startHour,
        template.startMinute,
        0,
        0,
      );
      const blockEnd = new Date(
        cursor.getFullYear(),
        cursor.getMonth(),
        cursor.getDate(),
        template.endHour,
        template.endMinute,
        0,
        0,
      );
      const start = new Date(
        Math.max(
          blockStart.getTime(),
          normalizedPhaseStart.getTime(),
        ),
      );
      const end = new Date(
        Math.min(
          blockEnd.getTime(),
          normalizedPhaseEnd.getTime(),
        ),
      );
      const remainingMs = end.getTime() - start.getTime();
      if (remainingMs > 0) {
        blocks.push({
          start,
          end,
          remainingMs,
        });
      }
    });
    cursor.setDate(cursor.getDate() + 1);
  }

  return blocks;
}

function allocateTaskDurationsByWeight({
  safeWeights,
  totalAvailableMs,
  minTaskSlotMs,
}) {
  if (safeWeights.length === 0) {
    return [];
  }
  const minimumRequiredMs =
    safeWeights.length * minTaskSlotMs;
  if (minimumRequiredMs > totalAvailableMs) {
    return null;
  }
  const totalWeight = safeWeights.reduce(
    (sum, value) => sum + value,
    0,
  );
  const durations = safeWeights.map((weight) =>
    Math.max(
      minTaskSlotMs,
      Math.floor(
        (totalAvailableMs * weight) /
          Math.max(1, totalWeight),
      ),
    ),
  );
  let allocatedMs = durations.reduce(
    (sum, value) => sum + value,
    0,
  );
  let overflowMs = allocatedMs - totalAvailableMs;
  while (overflowMs > 0) {
    let reduced = false;
    for (
      let index = durations.length - 1;
      index >= 0 && overflowMs > 0;
      index -= 1
    ) {
      const reducibleMs = Math.max(
        0,
        durations[index] - minTaskSlotMs,
      );
      if (reducibleMs <= 0) {
        continue;
      }
      const reduceBy = Math.min(
        reducibleMs,
        overflowMs,
      );
      durations[index] -= reduceBy;
      overflowMs -= reduceBy;
      reduced = true;
    }
    if (!reduced) {
      return null;
    }
  }
  allocatedMs = durations.reduce(
    (sum, value) => sum + value,
    0,
  );
  if (allocatedMs < totalAvailableMs) {
    durations[durations.length - 1] +=
      totalAvailableMs - allocatedMs;
  }
  return durations;
}

function buildTaskScheduleLegacy({
  phaseStart,
  phaseEnd,
  tasks,
}) {
  const {
    phaseStart: normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart,
    phaseEnd,
  });
  const totalMs =
    normalizedPhaseEnd.getTime() -
    normalizedPhaseStart.getTime();
  const safeWeights = tasks.map((task) =>
    Math.max(1, Math.floor(Number(task.weight || 1))),
  );
  const totalWeight = safeWeights.reduce(
    (sum, value) => sum + value,
    0,
  );
  const baseUnitMs =
    totalWeight > 0 ? totalMs / totalWeight : totalMs;
  let cursor = new Date(normalizedPhaseStart);

  return tasks.map((task, index) => {
    const isLast = index === tasks.length - 1;
    const durationMs = isLast ?
      normalizedPhaseEnd.getTime() - cursor.getTime()
    : Math.floor(baseUnitMs * safeWeights[index]);
    const startDate = new Date(cursor);
    const dueDate = new Date(
      cursor.getTime() + durationMs,
    );
    cursor = new Date(dueDate);
    return {
      ...task,
      weight: safeWeights[index],
      startDate,
      dueDate,
    };
  });
}

function scheduleTasksAcrossBlocks({
  tasks,
  taskDurations,
  safeWeights,
  blocks,
  phaseStart,
  phaseEnd,
}) {
  let blockIndex = 0;
  let blockOffsetMs = 0;
  return tasks.map((task, taskIndex) => {
    let remainingTaskMs = taskDurations[taskIndex];
    let taskStartMs = null;
    let taskEndMs = null;

    while (remainingTaskMs > 0) {
      while (
        blockIndex < blocks.length &&
        blockOffsetMs >= blocks[blockIndex].remainingMs
      ) {
        blockIndex += 1;
        blockOffsetMs = 0;
      }
      if (blockIndex >= blocks.length) {
        break;
      }
      const block = blocks[blockIndex];
      const chunkStartMs =
        block.start.getTime() + blockOffsetMs;
      const blockRemainingMs =
        block.remainingMs - blockOffsetMs;
      const chunkMs = Math.min(
        remainingTaskMs,
        blockRemainingMs,
      );
      if (taskStartMs == null) {
        taskStartMs = chunkStartMs;
      }
      taskEndMs = chunkStartMs + chunkMs;
      remainingTaskMs -= chunkMs;
      blockOffsetMs += chunkMs;
    }

    const fallbackStartMs = phaseStart.getTime();
    const fallbackEndMs = phaseEnd.getTime();
    const startDate = new Date(
      Math.max(
        fallbackStartMs,
        taskStartMs ?? fallbackStartMs,
      ),
    );
    const dueDate = new Date(
      Math.max(
        startDate.getTime(),
        Math.min(
          fallbackEndMs,
          taskEndMs ?? fallbackEndMs,
        ),
      ),
    );
    return {
      ...task,
      weight: safeWeights[taskIndex],
      startDate,
      dueDate,
    };
  });
}

function buildTaskSchedule({
  phaseStart,
  phaseEnd,
  tasks,
  schedulePolicy,
}) {
  const {
    phaseStart: normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  } = normalizeScheduleRangeBounds({
    phaseStart,
    phaseEnd,
  });
  const blocks = buildPhaseWorkBlocks({
    phaseStart: normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
    schedulePolicy,
  });
  const totalAvailableMs = blocks.reduce(
    (sum, block) => sum + Number(block.remainingMs || 0),
    0,
  );
  const safeWeights = tasks.map((task) =>
    Math.max(1, Math.floor(Number(task.weight || 1))),
  );
  const minTaskSlotMs =
    normalizeSchedulePolicyInput(schedulePolicy).minSlotMinutes *
    MS_PER_MINUTE;
  const durations = allocateTaskDurationsByWeight({
    safeWeights,
    totalAvailableMs,
    minTaskSlotMs,
  });
  if (!blocks.length || totalAvailableMs <= 0 || !durations) {
    return buildTaskScheduleLegacy({
      phaseStart: normalizedPhaseStart,
      phaseEnd: normalizedPhaseEnd,
      tasks,
    });
  }
  return scheduleTasksAcrossBlocks({
    tasks,
    taskDurations: durations,
    safeWeights,
    blocks,
    phaseStart: normalizedPhaseStart,
    phaseEnd: normalizedPhaseEnd,
  });
}

function toIsoDate(value) {
  return new Date(value).toISOString().slice(0, 10);
}

function formatDayKey(value) {
  const date = new Date(value);
  return `${date.getFullYear()}-${`${date.getMonth() + 1}`.padStart(2, "0")}-${`${date.getDate()}`.padStart(2, "0")}`;
}

function resolvePlanningWindow({
  lifecycle,
  startDate,
  endDate,
}) {
  const todayUtc = new Date();
  const utcStart = new Date(
    Date.UTC(
      todayUtc.getUTCFullYear(),
      todayUtc.getUTCMonth(),
      todayUtc.getUTCDate(),
      0,
      0,
      0,
      0,
    ),
  );
  const targetDays = startDate && endDate ?
    Math.max(
      1,
      Math.floor(
        (startOfDayLocal(endDate).getTime() -
          startOfDayLocal(startDate).getTime()) /
          MS_PER_DAY,
      ) + 1,
    )
  : lifecycle.maxDays;

  let resolvedStart = startDate ? new Date(startDate) : null;
  let resolvedEnd = endDate ? new Date(endDate) : null;
  if (!resolvedStart && !resolvedEnd) {
    resolvedStart = utcStart;
    resolvedEnd = new Date(
      utcStart.getTime() + (targetDays - 1) * MS_PER_DAY,
    );
  } else if (resolvedStart && !resolvedEnd) {
    resolvedEnd = new Date(
      resolvedStart.getTime() + (targetDays - 1) * MS_PER_DAY,
    );
  } else if (!resolvedStart && resolvedEnd) {
    resolvedStart = new Date(
      resolvedEnd.getTime() - (targetDays - 1) * MS_PER_DAY,
    );
  }

  return {
    startDate: resolvedStart,
    endDate: resolvedEnd,
    days: Math.max(
      1,
      Math.floor(
        (startOfDayLocal(resolvedEnd).getTime() -
          startOfDayLocal(resolvedStart).getTime()) /
          MS_PER_DAY,
      ) + 1,
    ),
    weeks: Math.max(
      1,
      Math.ceil(
        (
          Math.floor(
            (startOfDayLocal(resolvedEnd).getTime() -
              startOfDayLocal(resolvedStart).getTime()) /
              MS_PER_DAY,
          ) + 1
        ) / 7,
      ),
    ),
  };
}

function allocatePhaseWindowDays({
  phaseNames,
  targetDays,
}) {
  const weights = phaseNames.map(
    (phaseName) =>
      DEFAULT_PHASE_DURATIONS[phaseName] || 7,
  );
  const totalWeight = weights.reduce(
    (sum, value) => sum + value,
    0,
  );
  const provisional = weights.map((weight) =>
    Math.max(
      1,
      Math.floor((targetDays * weight) / Math.max(1, totalWeight)),
    ),
  );
  let allocated = provisional.reduce(
    (sum, value) => sum + value,
    0,
  );
  let cursor = 0;
  while (allocated < targetDays) {
    provisional[cursor % provisional.length] += 1;
    allocated += 1;
    cursor += 1;
  }
  while (allocated > targetDays) {
    const index = provisional.findIndex((value) => value > 1);
    if (index < 0) {
      break;
    }
    provisional[index] -= 1;
    allocated -= 1;
  }
  return provisional;
}

function buildPhaseWindows({
  phases,
  planningWindow,
}) {
  const allocatedDays = allocatePhaseWindowDays({
    phaseNames: phases.map((phase) => phase.phaseName),
    targetDays: planningWindow.days,
  });
  let cursor = new Date(planningWindow.startDate);
  return phases.map((phase, index) => {
    const phaseStart = new Date(cursor);
    const phaseEnd = new Date(
      cursor.getTime() + (allocatedDays[index] - 1) * MS_PER_DAY,
    );
    cursor = new Date(phaseEnd.getTime() + MS_PER_DAY);
    return {
      ...phase,
      order: index + 1,
      estimatedDays: allocatedDays[index],
      biologicalMinDays: allocatedDays[index],
      startDate: phaseStart,
      endDate: phaseEnd,
    };
  });
}

function resolveRoleCapacity(capacitySummary, roleRequired) {
  const roleEntry =
    capacitySummary?.roles?.[roleRequired] || {};
  return Math.max(
    1,
    Number(roleEntry.available || roleEntry.total || 1),
  );
}

function toPositiveInteger(value, fallback = 0) {
  const parsed = Math.floor(Number(value || 0));
  return parsed > 0 ? parsed : fallback;
}

function resolveExpectedActivePercent(workloadContext) {
  const configuredPercent = Number(
    workloadContext?.expectedActivePercent ||
      workloadContext?.activeStaffAvailabilityPercent ||
      0,
  );
  if (configuredPercent <= 0) {
    return DEFAULT_ACTIVE_STAFF_PERCENT;
  }
  return Math.min(
    DEFAULT_ACTIVE_STAFF_PERCENT,
    Math.max(1, Math.floor(configuredPercent)),
  );
}

function resolveOptimizedWorkloadHeadcount({
  task,
  capacitySummary,
  workloadContext,
}) {
  const baselineHeadcount = Math.max(
    1,
    toPositiveInteger(task.requiredHeadcount, 1),
  );
  const configuredMinStaffPerUnit = toPositiveInteger(
    workloadContext?.minStaffPerUnit,
    0,
  );
  const configuredMaxStaffPerUnit = toPositiveInteger(
    workloadContext?.maxStaffPerUnit,
    0,
  );
  const safeMinStaffPerUnit =
    configuredMinStaffPerUnit > 0 ?
      configuredMinStaffPerUnit
    : baselineHeadcount;
  const safeMaxStaffPerUnit =
    configuredMaxStaffPerUnit > 0 ?
      Math.max(
        safeMinStaffPerUnit,
        configuredMaxStaffPerUnit,
      )
    : Math.max(
        safeMinStaffPerUnit,
        baselineHeadcount,
      );
  const roleCapacity = resolveRoleCapacity(
    capacitySummary,
    task.roleRequired,
  );
  const expectedActivePercent =
    resolveExpectedActivePercent(
      workloadContext,
    );
  const activeRoleCapacity = Math.max(
    1,
    Math.ceil(
      (roleCapacity * expectedActivePercent) /
        DEFAULT_ACTIVE_STAFF_PERCENT,
    ),
  );
  const desiredHeadcount =
    configuredMaxStaffPerUnit > 0 ?
      safeMaxStaffPerUnit
    : Math.max(
        safeMinStaffPerUnit,
        baselineHeadcount,
      );
  const optimizedHeadcount = Math.max(
    Math.min(
      activeRoleCapacity,
      safeMinStaffPerUnit,
    ),
    Math.min(
      activeRoleCapacity,
      desiredHeadcount,
    ),
  );

  return {
    baselineHeadcount,
    optimizedHeadcount,
    activeRoleCapacity,
    expectedActivePercent,
    configuredMinStaffPerUnit,
    configuredMaxStaffPerUnit,
  };
}

function resolveTaskThroughputPerDay({
  taskKey,
  roleRequired,
}) {
  const roleDefaults =
    DEFAULT_THROUGHPUT[roleRequired] ||
    DEFAULT_THROUGHPUT.farmer;
  return Math.max(
    1,
    Number(
      roleDefaults[taskKey] ||
        roleDefaults.default ||
        1,
    ),
  );
}

function buildWorkloadRows({
  phaseName,
  task,
  phaseStart,
  capacitySummary,
  workUnitLabel,
  workloadContext,
}) {
  const {
    baselineHeadcount,
    optimizedHeadcount,
    activeRoleCapacity,
    expectedActivePercent,
    configuredMinStaffPerUnit,
    configuredMaxStaffPerUnit,
  } = resolveOptimizedWorkloadHeadcount({
    task,
    capacitySummary,
    workloadContext,
  });
  if (optimizedHeadcount !== baselineHeadcount) {
    debug(
      "PLANNER_V2_SCHEDULE: workload headcount optimized",
      {
        intent:
          "increase finite workload staffing to configured bounds before row expansion",
        phaseName,
        taskKey: task.taskKey,
        roleRequired: task.roleRequired,
        baselineHeadcount,
        optimizedHeadcount,
        activeRoleCapacity,
        expectedActivePercent,
        configuredMinStaffPerUnit,
        configuredMaxStaffPerUnit,
      },
    );
  }
  const availableWorkers = Math.max(
    1,
    optimizedHeadcount,
  );
  const throughputPerWorkerPerDay =
    resolveTaskThroughputPerDay({
      taskKey: task.taskKey,
      roleRequired: task.roleRequired,
    });
  const dailyCoverageUnits = Math.max(
    DEFAULT_WORKLOAD_UNITS_PER_ROW,
    availableWorkers * throughputPerWorkerPerDay,
  );
  const durationDays = Math.max(
    1,
    Math.ceil(task.workloadUnits / dailyCoverageUnits),
  );
  const rows = [];
  let remainingUnits = task.workloadUnits;

  for (let index = 0; index < durationDays; index += 1) {
    const rowUnits = Math.max(
      DEFAULT_WORKLOAD_UNITS_PER_ROW,
      Math.min(dailyCoverageUnits, remainingUnits),
    );
    remainingUnits = Math.max(0, remainingUnits - rowUnits);
    rows.push({
      title: task.taskName,
      roleRequired: task.roleRequired,
      requiredHeadcount: availableWorkers,
      weight: 1,
      unitCoverage: rowUnits,
      instructions: [
        `${task.taskName} for ${rowUnits} ${workUnitLabel}.`,
        `Planner V2 workload expansion from ${task.workloadUnits} total ${workUnitLabel}.`,
      ].join(" "),
      taskType: task.taskType,
      sourceTemplateKey: task.taskKey,
      recurrenceGroupKey: task.taskKey,
      occurrenceIndex: index,
      assignedStaffProfileIds: [],
      plannedDayAnchor: new Date(
        phaseStart.getTime() + index * MS_PER_DAY,
      ),
    });
  }

  return rows;
}

function buildRecurringRows({
  task,
  phaseStart,
  phaseEnd,
}) {
  return expandRecurringTaskDates({
    phaseStart,
    phaseEnd,
    frequencyEveryDays: task.frequencyEveryDays,
    firstOccurrenceOffsetDays:
      task.firstOccurrenceOffsetDays ||
      DEFAULT_RECURRING_OFFSET_DAYS,
  }).map((occurrenceDate, index) => ({
    title: task.taskName,
    roleRequired: task.roleRequired,
    requiredHeadcount: task.requiredHeadcount,
    weight: 1,
    instructions:
      `${task.taskName} recurring cycle ${index + 1}.`,
    taskType: task.taskType,
    sourceTemplateKey: task.taskKey,
    recurrenceGroupKey: task.taskKey,
    occurrenceIndex: index,
    assignedStaffProfileIds: [],
    plannedDayAnchor: occurrenceDate,
  }));
}

function buildEventRows({
  task,
  phaseStart,
  phaseEnd,
}) {
  const occurrenceRatio =
    DEFAULT_EVENT_OCCURRENCE[task.occurrence] ?? 0.5;
  const totalDays = Math.max(
    1,
    Math.floor(
      (startOfDayLocal(phaseEnd).getTime() -
        startOfDayLocal(phaseStart).getTime()) /
        MS_PER_DAY,
    ) + 1,
  );
  const offsetDays = Math.max(
    0,
    Math.min(
      totalDays - 1,
      Math.floor((totalDays - 1) * occurrenceRatio),
    ),
  );
  return [
    {
      title: task.taskName,
      roleRequired: task.roleRequired,
      requiredHeadcount: task.requiredHeadcount,
      weight: 1,
      instructions:
        `${task.taskName} event task scheduled at ${task.occurrence}.`,
      taskType: task.taskType,
      sourceTemplateKey: task.taskKey,
      recurrenceGroupKey: task.taskKey,
      occurrenceIndex: 0,
      assignedStaffProfileIds: [],
      plannedDayAnchor: new Date(
        phaseStart.getTime() + offsetDays * MS_PER_DAY,
      ),
    },
  ];
}

function expandSemanticTasksForPhase({
  phaseName,
  tasks,
  phaseStart,
  phaseEnd,
  capacitySummary,
  workUnitLabel,
  workloadContext,
}) {
  return tasks.flatMap((task) => {
    if (task.taskType === "workload") {
      return buildWorkloadRows({
        phaseName,
        task,
        phaseStart,
        capacitySummary,
        workUnitLabel,
        workloadContext,
      });
    }
    if (task.taskType === "recurring") {
      return buildRecurringRows({
        task,
        phaseStart,
        phaseEnd,
      });
    }
    return buildEventRows({
      task,
      phaseStart,
      phaseEnd,
    });
  });
}

function summarizePlannerTasks(phases) {
  return phases.flatMap((phase) =>
    phase.tasks.map((task, index) => ({
      taskId: `${phase.order}_${index}`,
      title: task.title,
      phaseName: phase.name,
      phaseOrder: phase.order,
      phaseType: "finite",
      requiredUnits: Number(phase.requiredUnits || 0),
      roleRequired: task.roleRequired,
      requiredHeadcount: task.requiredHeadcount,
      assignedStaffProfileIds:
        task.assignedStaffProfileIds || [],
      assignedCount:
        (task.assignedStaffProfileIds || []).length,
      startDate: new Date(task.startDate).toISOString(),
      dueDate: new Date(task.dueDate).toISOString(),
      instructions: task.instructions || "",
      weight: task.weight || 1,
      taskType: task.taskType || "",
      sourceTemplateKey:
        task.sourceTemplateKey || "",
      recurrenceGroupKey:
        task.recurrenceGroupKey || "",
      occurrenceIndex:
        Number(task.occurrenceIndex || 0),
    })),
  );
}

function buildPlanningSummary({
  planningStartDate,
  planningEndDate,
  productId,
}) {
  const safeStart = startOfDayLocal(
    planningStartDate,
  );
  const safeEnd = startOfDayLocal(
    planningEndDate,
  );
  const days = Math.max(
    1,
    Math.floor(
      (safeEnd.getTime() - safeStart.getTime()) /
        MS_PER_DAY,
    ) + 1,
  );
  return {
    startDate: toIsoDate(safeStart),
    endDate: toIsoDate(safeEnd),
    days,
    weeks: Math.max(1, Math.ceil(days / 7)),
    monthApprox: Number((days / 30).toFixed(2)),
    productId: productId?.toString() || "",
    cropSubtype: "",
  };
}

function buildDraftSchedule({
  lifecycle,
  phases,
  tasksByPhase,
  schedulePolicy,
  capacitySummary,
  workloadContext = {},
  productId,
  productName,
  estateAssetId,
  startDate,
  endDate,
}) {
  const workUnitLabel =
    (workloadContext?.workUnitType || "plot")
      .toString()
      .trim() || "plot";
  const planningWindow = resolvePlanningWindow({
    lifecycle,
    startDate,
    endDate,
  });
  const phaseWindows = buildPhaseWindows({
    phases,
    planningWindow,
  });
  const draftPhases = phaseWindows.map((phaseWindow) => {
    const semanticTasks =
      tasksByPhase.get(phaseWindow.phaseName) || [];
    const expandedTasks = expandSemanticTasksForPhase({
      phaseName: phaseWindow.phaseName,
      tasks: semanticTasks,
      phaseStart: phaseWindow.startDate,
      phaseEnd: phaseWindow.endDate,
      capacitySummary,
      workUnitLabel,
      workloadContext,
    }).sort(
      (left, right) =>
        left.plannedDayAnchor.getTime() -
        right.plannedDayAnchor.getTime(),
    );
    const tasksByDay = new Map();
    expandedTasks.forEach((task) => {
      const dayKey = formatDayKey(
        task.plannedDayAnchor,
      );
      if (!tasksByDay.has(dayKey)) {
        tasksByDay.set(dayKey, []);
      }
      tasksByDay.get(dayKey).push(task);
    });
    const scheduledTasks = Array.from(
      tasksByDay.entries(),
    )
      .sort(([leftDay], [rightDay]) =>
        leftDay.localeCompare(rightDay),
      )
      .flatMap(([_, dayTasks]) => {
        const anchorDate =
          dayTasks[0]?.plannedDayAnchor ||
          phaseWindow.startDate;
        const dayStart = new Date(
          anchorDate.getFullYear(),
          anchorDate.getMonth(),
          anchorDate.getDate(),
          0,
          0,
          0,
          0,
        );
        const dayEnd = new Date(
          anchorDate.getFullYear(),
          anchorDate.getMonth(),
          anchorDate.getDate(),
          23,
          59,
          59,
          999,
        );
        return buildTaskSchedule({
          phaseStart: dayStart,
          phaseEnd: dayEnd,
          tasks: dayTasks,
          schedulePolicy,
        }).map((task) => ({
          ...task,
          startDate: new Date(task.startDate).toISOString(),
          dueDate: new Date(task.dueDate).toISOString(),
        }));
      });
    const requiredUnits = semanticTasks
      .filter((task) => task.taskType === "workload")
      .reduce(
        (sum, task) => sum + Number(task.workloadUnits || 0),
        0,
      );
    return {
      name: phaseWindow.phaseName,
      order: phaseWindow.order,
      estimatedDays: phaseWindow.estimatedDays,
      phaseType: "finite",
      requiredUnits,
      minRatePerFarmerHour: 0.1,
      targetRatePerFarmerHour: 0.2,
      plannedHoursPerDay: 3,
      biologicalMinDays: phaseWindow.biologicalMinDays,
      tasks: scheduledTasks,
    };
  });

  const warnings = [];
  if (!draftPhases.some((phase) => phase.tasks.length > 0)) {
    warnings.push({
      code: "NO_SCHEDULED_ROWS",
      message:
        "Planner V2 produced a valid structure but no concrete schedule rows.",
    });
  }

  const taskRows = summarizePlannerTasks(draftPhases);
  const latestScheduledDueDate =
    taskRows.length > 0 ?
      taskRows.reduce((latest, taskRow) => {
        const dueDate = new Date(
          taskRow.dueDate,
        );
        return dueDate.getTime() >
            latest.getTime() ?
            dueDate
          : latest;
      }, new Date(taskRows[0].dueDate))
    : null;
  const summaryEndDate =
    latestScheduledDueDate &&
    latestScheduledDueDate.getTime() >
      planningWindow.endDate.getTime() ?
      latestScheduledDueDate
    : planningWindow.endDate;
  if (
    latestScheduledDueDate &&
    latestScheduledDueDate.getTime() >
      planningWindow.endDate.getTime()
  ) {
    warnings.push({
      code:
        WORKLOAD_COMPLETION_WINDOW_EXTENDED_WARNING_CODE,
      message:
        "Timeline end date was extended to include all finite workload rows at the current staffing throughput.",
    });
  }
  const summary = buildPlanningSummary({
    planningStartDate: planningWindow.startDate,
    planningEndDate: summaryEndDate,
    productId,
  });
  debug(
    "PLANNER_V2_SCHEDULE: success",
    {
      intent:
        "expanded semantic planner output into dated draft rows",
      phaseCount: draftPhases.length,
      taskCount: taskRows.length,
      startDate: summary.startDate,
      endDate: summary.endDate,
    },
  );

  return {
    summary,
    draft: {
      estateAssetId: estateAssetId?.toString() || "",
      productId: productId?.toString() || "",
      productName: productName || "",
      startDate: summary.startDate,
      endDate: summary.endDate,
      phases: draftPhases,
    },
    phases: draftPhases,
    tasks: taskRows,
    warnings,
  };
}

module.exports = {
  buildDraftSchedule,
  resolvePlanningWindow,
};
