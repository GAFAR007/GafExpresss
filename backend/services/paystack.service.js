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
  const reservationId =
    order.reservationId ?
      order.reservationId.toString()
    : "";

  const payload = {
    email: user.email,
    amount,
    currency: "NGN",
    metadata: {
      orderId,
      ...(reservationId ?
        { reservationId }
      : {}),
    },
  };

  // WHY: Paystack expects callback_url when provided.
  if (callbackUrl) {
    payload.callback_url = callbackUrl;
  }

  debug("PAYSTACK SERVICE: Calling Paystack initialize", {
    orderId,
    amount,
    hasReservationId:
      Boolean(reservationId),
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

/**
 * Initialize a Paystack transaction for tenant rent.
 *
 * @param {string} reference
 * @param {string} email
 * @param {number} amountMinor
 * @param {object} metadata
 * @param {string | undefined} callbackUrl
 * @returns {Promise<{ authorizationUrl: string, reference: string, accessCode: string }>}
 */
async function initTenantPaystackTransaction({
  reference,
  email,
  amountMinor,
  metadata,
  callbackUrl,
}) {
  debug("PAYSTACK SERVICE: initTenantPaystackTransaction - entry");

  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret) {
    debug("PAYSTACK SERVICE: Missing PAYSTACK_SECRET_KEY");
    throw new Error("Server misconfigured (missing PAYSTACK_SECRET_KEY)");
  }

  if (!reference) {
    debug("PAYSTACK SERVICE: Missing tenant payment reference");
    throw new Error("Missing tenant payment reference");
  }
  if (!email) {
    debug("PAYSTACK SERVICE: Missing tenant email");
    throw new Error("Missing tenant email");
  }
  if (!Number.isInteger(amountMinor) || amountMinor <= 0) {
    debug("PAYSTACK SERVICE: Invalid tenant rent amount", {
      amountMinor,
    });
    throw new Error("Invalid tenant rent amount");
  }

  const payload = {
    email,
    amount: amountMinor,
    currency: "NGN",
    reference,
    metadata,
  };
  if (callbackUrl) {
    payload.callback_url = callbackUrl;
  }

  debug("PAYSTACK SERVICE: Calling Paystack initialize (tenant)", {
    referenceSuffix: reference.slice(-6),
    amountMinor,
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
    debug("PAYSTACK SERVICE: Tenant init failed", {
      status: resp.status,
      providerCode: data?.code || null,
      providerMessage: data?.message || null,
      classification:
        resp.status === 401 || resp.status === 403
          ? "AUTHENTICATION_ERROR"
          : resp.status === 429
          ? "RATE_LIMITED"
          : resp.status >= 500
          ? "PROVIDER_OUTAGE"
          : "PROVIDER_REJECTED_FORMAT",
      resolutionHint:
        resp.status === 401 || resp.status === 403
          ? "Check PAYSTACK_SECRET_KEY and permissions"
          : resp.status === 429
          ? "Slow down requests and retry later"
          : "Review payload and Paystack response",
    });
    throw new Error("Paystack tenant init failed");
  }

  const authorizationUrl = data?.data?.authorization_url || "";
  const accessCode = data?.data?.access_code || "";

  if (!authorizationUrl) {
    debug("PAYSTACK SERVICE: Missing tenant authorization_url");
    throw new Error("Paystack tenant init missing authorization_url");
  }

  debug("PAYSTACK SERVICE: Tenant init success", {
    referenceSuffix: reference.slice(-6),
  });

  return {
    authorizationUrl,
    reference,
    accessCode,
  };
}

/**
 * Verify a Paystack transaction by reference.
 *
 * @param {string} reference
 * @returns {Promise<object>}
 */
async function verifyPaystackTransaction({ reference }) {
  debug("PAYSTACK SERVICE: verifyPaystackTransaction - entry", {
    referenceSuffix: reference ? reference.slice(-6) : null,
  });

  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret) {
    debug("PAYSTACK SERVICE: Missing PAYSTACK_SECRET_KEY");
    throw new Error("Server misconfigured (missing PAYSTACK_SECRET_KEY)");
  }
  if (!reference) {
    debug("PAYSTACK SERVICE: Missing Paystack reference");
    throw new Error("Reference is required");
  }

  const resp = await fetch(
    `https://api.paystack.co/transaction/verify/${reference}`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
    }
  );

  const data = await resp.json();

  if (!resp.ok || !data?.status) {
    debug("PAYSTACK SERVICE: Verify failed", {
      status: resp.status,
      providerCode: data?.code || null,
      providerMessage: data?.message || null,
      classification:
        resp.status === 401 || resp.status === 403
          ? "AUTHENTICATION_ERROR"
          : resp.status === 429
          ? "RATE_LIMITED"
          : resp.status >= 500
          ? "PROVIDER_OUTAGE"
          : "PROVIDER_REJECTED_FORMAT",
      resolutionHint:
        resp.status === 401 || resp.status === 403
          ? "Check PAYSTACK_SECRET_KEY and permissions"
          : resp.status === 429
          ? "Retry later after cooldown"
          : "Confirm reference and Paystack response",
    });
    throw new Error("Paystack verify failed");
  }

  debug("PAYSTACK SERVICE: Verify success", {
    referenceSuffix: reference.slice(-6),
    status: data?.data?.status,
  });

  return data?.data || {};
}

module.exports = {
  initPaystackTransaction,
  initTenantPaystackTransaction,
  verifyPaystackTransaction,
};
