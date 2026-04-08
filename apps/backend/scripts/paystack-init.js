/**
 * scripts/paystack-init.js
 * ------------------------
 * WHAT:
 * - Standalone script that calls Paystack "Initialize Transaction"
 *
 * IMPORTANT:
 * - This script runs OUTSIDE Express
 * - So it MUST load .env by itself
 *
 * WHY:
 * - When you run: node scripts/paystack-init.js
 *   it does NOT automatically read .env unless we load dotenv here.
 */

const path = require("path");
require("dotenv").config({
  path: path.join(__dirname, "../.env"),
});

console.log("ENV check:", {
  hasPaystackKey: !!process.env.PAYSTACK_SECRET_KEY,
  keyPrefix: process.env.PAYSTACK_SECRET_KEY?.slice(0, 8),
});

/**
 * scripts/paystack-init.js
 * ------------------------
 * WHAT:
 * - Creates a Paystack test transaction (returns authorization_url)
 *
 * WHY:
 * - You have no frontend yet
 * - This gives you a real Paystack checkout page to pay with test mode
 *
 * HOW:
 * - Uses PAYSTACK_SECRET_KEY from .env
 * - Passes metadata.orderId so webhook can map payment to an order
 */

const debug = require("../utils/debug");

// Node 18+ has fetch built-in
async function main() {
  const secret = process.env.PAYSTACK_SECRET_KEY;

  if (!secret) {
    console.error("❌ Missing PAYSTACK_SECRET_KEY in env");
    process.exit(1);
  }

  // ✅ Change these each run if you want
  const email =
    process.env.TEST_CUSTOMER_EMAIL || "test@example.com";
  const amountKobo = 50000; // NGN 500.00 if kobo-based (Paystack uses kobo)
  const orderId =
    process.argv[2] || "FAKE_ORDER_ID_FOR_NOW";

  debug("PAYSTACK INIT: starting", {
    email,
    amountKobo,
    orderId,
  });

  const payload = {
    email,
    amount: amountKobo,
    currency: "NGN",
    metadata: { orderId }, // ✅ IMPORTANT: webhook uses this
  };

  const resp = await fetch(
    "https://api.paystack.co/transaction/initialize",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    }
  );

  const data = await resp.json();

  if (!resp.ok) {
    console.error("❌ Paystack init failed:", data);
    process.exit(1);
  }

  console.log("\n✅ Paystack init ok!");
  console.log(
    "AUTH URL (open in browser):",
    data?.data?.authorization_url
  );
  console.log("REFERENCE:", data?.data?.reference);
  console.log("");
}

main().catch((err) => {
  console.error("❌ Script crashed:", err.message);
  process.exit(1);
});
