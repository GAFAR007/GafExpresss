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
const InventoryEvent = require('../models/InventoryEvent');
const { writeAuditLog } = require('../utils/audit');
const { getPagination } = require('../utils/pagination');
const { getSort } = require('../utils/sort');
const {
  sanitizeProductTaxonomyFields,
  sanitizeProductSellingFields,
} = require('../utils/product_taxonomy');
const debug = require('../utils/debug');

/**
 * Create new product
 */
async function createProduct(data, actor) {
  debug('ADMIN PRODUCT SERVICE: createProduct', {
    actorId: actor?.id,
  });

  const taxonomy = sanitizeProductTaxonomyFields(data, { requireBrand: true });
  const selling = sanitizeProductSellingFields(data, { requireUnits: true });
  const product = new Product({
    ...data,
    ...taxonomy,
    ...selling,
    createdBy: actor?.id,
    updatedBy: actor?.id,
  });
  await product.save();

  // WHY: Record creation for audit traceability.
  await writeAuditLog({
    businessId: product.businessId || null,
    actorId: actor?.id,
    actorRole: actor?.role || 'admin',
    action: 'product_create',
    entityType: 'product',
    entityId: product._id,
    message: `Product created: ${product.name}`,
  });

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
async function updateProduct(id, updates, actor) {
  debug('ADMIN PRODUCT SERVICE: updateProduct', {
    id,
    actorId: actor?.id,
  });

  const allowedFields = [
    'name',
    'description',
    'category',
    'subcategory',
    'brand',
    'sellingOptions',
    'sellingUnits',
    'defaultSellingUnit',
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

  const product = await Product.findById(id);
  if (!product) {
    throw new Error('Product not found');
  }

  const beforeStock = product.stock;
  const beforeSnapshot = {
    name: product.name,
    description: product.description,
    category: product.category,
    subcategory: product.subcategory,
    brand: product.brand,
    sellingOptions: product.sellingOptions,
    sellingUnits: product.sellingUnits,
    defaultSellingUnit: product.defaultSellingUnit,
    price: product.price,
    stock: product.stock,
    imageUrl: product.imageUrl,
    isActive: product.isActive,
  };

  Object.assign(product, filteredUpdates);
  const requireBrand = updates.brand !== undefined;
  const taxonomy = sanitizeProductTaxonomyFields(
    {
      category: product.category,
      subcategory: product.subcategory,
      brand: product.brand,
    },
    { requireBrand }
  );
  const selling = sanitizeProductSellingFields(
    {
      sellingUnits: product.sellingUnits,
      defaultSellingUnit: product.defaultSellingUnit,
      sellingOptions: product.sellingOptions,
    },
    { requireUnits: true }
  );
  Object.assign(product, taxonomy);
  Object.assign(product, selling);
  product.updatedBy = actor?.id || product.updatedBy;

  await product.save();

  // WHY: Track stock adjustments for inventory audit.
  if (filteredUpdates.stock !== undefined && beforeStock !== product.stock) {
    const delta = product.stock - beforeStock;
    await InventoryEvent.create({
      businessId: product.businessId || null,
      product: product._id,
      delta,
      before: beforeStock,
      after: product.stock,
      reason: 'admin_product_update',
      source: 'admin',
      actor: actor?.id,
      actorRole: actor?.role || 'admin',
    });
  }

  // WHY: Record update changes for compliance.
  await writeAuditLog({
    businessId: product.businessId || null,
    actorId: actor?.id,
    actorRole: actor?.role || 'admin',
    action: 'product_update',
    entityType: 'product',
    entityId: product._id,
    message: `Product updated: ${product.name}`,
    changes: {
      before: beforeSnapshot,
      after: {
        name: product.name,
        description: product.description,
        category: product.category,
        subcategory: product.subcategory,
        brand: product.brand,
        sellingOptions: product.sellingOptions,
        sellingUnits: product.sellingUnits,
        defaultSellingUnit: product.defaultSellingUnit,
        price: product.price,
        stock: product.stock,
        imageUrl: product.imageUrl,
        isActive: product.isActive,
      },
    },
  });

  return product;
}
/**
 * Restore soft-deleted product (admin only)
 */
async function restoreProduct(id, actor) {
  debug('ADMIN PRODUCT SERVICE: restoreProduct', {
    id,
    actorId: actor?.id,
  });

  const product = await Product.findByIdAndUpdate(
    id,
    {
      isActive: true,
      deletedAt: null,
      deletedBy: null,
      updatedBy: actor?.id,
    },
    { new: true, runValidators: true }
  ).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  debug('ADMIN PRODUCT SERVICE: Product restored');

  await writeAuditLog({
    businessId: product.businessId || null,
    actorId: actor?.id,
    actorRole: actor?.role || 'admin',
    action: 'product_restore',
    entityType: 'product',
    entityId: product._id,
    message: `Product restored: ${product.name}`,
  });

  return product;
}
/**

/**
 * Soft delete product
 */
async function softDeleteProduct(id, deletedById, actor) {
  debug('ADMIN PRODUCT SERVICE: softDeleteProduct', {
    id,
    deletedById,
    actorId: actor?.id,
  });

  const product = await Product.findByIdAndUpdate(
    id,
    {
      isActive: false,
      deletedAt: new Date(),
      deletedBy: deletedById,
      updatedBy: actor?.id,
    },
    { new: true, runValidators: true }
  ).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  await writeAuditLog({
    businessId: product.businessId || null,
    actorId: actor?.id || deletedById,
    actorRole: actor?.role || 'admin',
    action: 'product_soft_delete',
    entityType: 'product',
    entityId: product._id,
    message: `Product soft deleted: ${product.name}`,
  });

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
