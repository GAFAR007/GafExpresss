/**
 * apps/backend/middlewares/paystackWebhook.middleware.js
 * -----------------------------------------------------
 * WHAT THIS FILE IS:
 * - Middleware that verifies Paystack webhooks are REAL
 *
 * WHY THIS EXISTS:
 * - Anyone can hit your webhook URL publicly
 * - Without verification, attackers can fake "payment successful"
 *
 * HOW IT WORKS:
 * - Paystack sends a signature in `x-paystack-signature`
 * - We compute our own signature using:
 *   HMAC-SHA512(secret_key, RAW_REQUEST_BODY)
 * - If they match -> request is legit
 */

const crypto = require("crypto");
const debug = require("../utils/debug");

function verifyPaystackSignature(req, res, next) {
  debug("PAYSTACK WEBHOOK VERIFY: entry");

  const secret = process.env.PAYSTACK_SECRET_KEY;
  const signature = req.headers["x-paystack-signature"];

  debug(
    "PAYSTACK WEBHOOK VERIFY: header signature present?",
    !!signature
  );
  debug(
    "PAYSTACK WEBHOOK VERIFY: has PAYSTACK_SECRET_KEY?",
    !!secret
  );

  // ✅ If your secret key is missing, we CANNOT verify anything
  if (!secret) {
    debug(
      "PAYSTACK WEBHOOK VERIFY: missing PAYSTACK_SECRET_KEY"
    );
    return res.status(500).json({
      error:
        "Server misconfigured (missing PAYSTACK_SECRET_KEY)",
    });
  }

  // ✅ Paystack must send this header
  if (!signature) {
    debug(
      "PAYSTACK WEBHOOK VERIFY: missing x-paystack-signature header"
    );
    return res
      .status(401)
      .json({ error: "Missing Paystack signature" });
  }

  /**
   * ✅ VERY IMPORTANT:
   * req.body MUST be raw Buffer here (not parsed JSON),
   * otherwise the signature check may fail.
   */
  const rawBody = req.body;

  debug(
    "PAYSTACK WEBHOOK VERIFY: rawBody type",
    typeof rawBody
  );
  debug(
    "PAYSTACK WEBHOOK VERIFY: rawBody is Buffer?",
    Buffer.isBuffer(rawBody)
  );

  // Compute signature: HMAC-SHA512(secret, rawBody)
  const hash = crypto
    .createHmac("sha512", secret)
    .update(rawBody)
    .digest("hex");

  const matches = hash === signature;

  debug(
    "PAYSTACK WEBHOOK VERIFY: computed hash prefix",
    hash.slice(0, 10)
  );
  debug(
    "PAYSTACK WEBHOOK VERIFY: signature matches?",
    matches
  );

  if (!matches) {
    debug("PAYSTACK WEBHOOK VERIFY: ❌ invalid signature");
    return res
      .status(401)
      .json({ error: "Invalid Paystack signature" });
  }

  debug("PAYSTACK WEBHOOK VERIFY: ✅ signature verified");
  return next();
}

module.exports = {
  verifyPaystackSignature,
};
