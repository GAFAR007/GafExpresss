/**
 * models/PurchaseRequest.js
 * -------------------------
 * WHAT:
 * - Stores temporary buyer-to-seller purchase requests used before Paystack checkout.
 *
 * WHY:
 * - Keeps manual invoice, proof, and approval workflow separate from long-term payments.
 * - Links the request directly to chat until it is converted into a real paid order.
 *
 * HOW:
 * - Snapshots items + delivery address at request time.
 * - Tracks invoice, proof, and linked order lifecycle in one document.
 */

const mongoose = require("mongoose");
const debug = require("../utils/debug");

debug("Loading PurchaseRequest model...");

const PURCHASE_REQUEST_STATUSES = [
  "requested",
  "quoted",
  "proof_submitted",
  "approved",
  "rejected",
  "cancelled",
];

const purchaseRequestItemSchema = new mongoose.Schema(
  {
    product: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Product",
      required: true,
    },
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    imageUrl: {
      type: String,
      default: "",
      trim: true,
    },
    quantity: {
      type: Number,
      required: true,
      min: 1,
    },
    unitPrice: {
      type: Number,
      required: true,
      min: 0,
    },
    subtotal: {
      type: Number,
      required: true,
      min: 0,
    },
  },
  {
    _id: false,
  },
);

const deliveryAddressSchema = new mongoose.Schema(
  {
    source: {
      type: String,
      enum: ["home", "company", "custom"],
      required: true,
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

const purchaseRequestCustomerCareSchema = new mongoose.Schema(
  {
    assistantName: {
      type: String,
      default: "Amara",
      trim: true,
    },
    isEnabled: {
      type: Boolean,
      default: true,
    },
    currentAttendantUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    currentAttendantName: {
      type: String,
      default: "",
      trim: true,
    },
    currentAttendantRole: {
      type: String,
      default: "",
      trim: true,
    },
    currentAttendantStaffRole: {
      type: String,
      default: "",
      trim: true,
    },
    lastUpdatedAt: {
      type: Date,
      default: null,
    },
  },
  {
    _id: false,
  },
);

const purchaseRequestSchema = new mongoose.Schema(
  {
    customerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    businessId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ChatConversation",
      required: true,
      index: true,
    },
    reservationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "PreorderReservation",
      default: null,
      index: true,
    },
    linkedOrderId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Order",
      default: null,
      index: true,
    },
    status: {
      type: String,
      enum: PURCHASE_REQUEST_STATUSES,
      default: "requested",
      index: true,
    },
    currencyCode: {
      type: String,
      default: "NGN",
      trim: true,
    },
    items: {
      type: [purchaseRequestItemSchema],
      default: [],
    },
    subtotalAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    charges: {
      baseLogisticsFee: {
        type: Number,
        default: 0,
        min: 0,
      },
      sellerMarkupPercent: {
        type: Number,
        default: 0,
        min: 0,
      },
      sellerMarkupAmount: {
        type: Number,
        default: 0,
        min: 0,
      },
      logisticsFee: {
        type: Number,
        default: 0,
        min: 0,
      },
      serviceCharge: {
        type: Number,
        default: 0,
        min: 0,
      },
    },
    deliveryAddress: {
      type: deliveryAddressSchema,
      required: true,
    },
    invoice: {
      invoiceNumber: {
        type: String,
        default: "",
        trim: true,
      },
      totalAmount: {
        type: Number,
        default: 0,
        min: 0,
      },
      paymentInstructions: {
        type: String,
        default: "",
        trim: true,
      },
      paymentAccount: {
        accountId: {
          type: mongoose.Schema.Types.ObjectId,
          default: null,
        },
        bankName: {
          type: String,
          default: "",
          trim: true,
        },
        accountName: {
          type: String,
          default: "",
          trim: true,
        },
        accountNumber: {
          type: String,
          default: "",
          trim: true,
        },
        transferInstruction: {
          type: String,
          default: "",
          trim: true,
        },
      },
      note: {
        type: String,
        default: "",
        trim: true,
      },
      estimatedDeliveryDate: {
        type: Date,
        default: null,
      },
      sentAt: {
        type: Date,
        default: null,
      },
      sentByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        default: null,
      },
      sentByRole: {
        type: String,
        default: "",
        trim: true,
      },
    },
    proof: {
      attachmentId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "ChatAttachment",
        default: null,
      },
      url: {
        type: String,
        default: "",
        trim: true,
      },
      filename: {
        type: String,
        default: "",
        trim: true,
      },
      mimeType: {
        type: String,
        default: "",
        trim: true,
      },
      sizeBytes: {
        type: Number,
        default: 0,
        min: 0,
      },
      note: {
        type: String,
        default: "",
        trim: true,
      },
      submittedAt: {
        type: Date,
        default: null,
      },
      submittedByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        default: null,
      },
      reviewedAt: {
        type: Date,
        default: null,
      },
      reviewedByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
        default: null,
      },
      reviewedByRole: {
        type: String,
        default: "",
        trim: true,
      },
      reviewDecision: {
        type: String,
        default: "",
        trim: true,
      },
      reviewNote: {
        type: String,
        default: "",
        trim: true,
      },
    },
    customerCare: {
      type: purchaseRequestCustomerCareSchema,
      default: () => ({
        assistantName: "Amara",
        isEnabled: true,
      }),
    },
    cancelledAt: {
      type: Date,
      default: null,
    },
    cancelledByUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
    },
    cancelledByRole: {
      type: String,
      default: "",
      trim: true,
    },
    cancelReason: {
      type: String,
      default: "",
      trim: true,
    },
  },
  {
    timestamps: true,
  },
);

purchaseRequestSchema.index({
  customerId: 1,
  businessId: 1,
  status: 1,
  createdAt: -1,
});
purchaseRequestSchema.index({
  conversationId: 1,
  createdAt: -1,
});

const PurchaseRequest = mongoose.model(
  "PurchaseRequest",
  purchaseRequestSchema,
);

module.exports = {
  PurchaseRequest,
  PURCHASE_REQUEST_STATUSES,
};
