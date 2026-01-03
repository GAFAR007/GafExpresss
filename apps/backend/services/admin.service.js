/**
 * apps/backend/services/admin.service.js
 * -------------------------------------
 * WHAT:
 * - Business logic for admin operations
 *
 * WHY:
 * - Keeps controllers thin
 * - Centralises database access
 */

const User = require('../models/User');
const USER_ROLES = User.USER_ROLES;
const debug = require('../utils/debug');

/**
 * Fetch all users (admin only)
 *
 * @returns {Array} list of users
 */
async function getAllUsers() {
  debug('ADMIN SERVICE: Fetching all users');

  const users = await User.find({}).select({
    passwordHash: 0, // ❌ never expose passwords
    __v: 0,
  });

  debug(`ADMIN SERVICE: ${users.length} users found`);

  return users;
}
/**
 * Fetch single user by ID (admin only)
 *
 * @param {string} id - MongoDB user ID
 * @returns {Object|null} user object or null if not found
 */
async function getUserById(id) {
  debug('ADMIN SERVICE: Fetching user by ID', { id });

  const user = await User.findById(id).select({
    passwordHash: 0, // ❌ never expose passwords
    __v: 0,
  });

  debug('ADMIN SERVICE: User fetch result', { found: !!user });

  return user;
}


/**
 * Update user role or isActive status (admin only)
 *
 * @param {string} id - User ID
 * @param {Object} updates - Allowed fields: role, isActive
 * @returns {Object|null} updated user or null if not found
 */
async function updateUser(id, updates) {
  debug('ADMIN SERVICE: Updating user', { id, updates });

  const allowedFields = ['role', 'isActive'];
  const filteredUpdates = {};

  // Only allow specific fields
  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      filteredUpdates[field] = updates[field];
    }
  }

  if (Object.keys(filteredUpdates).length === 0) {
    throw new Error('No valid fields provided for update');
  }

  // Validate role if being changed
  if (filteredUpdates.role) {
    const { USER_ROLES } = require('../models/User');
    if (!USER_ROLES.includes(filteredUpdates.role)) {
      throw new Error(`Invalid role. Must be one of: ${USER_ROLES.join(', ')}`);
    }
  }

  const user = await User.findByIdAndUpdate(
    id,
    filteredUpdates,
    { new: true, runValidators: true } // return updated doc
  ).select({
    passwordHash: 0,
    __v: 0,
  });

  debug('ADMIN SERVICE: Update result', { found: !!user });

  return user;
}

/**
 * Soft delete user (admin only)
 *
 * @param {string} id - User ID to delete
 * @param {string} deletedById - Admin performing deletion
 * @returns {Object|null} updated user
 */
async function softDeleteUser(id, deletedById) {
  debug('ADMIN SERVICE: Soft deleting user', { id, deletedById });

  const user = await User.findByIdAndUpdate(
    id,
    {
      isActive: false,
      deletedAt: new Date(),
      deletedBy: deletedById,
    },
    { new: true, runValidators: true }
  ).select({
    passwordHash: 0,
    __v: 0,
  });

  debug('ADMIN SERVICE: Soft delete result', { found: !!user });

  return user;
}

/**
 * Update user role (admin only)
 * Prevents self-demote
 *
 * @param {Object} params
 * @param {string} params.adminId
 * @param {string} params.targetUserId
 * @param {string} params.role
 * @returns {Object} updated user
 */
async function updateUserRole({ adminId, targetUserId, role }) {
  debug('ADMIN SERVICE: updateUserRole', { adminId, targetUserId, role });

  if (!USER_ROLES.includes(role)) {
    throw new Error(`Invalid role: ${role}. Must be one of: ${USER_ROLES.join(', ')}`);
  }

  const user = await User.findById(targetUserId);

  if (!user) {
    throw new Error('User not found');
  }

  // Prevent self-demote
  if (targetUserId === adminId && role !== 'admin') {
    throw new Error('Admins cannot demote themselves');
  }

  user.role = role;
  await user.save();

  return user.toObject();  // Clean object without mongoose extras
}

/**
 * Restore soft-deleted user (admin only)
 * Resets isActive, deletedAt, deletedBy
 *
 * @param {Object} params
 * @param {string} params.adminId
 * @param {string} params.targetUserId
 * @returns {Object} restored user
 */
async function restoreUser({ adminId, targetUserId }) {
  debug('ADMIN SERVICE: restoreUser', { adminId, targetUserId });

  const user = await User.findByIdAndUpdate(
    targetUserId,
    {
      isActive: true,
      deletedAt: null,
      deletedBy: null,
    },
    { new: true }
  ).select({
    passwordHash: 0,
    __v: 0,
  });

  if (!user) {
    throw new Error('User not found');
  }

  // Optional: could add restore logging if needed later

  return user;
}
/**
 * Update user role (admin only)
 * Prevents self-demote
 *
 * @param {Object} params
 * @param {string} params.adminId
 * @param {string} params.targetUserId
 * @param {string} params.role
 * @returns {Object} updated user
 */
async function updateUserRole({ adminId, targetUserId, role }) {
  debug('ADMIN SERVICE: updateUserRole', { adminId, targetUserId, role });

  if (!USER_ROLES.includes(role)) {
    throw new Error(`Invalid role: ${role}. Must be one of: ${USER_ROLES.join(', ')}`);
  }

  const user = await User.findById(targetUserId);

  if (!user) {
    throw new Error('User not found');
  }

  // Prevent self-demote
  if (targetUserId === adminId && role !== 'admin') {
    throw new Error('Admins cannot demote themselves');
  }

  user.role = role;
  await user.save();

  return user.toObject();  // Clean object without mongoose extras
}

/**
 * Restore soft-deleted user (admin only)
 * Resets isActive, deletedAt, deletedBy
 *
 * @param {Object} params
 * @param {string} params.adminId
 * @param {string} params.targetUserId
 * @returns {Object} restored user
 */
async function restoreUser({ adminId, targetUserId }) {
  debug('ADMIN SERVICE: restoreUser', { adminId, targetUserId });

  const user = await User.findByIdAndUpdate(
    targetUserId,
    {
      isActive: true,
      deletedAt: null,
      deletedBy: null,
    },
    { new: true }
  ).select({
    passwordHash: 0,
    __v: 0,
  });

  if (!user) {
    throw new Error('User not found');
  }

  // Optional: could add restore logging if needed later

  return user;
}

module.exports = {
  getAllUsers,
  getUserById,
  updateUser,
  softDeleteUser,
  updateUserRole,  // NEW
  restoreUser,     // NEW
};