/**
 * apps/backend/services/order.service.js
 * --------------------------------------
 * WHAT:
 * - Business logic for user orders
 *
 * WHY:
 * - Handles checkout, stock deduction, and user order history
 */

const mongoose = require('mongoose');
const Order = require('../models/Order');
const Product = require('../models/Product');
const debug = require('../utils/debug');

/**
 * Create a new order (checkout)
 * @param {string} userId
 * @param {Array} items - [{productId, quantity}]
 * @returns {Object} created order
 */
async function createOrder(userId, items) {
  debug('ORDER SERVICE: createOrder', { userId, items });

  if (!items || items.length === 0) {
    throw new Error('Order must have at least one item');
  }

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    let totalPrice = 0;
    const orderItems = [];

    for (const item of items) {
      const product = await Product.findById(item.productId).session(session);

      if (!product) {
        throw new Error(`Product not found: ${item.productId}`);
      }

      // Enhanced checks
      if (product.deletedAt) {
        throw new Error(`Product is deleted: ${item.productId}`);
      }
      if (!product.isActive) {
        throw new Error(`Product is inactive: ${item.productId}`);
      }
      if (item.quantity <= 0) {
        throw new Error(`Invalid quantity for product: ${item.productId}`);
      }
      if (product.stock < item.quantity) {
        throw new Error(`Insufficient stock for product: ${item.productId}`);
      }

      // Snapshot price and deduct stock
      const itemPrice = product.price * item.quantity;
      totalPrice += itemPrice;
      product.stock -= item.quantity;
      await product.save({ session });

      orderItems.push({
        product: item.productId,
        quantity: item.quantity,
        price: product.price, // per unit snapshot
      });
    }

    const order = new Order({
      user: userId,
      items: orderItems,
      totalPrice,
    });
    await order.save({ session });

    await session.commitTransaction();
    debug('ORDER SERVICE: Order created successfully');

    return order;
  } catch (err) {
    await session.abortTransaction();
    throw err;
  } finally {
    session.endSession();
  }
}

/**
 * Get orders for a specific user
 * @param {string} userId
 * @returns {Array} list of orders
 */
async function getUserOrders(userId) {
  debug('ORDER SERVICE: getUserOrders', { userId });

  const orders = await Order.find({ user: userId })
    .populate('items.product', 'name imageUrl')
    .select({ deletedAt: 0, deletedBy: 0, __v: 0 })
    .sort({ createdAt: -1 });

  return orders;
}
/**
 * Cancel a pending order (customer only)
 * - Only allowed if status is 'pending'
 * - Restores stock atomically
 * - Placeholder for refund logic
 *
 * @param {string} orderId
 * @param {string} userId - To verify ownership
 * @returns {Object} updated cancelled order
 */
async function cancelOrder(orderId, userId) {
  debug('ORDER SERVICE: cancelOrder', { orderId, userId });

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const order = await Order.findById(orderId).session(session);

    if (!order) {
      throw new Error('Order not found');
    }

    if (order.user.toString() !== userId) {
      throw new Error('Not authorized: This is not your order');
    }

    if (order.status !== 'pending') {
      throw new Error('Can only cancel pending orders');
    }

    // Restore stock for each item
    for (const item of order.items) {
      const product = await Product.findById(item.product).session(session);
      if (product) {
        product.stock += item.quantity;
        await product.save({ session });
      }
    }

    // Update order status
    order.status = 'cancelled';
    await order.save({ session });

    // Placeholder for real refund processing
    debug('REFUND PLACEHOLDER: Initiate refund for order', orderId);

    await session.commitTransaction();
    debug('ORDER SERVICE: Order cancelled and stock restored');

    return order;
  } catch (err) {
    await session.abortTransaction();
    throw err;
  } finally {
    session.endSession();
  }
}

// EXPORT ALL FUNCTIONS
module.exports = {
  createOrder,
  getUserOrders,
  cancelOrder, // ← THIS WAS MISSING!
};