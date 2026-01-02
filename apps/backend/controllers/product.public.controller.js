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
 * GET /products?page=1&limit=10
 *
 * This function runs WHEN SOMEONE CALLS:
 * - /products
 * - /products?page=2
 * - /products?page=2&limit=5
 */
async function getActiveProducts(req, res) {
  debug('PUBLIC CONTROLLER: getActiveProducts - entry');
  debug('Query params received:', req.query); // BETTER DEBUG: Log incoming params

  try {
    /**
     * -------------------------------------------------
     * STEP 1: START PAGINATION (IMPORTANT)
     * -------------------------------------------------
     *
     * THIS IS WHERE PAGINATION BEGINS.
     *
     * We pass the URL query (?page= & ?limit=)
     * into a helper function.
     *
     * The helper:
     * - fixes bad values
     * - applies defaults
     * - calculates `skip`
     *
     * This keeps this controller CLEAN.
     */

    // Parse and validate pagination params
    let page = parseInt(req.query.page, 10) || 1;
    let limit = parseInt(req.query.limit, 10) || 10;

    // Handle NaN or invalid values safely
    page = isNaN(page) || page < 1 ? 1 : page;
    limit = isNaN(limit) || limit < 1 ? 10 : Math.min(limit, 100); // Max 100 to prevent abuse

    const skip = (page - 1) * limit;

    debug('Calculated pagination:', { page, limit, skip }); // BETTER DEBUG: Log calculated values

    /**
     * -------------------------------------------------
     * STEP 2: FETCH DATA FROM DATABASE
     * -------------------------------------------------
     *
     * We do TWO things at the SAME TIME:
     *
     * 1️⃣ Fetch ONLY the products for THIS page
     * 2️⃣ Count how many total products exist
     *
     * Promise.all = faster than doing them one-by-one
     */
    debug('Starting database queries...'); // BETTER DEBUG: Log query start

    const [products, total] = await Promise.all([
      /**
       * Find ONLY active products
       */
      Product.find({ isActive: true })
        .select({
          deletedAt: 0,
          deletedBy: 0,
          __v: 0,
        })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(), // Faster for read-only (plain JS objects)

      /**
       * Count ALL active products
       * (used to calculate pagination info)
       */
      Product.countDocuments({ isActive: true }),
    ]);

    debug('Queries completed successfully', { totalProducts: total, pageProducts: products.length }); // BETTER DEBUG: Log query results

    /**
     * -------------------------------------------------
     * STEP 3: CALCULATE TOTAL PAGES
     * -------------------------------------------------
     *
     * Example:
     * total = 23 products
     * limit = 5 per page
     *
     * totalPages = Math.ceil(23 / 5) = 5
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: SEND RESPONSE TO FRONTEND
     * -------------------------------------------------
     *
     * We send:
     * - Products for THIS page
     * - Pagination metadata
     *
     * The frontend uses this to:
     * - Show next/prev buttons
     * - Disable buttons
     * - Build infinite scroll
     */
    return res.status(200).json({
      message: 'Products fetched successfully',

      pagination: {
        page,              // current page
        limit,             // items per page
        total,             // total items in DB
        totalPages,        // total pages available
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: products.length, // items returned THIS request
      products,
    });
  } catch (err) {
    debug('PUBLIC CONTROLLER: getActiveProducts - error', err.message);
    debug('Full error stack:', err.stack); // BETTER DEBUG: Log full stack for troubleshooting

    return res.status(500).json({
      error: err.message || 'Failed to fetch products', // FIX 500: Show real error message
    });
  }
}

module.exports = {
  getActiveProducts,
};