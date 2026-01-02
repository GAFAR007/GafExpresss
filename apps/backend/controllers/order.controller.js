/**
 * apps/backend/controllers/order.controller.js
 * -------------------------------------------
 * WHAT:
 * - Handles user (customer) order requests
 */

const debug = require('../utils/debug');
// CORRECT IMPORT — this file has createOrder and getUserOrders
const orderService = require('../services/order.service');

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

async function getMyOrders(req, res) {
  debug('ORDER CONTROLLER: getMyOrders - entry');

  try {
    const orders = await orderService.getUserOrders(req.user.sub);

    return res.status(200).json({
      message: 'Orders fetched successfully',
      count: orders.length,
      orders,
    });
  } catch (err) {
    debug('ORDER CONTROLLER: getMyOrders - error', err.message);
    return res.status(500).json({
      error: 'Failed to fetch orders',
    });
  }
}

module.exports = {
  createOrder,
  getMyOrders,
};