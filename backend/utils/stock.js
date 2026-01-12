/**
 * utils/stock.js
 * --------------
 * WHAT: Reusable stock management for orders
 *
 * WHY:
 * - Central place for all stock adjustments
 * - Used by admin status updates, customer checkout, returns, etc.
 * - Keeps order service clean and focused
 * - Easy to test and modify in one place
 */

const mongoose = require('mongoose');
const Product = require('../models/Product');
const debug = require('./debug');

/**
 * Adjust stock based on order status change
 *
 * @param {Object} order - Full order document (with items array)
 * @param {string} action - 'decrease' (for paid) or 'restore' (for cancelled)
 * @param {Object} session - Active MongoDB session for atomicity
 */
async function adjustOrderStock(order, action, session) {
  if (!order || !order.items || order.items.length === 0) {
    return;
  }

  debug(`STOCK: Adjusting stock - ${action}`, {
    orderId: order._id,
    itemCount: order.items.length,
  });

  for (const item of order.items) {
    const product = await Product.findById(item.product).session(session);
    if (!product) {
      throw new Error(`Product not found: ${item.product}`);
    }

    const quantity = item.quantity;
    const delta = action === 'decrease' ? -quantity : +quantity;

    if (action === 'decrease' && product.stock < quantity) {
      throw new Error(
        `Insufficient stock: ${product.name} (need ${quantity}, available ${product.stock})`
      );
    }

    product.stock += delta;
    await product.save({ session });

    debug(
      `STOCK: ${product.name} → ${product.stock} (${
        delta > 0 ? '+' : ''
      }${delta})`
    );
  }
}

module.exports = {
  adjustOrderStock,
};
