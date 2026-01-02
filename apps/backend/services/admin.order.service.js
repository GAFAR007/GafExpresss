/**
 * apps/backend/services/admin.order.service.js
 * --------------------------------------------
 * WHAT:
 * - Business logic for admin order operations
 *
 * WHY:
 * - Centralizes admin access to orders
 */

const Order = require('../models/Order');
const debug = require('../utils/debug');

const ALLOWED_STATUSES = ['pending', 'paid', 'shipped', 'delivered', 'cancelled'];

// Valid status transitions (prevent invalid jumps)
const STATUS_TRANSITIONS = {
  pending: ['paid', 'cancelled'],
  paid: ['shipped', 'cancelled'],
  shipped: ['delivered'],
  delivered: [], // Terminal — no changes
  cancelled: [], // Terminal — no changes
};

/**



/**
 * Get all orders (admin view)
 */
async function getAllOrders() {
  debug('ADMIN ORDER SERVICE: getAllOrders');

  const orders = await Order.find({})
    .populate('user', 'name email')
    .populate('items.product', 'name imageUrl')
    .select({ __v: 0 })
    .sort({ createdAt: -1 });

  return orders;
}

/**
 * Update order status (admin only)
 * @param {string} id
 * @param {string} status
 * @returns {Object} updated order
 */
async function updateOrderStatus(id, status) {
  debug('ADMIN ORDER SERVICE: updateOrderStatus', { id, status });

  if (!ALLOWED_STATUSES.includes(status)) {
    throw new Error(`Invalid status: ${status}`);
  }

  const order = await Order.findById(id);

  if (!order) {
    throw new Error('Order not found');
  }

  // Check valid transition
  const currentStatus = order.status;
  const allowedNext = STATUS_TRANSITIONS[currentStatus] || [];
  if (!allowedNext.includes(status)) {
    throw new Error(`Invalid transition from '${currentStatus}' to '${status}'`);
  }

  order.status = status;
  await order.save();

  // Populate and return
  const populatedOrder = await Order.findById(id)
    .populate('user', 'name email')
    .populate('items.product', 'name imageUrl')
    .select({ __v: 0 });

  return populatedOrder;
}
module.exports = {
  getAllOrders,
  updateOrderStatus,
};