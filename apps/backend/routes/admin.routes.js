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
router.get('/health', requireAuth, requireRole('admin'), (req, res) => {
  debug('Admin health route accessed by user:', req.user.sub);
  res.json({
    status: 'ok',
    message: 'Admin access confirmed',
    admin: req.user,
  });
});

/**
 * ADMIN USER ROUTES
 */
/**
 * @swagger
 * tags:
 *   name: Admin - Users
 *   description: Admin user management
 */

/**
 * @swagger
 * /admin/users:
 *   get:
 *     summary: Get all users (admin)
 *     tags: [Admin - Users]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: query
 *         name: role
 *         schema:
 *           type: string
 *           example: customer
 *         description: Filter users by role
 *       - in: query
 *         name: isActive
 *         schema:
 *           type: boolean
 *           example: true
 *         description: Filter by active/inactive users
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           example: 1
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           example: 10
 *     responses:
 *       200:
 *         description: Users fetched successfully
 *       403:
 *         description: Admin only
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
/**
 * @swagger
 * /admin/users/{id}/role:
 *   patch:
 *     summary: Update user role (admin)
 *     tags: [Admin - Users]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [role]
 *             properties:
 *               role:
 *                 type: string
 *                 example: staff
 *     responses:
 *       200:
 *         description: User role updated
 *       403:
 *         description: Admin only
 *       404:
 *         description: User not found
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
/**
 * @swagger
 * /admin/users/{id}/restore:
 *   patch:
 *     summary: Restore a soft-deleted user (admin)
 *     tags: [Admin - Users]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: User restored successfully
 *       403:
 *         description: Admin only
 *       404:
 *         description: User not found
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
/**
 * @swagger
 * /admin/users/{id}:
 *   delete:
 *     summary: Soft-delete a user (admin)
 *     tags: [Admin - Users]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: User deleted successfully
 *       403:
 *         description: Admin only
 *       404:
 *         description: User not found
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
/**
 * @swagger
 * tags:
 *   name: Admin - Products
 *   description: Admin product management
 */

/**
 * @swagger
 * /admin/products:
 *   get:
 *     summary: Get all products (admin)
 *     tags: [Admin - Products]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           example: 1
 *         description: Page number (pagination)
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           example: 10
 *         description: Number of products per page
 *       - in: query
 *         name: isActive
 *         schema:
 *           type: boolean
 *           example: true
 *         description: Filter by active/inactive products
 *       - in: query
 *         name: sort
 *         schema:
 *           type: string
 *           example: price:desc
 *         description: |
 *           Sorting format: field:direction
 *           Examples:
 *           - price:desc
 *           - stock:asc
 *           - name:asc
 *     responses:
 *       200:
 *         description: Products fetched successfully
 *       401:
 *         description: Unauthorized
 *       403:
 *         description: Forbidden (admin only)
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
/**
 * @swagger
 * tags:
 *   name: Admin - Orders
 *   description: Admin order management
 */

/**
 * @swagger
 * /admin/orders:
 *   get:
 *     summary: Get all orders (admin)
 *     tags: [Admin - Orders]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: query
 *         name: status
 *         schema:
 *           type: string
 *           example: pending
 *         description: Filter orders by status
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           example: 1
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           example: 10
 *     responses:
 *       200:
 *         description: Orders fetched successfully
 *       403:
 *         description: Admin only
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
/**
 * @swagger
 * /admin/orders/{id}/status:
 *   patch:
 *     summary: Update order status (admin)
 *     tags: [Admin - Orders]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [status]
 *             properties:
 *               status:
 *                 type: string
 *                 example: shipped
 *     responses:
 *       200:
 *         description: Order status updated
 *       403:
 *         description: Admin only
 */
router.patch(
  '/orders/:id/status',
  requireAuth,
  requireRole('admin'),
  adminController.updateOrderStatus
);

module.exports = router;
