/**
 * controllers/webhooks.controller.js
 * ---------------------------------
 * WHAT:
 * - HTTP controller for webhook endpoints
 *
 * WHY:
 * - Keeps routes thin
 * - Keeps services free of Express response logic
 * - Ensures consistent error handling + fast responses
 *
 * IMPORTANT:
 * - Webhooks must return 200 quickly to prevent repeated retries
 * - Only return 401 when signature is invalid (security)
 */

const debug = require("../utils/debug");
const webhookService = require("../services/webhook.service");

/**
 * Handle Paystack webhook (Express controller)
 *
 * FLOW:
 * 1) Log entry
 * 2) Call service (does event routing / DB updates)
 * 3) Return HTTP status safely
 */
async function handlePaystackWebhook(req, res) {
  debug("WEBHOOK CONTROLLER: handlePaystackWebhook - entry");

  try {
    await webhookService.handlePaystackWebhook(req);

    debug("WEBHOOK CONTROLLER: handled successfully ✅");
    return res.sendStatus(200);
  } catch (err) {
    debug("WEBHOOK CONTROLLER: error", err.message);

    // ❌ Reject ONLY invalid signature (security)
    if (err.message === "Invalid Paystack signature") {
      debug("WEBHOOK CONTROLLER: invalid signature → 401");
      return res.sendStatus(401);
    }

    /**
     * ✅ Acknowledge everything else to avoid webhook retries.
     * We LOG failures so you can inspect later.
     */
    debug("WEBHOOK CONTROLLER: non-signature error → ACK 200 to prevent retries");
    return res.sendStatus(200);
  }
}

module.exports = {
  handlePaystackWebhook,
};