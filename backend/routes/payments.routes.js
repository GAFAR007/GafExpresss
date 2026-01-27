/**
 * routes/payments.routes.js
 * -------------------------
 * WHAT:
 * - Defines payment initialization routes.
 *
 * WHY:
 * - Exposes Paystack init endpoint for the frontend.
 *
 * HOW:
 * - Protected by requireAuth.
 * - Delegates logic to payments.controller.
 */

const express = require("express");
const debug = require("../utils/debug");
const {
  requireAuth,
} = require("../middlewares/auth.middleware");
const paymentsController = require("../controllers/payments.controller");

const router = express.Router();

debug("Payments routes initialized");

/**
 * @swagger
 * tags:
 *   name: Payments
 *   description: Payment initialization
 */

/**
 * @swagger
 * /payments/paystack/init:
 *   post:
 *     operationId: initPaystack
 *     summary: Initialize Paystack checkout
 *     tags: [Payments]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [orderId]
 *             properties:
 *               orderId:
 *                 type: string
 *               callbackUrl:
 *                 type: string
 *     responses:
 *       200:
 *         description: Paystack init success
 */
router.post(
  "/paystack/init",
  requireAuth,
  // WHY: Only authenticated users can start a payment for their own order.
  paymentsController.initPaystack
);

/**
 * @swagger
 * /payments/paystack/verify:
 *   get:
 *     operationId: verifyPaystack
 *     summary: Verify Paystack reference (server-side)
 *     tags: [Payments]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: query
 *         name: reference
 *         required: true
 *         schema:
 *           type: string
 *     responses:
 *       200:
 *         description: Paystack verification processed
 */
router.get(
  "/paystack/verify",
  requireAuth,
  // WHY: Verification must be server-side and scoped to the payment owner.
  paymentsController.verifyPaystack
);

module.exports = router;
