/**
 * backend/scripts/preorder-monitoring.test.js
 * -------------------------------------------
 * WHAT:
 * - Integration tests for GET /business/preorder/reservations.
 *
 * WHY:
 * - Ensures owner-only monitoring remains tenant-scoped with safe filtering.
 *
 * HOW:
 * - Wires real auth + role middleware with business controller route.
 * - Seeds isolated Mongo fixtures for two businesses and mixed reservation statuses.
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
  "PREORDER_MONITORING_TEST";
const TEST_DB_NAME =
  "preorder_monitoring_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "businessassets",
  "products",
  "productionplans",
  "preorderreservations",
];
const TEST_DB_NAME_PATTERN =
  /^(preorder_monitoring_test|prm_[a-z0-9]+_[a-z0-9]+)$/;
const OWNER_ROLE = "business_owner";
const STAFF_ROLE = "staff";
const ROUTE_TEMPLATE =
  "/business/preorder/reservations";
const HTTP_OK = 200;
const HTTP_BAD_REQUEST = 400;
const HTTP_FORBIDDEN = 403;

const RESET_MODELS = [
  PreorderReservation,
  ProductionPlan,
  Product,
  BusinessAsset,
  User,
];

let server = null;
let testDbUri = "";

function buildMonitoringApp() {
  const app = express();
  app.use(express.json());

  app.get(
    ROUTE_TEMPLATE,
    requireAuth,
    requireAnyRole([
      OWNER_ROLE,
    ]),
    businessController.listPreorderReservations,
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
    const request = http.request(
      {
        method: "GET",
        hostname: "127.0.0.1",
        port: server.address().port,
        path: routePath,
        headers: {
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
    request.end();
  });
}

async function getReservations({
  token,
  status,
  page,
  limit,
}) {
  const query = new URLSearchParams();
  if (status) {
    query.set("status", status);
  }
  if (page != null) {
    query.set("page", page.toString());
  }
  if (limit != null) {
    query.set("limit", limit.toString());
  }
  const suffix = query.toString();
  const routePath =
    suffix ?
      `${ROUTE_TEMPLATE}?${suffix}`
    : ROUTE_TEMPLATE;
  return requestJson({
    routePath,
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
  planId,
}) {
  return Product.create({
    _id: id,
    businessId,
    createdBy: ownerId,
    updatedBy: ownerId,
    name: `Rice ${id.toString().slice(-6)}`,
    description: "monitoring test product",
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
    preorderCapQuantity: 30,
    preorderReservedQuantity: 5,
    preorderReleasedQuantity: 0,
  });
}

async function createPlan({
  id,
  businessId,
  estateAssetId,
  productId,
  ownerId,
  title,
}) {
  return ProductionPlan.create({
    _id: id,
    businessId,
    estateAssetId,
    productId,
    title,
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "active",
    createdBy: ownerId,
    notes: "monitoring plan",
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
  createdAt,
}) {
  return PreorderReservation.create({
    _id: id,
    businessId,
    planId,
    userId,
    quantity,
    status,
    expiresAt: new Date(
      "2026-03-20T12:00:00.000Z",
    ),
    createdAt,
  });
}

async function purgeTestData() {
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
}

async function seedBusinessReservations() {
  const ownerId =
    new mongoose.Types.ObjectId();
  const staffId =
    new mongoose.Types.ObjectId();
  const businessId = ownerId;
  const estateAssetId =
    new mongoose.Types.ObjectId();
  const productId =
    new mongoose.Types.ObjectId();
  const planId =
    new mongoose.Types.ObjectId();

  await createUser({
    id: ownerId,
    businessId,
    role: OWNER_ROLE,
    email: `owner_${ownerId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: staffId,
    businessId,
    role: STAFF_ROLE,
    email: `staff_${staffId.toString().slice(-6)}@test.local`,
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
    planId,
  });
  await createPlan({
    id: planId,
    businessId,
    estateAssetId,
    productId,
    ownerId,
    title: "Monitoring Plan",
  });

  const reservationStatuses = [
    "reserved",
    "confirmed",
    "released",
    "expired",
  ];
  for (
    let index = 0;
    index < reservationStatuses.length;
    index += 1
  ) {
    await createReservation({
      id: new mongoose.Types.ObjectId(),
      businessId,
      planId,
      userId: ownerId,
      quantity: index + 1,
      status:
        reservationStatuses[index],
      createdAt: new Date(
        `2026-03-1${index}T08:00:00.000Z`,
      ),
    });
  }

  // WHY: Different business row proves tenant isolation.
  const outsideOwnerId =
    new mongoose.Types.ObjectId();
  const outsideBusinessId =
    outsideOwnerId;
  const outsideEstateId =
    new mongoose.Types.ObjectId();
  const outsideProductId =
    new mongoose.Types.ObjectId();
  const outsidePlanId =
    new mongoose.Types.ObjectId();

  await createUser({
    id: outsideOwnerId,
    businessId: outsideBusinessId,
    role: OWNER_ROLE,
    email: `owner_${outsideOwnerId.toString().slice(-6)}@test.local`,
  });
  await createAsset({
    id: outsideEstateId,
    businessId: outsideBusinessId,
    createdBy: outsideOwnerId,
  });
  await createProduct({
    id: outsideProductId,
    businessId: outsideBusinessId,
    ownerId: outsideOwnerId,
    planId: outsidePlanId,
  });
  await createPlan({
    id: outsidePlanId,
    businessId: outsideBusinessId,
    estateAssetId: outsideEstateId,
    productId: outsideProductId,
    ownerId: outsideOwnerId,
    title: "Outside Plan",
  });
  await createReservation({
    id: new mongoose.Types.ObjectId(),
    businessId: outsideBusinessId,
    planId: outsidePlanId,
    userId: outsideOwnerId,
    quantity: 9,
    status: "reserved",
    createdAt: new Date(
      "2026-03-19T08:00:00.000Z",
    ),
  });

  return {
    ownerId,
    staffId,
  };
}

test.before(async () => {
  testDbUri = await resolveReusableTestDbUri(
    {
      baseUri: process.env.MONGO_URI,
      preferredDbName: TEST_DB_NAME,
      requiredCollections:
        TEST_DB_REQUIRED_COLLECTIONS,
      dbNamePattern:
        TEST_DB_NAME_PATTERN,
    },
  );
  debug(
    TEST_LOG_TAG,
    "Connecting monitoring test database",
    {
      hasMongoUri: Boolean(
        process.env.MONGO_URI,
      ),
      testDbUri,
    },
  );
  await mongoose.connect(testDbUri);
  server = buildMonitoringApp().listen(0);
});

test.after(async () => {
  if (server) {
    await new Promise((resolve) =>
      server.close(resolve),
    );
    server = null;
  }
  await purgeTestData();
  await mongoose.disconnect();
  debug(
    TEST_LOG_TAG,
    "Monitoring tests disconnected",
    {
      disconnected: true,
    },
  );
});

test.beforeEach(async () => {
  await purgeTestData();
});

test("owner lists reservations with status filter and tenant isolation", async () => {
  const seed =
    await seedBusinessReservations();
  const ownerToken = issueToken({
    userId: seed.ownerId,
    role: OWNER_ROLE,
  });

  const response =
    await getReservations({
      token: ownerToken,
      status: "reserved",
      page: 1,
      limit: 10,
    });

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.message,
    "Pre-order reservations fetched successfully",
  );
  assert.equal(
    response.body.pagination.total,
    1,
  );
  assert.equal(
    response.body.reservations.length,
    1,
  );
  assert.equal(
    response.body.reservations[0].status,
    "reserved",
  );
  assert.equal(
    response.body.summary.total,
    4,
  );
  assert.equal(
    response.body.summary.reserved,
    1,
  );
  assert.equal(
    response.body.summary.confirmed,
    1,
  );
  assert.equal(
    response.body.summary.released,
    1,
  );
  assert.equal(
    response.body.summary.expired,
    1,
  );
});

test("invalid status filter returns 400", async () => {
  const seed =
    await seedBusinessReservations();
  const ownerToken = issueToken({
    userId: seed.ownerId,
    role: OWNER_ROLE,
  });

  const response =
    await getReservations({
      token: ownerToken,
      status: "bad_status",
      page: 1,
      limit: 20,
    });

  assert.equal(
    response.statusCode,
    HTTP_BAD_REQUEST,
  );
  assert.equal(
    response.body.error,
    "Reservation status filter is invalid",
  );
});

test("staff role is forbidden by route policy", async () => {
  const seed =
    await seedBusinessReservations();
  const staffToken = issueToken({
    userId: seed.staffId,
    role: STAFF_ROLE,
  });

  const response =
    await getReservations({
      token: staffToken,
      page: 1,
      limit: 20,
    });

  assert.equal(
    response.statusCode,
    HTTP_FORBIDDEN,
  );
});

