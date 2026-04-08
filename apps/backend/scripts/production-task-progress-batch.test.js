/**
 * backend/scripts/production-task-progress-batch.test.js
 * ------------------------------------------------------
 * WHAT:
 * - Integration tests for POST /business/production/tasks/progress/batch.
 *
 * WHY:
 * - Verifies real daily farm progress batch logging behavior with strict
 *   validation, partial success handling, and safe upsert semantics.
 *
 * HOW:
 * - Uses Node's built-in test runner with a minimal Express app that wires
 *   the same auth + role middleware chain as production.
 * - Uses an isolated MongoDB test database and drops state between tests.
 */

const path = require("node:path");
const http = require("node:http");
const test = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");

// WHY: Load backend env so test DB + JWT secret match runtime expectations.
require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const debug = require("../utils/debug");
const {
  requireAuth,
} = require("../middlewares/auth.middleware");
const {
  requireAnyRole,
} = require("../middlewares/requireRole.middleware");
const businessController = require("../controllers/business.controller");
const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const ProductionPlan = require("../models/ProductionPlan");
const ProductionPhase = require("../models/ProductionPhase");
const ProductionTask = require("../models/ProductionTask");
const TaskProgress = require("../models/TaskProgress");
const {
  HUMANE_WORKLOAD_LIMITS,
} = require("../utils/production_engine.config");

const TEST_LOG_TAG =
  "TASK_PROGRESS_BATCH_TEST";
const BATCH_ROUTE_PATH =
  "/business/production/tasks/progress/batch";
const STAFF_ROLE_FARMER = "farmer";
const OWNER_ROLE = "business_owner";
const HTTP_OK = 200;
const STATUS_NONE = "none";
const STATUS_RAIN = "rain";
const STATUS_MANAGEMENT_DELAY =
  "management_delay";
const WORK_DATE_STRING = "2026-03-10";
const WORK_DATE_NORMALIZED = new Date(
  "2026-03-10T00:00:00.000Z",
);

let server;
let baseUrl = "";
let testDbUri = "";
const RESET_MODELS = [
  TaskProgress,
  ProductionTask,
  ProductionPhase,
  ProductionPlan,
  BusinessStaffProfile,
  BusinessAsset,
  User,
];

function buildTestDbUri(baseUri) {
  const uri = (baseUri || "").trim();
  if (!uri) {
    throw new Error(
      "MONGO_URI is required for batch endpoint tests",
    );
  }

  // WHY: Isolate test writes in a throwaway database to protect shared data.
  const parsed = new URL(uri);
  const dbName = `tpb_${Date.now().toString(36)}_${Math.floor(Math.random() * 1e6).toString(36)}`;
  parsed.pathname = `/${dbName}`;
  return parsed.toString();
}

function buildBatchApp() {
  const app = express();
  app.use(express.json());

  // WHY: Match production auth/role middleware expectations for this endpoint.
  app.post(
    BATCH_ROUTE_PATH,
    requireAuth,
    requireAnyRole([
      OWNER_ROLE,
      "staff",
    ]),
    businessController.logProductionTaskProgressBatch,
  );

  return app;
}

function issueOwnerToken(ownerId) {
  const secret =
    process.env.JWT_SECRET ||
    "test_jwt_secret";
  return jwt.sign(
    {
      sub: ownerId.toString(),
      role: OWNER_ROLE,
    },
    secret,
    {
      expiresIn: "1h",
    },
  );
}

async function requestJson({
  method,
  routePath,
  token,
  payload,
}) {
  return new Promise((resolve, reject) => {
    const payloadText = JSON.stringify(
      payload || {},
    );
    const req = http.request(
      {
        method,
        hostname: "127.0.0.1",
        port: server.address().port,
        path: routePath,
        headers: {
          "Content-Type":
            "application/json",
          "Content-Length":
            Buffer.byteLength(
              payloadText,
            ),
          Authorization: `Bearer ${token}`,
        },
      },
      (res) => {
        let bodyText = "";
        res.on("data", (chunk) => {
          bodyText += chunk.toString();
        });
        res.on("end", () => {
          try {
            const parsed =
              bodyText.trim().length > 0 ?
                JSON.parse(bodyText)
              : {};
            resolve({
              statusCode:
                res.statusCode || 0,
              body: parsed,
            });
          } catch (error) {
            reject(error);
          }
        });
      },
    );

    req.on("error", reject);
    req.write(payloadText);
    req.end();
  });
}

