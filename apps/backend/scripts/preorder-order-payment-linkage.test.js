/**
 * backend/scripts/preorder-order-payment-linkage.test.js
 * ------------------------------------------------------
 * WHAT:
 * - Integration tests for reservation linkage across order + payment webhook flow.
 *
 * WHY:
 * - Ensures reservationId is persisted on orders and confirmed on payment success.
 *
 * HOW:
 * - Seeds isolated Mongo fixtures and exercises real services end-to-end.
 */

const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const mongoose = require("mongoose");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const debug = require("../utils/debug");
const {
  resolveReusableTestDbUri,
} = require("./_test_db.util");
const orderService = require("../services/order.service");
const paystackService = require("../services/paystack.service");
const paymentService = require("../services/payment.service");

const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const Product = require("../models/Product");
const ProductionPlan = require("../models/ProductionPlan");
const PreorderReservation = require("../models/PreorderReservation");
const Order = require("../models/Order");
const Payment = require("../models/Payment");
const InventoryEvent = require("../models/InventoryEvent");
const AuditLog = require("../models/AuditLog");
const BusinessAnalyticsEvent = require("../models/BusinessAnalyticsEvent");

const TEST_LOG_TAG =
  "PREORDER_ORDER_PAYMENT_LINKAGE_TEST";
const TEST_DB_NAME =
  "preorder_order_payment_linkage_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "businessassets",
  "products",
  "productionplans",
  "preorderreservations",
  "orders",
  "payments",
  "inventoryevents",
  "auditlogs",
  "businessanalyticsevents",
];
const TEST_DB_NAME_PATTERN =
  /^(preorder_order_payment_linkage_test|popl_[a-z0-9]+_[a-z0-9]+)$/;
const OWNER_ROLE = "business_owner";
const CUSTOMER_ROLE = "customer";

const RESET_MODELS = [
  Payment,
  InventoryEvent,
  Order,
  PreorderReservation,
  ProductionPlan,
  Product,
  BusinessAsset,
  AuditLog,
  BusinessAnalyticsEvent,
  User,
];

let testDbUri = "";

async function purgeTestData() {
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
}

async function seedLinkedPreorderScenario({
  reservationQuantity = 3,
  productStock = 20,
} = {}) {
  const ownerId =
    new mongoose.Types.ObjectId();
  const businessId = ownerId;
  const customerId =
    new mongoose.Types.ObjectId();
  const estateAssetId =
    new mongoose.Types.ObjectId();
  const productId =
    new mongoose.Types.ObjectId();
  const planId =
    new mongoose.Types.ObjectId();
  const reservationId =
    new mongoose.Types.ObjectId();

  await User.create({
    _id: ownerId,
    name: `owner-${ownerId.toString().slice(-6)}`,
    email: `owner_${ownerId.toString().slice(-6)}@test.local`,
    passwordHash: "hashed_for_tests",
    role: OWNER_ROLE,
    businessId,
  });

  await User.create({
    _id: customerId,
    name: `customer-${customerId.toString().slice(-6)}`,
    email: `customer_${customerId.toString().slice(-6)}@test.local`,
    passwordHash: "hashed_for_tests",
    role: CUSTOMER_ROLE,
    businessId,
    homeAddress: {
      houseNumber: "12",
      street: "Main Road",
      city: "Lagos",
      state: "Lagos",
      country: "NG",
      isVerified: true,
      verifiedAt: new Date(
        "2026-03-01T00:00:00.000Z",
      ),
      verificationSource: "test",
    },
  });

  await BusinessAsset.create({
    _id: estateAssetId,
    businessId,
    assetType: "equipment",
    ownershipType: "owned",
    assetClass: "current",
    name: `estate-${estateAssetId.toString().slice(-6)}`,
    createdBy: ownerId,
  });

  await Product.create({
    _id: productId,
    businessId,
    createdBy: ownerId,
    updatedBy: ownerId,
    name: `Rice ${productId.toString().slice(-6)}`,
    description: "order-payment linkage test product",
    price: 1500,
    stock: productStock,
    isActive: true,
    productionState: "available_for_preorder",
    productionPlanId: planId,
    conservativeYieldQuantity: 20,
    conservativeYieldUnit: "bags",
    preorderEnabled: true,
    preorderStartDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    preorderCapQuantity: 20,
    preorderReservedQuantity:
      reservationQuantity,
    preorderReleasedQuantity: 0,
  });

  await ProductionPlan.create({
    _id: planId,
    businessId,
    estateAssetId,
    productId,
    title: "Order Payment Linkage Plan",
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "active",
    createdBy: ownerId,
    notes: "order payment linkage test plan",
    aiGenerated: false,
    domainContext: "farm",
  });

  await PreorderReservation.create({
    _id: reservationId,
    businessId,
    planId,
    userId: customerId,
    quantity: reservationQuantity,
    status: "reserved",
    expiresAt: new Date(
      "2026-04-01T00:00:00.000Z",
    ),
  });

  return {
    ownerId,
    businessId,
    customerId,
    productId,
    planId,
    reservationId,
    reservationQuantity,
  };
}

