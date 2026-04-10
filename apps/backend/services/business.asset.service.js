/**
 * apps/backend/services/business.asset.service.js
 * -----------------------------------------------
 * WHAT:
 * - Business-scoped asset management service.
 *
 * WHY:
 * - Lets businesses track operational assets with audit trails.
 *
 * HOW:
 * - Filters by businessId and logs changes.
 */

const BusinessAsset = require("../models/BusinessAsset");
const {
  writeAuditLog,
} = require("../utils/audit");
const {
  writeAnalyticsEvent,
} = require("../utils/analytics");
const {
  getPagination,
} = require("../utils/pagination");
const debug = require("../utils/debug");

// WHY: Rent amounts should be stored in kobo (minor units).
const NAIRA_TO_KOBO = 100;
const APPROVAL_PENDING = "pending_approval";
const APPROVAL_APPROVED = "approved";
const APPROVAL_REJECTED = "rejected";
const FARM_APPROVER_STAFF_ROLES = new Set([
  "farm_manager",
  "asset_manager",
  "estate_manager",
  "shareholder",
]);
const TIME_24H_REGEX = /^([01]\d|2[0-3]):([0-5]\d)$/;

function buildNextAuditDate(lastAuditDate, auditFrequency) {
  if (!lastAuditDate || !auditFrequency) {
    return null;
  }

  const base = new Date(lastAuditDate);
  if (Number.isNaN(base.getTime())) {
    return null;
  }

  const next = new Date(base);
  if (auditFrequency === "quarterly") {
    next.setMonth(next.getMonth() + 3);
    return next;
  }
  if (auditFrequency === "yearly") {
    next.setFullYear(next.getFullYear() + 1);
    return next;
  }
  return null;
}

function startOfQuarter(date) {
  const month = Math.floor(date.getMonth() / 3) * 3;
  return new Date(date.getFullYear(), month, 1, 0, 0, 0, 0);
}

function endOfQuarter(date) {
  const start = startOfQuarter(date);
  return new Date(start.getFullYear(), start.getMonth() + 3, 0, 23, 59, 59, 999);
}

function quarterLabel(date) {
  const quarter = Math.floor(date.getMonth() / 3) + 1;
  return `Q${quarter}`;
}

function parsePositiveNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return parsed;
}

function parseNonNegativeNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return parsed;
}

function parseDateValue(value) {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
}

function trimText(value, fallback = "") {
  const text = value?.toString?.().trim?.() || "";
  return text || fallback;
}

function normalizeTimeText(value, fieldLabel) {
  const text = trimText(value);
  if (!text) {
    throw new Error(`${fieldLabel} is required`);
  }
  if (!TIME_24H_REGEX.test(text)) {
    throw new Error(`${fieldLabel} must use HH:MM format`);
  }
  return text;
}

function normalizeOptionalTimeText(value, fieldLabel) {
  const text = trimText(value);
  if (!text) {
    return "";
  }
  if (!TIME_24H_REGEX.test(text)) {
    throw new Error(`${fieldLabel} must use HH:MM format`);
  }
  return text;
}

