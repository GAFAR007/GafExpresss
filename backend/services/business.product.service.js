/**
 * apps/backend/services/business.product.service.js
 * -------------------------------------------------
 * WHAT:
 * - Business-scoped product operations for owners and staff.
 *
 * WHY:
 * - Ensures business users can only manage their own products.
 * - Adds audit + inventory trails for compliance.
 *
 * HOW:
 * - Filters by businessId and records actor metadata.
 */

const Product = require('../models/Product');
const InventoryEvent = require('../models/InventoryEvent');
const { writeAuditLog } = require('../utils/audit');
const { writeAnalyticsEvent } = require('../utils/analytics');
const { getPagination } = require('../utils/pagination');
const { getSort } = require('../utils/sort');
const debug = require('../utils/debug');

async function createProduct({ data, actor, businessId }) {
  debug('BUSINESS PRODUCT SERVICE: createProduct', {
    actorId: actor?.id,
    businessId,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const product = new Product({
    ...data,
    businessId,
    createdBy: actor?.id,
    updatedBy: actor?.id,
  });

  await product.save();

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: 'product_create',
    entityType: 'product',
    entityId: product._id,
    message: `Product created: ${product.name}`,
  });

  // WHY: Analytics event powers summary tiles without frontend math.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: 'product_created',
    entityType: 'product',
    entityId: product._id,
    metadata: {
      price: product.price,
      stock: product.stock,
      isActive: product.isActive,
    },
  });

  return product;
}

async function getAllProducts({ businessId, query }) {
  debug('BUSINESS PRODUCT SERVICE: getAllProducts', {
    businessId,
    query,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const { page, limit, skip } = getPagination(query);
  const filter = { businessId };

  if (query?.isActive === 'true') filter.isActive = true;
  if (query?.isActive === 'false') filter.isActive = false;

  const search = query?.q?.trim();
  if (search) {
    filter.$text = { $search: search };
  }

  const sort = getSort(query?.sort, ['price', 'stock', 'name', 'createdAt'], {
    createdAt: -1,
  });

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

async function getProductById({ businessId, id }) {
  debug('BUSINESS PRODUCT SERVICE: getProductById', { businessId, id });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  return Product.findOne({ _id: id, businessId }).select({ __v: 0 });
}

async function updateProduct({ businessId, id, updates, actor }) {
  debug('BUSINESS PRODUCT SERVICE: updateProduct', {
    businessId,
    id,
    actorId: actor?.id,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const allowedFields = [
    'name',
    'description',
    'price',
    'stock',
    'imageUrl',
    'isActive',
    'productionState',
    'productionPlanId',
    'conservativeYieldQuantity',
    'conservativeYieldUnit',
    'preorderEnabled',
    'preorderStartDate',
    'preorderCapQuantity',
    'preorderReservedQuantity',
    'preorderReleasedQuantity',
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

  const product = await Product.findOne({ _id: id, businessId });
  if (!product) {
    throw new Error('Product not found');
  }

  const beforeStock = product.stock;
  const beforeSnapshot = {
    name: product.name,
    description: product.description,
    price: product.price,
    stock: product.stock,
    imageUrl: product.imageUrl,
    isActive: product.isActive,
    productionState: product.productionState,
    productionPlanId: product.productionPlanId,
    conservativeYieldQuantity: product.conservativeYieldQuantity,
    conservativeYieldUnit: product.conservativeYieldUnit,
    preorderEnabled: product.preorderEnabled,
    preorderStartDate: product.preorderStartDate,
    preorderCapQuantity: product.preorderCapQuantity,
    preorderReservedQuantity: product.preorderReservedQuantity,
    preorderReleasedQuantity: product.preorderReleasedQuantity,
  };

  Object.assign(product, filteredUpdates);
  product.updatedBy = actor?.id || product.updatedBy;
  await product.save();

  if (filteredUpdates.stock !== undefined && beforeStock !== product.stock) {
    const delta = product.stock - beforeStock;
    await InventoryEvent.create({
      businessId,
      product: product._id,
      delta,
      before: beforeStock,
      after: product.stock,
      reason: 'business_product_update',
      source: 'business',
      actor: actor?.id,
      actorRole: actor?.role,
    });
  }

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: 'product_update',
    entityType: 'product',
    entityId: product._id,
    message: `Product updated: ${product.name}`,
    changes: {
      before: beforeSnapshot,
      after: {
        name: product.name,
        description: product.description,
        price: product.price,
        stock: product.stock,
        imageUrl: product.imageUrl,
        isActive: product.isActive,
        productionState: product.productionState,
        productionPlanId: product.productionPlanId,
        conservativeYieldQuantity: product.conservativeYieldQuantity,
        conservativeYieldUnit: product.conservativeYieldUnit,
        preorderEnabled: product.preorderEnabled,
        preorderStartDate: product.preorderStartDate,
        preorderCapQuantity: product.preorderCapQuantity,
        preorderReservedQuantity: product.preorderReservedQuantity,
        preorderReleasedQuantity: product.preorderReleasedQuantity,
      },
    },
  });

  // WHY: Capture product changes for analytics timelines.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: 'product_updated',
    entityType: 'product',
    entityId: product._id,
    metadata: {
      price: product.price,
      stock: product.stock,
      isActive: product.isActive,
      productionState: product.productionState,
      preorderEnabled: product.preorderEnabled,
      preorderCapQuantity: product.preorderCapQuantity,
      preorderReservedQuantity: product.preorderReservedQuantity,
    },
  });

  return product;
}

async function softDeleteProduct({ businessId, id, actor }) {
  debug('BUSINESS PRODUCT SERVICE: softDeleteProduct', {
    businessId,
    id,
    actorId: actor?.id,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const product = await Product.findOneAndUpdate(
    { _id: id, businessId },
    {
      isActive: false,
      deletedAt: new Date(),
      deletedBy: actor?.id,
      updatedBy: actor?.id,
    },
    { new: true, runValidators: true }
  ).select({ __v: 0 });

  if (!product) {
    throw new Error('Product not found');
  }

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: 'product_soft_delete',
    entityType: 'product',
    entityId: product._id,
    message: `Product soft deleted: ${product.name}`,
  });

  // WHY: Track product archive actions for analytics.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: 'product_archived',
    entityType: 'product',
    entityId: product._id,
  });

  return product;
}

async function restoreProduct({ businessId, id, actor }) {
  debug('BUSINESS PRODUCT SERVICE: restoreProduct', {
    businessId,
    id,
    actorId: actor?.id,
  });

  if (!businessId) {
    throw new Error('Business scope is required');
  }

  const product = await Product.findOneAndUpdate(
    { _id: id, businessId },
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

  await writeAuditLog({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    action: 'product_restore',
    entityType: 'product',
    entityId: product._id,
    message: `Product restored: ${product.name}`,
  });

  // WHY: Track restore actions so analytics reflect activations.
  await writeAnalyticsEvent({
    businessId,
    actorId: actor?.id,
    actorRole: actor?.role,
    eventType: 'product_restored',
    entityType: 'product',
    entityId: product._id,
  });

  return product;
}

module.exports = {
  createProduct,
  getAllProducts,
  getProductById,
  updateProduct,
  softDeleteProduct,
  restoreProduct,
};
