/**
 * routes/order.routes.js
 * ----------------------
 * WHAT:
 * - Defines user (customer) order routes
 *
 * WHY:
 * - Allows authenticated customers to:
 *   • create orders
 *   • view their own orders
 *   • cancel pending orders
 */

const express = require('express');
const debug = require('../utils/debug');
const { requireAuth } = require('../middlewares/auth.middleware');
const orderController = require('../controllers/order.controller');

const router = express.Router();

debug('Order routes initialized');

/**
 * @swagger
 * tags:
 *   name: Orders
 *   description: Customer order actions
 */

/**
 * @swagger
 * /orders:
 *   post:
 *     operationId: createOrder
 *     summary: Create a new order (checkout)
 *     tags: [Orders]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [items, deliveryAddress]
 *             properties:
 *               items:
 *                 type: array
 *                 items:
 *                   type: object
 *                   required: [product, quantity]
 *                   properties:
 *                     product:
 *                       type: string
 *                     quantity:
 *                       type: integer
 *               deliveryAddress:
 *                 type: object
 *                 required: [source]
 *                 properties:
 *                   source:
 *                     type: string
 *                     enum: [home, company, custom]
 *                   houseNumber:
 *                     type: string
 *                   street:
 *                     type: string
 *                   city:
 *                     type: string
 *                   state:
 *                     type: string
 *                   postalCode:
 *                     type: string
 *                   lga:
 *                     type: string
 *                   country:
 *                     type: string
 *                   landmark:
 *                     type: string
 *     responses:
 *       201:
 *         description: Order created successfully
 */

router.post('/', requireAuth, orderController.createOrder);

/**
 * @swagger
 * /orders:
 *   get:
 *     operationId: getMyOrders
 *     summary: Get orders for the authenticated customer
 *     tags: [Orders]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Orders retrieved successfully
 */

router.get('/', requireAuth, orderController.getMyOrders);
/**
 * @swagger
 * /orders/{id}/cancel:
 *   patch:
 *     operationId: cancelOrder
 *     summary: Cancel a pending order
 *     tags: [Orders]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: Order cancelled
 */

router.patch('/:id/cancel', requireAuth, orderController.cancelOrder);

module.exports = router;
