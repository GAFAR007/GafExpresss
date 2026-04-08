/**
 * apps/backend/services/purchase_request.service.js
 * -------------------------------------------------
 * WHAT:
 * - Business logic for temporary buyer-to-seller purchase requests.
 *
 * WHY:
 * - Keeps manual invoice + proof review flow isolated from Paystack.
 * - Converts approved requests into normal paid orders without changing webhook flow.
 *
 * HOW:
 * - Validates items and delivery address.
 * - Creates business-scoped chat conversations and structured system messages.
 * - Lets sellers quote requests and approve or reject payment proof.
 */

const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");
const Order = require("../models/Order");
const Product = require("../models/Product");
const ProductionPlan = require("../models/ProductionPlan");
const PreorderReservation = require("../models/PreorderReservation");
const ChatAttachment = require("../models/ChatAttachment");
const User = require("../models/User");
const {
  PurchaseRequest,
  PURCHASE_REQUEST_STATUSES,
} = require("../models/PurchaseRequest");
const chatService = require("./chat.service");
const {
  verifyAddressPayload,
} = require("./address_verification.service");
const {
  resolveBusinessContext,
  resolveStaffProfile,
} = require("./business_context.service");
const {
  createAiChatCompletion,
} = require("./ai.service");
const {
  adjustOrderStock,
} = require("../utils/stock");
const {
  writeAuditLog,
} = require("../utils/audit");
const {
  writeAnalyticsEvent,
} = require("../utils/analytics");
const {
  CHAT_CONVERSATION_TYPES,
  CHAT_MESSAGE_TYPES,
} = require("../utils/chat_constants");
const {
  normalizeBusinessPaymentAccountInput,
  shapeBusinessPaymentAccounts,
  businessPaymentAccountsEqual,
  formatBusinessPaymentInstructions,
} = require("../utils/business_payment_accounts");
const debug = require("../utils/debug");

const STATUS_REQUESTED =
  PURCHASE_REQUEST_STATUSES[0];
const STATUS_QUOTED =
  PURCHASE_REQUEST_STATUSES[1];
const STATUS_PROOF_SUBMITTED =
  PURCHASE_REQUEST_STATUSES[2];
const STATUS_APPROVED =
  PURCHASE_REQUEST_STATUSES[3];
const STATUS_REJECTED =
  PURCHASE_REQUEST_STATUSES[4];
const STATUS_CANCELLED =
  PURCHASE_REQUEST_STATUSES[5];

const PREORDER_STATUS_RESERVED = "reserved";
const PREORDER_STATUS_CONFIRMED = "confirmed";
const BUYER_ROLES = new Set([
  "customer",
  "tenant",
  "business_owner",
]);
const REQUEST_CHAT_STAFF_ROLES = new Set([
  "farm_manager",
  "estate_manager",
  "customer_care",
]);
const REQUEST_INVOICE_STAFF_ROLES = new Set([
  "farm_manager",
  "estate_manager",
  "customer_care",
]);
const REQUEST_PROOF_REVIEW_STAFF_ROLES = new Set([
  "farm_manager",
  "estate_manager",
  "customer_care",
]);
const DEFAULT_ASSISTANT_NAME = "Amara";
const CUSTOMER_CARE_PRESENTATION = "assistant";
const CUSTOMER_CARE_LABEL = "Customer care";
const MAX_PRODUCT_SUMMARY_ITEMS = 6;
const REQUEST_SERVICE_CHARGE_RATE = 0.05;
const REQUEST_SELLER_MARKUP_MIN_PERCENT = 5;
const REQUEST_SELLER_MARKUP_MAX_PERCENT = 20;

const REQUEST_EVENT_TYPES = {
  REQUEST_CREATED: "request_created",
  INVOICE_SENT: "invoice_sent",
  PROOF_UPLOADED: "proof_uploaded",
  PROOF_APPROVED: "proof_approved",
  PROOF_REJECTED: "proof_rejected",
  REQUEST_CANCELLED: "request_cancelled",
  CUSTOMER_CARE_INTRO: "customer_care_intro",
  CUSTOMER_CARE_REPLY: "customer_care_reply",
  SELLER_ATTENDING: "seller_attending",
  CUSTOMER_CARE_RESUMED: "customer_care_resumed",
};

function isBuyerRole(role) {
  return BUYER_ROLES.has(
    (role || "").toString().trim().toLowerCase(),
  );
}

function buildInvoiceNumber(requestId) {
  const now = new Date();
  const y = now.getFullYear().toString();
  const m = String(now.getMonth() + 1).padStart(
    2,
    "0",
  );
  const d = String(now.getDate()).padStart(
    2,
    "0",
  );
  const suffix =
    String(requestId || "")
      .slice(-6)
      .toUpperCase() || "REQ";
  return `INV-${y}${m}${d}-${suffix}`;
}

function formatMinorAmount(value) {
  return (Number(value || 0) / 100).toFixed(2);
}

function formatPercent(value) {
  const numeric = Number(value || 0);
  if (!Number.isFinite(numeric)) {
    return "0";
  }
  if (Number.isInteger(numeric)) {
    return numeric.toString();
  }
  return numeric.toFixed(2).replace(/\.?0+$/, "");
}

function formatAddress(address = {}) {
  return [
    address.houseNumber,
    address.street,
    address.city,
    address.state,
  ]
    .map((value) =>
      (value || "").toString().trim(),
    )
    .filter(Boolean)
    .join(", ");
}

function buildDisplayName(user = {}) {
  const nameParts = [
    user.firstName,
    user.middleName,
    user.lastName,
  ]
    .map((value) =>
      (value || "").toString().trim(),
    )
    .filter(Boolean);
  if (nameParts.length > 0) {
    return nameParts.join(" ");
  }

  return (
    user.name?.toString().trim() ||
    user.companyName?.toString().trim() ||
    user.email?.toString().trim() ||
    "Team member"
  );
}

function formatRoleLabel(role = "") {
  const normalized = role
    .toString()
    .trim()
    .replaceAll("_", " ");
  return normalized || "team";
}

function buildAllowedRoleMessage({
  actionLabel,
  staffRoles = [],
}) {
  const labels = [
    "business owner",
    ...staffRoles.map((role) =>
      formatRoleLabel(role),
    ),
  ];
  if (labels.length === 1) {
    return `Only ${labels[0]} can ${actionLabel}`;
  }
  if (labels.length === 2) {
    return `Only ${labels[0]} or ${labels[1]} can ${actionLabel}`;
  }
  return `Only ${labels.slice(0, -1).join(", ")}, or ${labels[labels.length - 1]} can ${actionLabel}`;
}

async function loadBusinessPaymentAccounts({
  businessId,
  session = null,
}) {
  if (!businessId) {
    return [];
  }

  let query = User.findById(businessId).select(
    "businessPaymentAccounts",
  );
  if (session) {
    query = query.session(session);
  }

  const business = await query;
  return shapeBusinessPaymentAccounts(
    business?.businessPaymentAccounts,
  );
}

function toRequestPlainObject(request) {
  if (!request) {
    return null;
  }
  if (typeof request.toObject === "function") {
    return request.toObject();
  }
  return { ...request };
}

async function presentPurchaseRequest(
  request,
  { session = null } = {},
) {
  const plain = toRequestPlainObject(request);
  if (!plain) {
    return null;
  }
  return {
    ...plain,
    availablePaymentAccounts:
      await loadBusinessPaymentAccounts({
        businessId:
          plain.businessId ||
          request?.businessId,
        session,
      }),
  };
}

