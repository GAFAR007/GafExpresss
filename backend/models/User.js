/**
 * models/User.js
 * --------------
 * WHAT:
 * - Defines the User schema and model for MongoDB (Mongoose)
 *
 * HOW:
 * - Uses a role field to support authorization (admin/staff/customer)
 * - Stores email in lowercase + unique index
 * - Stores password as a hashed string (hashing happens in auth service)
 *
 * WHY:
 * - Central source of truth for user data
 * - Enables clean auth + role-based access control
 */

const mongoose = require('mongoose');
const debug = require('../utils/debug');

// ✅ Allowed roles in the system (extend later if needed)
// WHY: business_owner + tenant support multi-tenant business workflows.
const USER_ROLES = [
  'admin',
  'business_owner',
  'staff',
  'tenant',
  'customer',
];
// ✅ Allowed account types for Nigeria-specific registration flows
const ACCOUNT_TYPES = [
  'personal',
  'sole_proprietorship',
  'partnership',
  'limited_liability_company',
  'public_limited_company',
  'incorporated_trustees',
];

// WHY: Schedule policy is configurable per business and used by production planners.
const workScheduleBlockSchema = new mongoose.Schema(
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
  { _id: false },
);

// WHY: Store business-level production scheduling defaults for all estates.
const productionSchedulePolicySchema = new mongoose.Schema(
  {
    workWeekDays: {
      type: [Number],
      default: undefined,
    },
    blocks: {
      type: [workScheduleBlockSchema],
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
  { _id: false },
);

debug('Loading User model...');

// ✅ Structured address payload for verification + delivery.
const addressSchema = new mongoose.Schema(
  {
    houseNumber: {
      type: String,
      trim: true,
    },
    street: {
      type: String,
      trim: true,
    },
    city: {
      type: String,
      trim: true,
    },
    state: {
      type: String,
      trim: true,
    },
    postalCode: {
      type: String,
      trim: true,
    },
    lga: {
      type: String,
      trim: true,
    },
    country: {
      type: String,
      trim: true,
      default: 'NG',
    },
    landmark: {
      type: String,
      trim: true,
    },
    // ✅ Verification metadata (set only by backend verification flow)
    isVerified: {
      type: Boolean,
      default: false,
    },
    verifiedAt: {
      type: Date,
      default: null,
    },
    verificationSource: {
      type: String,
      trim: true,
    },
    formattedAddress: {
      type: String,
      trim: true,
    },
    placeId: {
      type: String,
      trim: true,
    },
    lat: {
      type: Number,
    },
    lng: {
      type: Number,
    },
  },
  {
    _id: false,
  }
);

const userSchema = new mongoose.Schema(
  {
    // ✅ Name is optional for now (useful for profile later)
    name: {
      type: String,
      trim: true,
      minlength: 2,
      maxlength: 80,
    },

    // ✅ First + last name stored separately for profile forms
    firstName: {
      type: String,
      trim: true,
      minlength: 1,
      maxlength: 40,
    },
    lastName: {
      type: String,
      trim: true,
      minlength: 1,
      maxlength: 40,
    },
    middleName: {
      type: String,
      trim: true,
      minlength: 1,
      maxlength: 40,
    },
    dob: {
      type: String,
      trim: true,
    },

    // ✅ Email is required + unique
    email: {
      type: String,
      required: [true, 'Email is required'],
      unique: true, // creates unique index
      trim: true,
      lowercase: true,
    },

    // ✅ Store hashed password (never store raw password)
    passwordHash: {
      type: String,
      required: [true, 'Password hash is required'],
    },

    // ✅ Role-based access (admin/staff/customer)
    role: {
      type: String,
      enum: USER_ROLES,
      default: 'customer',
      index: true,
    },
    // ✅ Business scoping (shared across owner + staff + tenant)
    // WHY: Enforces tenant isolation for business data access.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    // ✅ Estate-scoped access (optional, for estate staff/tenant users)
    // WHY: Restricts certain roles to a single estate asset.
    estateAssetId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'BusinessAsset',
      default: null,
      index: true,
    },

    // ✅ Profile account type (upgrade path for business/firm/org)
    accountType: {
      type: String,
      enum: ACCOUNT_TYPES,
      default: 'personal',
      index: true,
    },

    // ✅ Contact phone (unique when present; enforced via partial index)
    phone: {
      type: String,
      trim: true,
    },

    // ✅ Business profile fields (optional; shown when upgrading)
    companyName: {
      type: String,
      trim: true,
    },
    companyEmail: {
      type: String,
      trim: true,
      lowercase: true,
    },
    companyPhone: {
      type: String,
      trim: true,
    },
    // ✅ Structured addresses (home + company) with verification data.
    homeAddress: {
      type: addressSchema,
      default: null,
    },
    companyAddress: {
      type: addressSchema,
      default: null,
    },
    companyWebsite: {
      type: String,
      trim: true,
    },
    companyRegistration: {
      type: String,
      trim: true,
    },
    // ✅ Business verification metadata (Dojah-based)
    businessVerificationStatus: {
      type: String,
      enum: ['unverified', 'pending', 'verified', 'failed'],
      default: 'unverified',
    },
    businessVerificationSource: {
      type: String,
      trim: true,
    },
    businessVerificationRef: {
      type: String,
      trim: true,
    },
    businessVerificationMessage: {
      type: String,
      trim: true,
    },
    businessVerifiedAt: {
      type: Date,
      default: null,
    },
    // ✅ Business registration details (full number required by request)
    businessRegistrationNumber: {
      type: String,
      trim: true,
    },
    businessRegistrationType: {
      type: String,
      trim: true,
    },
    businessIncorporationDate: {
      type: String,
      trim: true,
    },
    businessIndustry: {
      type: String,
      trim: true,
    },
    businessTaxId: {
      type: String,
      trim: true,
    },
    businessRegisteredAddress: {
      type: addressSchema,
      default: null,
    },
    businessDirectors: {
      type: [
        {
          name: { type: String, trim: true },
          role: { type: String, trim: true },
          email: { type: String, trim: true, lowercase: true },
          phone: { type: String, trim: true },
        },
      ],
      default: [],
    },
    // WHY: Business default schedule policy is the fallback for estate planning.
    productionSchedulePolicy: {
      type: productionSchedulePolicySchema,
      default: null,
    },

    // ✅ Simple account status control (can expand later)
    isActive: {
      type: Boolean,
      default: true,
    },

    // ✅ Email verification status (required for secure onboarding)
    isEmailVerified: {
      type: Boolean,
      default: false,
    },

    // ✅ Phone verification status (OTP-based)
    isPhoneVerified: {
      type: Boolean,
      default: false,
    },

    // ✅ Email verification flow metadata
    emailVerificationCodeHash: {
      type: String,
      default: null,
    },
    emailVerificationExpiresAt: {
      type: Date,
      default: null,
    },

    // ✅ Phone verification flow metadata
    phoneVerificationCodeHash: {
      type: String,
      default: null,
    },
    phoneVerificationExpiresAt: {
      type: Date,
      default: null,
    },

    // ✅ NIN verification status + audit fields (store hash + last4 only)
    isNinVerified: {
      type: Boolean,
      default: false,
    },
    ninHash: {
      type: String,
      default: null,
    },
    ninLast4: {
      type: String,
      default: null,
    },

    // ✅ Profile image URL (optional; hosted externally)
    profileImageUrl: {
      type: String,
      trim: true,
      default: null,
    },

    // ✅ Soft delete tracking
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
    timestamps: true, // adds createdAt + updatedAt
  }
);

// WHY: Enforce unique phone numbers only when the field is populated.
userSchema.index(
  { phone: 1 },
  {
    unique: true,
    partialFilterExpression: {
      phone: { $type: 'string' },
    },
  }
);

const User = mongoose.model('User', userSchema);

module.exports = User;
module.exports.USER_ROLES = USER_ROLES;
module.exports.ACCOUNT_TYPES = ACCOUNT_TYPES;
