/**
 * apps/backend/services/business_tenant_request.service.js
 * ----------------------------------------------------------
 * WHAT:
 * - Creates public tenant-request links and stores submitted requests.
 *
 * WHY:
 * - Business owners/shareholders/estate managers need a link they can copy
 *   and send to a tenant without requiring email invite delivery.
 * - Public tenants need a direct, unauthenticated form to submit identity and
 *   unit preferences.
 *
 * HOW:
 * - Generates a hashed link token and persists it with estate scope.
 * - Resolves the link back into a tenant request context for the frontend.
 * - Accepts a public submission, uploads the identity document, and stores a
 *   BusinessTenantApplication record using the same review pipeline.
 */

const crypto = require('crypto');
const debug = require('../utils/debug');
const BusinessAsset = require('../models/BusinessAsset');
const BusinessTenantApplication = require('../models/BusinessTenantApplication');
const BusinessTenantRequestLink = require('../models/BusinessTenantRequestLink');
const User = require('../models/User');
const {
  writeAuditLog,
} = require('../utils/audit');
const {
  writeAnalyticsEvent,
} = require('../utils/analytics');
const {
  uploadTenantIdentityDocument,
} = require('./tenant_identity_document.service');

const FRONTEND_BASE_URL =
  (process.env.FRONTEND_BASE_URL || 'http://localhost:5173').trim();
const REQUEST_LINK_TTL_DAYS = Number(
  process.env.TENANT_REQUEST_LINK_TTL_DAYS || 7,
);

function generateToken() {
  return crypto.randomBytes(24).toString('hex');
}

