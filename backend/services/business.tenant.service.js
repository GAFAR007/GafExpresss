/**
 * apps/backend/services/business.tenant.service.js
 * ------------------------------------------------
 * WHAT:
 * - Tenant-specific estate verification service.
 *
 * WHY:
 * - Keeps tenant onboarding auditable and scoped to a single estate asset.
 * - Centralizes validation rules (references, guarantors, agreement).
 *
 * HOW:
 * - Loads the estate asset for the tenant.
 * - Validates unit selection + tenant rules.
 * - Creates a BusinessTenantApplication record with snapshots.
 */

const BusinessAsset = require("../models/BusinessAsset");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");
const {
  writeAuditLog,
} = require("../utils/audit");
const {
  writeAnalyticsEvent,
} = require("../utils/analytics");
const debug = require("../utils/debug");

function normalizeUnitType(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase();
}

function parseDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ?
      null
    : date;
}

function clampList(list) {
  // WHY: Normalize user payloads to arrays for predictable validation.
  return Array.isArray(list) ? list : (
      []
    );
}

function buildDisplayName(user) {
  // WHY: Prefer verified split names when available (NIN), fall back to legacy name.
  if (!user) return "";
  const first =
    user.firstName?.toString().trim() ||
    "";
  const middle =
    user.middleName
      ?.toString()
      .trim() || "";
  const last =
    user.lastName?.toString().trim() ||
    "";
  const combined = [first, middle, last]
    .filter(Boolean)
    .join(" ")
    .trim();
  if (combined) return combined;
  return (
    user.name?.toString().trim() || ""
  );
}

function resolveTenantSnapshot(
  application,
) {
  // WHY: Tenant list/detail screens rely on snapshot fields for display consistency.
  if (!application) return application;

  const existing =
    application.tenantSnapshot || {};
  const tenantUser =
    application.tenantUserId || {};
  const resolved = {
    name:
      existing.name ||
      buildDisplayName(tenantUser),
    email:
      existing.email ||
      tenantUser.email,
    phone:
      existing.phone ||
      tenantUser.phone,
    ninLast4:
      existing.ninLast4 ||
      tenantUser.ninLast4,
  };

  const usedFallback = {
    name: Boolean(
      resolved.name && !existing.name,
    ),
    email: Boolean(
      resolved.email && !existing.email,
    ),
    phone: Boolean(
      resolved.phone && !existing.phone,
    ),
    ninLast4: Boolean(
      resolved.ninLast4 &&
      !existing.ninLast4,
    ),
  };

  // WHY: Log only whether we backfilled fields, never the actual identity values.
  if (
    usedFallback.name ||
    usedFallback.email ||
    usedFallback.phone ||
    usedFallback.ninLast4
  ) {
    debug(
      "BUSINESS TENANT SERVICE: tenant snapshot backfilled",
      {
        applicationId: application._id,
        usedFallback,
      },
    );
  }

  return {
    ...application,
    tenantSnapshot: {
      ...existing,
      ...resolved,
    },
  };
}

function toContactList(list) {
  return clampList(list)
    .map((item) => ({
      name: item?.name
        ?.toString()
        .trim(),
      phone:
        item?.phone
          ?.toString()
          .trim() || null,
    }))
    .filter((item) => item.name);
}

async function findLatestTenantApplication({
  businessId,
  estateAssetId,
  tenantUserId,
}) {
  // WHY: Reuse a single lookup path for tenant self-service reads/updates.
  if (
    !businessId ||
    !estateAssetId ||
    !tenantUserId
  ) {
    throw new Error(
      "Tenant application lookup requires business, estate, and tenant",
    );
  }

  return BusinessTenantApplication.findOne(
    {
      businessId,
      estateAssetId,
      tenantUserId,
    },
  )
    .sort({ createdAt: -1 })
    .populate(
      "estateAssetId",
      "name estate.unitMix estate.tenantRules",
    )
    .populate(
      "tenantUserId",
      "name firstName middleName lastName email phone ninLast4 isEmailVerified isPhoneVerified isNinVerified",
    );
}

