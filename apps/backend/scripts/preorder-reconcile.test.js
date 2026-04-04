/**
 * backend/scripts/preorder-reconcile.test.js
 * ------------------------------------------
 * WHAT:
 * - Integration tests for expired pre-order reservation reconciliation.
 *
 * WHY:
 * - Ensures reserved counters are released deterministically when holds expire.
 *
 * HOW:
 * - Uses isolated Mongo test DB with direct service invocation for deterministic checks.
 * - Seeds realistic business + plan + product + reservation fixtures per test.
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
const {
  reconcileExpiredPreorderReservations,
} = require("../services/preorder_reservation_reconciler.service");
const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const Product = require("../models/Product");
const ProductionPlan = require("../models/ProductionPlan");
const PreorderReservation = require("../models/PreorderReservation");

const TEST_LOG_TAG =
  "PREORDER_RECONCILE_TEST";
const TEST_DB_NAME =
  "preorder_reconcile_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "businessassets",
  "products",
  "productionplans",
  "preorderreservations",
];
const TEST_DB_NAME_PATTERN =
  /^(preorder_reconcile_test|prc_[a-z0-9]+_[a-z0-9]+)$/;
const OWNER_ROLE = "business_owner";
const RECONCILE_NOW = new Date(
  "2026-03-25T09:00:00.000Z",
);
const PAST_EXPIRES_AT = new Date(
  "2026-03-25T08:00:00.000Z",
);
const FUTURE_EXPIRES_AT = new Date(
  "2026-03-25T18:00:00.000Z",
);

const RESET_MODELS = [
  PreorderReservation,
  ProductionPlan,
  Product,
  BusinessAsset,
  User,
];

let testDbUri = "";

async function purgeTestData() {
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
}

async function seedBusinessWithReservation({
  reservedQuantity = 5,
  reservationQuantity = 2,
  expiresAt = PAST_EXPIRES_AT,
  reservationStatus = "reserved",
}) {
  const ownerId =
    new mongoose.Types.ObjectId();
  const businessId = ownerId;
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
    description: "reconcile test product",
    price: 1000,
    stock: 0,
    isActive: false,
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
      reservedQuantity,
    preorderReleasedQuantity: 0,
  });

  await ProductionPlan.create({
    _id: planId,
    businessId,
    estateAssetId,
    productId,
    title: "Reconcile Plan",
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "active",
    createdBy: ownerId,
    notes: "reconcile test plan",
    aiGenerated: false,
    domainContext: "farm",
  });

  await PreorderReservation.create({
    _id: reservationId,
    businessId,
    planId,
    userId: ownerId,
    quantity: reservationQuantity,
    status: reservationStatus,
    expiresAt,
  });

  return {
    businessId,
    productId,
    planId,
    reservationId,
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
  debug(
    TEST_LOG_TAG,
    "Connecting reconcile test database",
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
    "Reconcile tests disconnected",
    {
      disconnected: true,
    },
  );
});

test.beforeEach(async () => {
  await purgeTestData();
});

test("expired reservation decrements reserved quantity (tenant-scoped)", async () => {
  const scoped =
    await seedBusinessWithReservation({
      reservedQuantity: 6,
      reservationQuantity: 2,
      expiresAt: PAST_EXPIRES_AT,
    });
  const outsideScope =
    await seedBusinessWithReservation({
      reservedQuantity: 5,
      reservationQuantity: 3,
      expiresAt: PAST_EXPIRES_AT,
    });

  debug(
    TEST_LOG_TAG,
    "Running scoped reconcile",
    {
      scopedBusinessId:
        scoped.businessId.toString(),
    },
  );

  const summary =
    await reconcileExpiredPreorderReservations(
      {
        businessId: scoped.businessId,
        now: RECONCILE_NOW,
      },
    );

  assert.equal(summary.errorCount, 0);
  assert.equal(summary.expiredCount, 1);

  const scopedProduct =
    await Product.findById(
      scoped.productId,
    ).lean();
  assert.equal(
    scopedProduct.preorderReservedQuantity,
    4,
  );

  const scopedReservation =
    await PreorderReservation.findById(
      scoped.reservationId,
    ).lean();
  assert.equal(
    scopedReservation.status,
    "expired",
  );
  assert.equal(
    new Date(
      scopedReservation.expiredAt,
    ).toISOString(),
    RECONCILE_NOW.toISOString(),
  );

  const outsideProduct =
    await Product.findById(
      outsideScope.productId,
    ).lean();
  const outsideReservation =
    await PreorderReservation.findById(
      outsideScope.reservationId,
    ).lean();
  assert.equal(
    outsideProduct.preorderReservedQuantity,
    5,
  );
  assert.equal(
    outsideReservation.status,
    "reserved",
  );
});

test("running reconcile twice is idempotent", async () => {
  const scenario =
    await seedBusinessWithReservation({
      reservedQuantity: 5,
      reservationQuantity: 2,
      expiresAt: PAST_EXPIRES_AT,
    });

  const firstRun =
    await reconcileExpiredPreorderReservations(
      {
        businessId: scenario.businessId,
        now: RECONCILE_NOW,
      },
    );
  const secondRun =
    await reconcileExpiredPreorderReservations(
      {
        businessId: scenario.businessId,
        now: RECONCILE_NOW,
      },
    );

  assert.equal(firstRun.expiredCount, 1);
  assert.equal(secondRun.expiredCount, 0);
  assert.equal(secondRun.errorCount, 0);

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    3,
  );

  const updatedReservation =
    await PreorderReservation.findById(
      scenario.reservationId,
    ).lean();
  assert.equal(
    updatedReservation.status,
    "expired",
  );
});

test("non-expired reservation remains untouched", async () => {
  const scenario =
    await seedBusinessWithReservation({
      reservedQuantity: 4,
      reservationQuantity: 1,
      expiresAt: FUTURE_EXPIRES_AT,
    });

  const summary =
    await reconcileExpiredPreorderReservations(
      {
        businessId: scenario.businessId,
        now: RECONCILE_NOW,
      },
    );

  assert.equal(summary.expiredCount, 0);
  assert.equal(summary.errorCount, 0);

  const product =
    await Product.findById(
      scenario.productId,
    ).lean();
  const reservation =
    await PreorderReservation.findById(
      scenario.reservationId,
    ).lean();

  assert.equal(
    product.preorderReservedQuantity,
    4,
  );
  assert.equal(
    reservation.status,
    "reserved",
  );
  assert.equal(
    reservation.expiredAt,
    null,
  );
});
