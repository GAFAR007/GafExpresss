/**
 * apps/backend/services/admin.product.service.js
 * ----------------------------------------------
 * WHAT:
 * - Business logic for admin product operations
 *
 * WHY:
 * - Keeps controllers thin
 * - Centralises product database access
 */

const Product = require('../models/Product');
const debug = require('../utils/debug');

/**
 * Create new product
 */
async function createProduct(data) {
  debug('ADMIN PRODUCT SERVICE: createProduct', data);

  const product = new Product(data);
  await product.save();

  return product;
}

/**
 * Get all products (admin view — includes soft-deleted)
 */
async function getAllProducts() {
  debug('ADMIN PRODUCT SERVICE: getAllProducts');

  const products = await Product.find({})
    .select({ __v: 0 })
    .sort({ createdAt: -1 });

  return products;
}

/**
 * Get single product by ID
 */
async function getProductById(id) {
  debug('ADMIN PRODUCT SERVICE: getProductById', { id });

  const product = await Product.findById(id).select({ __v: 0 });

  return product;
}

/**
 * Update product
 */
async function updateProduct(id, updates) {
  debug('ADMIN PRODUCT SERVICE: updateProduct', { id, updates });

  const allowedFields = ['name', 'description', 'price', 'stock', 'imageUrl', 'isActive'];
  const filteredUpdates = {};

  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      filteredUpdates[field] = updates[field];
    }
  }

  if (Object.keys(filteredUpdates).length === 0) {
    throw new Error('No valid fields provided for update');
  }

  const product = await Product.findByIdAndUpdate(
    id,
    filteredUpdates,
    { new: true, runValidators: true }
  ).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  return product;
}

/**
 * Soft delete product
 */
async function softDeleteProduct(id, deletedById) {
  debug('ADMIN PRODUCT SERVICE: softDeleteProduct', { id, deletedById });

  const product = await Product.findByIdAndUpdate(
    id,
    {
      isActive: false,
      deletedAt: new Date(),
      deletedBy: deletedById,
    },
    { new: true }
  ).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  return product;
}

module.exports = {
  createProduct,
  getAllProducts,
  getProductById,
  updateProduct,
  softDeleteProduct,
};