async function getTenantEstate({
  businessId,
  estateAssetId,
}) {
  debug(
    "BUSINESS TENANT SERVICE: getTenantEstate",
    {
      businessId,
      estateAssetId,
    },
  );

  if (!businessId || !estateAssetId) {
    throw new Error(
      "Estate assignment is required",
    );
  }

  const estate =
    await BusinessAsset.findOne({
      _id: estateAssetId,
      businessId,
      assetType: "estate",
    }).lean();

  if (!estate) {
    throw new Error(
      "Estate asset not found",
    );
  }

  return {
    id: estate._id,
    name: estate.name,
    estate: estate.estate,
  };
}

async function getTenantApplicationForTenant({
  businessId,
  estateAssetId,
  tenantUserId,
}) {
  debug(
    "BUSINESS TENANT SERVICE: getTenantApplicationForTenant",
    {
      businessId,
      estateAssetId,
      tenantUserId,
    },
  );

  const application =
    await findLatestTenantApplication({
      businessId,
      estateAssetId,
      tenantUserId,
    });

  if (!application) {
    // WHY: Let the frontend render an empty state so tenants can submit.
    return null;
  }

  return resolveTenantSnapshot(
    application.toObject(),
  );
}

async function createTenantApplication({
  businessId,
  estateAssetId,
  actor,
  payload,
}) {
  debug(
    "BUSINESS TENANT SERVICE: createTenantApplication",
    {
      businessId,
      estateAssetId,
      actorId: actor?._id,
    },
  );

  if (!businessId || !estateAssetId) {
    throw new Error(
      "Estate assignment is required",
    );
  }

  const estate =
    await BusinessAsset.findOne({
      _id: estateAssetId,
      businessId,
      assetType: "estate",
    });

  if (!estate) {
    throw new Error(
      "Estate asset not found",
    );
  }

  const unitMix =
    (
      Array.isArray(
        estate.estate?.unitMix,
      )
    ) ?
      estate.estate.unitMix
    : [];

  const requestedUnitType =
    normalizeUnitType(
      payload?.unitType,
    );
  if (!requestedUnitType) {
    throw new Error(
      "Unit type is required",
    );
  }

  const selectedUnit = unitMix.find(
    (unit) =>
      normalizeUnitType(
        unit.unitType,
      ) === requestedUnitType,
  );

  if (!selectedUnit) {
    throw new Error(
      "Selected unit type is not available",
    );
  }

  const rentPeriod =
    payload?.rentPeriod
      ?.toString()
      .trim() ||
    selectedUnit.rentPeriod;
  if (!rentPeriod) {
    throw new Error(
      "Rent period is required",
    );
  }

  const moveInDate = parseDate(
    payload?.moveInDate,
  );
  if (!moveInDate) {
    throw new Error(
      "Move-in date is required",
    );
  }

  const references = toContactList(
    payload?.references,
  );
  const guarantors = toContactList(
    payload?.guarantors,
  );

  const rules =
    estate.estate?.tenantRules || {};
  const referencesMin = Number(
    rules.referencesMin || 1,
  );
  const referencesMax = Number(
    rules.referencesMax || 2,
  );
  const guarantorsMin = Number(
    rules.guarantorsMin || 1,
  );
  const guarantorsMax = Number(
    rules.guarantorsMax || 2,
  );

  if (
    references.length < referencesMin ||
    references.length > referencesMax
  ) {
    throw new Error(
      `References must be between ${referencesMin} and ${referencesMax}`,
    );
  }

  if (
    guarantors.length < guarantorsMin ||
    guarantors.length > guarantorsMax
  ) {
    throw new Error(
      `Guarantors must be between ${guarantorsMin} and ${guarantorsMax}`,
    );
  }

  if (
    rules.requiresAgreementSigned &&
    payload?.agreementSigned !== true
  ) {
    throw new Error(
      "Agreement must be signed before verification",
    );
  }

  const application =
    new BusinessTenantApplication({
      businessId,
      estateAssetId,
      tenantUserId: actor?._id,
      tenantSnapshot: {
        // WHY: Use verified split names when present for clean tenant displays.
        name: buildDisplayName(actor),
        email: actor?.email,
        phone: actor?.phone,
        ninLast4: actor?.ninLast4,
      },
      unitType: selectedUnit.unitType,
      unitCount: 1,
      rentAmount: Number(
        selectedUnit.rentAmount || 0,
      ),
      rentPeriod,
      moveInDate,
      references,
      guarantors,
      agreementSigned:
        payload?.agreementSigned ===
        true,
      tenantRulesSnapshot: {
        referencesMin,
        referencesMax,
        guarantorsMin,
        guarantorsMax,
        requiresAgreementSigned:
          Boolean(
            rules.requiresAgreementSigned,
          ),
      },
    });

  await application.save();

  await writeAuditLog({
    businessId,
    actorId: actor?._id,
    actorRole: actor?.role,
    action: "tenant_application_create",
    entityType: "tenant_application",
    entityId: application._id,
    message: `Tenant application submitted for ${selectedUnit.unitType}`,
    changes: {
      estateAssetId,
      unitType: selectedUnit.unitType,
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: actor?._id,
    actorRole: actor?.role,
    eventType:
      "tenant_application_created",
    entityType: "tenant_application",
    entityId: application._id,
    metadata: {
      estateAssetId,
      unitType: selectedUnit.unitType,
    },
  });

  return application;
}

async function updateTenantApplicationForTenant({
  businessId,
  estateAssetId,
  tenantUserId,
  actor,
  payload,
}) {
  debug(
    "BUSINESS TENANT SERVICE: updateTenantApplicationForTenant",
    {
      businessId,
      estateAssetId,
      tenantUserId,
      actorId: actor?._id,
    },
  );

  const application =
    await findLatestTenantApplication({
      businessId,
      estateAssetId,
      tenantUserId,
    });

  if (!application) {
    throw new Error(
      "Tenant application not found. Submit a new application.",
    );
  }

  if (
    application.status !== "pending"
  ) {
    // WHY: Only pending applications are editable; rejected should reapply.
    throw new Error(
      (
        application.status ===
          "rejected"
      ) ?
        "Application is rejected. Submit a new application."
      : "Only pending applications can be updated",
    );
  }

  const estate =
    application.estateAssetId;
  if (
    !estate ||
    estate.assetType !== "estate"
  ) {
    throw new Error(
      "Estate asset not found",
    );
  }

  const unitMix =
    (
      Array.isArray(
        estate.estate?.unitMix,
      )
    ) ?
      estate.estate.unitMix
    : [];

  const requestedUnitType =
    normalizeUnitType(
      payload?.unitType ||
        application.unitType,
    );
  const selectedUnit = unitMix.find(
    (unit) =>
      normalizeUnitType(
        unit.unitType,
      ) === requestedUnitType,
  );

  if (!selectedUnit) {
    throw new Error(
      "Selected unit type is not available",
    );
  }

  const rentPeriod =
    payload?.rentPeriod
      ?.toString()
      .trim() ||
    ((
      requestedUnitType !==
      normalizeUnitType(
        application.unitType,
      )
    ) ?
      selectedUnit.rentPeriod
    : application.rentPeriod);

  if (!rentPeriod) {
    throw new Error(
      "Rent period is required",
    );
  }

  const moveInDate =
    payload?.moveInDate !== undefined ?
      parseDate(payload?.moveInDate)
    : application.moveInDate;

  if (!moveInDate) {
    throw new Error(
      "Move-in date is required",
    );
  }

  const references =
    payload?.references !== undefined ?
      toContactList(payload?.references)
    : application.references || [];

  const guarantors =
    payload?.guarantors !== undefined ?
      toContactList(payload?.guarantors)
    : application.guarantors || [];

  const rules =
    estate.estate?.tenantRules || {};
  const referencesMin = Number(
    rules.referencesMin || 1,
  );
  const referencesMax = Number(
    rules.referencesMax || 2,
  );
  const guarantorsMin = Number(
    rules.guarantorsMin || 1,
  );
  const guarantorsMax = Number(
    rules.guarantorsMax || 2,
  );

  if (
    references.length < referencesMin ||
    references.length > referencesMax
  ) {
    throw new Error(
      `References must be between ${referencesMin} and ${referencesMax}`,
    );
  }

  if (
    guarantors.length < guarantorsMin ||
    guarantors.length > guarantorsMax
  ) {
    throw new Error(
      `Guarantors must be between ${guarantorsMin} and ${guarantorsMax}`,
    );
  }

  const agreementSigned =
    payload?.agreementSigned === true ||
    application.agreementSigned ===
      true;

  if (
    rules.requiresAgreementSigned &&
    !agreementSigned
  ) {
    throw new Error(
      "Agreement must be signed before verification",
    );
  }

  application.unitType =
    selectedUnit.unitType;
  application.rentAmount = Number(
    selectedUnit.rentAmount ||
      application.rentAmount ||
      0,
  );
  application.rentPeriod = rentPeriod;
  application.moveInDate = moveInDate;
  application.references = references;
  application.guarantors = guarantors;
  application.agreementSigned =
    agreementSigned;
  application.tenantRulesSnapshot = {
    referencesMin,
    referencesMax,
    guarantorsMin,
    guarantorsMax,
    requiresAgreementSigned: Boolean(
      rules.requiresAgreementSigned,
    ),
  };

  await application.save();

  await writeAuditLog({
    businessId,
    actorId: actor?._id,
    actorRole: actor?.role,
    action: "tenant_application_update",
    entityType: "tenant_application",
    entityId: application._id,
    message: `Tenant application updated for ${selectedUnit.unitType}`,
    changes: {
      estateAssetId,
      unitType: selectedUnit.unitType,
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: actor?._id,
    actorRole: actor?.role,
    eventType:
      "tenant_application_updated",
    entityType: "tenant_application",
    entityId: application._id,
    metadata: {
      estateAssetId,
      unitType: selectedUnit.unitType,
    },
  });

  return resolveTenantSnapshot(
    application.toObject(),
  );
}

async function listTenantApplications({
  businessId,
  estateAssetId,
  status,
  limit = 20,
  page = 1,
}) {
  debug(
    "BUSINESS TENANT SERVICE: listTenantApplications",
    {
      businessId,
      estateAssetId,
      status,
      limit,
      page,
    },
  );

  if (!businessId) {
    throw new Error(
      "Business context is required",
    );
  }

  const filter = {
    businessId,
  };

  if (estateAssetId) {
    filter.estateAssetId =
      estateAssetId;
  }

  if (status) {
    filter.status = status;
  }

  const safeLimit = Math.max(
    1,
    Math.min(Number(limit) || 20, 100),
  );
  const safePage = Math.max(
    1,
    Number(page) || 1,
  );
  const skip =
    (safePage - 1) * safeLimit;

  const [items, total] =
    await Promise.all([
      BusinessTenantApplication.find(
        filter,
      )
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(safeLimit)
        // WHY: Include estate name for list rendering without extra calls.
        .populate(
          "estateAssetId",
          "name",
        )
        // WHY: Backfill missing snapshot fields for legacy applications.
        .populate(
          "tenantUserId",
          "name firstName middleName lastName email phone ninLast4",
        )
        .lean(),
      BusinessTenantApplication.countDocuments(
        filter,
      ),
    ]);

  return {
    applications: items.map(
      resolveTenantSnapshot,
    ),
    total,
    page: safePage,
    limit: safeLimit,
  };
}

async function getTenantApplicationDetail({
  businessId,
  applicationId,
}) {
  debug(
    "BUSINESS TENANT SERVICE: getTenantApplicationDetail",
    {
      businessId,
      applicationId,
    },
  );

  if (!businessId || !applicationId) {
    throw new Error(
      "Application id is required",
    );
  }

  const application =
    await BusinessTenantApplication.findOne(
      {
        _id: applicationId,
        businessId,
      },
    )
      // WHY: Include estate name so the reviewer sees the context.
      .populate(
        "estateAssetId",
        "name estate.unitMix estate.tenantRules",
      )
      // WHY: Load current verification flags for admin review.
      .populate(
        "tenantUserId",
        "name firstName middleName lastName email phone ninLast4 role isEmailVerified isPhoneVerified isNinVerified",
      )
      .lean();

  if (!application) {
    throw new Error(
      "Tenant application not found",
    );
  }

  return resolveTenantSnapshot(
    application,
  );
}

module.exports = {
  getTenantEstate,
  getTenantApplicationForTenant,
  createTenantApplication,
  updateTenantApplicationForTenant,
  listTenantApplications,
  getTenantApplicationDetail,
};
