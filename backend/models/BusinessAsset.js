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
    },
    rentPeriod: {
      type: String,
      enum: RENT_PERIODS,
      default: 'monthly',
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

// WHY: Auto-derive class + estate rollups when users provide mixed data.
assetSchema.pre('validate', function applyAssetDefaults(next) {
  if (!this.assetClass) {
    this.assetClass = ASSET_CLASS_BY_TYPE[this.assetType] || 'fixed';
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
