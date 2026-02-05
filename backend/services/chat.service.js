/**
 * services/chat.service.js
 * ------------------------
 * WHAT:
 * - Chat domain service for conversations, messages, and attachments.
 *
 * WHY:
 * - Keeps controllers REST-only while centralizing chat validation logic.
 * - Enforces business scoping rules for staff, tenants, and customers.
 *
 * HOW:
 * - Resolves actor + business scope, validates participants, and persists data.
 * - Uploads attachments to Cloudinary with structured error logging.
 */

const {
  v2: cloudinary,
} = require("cloudinary");
const debug = require("../utils/debug");
const User = require("../models/User");
const Order = require("../models/Order");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const BusinessAsset = require("../models/BusinessAsset");
const ChatConversation = require("../models/ChatConversation");
const ChatParticipant = require("../models/ChatParticipant");
const ChatMessage = require("../models/ChatMessage");
const ChatAttachment = require("../models/ChatAttachment");
const ChatReadReceipt = require("../models/ChatReadReceipt");
const {
  CHAT_CONVERSATION_TYPES,
  CHAT_MESSAGE_TYPES,
  CHAT_ATTACHMENT_TYPES,
  CHAT_ATTACHMENT_MIME_TYPES,
  CHAT_LIMITS,
} = require("../utils/chat_constants");

// WHY: Configure Cloudinary once for chat attachment uploads.
cloudinary.config({
  cloud_name:
    process.env.CLOUDINARY_CLOUD_NAME ||
    "",
  api_key:
    process.env.CLOUDINARY_API_KEY ||
    "",
  api_secret:
    process.env.CLOUDINARY_API_SECRET ||
    "",
});

// WHY: Centralize log labels for consistent diagnostics.
const LOG_TAG = "CHAT_SERVICE";
const LOG_STEPS = {
  SERVICE_START: "SERVICE_START",
  DB_QUERY_START: "DB_QUERY_START",
  DB_QUERY_OK: "DB_QUERY_OK",
  DB_QUERY_FAIL: "DB_QUERY_FAIL",
  SERVICE_OK: "SERVICE_OK",
  SERVICE_FAIL: "SERVICE_FAIL",
};

// WHY: Keep HTTP codes in one place for safe reuse.
const HTTP_STATUS = {
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
};

// WHY: Keep error codes consistent across chat services.
const ERROR_CODES = {
  ACTOR_REQUIRED: "CHAT_ACTOR_REQUIRED",
  BUSINESS_REQUIRED:
    "CHAT_BUSINESS_REQUIRED",
  CONVERSATION_REQUIRED:
    "CHAT_CONVERSATION_REQUIRED",
  CONVERSATION_NOT_FOUND:
    "CHAT_CONVERSATION_NOT_FOUND",
  PARTICIPANTS_REQUIRED:
    "CHAT_PARTICIPANTS_REQUIRED",
  MESSAGE_REQUIRED:
    "CHAT_MESSAGE_REQUIRED",
  ACCESS_FORBIDDEN:
    "CHAT_ACCESS_FORBIDDEN",
  CUSTOMER_SCOPE_INVALID:
    "CHAT_CUSTOMER_SCOPE_INVALID",
  ATTACHMENT_INVALID:
    "CHAT_ATTACHMENT_INVALID",
  CLOUDINARY_CONFIG_MISSING:
    "CHAT_CLOUDINARY_CONFIG_MISSING",
};

// WHY: Keep resolution hints explicit and helpful.
const RESOLUTION_HINTS = {
  ACTOR_REQUIRED:
    "Provide a valid user id before retrying.",
  BUSINESS_REQUIRED:
    "Select a business scope before starting chat.",
  CONVERSATION_REQUIRED:
    "Provide a valid conversation id.",
  CONVERSATION_NOT_FOUND:
    "Confirm the conversation exists and retry.",
  PARTICIPANTS_REQUIRED:
    "Provide at least one participant (two for group chats).",
  MESSAGE_REQUIRED:
    "Provide text or attachments to send.",
  ACCESS_FORBIDDEN:
    "Ensure the user is allowed to access this chat.",
  CUSTOMER_SCOPE_INVALID:
    "Customers may only chat with businesses they purchased from.",
  ATTACHMENT_INVALID:
    "Check attachment type and size before retrying.",
  CLOUDINARY_CONFIG_MISSING:
    "Configure Cloudinary credentials and retry.",
};

// WHY: Role constants prevent inline magic strings.
const ROLE_BUSINESS_OWNER =
  "business_owner";
const ROLE_STAFF = "staff";
const ROLE_TENANT = "tenant";
const ROLE_CUSTOMER = "customer";
const ROLE_ADMIN = "admin";
const ROLE_SUPPORT = "support";

// WHY: Limit preview length for conversation inbox tiles.
const MAX_PREVIEW_LENGTH = 120;
const ATTACHMENT_PREVIEW = "Attachment";