async function upsertBusinessPaymentAccount({
  businessId,
  session,
  paymentAccount,
  savePaymentAccount = false,
}) {
  let savedAccountId = "";

  if (savePaymentAccount) {
    const business = await User.findById(
      businessId,
    )
      .select("businessPaymentAccounts")
      .session(session);

    if (!business) {
      throw new Error(
        "Business account not found for saved payment details",
      );
    }

    const existingAccounts =
      Array.isArray(
        business.businessPaymentAccounts,
      )
        ? business.businessPaymentAccounts
        : [];

    const requestedAccountId =
      (paymentAccount.accountId || "")
        .toString()
        .trim();
    let matchedAccount =
      requestedAccountId.length > 0
        ? existingAccounts.find(
            (entry) =>
              entry?._id?.toString() ===
              requestedAccountId,
          )
        : null;

    if (!matchedAccount) {
      matchedAccount = existingAccounts.find(
        (entry) =>
          businessPaymentAccountsEqual(
            entry,
            paymentAccount,
          ),
      );
    }

    if (matchedAccount) {
      matchedAccount.bankName =
        paymentAccount.bankName;
      matchedAccount.accountName =
        paymentAccount.accountName;
      matchedAccount.accountNumber =
        paymentAccount.accountNumber;
      matchedAccount.transferInstruction =
        paymentAccount.transferInstruction;
      matchedAccount.updatedAt = new Date();
      savedAccountId =
        matchedAccount._id?.toString() || "";
    } else {
      business.businessPaymentAccounts.push({
        bankName: paymentAccount.bankName,
        accountName:
          paymentAccount.accountName,
        accountNumber:
          paymentAccount.accountNumber,
        transferInstruction:
          paymentAccount.transferInstruction,
        isDefault:
          existingAccounts.length === 0,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      const inserted =
        business.businessPaymentAccounts[
          business.businessPaymentAccounts
            .length - 1
        ];
      savedAccountId =
        inserted?._id?.toString() || "";
    }

    await business.save({ session });
  }

  if (!savedAccountId) {
    const existingAccounts =
      await loadBusinessPaymentAccounts({
        businessId,
        session,
      });
    const matchedAccount =
      existingAccounts.find((entry) =>
        businessPaymentAccountsEqual(
          entry,
          paymentAccount,
        ),
      );
    savedAccountId =
      matchedAccount?.id || "";
  }

  return savedAccountId;
}

function resolveActorApprovalRole({
  actor,
  staffProfile,
}) {
  if (actor?.role === "staff") {
    return (staffProfile?.staffRole || "staff")
      .toString()
      .trim();
  }
  return (actor?.role || "").toString().trim();
}

function resolveAssistantName(request) {
  return (
    request?.customerCare?.assistantName
      ?.toString()
      .trim() || DEFAULT_ASSISTANT_NAME
  );
}

function buildCustomerCareSnapshot(request) {
  return {
    assistantName: resolveAssistantName(request),
    isEnabled:
      request?.customerCare?.isEnabled !== false,
    currentAttendantUserId:
      request?.customerCare?.currentAttendantUserId?.toString() ||
      "",
    currentAttendantName:
      request?.customerCare?.currentAttendantName
        ?.toString()
        .trim() || "",
    currentAttendantRole:
      request?.customerCare?.currentAttendantRole
        ?.toString()
        .trim() || "",
    currentAttendantStaffRole:
      request?.customerCare?.currentAttendantStaffRole
        ?.toString()
        .trim() || "",
    lastUpdatedAt:
      request?.customerCare?.lastUpdatedAt ||
      null,
  };
}

function buildCustomerCareEventData(
  request,
  extra = {},
) {
  return {
    ...buildRequestEventData(request),
    presentation: CUSTOMER_CARE_PRESENTATION,
    assistantLabel: CUSTOMER_CARE_LABEL,
    assistantName: resolveAssistantName(request),
    ...extra,
  };
}

function containsAny(text, tokens) {
  return tokens.some((token) =>
    text.includes(token),
  );
}

function isUnsafeAssistantReply(text) {
  return /\b(ai|chatbot|language model|virtual assistant|bot)\b/i.test(
    (text || "").toString(),
  );
}

function buildRequestStatusBrief({
  request,
  linkedOrder = null,
}) {
  switch ((request?.status || "").toString()) {
    case STATUS_REQUESTED:
      return "The request has been received and the team is reviewing the address, stock, and delivery cost.";
    case STATUS_QUOTED:
      return `The invoice is ready for NGN ${formatMinorAmount(request?.invoice?.totalAmount)} and payment details are already in this chat.`;
    case STATUS_PROOF_SUBMITTED:
      return "Payment proof has been uploaded and the team is reviewing it now.";
    case STATUS_APPROVED:
      return linkedOrder?.status
        ? `Payment has been approved and the linked order is currently ${linkedOrder.status}.`
        : "Payment has been approved and the request has already been converted into an order.";
    case STATUS_REJECTED:
      return "The last proof was rejected, so the buyer can clarify in chat or upload a new proof.";
    case STATUS_CANCELLED:
      return "This purchase request has been cancelled.";
    default:
      return "This request is still active in chat.";
  }
}

function buildProductListLabel(products = []) {
  if (
    !Array.isArray(products) ||
    products.length === 0
  ) {
    return "";
  }

  return products
    .slice(0, MAX_PRODUCT_SUMMARY_ITEMS)
    .map(
      (product) =>
        `${product.name} (${Number(product.stock || 0)} in stock, NGN ${formatMinorAmount(product.price || 0)})`,
    )
    .join("; ");
}

function buildCustomerCareFallback({
  request,
  summary,
  customerMessage,
  hasAttachments,
}) {
  const assistantName = summary.assistantName;
  const businessName = summary.businessName;
  const ownerName = summary.ownerName;
  const lower = (customerMessage || "")
    .toString()
    .trim()
    .toLowerCase();
  const requestedItems = (request.items || [])
    .map(
      (item) => `${item.quantity} x ${item.name}`,
    )
    .join(", ");
  const requestedPrice = request.invoice?.sentAt
    ? `NGN ${formatMinorAmount(request.invoice.totalAmount)}`
    : `NGN ${formatMinorAmount(request.subtotalAmount)}`;
  const deliveryAddress = formatAddress(
    request.deliveryAddress,
  );
  const productSummary = buildProductListLabel(
    summary.products,
  );
  const statusSummary = buildRequestStatusBrief({
    request,
    linkedOrder: summary.linkedOrder,
  });

  if (hasAttachments && !lower) {
    return `Thanks, I’ve added that to your request with ${businessName}. ${statusSummary}`;
  }

  if (
    !lower ||
    containsAny(lower, [
      "hello",
      "hi",
      "hey",
      "good morning",
      "good afternoon",
    ])
  ) {
    return `Hi, my name is ${assistantName} from ${businessName}. ${statusSummary} I can help with available items, invoice details, and the next steps here.`;
  }

  if (
    containsAny(lower, [
      "who are you",
      "your name",
      "owner",
      "business",
    ])
  ) {
    return `Hi, my name is ${assistantName} from ${businessName}. ${ownerName ? `${ownerName} manages this business.` : "I’m helping with this request while the team reviews it."} ${statusSummary}`;
  }

  if (
    containsAny(lower, [
      "what do you sell",
      "what do you have",
      "available",
      "stock",
      "inventory",
      "products",
      "goods",
    ])
  ) {
    if (!summary.products.length) {
      return `We do not have a fresh stock summary to share in chat yet, but I can keep the request moving while the team confirms availability. ${statusSummary}`;
    }
    return `${businessName} currently has ${summary.activeProductCount} active product${summary.activeProductCount === 1 ? "" : "s"} in the catalog. Some available items are ${productSummary}. ${requestedItems ? `For this request, you selected ${requestedItems}.` : ""}`;
  }

  if (
    containsAny(lower, [
      "price",
      "amount",
      "total",
      "cost",
      "invoice",
      "payment",
    ])
  ) {
    if (request.invoice?.sentAt) {
      return `The current invoice total for this request is ${requestedPrice}. The payment details are already pinned in this chat, and once proof is uploaded the team can review it here.`;
    }
    return `The current item subtotal for this request is ${requestedPrice}. Delivery and service charges are added after the team reviews the address and logistics.`;
  }

  if (
    containsAny(lower, [
      "status",
      "order",
      "request",
      "proof",
    ])
  ) {
    return statusSummary;
  }

  if (
    containsAny(lower, [
      "delivery",
      "address",
      "logistics",
      "where",
      "location",
    ])
  ) {
    return deliveryAddress
      ? `The delivery address on this request is ${deliveryAddress}. The team uses that address to confirm logistics and the final invoice.`
      : "The team still needs the delivery address confirmed before final logistics can be added.";
  }

  return `Thanks for the message. ${statusSummary} ${requestedItems ? `This request currently covers ${requestedItems}.` : ""}`;
}

function safeMinorAmount(value) {
  const numeric = Number.isFinite(value)
    ? value
    : Number(value);
  if (!Number.isFinite(numeric)) {
    throw new Error("Amount must be numeric");
  }
  const rounded = Math.round(numeric);
  if (rounded < 0) {
    throw new Error("Amount cannot be negative");
  }
  return rounded;
}

function safeSellerMarkupPercent(value) {
  if (
    value === undefined ||
    value === null ||
    value === ""
  ) {
    return 0;
  }

  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    throw new Error(
      "Seller markup percent must be numeric",
    );
  }
  if (numeric < 0) {
    throw new Error(
      "Seller markup percent cannot be negative",
    );
  }

  const rounded =
    Math.round(numeric * 100) / 100;
  if (
    rounded > 0 &&
    rounded < REQUEST_SELLER_MARKUP_MIN_PERCENT
  ) {
    throw new Error(
      `Seller markup percent must be 0 or at least ${REQUEST_SELLER_MARKUP_MIN_PERCENT}%`,
    );
  }
  if (
    rounded >
    REQUEST_SELLER_MARKUP_MAX_PERCENT
  ) {
    throw new Error(
      `Seller markup percent cannot exceed ${REQUEST_SELLER_MARKUP_MAX_PERCENT}%`,
    );
  }

  return rounded;
}

function parseRequiredDate(
  value,
  fieldLabel = "Date",
) {
  const normalized = (value || "")
    .toString()
    .trim();
  if (!normalized) {
    throw new Error(`${fieldLabel} is required`);
  }
  const parsed = new Date(normalized);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(
      `${fieldLabel} must be a valid date`,
    );
  }
  return parsed;
}

