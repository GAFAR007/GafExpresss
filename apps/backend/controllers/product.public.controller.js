/**
 * apps/backend/controllers/product.public.controller.js
 * ---------------------------------------------------
 * WHAT:
 * - Handles public (unauthenticated) product requests
 */

const debug = require('../utils/debug');
const Product = require('../models/Product');

/**
 * GET /products
 * Public: List active products
 */
async function getActiveProducts(req, res) {
  debug('PUBLIC CONTROLLER: getActiveProducts - entry');

  try {
    const products = await Product.find({ isActive: true })
      .select({
        deletedAt: 0,
        deletedBy: 0,
        __v: 0,
      })
      .sort({ createdAt: -1 });

    return res.status(200).json({
      message: 'Products fetched successfully',
      count: products.length,
      products,
    });
  } catch (err) {
    debug('PUBLIC CONTROLLER: getActiveProducts - error', err.message);
    return res.status(500).json({
      error: 'Failed to fetch products',
    });
  }
}

module.exports = {
  getActiveProducts,
};