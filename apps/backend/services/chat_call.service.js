/**
 * services/chat_call.service.js
 * -----------------------------
 * WHAT:
 * - Chat call service for 1-to-1 in-app audio/video call sessions.
 *
 * WHY:
 * - Keeps call validation and state transitions out of controllers/sockets.
 * - Reuses the existing chat permission model while separating call lifecycle.
 *
 * HOW:
 * - Validates direct conversation membership.
 * - Persists ringing/active/terminal session state.
 * - Creates system chat messages for completed call events.
 */

const debug = require("../utils/debug");
const User = require("../models/User");
const ChatParticipant = require("../models/ChatParticipant");
const ChatCallSession = require("../models/ChatCallSession");
const chatService = require("./chat.service");
const {
  CHAT_CONVERSATION_TYPES,
  CHAT_MESSAGE_TYPES,
  CHAT_CALL_MEDIA_MODES,
  CHAT_CALL_STATES,
} = require("../utils/chat_constants");

const LOG_TAG = "CHAT_CALL_SERVICE";

const HTTP_STATUS = {
  BAD_REQUEST: 400,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
};

const ERROR_CODES = {
  CONVERSATION_REQUIRED: "CHAT_CALL_CONVERSATION_REQUIRED",
  CALL_NOT_FOUND: "CHAT_CALL_NOT_FOUND",
  CALL_FORBIDDEN: "CHAT_CALL_FORBIDDEN",
  CALL_CONFLICT: "CHAT_CALL_CONFLICT",
  DIRECT_ONLY: "CHAT_CALL_DIRECT_ONLY",
  PARTICIPANTS_INVALID: "CHAT_CALL_PARTICIPANTS_INVALID",
  MODE_INVALID: "CHAT_CALL_MODE_INVALID",
};

function buildCallError({
  message,
  classification,
  errorCode,
  resolutionHint,
  httpStatus,
  extra = {},
}) {
  const error = new Error(message);
  error.classification = classification;
  error.errorCode = errorCode;
  error.resolutionHint = resolutionHint;
  error.httpStatus = httpStatus;
  Object.assign(error, extra);
  return error;
}

function logStep(step, context = {}) {
  if (!context || (!context.requestId && !context.route)) {
    return;
  }

  debug(LOG_TAG, {
    step,
    requestId: context.requestId || "unknown",
    route: context.route || "unknown",
    userRole: context.userRole || "unknown",
    operation: context.operation || "ChatCallService",
    intent: context.intent || "chat_call_operation",
    ...context.extra,
  });
}

function resolveDisplayName(user) {
  const parts = [
    user?.firstName?.toString().trim() || "",
    user?.middleName?.toString().trim() || "",
    user?.lastName?.toString().trim() || "",
  ].filter(Boolean);
  if (parts.length > 0) {
    return parts.join(" ");
  }
  return (
    user?.name?.toString().trim() ||
    user?.email?.toString().trim() ||
    "User"
  );
}

function normalizeCallState(value) {
  return (value || "").toString().trim().toLowerCase();
}

function normalizeMediaMode(value) {
  const normalized = (value || "")
    .toString()
    .trim()
    .toLowerCase();
  if (!normalized) {
    return CHAT_CALL_MEDIA_MODES.AUDIO;
  }
  if (
    normalized !== CHAT_CALL_MEDIA_MODES.AUDIO &&
    normalized !== CHAT_CALL_MEDIA_MODES.VIDEO
  ) {
    throw buildCallError({
      message: "Unsupported call media mode",
      classification: "INVALID_INPUT",
      errorCode: ERROR_CODES.MODE_INVALID,
      resolutionHint: "Use audio for the current release.",
      httpStatus: HTTP_STATUS.BAD_REQUEST,
    });
  }
  return normalized;
}

async function loadUserMap(userIds) {
  const normalizedIds = [
    ...new Set(
      (userIds || [])
        .filter(Boolean)
        .map((id) => id.toString()),
    ),
  ];
  if (normalizedIds.length === 0) {
    return new Map();
  }

  const rows = await User.find({
    _id: { $in: normalizedIds },
  })
    .select(
      "name email firstName middleName lastName role profileImageUrl",
    )
    .lean();

  const map = new Map();
  rows.forEach((row) => {
    map.set(row._id.toString(), row);
  });
  return map;
}

