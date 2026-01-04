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
/**
 * Get all products for admin
 * Supports:
 * - isActive filter
 * - full-text search (?q=)
 * - sorting
 * - pagination
 */
async function getAllProducts(query) {
  const { page, limit, skip } = getPagination(query);

  // ------------------------------------
  // BASE FILTER (always applied)
  // ------------------------------------
  const filter = {};

  // Filter by active/inactive if provided
  if (query.isActive === 'true') filter.isActive = true;
  if (query.isActive === 'false') filter.isActive = false;

  // ------------------------------------
  // FULL-TEXT SEARCH (?q=)
  // ------------------------------------
  const search = query.q?.trim();
  if (search) {
    filter.$text = { $search: search };
  }

  // ------------------------------------
  // SORTING
  // ------------------------------------
  const sort = getSort(query.sort, ['price', 'stock', 'name', 'createdAt'], {
    createdAt: -1,
  });

  // ------------------------------------
  // QUERY DATABASE
  // ------------------------------------
  const [products, total] = await Promise.all([
    Product.find(filter).sort(sort).skip(skip).limit(limit).lean(),

    Product.countDocuments(filter),
  ]);

  return {
    products,
    total,
    page,
    limit,
  };
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

  const allowedFields = [
    'name',
    'description',
    'price',
    'stock',
    'imageUrl',
    'isActive',
  ];
  const filteredUpdates = {};

  for (const field of allowedFields) {
    if (updates[field] !== undefined) {
      filteredUpdates[field] = updates[field];
    }
  }

  if (Object.keys(filteredUpdates).length === 0) {
    throw new Error('No valid fields provided for update');
  }

  const product = await Product.findByIdAndUpdate(id, filteredUpdates, {
    new: true,
    runValidators: true,
  }).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  return product;
}
/**
 * Restore soft-deleted product (admin only)
 */
async function restoreProduct(id) {
  debug('ADMIN PRODUCT SERVICE: restoreProduct', { id });

  const product = await Product.findByIdAndUpdate(
    id,
    {
      isActive: true,
      deletedAt: null,
      deletedBy: null,
    },
    { new: true }
  ).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  debug('ADMIN PRODUCT SERVICE: Product restored');

  return product;
}
/**

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
  restoreProduct,
  softDeleteProduct,
};
