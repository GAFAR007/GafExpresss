/**
 * routes/admin.routes.js
 * ----------------------
 * WHAT:
 * - Defines admin-only routes
 *
 * WHY:
 * - Isolates admin functionality
 * - Enforces role-based protection in one place
 */

const express = require('express');
const debug = require('../utils/debug');
const { requireAuth } = require('../middlewares/auth.middleware');
const { requireRole } = require('../middlewares/requireRole.middleware');

// ✅ Import the admin controller
const adminController = require('../controllers/admin.controller');

const router = express.Router();

debug('Admin routes initialized');
/**
 * GET /admin/health
 */
router.get(
  '/health',
  requireAuth,
  requireRole('admin'),
  (req, res) => {
    debug('Admin health route accessed by user:', req.user.sub);
    res.json({ status: 'ok', message: 'Admin access confirmed', admin: req.user });
  }
);

/**
 * GET /admin/users/:id
 */
router.get(
  '/users/:id',
  requireAuth,
  requireRole('admin'),
  adminController.getUserById
);

/**
 * PATCH /admin/users/:id/role  ← SPECIFIC — MUST COME FIRST
 */
router.patch(
  '/users/:id/role',
  requireAuth,
  requireRole('admin'),
  adminController.updateUserRole
);

/**
 * PATCH /admin/users/:id/restore  ← SPECIFIC — MUST COME FIRST
 */
router.patch(
  '/users/:id/restore',
  requireAuth,
  requireRole('admin'),
  adminController.restoreUser
);

/**
 * PATCH /admin/users/:id  ← GENERAL — COMES AFTER SPECIFIC ONES
 */
router.patch(
  '/users/:id',
  requireAuth,
  requireRole('admin'),
  adminController.updateUser
);

/**
 * DELETE /admin/users/:id
 */
router.delete(
  '/users/:id',
  requireAuth,
  requireRole('admin'),
  adminController.softDeleteUser
);

/**
 * GET /admin/users
 */
router.get(
  '/users',
  requireAuth,
  requireRole('admin'),
  adminController.getAllUsers
);

module.exports = router;