async function serializeCallSession(callSession) {
  const call = callSession?.toObject
    ? callSession.toObject()
    : callSession;
  if (!call) {
    return null;
  }

  const userIds = [
    call.callerUserId,
    call.calleeUserId,
    call.endedByUserId,
  ];
  const userMap = await loadUserMap(userIds);
  const callerId = call.callerUserId?.toString() || "";
  const calleeId = call.calleeUserId?.toString() || "";
  const endedById = call.endedByUserId?.toString() || "";
  const caller = userMap.get(callerId) || null;
  const callee = userMap.get(calleeId) || null;
  const endedBy = userMap.get(endedById) || null;
  const answeredAt = call.answeredAt ? new Date(call.answeredAt) : null;
  const endedAt = call.endedAt ? new Date(call.endedAt) : null;
  const durationSeconds =
    answeredAt && endedAt
      ? Math.max(
          0,
          Math.round(
            (endedAt.getTime() - answeredAt.getTime()) / 1000,
          ),
        )
      : 0;

  return {
    _id: call._id?.toString() || "",
    conversationId: call.conversationId?.toString() || "",
    businessId: call.businessId?.toString() || "",
    mediaMode: call.mediaMode || CHAT_CALL_MEDIA_MODES.AUDIO,
    state: normalizeCallState(call.state),
    callerUserId: callerId,
    callerName: resolveDisplayName(caller),
    callerRole: caller?.role || "",
    callerProfileImageUrl:
      caller?.profileImageUrl?.toString() || "",
    calleeUserId: calleeId,
    calleeName: resolveDisplayName(callee),
    calleeRole: callee?.role || "",
    calleeProfileImageUrl:
      callee?.profileImageUrl?.toString() || "",
    ringTimeoutAt: call.ringTimeoutAt || null,
    answeredAt,
    endedAt,
    endedByUserId: endedById,
    endedByName: endedBy ? resolveDisplayName(endedBy) : "",
    endReason: (call.endReason || "").toString().trim(),
    durationSeconds,
    createdAt: call.createdAt || null,
    updatedAt: call.updatedAt || null,
  };
}

