/**
 * models/BusinessAsset.js
 * ------------------------
 * WHAT:
 * - Stores non-product assets owned by a business (vehicles, equipment, etc.).
 *
 * WHY:
 * - Separates operational assets from product inventory.
 * - Keeps business asset tracking auditable and scoped.
 *
 * HOW:
 * - Each asset is linked to a businessId and soft-deletable.
 * - Captures ownership, depreciation, and estate-specific details.
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

debug('Loading BusinessAsset model...');

// WHY: Keep enums centralized so the schema + UI stay aligned.
const ASSET_TYPES = [
  'estate',
  'intangible',
  'vehicle',
  'equipment',
  'warehouse',
  'inventory_asset',
  'other',
];

const OWNERSHIP_TYPES = [
  'owned',
  'leased',
  'rented_out',
  'managed_for_client',
];

const ASSET_CLASSES = ['fixed', 'current'];

// WHY: Phase 1 supports straight-line only; add more later.
const DEPRECIATION_METHODS = ['straight_line'];

const RENT_PERIODS = ['monthly', 'quarterly', 'yearly'];
const FEE_PERIODS = ['monthly', 'quarterly', 'yearly'];
const FARM_AUDIT_FREQUENCIES = ['quarterly', 'yearly'];
const ASSET_APPROVAL_STATUSES = [
  'pending_approval',
  'approved',
  'rejected',
];
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
  if (auditFrequency === 'quarterly') {
    next.setMonth(next.getMonth() + 3);
    return next;
  }
  if (auditFrequency === 'yearly') {
    next.setFullYear(next.getFullYear() + 1);
    return next;
  }
  return null;
}

// WHY: Estate-level schedule blocks override business defaults when configured.
const estateWorkScheduleBlockSchema = new mongoose.Schema(
  {
    start: {
      type: String,
      trim: true,
      default: '',
    },
    end: {
      type: String,
      trim: true,
      default: '',
    },
  },
  { _id: false }
);

// WHY: Estate-specific policy lets managers customize execution windows per estate.
const estateProductionSchedulePolicySchema = new mongoose.Schema(
  {
    workWeekDays: {
      type: [Number],
      default: undefined,
    },
    blocks: {
      type: [estateWorkScheduleBlockSchema],
      default: undefined,
    },
    minSlotMinutes: {
      type: Number,
      default: undefined,
    },
    timezone: {
      type: String,
      trim: true,
      default: '',
    },
  },
  { _id: false }
);

// WHY: Help users who are unsure about fixed vs current.
const ASSET_CLASS_BY_TYPE = {
  estate: 'fixed',
  intangible: 'fixed',
  vehicle: 'fixed',
  equipment: 'fixed',
  warehouse: 'fixed',
  inventory_asset: 'current',
  other: 'fixed',
};

// WHY: Structured address supports NG validation + consistent storage.
const addressSchema = new mongoose.Schema(
  {
    houseNumber: {
      type: String,
      trim: true,
      required() {
        return this.ownerDocument()?.assetType === 'estate';
      },
    },
    street: {
      type: String,
      trim: true,
      required() {
        return this.ownerDocument()?.assetType === 'estate';
      },
    },
    city: {
      type: String,
      trim: true,
      required() {
        return this.ownerDocument()?.assetType === 'estate';
      },
    },
    state: {
      type: String,
      trim: true,
      required() {
        return this.ownerDocument()?.assetType === 'estate';
      },
    },
    postalCode: {
      type: String,
      trim: true,
    },
    lga: {
      type: String,
      trim: true,
    },
    landmark: {
      type: String,
      trim: true,
    },
    country: {
      type: String,
      default: 'Nigeria',
      trim: true,
    },
  },
  { _id: false }
);

// WHY: Estate rent schedules are per-unit for mixed properties.
const unitMixSchema = new mongoose.Schema(
  {
    unitType: {
      type: String,
      trim: true,
      required: true,
    },
    count: {
      type: Number,
      min: 1,
      required: true,
    },
    rentAmount: {
      type: Number,
      min: 0,
      required: true,
      // WHY: Monetary values are stored in kobo; enforce integer to avoid fractions.
      validate: {
        validator(value) {
          return Number.isInteger(value);
        },
        message: 'Rent amount must be an integer (kobo)',
      },
    },
    rentPeriod: {
      type: String,
      enum: RENT_PERIODS,
      // WHY: Default estates to yearly rent to match most Nigerian leases.
      default: 'yearly',
    },
  },
  { _id: false }
);

// WHY: Tenant rules enforce NIN + agreement before payment.
const tenantRulesSchema = new mongoose.Schema(
  {
    referencesMin: {
      type: Number,
      default: 1,
      min: 1,
    },
    referencesMax: {
      type: Number,
      default: 2,
      min: 1,
    },
    guarantorsMin: {
      type: Number,
      default: 1,
      min: 1,
    },
    guarantorsMax: {
      type: Number,
      default: 2,
      min: 1,
    },
    requiresNinVerified: {
      type: Boolean,
      default: true,
    },
    requiresAgreementSigned: {
      type: Boolean,
      default: true,
    },
  },
  { _id: false }
);

// WHY: Estate fields are scoped to property operations only.
const estateSchema = new mongoose.Schema(
  {
    propertyAddress: {
      type: addressSchema,
      default: null,
    },
    unitMix: {
      type: [unitMixSchema],
      default: [],
      validate: {
        validator(value) {
          const doc = this.ownerDocument();
          if (!doc || doc.assetType !== 'estate') return true;
          return Array.isArray(value) && value.length > 0;
        },
        message: 'Estate assets require at least one unit definition',
      },
    },
    totalUnits: {
      type: Number,
      min: 0,
      default: 0,
    },
    rentableUnits: {
      type: Number,
      min: 0,
      default: 0,
    },
    occupancyRate: {
      type: Number,
      min: 0,
      max: 100,
      default: 0,
    },
    leaseTermMonths: {
      type: Number,
      min: 1,
    },
    rentSummary: {
      totalMonthly: { type: Number, min: 0, default: 0 },
      totalAnnual: { type: Number, min: 0, default: 0 },
    },
    operatingCosts: {
      managementMonthly: { type: Number, min: 0, default: 0 },
      cleaningMonthly: { type: Number, min: 0, default: 0 },
      maintenanceMonthly: { type: Number, min: 0, default: 0 },
      insuranceAnnual: { type: Number, min: 0, default: 0 },
      taxAnnual: { type: Number, min: 0, default: 0 },
    },
    tenantRules: {
      type: tenantRulesSchema,
      default: () => ({}),
    },
  },
  { _id: false }
);

const assetActorSnapshotSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    name: {
      type: String,
      trim: true,
      default: '',
    },
    actorRole: {
      type: String,
      trim: true,
      default: '',
    },
    staffRole: {
      type: String,
      trim: true,
      default: '',
    },
    email: {
      type: String,
      trim: true,
      default: '',
    },
  },
  { _id: false }
);

const farmProductionUsageRequestSchema = new mongoose.Schema({
  status: {
    type: String,
    enum: ASSET_APPROVAL_STATUSES,
    default: 'pending_approval',
    index: true,
  },
  requestedBy: {
    type: assetActorSnapshotSchema,
    default: null,
  },
  requestedAt: {
    type: Date,
    default: null,
  },
  productionDate: {
    type: Date,
    default: null,
  },
  usageStartTime: {
    type: String,
    trim: true,
    default: '',
    validate: {
      validator(value) {
        return !value || TIME_24H_REGEX.test(value);
      },
      message: 'Usage start time must use HH:MM format',
    },
  },
  usageEndTime: {
    type: String,
    trim: true,
    default: '',
    validate: {
      validator(value) {
        return !value || TIME_24H_REGEX.test(value);
      },
      message: 'Usage end time must use HH:MM format',
    },
  },
  productionActivity: {
    type: String,
    trim: true,
    default: '',
  },
  quantityRequested: {
    type: Number,
    min: 1,
    default: 1,
  },
  quantityUsed: {
    type: Number,
    min: 0,
    default: 0,
  },
  note: {
    type: String,
    trim: true,
    default: '',
  },
  approvedBy: {
    type: assetActorSnapshotSchema,
    default: null,
  },
  approvedAt: {
    type: Date,
    default: null,
  },
});

const farmProfileSchema = new mongoose.Schema(
  {
    attachedFarmLabel: {
      type: String,
      trim: true,
    },
    farmSection: {
      type: String,
      trim: true,
    },
    farmCategory: {
      type: String,
      trim: true,
      required() {
        return this.ownerDocument()?.domainContext === 'farm';
      },
    },
    farmSubcategory: {
      type: String,
      trim: true,
    },
    auditFrequency: {
      type: String,
      enum: FARM_AUDIT_FREQUENCIES,
      required() {
        return this.ownerDocument()?.domainContext === 'farm';
      },
    },
    lastAuditDate: {
      type: Date,
      required() {
        return this.ownerDocument()?.domainContext === 'farm';
      },
    },
    nextAuditDate: {
      type: Date,
      default: null,
    },
    quantity: {
      type: Number,
      min: 1,
      default: 1,
    },
    unitOfMeasure: {
      type: String,
      trim: true,
      default: 'units',
    },
    estimatedCurrentValue: {
      type: Number,
      min: 0,
      default: 0,
    },
    lastAuditSubmittedBy: {
      type: assetActorSnapshotSchema,
      default: null,
    },
    lastAuditSubmittedAt: {
      type: Date,
      default: null,
    },
    lastAuditNote: {
      type: String,
      trim: true,
      default: '',
    },
    pendingAuditRequest: {
      type: new mongoose.Schema(
        {
          status: {
            type: String,
            enum: ASSET_APPROVAL_STATUSES,
            default: 'pending_approval',
          },
          requestedBy: {
            type: assetActorSnapshotSchema,
            default: null,
          },
          requestedAt: {
            type: Date,
            default: null,
          },
          auditDate: {
            type: Date,
            default: null,
          },
          resultingStatus: {
            type: String,
            enum: ['active', 'inactive', 'maintenance'],
            default: 'active',
          },
          estimatedCurrentValue: {
            type: Number,
            min: 0,
            default: 0,
          },
          note: {
            type: String,
            trim: true,
            default: '',
          },
          approvedBy: {
            type: assetActorSnapshotSchema,
            default: null,
          },
          approvedAt: {
            type: Date,
            default: null,
          },
        },
        { _id: false },
      ),
      default: null,
    },
    productionUsageRequests: {
      type: [farmProductionUsageRequestSchema],
      default: [],
    },
  },
  { _id: false }
);

const assetSchema = new mongoose.Schema(
  {
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    assetType: {
      type: String,
      enum: ASSET_TYPES,
      required: true,
      trim: true,
    },
    // WHY: Ownership controls which financial fields apply.
    ownershipType: {
      type: String,
      enum: OWNERSHIP_TYPES,
      required: true,
      trim: true,
    },
    // WHY: Asset class drives depreciation and tax reporting.
    assetClass: {
      type: String,
      enum: ASSET_CLASSES,
      required: true,
      trim: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      trim: true,
    },
    serialNumber: {
      type: String,
      trim: true,
    },
    status: {
      type: String,
      enum: ['active', 'inactive', 'maintenance'],
      default: 'active',
    },
    location: {
      type: String,
      trim: true,
    },
    currency: {
      type: String,
      default: 'NGN',
      trim: true,
    },
    domainContext: {
      type: String,
      trim: true,
      default: '',
    },
    approvalStatus: {
      type: String,
      enum: ASSET_APPROVAL_STATUSES,
      default: 'approved',
      index: true,
    },
    approvalRequestedBy: {
      type: assetActorSnapshotSchema,
      default: null,
    },
    approvalRequestedAt: {
      type: Date,
      default: null,
    },
    approvalReviewedBy: {
      type: assetActorSnapshotSchema,
      default: null,
    },
    approvalReviewedAt: {
      type: Date,
      default: null,
    },
    approvalNote: {
      type: String,
      trim: true,
      default: '',
    },
    // WHY: Fixed assets require cost + useful life to compute depreciation.
    purchaseCost: {
      type: Number,
      min: 0,
      required() {
        return (
          this.assetClass === 'fixed' &&
          ['owned', 'rented_out'].includes(this.ownershipType)
        );
      },
    },
    purchaseDate: {
      type: Date,
      required() {
        return (
          this.assetClass === 'fixed' &&
          ['owned', 'rented_out'].includes(this.ownershipType)
        );
      },
    },
    usefulLifeMonths: {
      type: Number,
      min: 1,
      required() {
        return (
          this.assetClass === 'fixed' &&
          ['owned', 'rented_out'].includes(this.ownershipType)
        );
      },
    },
    salvageValue: {
      type: Number,
      min: 0,
      default: 0,
    },
    depreciationMethod: {
      type: String,
      enum: DEPRECIATION_METHODS,
      default: 'straight_line',
    },
    // WHY: Lease fields apply only when the asset is leased.
    leaseStart: {
      type: Date,
      required() {
        return this.ownershipType === 'leased';
      },
    },
    leaseEnd: {
      type: Date,
      required() {
        return this.ownershipType === 'leased';
      },
    },
    leaseCostAmount: {
      type: Number,
      min: 0,
      required() {
        return this.ownershipType === 'leased';
      },
    },
    leaseCostPeriod: {
      type: String,
      enum: FEE_PERIODS,
      default: 'monthly',
    },
    lessorName: {
      type: String,
      trim: true,
    },
    leaseTerms: {
      type: String,
      trim: true,
    },
    // WHY: Managed assets track fees without ownership value.
    managementFeeAmount: {
      type: Number,
      min: 0,
      required() {
        return this.ownershipType === 'managed_for_client';
      },
    },
    managementFeePeriod: {
      type: String,
      enum: FEE_PERIODS,
      default: 'monthly',
    },
    clientName: {
      type: String,
      trim: true,
    },
    serviceTerms: {
      type: String,
      trim: true,
    },
    // WHY: Inventory assets track quantity + unit cost for current assets.
    inventory: {
      quantity: { type: Number, min: 0, default: 0 },
      unitCost: { type: Number, min: 0, default: 0 },
      reorderLevel: { type: Number, min: 0, default: 0 },
      unitOfMeasure: { type: String, trim: true },
    },
    // WHY: Estate holds rich metadata for mixed-unit properties.
    estate: {
      type: estateSchema,
      default: null,
    },
    // WHY: Farm asset registers need category + audit cadence for equipment reviews.
    farmProfile: {
      type: farmProfileSchema,
      default: null,
    },
    // WHY: Estate override policy allows per-location scheduling controls.
    productionSchedulePolicy: {
      type: estateProductionSchedulePolicySchema,
      default: null,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    deletedAt: {
      type: Date,
      default: null,
    },
    deletedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

// WHY: Speed up filtered asset listings by type and status.
assetSchema.index({ businessId: 1, assetType: 1, ownershipType: 1, status: 1 });
assetSchema.index({
  businessId: 1,
  domainContext: 1,
  'farmProfile.auditFrequency': 1,
  'farmProfile.farmCategory': 1,
});

// WHY: Auto-derive class + estate rollups when users provide mixed data.
assetSchema.pre('validate', function applyAssetDefaults(next) {
  if (!this.assetClass) {
    this.assetClass = ASSET_CLASS_BY_TYPE[this.assetType] || 'fixed';
  }

  if (this.farmProfile || this.domainContext === 'farm') {
    this.domainContext = 'farm';
    this.farmProfile = this.farmProfile || {};

    const quantity = Number(this.farmProfile.quantity || 1);
    this.farmProfile.quantity =
      Number.isFinite(quantity) && quantity > 0 ? Math.round(quantity) : 1;

    const estimatedCurrentValue = Number(
      this.farmProfile.estimatedCurrentValue || 0
    );
    this.farmProfile.estimatedCurrentValue =
      Number.isFinite(estimatedCurrentValue) && estimatedCurrentValue > 0
        ? estimatedCurrentValue
        : 0;

    const nextAuditDate = buildNextAuditDate(
      this.farmProfile.lastAuditDate,
      this.farmProfile.auditFrequency
    );
    if (nextAuditDate) {
      this.farmProfile.nextAuditDate = nextAuditDate;
    }
  }

  if (this.assetType !== 'estate') {
    // WHY: Some validation flows can run without a `next` callback (sync paths).
    if (typeof next === 'function') {
      return next();
    }
    return;
  }

  if (!this.estate) {
    this.estate = {};
  }

  const unitMix = Array.isArray(this.estate.unitMix) ? this.estate.unitMix : [];
  let totalUnits = 0;
  let totalMonthly = 0;

  unitMix.forEach((unit) => {
    const count = Number(unit.count || 0);
    const rent = Number(unit.rentAmount || 0);
    const period = unit.rentPeriod || 'monthly';

    totalUnits += count;

    if (period === 'yearly') {
      totalMonthly += rent / 12 * count;
      return;
    }
    if (period === 'quarterly') {
      totalMonthly += rent / 3 * count;
      return;
    }
    totalMonthly += rent * count;
  });

  // WHY: Keep estate rollups in sync for analytics.
  if (!Number.isNaN(totalUnits)) {
    this.estate.totalUnits = totalUnits;
    if (!this.estate.rentableUnits) {
      this.estate.rentableUnits = totalUnits;
    }
  }

  const monthly = Number(totalMonthly || 0);
  this.estate.rentSummary = this.estate.rentSummary || {};
  this.estate.rentSummary.totalMonthly = monthly;
  this.estate.rentSummary.totalAnnual = monthly * 12;

  this.estate.tenantRules = this.estate.tenantRules || {};

  if (typeof next === 'function') {
    return next();
  }
});

const BusinessAsset = mongoose.model('BusinessAsset', assetSchema);

module.exports = BusinessAsset;