// WHY: Shared selection fields reduce query payloads.
const ACTOR_SELECT_FIELDS =
  "role businessId estateAssetId name email firstName middleName lastName";
// WHY: Keep participant lookups small while supporting profile summary.
const PARTICIPANT_SELECT_FIELDS =
  "role businessId estateAssetId name email firstName middleName lastName companyName profileImageUrl";

function logStep(step, context = {}) {
  // WHY: Avoid noisy logs unless context is provided.
  if (
    !context ||
    (!context.requestId &&
      !context.route)
  ) {
    return;
  }

  debug(LOG_TAG, {
    requestId:
      context.requestId || "unknown",
    route: context.route || "unknown",
    step,
    layer: "service",
    operation:
      context.operation ||
      "ChatService",
    intent:
      context.intent ||
      "chat_operation",
    userRole:
      context.userRole || "unknown",
    businessId:
      context.businessId || null,
    ...context.extra,
  });
}

function buildChatError({
  message,
  classification,
  errorCode,
  resolutionHint,
  httpStatus,
}) {
  // WHY: Attach metadata for consistent controller responses.
  const error = new Error(message);
  error.classification = classification;
  error.errorCode = errorCode;
  error.resolutionHint = resolutionHint;
  error.httpStatus = httpStatus;
  return error;
}

function sanitizePreview(text) {
  // WHY: Keep previews short for inbox rendering.
  const trimmed = (text || "")
    .toString()
    .trim();
  if (
    trimmed.length <= MAX_PREVIEW_LENGTH
  )
    return trimmed;
  return trimmed.slice(
    0,
    MAX_PREVIEW_LENGTH,
  );
}

function resolveDisplayName(user) {
  // WHY: Prefer a human-friendly name for profile summaries.
  const parts = [
    user?.firstName
      ?.toString()
      .trim() || "",
    user?.middleName
      ?.toString()
      .trim() || "",
    user?.lastName?.toString().trim() ||
      "",
  ].filter((part) => part);
  if (parts.length > 0) {
    return parts.join(" ");
  }
  return (
    user?.name?.toString().trim() ||
    user?.email?.toString().trim() ||
    "User"
  );
}

async function loadBusinessNameMap(
  businessIds,
) {
  // WHY: Resolve business names once to avoid N+1 lookups.
  const uniqueIds = [
    ...new Set(
      businessIds.map((id) =>
        id.toString(),
      ),
    ),
  ];
  if (uniqueIds.length === 0)
    return new Map();

  const rows = await User.find({
    _id: { $in: uniqueIds },
  }).select("companyName name email");
  const map = new Map();
  rows.forEach((row) => {
    map.set(
      row._id.toString(),
      row.companyName ||
        row.name ||
        row.email ||
        "",
    );
  });
  return map;
}

async function loadStaffProfileMap(
  userIds,
) {
  // WHY: Staff estate assignment + staff role live on the staff profile.
  const uniqueIds = [
    ...new Set(
      userIds.map((id) =>
        id.toString(),
      ),
    ),
  ];
  if (uniqueIds.length === 0)
    return new Map();

  const profiles =
    await BusinessStaffProfile.find({
      userId: { $in: uniqueIds },
    }).select(
      "userId estateAssetId staffRole",
    );

  const map = new Map();
  profiles.forEach((profile) => {
    if (profile.userId) {
      map.set(
        profile.userId.toString(),
        {
          estateAssetId:
            profile.estateAssetId?.toString() ||
            "",
          staffRole:
            profile.staffRole || "",
        },
      );
    }
  });
  return map;
}

async function loadEstateNameMap(
  estateIds,
) {
  // WHY: Surface estate names for chat profile summaries.
  const uniqueIds = [
    ...new Set(
      estateIds.map((id) =>
        id.toString(),
      ),
    ),
  ];
  if (uniqueIds.length === 0)
    return new Map();

  const assets =
    await BusinessAsset.find({
      _id: { $in: uniqueIds },
    }).select("name");

  const map = new Map();
  assets.forEach((asset) => {
    map.set(
      asset._id.toString(),
      asset.name || "",
    );
  });
  return map;
}

async function loadActor(
  userId,
  context,
) {
  // WHY: Enforce a valid actor before any chat action.
  if (!userId) {
    throw buildChatError({
      message: "User id is required",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.ACTOR_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.ACTOR_REQUIRED,
      httpStatus:
        HTTP_STATUS.UNAUTHORIZED,
    });
  }

  logStep(
    LOG_STEPS.DB_QUERY_START,
    context,
  );
  const actor = await User.findById(
    userId,
  ).select(ACTOR_SELECT_FIELDS);
  if (!actor) {
    logStep(LOG_STEPS.DB_QUERY_FAIL, {
      ...context,
      extra: {
        classification:
          "AUTHENTICATION_ERROR",
        error_code:
          ERROR_CODES.ACTOR_REQUIRED,
        resolution_hint:
          RESOLUTION_HINTS.ACTOR_REQUIRED,
      },
    });
    throw buildChatError({
      message: "User not found",
      classification:
        "AUTHENTICATION_ERROR",
      errorCode:
        ERROR_CODES.ACTOR_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.ACTOR_REQUIRED,
      httpStatus:
        HTTP_STATUS.UNAUTHORIZED,
    });
  }
  logStep(
    LOG_STEPS.DB_QUERY_OK,
    context,
  );
  return actor;
}