async function postBatch({
  token,
  workDate = WORK_DATE_STRING,
  entries,
}) {
  return requestJson({
    method: "POST",
    routePath: BATCH_ROUTE_PATH,
    token,
    payload: {
      workDate,
      entries,
    },
  });
}

async function createUser({
  id,
  businessId,
  role,
  email,
  estateAssetId = null,
}) {
  return User.create({
    _id: id,
    name: `${role}-${id.toString().slice(-6)}`,
    email,
    passwordHash: "hashed_password_for_tests",
    role,
    businessId,
    estateAssetId,
  });
}

async function createEstateAsset({
  id,
  businessId,
  createdBy,
  name,
}) {
  return BusinessAsset.create({
    _id: id,
    businessId,
    assetType: "equipment",
    ownershipType: "owned",
    assetClass: "current",
    name,
    createdBy,
  });
}

async function createStaffProfile({
  id,
  userId,
  businessId,
  estateAssetId,
  staffRole = STAFF_ROLE_FARMER,
}) {
  return BusinessStaffProfile.create({
    _id: id,
    userId,
    businessId,
    staffRole,
    estateAssetId,
    status: "active",
  });
}

async function createPlan({
  id,
  businessId,
  estateAssetId,
  createdBy,
}) {
  return ProductionPlan.create({
    _id: id,
    businessId,
    estateAssetId,
    productId:
      new mongoose.Types.ObjectId(),
    title: "Rice Plan Test",
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-03-31T00:00:00.000Z",
    ),
    status: "active",
    createdBy,
    notes: "batch test plan",
    aiGenerated: false,
    domainContext: "farm",
  });
}

async function createPhase({
  id,
  planId,
}) {
  return ProductionPhase.create({
    _id: id,
    planId,
    name: "Execution",
    order: 1,
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-03-31T00:00:00.000Z",
    ),
    status: "in_progress",
  });
}

async function createTask({
  id,
  planId,
  phaseId,
  title,
  assignedStaffId,
  createdBy,
  weight = 2,
}) {
  return ProductionTask.create({
    _id: id,
    planId,
    phaseId,
    title,
    roleRequired: STAFF_ROLE_FARMER,
    assignedStaffId,
    weight,
    startDate: new Date(
      "2026-03-01T00:00:00.000Z",
    ),
    dueDate: new Date(
      "2026-03-31T00:00:00.000Z",
    ),
    status: "pending",
    instructions: "Test task",
    createdBy,
    assignedBy: createdBy,
    approvalStatus: "approved",
  });
}

