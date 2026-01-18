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
const USER_ROLES = ['admin', 'staff', 'customer'];
// ✅ Allowed account types for Nigeria-specific registration flows
const ACCOUNT_TYPES = [
  'personal',
  'sole_proprietorship',
  'partnership',
  'limited_liability_company',
  'public_limited_company',
  'incorporated_trustees',
];

debug('Loading User model...');

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
    companyAddress: {
      type: String,
      trim: true,
    },
    companyWebsite: {
      type: String,
      trim: true,
    },
    companyRegistration: {
      type: String,
      trim: true,
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
