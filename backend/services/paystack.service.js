/**
 * services/paystack.service.js
 * ----------------------------
 * WHAT:
 * - Paystack API integration (transaction init).
 *
 * WHY:
 * - Keeps Paystack HTTP logic out of controllers.
 * - Centralizes validation + security checks.
 *
 * HOW:
 * - Validates user + order ownership.
 * - Builds Paystack payload from order total.
 * - Calls Paystack initialize endpoint and returns auth_url.
 */

const debug = require("../utils/debug");
const Order = require("../models/Order");
const User = require("../models/User");

/**
 * Initialize a Paystack transaction for a specific order.
 *
 * @param {string} orderId
 * @param {string} userId
 * @param {string | undefined} callbackUrl
 * @returns {Promise<{ authorizationUrl: string, reference: string, accessCode: string }>}
 */
async function initPaystackTransaction({
  orderId,
  userId,
  callbackUrl,
}) {
  debug("PAYSTACK SERVICE: initPaystackTransaction - entry");

  // WHY: Ensure server has the secret before calling Paystack.
  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret) {
    debug("PAYSTACK SERVICE: Missing PAYSTACK_SECRET_KEY");
    throw new Error("Server misconfigured (missing PAYSTACK_SECRET_KEY)");
  }

  // WHY: Validate required inputs early for clean errors.
  if (!orderId) {
    debug("PAYSTACK SERVICE: Missing orderId");
    throw new Error("Missing orderId");
  }
  if (!userId) {
    debug("PAYSTACK SERVICE: Missing userId");
    throw new Error("Missing userId");
  }

  // WHY: Ensure user exists and use a trusted email.
  const user = await User.findById(userId).lean();
  if (!user) {
    debug("PAYSTACK SERVICE: User not found");
    throw new Error("User not found");
  }

  // WHY: Ensure the order belongs to the logged-in user.
  const order = await Order.findById(orderId).lean();
  if (!order) {
    debug("PAYSTACK SERVICE: Order not found", orderId);
    throw new Error("Order not found");
  }
  if (order.user.toString() !== userId) {
    debug("PAYSTACK SERVICE: Order ownership mismatch", {
      orderId,
      userId,
    });
    throw new Error("Order does not belong to user");
  }

  // WHY: Only allow payment for pending orders.
  if (order.status !== "pending") {
    debug("PAYSTACK SERVICE: Order not pending", {
      orderId,
      status: order.status,
    });
    throw new Error("Order is not payable");
  }

  // WHY: Compute amount from order total (ignore client values).
  const amount = order.totalPrice;
  if (!amount || amount <= 0) {
    debug("PAYSTACK SERVICE: Invalid order amount", { orderId, amount });
    throw new Error("Invalid order amount");
  }

  const payload = {
    email: user.email,
    amount,
    currency: "NGN",
    metadata: { orderId },
  };

  // WHY: Paystack expects callback_url when provided.
  if (callbackUrl) {
    payload.callback_url = callbackUrl;
  }

  debug("PAYSTACK SERVICE: Calling Paystack initialize", {
    orderId,
    amount,
  });

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

  if (!resp.ok || !data?.status) {
    debug("PAYSTACK SERVICE: Init failed", {
      status: resp.status,
      message: data?.message,
    });
    throw new Error("Paystack init failed");
  }

  const authorizationUrl = data?.data?.authorization_url || "";
  const reference = data?.data?.reference || "";
  const accessCode = data?.data?.access_code || "";

  if (!authorizationUrl) {
    debug("PAYSTACK SERVICE: Missing authorization_url");
    throw new Error("Paystack init missing authorization_url");
  }

  debug("PAYSTACK SERVICE: Init success", { reference });

  return {
    authorizationUrl,
    reference,
    accessCode,
  };
}

module.exports = {
  initPaystackTransaction,
};
