/**
 * backend/scripts/preorder-release.test.js
 * ----------------------------------------
 * WHAT:
 * - Integration tests for POST /business/preorder/reservations/:id/release.
 *
 * WHY:
 * - Ensures released reservations return capacity safely and idempotently.
 *
 * HOW:
 * - Wires real auth + role middleware with the business controller endpoint.
 * - Seeds isolated Mongo fixtures for owner/customer + product/plan/reservation flows.
 */

const path = require("node:path");
const http = require("node:http");
const test = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const debug = require("../utils/debug");
const {
  resolveReusableTestDbUri,
} = require("./_test_db.util");
const {
  requireAuth,
} = require("../middlewares/auth.middleware");
const {
  requireAnyRole,
} = require("../middlewares/requireRole.middleware");
const businessController = require("../controllers/business.controller");
const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const Product = require("../models/Product");
const ProductionPlan = require("../models/ProductionPlan");
const PreorderReservation = require("../models/PreorderReservation");

const TEST_LOG_TAG =
  "PREORDER_RELEASE_TEST";
const TEST_DB_NAME =
  "preorder_release_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "businessassets",
  "products",
  "productionplans",
  "preorderreservations",
];
const TEST_DB_NAME_PATTERN =
  /^(preorder_release_test|prl_[a-z0-9]+_[a-z0-9]+)$/;
const RELEASE_ROUTE_TEMPLATE =
  "/business/preorder/reservations/:id/release";
const OWNER_ROLE = "business_owner";
const CUSTOMER_ROLE = "customer";
const HTTP_OK = 200;
const HTTP_NOT_FOUND = 404;
const HTTP_CONFLICT = 409;

const RESET_MODELS = [
  PreorderReservation,
  ProductionPlan,
  Product,
  BusinessAsset,
  User,
];

let server = null;
let testDbUri = "";

function buildReleaseApp() {
  const app = express();
  app.use(express.json());

  app.post(
    RELEASE_ROUTE_TEMPLATE,
    requireAuth,
    requireAnyRole([
      CUSTOMER_ROLE,
      OWNER_ROLE,
    ]),
    businessController.releasePreorderReservation,
  );

  return app;
}

function issueToken({
  userId,
  role,
}) {
  return jwt.sign(
    {
      sub: userId.toString(),
      role,
    },
    process.env.JWT_SECRET,
    {
      expiresIn: "1h",
    },
  );
}

async function requestJson({
  routePath,
  token,
}) {
  return new Promise((resolve, reject) => {
    const body = "{}";
    const request = http.request(
      {
        method: "POST",
        hostname: "127.0.0.1",
        port: server.address().port,
        path: routePath,
        headers: {
          "Content-Type":
            "application/json",
          "Content-Length":
            Buffer.byteLength(body),
          Authorization: `Bearer ${token}`,
        },
      },
      (response) => {
        let raw = "";
        response.on("data", (chunk) => {
          raw += chunk.toString();
        });
        response.on("end", () => {
          const parsed =
            raw.trim().length > 0 ?
              JSON.parse(raw)
            : {};
          resolve({
            statusCode:
              response.statusCode || 0,
            body: parsed,
          });
        });
      },
    );

    request.on("error", reject);
    request.write(body);
    request.end();
  });
}

async function postRelease({
  token,
  reservationId,
}) {
  return requestJson({
    routePath: `/business/preorder/reservations/${reservationId}/release`,
    token,
  });
}

async function createUser({
  id,
  businessId,
  role,
  email,
}) {
  return User.create({
    _id: id,
    name: `${role}-${id.toString().slice(-6)}`,
    email,
    passwordHash: "hashed_for_tests",
    role,
    businessId,
  });
}

async function createAsset({
  id,
  businessId,
  createdBy,
}) {
  return BusinessAsset.create({
    _id: id,
    businessId,
    assetType: "equipment",
    ownershipType: "owned",
    assetClass: "current",
    name: `asset-${id.toString().slice(-6)}`,
    createdBy,
  });
}

async function createProduct({
  id,
  businessId,
  ownerId,
  preorderReservedQuantity,
}) {
  return Product.create({
    _id: id,
    businessId,
    createdBy: ownerId,
    updatedBy: ownerId,
    name: `Rice ${id.toString().slice(-6)}`,
    description: "release test product",
    price: 1000,
    stock: 0,
    isActive: false,
    productionState: "available_for_preorder",
    productionPlanId: null,
    conservativeYieldQuantity: 20,
    conservativeYieldUnit: "bags",
    preorderEnabled: true,
    preorderStartDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    preorderCapQuantity: 30,
    preorderReservedQuantity,
    preorderReleasedQuantity: 0,
  });
}

async function createPlan({
  id,
  businessId,
  estateAssetId,
  productId,
  ownerId,
}) {
  return ProductionPlan.create({
    _id: id,
    businessId,
    estateAssetId,
    productId,
    title: "Release Plan",
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "active",
    createdBy: ownerId,
    notes: "release test plan",
    aiGenerated: false,
    domainContext: "farm",
  });
}

async function createReservation({
  id,
  businessId,
  planId,
  userId,
  quantity,
  status,
}) {
  return PreorderReservation.create({
    _id: id,
    businessId,
    planId,
    userId,
    quantity,
    status,
    expiresAt: new Date(
      "2026-04-01T00:00:00.000Z",
    ),
  });
}

