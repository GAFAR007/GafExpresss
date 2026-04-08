/**
 * services/production_draft_presence_socket.service.js
 * -----------------------------------------------------
 * WHAT:
 * - Socket.IO handlers for live production draft presence.
 *
 * WHY:
 * - Lets the draft editor show who is currently viewing the same plan.
 * - Keeps live-collaboration state out of controllers and REST payloads.
 *
 * HOW:
 * - Authenticates sockets with the existing JWT token.
 * - Resolves the user + staff role from MongoDB.
 * - Joins plan-specific draft rooms and broadcasts the active viewer list.
 */

const jwt = require("jsonwebtoken");
const debug = require("../utils/debug");
const ProductionPlan = require("../models/ProductionPlan");
const {
  resolveBusinessContext,
  resolveStaffProfile,
} = require("./business_context.service");
const {
  PRODUCTION_DRAFT_PRESENCE_EVENTS,
  PRODUCTION_DRAFT_PRESENCE_ROOM_PREFIX,
} = require("../utils/production_draft_presence.constants");

// WHY: Store the active Socket.IO instance so we can broadcast snapshots.
let socketServer = null;

// WHY: Keep draft presence logs easy to grep.
const LOG_TAG = "PRODUCTION_DRAFT_PRESENCE";

function parseSocketToken(socket) {
  const authToken = socket?.handshake?.auth?.token;
  const headerToken = socket?.handshake?.headers?.authorization;
  const candidate = authToken || headerToken || "";
  if (candidate.startsWith("Bearer ")) {
    return candidate.replace("Bearer ", "").trim();
  }
  return candidate.trim();
}

function verifySocketToken(token) {
  return jwt.verify(token, process.env.JWT_SECRET);
}

function emitSocketError(socket, message) {
  socket.emit(PRODUCTION_DRAFT_PRESENCE_EVENTS.ERROR, {
    message,
  });
}

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

