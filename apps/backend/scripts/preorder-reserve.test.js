/**
 * backend/scripts/preorder-reserve.test.js
 * ----------------------------------------
 * WHAT:
 * - Integration tests for POST /business/production/plans/:planId/preorder/reserve.
 *
 * WHY:
 * - Verifies atomic cap enforcement and reservation recording safety.
 *
 * HOW:
 * - Uses Node test runner with minimal Express route wiring and real auth middleware.
 * - Uses isolated Mongo database + collection cleanup for deterministic outcomes.
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
const TaskProgress = require("../models/TaskProgress");
const PreorderReservation = require("../models/PreorderReservation");

const TEST_LOG_TAG =
  "PREORDER_RESERVE_TEST";
const TEST_DB_NAME =
  "preorder_reserve_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "businessassets",
  "products",
  "productionplans",
  "preorderreservations",
  "taskprogresses",
];
const TEST_DB_NAME_PATTERN =
  /^(preorder_reserve_test|pr_[a-z0-9]+_[a-z0-9]+)$/;
const OWNER_ROLE = "business_owner";
const ROUTE_TEMPLATE =
  "/business/production/plans/:planId/preorder/reserve";
const REQUEST_DATE = "2026-03-20";
const HTTP_OK = 200;
const HTTP_BAD_REQUEST = 400;
const HTTP_CONFLICT = 409;

const RESET_MODELS = [
  PreorderReservation,
  TaskProgress,
  ProductionPlan,
  Product,
  BusinessAsset,
  User,
];

let server;
let testDbUri = "";

function buildApp() {
  const app = express();
  app.use(express.json());

  app.post(
    ROUTE_TEMPLATE,
    requireAuth,
    requireAnyRole([
      "customer",
      OWNER_ROLE,
    ]),
    businessController.reserveProductionPlanPreorder,
  );

  return app;
}

function issueOwnerToken(ownerId) {
  return jwt.sign(
    {
      sub: ownerId.toString(),
      role: OWNER_ROLE,
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
  payload,
}) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(
      payload || {},
    );
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

async function postReserve({
  planId,
  token,
  quantity,
}) {
  return requestJson({
    routePath: `/business/production/plans/${planId}/preorder/reserve`,
    token,
    payload: {
      quantity,
      requestDate: REQUEST_DATE,
    },
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
  preorderEnabled,
  preorderCapQuantity,
  preorderReservedQuantity,
}) {
  return Product.create({
    _id: id,
    businessId,
    createdBy: ownerId,
    updatedBy: ownerId,
    name: `Rice ${id.toString().slice(-6)}`,
    description: "preorder product",
    price: 1000,
    stock: 0,
    isActive: false,
    productionState: "available_for_preorder",
    productionPlanId: null,
    conservativeYieldQuantity: 20,
    conservativeYieldUnit: "bags",
    preorderEnabled,
    preorderStartDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    preorderCapQuantity,
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
    title: "Preorder Plan",
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "active",
    createdBy: ownerId,
    notes: "preorder reservation test",
    aiGenerated: false,
    domainContext: "farm",
  });
}

async function createTaskProgress({
  planId,
  createdBy,
  approved = false,
  actualPlots = 4,
  expectedPlots = 4,
}) {
  const now = new Date(
    "2026-03-30T10:00:00.000Z",
  );
  return TaskProgress.create({
    taskId:
      new mongoose.Types.ObjectId(),
    planId,
    staffId:
      new mongoose.Types.ObjectId(),
    workDate: now,
    expectedPlots,
    actualPlots,
    delayReason: "none",
    notes: "",
    createdBy,
    approvedBy:
      approved ? createdBy : null,
    approvedAt:
      approved ? now : null,
  });
}

async function seedScenario({
  preorderEnabled = true,
  preorderCapQuantity = 10,
  preorderReservedQuantity = 0,
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

  await createUser({
    id: ownerId,
    businessId,
    role: OWNER_ROLE,
    email: `owner_${ownerId.toString().slice(-6)}@test.local`,
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
    preorderEnabled,
    preorderCapQuantity,
    preorderReservedQuantity,
  });
  await createPlan({
    id: planId,
    businessId,
    estateAssetId,
    productId,
    ownerId,
  });

  return {
    ownerId,
    productId,
    planId,
    token: issueOwnerToken(ownerId),
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
      "JWT_SECRET is required for preorder reservation tests",
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
    "Connecting reservation test database",
    {
      hasMongoUri: Boolean(
        process.env.MONGO_URI,
      ),
    },
  );
  await mongoose.connect(testDbUri);

  const app = buildApp();
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
  debug(
    TEST_LOG_TAG,
    "Reservation tests disconnected",
    {
      disconnected: true,
    },
  );
});

test.beforeEach(async () => {
  await purgeTestData();
});

test("reserve succeeds within cap", async () => {
  const scenario = await seedScenario({
    preorderEnabled: true,
    preorderCapQuantity: 10,
    preorderReservedQuantity: 2,
  });
  const response = await postReserve({
    token: scenario.token,
    planId: scenario.planId,
    quantity: 3,
  });

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.preorderSummary.cap,
    10,
  );
  assert.equal(
    response.body.preorderSummary.effectiveCap,
    10,
  );
  assert.equal(
    response.body.preorderSummary.reserved,
    5,
  );
  assert.equal(
    response.body.preorderSummary.remaining,
    5,
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    5,
  );

  const reservations =
    await PreorderReservation.find({
      planId: scenario.planId,
    }).lean();
  assert.equal(reservations.length, 1);
  assert.equal(
    reservations[0].quantity,
    3,
  );
  assert.equal(
    reservations[0].status,
    "reserved",
  );
});

test("reserve enforces effective cap from approved progress coverage", async () => {
  const scenario = await seedScenario({
    preorderEnabled: true,
    preorderCapQuantity: 10,
    preorderReservedQuantity: 4,
  });
  await createTaskProgress({
    planId: scenario.planId,
    createdBy: scenario.ownerId,
    approved: true,
  });
  await createTaskProgress({
    planId: scenario.planId,
    createdBy: scenario.ownerId,
    approved: false,
  });

  const response = await postReserve({
    token: scenario.token,
    planId: scenario.planId,
    quantity: 2,
  });

  assert.equal(
    response.statusCode,
    HTTP_CONFLICT,
  );
  assert.equal(
    response.body.error,
    "Reservation quantity exceeds remaining pre-order capacity",
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    4,
  );
  assert.equal(
    await PreorderReservation.countDocuments(
      {
        planId: scenario.planId,
      },
    ),
    0,
  );
});

test("reserve remains blocked when effective cap is below current reserved", async () => {
  const scenario = await seedScenario({
    preorderEnabled: true,
    preorderCapQuantity: 10,
    preorderReservedQuantity: 7,
  });
  await createTaskProgress({
    planId: scenario.planId,
    createdBy: scenario.ownerId,
    approved: true,
  });
  await createTaskProgress({
    planId: scenario.planId,
    createdBy: scenario.ownerId,
    approved: false,
  });
  await createTaskProgress({
    planId: scenario.planId,
    createdBy: scenario.ownerId,
    approved: false,
  });

  const response = await postReserve({
    token: scenario.token,
    planId: scenario.planId,
    quantity: 1,
  });

  assert.equal(
    response.statusCode,
    HTTP_CONFLICT,
  );
  assert.equal(
    response.body.error,
    "Reservation quantity exceeds remaining pre-order capacity",
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    7,
  );
  assert.equal(
    await PreorderReservation.countDocuments(
      {
        planId: scenario.planId,
      },
    ),
    0,
  );
});

test("reserve fails when exceeding cap", async () => {
  const scenario = await seedScenario({
    preorderEnabled: true,
    preorderCapQuantity: 5,
    preorderReservedQuantity: 4,
  });
  const response = await postReserve({
    token: scenario.token,
    planId: scenario.planId,
    quantity: 2,
  });

  assert.equal(
    response.statusCode,
    HTTP_CONFLICT,
  );
  assert.equal(
    response.body.error,
    "Reservation quantity exceeds remaining pre-order capacity",
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    4,
  );
  assert.equal(
    await PreorderReservation.countDocuments(
      {
        planId: scenario.planId,
      },
    ),
    0,
  );
});

test("concurrent double reservation does not exceed cap", async () => {
  const scenario = await seedScenario({
    preorderEnabled: true,
    preorderCapQuantity: 5,
    preorderReservedQuantity: 0,
  });

  const [first, second] =
    await Promise.all([
      postReserve({
        token: scenario.token,
        planId: scenario.planId,
        quantity: 4,
      }),
      postReserve({
        token: scenario.token,
        planId: scenario.planId,
        quantity: 4,
      }),
    ]);

  const statusCodes = [
    first.statusCode,
    second.statusCode,
  ].sort();
  assert.deepEqual(statusCodes, [
    HTTP_OK,
    HTTP_CONFLICT,
  ]);

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    4,
  );
  assert.equal(
    await PreorderReservation.countDocuments(
      {
        planId: scenario.planId,
      },
    ),
    1,
  );
});

test("reservation blocked when preorder disabled", async () => {
  const scenario = await seedScenario({
    preorderEnabled: false,
    preorderCapQuantity: 5,
    preorderReservedQuantity: 0,
  });

  const response = await postReserve({
    token: scenario.token,
    planId: scenario.planId,
    quantity: 1,
  });

  assert.equal(
    response.statusCode,
    HTTP_BAD_REQUEST,
  );
  assert.equal(
    response.body.error,
    "Pre-order is not enabled for this production plan",
  );

  const updatedProduct =
    await Product.findById(
      scenario.productId,
    ).lean();
  assert.equal(
    updatedProduct.preorderReservedQuantity,
    0,
  );
  assert.equal(
    await PreorderReservation.countDocuments(
      {
        planId: scenario.planId,
      },
    ),
    0,
  );
});