function computeInvoiceCharges({
  subtotalAmount,
  baseLogisticsFee,
  sellerMarkupPercent,
}) {
  const normalizedBaseLogisticsFee =
    safeMinorAmount(baseLogisticsFee);
  const normalizedSellerMarkupPercent =
    safeSellerMarkupPercent(
      sellerMarkupPercent,
    );
  const sellerMarkupAmount = Math.round(
    Number(subtotalAmount || 0) *
      (normalizedSellerMarkupPercent / 100),
  );
  const logisticsFee =
    normalizedBaseLogisticsFee +
    sellerMarkupAmount;
  const serviceCharge = Math.round(
    Number(subtotalAmount || 0) *
      REQUEST_SERVICE_CHARGE_RATE,
  );
  const totalAmount =
    Number(subtotalAmount || 0) +
    logisticsFee +
    serviceCharge;

  return {
    baseLogisticsFee:
      normalizedBaseLogisticsFee,
    sellerMarkupPercent:
      normalizedSellerMarkupPercent,
    sellerMarkupAmount,
    logisticsFee,
    serviceCharge,
    totalAmount,
  };
}

function isFinalStatus(status) {
  return [
    STATUS_APPROVED,
    STATUS_CANCELLED,
  ].includes((status || "").toString());
}

async function buildDeliveryAddressSnapshot({
  userId,
  deliveryAddress,
  session,
}) {
  if (!deliveryAddress) {
    throw new Error(
      "Delivery address is required",
    );
  }

  const addressSource = deliveryAddress.source;
  if (
    addressSource !== "home" &&
    addressSource !== "company" &&
    addressSource !== "custom"
  ) {
    throw new Error(
      "Invalid delivery address source",
    );
  }

  if (
    addressSource === "home" ||
    addressSource === "company"
  ) {
    const user = await User.findById(userId)
      .select("homeAddress companyAddress")
      .session(session)
      .lean();

    if (!user) {
      throw new Error("User not found");
    }

    const selected =
      addressSource === "home"
        ? user.homeAddress
        : user.companyAddress;
    if (!selected) {
      throw new Error(
        "Selected delivery address is missing",
      );
    }
    if (!selected.isVerified) {
      throw new Error(
        "Selected delivery address is not verified",
      );
    }

    return {
      source: addressSource,
      ...selected,
    };
  }

  const { source, placeId, ...rawAddress } =
    deliveryAddress;
  const result = await verifyAddressPayload({
    address: rawAddress,
    source: "custom",
    placeId,
  });

  if (!result.address?.isVerified) {
    throw new Error(
      "Delivery address must be verified",
    );
  }

  return {
    source: "custom",
    ...result.address,
  };
}

async function resolveLinkedReservation({
  userId,
  reservationId,
  session,
}) {
  const normalizedId =
    reservationId == null
      ? ""
      : reservationId.toString().trim();
  if (!normalizedId) {
    return {
      reservation: null,
      linkedPlanProductId: null,
      linkedReservationQuantity: 0,
    };
  }

  if (
    !mongoose.Types.ObjectId.isValid(normalizedId)
  ) {
    throw new Error(
      "Invalid pre-order reservation id",
    );
    DDD;
  }

  const reservation =
    await PreorderReservation.findOne({
      _id: normalizedId,
      userId,
      status: PREORDER_STATUS_RESERVED,
    }).session(session);
  if (!reservation) {
    throw new Error(
      "Pre-order reservation not found or not reserved",
    );
  }

  const linkedPlan = await ProductionPlan.findOne(
    {
      _id: reservation.planId,
      businessId: reservation.businessId,
    },
  )
    .select({ productId: 1 })
    .session(session)
    .lean();

  if (!linkedPlan?.productId) {
    throw new Error(
      "Pre-order reservation plan is not linked to a product",
    );
  }

  const linkedReservationQuantity = Number(
    reservation.quantity || 0,
  );
  if (
    !Number.isFinite(linkedReservationQuantity) ||
    linkedReservationQuantity <= 0
  ) {
    throw new Error(
      "Pre-order reservation quantity is invalid",
    );
  }

  return {
    reservation,
    linkedPlanProductId:
      linkedPlan.productId.toString(),
    linkedReservationQuantity,
  };
}

async function buildItemGroups({
  items,
  session,
  reservationContext,
}) {
  if (
    !Array.isArray(items) ||
    items.length === 0
  ) {
    throw new Error(
      "Purchase request must have at least one item",
    );
  }

  const groups = new Map();
  let linkedProductQuantity = 0;

  for (const item of items) {
    const productId =
      item?.productId?.toString().trim() ||
      item?.product?.toString().trim() ||
      "";
    const quantity = Number(item?.quantity || 0);
    if (!productId) {
      throw new Error("productId is required");
    }
    if (
      !Number.isFinite(quantity) ||
      quantity <= 0
    ) {
      throw new Error(
        `Invalid quantity for product: ${productId}`,
      );
    }

    const product =
      await Product.findById(productId).session(
        session,
      );
    if (!product) {
      throw new Error(
        `Product not found: ${productId}`,
      );
    }
    if (product.deletedAt) {
      throw new Error(
        `Product is deleted: ${productId}`,
      );
    }
    if (!product.isActive) {
      throw new Error(
        `Product is inactive: ${productId}`,
      );
    }
    if (product.stock < quantity) {
      throw new Error(
        `Insufficient stock for product: ${productId}`,
      );
    }

    const businessId =
      product.businessId?.toString() || "";
    if (!businessId) {
      throw new Error(
        `Product is missing business scope: ${productId}`,
      );
    }

    if (!groups.has(businessId)) {
      groups.set(businessId, {
        businessId,
        items: [],
        subtotalAmount: 0,
      });
    }

    const subtotal = product.price * quantity;
    groups.get(businessId).items.push({
      product: product._id,
      businessId: product.businessId || null,
      name: product.name || "Product",
      imageUrl: product.imageUrl || "",
      quantity,
      unitPrice: product.price,
      subtotal,
    });
    groups.get(businessId).subtotalAmount +=
      subtotal;

    if (
      reservationContext?.linkedPlanProductId &&
      product._id.toString() ===
        reservationContext.linkedPlanProductId
    ) {
      linkedProductQuantity += quantity;
    }
  }

  if (
    reservationContext?.reservation &&
    linkedProductQuantity !==
      reservationContext.linkedReservationQuantity
  ) {
    throw new Error(
      "Request quantity must match linked pre-order reservation quantity",
    );
  }

  return Array.from(groups.values());
}

