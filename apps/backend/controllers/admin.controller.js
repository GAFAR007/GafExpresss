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

const debug = require("../utils/debug");
const adminService = require("../services/admin.service");
const adminProductService = require("../services/admin.product.service");
const adminOrderService = require("../services/admin.order.service");

const Product = require("../models/Product");
const Order = require("../models/Order");
const User = require("../models/User");

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
  debug("ADMIN CONTROLLER: getAllUsers - entry");
  debug("Query params received:", req.query); // BETTER DEBUG: Log what client sent

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
    const { page, limit, skip } =
      require("../utils/pagination").getPagination(
        req.query
      );

    debug("Calculated pagination:", { page, limit, skip }); // BETTER DEBUG: Confirm values

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
    debug("Starting database queries..."); // BETTER DEBUG: Query start

    const [users, total] = await Promise.all([
      User.find({}) // Admin sees ALL users
        .select({
          passwordHash: 0, // NEVER send passwords
          __v: 0, // Hide internal version field
        })
        .sort({ createdAt: -1 }) // Newest users first
        .skip(skip)
        .limit(limit)
        .lean(), // Faster for read-only responses

      User.countDocuments({}), // Total count for pagination
    ]);

    debug("Queries completed successfully", {
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
      message: "Users fetched successfully",

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
    debug(
      "ADMIN CONTROLLER: getAllUsers - error",
      err.message
    );
    debug("Full error stack:", err.stack); // BETTER DEBUG: Full trace for troubleshooting

    return res.status(500).json({
      error: err.message || "Failed to fetch users",
    });
  }
}

/**
 * GET /admin/users/:id
 * Returns single user by ID (admin only)
 */
