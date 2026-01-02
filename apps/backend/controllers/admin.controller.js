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
const adminProductService = require('../services/admin.product.service');
const adminOrderService = require('../services/admin.order.service');

const Product = require('../models/Product');
const Order = require('../models/Order');
const User = require('../models/User');

/**
 * GET /admin/users?page=1&limit=10
 * Admin-only: List ALL users with pagination
 *
 * Why this endpoint exists:
 * - Full user management in admin dashboard
 * - Admins need to see every user (active, inactive, soft-deleted if added later)
 * - Never expose passwordHash to frontend
 */
async function getAllUsers(req, res) {
  debug('ADMIN CONTROLLER: getAllUsers - entry');
  debug('Query params received:', req.query); // BETTER DEBUG: Log what client sent

  try {
    /**
     * -------------------------------------------------
     * STEP 1: START PAGINATION (REUSABLE HELPER)
     * -------------------------------------------------
     *
     * We use the shared pagination utility.
     * It validates inputs, applies safe defaults,
     * and calculates how many documents to skip.
     *
     * Keeps code DRY across all admin list endpoints.
     */
    const { page, limit, skip } = require('../utils/pagination').getPagination(req.query);

    debug('Calculated pagination:', { page, limit, skip }); // BETTER DEBUG: Confirm values

    /**
     * -------------------------------------------------
     * STEP 2: FETCH DATA FROM DATABASE
     * -------------------------------------------------
     *
     * We run TWO queries in parallel:
     *
     * 1️⃣ Get only the users for THIS page
     * 2️⃣ Count total number of users
     *
     * Promise.all = faster performance
     */
    debug('Starting database queries...'); // BETTER DEBUG: Query start

    const [users, total] = await Promise.all([
      User.find({}) // Admin sees ALL users
        .select({ 
          passwordHash: 0, // NEVER send passwords
          __v: 0           // Hide internal version field
        })
        .sort({ createdAt: -1 }) // Newest users first
        .skip(skip)
        .limit(limit)
        .lean(), // Faster for read-only responses

      User.countDocuments({}), // Total count for pagination
    ]);

    debug('Queries completed successfully', {
      totalUsers: total,
      pageUsers: users.length,
    }); // BETTER DEBUG: Confirm results

    /**
     * -------------------------------------------------
     * STEP 3: CALCULATE TOTAL PAGES
     * -------------------------------------------------
     *
     * Example:
     * total = 73 users
     * limit = 10
     * totalPages = 8 (because 73 / 10 = 7.3 → ceil to 8)
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: SEND RESPONSE TO ADMIN DASHBOARD
     * -------------------------------------------------
     *
     * Full pagination metadata helps frontend build:
     * - Page navigation
     * - "Showing X-Y of Z users"
     * - Next/Prev button states
     */
    return res.status(200).json({
      message: 'Users fetched successfully',

      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: users.length, // Users returned in this request
      users,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getAllUsers - error', err.message);
    debug('Full error stack:', err.stack); // BETTER DEBUG: Full trace for troubleshooting

    return res.status(500).json({
      error: err.message || 'Failed to fetch users',
    });
  }
}

/**
 * GET /admin/users/:id
 * Returns single user by ID (admin only)
 */
async function getUserById(req, res) {
  debug('ADMIN CONTROLLER: getUserById - entry', { userId: req.params.id });

  try {
    const user = await adminService.getUserById(req.params.id);

    if (!user) {
      debug('ADMIN CONTROLLER: getUserById - user not found');
      return res.status(404).json({
        error: 'User not found',
      });
    }

    debug('ADMIN CONTROLLER: getUserById - success');

    return res.status(200).json({
      message: 'User fetched successfully',
      user,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getUserById - error', err.message);

    return res.status(500).json({
      error: 'Failed to fetch user',
      details: err.message,
    });
  }
}

/**
 * PATCH /admin/users/:id
 * Update user role or isActive status (admin only)
 */
async function updateUser(req, res) {
  debug('ADMIN CONTROLLER: updateUser - entry', { 
    userId: req.params.id,
    updates: req.body 
  });

  try {
    const updatedUser = await adminService.updateUser(req.params.id, req.body);

    if (!updatedUser) {
      debug('ADMIN CONTROLLER: updateUser - user not found');
      return res.status(404).json({
        error: 'User not found',
      });
    }

    debug('ADMIN CONTROLLER: updateUser - success');

    return res.status(200).json({
      message: 'User updated successfully',
      user: updatedUser,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: updateUser - error', err.message);

    // Validation errors from service
    if (err.name === 'ValidationError') {
      return res.status(400).json({
        error: 'Invalid update data',
        details: err.message,
      });
    }

    return res.status(500).json({
      error: 'Failed to update user',
      details: err.message,
    });
  }
}

/**
 * PATCH /admin/users/:id/role
 * Update user role (admin only)
 */
async function updateUserRole(req, res) {
  debug('ADMIN CONTROLLER: updateUserRole - entry', {
    adminId: req.user.sub,
    targetUserId: req.params.id,
    newRole: req.body.role,
  });

  try {
    const updatedUser = await adminService.updateUserRole({
      adminId: req.user.sub,
      targetUserId: req.params.id,
      role: req.body.role,
    });

    debug('ADMIN CONTROLLER: updateUserRole - success');

    return res.status(200).json({
      message: 'User role updated successfully',
      user: updatedUser,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: updateUserRole - error', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * PATCH /admin/users/:id/restore
 * Restore soft-deleted user (admin only)
 */
async function restoreUser(req, res) {
  debug('ADMIN CONTROLLER: restoreUser - entry', {
    adminId: req.user.sub,
    targetUserId: req.params.id,
  });

  try {
    const restoredUser = await adminService.restoreUser({
      adminId: req.user.sub,
      targetUserId: req.params.id,
    });

    debug('ADMIN CONTROLLER: restoreUser - success');

    return res.status(200).json({
      message: 'User restored successfully',
      user: restoredUser,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: restoreUser - error', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * DELETE /admin/users/:id
 * Soft delete user (admin only)
 */
async function softDeleteUser(req, res) {
  debug('ADMIN CONTROLLER: softDeleteUser - entry', { 
    targetUserId: req.params.id,
    adminUserId: req.user.sub 
  });

  // Prevent self-deletion
  if (req.params.id === req.user.sub) {
    return res.status(400).json({
      error: 'Admins cannot delete their own account',
    });
  }

  try {
    const deletedUser = await adminService.softDeleteUser(
      req.params.id,
      req.user.sub  // admin who is deleting
    );

    if (!deletedUser) {
      debug('ADMIN CONTROLLER: softDeleteUser - user not found');
      return res.status(404).json({
        error: 'User not found',
      });
    }

    debug('ADMIN CONTROLLER: softDeleteUser - success');

    return res.status(200).json({
      message: 'User soft deleted successfully',
      user: deletedUser,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: softDeleteUser - error', err.message);

    return res.status(500).json({
      error: 'Failed to delete user',
      details: err.message,
    });
  }
}

/**
 * POST /admin/products
 * Admin-only: Create new product
 */
async function createProduct(req, res) {
  debug('ADMIN CONTROLLER: createProduct - entry', { body: req.body });

  try {
    const product = await adminProductService.createProduct(req.body);

    debug('ADMIN CONTROLLER: createProduct - success');

    return res.status(201).json({
      message: 'Product created successfully',
      product,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: createProduct - error', err.message);

    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /admin/products
 * Admin-only: List all products (including soft-deleted)
 */
/**
 * GET /admin/products?page=1&limit=10
 * Admin-only: List ALL products (including soft-deleted) with pagination
 *
 * Why this is different from public endpoint:
 * - Admin sees EVERYTHING (active + soft-deleted)
 * - Used for full product management in dashboard
 */
async function getAllProducts(req, res) {
  debug('ADMIN CONTROLLER: getAllProducts - entry');
  debug('Query params received:', req.query); // BETTER DEBUG: See what the client sent

  try {
    /**
     * -------------------------------------------------
     * STEP 1: START PAGINATION (REUSABLE HELPER)
     * -------------------------------------------------
     *
     * We use the shared pagination utility.
     * It:
     * - Validates page/limit
     * - Applies safe defaults
     * - Calculates how many items to skip
     *
     * Keeps this controller clean and consistent
     */
    const { page, limit, skip } = require('../utils/pagination').getPagination(req.query);

    debug('Calculated pagination:', { page, limit, skip }); // BETTER DEBUG: Confirm values

    /**
     * -------------------------------------------------
     * STEP 2: FETCH DATA FROM DATABASE
     * -------------------------------------------------
     *
     * We run TWO queries at the SAME TIME:
     *
     * 1️⃣ Get only the products for THIS page
     * 2️⃣ Count ALL products (including soft-deleted)
     *
     * Promise.all = faster than sequential queries
     */
    debug('Starting database queries...'); // BETTER DEBUG: Query start

    const [products, total] = await Promise.all([
      Product.find({}) // Admin sees ALL products (no isActive filter)
        .select({ __v: 0 }) // Hide internal version field
        .sort({ createdAt: -1 }) // Newest first
        .skip(skip)
        .limit(limit)
        .lean(), // Faster for read-only responses

      Product.countDocuments({}), // Total count (all products)
    ]);

    debug('Queries completed successfully', {
      totalProducts: total,
      pageProducts: products.length,
    }); // BETTER DEBUG: Confirm results

    /**
     * -------------------------------------------------
     * STEP 3: CALCULATE TOTAL PAGES
     * -------------------------------------------------
     *
     * Example:
     * total = 47 products
     * limit = 10
     * totalPages = 5
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: SEND RESPONSE TO ADMIN DASHBOARD
     * -------------------------------------------------
     *
     * Full pagination metadata helps frontend:
     * - Show page numbers
     * - Enable/disable next/prev buttons
     * - Display "Showing 1-10 of 47"
     */
    return res.status(200).json({
      message: 'Products fetched successfully',

      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: products.length, // Items in current page
      products,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getAllProducts - error', err.message);
    debug('Full error stack:', err.stack); // BETTER DEBUG: Full trace for troubleshooting

    return res.status(500).json({
      error: err.message || 'Failed to fetch products',
    });
  }
}

/**
 * GET /admin/products/:id
 * Admin-only: View single product
 */
async function getProductById(req, res) {
  debug('ADMIN CONTROLLER: getProductById - entry', { productId: req.params.id });

  try {
    const product = await adminProductService.getProductById(req.params.id);

    if (!product) {
      return res.status(404).json({
        error: 'Product not found',
      });
    }

    return res.status(200).json({
      message: 'Product fetched successfully',
      product,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getProductById - error', err.message);
    return res.status(500).json({
      error: 'Failed to fetch product',
    });
  }
}

/**
 * PATCH /admin/products/:id
 * Admin-only: Update product
 */
async function updateProduct(req, res) {
  debug('ADMIN CONTROLLER: updateProduct - entry', { id: req.params.id, updates: req.body });

  try {
    const updatedProduct = await adminProductService.updateProduct(req.params.id, req.body);

    if (!updatedProduct) {
      return res.status(404).json({
        error: 'Product not found',
      });
    }

    return res.status(200).json({
      message: 'Product updated successfully',
      product: updatedProduct,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: updateProduct - error', err.message);
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * DELETE /admin/products/:id
 * Admin-only: Soft delete product
 */
async function softDeleteProduct(req, res) {
  debug('ADMIN CONTROLLER: softDeleteProduct - entry', { productId: req.params.id });

  try {
    const deletedProduct = await adminProductService.softDeleteProduct(req.params.id, req.user.sub);

    if (!deletedProduct) {
      return res.status(404).json({
        error: 'Product not found',
      });
    }

    return res.status(200).json({
      message: 'Product soft deleted successfully',
      product: deletedProduct,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: softDeleteProduct - error', err.message);
    return res.status(500).json({
      error: 'Failed to delete product',
    });
  }
}

/**
 * PATCH /admin/products/:id/restore
 * Admin-only: Restore soft-deleted product
 */
async function restoreProduct(req, res) {
  debug('ADMIN CONTROLLER: restoreProduct - entry', { productId: req.params.id });

  try {
    const product = await adminProductService.restoreProduct(req.params.id);

    if (!product) {
      return res.status(404).json({
        error: 'Product not found',
      });
    }

    return res.status(200).json({
      message: 'Product restored successfully',
      product,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: restoreProduct - error', err.message);
    return res.status(400).json({
      error: err.message,
    });
  }
}
// ... (existing code)

// Add these new functions

/**
 * GET /admin/orders?page=1&limit=10
 * Admin-only: List ALL orders with pagination
 *
 * Why this endpoint exists:
 * - Full order management in admin dashboard
 * - Admins need to see every order across all customers
 * - Includes populated user and product details for easy viewing
 */
async function getAllOrders(req, res) {
  debug('ADMIN CONTROLLER: getAllOrders - entry');
  debug('Query params received:', req.query); // BETTER DEBUG: Log what client sent

  try {
    /**
     * -------------------------------------------------
     * STEP 1: START PAGINATION (REUSABLE HELPER)
     * -------------------------------------------------
     *
     * We use the shared pagination utility.
     * It validates inputs, applies safe defaults,
     * and calculates how many documents to skip.
     *
     * Keeps code consistent across all admin list endpoints.
     */
    const { page, limit, skip } = require('../utils/pagination').getPagination(req.query);

    debug('Calculated pagination:', { page, limit, skip }); // BETTER DEBUG: Confirm values

    /**
     * -------------------------------------------------
     * STEP 2: FETCH DATA FROM DATABASE
     * -------------------------------------------------
     *
     * We run TWO queries in parallel:
     *
     * 1️⃣ Get only the orders for THIS page (with population)
     * 2️⃣ Count total number of orders
     *
     * Promise.all = faster performance
     */
    debug('Starting database queries...'); // BETTER DEBUG: Query start

    const [orders, total] = await Promise.all([
      Order.find({}) // Admin sees ALL orders
        .populate('user', 'name email')
        .populate('items.product', 'name imageUrl')
        .select({ __v: 0 })
        .sort({ createdAt: -1 }) // Newest orders first
        .skip(skip)
        .limit(limit)
        .lean(),

      Order.countDocuments({}), // Total count for pagination
    ]);

    debug('Queries completed successfully', {
      totalOrders: total,
      pageOrders: orders.length,
    }); // BETTER DEBUG: Confirm results

    /**
     * -------------------------------------------------
     * STEP 3: CALCULATE TOTAL PAGES
     * -------------------------------------------------
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: SEND RESPONSE TO ADMIN DASHBOARD
     * -------------------------------------------------
     *
     * Full pagination metadata helps frontend build:
     * - Order list with page navigation
     * - "Showing X-Y of Z orders"
     * - Next/Prev button states
     */
    return res.status(200).json({
      message: 'Orders fetched successfully',

      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: orders.length, // Orders returned in this request
      orders,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getAllOrders - error', err.message);
    debug('Full error stack:', err.stack); // BETTER DEBUG: Full trace

    return res.status(500).json({
      error: err.message || 'Failed to fetch orders',
    });
  }
}

/**
 * PATCH /admin/orders/:id/status
 * Admin-only: Update order status
 */
async function updateOrderStatus(req, res) {
  debug('ADMIN CONTROLLER: updateOrderStatus - entry', { id: req.params.id, status: req.body.status });

  try {
    const order = await adminOrderService.updateOrderStatus(req.params.id, req.body.status);

    return res.status(200).json({
      message: 'Order status updated successfully',
      order,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: updateOrderStatus - error', err.message);
    return res.status(400).json({
      error: err.message,
    });
  }
}


module.exports = {
  getAllUsers,
  getUserById,
  updateUser,
  softDeleteUser,
  updateUserRole,
  restoreUser,
  createProduct,
  getAllProducts,
  getProductById,
  updateProduct,
  softDeleteProduct,
  restoreProduct,  // ... existing exports ...
  getAllOrders,
  updateOrderStatus,
};