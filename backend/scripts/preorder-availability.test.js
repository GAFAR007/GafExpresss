/**
 * backend/scripts/preorder-availability.test.js
 * ---------------------------------------------
 * WHAT:
 * - Integration tests for GET /products/:id/preorder-availability.
 *
 * WHY:
 * - Ensures UI gets stable cap/reserved/remaining values for preorder summaries.
 *
 * HOW:
 * - Runs isolated Mongo fixtures and calls the public route through an Express app.
 */

const path = require("node:path");
const http = require("node:http");
const test = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const mongoose = require("mongoose");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const debug = require("../utils/debug");
const {
  resolveReusableTestDbUri,
} = require("./_test_db.util");
const productPublicController = require("../controllers/product.public.controller");
const Product = require("../models/Product");
const TaskProgress = require("../models/TaskProgress");
const User = require("../models/User");

const TEST_LOG_TAG =
  "PREORDER_AVAILABILITY_TEST";
const TEST_DB_NAME =
  "preorder_availability_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "products",
  "productionplans",
  "taskprogresses",
];
const TEST_DB_NAME_PATTERN =
  /^(preorder_availability_test|pav_[a-z0-9]+_[a-z0-9]+)$/;
const AVAILABILITY_ROUTE_TEMPLATE =
  "/products/:id/preorder-availability";
const HTTP_OK = 200;
const HTTP_NOT_FOUND = 404;

const RESET_MODELS = [
  TaskProgress,
  Product,
  User,
];

let server = null;
let testDbUri = "";

function buildAvailabilityApp() {
  const app = express();
  app.use(express.json());

  app.get(
    AVAILABILITY_ROUTE_TEMPLATE,
    productPublicController.getPreorderAvailabilitySummary,
  );

  return app;
}

async function requestJson({
  routePath,
}) {
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        method: "GET",
        hostname: "127.0.0.1",
        port: server.address().port,
        path: routePath,
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

async function getAvailability({
  productId,
}) {
  return requestJson({
    routePath: `/products/${productId}/preorder-availability`,
  });
}

async function createOwner({
  id,
}) {
  return User.create({
    _id: id,
    name: `owner-${id.toString().slice(-6)}`,
    email: `owner_${id.toString().slice(-6)}@test.local`,
    passwordHash: "hashed_for_tests",
    role: "business_owner",
    businessId: id,
  });
}

async function createProduct({
  id,
  ownerId,
  isActive = false,
  productionState = "available_for_preorder",
  preorderEnabled = true,
  preorderCapQuantity = 10,
  preorderReservedQuantity = 4,
  productionPlanId = null,
}) {
  return Product.create({
    _id: id,
    businessId: ownerId,
    createdBy: ownerId,
    updatedBy: ownerId,
    name: `Rice ${id.toString().slice(-6)}`,
    description: "preorder availability test product",
    price: 1500,
    stock: 0,
    isActive,
    productionState,
    preorderEnabled,
    productionPlanId,
    preorderCapQuantity,
    preorderReservedQuantity,
    preorderReleasedQuantity: 0,
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

async function seedScenario(overrides = {}) {
  const ownerId =
    new mongoose.Types.ObjectId();
  const productId =
    new mongoose.Types.ObjectId();

  await createOwner({ id: ownerId });
  await createProduct({
    id: productId,
    ownerId,
    ...overrides,
  });

  return { ownerId, productId };
}

async function purgeTestData() {
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
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
    "Connecting availability test database",
    {
      hasMongoUri: Boolean(
        process.env.MONGO_URI,
      ),
    },
  );
  await mongoose.connect(testDbUri);

  const app = buildAvailabilityApp();
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

test("returns cap/reserved/remaining for visible preorder product", async () => {
  const scenario = await seedScenario({
    isActive: false,
    productionState:
      "available_for_preorder",
    preorderEnabled: true,
    preorderCapQuantity: 12,
    preorderReservedQuantity: 5,
  });

  const response = await getAvailability({
    productId: scenario.productId,
  });

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.availability.preorderCapQuantity,
    12,
  );
  assert.equal(
    response.body.availability.preorderReservedQuantity,
    5,
  );
  assert.equal(
    response.body.availability.preorderRemainingQuantity,
    7,
  );
  assert.equal(
    response.body.availability.baseCap,
    12,
  );
  assert.equal(
    response.body.availability.effectiveCap,
    12,
  );
  assert.equal(
    response.body.availability.confidenceScore,
    1,
  );
  assert.equal(
    response.body.availability.approvedProgressCoverage,
    0,
  );
});

test("remaining clamps at zero when reserved exceeds cap", async () => {
  const scenario = await seedScenario({
    isActive: false,
    productionState:
      "available_for_preorder",
    preorderEnabled: true,
    preorderCapQuantity: 3,
    preorderReservedQuantity: 9,
  });

  const response = await getAvailability({
    productId: scenario.productId,
  });

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.availability.preorderCapQuantity,
    3,
  );
  assert.equal(
    response.body.availability.preorderReservedQuantity,
    9,
  );
  assert.equal(
    response.body.availability.preorderRemainingQuantity,
    0,
  );
  assert.equal(
    response.body.availability.baseCap,
    3,
  );
  assert.equal(
    response.body.availability.effectiveCap,
    3,
  );
});

test("returns confidence-based effective cap from approved progress coverage", async () => {
  const planId =
    new mongoose.Types.ObjectId();
  const scenario = await seedScenario({
    isActive: false,
    productionState:
      "available_for_preorder",
    preorderEnabled: true,
    preorderCapQuantity: 10,
    preorderReservedQuantity: 4,
    productionPlanId: planId,
  });

  await createTaskProgress({
    planId,
    createdBy: scenario.ownerId,
    approved: true,
  });
  await createTaskProgress({
    planId,
    createdBy: scenario.ownerId,
    approved: false,
  });

  const response = await getAvailability({
    productId: scenario.productId,
  });

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.availability.preorderCapQuantity,
    10,
  );
  assert.equal(
    response.body.availability.baseCap,
    10,
  );
  assert.equal(
    response.body.availability.approvedProgressCoverage,
    0.5,
  );
  assert.equal(
    response.body.availability.confidenceScore,
    0.5,
  );
  assert.equal(
    response.body.availability.effectiveCap,
    5,
  );
});

test("hidden product returns 404", async () => {
  const scenario = await seedScenario({
    isActive: false,
    productionState: "in_production",
    preorderEnabled: false,
    preorderCapQuantity: 0,
    preorderReservedQuantity: 0,
  });

  const response = await getAvailability({
    productId: scenario.productId,
  });

  assert.equal(
    response.statusCode,
    HTTP_NOT_FOUND,
  );
  assert.equal(
    response.body.error,
    "Product not found",
  );
});
