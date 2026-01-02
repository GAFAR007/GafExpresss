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
      if (!product.isActive) {
        throw new Error(`Product is inactive: ${item.productId}`);
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
        price: product.price, // per unit
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
    .populate('items.product', 'name imageUrl') // Populate product details for display
    .select({ deletedAt: 0, deletedBy: 0, __v: 0 })
    .sort({ createdAt: -1 });

  return orders;
}

module.exports = {
  createOrder,
  getUserOrders,
};