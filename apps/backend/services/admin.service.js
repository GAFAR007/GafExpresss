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

const { User } = require('../models/User');
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

module.exports = {
  getAllUsers,
};