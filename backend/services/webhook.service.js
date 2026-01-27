/**
 * services/webhook.service.js
 * ---------------------------
 * WHAT:
 * - Central webhook handler logic (NO Express here)
 *
 * WHY:
 * - Keeps routes thin
 * - Makes webhook logic testable
 * - Prevents business logic leakage
 *
 * RULE:
 * - Verify signature FIRST
 * - Parse raw body SECOND
 * - Delegate DB writes to payment.service THIRD
 */

const crypto = require("crypto");
const debug = require("../utils/debug");
const paymentService = require("./payment.service");

const PAYSTACK_SECRET = process.env.PAYSTACK_SECRET_KEY;

// --------------------------------------------------
// STARTUP DEBUG (SAFE)
// --------------------------------------------------
debug(
  "Paystack secret loaded:",
  PAYSTACK_SECRET ? "YES" : "NO"
);

if (process.env.NODE_ENV !== "production") {
  debug(
    "Paystack secret suffix (dev only):",
    PAYSTACK_SECRET
      ? `****${PAYSTACK_SECRET.slice(-4)}`
      : "No secret"
  );
}

// --------------------------------------------------
// MAIN WEBHOOK HANDLER
// --------------------------------------------------
/**
 * Handle Paystack webhook
 *
 * STEPS:
 * 1) Verify signature
 * 2) Parse event JSON (raw body)
 * 3) Delegate to payment.service (idempotency + DB writes)
 */
async function handlePaystackWebhook(req) {
  debug("WEBHOOK SERVICE: Entry");

  // 1️⃣ Verify signature FIRST
  verifyPaystackSignature(req);

  // 2️⃣ Parse raw body → JSON
  const event = JSON.parse(req.body.toString("utf8"));

  debug("WEBHOOK SERVICE: Signature verified ✅");
  debug("WEBHOOK SERVICE: Event received", {
    event: event?.event,
    reference: event?.data?.reference,
  });
  debug("WEBHOOK SERVICE: Dispatching to payment service", {
    source: "paystack_webhook",
    eventType: event?.event,
    referenceSuffix: event?.data?.reference
      ? event.data.reference.slice(-6)
      : null,
  });

  // 3️⃣ Delegate ALL business logic
  await paymentService.processPaystackEvent(event);

  debug("WEBHOOK SERVICE: Completed safely ✅");
}

// --------------------------------------------------
// SIGNATURE VERIFICATION
// --------------------------------------------------
/**
 * Verify Paystack webhook signature
 *
 * SECURITY:
 * - Prevents forged webhook calls
 * - Uses HMAC SHA512 with PAYSTACK_SECRET_KEY
 *
 * NOTE:
 * - req.body MUST be raw Buffer (express.raw)
 */
function verifyPaystackSignature(req) {
  if (!PAYSTACK_SECRET) {
    debug(
      "WEBHOOK SERVICE: PAYSTACK_SECRET_KEY missing ❌"
    );
    throw new Error("Invalid Paystack signature");
  }

  const signature = req.headers["x-paystack-signature"];

  if (!signature) {
    debug(
      "WEBHOOK SERVICE: Missing Paystack signature header ❌"
    );
    throw new Error("Invalid Paystack signature");
  }

  const hash = crypto
    .createHmac("sha512", PAYSTACK_SECRET)
    .update(req.body)
    .digest("hex");

  if (hash !== signature) {
    debug("WEBHOOK SERVICE: Signature mismatch ❌");
    throw new Error("Invalid Paystack signature");
  }
}

module.exports = {
  handlePaystackWebhook,
};
