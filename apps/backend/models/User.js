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

    // ✅ Simple account status control (can expand later)
    isActive: {
      type: Boolean,
      default: true,
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

const User = mongoose.model('User', userSchema);

module.exports = User;
module.exports.USER_ROLES = USER_ROLES;
