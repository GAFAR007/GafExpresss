/**
 * models/Payment.js
 * -----------------
 * WHAT:
 * - Stores payment records from providers (Paystack)
 *
 * WHY:
 * - Enables idempotency (no double-processing)
 * - Keeps a full audit trail of payment attempts
 *
 * HOW:
 * - Unique index prevents duplicate reference processing
 * - processedAt marks "we have already applied this payment to an order"
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading Payment model...");

const paymentSchema = new mongoose.Schema(
  {
    provider: {
      type: String,
      enum: ["paystack"],
      required: true,
    },

    // Paystack reference (idempotency key)
    reference: {
      type: String,
      required: true,
      trim: true,
    },

    // Paystack transaction id (if available)
    providerTransactionId: {
      type: String,
      default: null,
    },

    // charge.success / charge.failed / etc
    event: {
      type: String,
      required: true,
    },

    status: {
      type: String,
      enum: ["success", "failed", "pending"],
      default: "pending",
    },

    amount: {
      type: Number,
      default: 0,
    },

    currency: {
      type: String,
      default: "NGN",
    },

    // Optional linkage (recommended)
    order: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Order",
      default: null,
    },

    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },

    // When we have fully applied effects (mark order paid, stock adjusted, etc.)
    processedAt: {
      type: Date,
      default: null,
    },

    // Store raw event safely for debugging/audit
    rawEvent: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
  },
  { timestamps: true }
);

// ✅ CRITICAL: This is what enforces idempotency at DB level
paymentSchema.index(
  { provider: 1, reference: 1 },
  { unique: true }
);

const Payment = mongoose.model("Payment", paymentSchema);

module.exports = Payment;
