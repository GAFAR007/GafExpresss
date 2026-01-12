/**
 * routes/webhooks.routes.js
 * -------------------------
 * WHAT:
 * - Receives external payment provider webhooks (Paystack)
 *
 * WHY:
 * - Webhooks are the ONLY trusted source of payment truth
 * - Frontend redirects CANNOT be trusted
 *
 * CRITICAL:
 * - Uses RAW BODY (NOT express.json)
 * - Required for signature verification
 */

const express = require("express");
const debug = require("../utils/debug");
const webhooksController = require("../controllers/webhooks.controller");
const {
  verifyPaystackSignature,
} = require("../middlewares/paystackWebhook.middleware");

const router = express.Router();

debug("Webhook routes initialized");

/**
 * POST /webhooks/paystack
 *
 * Paystack webhook endpoint
 *
 * IMPORTANT:
 * - Must return 200 quickly
 * - Must never throw uncaught errors
 * - Must verify signature BEFORE processing
 */
router.post(
  "/paystack",
  express.raw({ type: "application/json" }), // 🔐 REQUIRED FOR SIGNATURE VERIFICATION
  verifyPaystackSignature, // 🔒 MUST RUN BEFORE controller
  webhooksController.handlePaystackWebhook // ✅ MUST EXIST
);

module.exports = router;