function hashValue(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function normalizeUnitType(value) {
  return (value || '').toString().trim().toLowerCase();
}

function parseDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function last4(value) {
  const cleaned = (value || '').toString().replace(/\s+/g, '');
  return cleaned.length >= 4 ? cleaned.slice(-4) : cleaned;
}

function buildTenantRequestLink(token) {
  return `${FRONTEND_BASE_URL}/#/tenant-request?token=${token}`;
}

function linkExpiryDate() {
  const now = new Date();
  now.setDate(now.getDate() + REQUEST_LINK_TTL_DAYS);
  return now;
}

function buildDisplayName(user) {
  if (!user) return '';
  const first = user.firstName?.toString().trim() || '';
  const middle = user.middleName?.toString().trim() || '';
  const last = user.lastName?.toString().trim() || '';
  const combined = [first, middle, last].filter(Boolean).join(' ').trim();
  return combined || user.name?.toString().trim() || '';
}

function buildApplicantName(payload) {
  const firstName = (payload?.firstName || '').toString().trim();
  const middleName = (payload?.middleName || '').toString().trim();
  const lastName = (payload?.lastName || '').toString().trim();
  return [firstName, middleName, lastName].filter(Boolean).join(' ').trim();
}

function validatePublicRequestPayload(payload) {
  const firstName = (payload?.firstName || '').toString().trim();
  const lastName = (payload?.lastName || '').toString().trim();
  const nin = (payload?.nin || '').toString().trim().replace(/\s+/g, '');
  const dob = parseDate(payload?.dob);
  const unitType = normalizeUnitType(payload?.unitType);

  if (!firstName) {
    throw new Error('First name is required');
  }
  if (!lastName) {
    throw new Error('Last name is required');
  }
  if (!nin) {
    throw new Error('NIN is required');
  }
  if (!/^\d{11}$/.test(nin)) {
    throw new Error('NIN must be 11 digits');
  }
  if (!dob) {
    throw new Error('DOB is required');
  }
  if (dob > new Date()) {
    throw new Error('DOB cannot be in the future');
  }
  if (!unitType) {
    throw new Error('Unit type is required');
  }

  return {
    firstName,
    middleName: (payload?.middleName || '').toString().trim(),
    lastName,
    nin,
    dob,
    unitType,
  };
}

async function cancelActiveRequestLinks({ businessId, estateAssetId }) {
  await BusinessTenantRequestLink.updateMany(
    {
      businessId,
      estateAssetId,
      status: 'pending',
    },
    {
      $set: {
        status: 'cancelled',
      },
    },
  );
}

async function createTenantRequestLink({
  businessId,
  inviterId,
  estateAssetId,
}) {
  debug('TENANT REQUEST: create link', {
    businessId,
    inviterId,
    estateAssetId,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }
  if (!inviterId) {
    throw new Error('Inviter is required');
  }
  if (!estateAssetId) {
    throw new Error('Estate asset is required for tenant request links');
  }

  const estate = await BusinessAsset.findOne({
    _id: estateAssetId,
    businessId,
    assetType: 'estate',
  }).lean();

  if (!estate) {
    throw new Error('Estate asset not found');
  }

  const token = generateToken();
  const tokenHash = hashValue(token);
  const tokenExpiresAt = linkExpiryDate();

  await cancelActiveRequestLinks({
    businessId,
    estateAssetId,
  });

  const requestLink = await BusinessTenantRequestLink.create({
    businessId,
    inviterId,
    estateAssetId,
    tokenHash,
    tokenExpiresAt,
    status: 'pending',
  });

  const requestLinkUrl = buildTenantRequestLink(token);

  await writeAuditLog({
    businessId,
    actorId: inviterId,
    action: 'tenant_request_link_create',
    entityType: 'tenant_request_link',
    entityId: requestLink._id,
    message: 'Tenant request link created',
    changes: {
      estateAssetId,
    },
  });

  await writeAnalyticsEvent({
    businessId,
    actorId: inviterId,
    eventType: 'tenant_request_link_created',
    entityType: 'tenant_request_link',
    entityId: requestLink._id,
    metadata: {
      estateAssetId,
    },
  });

  return {
    requestLink,
    requestLinkUrl,
    estate,
  };
}

async function getTenantRequestLinkContext({ token }) {
  debug('TENANT REQUEST: get context', {
    hasToken: Boolean(token),
  });

  if (!token) {
    throw new Error('Tenant request token is required');
  }

  const tokenHash = hashValue(token);
  const requestLink = await BusinessTenantRequestLink.findOne({
    tokenHash,
    status: 'pending',
  }).lean();

  if (!requestLink) {
    throw new Error('Tenant request link not found');
  }

  if (new Date(requestLink.tokenExpiresAt) < new Date()) {
    await BusinessTenantRequestLink.updateOne(
      { _id: requestLink._id },
      { $set: { status: 'expired' } },
    );
    throw new Error('Tenant request link has expired');
  }

  const [business, estate] = await Promise.all([
    User.findById(requestLink.businessId)
      .select('name firstName middleName lastName role')
      .lean(),
    BusinessAsset.findOne({
      _id: requestLink.estateAssetId,
      businessId: requestLink.businessId,
      assetType: 'estate',
    })
      .select('name estate.unitMix estate.tenantRules')
      .lean(),
  ]);

  if (!estate) {
    throw new Error('Estate asset not found');
  }

  return {
    requestLinkId: requestLink._id,
    business: {
      id: business?._id?.toString() || requestLink.businessId.toString(),
      name: buildDisplayName(business) || 'Business',
    },
    estate: {
      id: estate._id,
      name: estate.name,
      unitMix: Array.isArray(estate.estate?.unitMix)
        ? estate.estate.unitMix
        : [],
      tenantRules: estate.estate?.tenantRules || {},
    },
    expiresAt: requestLink.tokenExpiresAt,
  };
}

async function submitTenantRequest({
  token,
  payload,
  file,
}) {
  debug('TENANT REQUEST: submit', {
    hasToken: Boolean(token),
    hasFile: Boolean(file),
  });

  if (!token) {
    throw new Error('Tenant request token is required');
  }
  if (!file) {
    throw new Error('Document file is required');
  }

  const tokenHash = hashValue(token);
  const requestLink = await BusinessTenantRequestLink.findOne({
    tokenHash,
    status: 'pending',
  });

  if (!requestLink) {
    throw new Error('Tenant request link not found');
  }

  if (new Date(requestLink.tokenExpiresAt) < new Date()) {
    requestLink.status = 'expired';
    await requestLink.save();
    throw new Error('Tenant request link has expired');
  }

  const estate = await BusinessAsset.findOne({
    _id: requestLink.estateAssetId,
    businessId: requestLink.businessId,
    assetType: 'estate',
  });

  if (!estate) {
    throw new Error('Estate asset not found');
  }

  const normalized = validatePublicRequestPayload(payload);
  const unitMix = Array.isArray(estate.estate?.unitMix)
    ? estate.estate.unitMix
    : [];

  const selectedUnit = unitMix.find(
    (unit) =>
      normalizeUnitType(unit.unitType) === normalized.unitType,
  );

  if (!selectedUnit) {
    throw new Error('Selected unit type is not available');
  }

  const documentUpload = await uploadTenantIdentityDocument({
    businessId: requestLink.businessId,
    file,
    source: 'tenant_request',
  });

  const applicantName = buildApplicantName(normalized);
  const application = new BusinessTenantApplication({
    businessId: requestLink.businessId,
    estateAssetId: requestLink.estateAssetId,
    tenantUserId: null,
    tenantSnapshot: {
      name: applicantName,
      email: '',
      phone: '',
      ninLast4: last4(normalized.nin),
    },
    applicantFirstName: normalized.firstName,
    applicantMiddleName: normalized.middleName || null,
    applicantLastName: normalized.lastName,
    applicantDob: normalized.dob,
    applicantNinHash: hashValue(normalized.nin),
    applicantNinLast4: last4(normalized.nin),
    identityDocumentUrl: documentUpload.url,
    identityDocumentPublicId: documentUpload.publicId,
    requestSource: 'public_request',
    requestLinkId: requestLink._id,
    unitType: selectedUnit.unitType,
    unitCount: 1,
    rentAmount: Number(selectedUnit.rentAmount || 0),
    rentPeriod: selectedUnit.rentPeriod || 'monthly',
    moveInDate: parseDate(payload?.moveInDate) || null,
    references: [],
    guarantors: [],
    agreementSigned: false,
    agreementText: '',
    agreementAcceptedAt: null,
    tenantRulesSnapshot: {
      referencesMin: 0,
      referencesMax: 0,
      guarantorsMin: 0,
      guarantorsMax: 0,
      requiresAgreementSigned: false,
    },
  });

  await application.save();

  requestLink.status = 'consumed';
  requestLink.submittedApplicationId = application._id;
  await requestLink.save();

  await writeAuditLog({
    businessId: requestLink.businessId,
    actorId: null,
    actorRole: 'guest',
    action: 'tenant_public_request_submitted',
    entityType: 'tenant_application',
    entityId: application._id,
    message: 'Public tenant request submitted',
    changes: {
      estateAssetId: requestLink.estateAssetId,
      unitType: selectedUnit.unitType,
    },
  });

  await writeAnalyticsEvent({
    businessId: requestLink.businessId,
    actorId: null,
    actorRole: 'guest',
    eventType: 'tenant_public_request_submitted',
    entityType: 'tenant_application',
    entityId: application._id,
    metadata: {
      estateAssetId: requestLink.estateAssetId,
      unitType: selectedUnit.unitType,
    },
  });

  return {
    requestLink,
    application,
  };
}

module.exports = {
  buildTenantRequestLink,
  createTenantRequestLink,
  getTenantRequestLinkContext,
  submitTenantRequest,
  validatePublicRequestPayload,
  normalizeUnitType,
  parseDate,
  last4,
  hashValue,
};
