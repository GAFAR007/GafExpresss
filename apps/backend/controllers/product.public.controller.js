/**
 * apps/backend/controllers/product.public.controller.js
 * ---------------------------------------------------
 * WHAT THIS FILE IS:
 * - Controls what happens when someone visits:
 *   GET /products
 *
 * WHY THIS FILE EXISTS:
 * - This endpoint is PUBLIC (no login required)
 * - Anyone can browse products in the store
 *
 * IMPORTANT IDEA:
 * - We NEVER send all products at once
 * - We send them in SMALL PIECES (pagination)
 */

const debug = require('../utils/debug');
const Product = require('../models/Product');
const {
  buildPreorderCapConfidenceSummary,
} = require('../services/preorder_cap_confidence.service');
const PRODUCT_STATE_AVAILABLE_FOR_PREORDER =
  'available_for_preorder';

function buildPreorderAvailabilitySummary(product) {
  const cap = Math.max(
    0,
    Number(product?.preorderCapQuantity || 0),
  );
  const reserved = Math.max(
    0,
    Number(product?.preorderReservedQuantity || 0),
  );
  const remaining = Math.max(0, cap - reserved);

  return {
    preorderEnabled: product?.preorderEnabled === true,
    preorderCapQuantity: cap,
    preorderReservedQuantity: reserved,
    preorderRemainingQuantity: remaining,
  };
}

/**
 * GET /products?page=1&limit=10&sort=price:asc&q=shirt
 *
 * This function runs WHEN SOMEONE CALLS:
 * - /products
 * - /products?page=2
 * - /products?page=2&limit=5
 * - /products?sort=price:desc
 * - /products?q=denim
 */
