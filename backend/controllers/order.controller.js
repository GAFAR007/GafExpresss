/**
 * apps/backend/controllers/order.controller.js
 * -------------------------------------------
 * WHAT:
 * - Handles user (customer) order requests
 */

const debug = require('../utils/debug');
// CORRECT IMPORT — this file has createOrder and getUserOrders
const orderService = require('../services/order.service');
const Order = require('../models/Order'); // NEW IMPORT for direct model access


async function createOrder(req, res) {
  debug('ORDER CONTROLLER: createOrder - entry');

  try {
    const { items } = req.body;
    const order = await orderService.createOrder(req.user.sub, items);

    return res.status(201).json({
      message: 'Order created successfully',
      order,
    });
  } catch (err) {
    debug('ORDER CONTROLLER: createOrder - error', err.message);
    return res.status(400).json({
      error: err.message,
    });
  }
}

/**
 * GET /orders?page=1&limit=10
 * Protected: Get current user's order history with pagination
 */
async function getMyOrders(req, res) {
  debug('ORDER CONTROLLER: getMyOrders - entry');
  debug('Query params received:', req.query); // BETTER DEBUG: Log incoming params

  try {
    /**
     * -------------------------------------------------
     * STEP 1: START PAGINATION (REUSABLE)
     * -------------------------------------------------
     *
     * We use the shared pagination helper.
     * It handles defaults, validation, and calculates skip.
     */
    const { page, limit, skip } = require('../utils/pagination').getPagination(req.query);

    debug('Calculated pagination:', { page, limit, skip }); // BETTER DEBUG: Log values

    /**
     * -------------------------------------------------
     * STEP 2: FETCH DATA FROM DATABASE
     * -------------------------------------------------
     *
     * We do TWO things at the SAME TIME:
     *
     * 1️⃣ Fetch ONLY the orders for THIS page
     * 2️⃣ Count how many total orders the user has
     *
     * Promise.all = faster than doing them one-by-one
     */
    debug('Starting database queries...'); // BETTER DEBUG: Log query start

    const [orders, total] = await Promise.all([
      Order.find({ user: req.user.sub })
        .populate('items.product', 'name imageUrl')
        .select({ deletedAt: 0, deletedBy: 0, __v: 0 })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),

      Order.countDocuments({ user: req.user.sub }),
    ]);

    debug('Queries completed successfully', { totalOrders: total, pageOrders: orders.length }); // BETTER DEBUG: Log results

    /**
     * -------------------------------------------------
     * STEP 3: CALCULATE TOTAL PAGES
     * -------------------------------------------------
     */
    const totalPages = Math.ceil(total / limit);

    /**
     * -------------------------------------------------
     * STEP 4: SEND RESPONSE TO FRONTEND
     * -------------------------------------------------
     */
    return res.status(200).json({
      message: 'Orders fetched successfully',

      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },

      count: orders.length, // items returned THIS request
      orders,
    });
  } catch (err) {
    debug('ORDER CONTROLLER: getMyOrders - error', err.message);
    debug('Full error stack:', err.stack); // BETTER DEBUG: Full trace

    return res.status(500).json({
      error: err.message || 'Failed to fetch orders',
    });
  }
}
/**
 * PATCH /orders/:id/cancel
 * Customer: Cancel pending order
 */
async function cancelOrder(req, res) {
  debug('ORDER CONTROLLER: cancelOrder - entry', { orderId: req.params.id });

  try {
    const order = await orderService.cancelOrder(req.params.id, req.user.sub);

    return res.status(200).json({
      message: 'Order cancelled successfully',
      order,
    });
  } catch (err) {
    debug('ORDER CONTROLLER: cancelOrder - error', err.message);
    return res.status(400).json({
      error: err.message,
    });
  }
}

// Update exports
module.exports = {
  createOrder,
  getMyOrders,
  cancelOrder, // NEW
};