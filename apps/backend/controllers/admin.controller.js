/**
 * apps/backend/controllers/admin.controller.js
 * -------------------------------------------
 * WHAT:
 * - Handles admin-only HTTP requests
 * - Keeps routes thin, services testable
 *
 * WHY:
 * - Consistent pattern with auth.controller.js
 * - Easy to add more admin endpoints later
 */

const debug = require('../utils/debug');
const adminService = require('../services/admin.service');

/**
 * GET /admin/users
 * Returns list of all users (admin only)
 */
async function getAllUsers(req, res) {
  debug('ADMIN CONTROLLER: getAllUsers - entry');

  try {
    const users = await adminService.getAllUsers();

    debug('ADMIN CONTROLLER: getAllUsers - success', { count: users.length });

    return res.status(200).json({
      message: 'Users fetched successfully',
      count: users.length,
      users,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getAllUsers - error', err.message);

    return res.status(500).json({
      error: 'Failed to fetch users',
      details: err.message,
    });
  }
}

module.exports = {
  getAllUsers,
};