function buildDisplayName(user) {
  const structuredName = [
    user?.firstName,
    user?.middleName,
    user?.lastName,
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
    typeof user?.name === "string" ? user.name.trim() : "";
  if (fallbackName) {
    return fallbackName;
  }

  return typeof user?.email === "string"
    ? user.email.trim()
    : "Unknown user";
}

function buildViewerSummary({ actor, staffProfile }) {
  const accountRole = normalizeRoleKey(actor?.role);
  const staffRole = normalizeRoleKey(staffProfile?.staffRole);
  const displayRoleKey =
    accountRole === "staff" && staffRole ? staffRole : accountRole;

  return {
    userId: actor?._id?.toString() || "",
    displayName: buildDisplayName(actor),
    email: typeof actor?.email === "string" ? actor.email.trim() : "",
    accountRole,
    staffRole: staffRole || null,
    displayRoleKey,
    displayRoleLabel: humanizeLabel(displayRoleKey),
  };
}

function getDraftRoomId(planId) {
  return `${PRODUCTION_DRAFT_PRESENCE_ROOM_PREFIX}${planId}`;
}

async function resolveSocketViewer(socket) {
  const token = parseSocketToken(socket);
  if (!token) {
    throw new Error("Authentication required");
  }

  let decoded;
  try {
    decoded = verifySocketToken(token);
  } catch (error) {
    debug(LOG_TAG, {
      step: "AUTH_FAIL",
      reason: "invalid_token",
      error: error?.message,
    });
    throw new Error("Invalid authentication token");
  }

  const context = {
    route: "socket:draft:presence:connect",
    requestId: socket.id,
    userRole: decoded.role,
    operation: "DraftPresenceConnect",
    intent: "resolve draft viewer identity",
  };

  const { actor, businessId } = await resolveBusinessContext(
    decoded.sub,
    context,
  );
  const staffProfile = await resolveStaffProfile(
    {
      actor,
      businessId,
      allowMissing: true,
    },
    context,
  );

  return {
    actor,
    businessId,
    staffProfile,
    viewer: buildViewerSummary({ actor, staffProfile }),
  };
}

async function collectRoomViewers(roomId) {
  if (!socketServer) {
    return [];
  }

  const sockets = await socketServer.in(roomId).fetchSockets();
  const viewersByUserId = new Map();

  for (const participant of sockets) {
    const viewer = participant.data?.viewer;
    if (!viewer || !viewer.userId) {
      continue;
    }
    viewersByUserId.set(viewer.userId, viewer);
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

async function emitPresenceSnapshot(planId) {
  if (!socketServer) {
    return;
  }

  const normalizedPlanId = (planId || "").toString().trim();
  if (!normalizedPlanId) {
    return;
  }

  const roomId = getDraftRoomId(normalizedPlanId);
  const viewers = await collectRoomViewers(roomId);

  socketServer.to(roomId).emit(
    PRODUCTION_DRAFT_PRESENCE_EVENTS.UPDATE,
    {
      planId: normalizedPlanId,
      roomId,
      viewers,
      viewerCount: viewers.length,
      updatedAt: new Date().toISOString(),
    },
  );
}

async function validateDraftPlanAccess({ planId, businessId }) {
  const normalizedPlanId = (planId || "").toString().trim();
  if (!normalizedPlanId) {
    throw new Error("Plan id is required");
  }

  const plan = await ProductionPlan.findOne({
    _id: normalizedPlanId,
    businessId,
  }).select("_id businessId");

  if (!plan) {
    throw new Error("Draft plan not found");
  }

  return plan;
}

function registerDraftPresenceSocket(io) {
  socketServer = io;

  io.on("connection", async (socket) => {
    try {
      const viewerContext = await resolveSocketViewer(socket);
      socket.data.viewer = viewerContext.viewer;
      socket.data.businessId = viewerContext.businessId;
      socket.data.joinedDraftPlanIds = new Set();

      debug(LOG_TAG, {
        step: "AUTH_OK",
        userId: viewerContext.viewer.userId,
        role: viewerContext.viewer.displayRoleKey,
      });
    } catch (error) {
      debug(LOG_TAG, {
        step: "AUTH_FAIL",
        reason: error?.message,
      });
      emitSocketError(socket, error?.message || "Authentication required");
      socket.disconnect();
      return;
    }

    socket.on(
      PRODUCTION_DRAFT_PRESENCE_EVENTS.JOIN,
      async (payload) => {
        const planId = (payload?.planId || "").toString().trim();
        if (!planId) {
          emitSocketError(socket, "Plan id is required");
          return;
        }

        try {
          await validateDraftPlanAccess({
            planId,
            businessId: socket.data.businessId,
          });

          const roomId = getDraftRoomId(planId);
          socket.join(roomId);
          socket.data.joinedDraftPlanIds.add(planId);

          debug(LOG_TAG, {
            step: "JOIN_OK",
            planId,
            userId: socket.data.viewer?.userId,
            role: socket.data.viewer?.displayRoleKey,
          });

          await emitPresenceSnapshot(planId);
        } catch (error) {
          debug(LOG_TAG, {
            step: "JOIN_FAIL",
            planId,
            userId: socket.data.viewer?.userId,
            reason: error?.message,
          });
          emitSocketError(
            socket,
            "Access denied for this draft plan",
          );
        }
      },
    );

    socket.on(
      PRODUCTION_DRAFT_PRESENCE_EVENTS.LEAVE,
      async (payload) => {
        const planId = (payload?.planId || "").toString().trim();
        if (!planId) {
          emitSocketError(socket, "Plan id is required");
          return;
        }

        const roomId = getDraftRoomId(planId);
        socket.leave(roomId);
        socket.data.joinedDraftPlanIds.delete(planId);

        debug(LOG_TAG, {
          step: "LEAVE_OK",
          planId,
          userId: socket.data.viewer?.userId,
        });

        await emitPresenceSnapshot(planId);
      },
    );

    socket.on("disconnect", async () => {
      const planIds = Array.from(
        socket.data.joinedDraftPlanIds || [],
      );
      if (planIds.length === 0) {
        return;
      }

      for (const planId of planIds) {
        await emitPresenceSnapshot(planId);
      }
    });
  });
}

module.exports = {
  registerDraftPresenceSocket,
};