async function resolveBusinessScope({
  actor,
  businessIdHint,
  context,
}) {
  // WHY: Staff/owners/tenants must stay within their business scope.
  if (
    actor.role ===
      ROLE_BUSINESS_OWNER ||
    actor.role === ROLE_STAFF ||
    actor.role === ROLE_TENANT
  ) {
    if (!actor.businessId) {
      throw buildChatError({
        message:
          "Business scope is required",
        classification:
          "MISSING_REQUIRED_FIELD",
        errorCode:
          ERROR_CODES.BUSINESS_REQUIRED,
        resolutionHint:
          RESOLUTION_HINTS.BUSINESS_REQUIRED,
        httpStatus:
          HTTP_STATUS.BAD_REQUEST,
      });
    }
    if (
      businessIdHint &&
      actor.businessId.toString() !==
        businessIdHint
    ) {
      throw buildChatError({
        message:
          "Business scope mismatch",
        classification:
          "AUTHENTICATION_ERROR",
        errorCode:
          ERROR_CODES.ACCESS_FORBIDDEN,
        resolutionHint:
          RESOLUTION_HINTS.ACCESS_FORBIDDEN,
        httpStatus:
          HTTP_STATUS.FORBIDDEN,
      });
    }
    return actor.businessId.toString();
  }

  // WHY: Customers must supply a business and prove purchase history.
  if (actor.role === ROLE_CUSTOMER) {
    if (!businessIdHint) {
      throw buildChatError({
        message:
          "Business scope is required",
        classification:
          "MISSING_REQUIRED_FIELD",
        errorCode:
          ERROR_CODES.BUSINESS_REQUIRED,
        resolutionHint:
          RESOLUTION_HINTS.BUSINESS_REQUIRED,
        httpStatus:
          HTTP_STATUS.BAD_REQUEST,
      });
    }

    logStep(LOG_STEPS.DB_QUERY_START, {
      ...context,
      extra: { check: "order_scope" },
    });
    const hasOrder = await Order.exists(
      {
        user: actor._id,
        businessIds: businessIdHint,
      },
    );
    if (!hasOrder) {
      logStep(LOG_STEPS.DB_QUERY_FAIL, {
        ...context,
        extra: {
          classification:
            "AUTHENTICATION_ERROR",
          error_code:
            ERROR_CODES.CUSTOMER_SCOPE_INVALID,
          resolution_hint:
            RESOLUTION_HINTS.CUSTOMER_SCOPE_INVALID,
        },
      });
      throw buildChatError({
        message:
          "Customer has no orders with this business",
        classification:
          "AUTHENTICATION_ERROR",
        errorCode:
          ERROR_CODES.CUSTOMER_SCOPE_INVALID,
        resolutionHint:
          RESOLUTION_HINTS.CUSTOMER_SCOPE_INVALID,
        httpStatus:
          HTTP_STATUS.FORBIDDEN,
      });
    }
    logStep(LOG_STEPS.DB_QUERY_OK, {
      ...context,
      extra: { check: "order_scope" },
    });
    return businessIdHint;
  }

  // WHY: Default safeguard for unknown roles.
  throw buildChatError({
    message:
      "User role is not permitted for chat",
    classification:
      "AUTHENTICATION_ERROR",
    errorCode:
      ERROR_CODES.ACCESS_FORBIDDEN,
    resolutionHint:
      RESOLUTION_HINTS.ACCESS_FORBIDDEN,
    httpStatus: HTTP_STATUS.FORBIDDEN,
  });
}

