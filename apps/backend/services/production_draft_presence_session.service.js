/**
 * apps/backend/services/production_draft_presence_session.service.js
 * -------------------------------------------------------------------
 * WHAT:
 * - Persistence and reporting helpers for draft room presence sessions.
 *
 * WHY:
 * - Tracks when a user enters/leaves a draft room.
 * - Lets the UI show current, daily, monthly, and yearly room time.
 *
 * HOW:
 * - Stores open sessions in MongoDB with a single active row per user/plan.
 * - Reuses closed sessions to build historical duration rollups.
 */

const ProductionDraftPresenceSession = require("../models/ProductionDraftPresenceSession");
const {
  PRODUCTION_DRAFT_PRESENCE_ROOM_PREFIX,
} = require("../utils/production_draft_presence.constants");

const MS_PER_SECOND = 1000;

function normalizeRoleKey(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/-/g, "_")
    .replace(/\s+/g, "_");
}

function humanizeLabel(value) {
  const normalized = normalizeRoleKey(value);
  if (!normalized) {
    return "";
  }

  return normalized
    .split("_")
    .filter(Boolean)
    .map(
      (segment) =>
        segment[0].toUpperCase() + segment.slice(1),
    )
    .join(" ");
}

function buildDisplayName(viewer) {
  const structuredName = [
    viewer?.firstName,
    viewer?.middleName,
    viewer?.lastName,
  ]
    .map((value) =>
      typeof value === "string" ? value.trim() : "",
    )
    .filter(Boolean)
    .join(" ")
    .trim();

  if (structuredName) {
    return structuredName;
  }

  const fallbackName =
    typeof viewer?.name === "string" ? viewer.name.trim() : "";
  if (fallbackName) {
    return fallbackName;
  }

  return typeof viewer?.email === "string"
    ? viewer.email.trim()
    : "Unknown user";
}

function getDraftRoomId(planId) {
  const normalizedPlanId = (planId || "").toString().trim();
  if (!normalizedPlanId) {
    return "";
  }
  return `${PRODUCTION_DRAFT_PRESENCE_ROOM_PREFIX}${normalizedPlanId}`;
}

function toUtcDayKey(value) {
  return value.toISOString().slice(0, 10);
}

function toUtcMonthKey(value) {
  return value.toISOString().slice(0, 7);
}

function toUtcYearKey(value) {
  return value.toISOString().slice(0, 4);
}

function startOfNextUtcDay(value) {
  const next = new Date(value);
  next.setUTCHours(0, 0, 0, 0);
  next.setUTCDate(next.getUTCDate() + 1);
  return next;
}

function createEmptyBucketMap() {
  return Object.create(null);
}

function addSeconds(map, key, seconds) {
  if (!key || seconds <= 0) {
    return;
  }
  map[key] = (map[key] || 0) + seconds;
}

function accumulateInterval(buckets, start, end) {
  const safeStart = new Date(start);
  const safeEnd = new Date(end);
  if (Number.isNaN(safeStart.getTime()) || Number.isNaN(safeEnd.getTime())) {
    return;
  }

  if (safeEnd <= safeStart) {
    return;
  }

  let cursor = new Date(safeStart);
  while (cursor < safeEnd) {
    const boundary = startOfNextUtcDay(cursor);
    const segmentEnd = boundary < safeEnd ? boundary : safeEnd;
    const seconds = Math.max(
      0,
      Math.floor((segmentEnd.getTime() - cursor.getTime()) / MS_PER_SECOND),
    );

    if (seconds > 0) {
      const dayKey = toUtcDayKey(cursor);
      addSeconds(buckets.dailySeconds, dayKey, seconds);
      addSeconds(buckets.monthlySeconds, toUtcMonthKey(cursor), seconds);
      addSeconds(buckets.yearlySeconds, toUtcYearKey(cursor), seconds);
      buckets.totalSeconds += seconds;
    }

    if (segmentEnd.getTime() <= cursor.getTime()) {
      break;
    }
    cursor = segmentEnd;
  }
}

function createDurationBuckets() {
  return {
    totalSeconds: 0,
    dailySeconds: createEmptyBucketMap(),
    monthlySeconds: createEmptyBucketMap(),
    yearlySeconds: createEmptyBucketMap(),
  };
}

function toSessionTimeSummary(session, now) {
  const enteredAt = session?.enteredAt ? new Date(session.enteredAt) : null;
  const leftAt = session?.leftAt ? new Date(session.leftAt) : null;
  const intervalEnd = leftAt || now;
  const currentSessionSeconds = enteredAt
    ? Math.max(
        0,
        Math.floor((intervalEnd.getTime() - enteredAt.getTime()) / MS_PER_SECOND),
      )
    : 0;

  return {
    enteredAt: enteredAt ? enteredAt.toISOString() : null,
    lastSeenAt: session?.lastSeenAt
      ? new Date(session.lastSeenAt).toISOString()
      : null,
    leftAt: leftAt ? leftAt.toISOString() : null,
    activeSocketCount: Math.max(
      0,
      Math.floor(Number(session?.activeSocketCount || 0)),
    ),
    currentSessionSeconds,
    durationSeconds: Math.max(
      0,
      Math.floor(Number(session?.durationSeconds || currentSessionSeconds)),
    ),
    roomId: session?.roomId || "",
  };
}

