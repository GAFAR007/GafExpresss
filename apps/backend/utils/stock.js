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
const InventoryEvent = require('../models/InventoryEvent');
const debug = require('./debug');

/**
 * Adjust stock based on order status change
 *
 * @param {Object} order - Full order document (with items array)
 * @param {string} action - 'decrease' (for paid) or 'restore' (for cancelled)
 * @param {Object} session - Active MongoDB session for atomicity
 * @param {Object} context - Actor + metadata for audit trails
 */
async function adjustOrderStock(order, action, session, context = {}) {
  if (!order || !order.items || order.items.length === 0) {
    return;
  }

  debug(`STOCK: Adjusting stock - ${action}`, {
    orderId: order._id,
    itemCount: order.items.length,
  });

  const fallbackActorId = context.actorId || order.user;
  const fallbackActorRole = context.actorRole || 'system';

  for (const item of order.items) {
    const product = await Product.findById(item.product).session(session);
    if (!product) {
      throw new Error(`Product not found: ${item.product}`);
    }

    const quantity = item.quantity;
    const delta = action === 'decrease' ? -quantity : +quantity;
    const before = product.stock;

    if (action === 'decrease' && product.stock < quantity) {
      throw new Error(
        `Insufficient stock: ${product.name} (need ${quantity}, available ${product.stock})`
      );
    }

    product.stock += delta;
    product.updatedBy = fallbackActorId || product.updatedBy;
    await product.save({ session });

    debug(
      `STOCK: ${product.name} → ${product.stock} (${
        delta > 0 ? '+' : ''
      }${delta})`
    );

    // WHY: Persist inventory history for audits and troubleshooting.
    await InventoryEvent.create(
      [
        {
          businessId: context.businessId || product.businessId || null,
          product: product._id,
          delta,
          before,
          after: product.stock,
          reason: context.reason || `order_${action}`,
          source: context.source || 'order_status',
          orderId: order._id,
          actor: fallbackActorId,
          actorRole: fallbackActorRole,
        },
      ],
      { session }
    );
  }
}

module.exports = {
  adjustOrderStock,
};
