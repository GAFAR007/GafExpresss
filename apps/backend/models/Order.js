/**
 * models/Order.js
 * ---------------
 * WHAT:
 * - Defines the Order schema for e-commerce orders
 *
 * WHY:
 * - Tracks user purchases, items, total, and status
 * - Enables order history and admin management
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading Order model...");

// ✅ Delivery address snapshot stored on the order
// WHY: Orders must retain historical delivery data even if profile changes.
const deliveryAddressSchema = new mongoose.Schema(
  {
    source: {
      type: String,
      enum: ["home", "company", "custom"],
      required: [true, "Delivery address source is required"],
    },
    houseNumber: { type: String, trim: true },
    street: { type: String, trim: true },
    city: { type: String, trim: true },
    state: { type: String, trim: true },
    postalCode: { type: String, trim: true },
    lga: { type: String, trim: true },
    country: { type: String, trim: true, default: "NG" },
    landmark: { type: String, trim: true },
    isVerified: { type: Boolean, default: false },
    verifiedAt: { type: Date, default: null },
    verificationSource: { type: String, trim: true, default: null },
    formattedAddress: { type: String, trim: true, default: null },
    placeId: { type: String, trim: true, default: null },
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },
  },
  {
    _id: false,
  },
);

const orderFulfillmentSchema = new mongoose.Schema(
  {
    carrierName: {
      type: String,
      default: '',
      trim: true,
    },
    trackingReference: {
      type: String,
      default: '',
      trim: true,
    },
    dispatchNote: {
      type: String,
      default: '',
      trim: true,
    },
    estimatedDeliveryDate: {
      type: Date,
      default: null,
    },
    shippedAt: {
      type: Date,
      default: null,
    },
    deliveredAt: {
      type: Date,
      default: null,
    },
  },
  {
    _id: false,
  },
);

const orderSchema = new mongoose.Schema(
  {
    // ✅ User who placed the order
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "User is required for order"],
    },
    // WHY: Optional reservation linkage keeps preorder payment confirmation deterministic.
    reservationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "PreorderReservation",
      default: null,
      index: true,
    },

    // ✅ Order items (embedded array for simplicity)
    items: [
      {
        product: {
          type: mongoose.Schema.Types.ObjectId,
          ref: "Product",
          required: true,
        },
        // ✅ Business scope for each line item
        // WHY: Allows business owners to query orders that contain their products.
        businessId: {
          type: mongoose.Schema.Types.ObjectId,
          ref: "User",
          default: null,
        },
        quantity: {
          type: Number,
          required: true,
          min: [1, "Quantity must be at least 1"],
        },
        price: {
          type: Number, // Snapshot of product price at order time
          required: true,
          min: [0, "Price cannot be negative"],
        },
      },
    ],

    // ✅ Total price (calculated on creation)
    totalPrice: {
      type: Number,
      required: true,
      min: [0, "Total price cannot be negative"],
    },
    // WHY: Manual-direct requests can add logistics + service charges.
    charges: {
      logisticsFee: {
        type: Number,
        default: 0,
        min: [0, "Logistics fee cannot be negative"],
      },
      serviceCharge: {
        type: Number,
        default: 0,
        min: [0, "Service charge cannot be negative"],
      },
    },
    fulfillment: {
      type: orderFulfillmentSchema,
      default: () => ({}),
    },
    // ✅ Business scopes for quick queries (one order can contain multiple businesses)
    // WHY: Lets business dashboards filter orders without heavy item scans.
    businessIds: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: "User",
      default: [],
      index: true,
    },

    // ✅ Delivery address snapshot
    deliveryAddress: {
      type: deliveryAddressSchema,
      required: [true, "Delivery address is required"],
    },

    // ✅ Order status workflow
    status: {
      type: String,
      enum: ["pending", "paid", "shipped", "delivered", "cancelled"],
      default: "pending",
    },
    paymentSource: {
      type: String,
      enum: ["paystack", "manual_direct"],
      default: "paystack",
    },
    // ✅ Status history for audit trail (who changed what and when)
    statusHistory: [
      {
        status: { type: String, trim: true },
        changedAt: { type: Date, default: Date.now },
        changedBy: {
          type: mongoose.Schema.Types.ObjectId,
          ref: "User",
        },
        changedByRole: { type: String, trim: true },
        note: { type: String, trim: true },
      },
    ],

    // ✅ Soft delete (consistent with other models)
    deletedAt: {
      type: Date,
      default: null,
    },
    deletedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
  },
  {
    timestamps: true, // createdAt, updatedAt
  },
);

// Indexes for faster queries
orderSchema.index({ user: 1 });
orderSchema.index({ status: 1 });
orderSchema.index({ createdAt: -1 });
// WHY: Business dashboards filter orders by business scope.
orderSchema.index({ businessIds: 1, createdAt: -1 });

const Order = mongoose.model("Order", orderSchema);
// ✅ FULL-TEXT SEARCH INDEX
// Enables ?q= search on order status
orderSchema.index({
  status: "text",
});
module.exports = Order;
