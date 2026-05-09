/**
 * apps/backend/services/management_notification.service.js
 * --------------------------------------------------------
 * WHAT:
 * - Writes management-facing notification audit entries for operational events.
 *
 * WHY:
 * - Managers need a compact trail when staff log in, clock in/out, work gets
 *   approved, and chat messages arrive.
 * - Using audit entries first keeps the feature durable without depending on a
 *   separate push-notification provider.
 *
 * HOW:
 * - Resolves safe staff/user/task/message context.
 * - Writes a scoped AuditLog entry with `notificationEnabled: true`.
 * - Never blocks the primary action if notification logging fails.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const { writeAuditLog } = require("../utils/audit");
const User = require("../models/User");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const ProductionTask = require("../models/ProductionTask");
const ProductionPlan = require("../models/ProductionPlan");
const ChatParticipant = require("../models/ChatParticipant");

const LOG_PREFIX = "MANAGEMENT_NOTIFICATION_SERVICE";
const MANAGEMENT_STAFF_ROLES = [
  "shareholder",
  "estate_manager",
  "farm_manager",
  "asset_manager",
  "customer_care",
];

function normalizeId(value) {
  return value?.toString?.().trim() || "";
}

function isObjectId(value) {
  return mongoose.Types.ObjectId.isValid(normalizeId(value));
}

function formatUserName(user) {
  // WHY: Notification copy should identify people without exposing credentials.
  return (
    [user?.firstName, user?.middleName, user?.lastName]
      .map((part) => (typeof part === "string" ? part.trim() : ""))
      .filter(Boolean)
      .join(" ") ||
    user?.name?.toString().trim() ||
    user?.email?.toString().trim() ||
    "Unknown user"
  );
}

function formatDateTime(value) {
  const date = value instanceof Date ? value : value ? new Date(value) : null;
  return date && !Number.isNaN(date.getTime()) ? date.toISOString() : null;
}

async function resolveStaffProfileWithUser(staffProfileId) {
  if (!isObjectId(staffProfileId)) {
    return null;
  }

  // WHY: Staff profile plus user name makes audit entries readable for management.
  return BusinessStaffProfile.findById(staffProfileId)
    .populate("userId", "firstName middleName lastName name email role")
    .lean();
}

async function resolveManagementAudience({ businessId, excludeUserIds = [] }) {
  const normalizedBusinessId = normalizeId(businessId);
  if (!isObjectId(normalizedBusinessId)) {
    return [];
  }

  const excluded = new Set(excludeUserIds.map(normalizeId).filter(Boolean));
  const owner = await User.findOne({
    _id: normalizedBusinessId,
    role: "business_owner",
  })
    .select("_id role firstName middleName lastName name email")
    .lean();
  const managerProfiles = await BusinessStaffProfile.find({
    businessId: normalizedBusinessId,
    status: "active",
    staffRole: { $in: MANAGEMENT_STAFF_ROLES },
  })
    .populate("userId", "firstName middleName lastName name email role")
    .lean();

  const audienceById = new Map();
  if (owner && !excluded.has(normalizeId(owner._id))) {
    audienceById.set(normalizeId(owner._id), {
      userId: normalizeId(owner._id),
      name: formatUserName(owner),
      role: owner.role,
    });
  }
  managerProfiles.forEach((profile) => {
    const user = profile.userId;
    const userId = normalizeId(user?._id);
    if (!userId || excluded.has(userId)) {
      return;
    }
    audienceById.set(userId, {
      userId,
      name: formatUserName(user),
      role: profile.staffRole,
    });
  });

  return [...audienceById.values()];
}

async function writeManagementNotification({
  businessId,
  actorId,
  actorRole,
  action,
  entityType,
  entityId,
  message,
  severity = "info",
  audience = [],
  details = {},
}) {
  try {
    if (!isObjectId(entityId)) {
      return null;
    }

    // WHY: One compact audit row carries both the notification marker and the
    // management audience, avoiding crowded duplicate rows.
    return writeAuditLog({
      businessId: isObjectId(businessId) ? businessId : null,
      actorId,
      actorRole: actorRole || "system",
      action,
      entityType,
      entityId,
      message,
      changes: {
        notificationEnabled: true,
        notificationAudience: "management",
        severity,
        audience,
        details,
      },
    });
  } catch (error) {
    debug(`${LOG_PREFIX}: writeManagementNotification - skipped`, {
      action,
      entityType,
      entityId: normalizeId(entityId),
      reason: error.message,
      next: "Primary operation continues; inspect audit persistence separately",
    });
    return null;
  }
}

async function notifyStaffLogin({ user }) {
  try {
    if (!user || user.role !== "staff") {
      return null;
    }

    const staffProfile = await BusinessStaffProfile.findOne({
      userId: user._id,
      status: "active",
    }).lean();
    if (!staffProfile) {
      return null;
    }

    const audience = await resolveManagementAudience({
      businessId: staffProfile.businessId,
      excludeUserIds: [user._id],
    });

    return writeManagementNotification({
      businessId: staffProfile.businessId,
      actorId: user._id,
      actorRole: user.role,
      action: "management_notification_staff_login",
      entityType: "user",
      entityId: user._id,
      message: `${formatUserName(user)} logged in as ${staffProfile.staffRole}`,
      audience,
      details: {
        staffProfileId: normalizeId(staffProfile._id),
        staffRole: staffProfile.staffRole,
        estateAssetId: normalizeId(staffProfile.estateAssetId) || null,
        loginAt: formatDateTime(new Date()),
      },
    });
  } catch (error) {
    debug(`${LOG_PREFIX}: notifyStaffLogin - skipped`, {
      userId: normalizeId(user?._id),
      reason: error.message,
      next: "Primary login continues; inspect notification audit later",
    });
    return null;
  }
}

async function notifyStaffAttendanceEvent({
  businessId,
  actor,
  attendance,
  staffProfile,
  eventType,
}) {
  try {
    const resolvedProfile =
      staffProfile || (await resolveStaffProfileWithUser(attendance?.staffProfileId));
    if (!resolvedProfile || !attendance) {
      return null;
    }

    const staffName = formatUserName(resolvedProfile.userId);
    const audience = await resolveManagementAudience({
      businessId,
      excludeUserIds: [resolvedProfile.userId?._id],
    });
    const task = isObjectId(attendance.taskId)
      ? await ProductionTask.findById(attendance.taskId)
          .select("title roleRequired")
          .lean()
      : null;
    const verb =
      eventType === "clock_out"
        ? "clocked out"
        : eventType === "clock_out_with_proof"
          ? "clocked out with proof"
          : "clocked in";

    return writeManagementNotification({
      businessId,
      actorId: actor?._id || resolvedProfile.userId?._id,
      actorRole: actor?.role || "staff",
      action: `management_notification_staff_${eventType}`,
      entityType: "staff_attendance",
      entityId: attendance._id,
      message: `${staffName} ${verb}`,
      audience,
      details: {
        staffProfileId: normalizeId(resolvedProfile._id),
        staffRole: resolvedProfile.staffRole,
        estateAssetId: normalizeId(resolvedProfile.estateAssetId) || null,
        planId: normalizeId(attendance.planId) || null,
        taskId: normalizeId(attendance.taskId) || null,
        taskTitle: task?.title || attendance.clockOutAudit?.taskTitle || "",
        workDate: formatDateTime(attendance.workDate),
        clockInAt: formatDateTime(attendance.clockInAt),
        clockOutAt: formatDateTime(attendance.clockOutAt),
        durationMinutes: attendance.durationMinutes ?? null,
        sessionStatus: attendance.sessionStatus || "",
        proofStatus: attendance.proofStatus || "",
        proofCount: Array.isArray(attendance.proofs) ? attendance.proofs.length : 0,
        requiredProofs: attendance.requiredProofs ?? 0,
        note: attendance.notes || "",
      },
    });
  } catch (error) {
    debug(`${LOG_PREFIX}: notifyStaffAttendanceEvent - skipped`, {
      attendanceId: normalizeId(attendance?._id),
      eventType,
      reason: error.message,
      next: "Primary attendance action continues; inspect audit persistence separately",
    });
    return null;
  }
}

async function notifyProductionApproval({
  businessId,
  actor,
  task = null,
  progress = null,
  approvalType,
}) {
  try {
    const resolvedTask =
      task ||
      (isObjectId(progress?.taskId)
        ? await ProductionTask.findById(progress.taskId).lean()
        : null);
    if (!resolvedTask && !progress) {
      return null;
    }

    const planId = progress?.planId || resolvedTask?.planId;
    const plan = isObjectId(planId)
      ? await ProductionPlan.findById(planId).select("estateAssetId productId").lean()
      : null;
    const audience = await resolveManagementAudience({
      businessId,
      excludeUserIds: [actor?._id],
    });
    const approvalLabel =
      approvalType === "task_progress"
        ? "Progress approved"
        : "Task assignment approved";

    return writeManagementNotification({
      businessId,
      actorId: actor?._id,
      actorRole: actor?.role || "staff",
      action: `management_notification_${approvalType}_approved`,
      entityType: approvalType === "task_progress" ? "task_progress" : "production_task",
      entityId: progress?._id || resolvedTask?._id,
      message: `${approvalLabel}: ${resolvedTask?.title || "Production task"}`,
      severity: "success",
      audience,
      details: {
        planId: normalizeId(planId) || null,
        taskId: normalizeId(resolvedTask?._id) || null,
        taskTitle: resolvedTask?.title || "",
        roleRequired: resolvedTask?.roleRequired || "",
        estateAssetId: normalizeId(plan?.estateAssetId) || null,
        workDate: formatDateTime(progress?.workDate),
        approvedAt: formatDateTime(progress?.approvedAt || resolvedTask?.reviewedAt),
        approvedBy: normalizeId(actor?._id) || null,
        actualPlots: progress?.actualPlots ?? null,
        expectedPlots: progress?.expectedPlots ?? null,
        proofCount: Array.isArray(progress?.proofs) ? progress.proofs.length : null,
      },
    });
  } catch (error) {
    debug(`${LOG_PREFIX}: notifyProductionApproval - skipped`, {
      approvalType,
      taskId: normalizeId(task?._id || progress?.taskId),
      reason: error.message,
      next: "Primary approval continues; inspect notification audit later",
    });
    return null;
  }
}

async function notifyChatMessage({ actor, conversation, message }) {
  try {
    if (!conversation || !message) {
      return null;
    }

    const audience = await ChatParticipant.find({
      conversationId: conversation._id,
      userId: { $ne: actor._id },
      isHidden: false,
    })
      .select("userId roleAtJoin")
      .lean();

    return writeManagementNotification({
      businessId: conversation.businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action: "management_notification_chat_message_received",
      entityType: "chat_message",
      entityId: message._id,
      message: `New chat message from ${formatUserName(actor)}`,
      audience: audience.map((entry) => ({
        userId: normalizeId(entry.userId),
        role: entry.roleAtJoin || "participant",
      })),
      details: {
        conversationId: normalizeId(conversation._id),
        senderUserId: normalizeId(actor._id),
        senderRole: actor.role,
        messageType: message.type || "",
        hasAttachments:
          Array.isArray(message.attachmentIds) && message.attachmentIds.length > 0,
        attachmentCount: Array.isArray(message.attachmentIds)
          ? message.attachmentIds.length
          : 0,
        preview: (message.body || "").toString().trim().slice(0, 160),
        sentAt: formatDateTime(message.createdAt || new Date()),
      },
    });
  } catch (error) {
    debug(`${LOG_PREFIX}: notifyChatMessage - skipped`, {
      conversationId: normalizeId(conversation?._id),
      messageId: normalizeId(message?._id),
      reason: error.message,
      next: "Primary chat send continues; inspect notification audit later",
    });
    return null;
  }
}

module.exports = {
  notifyStaffLogin,
  notifyStaffAttendanceEvent,
  notifyProductionApproval,
  notifyChatMessage,
};