async function confirmReservationForOrder({
  order,
  session,
}) {
  const reservationId =
    order.reservationId?.toString() || "";
  if (!reservationId) {
    return;
  }

  const reservation =
    await PreorderReservation.findOne({
      _id: reservationId,
      userId: order.user,
    }).session(session);
  if (!reservation) {
    throw new Error(
      "Linked pre-order reservation not found for order",
    );
  }

  const orderScopedToBusiness =
    Array.isArray(order.businessIds) &&
    order.businessIds.some(
      (businessId) =>
        businessId?.toString() ===
        reservation.businessId?.toString(),
    );
  if (!orderScopedToBusiness) {
    throw new Error(
      "Linked pre-order reservation business scope mismatch",
    );
  }

  if (
    reservation.status ===
    PREORDER_STATUS_CONFIRMED
  ) {
    return;
  }
  if (
    reservation.status !==
    PREORDER_STATUS_RESERVED
  ) {
    throw new Error(
      `Linked pre-order reservation is not confirmable (${reservation.status})`,
    );
  }

  reservation.status = PREORDER_STATUS_CONFIRMED;
  await reservation.save({ session });
}

function buildRequestEventData(request) {
  return {
    purchaseRequestId:
      request._id?.toString() || "",
    status: request.status,
    subtotalAmount: request.subtotalAmount || 0,
    baseLogisticsFee:
      request.charges?.baseLogisticsFee || 0,
    sellerMarkupPercent:
      request.charges?.sellerMarkupPercent || 0,
    sellerMarkupAmount:
      request.charges?.sellerMarkupAmount || 0,
    logisticsFee:
      request.charges?.logisticsFee || 0,
    serviceCharge:
      request.charges?.serviceCharge || 0,
    totalAmount:
      request.invoice?.totalAmount || 0,
    estimatedDeliveryDate:
      request.invoice?.estimatedDeliveryDate ||
      null,
    linkedOrderId:
      request.linkedOrderId?.toString() || "",
    customerCare:
      buildCustomerCareSnapshot(request),
  };
}

async function loadCustomerCareBusinessSummary({
  request,
  session = null,
}) {
  const businessQuery = User.findById(
    request.businessId,
  ).select(
    "companyName name firstName middleName lastName",
  );
  const productsQuery = Product.find({
    businessId: request.businessId,
    isActive: true,
    deletedAt: null,
  })
    .select("name price stock")
    .lean();

  if (session) {
    businessQuery.session(session);
    productsQuery.session(session);
  }

  const orderQuery = request.linkedOrderId
    ? Order.findById(request.linkedOrderId)
        .select("status totalPrice fulfillment")
        .lean()
    : Promise.resolve(null);
  if (
    session &&
    typeof orderQuery.session === "function"
  ) {
    orderQuery.session(session);
  }

  const [business, products, linkedOrder] =
    await Promise.all([
      businessQuery.lean(),
      productsQuery,
      orderQuery,
    ]);

  const safeProducts = (products || [])
    .map((product) => ({
      name: product.name || "Product",
      price: Number(product.price || 0),
      stock: Number(product.stock || 0),
    }))
    .sort((left, right) => {
      if (right.stock !== left.stock) {
        return right.stock - left.stock;
      }
      return left.name.localeCompare(right.name);
    })
    .slice(0, MAX_PRODUCT_SUMMARY_ITEMS);

  return {
    assistantName: resolveAssistantName(request),
    businessName:
      business?.companyName?.toString().trim() ||
      buildDisplayName(business) ||
      "this business",
    ownerName: buildDisplayName(business),
    activeProductCount: Array.isArray(products)
      ? products.length
      : 0,
    products: safeProducts,
    linkedOrder: linkedOrder || null,
  };
}

async function createCustomerCareMessage({
  request,
  body,
  eventType,
  eventData = {},
  session = null,
  context = {},
}) {
  const businessActor =
    await chatService.loadActor(
      request.businessId,
      context,
    );
  return createStructuredMessage({
    actor: businessActor,
    businessId: request.businessId,
    conversationId: request.conversationId,
    body,
    eventType,
    eventData: buildCustomerCareEventData(
      request,
      eventData,
    ),
    session,
    context,
  });
}

async function createCustomerCareIntroMessage({
  request,
  session = null,
  context = {},
}) {
  const summary =
    await loadCustomerCareBusinessSummary({
      request,
      session,
    });
  const body = `Hi, my name is ${summary.assistantName} from ${summary.businessName}. I’ve received your request and I’ll keep this chat moving while the team reviews the address, availability, and delivery cost. I can help with available items, request status, invoice details, and the next steps here.`;

  return createCustomerCareMessage({
    request,
    body,
    eventType:
      REQUEST_EVENT_TYPES.CUSTOMER_CARE_INTRO,
    eventData: {
      businessName: summary.businessName,
      ownerName: summary.ownerName,
    },
    session,
    context,
  });
}

function buildSellerAttendanceMessage({
  assistantName,
  businessName,
  actor,
  staffProfile,
}) {
  const attendantName = buildDisplayName(actor);
  const roleLabel =
    actor.role === "staff"
      ? formatRoleLabel(
          staffProfile?.staffRole || "staff",
        )
      : "business owner";
  return `Hi, my name is ${assistantName} from ${businessName}. ${attendantName} is attending this request now as ${roleLabel}, so they can reply directly in this chat from here. I’m stepping back while they handle the conversation.`;
}

async function buildCustomerCareReplyText({
  request,
  customerMessage,
  hasAttachments = false,
  context = {},
}) {
  const summary =
    await loadCustomerCareBusinessSummary({
      request,
    });
  const fallback = buildCustomerCareFallback({
    request,
    summary,
    customerMessage,
    hasAttachments,
  });
  const latestCustomerText = (
    customerMessage || ""
  )
    .toString()
    .trim();
  if (!latestCustomerText) {
    return fallback;
  }

  const facts = [
    `Assistant name: ${summary.assistantName}`,
    `Business name: ${summary.businessName}`,
    `Owner name: ${summary.ownerName}`,
    `Request status: ${request.status}`,
    `Request subtotal: NGN ${formatMinorAmount(request.subtotalAmount)}`,
    `Invoice total: NGN ${formatMinorAmount(request.invoice?.totalAmount || 0)}`,
    `Delivery address: ${formatAddress(request.deliveryAddress) || "Not available"}`,
    `Requested items: ${
      (request.items || [])
        .map(
          (item) =>
            `${item.quantity} x ${item.name} at NGN ${formatMinorAmount(item.unitPrice)}`,
        )
        .join("; ") || "None"
    }`,
    `Active product count: ${summary.activeProductCount}`,
    `Product summary: ${buildProductListLabel(summary.products) || "No safe inventory summary available"}`,
    `Linked order status: ${summary.linkedOrder?.status || "No linked order yet"}`,
  ].join("\n");

  try {
    const response = await createAiChatCompletion(
      {
        messages: [
          {
            role: "user",
            content: `FACTS:\n${facts}\n\nCustomer message: ${latestCustomerText}`,
          },
        ],
        systemPrompt: [
          `You are ${summary.assistantName}, a warm customer care representative for ${summary.businessName}.`,
          "Speak like a real team member.",
          "Never say you are an AI, chatbot, model, or automated assistant.",
          "Use only the facts provided in the user message.",
          "Do not mention email addresses, phone numbers, other customers, or internal-only data.",
          "If the customer asks for something unavailable, say the team will confirm it in chat.",
          "Keep the reply friendly, useful, and under 90 words.",
        ].join(" "),
        temperature: 0.25,
        maxTokens: 180,
        useReasoning: false,
        context: {
          ...context,
          operation:
            "PurchaseRequestCustomerCareReply",
          intent:
            "purchase_request_customer_care_reply",
          businessId:
            request.businessId?.toString() || "",
          source:
            "purchase_request_customer_care",
        },
      },
    );

    const content = (response?.content || "")
      .toString()
      .replace(/\s+/g, " ")
      .trim();
    if (
      !content ||
      isUnsafeAssistantReply(content)
    ) {
      return fallback;
    }
    return content;
  } catch (error) {
    debug(
      "PURCHASE_REQUEST_SERVICE: customer care reply fallback",
      {
        error: error?.message || "unknown_error",
        conversationId:
          request.conversationId?.toString() ||
          "",
        purchaseRequestId:
          request._id?.toString() || "",
      },
    );
    return fallback;
  }
}