async function getActiveProducts(req, res) {
  debug('PUBLIC CONTROLLER: getActiveProducts - entry');
  debug('Query params received:', req.query);

  try {
    /**
     * -------------------------------------------------
     * STEP 1: PAGINATION (shared system-wide logic)
     * -------------------------------------------------
     */
    const { page, limit, skip } = require('../utils/pagination').getPagination(
      req.query
    );

    debug('Calculated pagination:', { page, limit, skip });

    /**
     * -------------------------------------------------
     * STEP 1.5: SORTING (shared helper)
     * -------------------------------------------------
     */
    const allowedSortFields = ['price', 'createdAt', 'name'];
    const sort = require('../utils/sort').getSort(
      req.query.sort,
      allowedSortFields,
      { createdAt: -1 }
    );

    debug('Using sort:', sort);

    /**
     * -------------------------------------------------
     * STEP 1.6: SEARCH (?q=)
     * -------------------------------------------------
     *
     * NOTE:
     * - Use a case-insensitive regex so partial words match
     *   (e.g., "leathe" matches "Leather").
     */
    const search = req.query.q?.trim();

    /**
     * -------------------------------------------------
     * STEP 1.7: STOCK FILTER (?inStock=true)
     * -------------------------------------------------
     *
     * WHY:
     * - Keeps frontend dumb; backend decides availability.
     */
    const inStockOnly = req.query.inStock === 'true';

    /**
     * BASE FILTER (always applied)
     * Public users only see active products
     */
    const filter = {
      $or: [
        { isActive: true },
        {
          productionState:
            PRODUCT_STATE_AVAILABLE_FOR_PREORDER,
          preorderEnabled: true,
        },
      ],
    };

    /**
     * If search exists, use regex for partial matching.
     * WHY:
     * - Text search requires full terms and feels "late" on mobile typing.
     */
    if (search) {
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      filter.$or = [
        { name: { $regex: escaped, $options: 'i' } },
        { description: { $regex: escaped, $options: 'i' } },
      ];
    }

    /**
     * If inStockOnly, only return products with stock > 0.
     */
    if (inStockOnly) {
      filter.stock = { $gt: 0 };
    }

    debug('Using search filter:', filter);
    debug('Using inStockOnly:', inStockOnly);

    /**
     * -------------------------------------------------
     * STEP 2: DATABASE QUERY
     * -------------------------------------------------
     */
    const [products, total] = await Promise.all([
      Product.find(filter)
        .select({
          deletedAt: 0,
          deletedBy: 0,
          __v: 0,
        })
        .sort(sort)
        .skip(skip)
        .limit(limit)
        .lean(),

      Product.countDocuments(filter),
    ]);

    debug('Queries completed successfully', {
      totalProducts: total,
      pageProducts: products.length,
    });

    /**
     * -------------------------------------------------
     * STEP 3: PAGINATION METADATA
     * -------------------------------------------------
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: RESPONSE
     * -------------------------------------------------
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
      count: products.length,
      products,
    });
  } catch (err) {
    debug('PUBLIC CONTROLLER: getActiveProducts - error', err.message);
    debug('Full error stack:', err.stack);

    return res.status(500).json({
      error: err.message || 'Failed to fetch products',
    });
  }
}

/**
 * GET /products/:id
 *
 * Public: Fetch single active product by id
 *
 * WHY:
 * - Allows product detail pages to load by id
 * - Keeps response minimal and public-safe
 */
async function getActiveProductById(req, res) {
  debug('PUBLIC CONTROLLER: getActiveProductById - entry', {
    id: req.params.id,
  });

  try {
    const product = await Product.findById(req.params.id)
      .select({
        deletedAt: 0,
        deletedBy: 0,
        __v: 0,
      })
      .lean();

    const isPreorderVisible =
      product?.productionState ===
        PRODUCT_STATE_AVAILABLE_FOR_PREORDER &&
      product?.preorderEnabled === true;
    if (
      !product ||
      product.deletedAt ||
      (!product.isActive &&
        !isPreorderVisible)
    ) {
      debug('PUBLIC CONTROLLER: getActiveProductById - not found');
      return res.status(404).json({
        error: 'Product not found',
      });
    }

    return res.status(200).json({
      message: 'Product fetched successfully',
      product,
    });
  } catch (err) {
    debug('PUBLIC CONTROLLER: getActiveProductById - error', err.message);
    debug('Full error stack:', err.stack);

    return res.status(500).json({
      error: err.message || 'Failed to fetch product',
    });
  }
}

/**
 * GET /products/:id/preorder-availability
 *
 * Public: return pre-order cap/reserved/remaining summary for a visible product.
 */
async function getPreorderAvailabilitySummary(req, res) {
  debug(
    'PUBLIC CONTROLLER: getPreorderAvailabilitySummary - entry',
    { id: req.params.id },
  );

  try {
    const product = await Product.findById(req.params.id)
      .select({
        businessId: 1,
        isActive: 1,
        deletedAt: 1,
        productionState: 1,
        productionPlanId: 1,
        preorderEnabled: 1,
        preorderCapQuantity: 1,
        preorderReservedQuantity: 1,
      })
      .lean();

    const isPreorderVisible =
      product?.productionState ===
        PRODUCT_STATE_AVAILABLE_FOR_PREORDER &&
      product?.preorderEnabled === true;
    if (
      !product ||
      product.deletedAt ||
      (!product.isActive &&
        !isPreorderVisible)
    ) {
      return res.status(404).json({
        error: 'Product not found',
      });
    }

    const summary =
      buildPreorderAvailabilitySummary(product);
    const capConfidence =
      await buildPreorderCapConfidenceSummary({
        productId: product._id,
        businessId: product.businessId,
        planId: product.productionPlanId,
        baseCap:
          summary.preorderCapQuantity,
      });

    return res.status(200).json({
      message:
        'Pre-order availability fetched successfully',
      productId: req.params.id,
      availability: {
        ...summary,
        ...capConfidence,
      },
    });
  } catch (err) {
    debug(
      'PUBLIC CONTROLLER: getPreorderAvailabilitySummary - error',
      err.message,
    );
    return res.status(500).json({
      error:
        err.message ||
        'Failed to fetch pre-order availability',
    });
  }
}

module.exports = {
  getActiveProducts,
  getActiveProductById,
  getPreorderAvailabilitySummary,
};
