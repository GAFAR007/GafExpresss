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

// WHY: Rent payments share the same period values as estate units.
const RENT_PERIODS = [
  "monthly",
  "quarterly",
  "yearly",
];

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

    // WHY: Tenant rent payments link back to the tenant application for audits.
    tenantApplication: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "BusinessTenantApplication",
      default: null,
    },

    // WHY: Business context is needed for tenant rent + staff audit trails.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },

    // WHY: Distinguish order vs tenant rent flows in analytics/filters.
    purpose: {
      type: String,
      trim: true,
      default: null,
    },
    // WHY: Tenant rent coverage period (used only for tenant_rent payments).
    coversFrom: {
      type: Date,
      default: null,
    },
    coversTo: {
      type: Date,
      default: null,
    },
    rentPeriod: {
      type: String,
      enum: RENT_PERIODS,
      default: null,
    },
    periodCount: {
      type: Number,
      min: 1,
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
  { timestamps: true },
);

// ✅ CRITICAL: This is what enforces idempotency at DB level
paymentSchema.index(
  { provider: 1, reference: 1 },
  { unique: true },
);

const Payment = mongoose.model(
  "Payment",
  paymentSchema,
);

module.exports = Payment;
