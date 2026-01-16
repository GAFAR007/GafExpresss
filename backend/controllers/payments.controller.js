/**
 * controllers/payments.controller.js
 * ----------------------------------
 * WHAT:
 * - HTTP controller for payment-related endpoints.
 *
 * WHY:
 * - Keeps routes thin and consistent.
 * - Central place for request validation + responses.
 *
 * HOW:
 * - Validates input, then delegates to Paystack service.
 */

const debug = require("../utils/debug");
const paystackService = require("../services/paystack.service");

/**
 * POST /payments/paystack/init
 *
 * Starts a Paystack transaction for an order.
 */
async function initPaystack(req, res) {
  debug("PAYMENTS CONTROLLER: initPaystack - entry");

  try {
    const { orderId, callbackUrl } = req.body || {};
    const userId = req.user?.sub;

    // WHY: Avoid ambiguous errors by validating required fields.
    if (!orderId) {
      debug("PAYMENTS CONTROLLER: Missing orderId");
      return res.status(400).json({ error: "orderId is required" });
    }
    if (!userId) {
      debug("PAYMENTS CONTROLLER: Missing userId on request");
      return res.status(401).json({ error: "Unauthorized" });
    }

    debug("PAYMENTS CONTROLLER: initPaystack request validated", {
      orderId,
    });

    const result = await paystackService.initPaystackTransaction({
      orderId,
      userId,
      callbackUrl,
    });

    debug("PAYMENTS CONTROLLER: initPaystack success");

    return res.status(200).json({
      message: "Paystack init success",
      data: {
        authorization_url: result.authorizationUrl,
        reference: result.reference,
        access_code: result.accessCode,
      },
    });
  } catch (err) {
    debug("PAYMENTS CONTROLLER: initPaystack failed", err.message);
    return res.status(400).json({
      error: err.message || "Paystack init failed",
    });
  }
}

module.exports = {
  initPaystack,
};
