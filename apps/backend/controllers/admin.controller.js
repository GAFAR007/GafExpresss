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

// ... existing getAllUsers and getUserById ...

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
 * Update a user's role
 * PATCH /admin/users/:id/role
 */
async function updateUserRole(req, res) {
  try {
    const adminId = req.user.sub;
    const targetUserId = req.params.id;
    const { role } = req.body;

    const updatedUser = await adminService.updateUserRole({
      adminId,
      targetUserId,
      role,
    });

    res.json({
      message: 'User role updated successfully',
      user: updatedUser,
    });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

/**
 * Restore a soft-deleted user
 * PATCH /admin/users/:id/restore
 */
async function restoreUser(req, res) {
  try {
    const adminId = req.user.sub;
    const targetUserId = req.params.id;

    const restoredUser = await adminService.restoreUser({
      adminId,
      targetUserId,
    });

    res.json({
      message: 'User restored successfully',
      user: restoredUser,
    });
  } catch (err) {
    res.status(400).json({ error: err.message });
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
async function getAllProducts(req, res) {
  debug('ADMIN CONTROLLER: getAllProducts - entry');

  try {
    const products = await adminProductService.getAllProducts();

    debug('ADMIN CONTROLLER: getAllProducts - success', { count: products.length });

    return res.status(200).json({
      message: 'Products fetched successfully',
      count: products.length,
      products,
    });
  } catch (err) {
    debug('ADMIN CONTROLLER: getAllProducts - error', err.message);

    return res.status(500).json({
      error: 'Failed to fetch products',
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
};