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

  const order = await Order.findByIdAndUpdate(
    id,
    { status },
    { new: true }
  )
    .populate('user', 'name email')
    .populate('items.product', 'name imageUrl')
    .select({ __v: 0 });

  if (!order) {
    throw new Error('Order not found');
  }

  return order;
}

module.exports = {
  getAllOrders,
  updateOrderStatus,
};