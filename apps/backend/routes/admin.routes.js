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

// Import the admin controller
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
 * ADMIN USER ROUTES
 */
router.get(
  '/users',
  requireAuth,
  requireRole('admin'),
  adminController.getAllUsers
);

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
 * ADMIN PRODUCT ROUTES
 */

/**
 * POST /admin/products
 * Admin-only: Create new product
 */
router.post(
  '/products',
  requireAuth,
  requireRole('admin'),
  adminController.createProduct
);

/**
 * GET /admin/products
 * Admin-only: List all products (including soft-deleted for management)
 */
router.get(
  '/products',
  requireAuth,
  requireRole('admin'),
  adminController.getAllProducts
);

/**
 * GET /admin/products/:id
 * Admin-only: View single product
 */
router.get(
  '/products/:id',
  requireAuth,
  requireRole('admin'),
  adminController.getProductById
);

/**
 * PATCH /admin/products/:id
 * Admin-only: Update product
 */
router.patch(
  '/products/:id',
  requireAuth,
  requireRole('admin'),
  adminController.updateProduct
);

/**
 * PATCH /admin/products/:id/restore
 * Admin-only: Restore soft-deleted product
 * Protected by requireAuth + requireRole('admin')
 */
router.patch(
  '/products/:id/restore',
  requireAuth,
  requireRole('admin'),
  adminController.restoreProduct
);

/**
 * DELETE /admin/products/:id
 * Admin-only: Soft delete product
 */
router.delete(
  '/products/:id',
  requireAuth,
  requireRole('admin'),
  adminController.softDeleteProduct
);

/**
 * ADMIN ORDER ROUTES
 */

/**
 * GET /admin/orders
 * Admin-only: List all orders
 */
router.get(
  '/orders',
  requireAuth,
  requireRole('admin'),
  adminController.getAllOrders
);

/**
 * PATCH /admin/orders/:id/status
 * Admin-only: Update order status
 * Body: { status }
 */
router.patch(
  '/orders/:id/status',
  requireAuth,
  requireRole('admin'),
  adminController.updateOrderStatus
);

module.exports = router;