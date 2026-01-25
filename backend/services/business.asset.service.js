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

  const asset = new BusinessAsset({
    ...payload,
    businessId,
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

  Object.assign(asset, payload);
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
  getAssets,
  updateAsset,
  softDeleteAsset,
};
