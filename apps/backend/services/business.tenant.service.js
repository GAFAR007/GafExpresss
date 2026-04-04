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
    .map((item) => {
      const firstName =
        item?.firstName
          ?.toString()
          .trim() || "";
      const middleName =
        item?.middleName
          ?.toString()
          .trim() || "";
      const lastName =
        item?.lastName
          ?.toString()
          .trim() || "";
      const legacyName =
        item?.name
          ?.toString()
          .trim() || "";
      const combinedName =
        [
          firstName,
          middleName,
          lastName,
        ]
          .filter(Boolean)
          .join(" ")
          .trim();

      return {
        // WHY: Preserve legacy name field while storing split names.
        name: combinedName || legacyName,
        firstName: firstName || null,
        middleName:
          middleName || null,
        lastName: lastName || null,
        email:
          item?.email
            ?.toString()
            .trim()
            .toLowerCase() || null,
        phone:
          item?.phone
            ?.toString()
            .trim() || null,
        documentUrl:
          item?.documentUrl
            ?.toString()
            .trim() || null,
        documentPublicId:
          item?.documentPublicId
            ?.toString()
            .trim() || null,
      };
    })
    // WHY: Keep only entries that at least include a name for legacy payloads.
    .filter((item) => item.name);
}

function validateContactRequirements(
  list,
  label,
  { allowLegacyName = false } = {},
) {
  // WHY: Enforce required fields before saving tenant contacts.
  clampList(list).forEach(
    (contact, index) => {
      const firstName =
        contact?.firstName
          ?.toString()
          .trim() || "";
      const lastName =
        contact?.lastName
          ?.toString()
          .trim() || "";
      const email =
        contact?.email
          ?.toString()
          .trim() || "";
      const phone =
        contact?.phone
          ?.toString()
          .trim() || "";
      const legacyName =
        contact?.name
          ?.toString()
          .trim() || "";

      if (
        allowLegacyName &&
        legacyName &&
        (!firstName || !lastName)
      ) {
        return;
      }

      if (
        !firstName ||
        !lastName ||
        !email ||
        !phone
      ) {
        throw new Error(
          `${label} ${index + 1} requires first name, last name, email, and phone`,
        );
      }
    },
  );
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
  // WHY: Enforce required fields before applying rule limits.
  validateContactRequirements(
    references,
    "Reference",
  );
  validateContactRequirements(
    guarantors,
    "Guarantor",
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

  const referencesFromPayload =
    payload?.references !== undefined;
  const guarantorsFromPayload =
    payload?.guarantors !== undefined;

  const references =
    referencesFromPayload ?
      toContactList(payload?.references)
    : application.references || [];

  const guarantors =
    guarantorsFromPayload ?
      toContactList(payload?.guarantors)
    : application.guarantors || [];
  // WHY: Ensure updated contacts still include required fields.
  validateContactRequirements(
    references,
    "Reference",
    { allowLegacyName: !referencesFromPayload },
  );
  validateContactRequirements(
    guarantors,
    "Guarantor",
    { allowLegacyName: !guarantorsFromPayload },
  );

  const agreementText =
    payload?.agreementText !== undefined ?
      (payload.agreementText || "").toString().trim()
    : application.agreementText || "";

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
  if (agreementText) {
    application.agreementText = agreementText;
    application.agreementStatus = "pending";
    application.agreementAcceptedAt = new Date();
  }
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

async function verifyTenantContact({
  businessId,
  applicationId,
  actorId,
  type,
  index,
  status,
  note,
}) {
  debug(
    "BUSINESS TENANT SERVICE: verifyTenantContact - entry",
    {
      businessId,
      applicationId,
      actorId,
      type,
      index,
      status,
    },
  );

  if (!businessId || !applicationId) {
    throw new Error(
      "Application id is required",
    );
  }

  const normalizedType =
    (type || "").toString().trim().toLowerCase();
  const normalizedStatus =
    (status || "").toString().trim().toLowerCase();

  if (
    normalizedType !== "reference" &&
    normalizedType !== "guarantor"
  ) {
    throw new Error(
      "Contact type must be reference or guarantor",
    );
  }

  if (
    normalizedStatus !== "verified" &&
    normalizedStatus !== "rejected"
  ) {
    throw new Error(
      "Contact status must be verified or rejected",
    );
  }

  const safeIndex = Number(index);
  if (
    Number.isNaN(safeIndex) ||
    safeIndex < 0
  ) {
    throw new Error(
      "Contact index must be a valid number",
    );
  }

  const application =
    await BusinessTenantApplication.findOne(
      {
        _id: applicationId,
        businessId,
      },
    );

  if (!application) {
    throw new Error(
      "Tenant application not found",
    );
  }

  if (application.status !== "pending") {
    throw new Error(
      "Only pending applications can be verified",
    );
  }

  const listKey =
    normalizedType === "reference"
      ? "references"
      : "guarantors";
  const contacts = clampList(
    application[listKey],
  );

  if (safeIndex >= contacts.length) {
    throw new Error(
      "Contact index is out of range",
    );
  }

  const contact =
    contacts[safeIndex];
  const isVerified =
    normalizedStatus === "verified";

  contact.status = normalizedStatus;
  contact.isVerified = isVerified;
  contact.verifiedAt = new Date();
  contact.verifiedBy = actorId;
  contact.note =
    note?.toString().trim() || null;

  application[listKey] = contacts;

  await application.save();

  const actionLabel =
    normalizedType === "reference"
      ? "reference_verified"
      : "guarantor_verified";
  const eventType =
    normalizedType === "reference"
      ? "REFERENCE_VERIFIED"
      : "GUARANTOR_VERIFIED";

  await writeAuditLog({
    action: actionLabel,
    entityType: "tenant_application",
    entityId: application._id,
    actorId,
    metadata: {
      contactType: normalizedType,
      index: safeIndex,
      status: normalizedStatus,
    },
  });

  await writeAnalyticsEvent({
    eventType,
    entityType: "tenant_application",
    entityId: application._id,
    actorId,
    metadata: {
      contactType: normalizedType,
      status: normalizedStatus,
    },
  });

  const rules =
    application.tenantRulesSnapshot || {};
  const referencesMin = Math.max(
    1,
    Number(rules.referencesMin) || 1,
  );
  const guarantorsMin = Math.max(
    0,
    Number(rules.guarantorsMin) || 0,
  );

  const references = clampList(
    application.references,
  );
  const guarantors = clampList(
    application.guarantors,
  );

  const hasEnoughReferences =
    references.length >= referencesMin;
  const hasEnoughGuarantors =
    guarantors.length >= guarantorsMin;

  const allReferencesVerified =
    references.every(
      (ref) => ref?.isVerified,
    );
  const allGuarantorsVerified =
    guarantors.every(
      (guarantor) =>
        guarantor?.isVerified,
    );

  const canApprove =
    hasEnoughReferences &&
    hasEnoughGuarantors &&
    allReferencesVerified &&
    allGuarantorsVerified;

  if (canApprove) {
    application.status = "approved";
    application.reviewedAt =
      new Date();
    application.reviewedBy = actorId;
    application.reviewNotes =
      "auto_approved_after_contact_verification";

    await application.save();

    await writeAuditLog({
      action: "tenant_approved",
      entityType: "tenant_application",
      entityId: application._id,
      actorId,
      metadata: {
        source:
          "contact_verification",
      },
    });

    await writeAnalyticsEvent({
      eventType: "TENANT_APPROVED",
      entityType: "tenant_application",
      entityId: application._id,
      actorId,
    });
  }

  return resolveTenantSnapshot(
    application.toObject(),
  );
}

async function approveAgreement({
  businessId,
  applicationId,
  actorId,
}) {
  debug(
    "BUSINESS TENANT SERVICE: approveAgreement - entry",
    { businessId, applicationId, actorId },
  );

  if (!businessId || !applicationId) {
    throw new Error("Application id is required");
  }

  const application = await BusinessTenantApplication.findOne({
    _id: applicationId,
    businessId,
  });

  if (!application) {
    throw new Error("Tenant application not found");
  }

  application.agreementStatus = "approved";
  application.reviewedAt = new Date();
  application.reviewedBy = actorId;
  application.reviewNotes = "agreement_approved";

  await application.save();

  await writeAuditLog({
    action: "agreement_approved",
    entityType: "tenant_application",
    entityId: application._id,
    actorId,
  });

  await writeAnalyticsEvent({
    eventType: "AGREEMENT_APPROVED",
    entityType: "tenant_application",
    entityId: application._id,
    actorId,
  });

  return resolveTenantSnapshot(application.toObject());
}

async function setAgreementText({
  businessId,
  applicationId,
  actorId,
  agreementText,
}) {
  debug(
    "BUSINESS TENANT SERVICE: setAgreementText - entry",
    { businessId, applicationId, actorId },
  );

  if (!businessId || !applicationId) {
    throw new Error("Application id is required");
  }

  const application = await BusinessTenantApplication.findOne({
    _id: applicationId,
    businessId,
  });

  if (!application) {
    throw new Error("Tenant application not found");
  }

  application.agreementText = (agreementText || "").toString().trim();
  application.agreementStatus = "pending";
  application.agreementAcceptedAt = new Date();

  await application.save();

  await writeAuditLog({
    action: "agreement_uploaded",
    entityType: "tenant_application",
    entityId: application._id,
    actorId,
    metadata: {
      hasText: Boolean(application.agreementText),
    },
  });

  await writeAnalyticsEvent({
    eventType: "AGREEMENT_UPLOADED",
    entityType: "tenant_application",
    entityId: application._id,
    actorId,
  });

  return resolveTenantSnapshot(application.toObject());
}


async function approveTenantApplication({
  businessId,
  applicationId,
  actorId,
  actorRole,
}) {
  debug(
    "BUSINESS TENANT SERVICE: approveTenantApplication - entry",
    {
      businessId,
      applicationId,
      actorId,
      actorRole,
    },
  );

  if (!businessId || !applicationId) {
    throw new Error(
      "Application ID and business ID are required",
    );
  }

  const application =
    await BusinessTenantApplication.findOne({
      _id: applicationId,
      businessId,
    })
      .populate(
        "estateAssetId",
        "name estate.unitMix estate.tenantRules",
      )
      .populate(
        "tenantUserId",
        "name firstName middleName lastName email phone ninLast4 role isEmailVerified isPhoneVerified isNinVerified",
      );

  if (!application) {
    throw new Error(
      "Tenant application not found",
    );
  }

  // WHY: Application must be pending or have all contacts verified.
  if (application.status === "approved") {
    throw new Error(
      "Tenant application is already approved",
    );
  }
  if (application.status === "rejected") {
    throw new Error(
      "Tenant application is rejected. Cannot approve.",
    );
  }

  const rules =
    application.tenantRulesSnapshot || {};
  const referencesMin = Math.max(
    0,
    Number(rules.referencesMin) || 0,
  );
  const guarantorsMin = Math.max(
    0,
    Number(rules.guarantorsMin) || 0,
  );

  const references = clampList(
    application.references,
  );
  const guarantors = clampList(
    application.guarantors,
  );

  const allReferencesVerified =
    references.length >= referencesMin &&
    references.every(
      (ref) => ref?.isVerified,
    );
  const allGuarantorsVerified =
    guarantors.length >= guarantorsMin &&
    guarantors.every(
      (guarantor) =>
        guarantor?.isVerified,
    );

  if (
    !allReferencesVerified ||
    !allGuarantorsVerified
  ) {
    throw new Error(
      "All required references and guarantors must be verified before approval",
    );
  }

  application.status = "approved";
  application.reviewedAt = new Date();
  application.reviewedBy = actorId;
  application.reviewNotes =
    "approved_by_business_staff";

  await application.save();

  // Update the user's role to 'tenant' if they are not already.
  // This is a safety check; usually handled by invite acceptance.
  const tenantUser =
    application.tenantUserId;
  if (tenantUser && tenantUser.role !== "tenant") {
    tenantUser.role = "tenant";
    tenantUser.businessId = businessId;
    tenantUser.estateAssetId = application.estateAssetId;
    await tenantUser.save();
  }

  await writeAuditLog({
    businessId,
    actorId,
    actorRole,
    action: "tenant_approved",
    entityType: "tenant_application",
    entityId: application._id,
    message: "Tenant application approved",
    changes: { status: "approved" },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId,
    actorRole,
    eventType: "TENANT_APPROVED",
    entityType: "tenant_application",
    entityId: application._id,
    metadata: {
      estateAssetId: application.estateAssetId,
    },
  });

  return resolveTenantSnapshot(
    application.toObject(),
  );
}

module.exports = {
  getTenantEstate,
  getTenantApplicationForTenant,
  createTenantApplication,
  updateTenantApplicationForTenant,
  listTenantApplications,
  getTenantApplicationDetail,
  verifyTenantContact,
  approveAgreement,
  approveTenantApplication,
  setAgreementText,
};
