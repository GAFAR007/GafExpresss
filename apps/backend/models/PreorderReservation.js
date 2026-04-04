/**
 * apps/backend/models/PreorderReservation.js
 * ------------------------------------------
 * WHAT:
 * - Stores temporary pre-order reservation holds for production plans.
 *
 * WHY:
 * - Prevents overselling by recording each hold against capped pre-order stock.
 * - Preserves auditability for reservation lifecycle transitions.
 *
 * HOW:
 * - Links reservation to business, plan, and requesting user.
 * - Keeps expired rows for reconciliation + audit history.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading PreorderReservation model...");

const PREORDER_RESERVATION_STATUSES = [
  "reserved",
  "confirmed",
  "released",
  "expired",
];
const DEFAULT_RESERVATION_TTL_MS =
  15 * 60 * 1000;

const preorderReservationSchema = new mongoose.Schema(
  {
    // WHY: Business scope prevents cross-tenant reservation leaks.
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    // WHY: Reservation must always tie to one production plan.
    planId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ProductionPlan",
      required: true,
      index: true,
    },
    // WHY: User link supports customer-specific reservation ownership.
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    // WHY: Quantity must be a positive reservation request.
    quantity: {
      type: Number,
      required: true,
      validate: {
        validator(value) {
          return Number.isFinite(value) && value > 0;
        },
        message:
          "Reservation quantity must be greater than zero",
      },
    },
    // WHY: Status tracks where each hold is in fulfillment lifecycle.
    status: {
      type: String,
      enum: PREORDER_RESERVATION_STATUSES,
      default: "reserved",
      required: true,
      index: true,
    },
    // WHY: Reservations should auto-expire if not confirmed in time.
    expiresAt: {
      type: Date,
      required: true,
      default() {
        return new Date(
          Date.now() +
            DEFAULT_RESERVATION_TTL_MS,
        );
      },
    },
    // WHY: Reconciler stamps this moment so release actions are auditable.
    expiredAt: {
      type: Date,
      default: null,
      index: true,
    },
  },
  {
    timestamps: true,
  },
);

const PreorderReservation = mongoose.model(
  "PreorderReservation",
  preorderReservationSchema,
);

module.exports = PreorderReservation;
module.exports.PREORDER_RESERVATION_STATUSES =
  PREORDER_RESERVATION_STATUSES;
module.exports.DEFAULT_RESERVATION_TTL_MS =
  DEFAULT_RESERVATION_TTL_MS;