async function seedScenario() {
  const ownerId =
    new mongoose.Types.ObjectId();
  const reviewerId =
    new mongoose.Types.ObjectId();
  const staffUserAId =
    new mongoose.Types.ObjectId();
  const staffUserBId =
    new mongoose.Types.ObjectId();
  const staffUserMismatchId =
    new mongoose.Types.ObjectId();
  const businessId = ownerId;

  const estateAId =
    new mongoose.Types.ObjectId();
  const estateBId =
    new mongoose.Types.ObjectId();

  const staffProfileAId =
    new mongoose.Types.ObjectId();
  const staffProfileBId =
    new mongoose.Types.ObjectId();
  const staffProfileMismatchId =
    new mongoose.Types.ObjectId();

  const planId =
    new mongoose.Types.ObjectId();
  const phaseId =
    new mongoose.Types.ObjectId();
  const taskAId =
    new mongoose.Types.ObjectId();
  const taskBId =
    new mongoose.Types.ObjectId();
  const taskMismatchId =
    new mongoose.Types.ObjectId();

  // WHY: Owner must have businessId for resolveBusinessContext.
  await createUser({
    id: ownerId,
    businessId,
    role: OWNER_ROLE,
    email: `owner_${ownerId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: reviewerId,
    businessId,
    role: OWNER_ROLE,
    email: `reviewer_${reviewerId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: staffUserAId,
    businessId,
    role: "staff",
    email: `staffa_${staffUserAId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: staffUserBId,
    businessId,
    role: "staff",
    email: `staffb_${staffUserBId.toString().slice(-6)}@test.local`,
  });
  await createUser({
    id: staffUserMismatchId,
    businessId,
    role: "staff",
    email: `staffm_${staffUserMismatchId.toString().slice(-6)}@test.local`,
  });

  await createEstateAsset({
    id: estateAId,
    businessId,
    createdBy: ownerId,
    name: "Estate A",
  });
  await createEstateAsset({
    id: estateBId,
    businessId,
    createdBy: ownerId,
    name: "Estate B",
  });

  await createStaffProfile({
    id: staffProfileAId,
    userId: staffUserAId,
    businessId,
    estateAssetId: estateAId,
  });
  await createStaffProfile({
    id: staffProfileBId,
    userId: staffUserBId,
    businessId,
    estateAssetId: estateAId,
  });
  await createStaffProfile({
    id: staffProfileMismatchId,
    userId: staffUserMismatchId,
    businessId,
    estateAssetId: estateBId,
  });

  await createPlan({
    id: planId,
    businessId,
    estateAssetId: estateAId,
    createdBy: ownerId,
  });
  await createPhase({
    id: phaseId,
    planId,
  });

  await createTask({
    id: taskAId,
    planId,
    phaseId,
    title: "Task A",
    assignedStaffId: staffProfileAId,
    createdBy: ownerId,
    weight: 2,
  });
  await createTask({
    id: taskBId,
    planId,
    phaseId,
    title: "Task B",
    assignedStaffId: staffProfileBId,
    createdBy: ownerId,
    weight: 3,
  });
  await createTask({
    id: taskMismatchId,
    planId,
    phaseId,
    title: "Task Mismatch",
    assignedStaffId:
      staffProfileMismatchId,
    createdBy: ownerId,
    weight: 2,
  });

  return {
    ownerId,
    reviewerId,
    planId,
    phaseId,
    taskAId,
    taskBId,
    taskMismatchId,
    staffProfileAId,
    staffProfileBId,
    staffProfileMismatchId,
    token: issueOwnerToken(ownerId),
  };
}

async function countProgressDocs() {
  return TaskProgress.countDocuments({});
}

async function purgeTestData() {
  // WHY: Atlas user cannot drop DB; explicit collection cleanup keeps tests isolated.
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
}

test.before(async () => {
  process.env.JWT_SECRET =
    process.env.JWT_SECRET ||
    "test_jwt_secret";
  testDbUri = buildTestDbUri(
    process.env.MONGO_URI,
  );
  debug(
    TEST_LOG_TAG,
    "Connecting test database",
    {
      hasMongoUri: Boolean(
        process.env.MONGO_URI,
      ),
    },
  );
  await mongoose.connect(testDbUri);

  const app = buildBatchApp();
  await new Promise((resolve) => {
    server = app.listen(0, () => {
      baseUrl = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });
  debug(
    TEST_LOG_TAG,
    "Batch test server started",
    {
      baseUrl,
    },
  );
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
    "Batch test server stopped",
    {
      disconnected: true,
    },
  );
});

test.beforeEach(async () => {
  // WHY: Hard reset collections between tests to keep outcomes deterministic.
  await purgeTestData();
});

test("all entries succeed and persist TaskProgress rows", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskAId.toString(),
        staffId:
          scenario.staffProfileAId.toString(),
        actualPlots: 2,
        delayReason: STATUS_NONE,
        notes: "normal output",
      },
      {
        taskId:
          scenario.taskBId.toString(),
        staffId:
          scenario.staffProfileBId.toString(),
        actualPlots: 3,
        delayReason: STATUS_NONE,
        notes: "strong output",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "all entries succeed response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.successCount,
    2,
  );
  assert.equal(
    response.body.summary.errorCount,
    0,
  );
  assert.equal(
    response.body.successes.length,
    2,
  );
  assert.equal(
    await countProgressDocs(),
    2,
  );
});

test("mixed success + failure persists only successful entries", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskAId.toString(),
        staffId:
          scenario.staffProfileAId.toString(),
        actualPlots: 2,
        delayReason: STATUS_NONE,
        notes: "ok",
      },
      {
        taskId: "invalid-task-id",
        staffId:
          scenario.staffProfileBId.toString(),
        actualPlots: 1,
        delayReason: STATUS_RAIN,
        notes: "bad task id",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "mixed response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.successCount,
    1,
  );
  assert.equal(
    response.body.summary.errorCount,
    1,
  );
  assert.equal(
    response.body.successes.length,
    1,
  );
  assert.equal(
    response.body.errors.length,
    1,
  );
  assert.equal(
    await countProgressDocs(),
    1,
  );
});

test("invalid taskId yields TASK_ID_INVALID or TASK_NOT_FOUND", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId: "not-an-object-id",
        staffId:
          scenario.staffProfileAId.toString(),
        actualPlots: 1,
        delayReason: STATUS_RAIN,
        notes: "invalid task id",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "invalid task response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.errorCount,
    1,
  );
  const errorCode =
    response.body.errors[0]?.errorCode;
  assert.ok(
    [
      "TASK_ID_INVALID",
      "TASK_NOT_FOUND",
    ].includes(errorCode),
  );
});

test("staff not assigned yields STAFF_NOT_ASSIGNED", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskAId.toString(),
        staffId:
          scenario.staffProfileBId.toString(),
        actualPlots: 2,
        delayReason: STATUS_NONE,
        notes: "wrong staff",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "staff not assigned response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.errorCount,
    1,
  );
  assert.equal(
    response.body.errors[0]?.errorCode,
    "STAFF_NOT_ASSIGNED",
  );
});

test("estate mismatch yields STAFF_SCOPE_INVALID", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskMismatchId.toString(),
        staffId:
          scenario.staffProfileMismatchId.toString(),
        actualPlots: 1,
        delayReason: STATUS_MANAGEMENT_DELAY,
        notes: "estate mismatch",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "estate mismatch response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.errorCount,
    1,
  );
  assert.equal(
    response.body.errors[0]?.errorCode,
    "STAFF_SCOPE_INVALID",
  );
});

test("humane limit exceeded yields HUMANE_LIMIT_EXCEEDED", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskAId.toString(),
        staffId:
          scenario.staffProfileAId.toString(),
        actualPlots:
          HUMANE_WORKLOAD_LIMITS.maxPlotsPerFarmerPerDay + 1,
        delayReason: STATUS_NONE,
        notes: "over limit",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "humane limit response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.errorCount,
    1,
  );
  assert.equal(
    response.body.errors[0]?.errorCode,
    "HUMANE_LIMIT_EXCEEDED",
  );
});

test("zero-output without delay reason yields ZERO_OUTPUT_DELAY_REQUIRED", async () => {
  const scenario = await seedScenario();
  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskAId.toString(),
        staffId:
          scenario.staffProfileAId.toString(),
        actualPlots: 0,
        delayReason: STATUS_NONE,
        notes: "missing delay reason",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "zero output response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.errorCount,
    1,
  );
  assert.equal(
    response.body.errors[0]?.errorCode,
    "ZERO_OUTPUT_DELAY_REQUIRED",
  );
});

test("upsert updates existing row and preserves approval fields", async () => {
  const scenario = await seedScenario();
  const approvedAt = new Date(
    "2026-03-11T10:00:00.000Z",
  );

  const existingProgress =
    await TaskProgress.create({
      taskId: scenario.taskAId,
      planId: scenario.planId,
      staffId:
        scenario.staffProfileAId,
      workDate:
        WORK_DATE_NORMALIZED,
      expectedPlots: 2,
      actualPlots: 1,
      delayReason: STATUS_RAIN,
      notes: "initial log",
      createdBy: scenario.ownerId,
      approvedBy:
        scenario.reviewerId,
      approvedAt,
    });

  const response = await postBatch({
    token: scenario.token,
    entries: [
      {
        taskId:
          scenario.taskAId.toString(),
        staffId:
          scenario.staffProfileAId.toString(),
        actualPlots: 2,
        delayReason: STATUS_NONE,
        notes: "updated by batch",
      },
    ],
  });
  debug(
    TEST_LOG_TAG,
    "upsert response",
    response,
  );

  assert.equal(
    response.statusCode,
    HTTP_OK,
  );
  assert.equal(
    response.body.summary.successCount,
    1,
  );
  assert.equal(
    response.body.summary.errorCount,
    0,
  );

  const updatedProgress =
    await TaskProgress.findOne({
      taskId: scenario.taskAId,
      staffId:
        scenario.staffProfileAId,
      workDate:
        WORK_DATE_NORMALIZED,
    }).lean();

  assert.ok(updatedProgress);
  assert.equal(
    updatedProgress._id.toString(),
    existingProgress._id.toString(),
  );
  assert.equal(
    updatedProgress.actualPlots,
    2,
  );
  assert.equal(
    updatedProgress.notes,
    "updated by batch",
  );
  assert.equal(
    updatedProgress.approvedBy.toString(),
    scenario.reviewerId.toString(),
  );
  assert.equal(
    new Date(
      updatedProgress.approvedAt,
    ).toISOString(),
    approvedAt.toISOString(),
  );
  assert.equal(
    await countProgressDocs(),
    1,
  );
});
