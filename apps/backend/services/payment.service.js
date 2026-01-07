/**
 * services/payment.service.js
 * ---------------------------
 * WHAT:
 * - Handles payment provider events (Paystack) safely
 *
 * WHY:
 * - Central place for payment truth
 * - Enforces idempotency (no double processing)
 * - Later: used by payment intents / verification endpoints
 *
 * IMPORTANT SAFETY RULES:
 * - Webhook may be retried multiple times
 * - We must be able to receive the same event 10x and still be safe
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

const Payment = require("../models/Payment");
const Order = require("../models/Order");

const {
  assertTransition,
} = require("../utils/orderStatus");
const { adjustOrderStock } = require("../utils/stock");

/**
 * Extract common Paystack fields safely
 */
function extractPaystackInfo(event) {
  const data = event?.data || {};

  return {
    reference: data.reference,
    providerTransactionId: data.id ? String(data.id) : null,
    amount: data.amount || 0,
    currency: data.currency || "NGN",
    // recommended: you pass orderId in metadata when initiating payment
    orderId:
      data?.metadata?.orderId ||
      data?.metadata?.order_id ||
      null,
  };
}

/**
 * Process Paystack webhook event (idempotent + safe)
 *
 * RULE:
 * - Never throw uncaught errors to webhook route
 * - Route already acknowledges 200 for non-signature errors
 */
async function processPaystackEvent(event) {
  debug("PAYMENT SERVICE: processPaystackEvent - entry", {
    event: event?.event,
  });

  const {
    reference,
    providerTransactionId,
    amount,
    currency,
    orderId,
  } = extractPaystackInfo(event);

  if (!reference) {
    debug(
      "PAYMENT SERVICE: Missing reference ❌ - ignoring safely"
    );
    return { ok: false, reason: "Missing reference" };
  }

  // Map event type -> status
  const eventType = event.event;
  const isSuccess = eventType === "charge.success";
  const isFailed = eventType === "charge.failed";

  const status = isSuccess
    ? "success"
    : isFailed
    ? "failed"
    : "pending";

  debug("PAYMENT SERVICE: Parsed Paystack payload", {
    reference,
    providerTransactionId,
    status,
    orderId,
  });

  // ✅ Transaction: payment save + (optional) order transition + stock effect
  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    // 1) Upsert payment record (idempotency)
    // If it already exists, we get the existing doc back
    let payment = await Payment.findOne({
      provider: "paystack",
      reference,
    }).session(session);

    if (!payment) {
      debug("PAYMENT SERVICE: Creating new Payment record");

      payment = await Payment.create(
        [
          {
            provider: "paystack",
            reference,
            providerTransactionId,
            event: eventType,
            status,
            amount,
            currency,
            rawEvent: event,
          },
        ],
        { session }
      );

      // create() with array returns array
      payment = payment[0];
    } else {
      debug(
        "PAYMENT SERVICE: Payment already exists (idempotency hit) ✅",
        {
          processedAt: payment.processedAt,
          existingStatus: payment.status,
        }
      );

      // Update rawEvent/status if you want latest info (safe)
      payment.event = eventType;
      payment.status = status;
      payment.providerTransactionId =
        providerTransactionId ||
        payment.providerTransactionId;
      payment.rawEvent = event;

      await payment.save({ session });

      // If already processed, STOP here (critical)
      if (payment.processedAt) {
        await session.commitTransaction();
        return { ok: true, idempotent: true };
      }
    }

    // 2) Only apply business effects for success
    if (!isSuccess) {
      debug(
        "PAYMENT SERVICE: Not a success event, no order updates"
      );
      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return { ok: true, applied: false, status };
    }

    // 3) If no orderId, we cannot safely mark anything paid
    if (!orderId) {
      debug(
        "PAYMENT SERVICE: Missing orderId in metadata - cannot apply payment to order"
      );
      // still mark processed to avoid retries spamming your logs
      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        reason: "Missing orderId metadata",
      };
    }

    // 4) Load order
    const order = await Order.findById(orderId).session(
      session
    );

    if (!order) {
      debug(
        "PAYMENT SERVICE: Order not found - cannot apply payment",
        { orderId }
      );

      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        reason: "Order not found",
      };
    }

    // Link payment -> order/user
    payment.order = order._id;
    payment.user = order.user;

    debug("PAYMENT SERVICE: Order loaded", {
      orderId: order._id,
      currentStatus: order.status,
    });

    // 5) If order already paid or beyond, just mark processed
    // (prevents double stock decrease)
    if (
      ["paid", "shipped", "delivered"].includes(
        order.status
      )
    ) {
      debug(
        "PAYMENT SERVICE: Order already paid/beyond - marking payment processed only ✅"
      );

      payment.processedAt = new Date();
      await payment.save({ session });

      await session.commitTransaction();
      return {
        ok: true,
        applied: false,
        reason: "Order already paid/beyond",
      };
    }

    // 6) Enforce transition + apply stock change (pending -> paid)
    assertTransition(order.status, "paid");

    // Stock safety: decrease only on pending -> paid
    await adjustOrderStock(order, "decrease", session);

    order.status = "paid";
    await order.save({ session });

    debug(
      "PAYMENT SERVICE: Order marked paid + stock decreased ✅",
      {
        orderId: order._id,
      }
    );

    // 7) Mark payment as processed (THIS is the idempotency "done" flag)
    payment.processedAt = new Date();
    await payment.save({ session });

    await session.commitTransaction();

    return { ok: true, applied: true };
  } catch (err) {
    await session.abortTransaction();

    debug(
      "PAYMENT SERVICE: processPaystackEvent failed - rollback ✅",
      {
        message: err.message,
        stack: err.stack,
        eventType: event?.event,
        reference: event?.data?.reference,
        orderId: event?.data?.metadata?.orderId,
      }
    );

    throw err;
  } finally {
    session.endSession();
  }
}

module.exports = {
  processPaystackEvent,
};