async function getUserById(req, res) {
  debug("ADMIN CONTROLLER: getUserById - entry", {
    userId: req.params.id,
  });

  try {
    const user = await adminService.getUserById(
      req.params.id
    );

    if (!user) {
      debug(
        "ADMIN CONTROLLER: getUserById - user not found"
      );
      return res.status(404).json({
        error: "User not found",
      });
    }

    debug("ADMIN CONTROLLER: getUserById - success");

    return res.status(200).json({
      message: "User fetched successfully",
      user,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: getUserById - error",
      err.message
    );

    return res.status(500).json({
      error: "Failed to fetch user",
      details: err.message,
    });
  }
}

/**
 * PATCH /admin/users/:id
 * Update user role or isActive status (admin only)
 */
async function updateUser(req, res) {
  debug("ADMIN CONTROLLER: updateUser - entry", {
    userId: req.params.id,
    updates: req.body,
  });

  try {
    const updatedUser = await adminService.updateUser(
      req.params.id,
      req.body
    );

    if (!updatedUser) {
      debug(
        "ADMIN CONTROLLER: updateUser - user not found"
      );
      return res.status(404).json({
        error: "User not found",
      });
    }

    debug("ADMIN CONTROLLER: updateUser - success");

    return res.status(200).json({
      message: "User updated successfully",
      user: updatedUser,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: updateUser - error",
      err.message
    );

    // Validation errors from service
    if (err.name === "ValidationError") {
      return res.status(400).json({
        error: "Invalid update data",
        details: err.message,
      });
    }

    return res.status(500).json({
      error: "Failed to update user",
      details: err.message,
    });
  }
}

/**
 * PATCH /admin/users/:id/role
 * Update user role (admin only)
 */
async function updateUserRole(req, res) {
  debug("ADMIN CONTROLLER: updateUserRole - entry", {
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

    debug("ADMIN CONTROLLER: updateUserRole - success");

    return res.status(200).json({
      message: "User role updated successfully",
      user: updatedUser,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: updateUserRole - error",
      err.message
    );

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
  debug("ADMIN CONTROLLER: restoreUser - entry", {
    adminId: req.user.sub,
    targetUserId: req.params.id,
  });

  try {
    const restoredUser = await adminService.restoreUser({
      adminId: req.user.sub,
      targetUserId: req.params.id,
    });

    debug("ADMIN CONTROLLER: restoreUser - success");

    return res.status(200).json({
      message: "User restored successfully",
      user: restoredUser,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: restoreUser - error",
      err.message
    );

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
  debug("ADMIN CONTROLLER: softDeleteUser - entry", {
    targetUserId: req.params.id,
    adminUserId: req.user.sub,
  });

  // Prevent self-deletion
  if (req.params.id === req.user.sub) {
    return res.status(400).json({
      error: "Admins cannot delete their own account",
    });
  }

  try {
    const deletedUser = await adminService.softDeleteUser(
      req.params.id,
      req.user.sub // admin who is deleting
    );

    if (!deletedUser) {
      debug(
        "ADMIN CONTROLLER: softDeleteUser - user not found"
      );
      return res.status(404).json({
        error: "User not found",
      });
    }

    debug("ADMIN CONTROLLER: softDeleteUser - success");

    return res.status(200).json({
      message: "User soft deleted successfully",
      user: deletedUser,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: softDeleteUser - error",
      err.message
    );

    return res.status(500).json({
      error: "Failed to delete user",
      details: err.message,
    });
  }
}

/**
 * POST /admin/products
 * Admin-only: Create new product
 */
async function createProduct(req, res) {
  debug("ADMIN CONTROLLER: createProduct - entry", {
    body: req.body,
  });

  try {
    const product = await adminProductService.createProduct(
      req.body
    );

    debug("ADMIN CONTROLLER: createProduct - success");

    return res.status(201).json({
      message: "Product created successfully",
      product,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: createProduct - error",
      err.message
    );

    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /admin/products?page=1&limit=10&sort=price:desc
 * Admin-only: List ALL products (including soft-deleted) with pagination + sorting
 *
 * Allowed sorting fields:
 * - createdAt (default: newest first)
 * - price
 * - name
 * - stock
 */
async function getAllProducts(req, res) {
  debug("ADMIN CONTROLLER: getAllProducts - entry");
  debug("Query params received:", req.query);

  try {
    // Pagination
    const { page, limit, skip } =
      require("../utils/pagination").getPagination(
        req.query
      );

    // Sorting - admin has more fields than public
    const allowedSortFields = [
      "createdAt",
      "price",
      "name",
      "stock",
    ];
    const sort = require("../utils/sort").getSort(
      req.query.sort,
      allowedSortFields,
      { createdAt: -1 } // default: newest first
    );

    debug("Using sort:", sort);

    debug("Starting database queries...");

    const [products, total] = await Promise.all([
      Product.find({}) // Admin sees all (active + soft-deleted)
        .select({ __v: 0 })
        .sort(sort)
        .skip(skip)
        .limit(limit)
        .lean(),

      Product.countDocuments({}),
    ]);

    debug("Queries completed successfully", {
      totalProducts: total,
      pageProducts: products.length,
    });

    const totalPages = Math.ceil(total / limit);

    return res.status(200).json({
      message: "Products fetched successfully",

      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: products.length,
      products,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: getAllProducts - error",
      err.message
    );
    debug("Full error stack:", err.stack);

    return res.status(500).json({
      error: err.message || "Failed to fetch products",
    });
  }
}

/**
 * GET /admin/products/:id
 * Admin-only: View single product
 */
async function getProductById(req, res) {
  debug("ADMIN CONTROLLER: getProductById - entry", {
    productId: req.params.id,
  });

  try {
    const product =
      await adminProductService.getProductById(
        req.params.id
      );

    if (!product) {
      return res.status(404).json({
        error: "Product not found",
      });
    }

    return res.status(200).json({
      message: "Product fetched successfully",
      product,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: getProductById - error",
      err.message
    );
    return res.status(500).json({
      error: "Failed to fetch product",
    });
  }
}

/**
 * PATCH /admin/products/:id
 * Admin-only: Update product
 */
async function updateProduct(req, res) {
  debug("ADMIN CONTROLLER: updateProduct - entry", {
    id: req.params.id,
    updates: req.body,
  });

  try {
    const updatedProduct =
      await adminProductService.updateProduct(
        req.params.id,
        req.body
      );

    if (!updatedProduct) {
      return res.status(404).json({
        error: "Product not found",
      });
    }

    return res.status(200).json({
      message: "Product updated successfully",
      product: updatedProduct,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: updateProduct - error",
      err.message
    );
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
  debug("ADMIN CONTROLLER: softDeleteProduct - entry", {
    productId: req.params.id,
  });

  try {
    const deletedProduct =
      await adminProductService.softDeleteProduct(
        req.params.id,
        req.user.sub
      );

    if (!deletedProduct) {
      return res.status(404).json({
        error: "Product not found",
      });
    }

    return res.status(200).json({
      message: "Product soft deleted successfully",
      product: deletedProduct,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: softDeleteProduct - error",
      err.message
    );
    return res.status(500).json({
      error: "Failed to delete product",
    });
  }
}

/**
 * PATCH /admin/products/:id/restore
 * Admin-only: Restore soft-deleted product
 */
async function restoreProduct(req, res) {
  debug("ADMIN CONTROLLER: restoreProduct - entry", {
    productId: req.params.id,
  });

  try {
    const product =
      await adminProductService.restoreProduct(
        req.params.id
      );

    if (!product) {
      return res.status(404).json({
        error: "Product not found",
      });
    }

    return res.status(200).json({
      message: "Product restored successfully",
      product,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: restoreProduct - error",
      err.message
    );
    return res.status(400).json({
      error: err.message,
    });
  }
}
// ... (existing code)

// Add these new functions

/**
 * GET /admin/orders?page=1&limit=10&sort=totalPrice:desc
 * Admin-only: List ALL orders with pagination + sorting
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
 */

// Safe, reusable via utils/sort.js
// Default: newest first
// Examples:
// ?sort=totalPrice:desc → Highest value orders first
// ?sort=status:asc → pending → paid → shipped → delivered
// ?sort=createdAt:asc → Oldest first
// Invalid → safely ignored

async function getAllOrders(req, res) {
  debug("ADMIN CONTROLLER: getAllOrders - entry");
  debug("Query params received:", req.query); // BETTER DEBUG: Log what client sent

  try {
    /**
     * -------------------------------------------------
     * STEP 1: START PAGINATION (REUSABLE HELPER)
     * -------------------------------------------------
     *
     *
     * Keeps code consistent across all admin list endpoints.
     */

    const { page, limit, skip } =
      require("../utils/pagination").getPagination(
        req.query
      );

    debug("Calculated pagination:", { page, limit, skip }); // BETTER DEBUG: Confirm values

    /**
     * -------------------------------------------------
     * STEP 1.5: APPLY SORTING (REUSABLE HELPER)
     * -------------------------------------------------
     *
     * We allow safe sorting by specific fields only.
     *
     * Allowed: createdAt, totalPrice, status
     * Format: ?sort=totalPrice:desc
     * Default: newest first (createdAt: -1)
     */
    const allowedSortFields = [
      "createdAt",
      "totalPrice",
      "status",
    ];
    const sort = require("../utils/sort").getSort(
      req.query.sort,
      allowedSortFields,
      { createdAt: -1 } // default: newest first
    );

    debug("Using sort:", sort); // BETTER DEBUG: Show what sort is applied

    /**
     * -------------------------------------------------
     * STEP 2: FETCH DATA FROM DATABASE
     * -------------------------------------------------
     *
     * We run TWO queries in parallel:
     *
     * 1️⃣ Get only the orders for THIS page (with population + sorting)
     * 2️⃣ Count total number of orders
     *
     * Promise.all = faster performance
     */
    debug("Starting database queries..."); // BETTER DEBUG: Query start

    const [orders, total] = await Promise.all([
      Order.find({}) // Admin sees ALL orders
        .populate("user", "name email")
        .populate("items.product", "name imageUrl")
        .select({ __v: 0 })
        .sort(sort) // ← NEW: Dynamic sorting applied here!
        .skip(skip)
        .limit(limit)
        .lean(),

      Order.countDocuments({}), // Total count for pagination
    ]);

    debug("Queries completed successfully", {
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
      message: "Orders fetched successfully",

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
    debug(
      "ADMIN CONTROLLER: getAllOrders - error",
      err.message
    );
    debug("Full error stack:", err.stack); // BETTER DEBUG: Full trace

    return res.status(500).json({
      error: err.message || "Failed to fetch orders",
    });
  }
}
/**
 * PATCH /admin/orders/:id/status
 * Admin-only: Update order status
 */
async function updateOrderStatus(req, res) {
  debug("ADMIN CONTROLLER: updateOrderStatus - entry", {
    id: req.params.id,
    status: req.body.status,
  });

  try {
    const order = await adminOrderService.updateOrderStatus(
      req.params.id,
      req.body.status
    );

    return res.status(200).json({
      message: "Order status updated successfully",
      order,
    });
  } catch (err) {
    debug(
      "ADMIN CONTROLLER: updateOrderStatus - error",
      err.message
    );
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
