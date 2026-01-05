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
const { getFilter } = require('../utils/filter');
const Product = require('../models/Product');
const Order = require('../models/Order');
const User = require('../models/User');

/**
 * GET /admin/users?sort=name:asc → Users A → Z
 * Admin-only: List ALL users with pagination + filtering
 *
 * Supported filters:
 * ?role=customer
 * ?isActive=false
 * ?role=admin&isActive=true
 *
 * 
 * ✅ What's Now Working
URL	Result
/admin/users	All users (original behavior)
/admin/users?role=customer	Only customers
/admin/users?isActive=false	Only inactive users
/admin/users?role=admin&isActive=true	Active admins only

 * Why this endpoint exists:
 * - Full user management in admin dashboard
 * - Admins need to see every user (active, inactive, soft-deleted if added later)
 * - Never expose passwordHash to frontend
 */
/**
 * GET /admin/users
 * Admin-only: list users with pagination, filtering, and search
 *
 * Supported query params:
 * - page
 * - limit
 * - role
 * - isActive
 * - q (search by email or role)
 */
async function getAllUsers(req, res) {
  debug('ADMIN CONTROLLER: getAllUsers - entry');
  debug('Query params received:', req.query);

  try {
    /**
     * Controller stays THIN:
     * - No pagination logic
     * - No filters
     * - No DB queries
     *
     * All business logic lives in the SERVICE
     */
    const result = await adminService.getAllUsers(req.query);

    const totalPages = Math.ceil(result.total / result.limit);

    return res.status(200).json({
      message: 'Users fetched successfully',

      pagination: {
        page: result.page,
        limit: result.limit,
        total: result.total,
        totalPages,
        hasNext: result.page < totalPages,
        hasPrev: result.page > 1,
      },

      count: result.users.length,
      users: result.users,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getAllUsers - error', err.message);
    debug('Full error stack:', err.stack);

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
  debug('ADMIN CONTROLLER: getUserById - entry', {
    userId: req.params.id,
  });

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
    updates: req.body,
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
    adminUserId: req.user.sub,
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
      req.user.sub // admin who is deleting
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
  debug('ADMIN CONTROLLER: createProduct - entry', {
    body: req.body,
  });

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
 * GET /admin/products?page=1&limit=10&sort=price:desc&isActive=false
 *
 * Admin-only: List ALL products (including soft-deleted) with pagination + sorting + filtering
 *
 * Why this endpoint exists:
 * - Full product management in admin dashboard
 * - Admins need to see every product — active, inactive, and soft-deleted
 * - Supports powerful sorting and filtering for efficient inventory management
 *
 * Supported sorting:
 * - createdAt (default: newest first)
 * - price (high → low or low → high)
 * - name (A → Z or Z → A)
 * - stock (high → low or low → high)
 *
 * Supported filtering:
 * URL,Result
/admin/products,"All products (active + inactive), newest first"
/admin/products?isActive=true,Only active products
/admin/products?isActive=false,Only inactive/soft-deleted products
/admin/products?sort=price:desc,Most expensive first
/admin/products?sort=stock:asc,Lowest stock first (perfect for restocking alerts)
/admin/products?sort=name:asc&isActive=true,Active products A → Z




 * Examples:
 * ?sort=price:desc             → Most expensive first
 * ?sort=name:asc               → Alphabetical A → Z
 * ?sort=stock:asc              → Lowest stock first (great for reordering!)
 * ?isActive=false              → Only soft-deleted/inactive products
 * ?sort=price:desc&isActive=true → Most expensive active products first
 */

async function getAllProducts(req, res) {
  debug('ADMIN CONTROLLER: getAllProducts - entry');
  debug('Query params received:', req.query); // BETTER DEBUG: Full visibility into incoming request

  try {
    /**
     * -------------------------------------------------
     * STEP 1: PAGINATION (REUSABLE HELPER)
     * -------------------------------------------------
     * Handles page, limit, skip with safe defaults and validation
     */
    const { page, limit, skip } = require('../utils/pagination').getPagination(
      req.query
    );

    debug('Calculated pagination:', { page, limit, skip }); // BETTER DEBUG: Confirm pagination math

    /**
     * -------------------------------------------------
     * STEP 1.5: FILTERING (REUSABLE HELPER)
     * -------------------------------------------------
     * Allow admins to filter by visibility status
     * Useful for viewing only active products or managing deleted ones
     */
    const { getFilter } = require('../utils/filter');
    const filter = getFilter(req.query, {
      isActive: { type: 'boolean' },
    });

    debug('Applied filter:', filter); // BETTER DEBUG: Show exactly what filter was built

    /**
     * -------------------------------------------------
     * STEP 1.6: SORTING (REUSABLE HELPER)
     * -------------------------------------------------
     * Admin has more sorting options than public endpoint
     * Safe validation prevents injection attacks
     */
    const allowedSortFields = ['createdAt', 'price', 'name', 'stock'];
    const sort = require('../utils/sort').getSort(
      req.query.sort,
      allowedSortFields,
      { createdAt: -1 } // default: newest first
    );

    debug('Using sort:', sort); // BETTER DEBUG: Confirm final sort object

    /**
     * -------------------------------------------------
     * STEP 2: DATABASE QUERIES
     * -------------------------------------------------
     * Run in parallel for performance:
     * 1. Fetch current page of products (with filter + sort)
     * 2. Count total matching products (for pagination)
     *
     * Admin sees ALL products — no isActive filter in base query
     * (but respects manual ?isActive filter when provided)
     */
    debug('Starting database queries...');

    const [products, total] = await Promise.all([
      Product.find(filter) // ← Filter applied here (e.g., only inactive if requested)
        .select({ __v: 0 }) // Hide internal Mongo fields
        .sort(sort) // ← Dynamic sorting applied
        .skip(skip)
        .limit(limit)
        .lean(), // Faster JSON serialization

      Product.countDocuments(filter), // ← Total count respects the same filter
    ]);

    debug('Queries completed successfully', {
      totalProducts: total,
      pageProducts: products.length,
      appliedFilter: filter,
      appliedSort: sort,
      pagination: { page, limit, skip },
    }); // RICH DEBUG: Full context at a glance

    /**
     * -------------------------------------------------
     * STEP 3: CALCULATE PAGINATION METADATA
     * -------------------------------------------------
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: SEND RESPONSE
     * -------------------------------------------------
     * Complete metadata enables smooth frontend experience:
     * - Page navigation controls
     * - "Showing X-Y of Z products"
     * - Disable next/prev buttons correctly
     */
    return res.status(200).json({
      message: 'Products fetched successfully',

      pagination: {
        page,
        limit,
        total, // Total matching products (after filter)
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: products.length, // How many returned this request
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
  debug('ADMIN CONTROLLER: getProductById - entry', {
    productId: req.params.id,
  });

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
  debug('ADMIN CONTROLLER: updateProduct - entry', {
    id: req.params.id,
    updates: req.body,
  });

  try {
    const updatedProduct = await adminProductService.updateProduct(
      req.params.id,
      req.body
    );

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
  debug('ADMIN CONTROLLER: softDeleteProduct - entry', {
    productId: req.params.id,
  });

  try {
    const deletedProduct = await adminProductService.softDeleteProduct(
      req.params.id,
      req.user.sub
    );

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
  debug('ADMIN CONTROLLER: restoreProduct - entry', {
    productId: req.params.id,
  });

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
 * GET /admin/orders?page=1&limit=10&sort=totalPrice:desc&status=pending
 * Admin-only: List ALL orders with pagination + sorting + filtering
 *
 * Why this endpoint exists:
 * - Full order management in admin dashboard
 * - Admins need to see every order across all customers
 * - Includes populated user and product details for easy viewing
 *
 * Supports sorting by:
 * - createdAt (default: newest first)
 * - totalPrice
 * - status
 *
 * Supports filtering by:
 * - status=pending|paid|shipped|delivered|cancelled
 *
 * Examples:
 * ?sort=totalPrice:desc → Highest value orders first
 * ?status=pending → Only pending orders
 * ?status=shipped&sort=createdAt:asc → Oldest shipped orders first
 * 
 * URL	Result
/admin/orders	All orders, newest first
/admin/orders?status=pending	Only pending orders
/admin/orders?sort=totalPrice:desc	Highest value orders first
/admin/orders?status=shipped&sort=createdAt:asc	Oldest shipped orders first
/admin/orders?page=2&limit=20&status=delivered	Page 2 of delivered orders
 */

async function getAllOrders(req, res) {
  try {
    const result = await adminOrderService.getAllOrders(req.query);

    const totalPages = Math.ceil(result.total / result.limit);

    return res.status(200).json({
      message: 'Orders fetched successfully',
      pagination: {
        page: result.page,
        limit: result.limit,
        total: result.total,
        totalPages,
        hasNext: result.page < totalPages,
        hasPrev: result.page > 1,
      },
      count: result.orders.length,
      orders: result.orders,
    });
  } catch (err) {
    return res.status(500).json({
      error: err.message || 'Failed to fetch orders',
    });
  }
}

/**
 * PATCH /admin/orders/:id/status
 * Admin-only: Update order status
 */

/**
 * PATCH /admin/orders/:id/status
 *
 * Admin updates order status
 */
/**
 * PATCH /admin/orders/:id/status
 *
 * Admin updates order status
 */
async function updateOrderStatus(req, res) {
  debug('ADMIN ORDER CONTROLLER: updateOrderStatus - entry');

  try {
    const { id } = req.params;
    const { status } = req.body;

    if (!status) {
      return res.status(400).json({
        error: 'Status is required',
      });
    }

    // FIXED: Use positional arguments (id, status) instead of object.
    // Removed unused adminId.
    const updatedOrder = await adminOrderService.updateOrderStatus(id, status);

    return res.status(200).json({
      message: 'Order status updated successfully',
      order: updatedOrder,
    });
  } catch (err) {
    debug('ADMIN ORDER CONTROLLER: updateOrderStatus - error', err.message);

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
  restoreProduct, // ... existing exports ...
  getAllOrders,
  updateOrderStatus,
};
