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
     * STEP 1.6: FULL-TEXT SEARCH (?q=)
     * -------------------------------------------------
     *
     * Same pattern as ADMIN products
     */
    const search = req.query.q?.trim();

    /**
     * BASE FILTER (always applied)
     * Public users only see active products
     */
    const filter = {
      isActive: true,
    };

    /**
     * If search exists, enable MongoDB text search
     */
    if (search) {
      filter.$text = { $search: search };
    }

    debug('Using search filter:', filter);

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

    if (!product || !product.isActive || product.deletedAt) {
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

module.exports = {
  getActiveProducts,
  getActiveProductById,
};