function buildViewerPresenceSummary(sessions, now = new Date()) {
  const buckets = createDurationBuckets();
  const orderedSessions = Array.isArray(sessions)
    ? [...sessions].sort((left, right) => {
        const leftEntered = new Date(left.enteredAt || 0).getTime();
        const rightEntered = new Date(right.enteredAt || 0).getTime();
        return rightEntered - leftEntered;
      })
    : [];

  for (const session of orderedSessions) {
    const enteredAt = session?.enteredAt ? new Date(session.enteredAt) : null;
    if (!enteredAt || Number.isNaN(enteredAt.getTime())) {
      continue;
    }

    const leftAt = session?.leftAt ? new Date(session.leftAt) : null;
    const intervalEnd = leftAt || now;
    if (Number.isNaN(intervalEnd.getTime()) || intervalEnd <= enteredAt) {
      continue;
    }

    accumulateInterval(buckets, enteredAt, intervalEnd);
  }

  const activeSession = orderedSessions.find((session) => !session.leftAt) || null;
  const latestSession = orderedSessions[0] || null;
  const sourceSession = activeSession || latestSession;
  const timeSummary = sourceSession ? toSessionTimeSummary(sourceSession, now) : null;
  const dayKey = toUtcDayKey(now);
  const monthKey = toUtcMonthKey(now);
  const yearKey = toUtcYearKey(now);

  return {
    enteredAt: timeSummary?.enteredAt || null,
    lastSeenAt: timeSummary?.lastSeenAt || null,
    leftAt: timeSummary?.leftAt || null,
    activeSocketCount: timeSummary?.activeSocketCount || 0,
    currentSessionSeconds: timeSummary?.currentSessionSeconds || 0,
    durationSeconds: timeSummary?.durationSeconds || 0,
    todaySeconds: buckets.dailySeconds[dayKey] || 0,
    monthSeconds: buckets.monthlySeconds[monthKey] || 0,
    yearSeconds: buckets.yearlySeconds[yearKey] || 0,
    totalSeconds: buckets.totalSeconds,
    sessionCount: orderedSessions.length,
  };
}

function buildViewerSummaryFromSession(session, presenceSummary) {
  const accountRole = normalizeRoleKey(session?.accountRole);
  const staffRole = normalizeRoleKey(session?.staffRole);
  const displayRoleKey =
    accountRole === "staff" && staffRole ? staffRole : accountRole;

  return {
    userId: session?.userId?.toString?.() || "",
    displayName: session?.displayName || session?.email || "Unknown user",
    email: session?.email || "",
    accountRole,
    staffRole: staffRole || null,
    displayRoleKey,
    displayRoleLabel: humanizeLabel(displayRoleKey),
    enteredAt: presenceSummary.enteredAt,
    lastSeenAt: presenceSummary.lastSeenAt,
    leftAt: presenceSummary.leftAt,
    activeSocketCount: presenceSummary.activeSocketCount,
    currentSessionSeconds: presenceSummary.currentSessionSeconds,
    durationSeconds: presenceSummary.durationSeconds,
    todaySeconds: presenceSummary.todaySeconds,
    monthSeconds: presenceSummary.monthSeconds,
    yearSeconds: presenceSummary.yearSeconds,
    totalSeconds: presenceSummary.totalSeconds,
    sessionCount: presenceSummary.sessionCount,
    roomId: session?.roomId || "",
  };
}

async function recordDraftPresenceJoin({
  businessId,
  planId,
  roomId,
  viewer,
  now = new Date(),
}) {
  const userId = viewer?.userId?.toString?.() || "";
  const normalizedBusinessId = (businessId || "").toString().trim();
  const normalizedPlanId = (planId || "").toString().trim();
  const normalizedRoomId = (roomId || getDraftRoomId(planId)).trim();

  if (
    !normalizedBusinessId ||
    !normalizedPlanId ||
    !userId ||
    !normalizedRoomId
  ) {
    return null;
  }

  return ProductionDraftPresenceSession.findOneAndUpdate(
    {
      businessId: normalizedBusinessId,
      planId: normalizedPlanId,
      userId,
      leftAt: null,
    },
    {
      $setOnInsert: {
        businessId: normalizedBusinessId,
        planId: normalizedPlanId,
        roomId: normalizedRoomId,
        userId,
        enteredAt: now,
        durationSeconds: 0,
        activeSocketCount: 0,
      },
      $set: {
        roomId: normalizedRoomId,
        displayName: buildDisplayName(viewer),
        email: typeof viewer?.email === "string" ? viewer.email.trim() : "",
        accountRole: normalizeRoleKey(viewer?.accountRole),
        staffRole: normalizeRoleKey(viewer?.staffRole),
        lastSeenAt: now,
        lastEventAt: now,
      },
      $inc: {
        activeSocketCount: 1,
      },
    },
    {
      new: true,
      upsert: true,
    },
  );
}