function parsePositiveIntegerValue(value, fieldLabel) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${fieldLabel} must be greater than zero`);
  }
  return Math.round(parsed);
}

function buildActorSnapshot(actor) {
  if (!actor?.id) {
    return null;
  }

  return {
    userId: actor.id,
    name: trimText(actor.name, trimText(actor.email, "Unknown user")),
    actorRole: trimText(actor.role),
    staffRole: trimText(actor.staffRole),
    email: trimText(actor.email),
  };
}

function isFarmApprover(actor) {
  if (actor?.role === "business_owner") {
    return true;
  }

  return (
    actor?.role === "staff" &&
    FARM_APPROVER_STAFF_ROLES.has(
      trimText(actor?.staffRole),
    )
  );
}

function ensureFarmContextPayload(payload) {
  if (!payload || payload.domainContext !== "farm" || !payload.farmProfile) {
    throw new Error("Farm asset payload is required");
  }

  return payload;
}

function normalizeFarmAuditRequestPayload(payload) {
  const auditDate = parseDateValue(
    payload?.auditDate,
  );
  if (!auditDate) {
    throw new Error("Audit date is required");
  }

  const resultingStatus = trimText(
    payload?.status,
    "active",
  );
  if (!["active", "inactive", "maintenance"].includes(resultingStatus)) {
    throw new Error("Audit status must be active, inactive, or maintenance");
  }

  return {
    auditDate,
    resultingStatus,
    estimatedCurrentValue: parseNonNegativeNumber(
      payload?.estimatedCurrentValue,
      0,
    ),
    note: trimText(payload?.note),
  };
}

function normalizeFarmToolUsagePayload(payload, asset) {
  const productionDate = parseDateValue(
    payload?.productionDate,
  );
  if (!productionDate) {
    throw new Error("Production date is required");
  }

  const quantityRequested = parsePositiveIntegerValue(
    payload?.quantityRequested,
    "Requested quantity",
  );
  const rawQuantityUsed = payload?.quantityUsed;
  const quantityUsed =
    rawQuantityUsed == null ||
      trimText(rawQuantityUsed).length === 0
      ? quantityRequested
      : parsePositiveIntegerValue(
          rawQuantityUsed,
          "Used quantity",
        );

  const availableQuantity = Math.max(
    1,
    parsePositiveNumber(
      asset?.farmProfile?.quantity,
      asset?.inventory?.quantity || 1,
    ),
  );
  if (
    quantityRequested > availableQuantity ||
    quantityUsed > availableQuantity
  ) {
    throw new Error(
      `Requested or used quantity cannot exceed tracked quantity (${availableQuantity})`,
    );
  }

  return {
    productionDate,
    usageStartTime: normalizeTimeText(
      payload?.usageStartTime,
      "Usage start time",
    ),
    usageEndTime: normalizeOptionalTimeText(
      payload?.usageEndTime,
      "Usage end time",
    ),
    productionActivity: trimText(
      payload?.productionActivity,
    ),
    quantityRequested,
    quantityUsed,
    note: trimText(payload?.note),
  };
}

function applyApprovedFarmAudit({
  asset,
  auditRequest,
}) {
  asset.farmProfile = asset.farmProfile || {};
  asset.status =
    auditRequest.resultingStatus || asset.status;
  asset.farmProfile.lastAuditDate =
    auditRequest.auditDate;
  asset.farmProfile.estimatedCurrentValue =
    parseNonNegativeNumber(
      auditRequest.estimatedCurrentValue,
      asset.farmProfile.estimatedCurrentValue || 0,
    );
  asset.farmProfile.lastAuditSubmittedBy =
    auditRequest.requestedBy || null;
  asset.farmProfile.lastAuditSubmittedAt =
    auditRequest.requestedAt || new Date();
  asset.farmProfile.lastAuditNote =
    trimText(auditRequest.note);
  asset.farmProfile.pendingAuditRequest = null;
}

function getFarmUsageRequests(asset) {
  asset.farmProfile = asset.farmProfile || {};
  if (!Array.isArray(asset.farmProfile.productionUsageRequests)) {
    asset.farmProfile.productionUsageRequests = [];
  }
  return asset.farmProfile.productionUsageRequests;
}

function resolveFarmUsageRequest(asset, requestId) {
  const normalizedRequestId = trimText(
    requestId,
  );
  if (!normalizedRequestId) {
    throw new Error("Usage request id is required");
  }

  const request = getFarmUsageRequests(asset).find(
    (item) =>
      item?._id?.toString?.() ===
      normalizedRequestId,
  );
  if (!request) {
    throw new Error("No matching production usage request found");
  }
  return request;
}

// WHY: Ensure estate unit mix rent amounts are saved in kobo consistently.
function normalizeEstateUnitMix(payload) {
  // WHY: Guard against null payloads to keep updates safe.
  if (!payload) {
    return {};
  }
  if (!payload?.estate?.unitMix) {
    return payload;
  }

  const unitMix = Array.isArray(payload.estate.unitMix)
    ? payload.estate.unitMix
    : [];
  let convertedCount = 0;

  for (const unit of unitMix) {
    // WHY: UI supplies naira; we persist kobo for payment safety.
    const rawRent = Number(unit?.rentAmount ?? 0);
    if (!Number.isFinite(rawRent) || rawRent <= 0) {
      continue;
    }
    unit.rentAmount = Math.round(
      rawRent * NAIRA_TO_KOBO,
    );
    convertedCount += 1;
  }

  if (convertedCount > 0) {
    debug(
      "BUSINESS ASSET SERVICE: normalized unit mix rent amounts",
      { convertedCount },
    );
  }

  return payload;
}

async function createAsset({
  businessId,
  actor,
  payload,
}) {
  debug(
    "BUSINESS ASSET SERVICE: createAsset",
    {
      businessId,
      actorId: actor?.id,
    },
  );

  if (!businessId) {
    throw new Error(
      "Business scope is required",
    );
  }

  // WHY: Normalize rent amounts before persisting estate assets.
  const normalizedPayload = normalizeEstateUnitMix(
    payload,
  );
  const actorSnapshot = buildActorSnapshot(
    actor,
  );
  const approvalRequestedAt =
    normalizedPayload?.approvalRequestedAt || new Date();
  const approvalStatus =
    trimText(
      normalizedPayload?.approvalStatus,
      APPROVAL_APPROVED,
    ) || APPROVAL_APPROVED;

  const asset = new BusinessAsset({
    ...normalizedPayload,
    businessId,
    approvalStatus,
    approvalRequestedBy:
      normalizedPayload?.approvalRequestedBy ||
      actorSnapshot,
    approvalRequestedAt,
    approvalReviewedBy:
      approvalStatus === APPROVAL_APPROVED ?
        normalizedPayload?.approvalReviewedBy ||
        actorSnapshot
      : normalizedPayload?.approvalReviewedBy || null,
    approvalReviewedAt:
      approvalStatus === APPROVAL_APPROVED ?
        normalizedPayload?.approvalReviewedAt || approvalRequestedAt
      : normalizedPayload?.approvalReviewedAt || null,
    approvalNote:
      trimText(normalizedPayload?.approvalNote),
    createdBy: actor?.id,
    updatedBy: actor?.id,
  });

  await asset.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: "asset_create",
    entityType: "business_asset",
    entityId: asset._id,
    message: `Asset created: ${asset.name}`,
  });

  // WHY: Track asset creation for analytics and operations dashboards.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: "asset_created",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      assetType: asset.assetType,
      status: asset.status,
      approvalStatus: asset.approvalStatus,
    },
  });

  return asset;
}

async function submitFarmAsset({
  businessId,
  actor,
  payload,
}) {
  debug(
    "BUSINESS ASSET SERVICE: submitFarmAsset",
    {
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      staffRole: actor?.staffRole,
    },
  );

  if (!businessId) {
    throw new Error("Business scope is required");
  }

  const farmPayload = ensureFarmContextPayload(payload);
  const normalizedPayload = normalizeEstateUnitMix(farmPayload);
  const actorSnapshot = buildActorSnapshot(actor);
  const submittedAt = new Date();
  const autoApprove = isFarmApprover(actor);
  const approvalStatus =
    autoApprove ? APPROVAL_APPROVED : APPROVAL_PENDING;

  const asset = new BusinessAsset({
    ...normalizedPayload,
    businessId,
    approvalStatus,
    approvalRequestedBy: actorSnapshot,
    approvalRequestedAt: submittedAt,
    approvalReviewedBy: autoApprove ? actorSnapshot : null,
    approvalReviewedAt: autoApprove ? submittedAt : null,
    approvalNote: autoApprove
      ? "approved_on_submission"
      : "awaiting_manager_approval",
    createdBy: actor?.id,
    updatedBy: actor?.id,
  });

  await asset.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: autoApprove
      ? "farm_asset_created"
      : "farm_asset_submission_requested",
    entityType: "business_asset",
    entityId: asset._id,
    message: autoApprove
      ? `Farm asset created: ${asset.name}`
      : `Farm asset submitted for approval: ${asset.name}`,
    changes: {
      approvalStatus,
      submittedBy: actorSnapshot,
      farmCategory: asset.farmProfile?.farmCategory || "",
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: autoApprove
      ? "farm_asset_created"
      : "farm_asset_submission_requested",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      approvalStatus,
      assetType: asset.assetType,
      status: asset.status,
      farmCategory: asset.farmProfile?.farmCategory || "",
      submittedByRole: actor?.staffRole || actor?.role || "",
    },
  });

  return asset;
}

async function getAssets({
  businessId,
  query,
  assetId,
}) {
  debug(
    "BUSINESS ASSET SERVICE: getAssets",
    {
      businessId,
      query,
      assetId,
    },
  );

  if (!businessId) {
    throw new Error(
      "Business scope is required",
    );
  }

  const { page, limit, skip } =
    getPagination(query);
  const filter = { businessId };

  // WHY: Estate-scoped staff can only list their assigned estate asset.
  if (assetId) {
    filter._id = assetId;
  }

  if (query?.status) {
    filter.status = query.status;
  }

  if (query?.assetType) {
    filter.assetType = query.assetType;
  }

  if (query?.domainContext) {
    filter.domainContext = query.domainContext;
  }

  if (query?.farmCategory) {
    filter["farmProfile.farmCategory"] = query.farmCategory;
  }

  if (query?.auditFrequency) {
    filter["farmProfile.auditFrequency"] = query.auditFrequency;
  }

  const [assets, total] =
    await Promise.all([
      BusinessAsset.find(filter)
        .select({ __v: 0 })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      BusinessAsset.countDocuments(
        filter,
      ),
    ]);

  return {
    assets,
    total,
    page,
    limit,
  };
}

async function getFarmAssetAuditAnalytics({
  businessId,
  query,
}) {
  debug(
    "BUSINESS ASSET SERVICE: getFarmAssetAuditAnalytics",
    {
      businessId,
      query,
    }
  );

  if (!businessId) {
    throw new Error("Business scope is required");
  }

  const filter = {
    businessId,
    domainContext: "farm",
    deletedAt: null,
    approvalStatus: {
      $nin: [APPROVAL_PENDING, APPROVAL_REJECTED],
    },
  };

  if (query?.status) {
    filter.status = query.status;
  }
  if (query?.assetType) {
    filter.assetType = query.assetType;
  }
  if (query?.farmCategory) {
    filter["farmProfile.farmCategory"] = query.farmCategory;
  }
  if (query?.auditFrequency) {
    filter["farmProfile.auditFrequency"] = query.auditFrequency;
  }

  const assets = await BusinessAsset.find(filter)
    .select({ __v: 0 })
    .sort({ createdAt: -1 })
    .lean();

  const now = new Date();
  const selectedYear = Number.parseInt(query?.year, 10) || now.getFullYear();
  const quarterStart = startOfQuarter(now);
  const quarterEnd = endOfQuarter(now);

  const categoryBreakdown = new Map();
  const statusBreakdown = new Map();
  const cadenceBreakdown = new Map();
  const quarterBreakdown = new Map([
    ["Q1", 0],
    ["Q2", 0],
    ["Q3", 0],
    ["Q4", 0],
  ]);

  let totalQuantity = 0;
  let totalEstimatedValue = 0;
  let dueThisQuarter = 0;
  let dueThisYear = 0;
  let overdueCount = 0;

  const attentionAssets = [];

  for (const asset of assets) {
    const farmProfile = asset.farmProfile || {};
    const quantity = Math.max(1, Math.round(parsePositiveNumber(
      farmProfile.quantity ?? asset.inventory?.quantity ?? 1,
      1
    )));
    const estimatedCurrentValue = parsePositiveNumber(
      farmProfile.estimatedCurrentValue ??
        asset.purchaseCost ??
        (asset.inventory?.unitCost || 0) * quantity,
      0
    );
    const category = (farmProfile.farmCategory || "uncategorized").trim();
    const cadence = (farmProfile.auditFrequency || "unscheduled").trim();
    const status = (asset.status || "inactive").trim();

    totalQuantity += quantity;
    totalEstimatedValue += estimatedCurrentValue;

    const categoryBucket = categoryBreakdown.get(category) || {
      label: category,
      assetCount: 0,
      quantity: 0,
      estimatedValue: 0,
    };
    categoryBucket.assetCount += 1;
    categoryBucket.quantity += quantity;
    categoryBucket.estimatedValue += estimatedCurrentValue;
    categoryBreakdown.set(category, categoryBucket);

    statusBreakdown.set(status, (statusBreakdown.get(status) || 0) + 1);
    cadenceBreakdown.set(cadence, (cadenceBreakdown.get(cadence) || 0) + 1);

    const nextAuditDate =
      farmProfile.nextAuditDate ||
      buildNextAuditDate(farmProfile.lastAuditDate, farmProfile.auditFrequency);

    if (!nextAuditDate) {
      continue;
    }

    const nextAudit = new Date(nextAuditDate);
    if (Number.isNaN(nextAudit.getTime())) {
      continue;
    }

    if (nextAudit < now) {
      overdueCount += 1;
    }
    if (nextAudit >= quarterStart && nextAudit <= quarterEnd) {
      dueThisQuarter += 1;
    }
    if (nextAudit.getFullYear() === selectedYear) {
      dueThisYear += 1;
      const label = quarterLabel(nextAudit);
      quarterBreakdown.set(label, (quarterBreakdown.get(label) || 0) + 1);
    }

    attentionAssets.push({
      id: asset._id.toString(),
      name: asset.name,
      category,
      status,
      quantity,
      nextAuditDate: nextAudit,
      estimatedCurrentValue,
    });
  }

  attentionAssets.sort((left, right) => {
    if (!left.nextAuditDate && !right.nextAuditDate) {
      return 0;
    }
    if (!left.nextAuditDate) {
      return 1;
    }
    if (!right.nextAuditDate) {
      return -1;
    }
    return new Date(left.nextAuditDate) - new Date(right.nextAuditDate);
  });

  return {
    selectedYear,
    summary: {
      totalAssets: assets.length,
      totalQuantity,
      totalEstimatedValue,
      dueThisQuarter,
      dueThisYear,
      overdueCount,
    },
    categoryBreakdown: Array.from(categoryBreakdown.values()).sort(
      (left, right) => right.estimatedValue - left.estimatedValue
    ),
    statusBreakdown: Array.from(statusBreakdown.entries()).map(([label, count]) => ({
      label,
      count,
    })),
    cadenceBreakdown: Array.from(cadenceBreakdown.entries()).map(([label, count]) => ({
      label,
      count,
    })),
    quarterBreakdown: Array.from(quarterBreakdown.entries()).map(
      ([label, dueCount]) => ({
        label,
        dueCount,
      })
    ),
    attentionAssets: attentionAssets.slice(0, 6),
  };
}

async function submitFarmAssetAudit({
  businessId,
  assetId,
  actor,
  payload,
}) {
  debug(
    "BUSINESS ASSET SERVICE: submitFarmAssetAudit",
    {
      businessId,
      assetId,
      actorId: actor?.id,
      actorRole: actor?.role,
      staffRole: actor?.staffRole,
    },
  );

  if (!businessId) {
    throw new Error("Business scope is required");
  }

  const asset = await BusinessAsset.findOne({
    _id: assetId,
    businessId,
    deletedAt: null,
  });
  if (!asset) {
    throw new Error("Asset not found");
  }
  if (asset.domainContext !== "farm") {
    throw new Error("Only farm equipment supports audit requests");
  }
  if (asset.approvalStatus === APPROVAL_PENDING) {
    throw new Error("Approve the farm equipment before requesting an audit");
  }

  const actorSnapshot = buildActorSnapshot(actor);
  const auditRequest = {
    status: APPROVAL_PENDING,
    requestedBy: actorSnapshot,
    requestedAt: new Date(),
    ...normalizeFarmAuditRequestPayload(payload),
  };

  const autoApprove = isFarmApprover(actor);
  if (
    !autoApprove &&
    asset.farmProfile?.pendingAuditRequest?.status === APPROVAL_PENDING
  ) {
    throw new Error("An audit approval request is already pending for this item");
  }

  if (autoApprove) {
    applyApprovedFarmAudit({
      asset,
      auditRequest,
    });
  } else {
    asset.farmProfile = asset.farmProfile || {};
    asset.farmProfile.pendingAuditRequest = auditRequest;
  }

  asset.updatedBy = actor?.id || asset.updatedBy;
  await asset.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: autoApprove
      ? "farm_asset_audit_recorded"
      : "farm_asset_audit_requested",
    entityType: "business_asset",
    entityId: asset._id,
    message: autoApprove
      ? `Farm audit recorded: ${asset.name}`
      : `Farm audit submitted for approval: ${asset.name}`,
    changes: {
      approvalStatus: autoApprove ? APPROVAL_APPROVED : APPROVAL_PENDING,
      auditDate: auditRequest.auditDate,
      requestedBy: actorSnapshot,
      resultingStatus: auditRequest.resultingStatus,
      estimatedCurrentValue: auditRequest.estimatedCurrentValue,
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: autoApprove
      ? "farm_asset_audit_recorded"
      : "farm_asset_audit_requested",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      assetType: asset.assetType,
      approvalStatus: autoApprove ? APPROVAL_APPROVED : APPROVAL_PENDING,
      auditDate: auditRequest.auditDate,
      resultingStatus: auditRequest.resultingStatus,
      farmCategory: asset.farmProfile?.farmCategory || "",
      requestedByRole: actor?.staffRole || actor?.role || "",
    },
  });

  return asset;
}

async function submitFarmToolUsageRequest({
  businessId,
  assetId,
  actor,
  payload,
}) {
  debug(
    "BUSINESS ASSET SERVICE: submitFarmToolUsageRequest",
    {
      businessId,
      assetId,
      actorId: actor?.id,
      actorRole: actor?.role,
      staffRole: actor?.staffRole,
    },
  );

  if (!businessId) {
    throw new Error("Business scope is required");
  }

  const asset = await BusinessAsset.findOne({
    _id: assetId,
    businessId,
    deletedAt: null,
  });
  if (!asset) {
    throw new Error("Asset not found");
  }
  if (asset.domainContext !== "farm") {
    throw new Error("Only farm equipment supports production usage requests");
  }
  if (asset.approvalStatus === APPROVAL_PENDING) {
    throw new Error("Approve the farm equipment before requesting tool usage");
  }

  const actorSnapshot = buildActorSnapshot(actor);
  const autoApprove = isFarmApprover(actor);
  const usageRequest = {
    status: autoApprove ? APPROVAL_APPROVED : APPROVAL_PENDING,
    requestedBy: actorSnapshot,
    requestedAt: new Date(),
    ...normalizeFarmToolUsagePayload(payload, asset),
    approvedBy: autoApprove ? actorSnapshot : null,
    approvedAt: autoApprove ? new Date() : null,
  };

  getFarmUsageRequests(asset).unshift(usageRequest);
  asset.updatedBy = actor?.id || asset.updatedBy;
  await asset.save();

  const savedUsageRequest =
    asset.farmProfile?.productionUsageRequests?.[0];

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: autoApprove
      ? "farm_tool_usage_logged"
      : "farm_tool_usage_requested",
    entityType: "business_asset",
    entityId: asset._id,
    message: autoApprove
      ? `Production tool usage logged: ${asset.name}`
      : `Production tool usage submitted for approval: ${asset.name}`,
    changes: {
      requestId:
        savedUsageRequest?._id?.toString?.() || "",
      approvalStatus: usageRequest.status,
      requestedBy: actorSnapshot,
      productionDate: usageRequest.productionDate,
      quantityRequested:
        usageRequest.quantityRequested,
      quantityUsed:
        usageRequest.quantityUsed,
      productionActivity:
        usageRequest.productionActivity,
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: autoApprove
      ? "farm_tool_usage_logged"
      : "farm_tool_usage_requested",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      requestId:
        savedUsageRequest?._id?.toString?.() || "",
      approvalStatus: usageRequest.status,
      assetType: asset.assetType,
      farmCategory: asset.farmProfile?.farmCategory || "",
      productionDate: usageRequest.productionDate,
      quantityRequested:
        usageRequest.quantityRequested,
      quantityUsed:
        usageRequest.quantityUsed,
      requestedByRole:
        actor?.staffRole || actor?.role || "",
    },
  });

  return asset;
}

async function approveFarmAssetRequest({
  businessId,
  assetId,
  actor,
  requestType,
  requestId,
}) {
  debug(
    "BUSINESS ASSET SERVICE: approveFarmAssetRequest",
    {
      businessId,
      assetId,
      actorId: actor?.id,
      actorRole: actor?.role,
      staffRole: actor?.staffRole,
      requestType,
    },
  );

  if (!businessId) {
    throw new Error("Business scope is required");
  }
  if (!isFarmApprover(actor)) {
    throw new Error("Only estate managers, farm managers, asset managers, or business owners can approve");
  }

  const asset = await BusinessAsset.findOne({
    _id: assetId,
    businessId,
    deletedAt: null,
  });
  if (!asset) {
    throw new Error("Asset not found");
  }

  const reviewSnapshot = buildActorSnapshot(actor);
  const normalizedRequestType = trimText(
    requestType,
  ).toLowerCase();
  const shouldApproveUsage =
    normalizedRequestType === "usage";
  const shouldApproveAudit =
    normalizedRequestType === "audit" ||
    (
      !shouldApproveUsage &&
      normalizedRequestType.length === 0 &&
      asset.farmProfile?.pendingAuditRequest?.status === APPROVAL_PENDING
    );

  if (shouldApproveUsage) {
    const pendingUsageRequest =
      resolveFarmUsageRequest(
        asset,
        requestId,
      );
    if (
      pendingUsageRequest.status !==
      APPROVAL_PENDING
    ) {
      throw new Error(
        "This production usage request is not pending approval",
      );
    }

    pendingUsageRequest.status =
      APPROVAL_APPROVED;
    pendingUsageRequest.approvedBy =
      reviewSnapshot;
    pendingUsageRequest.approvedAt =
      new Date();
    asset.updatedBy =
      actor?.id || asset.updatedBy;
    await asset.save();

    await writeAuditLog({
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      action: "farm_tool_usage_approved",
      entityType: "business_asset",
      entityId: asset._id,
      message: `Production tool usage approved: ${asset.name}`,
      changes: {
        requestId:
          pendingUsageRequest._id?.toString?.() || "",
        approvedBy: reviewSnapshot,
        quantityRequested:
          pendingUsageRequest.quantityRequested,
        quantityUsed:
          pendingUsageRequest.quantityUsed,
        productionDate:
          pendingUsageRequest.productionDate,
        usageStartTime:
          pendingUsageRequest.usageStartTime,
        usageEndTime:
          pendingUsageRequest.usageEndTime,
      },
    });

    await writeAnalyticsEvent({
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      eventType: "farm_tool_usage_approved",
      entityType: "business_asset",
      entityId: asset._id,
      metadata: {
        requestId:
          pendingUsageRequest._id?.toString?.() || "",
        farmCategory:
          asset.farmProfile?.farmCategory || "",
        productionDate:
          pendingUsageRequest.productionDate,
        quantityRequested:
          pendingUsageRequest.quantityRequested,
        quantityUsed:
          pendingUsageRequest.quantityUsed,
        approvedByRole:
          actor?.staffRole || actor?.role || "",
      },
    });

    return asset;
  }

  if (shouldApproveAudit) {
    const pendingAudit =
      asset.farmProfile?.pendingAuditRequest;
    if (!pendingAudit || pendingAudit.status !== APPROVAL_PENDING) {
      throw new Error("No pending farm audit request found");
    }

    pendingAudit.status = APPROVAL_APPROVED;
    pendingAudit.approvedBy = reviewSnapshot;
    pendingAudit.approvedAt = new Date();
    applyApprovedFarmAudit({
      asset,
      auditRequest: pendingAudit,
    });
    asset.updatedBy = actor?.id || asset.updatedBy;
    await asset.save();

    await writeAuditLog({
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      action: "farm_asset_audit_approved",
      entityType: "business_asset",
      entityId: asset._id,
      message: `Farm audit approved: ${asset.name}`,
      changes: {
        approvedBy: reviewSnapshot,
        auditDate: pendingAudit.auditDate,
        resultingStatus: pendingAudit.resultingStatus,
      },
    });

    await writeAnalyticsEvent({
      businessId,
      actorId: actor?.id,
      actorRole: actor?.role,
      eventType: "farm_asset_audit_approved",
      entityType: "business_asset",
      entityId: asset._id,
      metadata: {
        resultingStatus: pendingAudit.resultingStatus,
        farmCategory: asset.farmProfile?.farmCategory || "",
        approvedByRole: actor?.staffRole || actor?.role || "",
      },
    });

    return asset;
  }

  if (asset.approvalStatus !== APPROVAL_PENDING) {
    throw new Error("No pending farm equipment approval found");
  }

  asset.approvalStatus = APPROVAL_APPROVED;
  asset.approvalReviewedBy = reviewSnapshot;
  asset.approvalReviewedAt = new Date();
  asset.approvalNote = "approved_by_manager";
  asset.updatedBy = actor?.id || asset.updatedBy;
  await asset.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: "farm_asset_approved",
    entityType: "business_asset",
    entityId: asset._id,
    message: `Farm asset approved: ${asset.name}`,
    changes: {
      approvedBy: reviewSnapshot,
      submittedBy: asset.approvalRequestedBy || null,
      approvalStatus: asset.approvalStatus,
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: "farm_asset_approved",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      assetType: asset.assetType,
      status: asset.status,
      farmCategory: asset.farmProfile?.farmCategory || "",
      approvedByRole: actor?.staffRole || actor?.role || "",
    },
  });

  return asset;
}

async function updateAsset({
  businessId,
  assetId,
  payload,
  actor,
}) {
  debug(
    "BUSINESS ASSET SERVICE: updateAsset",
    {
      businessId,
      assetId,
      actorId: actor?.id,
    },
  );

  if (!businessId) {
    throw new Error(
      "Business scope is required",
    );
  }

  const asset =
    await BusinessAsset.findOne({
      _id: assetId,
      businessId,
    });
  if (!asset) {
    throw new Error("Asset not found");
  }

  const before = {
    name: asset.name,
    assetType: asset.assetType,
    status: asset.status,
  };

  // WHY: Normalize rent amounts before updating estate assets.
  const normalizedPayload = normalizeEstateUnitMix(
    payload,
  );

  Object.assign(asset, normalizedPayload);
  asset.updatedBy =
    actor?.id || asset.updatedBy;
  await asset.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: "asset_update",
    entityType: "business_asset",
    entityId: asset._id,
    message: `Asset updated: ${asset.name}`,
    changes: {
      before,
      after: {
        name: asset.name,
        assetType: asset.assetType,
        status: asset.status,
      },
    },
  });

  // WHY: Keep asset update events for analytics timelines.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: "asset_updated",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: {
      assetType: asset.assetType,
      status: asset.status,
    },
  });

  return asset;
}

async function softDeleteAsset({
  businessId,
  assetId,
  actor,
}) {
  debug(
    "BUSINESS ASSET SERVICE: softDeleteAsset",
    {
      businessId,
      assetId,
      actorId: actor?.id,
    },
  );

  if (!businessId) {
    throw new Error(
      "Business scope is required",
    );
  }

  const asset =
    await BusinessAsset.findOneAndUpdate(
      { _id: assetId, businessId },
      {
        deletedAt: new Date(),
        deletedBy: actor?.id,
        updatedBy: actor?.id,
        status: "inactive",
      },
      {
        new: true,
        runValidators: true,
      },
    ).select({ __v: 0 });

  if (!asset) {
    throw new Error("Asset not found");
  }

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: "asset_soft_delete",
    entityType: "business_asset",
    entityId: asset._id,
    message: `Asset soft deleted: ${asset.name}`,
  });

  // WHY: Track asset removal for audit-friendly analytics.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: "asset_archived",
    entityType: "business_asset",
    entityId: asset._id,
    metadata: { status: asset.status },
  });

  return asset;
}

module.exports = {
  createAsset,
  submitFarmAsset,
  getAssets,
  getFarmAssetAuditAnalytics,
  submitFarmAssetAudit,
  submitFarmToolUsageRequest,
  approveFarmAssetRequest,
  updateAsset,
  softDeleteAsset,
};