function buildRequestCreatedMessage(request) {
  const totalItems = (request.items || []).reduce(
    (sum, item) =>
      sum + Number(item.quantity || 0),
    0,
  );
  const destination = formatAddress(
    request.deliveryAddress,
  );
  const pieces = [
    `Buyer requested ${totalItems} item${totalItems === 1 ? "" : "s"} for NGN ${formatMinorAmount(request.subtotalAmount)}.`,
  ];
  if (destination) {
    pieces.push(
      `Delivery address: ${destination}.`,
    );
  }
  return pieces.join(" ");
}

function buildInvoiceSentMessage(request) {
  const deliveryLabel =
    request.invoice?.estimatedDeliveryDate
      ? new Date(
          request.invoice.estimatedDeliveryDate,
        ).toLocaleDateString("en-NG", {
          day: "numeric",
          month: "short",
          year: "numeric",
        })
      : "";
  return [
    `Invoice ${request.invoice?.invoiceNumber || buildInvoiceNumber(request._id)} is ready.`,
    `Total due: NGN ${formatMinorAmount(request.invoice?.totalAmount)}.`,
    `Logistics: NGN ${formatMinorAmount(request.charges?.logisticsFee)}.`,
    `In-app service charge: NGN ${formatMinorAmount(request.charges?.serviceCharge)}.`,
    deliveryLabel
      ? `Estimated delivery: ${deliveryLabel}.`
      : "",
    `Payment details: ${
      request.invoice?.paymentInstructions ||
      formatBusinessPaymentInstructions(
        request.invoice?.paymentAccount,
      )
    }`,
  ]
    .filter(Boolean)
    .join(" ");
}

function buildProofUploadedMessage(request) {
  return `Payment proof uploaded for invoice ${request.invoice?.invoiceNumber || buildInvoiceNumber(request._id)}.`;
}

function buildProofReviewedMessage({
  request,
  decision,
}) {
  if (decision === "approved") {
    return `Payment proof approved. Order ${request.linkedOrderId?.toString().slice(-6).toUpperCase() || ""} is now ready for fulfillment.`;
  }

  const reviewNote =
    request.proof?.reviewNote?.trim() || "";
  return `Payment proof rejected.${reviewNote ? ` Reason: ${reviewNote}` : ""}`;
}

async function createStructuredMessage({
  actor,
  businessId,
  conversationId,
  attachmentIds = [],
  body,
  eventType,
  eventData,
  session,
  context,
}) {
  return chatService.sendMessage({
    actor,
    businessId,
    conversationId,
    body,
    attachmentIds,
    context,
    messageType: CHAT_MESSAGE_TYPES.SYSTEM,
    eventType,
    eventData,
    session,
  });
}

async function createSingleRequestRecord({
  actor,
  businessId,
  requestDraft,
  deliveryAddress,
  reservationId,
  session,
  context,
}) {
  const conversation =
    await chatService.createConversation({
      actor,
      businessId,
      type: CHAT_CONVERSATION_TYPES.DIRECT,
      title: "",
      participantUserIds: [businessId],
      allowExternalBuyerActor: isBuyerRole(
        actor.role,
      ),
      context,
      session,
    });

  const request = await PurchaseRequest.create(
    [
      {
        customerId: actor._id,
        businessId,
        conversationId: conversation._id,
        reservationId: reservationId || null,
        status: STATUS_REQUESTED,
        items: requestDraft.items,
        subtotalAmount:
          requestDraft.subtotalAmount,
        deliveryAddress,
        charges: {
          logisticsFee: 0,
          serviceCharge: 0,
        },
        invoice: {
          invoiceNumber: "",
          totalAmount:
            requestDraft.subtotalAmount,
        },
        customerCare: {
          assistantName: DEFAULT_ASSISTANT_NAME,
          isEnabled: true,
          lastUpdatedAt: new Date(),
        },
      },
    ],
    { session },
  );

  const createdRequest = request[0];
  const message = await createStructuredMessage({
    actor,
    businessId,
    conversationId: conversation._id,
    body: buildRequestCreatedMessage(
      createdRequest,
    ),
    eventType:
      REQUEST_EVENT_TYPES.REQUEST_CREATED,
    eventData: buildRequestEventData(
      createdRequest,
    ),
    session,
    context,
  });

  const introMessage =
    await createCustomerCareIntroMessage({
      request: createdRequest,
      session,
      context,
    });

  return {
    purchaseRequest: createdRequest,
    conversation,
    message,
    followUpMessages: [introMessage],
  };
}

