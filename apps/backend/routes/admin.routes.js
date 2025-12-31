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
 * Admin-only test route
 */
router.get(
  '/health',
  requireAuth,
  requireRole('admin'),
  (req, res) => {
    debug('Admin health route accessed by user:', req.user.sub);

    res.json({
      status: 'ok',
      message: 'Admin access confirmed',
      admin: req.user,
    });
  }
);

/**
 * GET /admin/users
 * Admin-only: Fetch all users
 * Protected by requireAuth + requireRole('admin')
 */
router.get(
  '/users',
  requireAuth,
  requireRole('admin'),
  adminController.getAllUsers  // ← Calls controller → service
);

module.exports = router;