test.before(async () => {
  testDbUri =
    await resolveReusableTestDbUri({
      baseUri: process.env.MONGO_URI,
      preferredDbName: TEST_DB_NAME,
      requiredCollections:
        TEST_DB_REQUIRED_COLLECTIONS,
      dbNamePattern:
        TEST_DB_NAME_PATTERN,
    });
  process.env.PAYSTACK_SECRET_KEY =
    process.env.PAYSTACK_SECRET_KEY ||
    "sk_test_linkage_dummy";

  debug(
    TEST_LOG_TAG,
    "Connecting linkage test database",
    {
      hasMongoUri: Boolean(
        process.env.MONGO_URI,
      ),
    },
  );
  await mongoose.connect(testDbUri);
});

test.after(async () => {
  await purgeTestData();
  await mongoose.disconnect();
  debug(
    TEST_LOG_TAG,
    "Linkage tests disconnected",
    {
      disconnected: true,
    },
  );
});

test.beforeEach(async () => {
  await purgeTestData();
});

test("order stores reservationId and paystack init forwards metadata", async () => {
  const scenario =
    await seedLinkedPreorderScenario();
  const order = await orderService.createOrder(
    scenario.customerId,
    [
      {
        productId: scenario.productId,
        quantity:
          scenario.reservationQuantity,
      },
    ],
    { source: "home" },
    scenario.reservationId,
  );

  assert.equal(
    order.reservationId.toString(),
    scenario.reservationId.toString(),
  );

  let capturedPayload = null;
  const originalFetch = global.fetch;
  global.fetch = async (_url, options) => {
    capturedPayload = JSON.parse(
      options?.body || "{}",
    );
    return {
      ok: true,
      json: async () => ({
        status: true,
        data: {
          authorization_url:
            "https://paystack.test/checkout",
          reference:
            "plink_ref_001",
          access_code:
            "plink_access_001",
        },
      }),
    };
  };

  try {
    const initResult =
      await paystackService.initPaystackTransaction(
        {
          orderId: order._id.toString(),
          userId:
            scenario.customerId.toString(),
        },
      );

    assert.equal(
      capturedPayload?.metadata?.orderId,
      order._id.toString(),
    );
    assert.equal(
      capturedPayload?.metadata
        ?.reservationId,
      scenario.reservationId.toString(),
    );
    assert.equal(
      initResult.reference,
      "plink_ref_001",
    );
  } finally {
    global.fetch = originalFetch;
  }
});

test("payment success confirms linked reservation and remains idempotent", async () => {
  const scenario =
    await seedLinkedPreorderScenario();
  const order = await orderService.createOrder(
    scenario.customerId,
    [
      {
        productId: scenario.productId,
        quantity:
          scenario.reservationQuantity,
      },
    ],
    { source: "home" },
    scenario.reservationId,
  );

  const reference = `plink_ref_${Date.now().toString(36)}`;
  const event = {
    event: "charge.success",
    data: {
      id: "trx_plink_001",
      reference,
      amount: order.totalPrice,
      currency: "NGN",
      // WHY: Fallback to order.reservationId linkage must still confirm reservation.
      metadata: {
        orderId: order._id.toString(),
      },
    },
  };

  const firstRun =
    await paymentService.processPaystackEvent(
      event,
    );
  const secondRun =
    await paymentService.processPaystackEvent(
      event,
    );

  assert.equal(firstRun.ok, true);
  assert.equal(firstRun.applied, true);
  assert.equal(secondRun.ok, true);
  assert.equal(
    secondRun.idempotent,
    true,
  );

  const updatedOrder =
    await Order.findById(order._id).lean();
  const updatedReservation =
    await PreorderReservation.findById(
      scenario.reservationId,
    ).lean();
  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  const payment = await Payment.findOne({
    provider: "paystack",
    reference,
  }).lean();

  assert.equal(
    updatedOrder.status,
    "paid",
  );
  assert.equal(
    updatedReservation.status,
    "confirmed",
  );
  assert.equal(
    updatedProduct.stock,
    20 -
      scenario.reservationQuantity,
  );
  assert.ok(payment?.processedAt);
});

test("createOrder rejects reservation quantity mismatch", async () => {
  const scenario =
    await seedLinkedPreorderScenario({
      reservationQuantity: 3,
    });

  await assert.rejects(
    () =>
      orderService.createOrder(
        scenario.customerId,
        [
          {
            productId:
              scenario.productId,
            quantity: 2,
          },
        ],
        { source: "home" },
        scenario.reservationId,
      ),
    /Order quantity must match linked pre-order reservation quantity/,
  );
});