function assertParticipants(
  participantUserIds,
) {
  // WHY: Conversations require at least one other participant.
  if (
    !Array.isArray(
      participantUserIds,
    ) ||
    participantUserIds.length < 1
  ) {
    throw buildChatError({
      message:
        "Participants are required",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.PARTICIPANTS_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.PARTICIPANTS_REQUIRED,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }
}

async function loadParticipants(
  userIds,
) {
  // WHY: Validate participants in a single query to reduce DB load.
  return User.find({
    _id: { $in: userIds },
  }).select(ACTOR_SELECT_FIELDS);
}

async function loadParticipantUserMap(
  participantIds,
) {
  // WHY: Resolve participant ids to users, even when stored as staff profile ids.
  const uniqueIds = [
    ...new Set(
      (participantIds || [])
        .filter(Boolean)
        .map((id) => id.toString()),
    ),
  ];
  if (uniqueIds.length === 0)
    return new Map();

  const userRows = await User.find({
    _id: { $in: uniqueIds },
  }).select(PARTICIPANT_SELECT_FIELDS);

  const map = new Map();
  userRows.forEach((row) => {
    map.set(row._id.toString(), row);
  });

  const missingIds = uniqueIds.filter(
    (id) => !map.has(id),
  );
  if (missingIds.length === 0)
    return map;

  const staffProfiles =
    await BusinessStaffProfile.find({
      _id: { $in: missingIds },
    }).select("userId");

  const fallbackUserIds = [
    ...new Set(
      staffProfiles
        .map((profile) =>
          profile.userId?.toString(),
        )
        .filter(Boolean),
    ),
  ];
  if (fallbackUserIds.length === 0)
    return map;

  const fallbackUsers = await User.find(
    {
      _id: { $in: fallbackUserIds },
    },
  ).select(PARTICIPANT_SELECT_FIELDS);

  const fallbackMap = new Map();
  fallbackUsers.forEach((row) => {
    fallbackMap.set(
      row._id.toString(),
      row,
    );
  });

  staffProfiles.forEach((profile) => {
    const profileId =
      profile._id.toString();
    const userId =
      profile.userId?.toString();
    if (
      userId &&
      fallbackMap.has(userId)
    ) {
      map.set(
        profileId,
        fallbackMap.get(userId),
      );
    }
  });

  return map;
}

function buildUserRoleMap(users) {
  // WHY: Fast lookup for role + business checks.
  const map = new Map();
  users.forEach((user) => {
    map.set(user._id.toString(), {
      role: user.role,
      businessId:
        user.businessId?.toString() ||
        null,
    });
  });
  return map;
}

function assertGroupRoles(roleMap) {
  // WHY: Group chats are limited to staff + owners for now.
  const invalid = [
    ...roleMap.values(),
  ].find(
    (entry) =>
      ![
        ROLE_STAFF,
        ROLE_BUSINESS_OWNER,
      ].includes(entry.role),
  );
  if (invalid) {
    throw buildChatError({
      message:
        "Group chat is limited to staff and owners",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.ACCESS_FORBIDDEN,
      resolutionHint:
        RESOLUTION_HINTS.ACCESS_FORBIDDEN,
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }
}

function assertBusinessAlignment(
  roleMap,
  businessId,
) {
  // WHY: Ensure staff/tenant/owner accounts share the same business.
  const mismatch = [
    ...roleMap.values(),
  ].find(
    (entry) =>
      entry.businessId &&
      businessId &&
      entry.businessId !== businessId,
  );
  if (mismatch) {
    throw buildChatError({
      message:
        "Participant business scope mismatch",
      classification:
        "AUTHENTICATION_ERROR",
      errorCode:
        ERROR_CODES.ACCESS_FORBIDDEN,
      resolutionHint:
        RESOLUTION_HINTS.ACCESS_FORBIDDEN,
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }
}

function assertCustomerRules({
  type,
  participantIds,
  roleMap,
}) {
  // WHY: Customers may only join direct 1:1 conversations.
  const hasCustomer =
    participantIds.some(
      (id) =>
        roleMap.get(id)?.role ===
        ROLE_CUSTOMER,
    );
  if (!hasCustomer) return;

  if (
    type !==
    CHAT_CONVERSATION_TYPES.DIRECT
  ) {
    throw buildChatError({
      message:
        "Customers can only join direct chats",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.ACCESS_FORBIDDEN,
      resolutionHint:
        RESOLUTION_HINTS.ACCESS_FORBIDDEN,
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }

  if (participantIds.length !== 2) {
    throw buildChatError({
      message:
        "Customer chat must be 1:1",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.PARTICIPANTS_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.PARTICIPANTS_REQUIRED,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }
}

async function ensureParticipant({
  conversationId,
  userId,
  context,
}) {
  // WHY: Participants control access for every chat action.
  const participant =
    await ChatParticipant.findOne({
      conversationId,
      userId,
      isHidden: false,
    });
  if (!participant) {
    logStep(LOG_STEPS.DB_QUERY_FAIL, {
      ...context,
      extra: {
        classification:
          "AUTHENTICATION_ERROR",
        error_code:
          ERROR_CODES.ACCESS_FORBIDDEN,
        resolution_hint:
          RESOLUTION_HINTS.ACCESS_FORBIDDEN,
      },
    });
    throw buildChatError({
      message:
        "User is not a participant in this conversation",
      classification:
        "AUTHENTICATION_ERROR",
      errorCode:
        ERROR_CODES.ACCESS_FORBIDDEN,
      resolutionHint:
        RESOLUTION_HINTS.ACCESS_FORBIDDEN,
      httpStatus: HTTP_STATUS.FORBIDDEN,
    });
  }
  return participant;
}

async function findExistingDirectConversation({
  businessId,
  participantUserIds,
}) {
  // WHY: Prevent duplicate 1:1 threads for the same pair.
  const participantRows =
    await ChatParticipant.find({
      userId: {
        $in: participantUserIds,
      },
    }).select("conversationId userId");
  const map = new Map();
  participantRows.forEach((row) => {
    const convoId =
      row.conversationId.toString();
    if (!map.has(convoId)) {
      map.set(convoId, new Set());
    }
    map
      .get(convoId)
      .add(row.userId.toString());
  });

  const participantSet = new Set(
    participantUserIds,
  );
  for (const [
    conversationId,
    userSet,
  ] of map.entries()) {
    if (
      userSet.size ===
      participantSet.size
    ) {
      let matches = true;
      participantSet.forEach((id) => {
        if (!userSet.has(id))
          matches = false;
      });
      if (matches) {
        const conversation =
          await ChatConversation.findOne(
            {
              _id: conversationId,
              businessId,
              type: CHAT_CONVERSATION_TYPES.DIRECT,
            },
          );
        if (conversation)
          return conversation;
      }
    }
  }

  return null;
}

async function listConversations({
  userId,
  businessId,
  limit,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );
  logStep(
    LOG_STEPS.DB_QUERY_START,
    context,
  );

  const participants =
    await ChatParticipant.find({
      userId,
      isHidden: false,
    }).select("conversationId");

  const conversationIds =
    participants.map((row) =>
      row.conversationId.toString(),
    );
  if (conversationIds.length === 0) {
    return [];
  }

  const query = {
    _id: { $in: conversationIds },
  };
  if (businessId) {
    query.businessId = businessId;
  }

  const items =
    await ChatConversation.find(query)
      .sort({
        lastMessageAt: -1,
        updatedAt: -1,
      })
      .limit(limit || 50)
      .lean();

  // WHY: Load participants in bulk to avoid per-conversation queries.
  const participantRows =
    await ChatParticipant.find({
      conversationId: {
        $in: conversationIds,
      },
      isHidden: false,
    }).select("conversationId userId");

  // WHY: Build a per-conversation participant lookup for counts + display names.
  const participantMap = new Map();
  participantRows.forEach((row) => {
    const convoId =
      row.conversationId.toString();
    if (!participantMap.has(convoId)) {
      participantMap.set(convoId, []);
    }
    participantMap
      .get(convoId)
      .push(row.userId.toString());
  });

  // WHY: Resolve participant display info in a single query path.
  const participantIds =
    participantRows.map((row) =>
      row.userId.toString(),
    );
  const participantUserMap =
    await loadParticipantUserMap(
      participantIds,
    );

  const actorId =
    userId?.toString() || "";
  const enriched = items.map(
    (conversation) => {
      const convoId =
        conversation._id.toString();
      const participantIds =
        participantMap.get(convoId) ||
        [];
      const participantsCount =
        participantIds.length;
      let displayName = "";
      let displayAvatar = "";

      if (
        conversation.type ===
        CHAT_CONVERSATION_TYPES.DIRECT
      ) {
        // WHY: Direct chats display the other participant instead of a title.
        const otherId =
          participantIds.find(
            (id) => id !== actorId,
          );
        const otherUser =
          otherId ?
            participantUserMap.get(
              otherId,
            )
          : null;
        if (otherUser) {
          displayName =
            resolveDisplayName(
              otherUser,
            );
          displayAvatar =
            otherUser.profileImageUrl ||
            "";
        }
      } else {
        // WHY: Group chats use the stored conversation title.
        displayName = (
          conversation.title || ""
        )
          .toString()
          .trim();
      }

      return {
        ...conversation,
        displayName,
        displayAvatar,
        participantsCount,
      };
    },
  );

  logStep(
    LOG_STEPS.DB_QUERY_OK,
    context,
  );
  logStep(
    LOG_STEPS.SERVICE_OK,
    context,
  );
  return enriched;
}

async function createConversation({
  actor,
  businessId,
  type,
  title,
  participantUserIds,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );
  assertParticipants(
    participantUserIds,
  );
  // WHY: Group chats require at least two other members besides the actor.
  if (
    type ===
      CHAT_CONVERSATION_TYPES.GROUP &&
    participantUserIds.length < 2
  ) {
    throw buildChatError({
      message:
        "Participants are required",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.PARTICIPANTS_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.PARTICIPANTS_REQUIRED,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  const normalizedIds = [
    ...new Set(
      participantUserIds.map((id) =>
        id.toString(),
      ),
    ),
  ];
  if (
    !normalizedIds.includes(
      actor._id.toString(),
    )
  ) {
    normalizedIds.push(
      actor._id.toString(),
    );
  }

  const participants =
    await loadParticipants(
      normalizedIds,
    );
  const roleMap = buildUserRoleMap(
    participants,
  );

  assertCustomerRules({
    type,
    participantIds: normalizedIds,
    roleMap,
  });

  if (
    type ===
    CHAT_CONVERSATION_TYPES.GROUP
  ) {
    assertGroupRoles(roleMap);
  }

  assertBusinessAlignment(
    roleMap,
    businessId,
  );

  if (
    type ===
    CHAT_CONVERSATION_TYPES.DIRECT
  ) {
    const existing =
      await findExistingDirectConversation(
        {
          businessId,
          participantUserIds:
            normalizedIds,
        },
      );
    if (existing) {
      return existing;
    }
  }

  const conversation =
    await ChatConversation.create({
      businessId,
      type,
      title: (title || "")
        .toString()
        .trim(),
      createdByUserId: actor._id,
    });

  const participantDocs =
    normalizedIds.map((id) => ({
      conversationId: conversation._id,
      userId: id,
      roleAtJoin:
        roleMap.get(id)?.role || "",
      joinedAt: new Date(),
    }));
  await ChatParticipant.insertMany(
    participantDocs,
  );

  logStep(
    LOG_STEPS.SERVICE_OK,
    context,
  );
  return conversation;
}

async function getConversationDetail({
  userId,
  conversationId,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );

  if (!conversationId) {
    throw buildChatError({
      message:
        "Conversation id is required",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.CONVERSATION_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.CONVERSATION_REQUIRED,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  // WHY: Ensure the requesting user is a participant before exposing details.
  await ensureParticipant({
    conversationId,
    userId,
    context,
  });

  logStep(
    LOG_STEPS.DB_QUERY_START,
    context,
  );
  const conversation =
    await ChatConversation.findById(
      conversationId,
    ).lean();
  if (!conversation) {
    logStep(LOG_STEPS.DB_QUERY_FAIL, {
      ...context,
      extra: {
        reason:
          "conversation_not_found",
      },
    });
    throw buildChatError({
      message: "Conversation not found",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.CONVERSATION_NOT_FOUND,
      resolutionHint:
        RESOLUTION_HINTS.CONVERSATION_NOT_FOUND,
      httpStatus: HTTP_STATUS.NOT_FOUND,
    });
  }

  const participantRows =
    await ChatParticipant.find({
      conversationId,
      isHidden: false,
    })
      .populate(
        "userId",
        PARTICIPANT_SELECT_FIELDS,
      )
      .lean();

  const participantIds = participantRows
    .map((row) => {
      if (
        row.userId &&
        row.userId._id
      ) {
        return row.userId._id.toString();
      }
      return row.userId ?
          row.userId.toString()
        : "";
    })
    .filter(Boolean);
  const participantUserMap =
    await loadParticipantUserMap(
      participantIds,
    );

  const resolvedUsers =
    participantRows.map((row) => {
      const participantId =
        row.userId && row.userId._id ?
          row.userId._id.toString()
        : row.userId ?
          row.userId.toString()
        : "";
      const resolved =
        row.userId && row.userId._id ?
          row.userId
        : participantId ?
          participantUserMap.get(
            participantId,
          )
        : null;
      return {
        participantId,
        user: resolved || null,
      };
    });

  const businessIds = resolvedUsers
    .map(
      (entry) => entry.user?.businessId,
    )
    .filter(Boolean)
    .map((id) => id.toString());
  const businessNameMap =
    await loadBusinessNameMap(
      businessIds,
    );
  const staffUserIds = resolvedUsers
    .filter(
      (entry) =>
        entry.user?.role === ROLE_STAFF,
    )
    .map((entry) => entry.user?._id)
    .filter(Boolean)
    .map((id) => id.toString());
  const staffProfileMap =
    await loadStaffProfileMap(
      staffUserIds,
    );
  const estateIds = resolvedUsers
    .map(
      (entry) =>
        entry.user?.estateAssetId,
    )
    .filter(Boolean)
    .map((id) => id.toString());
  staffProfileMap.forEach((profile) => {
    if (profile?.estateAssetId) {
      estateIds.push(
        profile.estateAssetId,
      );
    }
  });
  const estateNameMap =
    await loadEstateNameMap(estateIds);

  const participants =
    resolvedUsers.map(
      (entry, index) => {
        const row =
          participantRows[index] || {};
        const user = entry.user || {};
        const businessId =
          user.businessId?.toString() ||
          "";
        const staffProfile =
          (
            user?._id &&
            staffProfileMap.has(
              user._id.toString(),
            )
          ) ?
            staffProfileMap.get(
              user._id.toString(),
            )
          : null;
        const staffEstateId =
          staffProfile?.estateAssetId ||
          "";
        const staffRole =
          staffProfile?.staffRole || "";
        const estateId =
          staffEstateId ||
          user.estateAssetId?.toString() ||
          "";
        return {
          userId:
            user._id?.toString() ||
            entry.participantId ||
            "",
          name: resolveDisplayName(
            user,
          ),
          email: user.email || "",
          // WHY: Expose profile avatar for chat header + profile cards.
          profileImageUrl:
            user.profileImageUrl || "",
          role:
            staffRole ||
            user.role ||
            row.roleAtJoin ||
            "",
          businessId,
          businessName:
            businessId ?
              businessNameMap.get(
                businessId,
              ) || ""
            : "",
          estateAssetId: estateId,
          estateName:
            estateId ?
              estateNameMap.get(
                estateId,
              ) || ""
            : "",
          roleAtJoin:
            row.roleAtJoin || "",
        };
      },
    );

  logStep(
    LOG_STEPS.DB_QUERY_OK,
    context,
  );
  logStep(
    LOG_STEPS.SERVICE_OK,
    context,
  );

  return { conversation, participants };
}

async function listMessages({
  userId,
  conversationId,
  limit,
  cursor,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );
  await ensureParticipant({
    conversationId,
    userId,
    context,
  });

  const query = {
    conversationId,
    isHidden: false,
    hiddenForUserIds: { $ne: userId },
  };
  if (cursor) {
    query.createdAt = {
      $lt: new Date(cursor),
    };
  }

  const items = await ChatMessage.find(
    query,
  )
    .populate("attachmentIds")
    .sort({ createdAt: -1 })
    .limit(limit || 30)
    .lean();

  logStep(
    LOG_STEPS.SERVICE_OK,
    context,
  );
  return items;
}

async function sendMessage({
  actor,
  businessId,
  conversationId,
  body,
  attachmentIds,
  clientMessageId,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );
  await ensureParticipant({
    conversationId,
    userId: actor._id,
    context,
  });

  const text = (body || "")
    .toString()
    .trim();
  const attachmentList =
    Array.isArray(attachmentIds) ?
      attachmentIds
    : [];

  if (
    !text &&
    attachmentList.length === 0
  ) {
    throw buildChatError({
      message:
        "Message text or attachment is required",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.MESSAGE_REQUIRED,
      resolutionHint:
        RESOLUTION_HINTS.MESSAGE_REQUIRED,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  const message =
    await ChatMessage.create({
      conversationId,
      businessId,
      senderUserId: actor._id,
      type:
        attachmentList.length > 0 ?
          CHAT_MESSAGE_TYPES.ATTACHMENT
        : CHAT_MESSAGE_TYPES.TEXT,
      body: text,
      attachmentIds: attachmentList,
      clientMessageId: (
        clientMessageId || ""
      )
        .toString()
        .trim(),
    });

  if (attachmentList.length > 0) {
    await ChatAttachment.updateMany(
      { _id: { $in: attachmentList } },
      { messageId: message._id },
    );
  }

  await ChatConversation.findByIdAndUpdate(
    conversationId,
    {
      lastMessageAt: message.createdAt,
      lastMessagePreview:
        sanitizePreview(
          text || ATTACHMENT_PREVIEW,
        ),
    },
  );

  const hydrated =
    await ChatMessage.findById(
      message._id,
    )
      .populate("attachmentIds")
      .lean();

  logStep(
    LOG_STEPS.SERVICE_OK,
    context,
  );
  return hydrated || message;
}

async function markMessagesRead({
  userId,
  conversationId,
  messageIds,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );
  await ensureParticipant({
    conversationId,
    userId,
    context,
  });

  const ids =
    Array.isArray(messageIds) ?
      messageIds
    : [];
  if (ids.length === 0) {
    return { updated: 0 };
  }

  const operations = ids.map(
    (messageId) => ({
      updateOne: {
        filter: { messageId, userId },
        update: {
          conversationId,
          messageId,
          userId,
          readAt: new Date(),
        },
        upsert: true,
      },
    }),
  );

  await ChatReadReceipt.bulkWrite(
    operations,
  );
  await ChatParticipant.updateOne(
    { conversationId, userId },
    { lastReadAt: new Date() },
  );

  logStep(
    LOG_STEPS.SERVICE_OK,
    context,
  );
  return { updated: ids.length };
}

function assertCloudinaryConfig() {
  // WHY: Guard against missing credentials before uploading.
  const hasConfig =
    !!process.env
      .CLOUDINARY_CLOUD_NAME &&
    !!process.env.CLOUDINARY_API_KEY &&
    !!process.env.CLOUDINARY_API_SECRET;
  if (!hasConfig) {
    throw buildChatError({
      message:
        "Cloudinary credentials are not configured",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.CLOUDINARY_CONFIG_MISSING,
      resolutionHint:
        RESOLUTION_HINTS.CLOUDINARY_CONFIG_MISSING,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }
}

function classifyCloudinaryFailure(
  status,
) {
  if (status == null)
    return "UNKNOWN_PROVIDER_ERROR";
  if (status === 400)
    return "INVALID_INPUT";
  if (status === 401 || status === 403)
    return "AUTHENTICATION_ERROR";
  if (status === 429)
    return "RATE_LIMITED";
  if (status >= 500)
    return "PROVIDER_OUTAGE";
  return "UNKNOWN_PROVIDER_ERROR";
}

function logCloudinaryFailure({
  error,
  context,
  source,
}) {
  // WHY: Ensure diagnostics include intent + provider details for support.
  const status =
    error?.http_code ||
    error?.status ||
    null;
  const providerCode =
    error?.code || null;
  const providerMessage =
    error?.message ||
    error?.error?.message ||
    "Unknown provider error";
  const classification =
    classifyCloudinaryFailure(status);
  const retryMeta =
    (
      classification ===
        "RATE_LIMITED" ||
      classification ===
        "PROVIDER_OUTAGE"
    ) ?
      {
        retry_allowed: true,
        retry_reason:
          "provider_throttle",
      }
    : {
        retry_skipped: true,
        retry_reason:
          "client_or_auth_error",
      };

  debug(
    "CHAT ATTACHMENT: upload failed",
    {
      service: "CLOUDINARY",
      operation:
        "chat_attachment_upload",
      request_intent:
        "Upload chat attachment",
      request_context: {
        country: "unknown",
        source,
        ...context,
      },
      http_status: status,
      provider_error_code: providerCode,
      provider_error_message:
        providerMessage,
      failure_classification:
        classification,
      ...(classification ===
        "UNKNOWN_PROVIDER_ERROR" && {
        failure_justification:
          "Cloudinary did not provide HTTP status.",
      }),
      resolution_hint:
        (
          classification ===
          "AUTHENTICATION_ERROR"
        ) ?
          "Verify Cloudinary credentials and retry."
        : (
          classification ===
          "INVALID_INPUT"
        ) ?
          "Check file type/size and retry."
        : (
          classification ===
          "RATE_LIMITED"
        ) ?
          "Wait before retrying to avoid rate limits."
        : "Retry later or inspect provider logs.",
      ...retryMeta,
    },
  );
}

async function uploadChatAttachment({
  actor,
  businessId,
  conversationId,
  file,
  context,
}) {
  logStep(
    LOG_STEPS.SERVICE_START,
    context,
  );
  await ensureParticipant({
    conversationId,
    userId: actor._id,
    context,
  });

  if (!file) {
    throw buildChatError({
      message:
        "Attachment file is required",
      classification:
        "MISSING_REQUIRED_FIELD",
      errorCode:
        ERROR_CODES.ATTACHMENT_INVALID,
      resolutionHint:
        RESOLUTION_HINTS.ATTACHMENT_INVALID,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  const isImage =
    CHAT_ATTACHMENT_MIME_TYPES.IMAGE.includes(
      file.mimetype,
    );
  const isDocument =
    CHAT_ATTACHMENT_MIME_TYPES.DOCUMENT.includes(
      file.mimetype,
    );

  if (!isImage && !isDocument) {
    throw buildChatError({
      message:
        "Unsupported attachment type",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.ATTACHMENT_INVALID,
      resolutionHint:
        RESOLUTION_HINTS.ATTACHMENT_INVALID,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  if (
    isImage &&
    file.size >
      CHAT_LIMITS.MAX_IMAGE_BYTES
  ) {
    throw buildChatError({
      message: "Image exceeds max size",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.ATTACHMENT_INVALID,
      resolutionHint:
        RESOLUTION_HINTS.ATTACHMENT_INVALID,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  if (
    isDocument &&
    file.size >
      CHAT_LIMITS.MAX_DOCUMENT_BYTES
  ) {
    throw buildChatError({
      message:
        "Document exceeds max size",
      classification: "INVALID_INPUT",
      errorCode:
        ERROR_CODES.ATTACHMENT_INVALID,
      resolutionHint:
        RESOLUTION_HINTS.ATTACHMENT_INVALID,
      httpStatus:
        HTTP_STATUS.BAD_REQUEST,
    });
  }

  assertCloudinaryConfig();

  try {
    const uploadResult =
      await new Promise(
        (resolve, reject) => {
          const stream =
            cloudinary.uploader.upload_stream(
              {
                folder: `gafexpress/chat/${businessId}/${conversationId}`,
                resource_type: "auto",
                allowed_formats: [
                  "pdf",
                  "png",
                  "jpg",
                  "jpeg",
                  "webp",
                  "docx",
                ],
              },
              (error, result) => {
                if (error)
                  return reject(error);
                return resolve(result);
              },
            );
          stream.end(file.buffer);
        },
      );

    const attachment =
      await ChatAttachment.create({
        conversationId,
        messageId: null,
        uploadedByUserId: actor._id,
        type:
          isImage ?
            CHAT_ATTACHMENT_TYPES.IMAGE
          : CHAT_ATTACHMENT_TYPES.DOCUMENT,
        mimeType: file.mimetype,
        sizeBytes: file.size,
        url: uploadResult.secure_url,
        publicId:
          uploadResult.public_id || "",
        filename:
          file.originalname || "",
        width:
          uploadResult.width || null,
        height:
          uploadResult.height || null,
      });

    logStep(
      LOG_STEPS.SERVICE_OK,
      context,
    );
    return attachment;
  } catch (error) {
    logCloudinaryFailure({
      error,
      source: "chat_attachment",
      context: {
        hasFile: Boolean(file),
        hasMimeType: Boolean(
          file?.mimetype,
        ),
      },
    });
    throw error;
  }
}

module.exports = {
  loadActor,
  resolveBusinessScope,
  listConversations,
  createConversation,
  getConversationDetail,
  listMessages,
  sendMessage,
  markMessagesRead,
  uploadChatAttachment,
  ensureParticipant,
};