async function assertDirectConversationParticipant({
  actorId,
  conversationId,
  context,
}) {
  if (!conversationId) {
    throw buildCallError({
      message: "Conversation id is required",
      classification: "MISSING_REQUIRED_FIELD",
      errorCode: ERROR_CODES.CONVERSATION_REQUIRED,
      resolutionHint: "Provide a conversation id and retry.",
      httpStatus: HTTP_STATUS.BAD_REQUEST,
    });
  }

  const actor = await chatService.loadActor(
    actorId,
    context,
  );
  const access = await chatService.ensureConversationAccess({
    conversationId,
    userId: actor._id,
    actor,
    context,
  });
  const conversation = access.conversation;

  if (
    conversation?.type !== CHAT_CONVERSATION_TYPES.DIRECT
  ) {
    throw buildCallError({
      message:
        "Calls are available only for direct conversations",
      classification: "INVALID_INPUT",
      errorCode: ERROR_CODES.DIRECT_ONLY,
      resolutionHint:
        "Open a direct chat before starting a call.",
      httpStatus: HTTP_STATUS.BAD_REQUEST,
    });
  }

  const rows = await ChatParticipant.find({
    conversationId,
    isHidden: false,
  })
    .select("userId")
    .lean();

  const participantIds = [
    ...new Set(
      rows
        .map((row) => row.userId?.toString() || "")
        .filter(Boolean),
    ),
  ];

  if (participantIds.length !== 2) {
    throw buildCallError({
      message:
        "Calls require exactly two conversation participants",
      classification: "INVALID_INPUT",
      errorCode: ERROR_CODES.PARTICIPANTS_INVALID,
      resolutionHint:
        "Keep the conversation direct and retry.",
      httpStatus: HTTP_STATUS.BAD_REQUEST,
    });
  }

  const actorIdText = actor._id.toString();
  if (!participantIds.includes(actorIdText)) {
    throw buildCallError({
      message:
        "Only direct conversation participants can place calls",
      classification: "AUTHENTICATION_ERROR",
      errorCode: ERROR_CODES.CALL_FORBIDDEN,
      resolutionHint:
        "Join the conversation as a participant before calling.",
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }

  const calleeUserId =
    participantIds.find((id) => id !== actorIdText) || "";

  return {
    actor,
    conversation,
    participantIds,
    calleeUserId,
  };
}

async function loadAuthorizedCall({
  callId,
  userId,
  context,
}) {
  if (!callId) {
    throw buildCallError({
      message: "Call id is required",
      classification: "MISSING_REQUIRED_FIELD",
      errorCode: ERROR_CODES.CALL_NOT_FOUND,
      resolutionHint: "Provide a valid call id.",
      httpStatus: HTTP_STATUS.BAD_REQUEST,
    });
  }

  const call = await ChatCallSession.findById(callId);
  if (!call) {
    throw buildCallError({
      message: "Call session not found",
      classification: "NOT_FOUND",
      errorCode: ERROR_CODES.CALL_NOT_FOUND,
      resolutionHint:
        "Refresh the thread and retry the call action.",
      httpStatus: HTTP_STATUS.NOT_FOUND,
    });
  }

  const userIdText = userId?.toString() || "";
  const callerId = call.callerUserId?.toString() || "";
  const calleeId = call.calleeUserId?.toString() || "";
  if (userIdText !== callerId && userIdText !== calleeId) {
    throw buildCallError({
      message:
        "User is not allowed to access this call session",
      classification: "AUTHENTICATION_ERROR",
      errorCode: ERROR_CODES.CALL_FORBIDDEN,
      resolutionHint:
        "Only the caller or callee may control this call.",
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }

  logStep("CALL_ACCESS_OK", {
    ...context,
    extra: {
      callId,
      callerUserId: callerId,
      calleeUserId: calleeId,
      state: call.state,
    },
  });

  return call;
}

function formatDurationSeconds(seconds) {
  const normalized = Math.max(
    0,
    Number.parseInt(seconds, 10) || 0,
  );
  if (normalized < 60) {
    return `${normalized}s`;
  }
  const minutes = Math.floor(normalized / 60);
  const remainder = normalized % 60;
  if (remainder === 0) {
    return `${minutes}m`;
  }
  return `${minutes}m ${remainder}s`;
}

async function createCallSystemMessage({
  call,
  actor,
  eventType,
  body,
  context,
  eventData = {},
}) {
  return chatService.sendMessage({
    actor,
    businessId: call.businessId,
    conversationId: call.conversationId,
    body,
    attachmentIds: [],
    clientMessageId: "",
    context: {
      ...context,
      operation: "ChatCallSystemMessage",
      intent: "record call event",
    },
    messageType: CHAT_MESSAGE_TYPES.SYSTEM,
    eventType,
    eventData: {
      callId: call._id.toString(),
      mediaMode: call.mediaMode,
      ...eventData,
    },
  });
}

function buildCallConflict(existingCall) {
  return buildCallError({
    message:
      "Another call is already ringing or active for this conversation",
    classification: "CONFLICT",
    errorCode: ERROR_CODES.CALL_CONFLICT,
    resolutionHint:
      "Finish the current call before starting a new one.",
    httpStatus: HTTP_STATUS.CONFLICT,
    extra: {
      activeCall: existingCall || null,
    },
  });
}

async function startCall({
  actorId,
  conversationId,
  mediaMode,
  context,
}) {
  logStep("START_CALL_BEGIN", {
    ...context,
    extra: { conversationId, mediaMode },
  });

  const normalizedMode = normalizeMediaMode(mediaMode);
  const {
    actor,
    conversation,
    calleeUserId,
  } = await assertDirectConversationParticipant({
    actorId,
    conversationId,
    context,
  });

  const existing = await ChatCallSession.findOne({
    conversationId,
    state: {
      $in: [
        CHAT_CALL_STATES.RINGING,
        CHAT_CALL_STATES.ACTIVE,
      ],
    },
  })
    .sort({ createdAt: -1 });

  if (existing) {
    throw buildCallConflict(
      await serializeCallSession(existing),
    );
  }

  let createdCall;
  try {
    createdCall = await ChatCallSession.create({
      conversationId,
      businessId: conversation.businessId,
      mediaMode: normalizedMode,
      callerUserId: actor._id,
      calleeUserId,
      state: CHAT_CALL_STATES.RINGING,
      ringTimeoutAt: new Date(
        Date.now() + 45 * 1000,
      ),
    });
  } catch (error) {
    if (error?.code !== 11000) {
      throw error;
    }
    const duplicate = await ChatCallSession.findOne({
      conversationId,
      state: {
        $in: [
          CHAT_CALL_STATES.RINGING,
          CHAT_CALL_STATES.ACTIVE,
        ],
      },
    })
      .sort({ createdAt: -1 });
    throw buildCallConflict(
      await serializeCallSession(duplicate),
    );
  }

  const call = await serializeCallSession(createdCall);
  logStep("START_CALL_OK", {
    ...context,
    extra: {
      callId: call?._id || "",
      callerUserId: call?.callerUserId || "",
      calleeUserId: call?.calleeUserId || "",
    },
  });

  return {
    call,
    actor,
  };
}

async function getCall({
  callId,
  userId,
  context,
}) {
  const call = await loadAuthorizedCall({
    callId,
    userId,
    context,
  });
  return {
    call: await serializeCallSession(call),
  };
}

async function acceptCall({
  callId,
  userId,
  context,
}) {
  logStep("ACCEPT_CALL_BEGIN", {
    ...context,
    extra: { callId, userId },
  });

  const actor = await chatService.loadActor(
    userId,
    context,
  );
  const call = await loadAuthorizedCall({
    callId,
    userId,
    context,
  });

  if (
    call.calleeUserId?.toString() !== actor._id.toString()
  ) {
    throw buildCallError({
      message: "Only the callee can accept this call",
      classification: "AUTHENTICATION_ERROR",
      errorCode: ERROR_CODES.CALL_FORBIDDEN,
      resolutionHint:
        "Use the incoming call screen to answer this call.",
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }

  if (call.state === CHAT_CALL_STATES.ACTIVE) {
    return {
      call: await serializeCallSession(call),
      systemMessage: null,
    };
  }

  if (call.state !== CHAT_CALL_STATES.RINGING) {
    throw buildCallError({
      message: "Only ringing calls can be accepted",
      classification: "CONFLICT",
      errorCode: ERROR_CODES.CALL_CONFLICT,
      resolutionHint:
        "Refresh the thread and check the latest call state.",
      httpStatus: HTTP_STATUS.CONFLICT,
    });
  }

  call.state = CHAT_CALL_STATES.ACTIVE;
  call.answeredAt = new Date();
  call.endedAt = null;
  call.endedByUserId = null;
  call.endReason = "";
  await call.save();

  const systemMessage =
    await createCallSystemMessage({
      call,
      actor,
      eventType: "call_started",
      body: "Voice call started.",
      context,
      eventData: {
        answeredAt: call.answeredAt,
        answeredByUserId: actor._id.toString(),
      },
    });

  return {
    call: await serializeCallSession(call),
    systemMessage,
  };
}

async function declineCall({
  callId,
  userId,
  reason = "declined",
  context,
}) {
  logStep("DECLINE_CALL_BEGIN", {
    ...context,
    extra: { callId, userId, reason },
  });

  const normalizedReason =
    reason === "busy" ? "busy" : "declined";
  const actor = await chatService.loadActor(
    userId,
    context,
  );
  const call = await loadAuthorizedCall({
    callId,
    userId,
    context,
  });

  if (
    call.calleeUserId?.toString() !== actor._id.toString()
  ) {
    throw buildCallError({
      message: "Only the callee can decline this call",
      classification: "AUTHENTICATION_ERROR",
      errorCode: ERROR_CODES.CALL_FORBIDDEN,
      resolutionHint:
        "Use the incoming call screen to decline this call.",
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }

  if (call.state !== CHAT_CALL_STATES.RINGING) {
    return {
      call: await serializeCallSession(call),
      systemMessage: null,
    };
  }

  call.state = CHAT_CALL_STATES.DECLINED;
  call.endedAt = new Date();
  call.endedByUserId = actor._id;
  call.endReason = normalizedReason;
  await call.save();

  const eventType =
    normalizedReason === "busy"
      ? "call_busy"
      : "call_declined";
  const body =
    normalizedReason === "busy"
      ? "Voice call could not connect because the other line is busy."
      : "Voice call declined.";

  const systemMessage =
    await createCallSystemMessage({
      call,
      actor,
      eventType,
      body,
      context,
      eventData: {
        endedAt: call.endedAt,
        endedByUserId: actor._id.toString(),
        endReason: normalizedReason,
      },
    });

  return {
    call: await serializeCallSession(call),
    systemMessage,
  };
}

async function endCall({
  callId,
  userId,
  reason = "ended",
  context,
}) {
  logStep("END_CALL_BEGIN", {
    ...context,
    extra: { callId, userId, reason },
  });

  const normalizedReason = [
    "ended",
    "cancelled",
    "missed",
  ].includes((reason || "").toString().trim())
    ? reason.toString().trim()
    : "ended";

  const actor = await chatService.loadActor(
    userId,
    context,
  );
  const call = await loadAuthorizedCall({
    callId,
    userId,
    context,
  });

  if (
    [
      CHAT_CALL_STATES.DECLINED,
      CHAT_CALL_STATES.ENDED,
      CHAT_CALL_STATES.MISSED,
      CHAT_CALL_STATES.CANCELLED,
    ].includes(call.state)
  ) {
    return {
      call: await serializeCallSession(call),
      systemMessage: null,
    };
  }

  const actorId = actor._id.toString();
  const isCaller =
    call.callerUserId?.toString() === actorId;

  if (call.state === CHAT_CALL_STATES.RINGING) {
    if (!isCaller && normalizedReason !== "missed") {
      return declineCall({
        callId,
        userId,
        reason: "declined",
        context,
      });
    }

    call.state =
      normalizedReason === "missed"
        ? CHAT_CALL_STATES.MISSED
        : CHAT_CALL_STATES.CANCELLED;
    call.endedAt = new Date();
    call.endedByUserId = actor._id;
    call.endReason = normalizedReason;
    await call.save();

    const eventType =
      normalizedReason === "missed"
        ? "call_missed"
        : "call_cancelled";
    const body =
      normalizedReason === "missed"
        ? "Voice call missed."
        : "Voice call cancelled.";

    const systemMessage =
      await createCallSystemMessage({
        call,
        actor,
        eventType,
        body,
        context,
        eventData: {
          endedAt: call.endedAt,
          endedByUserId: actorId,
          endReason: normalizedReason,
        },
      });

    return {
      call: await serializeCallSession(call),
      systemMessage,
    };
  }

  call.state = CHAT_CALL_STATES.ENDED;
  call.endedAt = new Date();
  call.endedByUserId = actor._id;
  call.endReason = normalizedReason;
  await call.save();

  const durationSeconds =
    call.answeredAt && call.endedAt
      ? Math.max(
          0,
          Math.round(
            (call.endedAt.getTime() -
              call.answeredAt.getTime()) /
              1000,
          ),
        )
      : 0;
  const durationLabel =
    durationSeconds > 0
      ? ` after ${formatDurationSeconds(durationSeconds)}`
      : "";

  const systemMessage =
    await createCallSystemMessage({
      call,
      actor,
      eventType: "call_ended",
      body: `Voice call ended${durationLabel}.`,
      context,
      eventData: {
        endedAt: call.endedAt,
        endedByUserId: actorId,
        endReason: normalizedReason,
        durationSeconds,
      },
    });

  return {
    call: await serializeCallSession(call),
    systemMessage,
  };
}

async function resolveSignalTarget({
  callId,
  userId,
  context,
}) {
  const call = await loadAuthorizedCall({
    callId,
    userId,
    context,
  });

  if (
    ![
      CHAT_CALL_STATES.RINGING,
      CHAT_CALL_STATES.ACTIVE,
    ].includes(call.state)
  ) {
    throw buildCallError({
      message:
        "Call signaling is available only while the call is ringing or active",
      classification: "CONFLICT",
      errorCode: ERROR_CODES.CALL_CONFLICT,
      resolutionHint:
        "Restart the call if the previous session already ended.",
      httpStatus: HTTP_STATUS.CONFLICT,
    });
  }

  const actorId = userId?.toString() || "";
  call.lastSignalAt = new Date();
  await call.save();

  return {
    callId: call._id.toString(),
    targetUserId:
      call.callerUserId?.toString() === actorId
        ? call.calleeUserId?.toString() || ""
        : call.callerUserId?.toString() || "",
  };
}

module.exports = {
  startCall,
  getCall,
  acceptCall,
  declineCall,
  endCall,
  resolveSignalTarget,
};