async function createPurchaseRequest({
  customerId,
  items,
  deliveryAddress,
  reservationId = null,
  context = {},
}) {
  debug(
    "PURCHASE_REQUEST_SERVICE: createPurchaseRequest - entry",
    {
      customerId,
      itemsCount: Array.isArray(items)
        ? items.length
        : 0,
      hasReservationId: Boolean(reservationId),
    },
  );

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const actor = await chatService.loadActor(
      customerId,
      context,
    );
    if (!isBuyerRole(actor.role)) {
      throw new Error(
        "Only customer, tenant, and business owner buyers can create purchase requests",
      );
    }
    const reservationContext =
      await resolveLinkedReservation({
        userId: customerId,
        reservationId,
        session,
      });
    const requestGroups = await buildItemGroups({
      items,
      session,
      reservationContext,
    });
    if (requestGroups.length !== 1) {
      throw new Error(
        "Request to buy supports one seller per request",
      );
    }

    const addressSnapshot =
      await buildDeliveryAddressSnapshot({
        userId: customerId,
        deliveryAddress,
        session,
      });

    const result =
      await createSingleRequestRecord({
        actor,
        businessId: requestGroups[0].businessId,
        requestDraft: requestGroups[0],
        deliveryAddress: addressSnapshot,
        reservationId:
          reservationContext.reservation?._id ||
          null,
        session,
        context,
      });

    await session.commitTransaction();

    await writeAnalyticsEvent({
      businessId:
        result.purchaseRequest.businessId,
      actorId: customerId,
      actorRole: actor.role,
      eventType: "purchase_request_created",
      entityType: "purchase_request",
      entityId: result.purchaseRequest._id,
      metadata: {
        subtotalAmount:
          result.purchaseRequest.subtotalAmount,
        status: result.purchaseRequest.status,
      },
    });

    return result;
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function createBatchPurchaseRequests({
  customerId,
  items,
  deliveryAddress,
  context = {},
}) {
  debug(
    "PURCHASE_REQUEST_SERVICE: createBatchPurchaseRequests - entry",
    {
      customerId,
      itemsCount: Array.isArray(items)
        ? items.length
        : 0,
    },
  );

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const actor = await chatService.loadActor(
      customerId,
      context,
    );
    if (!isBuyerRole(actor.role)) {
      throw new Error(
        "Only customer, tenant, and business owner buyers can create purchase requests",
      );
    }
    const requestGroups = await buildItemGroups({
      items,
      session,
      reservationContext: null,
    });
    const addressSnapshot =
      await buildDeliveryAddressSnapshot({
        userId: customerId,
        deliveryAddress,
        session,
      });

    const results = [];
    for (const group of requestGroups) {
      results.push(
        await createSingleRequestRecord({
          actor,
          businessId: group.businessId,
          requestDraft: group,
          deliveryAddress: addressSnapshot,
          reservationId: null,
          session,
          context,
        }),
      );
    }

    await session.commitTransaction();

    await Promise.all(
      results.map((entry) =>
        writeAnalyticsEvent({
          businessId:
            entry.purchaseRequest.businessId,
          actorId: customerId,
          actorRole: actor.role,
          eventType: "purchase_request_created",
          entityType: "purchase_request",
          entityId: entry.purchaseRequest._id,
          metadata: {
            subtotalAmount:
              entry.purchaseRequest
                .subtotalAmount,
            status: entry.purchaseRequest.status,
          },
        }),
      ),
    );

    return results;
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function resolveActivePurchaseRequest({
  conversationId,
}) {
  const active = await PurchaseRequest.findOne({
    conversationId,
    status: {
      $in: [
        STATUS_REQUESTED,
        STATUS_QUOTED,
        STATUS_PROOF_SUBMITTED,
        STATUS_REJECTED,
      ],
    },
  })
    .sort({ createdAt: -1 })
    .lean();
  if (active) {
    return active;
  }

  return PurchaseRequest.findOne({
    conversationId,
  })
    .sort({ createdAt: -1 })
    .lean();
}

async function getConversationPurchaseRequest({
  conversationId,
}) {
  if (!conversationId) {
    return null;
  }
  return resolveActivePurchaseRequest({
    conversationId,
  });
}

async function attendPurchaseRequestChat({
  requestId,
  actorUserId,
  context = {},
}) {
  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const {
      actor,
      businessId,
      request,
      staffProfile,
    } = await loadRequestForBusiness({
      requestId,
      actorUserId,
      context,
      session,
    });

    if (request.status === STATUS_CANCELLED) {
      throw new Error(
        "Cancelled purchase requests cannot be attended",
      );
    }

    const summary =
      await loadCustomerCareBusinessSummary({
        request,
        session,
      });
    request.customerCare = {
      assistantName:
        resolveAssistantName(request),
      isEnabled: false,
      currentAttendantUserId: actor._id,
      currentAttendantName:
        buildDisplayName(actor),
      currentAttendantRole: actor.role,
      currentAttendantStaffRole:
        staffProfile?.staffRole || "",
      lastUpdatedAt: new Date(),
    };
    await request.save({ session });

    const message = await createStructuredMessage(
      {
        actor,
        businessId,
        conversationId: request.conversationId,
        body: buildSellerAttendanceMessage({
          assistantName: summary.assistantName,
          businessName: summary.businessName,
          actor,
          staffProfile,
        }),
        eventType:
          REQUEST_EVENT_TYPES.SELLER_ATTENDING,
        eventData: buildCustomerCareEventData(
          request,
          {
            attendantName:
              buildDisplayName(actor),
            attendantRole:
              actor.role === "staff"
                ? staffProfile?.staffRole ||
                  "staff"
                : actor.role,
            businessName: summary.businessName,
            ownerName: summary.ownerName,
          },
        ),
        session,
        context,
      },
    );

    await session.commitTransaction();

    return {
      purchaseRequest: request,
      message,
    };
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function exitPurchaseRequestChat({
  requestId,
  actorUserId,
  context = {},
}) {
  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const { request } =
      await loadRequestForBusiness({
        requestId,
        actorUserId,
        context,
        session,
      });

    if (request.status === STATUS_CANCELLED) {
      throw new Error(
        "Cancelled purchase requests cannot be reopened in chat",
      );
    }

    const previousAttendantName =
      request.customerCare?.currentAttendantName
        ?.toString()
        .trim() || "";
    const previousAttendantRole =
      request.customerCare?.currentAttendantStaffRole
        ?.toString()
        .trim() ||
      request.customerCare?.currentAttendantRole
        ?.toString()
        .trim() ||
      "";
    const summary =
      await loadCustomerCareBusinessSummary({
        request,
        session,
      });
    request.customerCare = {
      assistantName:
        resolveAssistantName(request),
      isEnabled: true,
      currentAttendantUserId: null,
      currentAttendantName: "",
      currentAttendantRole: "",
      currentAttendantStaffRole: "",
      lastUpdatedAt: new Date(),
    };
    await request.save({ session });

    const message =
      await createCustomerCareMessage({
        request,
        body: previousAttendantName
          ? `Hi, my name is ${summary.assistantName} from ${summary.businessName}. ${previousAttendantName}${previousAttendantRole ? `, our ${formatRoleLabel(previousAttendantRole)}` : ""}, has stepped away, so I’ve picked this request back up for now. I can help with availability, invoice details, payment proof status, and the next steps here.`
          : `Hi, my name is ${summary.assistantName} from ${summary.businessName}. I’ve picked this request back up while the team steps away. I can help with availability, invoice details, payment proof status, and the next steps here.`,
        eventType:
          REQUEST_EVENT_TYPES.CUSTOMER_CARE_RESUMED,
        eventData: {
          businessName: summary.businessName,
          ownerName: summary.ownerName,
          previousAttendantName,
          previousAttendantRole,
        },
        session,
        context,
      });

    await session.commitTransaction();

    return {
      purchaseRequest: request,
      message,
    };
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function updatePurchaseRequestAiControl({
  requestId,
  actorUserId,
  enabled,
  context = {},
}) {
  if (typeof enabled !== "boolean") {
    throw new Error(
      "enabled must be true or false",
    );
  }

  if (enabled) {
    return exitPurchaseRequestChat({
      requestId,
      actorUserId,
      context,
    });
  }

  return attendPurchaseRequestChat({
    requestId,
    actorUserId,
    context,
  });
}

async function handleConversationMessageEffects({
  actor,
  conversationId,
  message,
  context = {},
}) {
  if (
    !conversationId ||
    !message ||
    !actor?._id
  ) {
    return [];
  }
  if (!isBuyerRole(actor.role)) {
    return [];
  }
  if (
    (message.eventType || "").toString().trim()
  ) {
    return [];
  }

  const request =
    await resolveActivePurchaseRequest({
      conversationId,
    });
  if (!request) {
    return [];
  }
  if (
    request.customerId?.toString() !==
    actor._id?.toString()
  ) {
    return [];
  }
  if (request.status === STATUS_CANCELLED) {
    return [];
  }
  if (request.customerCare?.isEnabled === false) {
    return [];
  }

  const body = await buildCustomerCareReplyText({
    request,
    customerMessage: message.body || "",
    hasAttachments:
      Array.isArray(message.attachmentIds) &&
      message.attachmentIds.length > 0,
    context,
  });
  if (!body) {
    return [];
  }

  const followUpMessage =
    await createCustomerCareMessage({
      request,
      body,
      eventType:
        REQUEST_EVENT_TYPES.CUSTOMER_CARE_REPLY,
      eventData: {
        autoReply: true,
      },
      context,
    });

  return [followUpMessage];
}

async function loadRequestForCustomer({
  requestId,
  customerId,
  session,
}) {
  const request = await PurchaseRequest.findOne({
    _id: requestId,
    customerId,
  }).session(session);
  if (!request) {
    throw new Error("Purchase request not found");
  }
  return request;
}

async function loadRequestForBusiness({
  requestId,
  actorUserId,
  context = {},
  session,
  allowedStaffRoles = REQUEST_CHAT_STAFF_ROLES,
  forbiddenMessage = "Only authorized seller roles can manage purchase requests",
}) {
  const { actor, businessId } =
    await resolveBusinessContext(
      actorUserId,
      context,
    );
  const staffProfile = await resolveStaffProfile(
    {
      actor,
      businessId,
      allowMissing: true,
    },
    context,
  );
  const isAllowedSellerActor =
    actor.role === "business_owner" ||
    (actor.role === "staff" &&
      allowedStaffRoles.has(
        staffProfile?.staffRole || "",
      ));
  if (!isAllowedSellerActor) {
    throw new Error(forbiddenMessage);
  }

  const request = await PurchaseRequest.findOne({
    _id: requestId,
    businessId,
  }).session(session);
  if (!request) {
    throw new Error(
      "Purchase request not found for this business",
    );
  }

  return {
    actor,
    businessId,
    request,
    staffProfile,
  };
}

async function sendInvoice({
  requestId,
  actorUserId,
  baseLogisticsFee,
  sellerMarkupPercent,
  estimatedDeliveryDate,
  paymentInstructions,
  paymentAccount,
  savePaymentAccount = false,
  note = "",
  context = {},
}) {
  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const { actor, businessId, request } =
      await loadRequestForBusiness({
        requestId,
        actorUserId,
        context,
        session,
        allowedStaffRoles:
          REQUEST_INVOICE_STAFF_ROLES,
        forbiddenMessage: buildAllowedRoleMessage(
          {
            actionLabel:
              "send purchase request invoices",
            staffRoles: [
              ...REQUEST_INVOICE_STAFF_ROLES,
            ],
          },
        ),
      });

    if (
      isFinalStatus(request.status) ||
      request.status === STATUS_PROOF_SUBMITTED
    ) {
      throw new Error(
        "Invoice cannot be updated in the current request state",
      );
    }

    const normalizedPaymentAccount =
      paymentAccount &&
      typeof paymentAccount === "object"
        ? normalizeBusinessPaymentAccountInput(
            paymentAccount,
          )
        : null;
    const safeInstructions =
      normalizedPaymentAccount
        ? formatBusinessPaymentInstructions(
            normalizedPaymentAccount,
          )
        : (paymentInstructions || "")
            .toString()
            .trim();
    if (!safeInstructions) {
      throw new Error(
        "Payment instructions are required",
      );
    }
    const safeEstimatedDeliveryDate =
      parseRequiredDate(
        estimatedDeliveryDate,
        "Estimated delivery date",
      );
    const charges = computeInvoiceCharges({
      subtotalAmount:
        request.subtotalAmount,
      baseLogisticsFee,
      sellerMarkupPercent,
    });

    request.charges.baseLogisticsFee =
      charges.baseLogisticsFee;
    request.charges.sellerMarkupPercent =
      charges.sellerMarkupPercent;
    request.charges.sellerMarkupAmount =
      charges.sellerMarkupAmount;
    request.charges.logisticsFee =
      charges.logisticsFee;
    request.charges.serviceCharge =
      charges.serviceCharge;
    request.invoice.invoiceNumber =
      buildInvoiceNumber(request._id);
    request.invoice.totalAmount =
      charges.totalAmount;
    request.invoice.paymentInstructions =
      safeInstructions;
    request.invoice.paymentAccount =
      normalizedPaymentAccount
        ? {
            accountId: null,
            bankName:
              normalizedPaymentAccount.bankName,
            accountName:
              normalizedPaymentAccount.accountName,
            accountNumber:
              normalizedPaymentAccount.accountNumber,
            transferInstruction:
              normalizedPaymentAccount.transferInstruction,
          }
        : {
            accountId: null,
            bankName: "",
            accountName: "",
            accountNumber: "",
            transferInstruction: "",
          };
    request.invoice.note = (note || "")
      .toString()
      .trim();
    request.invoice.estimatedDeliveryDate =
      safeEstimatedDeliveryDate;
    request.invoice.sentAt = new Date();
    request.invoice.sentByUserId = actor._id;
    request.invoice.sentByRole = actor.role;
    request.proof = {
      attachmentId: null,
      url: "",
      filename: "",
      mimeType: "",
      sizeBytes: 0,
      note: "",
      submittedAt: null,
      submittedByUserId: null,
      reviewedAt: null,
      reviewedByUserId: null,
      reviewedByRole: "",
      reviewDecision: "",
      reviewNote: "",
    };
    if (normalizedPaymentAccount) {
      const savedAccountId =
        await upsertBusinessPaymentAccount({
          businessId,
          session,
          paymentAccount:
            normalizedPaymentAccount,
          savePaymentAccount,
        });
      request.invoice.paymentAccount.accountId =
        savedAccountId || null;
    }
    request.linkedOrderId = null;
    request.status = STATUS_QUOTED;
    await request.save({ session });

    const message = await createStructuredMessage(
      {
        actor,
        businessId,
        conversationId: request.conversationId,
        body: buildInvoiceSentMessage(request),
        eventType:
          REQUEST_EVENT_TYPES.INVOICE_SENT,
        eventData: buildRequestEventData(request),
        context,
        session,
      },
    );

    await session.commitTransaction();

    await writeAuditLog({
      businessId,
      actorId: actor._id,
      actorRole: actor.role,
      action: "purchase_request_invoice_sent",
      entityType: "purchase_request",
      entityId: request._id,
      message:
        "Manual invoice sent for purchase request",
      changes: {
        status: request.status,
        totalAmount: request.invoice.totalAmount,
        logisticsFee:
          request.charges.logisticsFee,
        serviceCharge:
          request.charges.serviceCharge,
        sellerMarkupPercent:
          request.charges
            .sellerMarkupPercent,
      },
    });

    return {
      purchaseRequest:
        await presentPurchaseRequest(request, {
          session,
        }),
      message,
    };
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function submitPaymentProof({
  requestId,
  customerId,
  attachmentId,
  note = "",
  context = {},
}) {
  if (!attachmentId) {
    throw new Error("attachmentId is required");
  }

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const request = await loadRequestForCustomer({
      requestId,
      customerId,
      session,
    });

    if (
      ![STATUS_QUOTED, STATUS_REJECTED].includes(
        request.status,
      )
    ) {
      throw new Error(
        "Payment proof cannot be submitted in the current request state",
      );
    }

    const attachment =
      await ChatAttachment.findById(
        attachmentId,
      ).session(session);
    if (!attachment) {
      throw new Error("Attachment not found");
    }
    if (
      attachment.conversationId?.toString() !==
      request.conversationId.toString()
    ) {
      throw new Error(
        "Attachment does not belong to this request conversation",
      );
    }
    if (
      attachment.uploadedByUserId?.toString() !==
      customerId.toString()
    ) {
      throw new Error(
        "Only the buyer can upload payment proof",
      );
    }

    request.status = STATUS_PROOF_SUBMITTED;
    request.proof = {
      attachmentId: attachment._id,
      url: attachment.url || "",
      filename: attachment.filename || "",
      mimeType: attachment.mimeType || "",
      sizeBytes: attachment.sizeBytes || 0,
      note: (note || "").toString().trim(),
      submittedAt: new Date(),
      submittedByUserId: customerId,
      reviewedAt: null,
      reviewedByUserId: null,
      reviewedByRole: "",
      reviewDecision: "",
      reviewNote: "",
    };
    await request.save({ session });

    const actor = await chatService.loadActor(
      customerId,
      context,
    );
    const message = await createStructuredMessage(
      {
        actor,
        businessId: request.businessId,
        conversationId: request.conversationId,
        attachmentIds: [attachmentId],
        body: buildProofUploadedMessage(request),
        eventType:
          REQUEST_EVENT_TYPES.PROOF_UPLOADED,
        eventData: buildRequestEventData(request),
        context,
        session,
      },
    );

    await session.commitTransaction();

    return {
      purchaseRequest: request,
      message,
    };
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function approveProofAndCreateOrder({
  request,
  actor,
  businessId,
  session,
}) {
  const order = new Order({
    user: request.customerId,
    reservationId: request.reservationId || null,
    items: (request.items || []).map((item) => ({
      product: item.product,
      businessId: item.businessId,
      quantity: item.quantity,
      price: item.unitPrice,
    })),
    totalPrice: request.invoice.totalAmount,
    charges: {
      logisticsFee:
        request.charges?.logisticsFee || 0,
      serviceCharge:
        request.charges?.serviceCharge || 0,
    },
    fulfillment: {
      estimatedDeliveryDate:
        request.invoice
          ?.estimatedDeliveryDate || null,
    },
    deliveryAddress: request.deliveryAddress,
    businessIds: [businessId],
    status: "paid",
    paymentSource: "manual_direct",
    statusHistory: [
      {
        status: "paid",
        changedAt: new Date(),
        changedBy: actor._id,
        changedByRole: actor.role,
        note: "manual_direct_payment_approved",
      },
    ],
  });

  await order.save({ session });
  await confirmReservationForOrder({
    order,
    session,
  });
  await adjustOrderStock(
    order,
    "decrease",
    session,
    {
      actorId: actor._id,
      actorRole: actor.role,
      businessId,
      reason: "manual_direct_payment_approved",
      source: "purchase_request",
    },
  );

  return order;
}

async function reviewPaymentProof({
  requestId,
  actorUserId,
  decision,
  reviewNote = "",
  approvalPassword = "",
  context = {},
}) {
  const normalizedDecision = (decision || "")
    .toString()
    .trim()
    .toLowerCase();
  if (
    normalizedDecision !== "approved" &&
    normalizedDecision !== "rejected"
  ) {
    throw new Error(
      "decision must be approved or rejected",
    );
  }

  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const {
      actor,
      businessId,
      request,
      staffProfile,
    } = await loadRequestForBusiness({
      requestId,
      actorUserId,
      context,
      session,
      allowedStaffRoles:
        REQUEST_PROOF_REVIEW_STAFF_ROLES,
      forbiddenMessage: buildAllowedRoleMessage({
        actionLabel: "review payment proof",
        staffRoles: [
          ...REQUEST_PROOF_REVIEW_STAFF_ROLES,
        ],
      }),
    });

    if (
      request.status !== STATUS_PROOF_SUBMITTED
    ) {
      throw new Error(
        "Payment proof is not ready for review",
      );
    }

    const actorApprovalRole =
      resolveActorApprovalRole({
        actor,
        staffProfile,
      });

    if (normalizedDecision === "approved") {
      const normalizedPassword = (
        approvalPassword || ""
      ).toString();
      if (!normalizedPassword.trim()) {
        throw new Error(
          "Password is required to approve payment proof",
        );
      }

      const actorWithPassword =
        await User.findById(actor._id)
          .select("passwordHash")
          .session(session);
      if (!actorWithPassword?.passwordHash) {
        throw new Error(
          "Password confirmation is unavailable for this account",
        );
      }

      const isPasswordValid =
        await bcrypt.compare(
          normalizedPassword,
          actorWithPassword.passwordHash,
        );
      if (!isPasswordValid) {
        throw new Error("Incorrect password");
      }
    }

    request.proof.reviewedAt = new Date();
    request.proof.reviewedByUserId = actor._id;
    request.proof.reviewedByRole =
      actorApprovalRole;
    request.proof.reviewDecision =
      normalizedDecision;
    request.proof.reviewNote = (reviewNote || "")
      .toString()
      .trim();

    let order = null;
    if (normalizedDecision === "approved") {
      order = await approveProofAndCreateOrder({
        request,
        actor,
        businessId,
        session,
      });
      request.status = STATUS_APPROVED;
      request.linkedOrderId = order._id;
    } else {
      request.status = STATUS_REJECTED;
    }

    await request.save({ session });

    const message = await createStructuredMessage(
      {
        actor,
        businessId,
        conversationId: request.conversationId,
        body: buildProofReviewedMessage({
          request,
          decision: normalizedDecision,
        }),
        eventType:
          normalizedDecision === "approved"
            ? REQUEST_EVENT_TYPES.PROOF_APPROVED
            : REQUEST_EVENT_TYPES.PROOF_REJECTED,
        eventData: buildRequestEventData(request),
        session,
        context,
      },
    );

    await session.commitTransaction();

    if (order) {
      await Promise.all([
        writeAuditLog({
          businessId,
          actorId: actor._id,
          actorRole: actor.role,
          action: "purchase_request_approved",
          entityType: "purchase_request",
          entityId: request._id,
          message:
            "Payment proof approved and order created",
          changes: {
            status: request.status,
            linkedOrderId: order._id.toString(),
            reviewedByRole: actorApprovalRole,
            reviewedByStaffRole:
              actor.role === "staff"
                ? staffProfile?.staffRole || ""
                : "",
            passwordConfirmed: true,
          },
        }),
        writeAnalyticsEvent({
          businessId,
          actorId: actor._id,
          actorRole: actor.role,
          eventType: "purchase_request_approved",
          entityType: "purchase_request",
          entityId: request._id,
          metadata: {
            linkedOrderId: order._id.toString(),
            paymentSource: "manual_direct",
          },
        }),
        writeAnalyticsEvent({
          businessId,
          actorId: request.customerId,
          actorRole: "customer",
          eventType: "order_created",
          entityType: "order",
          entityId: order._id,
          metadata: {
            totalPrice: order.totalPrice,
            itemCount: order.items?.length || 0,
            status: order.status,
            paymentSource: order.paymentSource,
          },
        }),
      ]);
    } else {
      await writeAuditLog({
        businessId,
        actorId: actor._id,
        actorRole: actor.role,
        action: "purchase_request_rejected",
        entityType: "purchase_request",
        entityId: request._id,
        message: "Payment proof rejected",
        changes: {
          status: request.status,
          reviewedByRole: actorApprovalRole,
          reviewedByStaffRole:
            actor.role === "staff"
              ? staffProfile?.staffRole || ""
              : "",
          reviewNote: request.proof.reviewNote,
        },
      });
    }

    return {
      purchaseRequest: request,
      order,
      message,
    };
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

async function cancelPurchaseRequest({
  requestId,
  actorUserId,
  reason = "",
  context = {},
}) {
  const session = await mongoose.startSession();
  session.startTransaction();

  try {
    const actor = await chatService.loadActor(
      actorUserId,
      context,
    );

    let businessId = null;
    let request = null;
    if (isBuyerRole(actor.role)) {
      request = await PurchaseRequest.findOne({
        _id: requestId,
        customerId: actor._id,
      }).session(session);
    } else if (
      actor.role === "business_owner" ||
      actor.role === "staff"
    ) {
      const businessContext =
        await resolveBusinessContext(
          actorUserId,
          context,
        );
      businessId = businessContext.businessId;
      request = await PurchaseRequest.findOne({
        _id: requestId,
        businessId,
      }).session(session);
    }

    if (!request) {
      throw new Error(
        "Purchase request not found",
      );
    }
    if (isFinalStatus(request.status)) {
      throw new Error(
        "Purchase request is already closed",
      );
    }

    request.status = STATUS_CANCELLED;
    request.cancelledAt = new Date();
    request.cancelledByUserId = actor._id;
    request.cancelledByRole = actor.role;
    request.cancelReason = (reason || "")
      .toString()
      .trim();
    await request.save({ session });

    const message = await createStructuredMessage(
      {
        actor,
        businessId:
          businessId || request.businessId,
        conversationId: request.conversationId,
        body: request.cancelReason
          ? `Purchase request cancelled. Reason: ${request.cancelReason}`
          : "Purchase request cancelled.",
        eventType:
          REQUEST_EVENT_TYPES.REQUEST_CANCELLED,
        eventData: buildRequestEventData(request),
        context,
        session,
      },
    );

    await session.commitTransaction();

    return {
      purchaseRequest: request,
      message,
    };
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

module.exports = {
  REQUEST_EVENT_TYPES,
  createPurchaseRequest,
  createBatchPurchaseRequests,
  getConversationPurchaseRequest,
  attendPurchaseRequestChat,
  exitPurchaseRequestChat,
  updatePurchaseRequestAiControl,
  handleConversationMessageEffects,
  sendInvoice,
  submitPaymentProof,
  reviewPaymentProof,
  cancelPurchaseRequest,
};
