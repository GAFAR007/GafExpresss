/**
 * routes/order.routes.js
 * ----------------------
 * WHAT:
 * - Defines user order routes
 */

const express = require('express');
const debug = require('../utils/debug');
const { requireAuth } = require('../middlewares/auth.middleware');
const orderController = require('../controllers/order.controller');

const router = express.Router();

debug('Order routes initialized');

/**
 * POST /orders
 * Protected: Create order (checkout)
 */
router.post('/', requireAuth, orderController.createOrder);

/**
 * GET /orders
 * Protected: Get my orders
 */
router.get('/', requireAuth, orderController.getMyOrders);

module.exports = router;