async function recordDraftPresenceLeave({
  businessId,
  planId,
  viewer,
  now = new Date(),
}) {
  const userId = viewer?.userId?.toString?.() || "";
  const normalizedBusinessId = (businessId || "").toString().trim();
  const normalizedPlanId = (planId || "").toString().trim();

  if (!normalizedBusinessId || !normalizedPlanId || !userId) {
    return null;
  }

  const viewerUpdate = {
    displayName: buildDisplayName(viewer),
    email: typeof viewer?.email === "string" ? viewer.email.trim() : "",
    accountRole: normalizeRoleKey(viewer?.accountRole),
    staffRole: normalizeRoleKey(viewer?.staffRole),
    lastSeenAt: now,
    lastEventAt: now,
  };

  const decremented = await ProductionDraftPresenceSession.findOneAndUpdate(
    {
      businessId: normalizedBusinessId,
      planId: normalizedPlanId,
      userId,
      leftAt: null,
      activeSocketCount: {
        $gt: 1,
      },
    },
    {
      $inc: {
        activeSocketCount: -1,
      },
      $set: viewerUpdate,
    },
    {
      new: true,
    },
  );

  if (decremented) {
    return decremented;
  }

  const openSession = await ProductionDraftPresenceSession.findOne({
    businessId: normalizedBusinessId,
    planId: normalizedPlanId,
    userId,
    leftAt: null,
  });

  if (!openSession) {
    return null;
  }

  openSession.activeSocketCount = 0;
  openSession.leftAt = now;
  openSession.lastSeenAt = now;
  openSession.lastEventAt = now;
  openSession.durationSeconds = Math.max(
    0,
    Math.floor(
      (now.getTime() - new Date(openSession.enteredAt).getTime()) /
        MS_PER_SECOND,
    ),
  );
  openSession.displayName = viewerUpdate.displayName;
  openSession.email = viewerUpdate.email;
  openSession.accountRole = viewerUpdate.accountRole;
  openSession.staffRole = viewerUpdate.staffRole;

  await openSession.save();
  return openSession;
}

async function loadActiveDraftPresenceViewers({
  businessId,
  planId,
  now = new Date(),
}) {
  const normalizedBusinessId = (businessId || "").toString().trim();
  const normalizedPlanId = (planId || "").toString().trim();

  if (!normalizedBusinessId || !normalizedPlanId) {
    return [];
  }

  const openSessions = await ProductionDraftPresenceSession.find({
    businessId: normalizedBusinessId,
    planId: normalizedPlanId,
    leftAt: null,
  })
    .sort({
      enteredAt: -1,
      updatedAt: -1,
    })
    .lean();

  if (openSessions.length === 0) {
    return [];
  }

  const sessions = await ProductionDraftPresenceSession.find({
    businessId: normalizedBusinessId,
    planId: normalizedPlanId,
    userId: {
      $in: openSessions.map((session) => session.userId),
    },
  })
    .sort({
      enteredAt: -1,
      updatedAt: -1,
    })
    .lean();

  const sessionsByUserId = new Map();
  for (const session of sessions) {
    const userId = session?.userId?.toString?.() || "";
    if (!userId) {
      continue;
    }

    const userSessions = sessionsByUserId.get(userId) || [];
    userSessions.push(session);
    sessionsByUserId.set(userId, userSessions);
  }

  const viewersByUserId = new Map();
  for (const session of openSessions) {
    const userId = session?.userId?.toString?.() || "";
    if (!userId || viewersByUserId.has(userId)) {
      continue;
    }

    const viewerSessions = sessionsByUserId.get(userId) || [session];
    const presenceSummary = buildViewerPresenceSummary(viewerSessions, now);
    viewersByUserId.set(
      userId,
      buildViewerSummaryFromSession(session, presenceSummary),
    );
  }

  return Array.from(viewersByUserId.values()).sort((left, right) => {
    const leftName = left.displayName || "";
    const rightName = right.displayName || "";
    const nameCompare = leftName.localeCompare(rightName);
    if (nameCompare !== 0) {
      return nameCompare;
    }
    return (left.userId || "").localeCompare(right.userId || "");
  });
}

module.exports = {
  buildActiveDraftPresenceViewers: loadActiveDraftPresenceViewers,
  buildDraftPresenceViewerSummary: buildViewerSummaryFromSession,
  buildViewerPresenceSummary,
  getDraftRoomId,
  recordDraftPresenceJoin,
  recordDraftPresenceLeave,
};