async function seedReleaseScenario({
  reservationStatus = "reserved",
  reservedQuantity = 5,
  reservationQuantity = 3,
}) {
  const ownerId =
    new mongoose.Types.ObjectId();
  const businessId = ownerId;
  const customerAId =
    new mongoose.Types.ObjectId();
  const customerBId =
    new mongoose.Types.ObjectId();
  const estateAssetId =
    new mongoose.Types.ObjectId();
  const productId =
    new mongoose.Types.ObjectId();
  const planId =
    new mongoose.Types.ObjectId();
  const reservationId =
    new mongoose.Types.ObjectId();

  await createUser({
    id: ownerId,
    businessId,
    role: OWNER_ROLE,
    email: `owner_${ownerId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: customerAId,
    businessId,
    role: CUSTOMER_ROLE,
    email: `customer_a_${customerAId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: customerBId,
    businessId,
    role: CUSTOMER_ROLE,
    email: `customer_b_${customerBId.toString().slice(-6)}@test.local`,
  });

  await createAsset({
    id: estateAssetId,
    businessId,
    createdBy: ownerId,
  });
  await createProduct({
    id: productId,
    businessId,
    ownerId,
    preorderReservedQuantity:
      reservedQuantity,
  });
  await createPlan({
    id: planId,
    businessId,
    estateAssetId,
    productId,
    ownerId,
  });
  await createReservation({
    id: reservationId,
    businessId,
    planId,
    userId: customerAId,
    quantity: reservationQuantity,
    status: reservationStatus,
  });

  return {
    ownerId,
    customerAId,
    customerBId,
    productId,
    reservationId,
    ownerToken: issueToken({
      userId: ownerId,
      role: OWNER_ROLE,
    }),
    customerAToken: issueToken({
      userId: customerAId,
      role: CUSTOMER_ROLE,
    }),
    customerBToken: issueToken({
      userId: customerBId,
      role: CUSTOMER_ROLE,
    }),
  };
}

async function purgeTestData() {
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
}

test.before(async () => {
  if (!process.env.JWT_SECRET) {
    throw new Error(
      "JWT_SECRET is required for preorder release tests",
    );
  }
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
    "Connecting release test database",
    {
      hasMongoUri: Boolean(
        process.env.MONGO_URI,
      ),
    },
  );
  await mongoose.connect(testDbUri);

  const app = buildReleaseApp();
  await new Promise((resolve) => {
    server = app.listen(0, resolve);
  });
});

test.after(async () => {
  if (server) {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }
  await purgeTestData();
  await mongoose.disconnect();
});

test.beforeEach(async () => {
  await purgeTestData();
});

test("release succeeds and decrements reserved quantity", async () => {
  const scenario = await seedReleaseScenario(
    {
      reservationStatus: "reserved",
      reservedQuantity: 5,
      reservationQuantity: 3,
    },
  );

  const response = await postRelease({
    token: scenario.ownerToken,
    reservationId:
      scenario.reservationId,
  });

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.idempotent,
    false,
  );
  assert.equal(
    response.body.preorderSummary.reserved,
    2,
  );

  const updatedReservation =
    await PreorderReservation.findById(
      scenario.reservationId,
    ).lean();
  assert.equal(
    updatedReservation.status,
    "released",
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    2,
  );
});

test("release is idempotent when reservation already released", async () => {
  const scenario = await seedReleaseScenario(
    {
      reservationStatus: "reserved",
      reservedQuantity: 4,
      reservationQuantity: 2,
    },
  );

  const first = await postRelease({
    token: scenario.ownerToken,
    reservationId:
      scenario.reservationId,
  });
  const second = await postRelease({
    token: scenario.ownerToken,
    reservationId:
      scenario.reservationId,
  });

  assert.equal(
    first.statusCode,
    HTTP_OK,
  );
  assert.equal(
    second.statusCode,
    HTTP_OK,
  );
  assert.equal(
    second.body.idempotent,
    true,
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    2,
  );
});

test("release rejects non-reserved statuses", async () => {
  const scenario = await seedReleaseScenario(
    {
      reservationStatus: "expired",
      reservedQuantity: 4,
      reservationQuantity: 2,
    },
  );

  const response = await postRelease({
    token: scenario.ownerToken,
    reservationId:
      scenario.reservationId,
  });

  assert.equal(
    response.statusCode,
    HTTP_CONFLICT,
  );
  assert.equal(
    response.body.error,
    "Only reserved pre-order reservations can be released",
  );

  const reservation =
    await PreorderReservation.findById(
      scenario.reservationId,
    ).lean();
  assert.equal(
    reservation.status,
    "expired",
  );
});

test("customer cannot release another customer's reservation", async () => {
  const scenario = await seedReleaseScenario(
    {
      reservationStatus: "reserved",
      reservedQuantity: 5,
      reservationQuantity: 1,
    },
  );

  const response = await postRelease({
    token: scenario.customerBToken,
    reservationId:
      scenario.reservationId,
  });

  assert.equal(
    response.statusCode,
    HTTP_NOT_FOUND,
  );
  assert.equal(
    response.body.error,
    "Pre-order reservation not found",
  );

  const reservation =
    await PreorderReservation.findById(
      scenario.reservationId,
    ).lean();
  assert.equal(
    reservation.status,
    "reserved",
  );
});
