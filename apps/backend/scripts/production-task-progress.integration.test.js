/**
 * backend/scripts/production-task-progress.integration.test.js
 * ------------------------------------------------------------
 * WHAT:
 * - Integration tests for POST /business/production/tasks/:taskId/progress.
 *
 * WHY:
 * - This is the production save path used by the Clock Out logging flow.
 * - It must preserve personal sessions while updating one shared task/day ledger.
 *
 * HOW:
 * - Uses a minimal Express app with the real auth + role middleware chain.
 * - Seeds isolated MongoDB data and exercises the endpoint over HTTP JSON.
 * - Avoids external proof uploads by seeding existing proof rows where needed.
 */

const path = require("node:path");
const http = require("node:http");
const test = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");
const {
  MongoMemoryReplSet,
} = require("mongodb-memory-server");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

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
const ProductionTaskDayLedger = require("../models/ProductionTaskDayLedger");
const StaffAttendance = require("../models/StaffAttendance");
const TaskProgress = require("../models/TaskProgress");

const ROUTE_PREFIX =
  "/business/production/tasks";
const OWNER_ROLE = "business_owner";
const STAFF_ROLE_FARMER = "farmer";
const HTTP_OK = 200;
const HTTP_BAD_REQUEST = 400;
const STATUS_NONE = "none";
const WORK_DATE_STRING = "2026-04-12";
const WORK_DATE_NORMALIZED = new Date(
  "2026-04-12T00:00:00.000Z",
);
const PLOT_UNIT_SCALE = 1000;

let server;
let testDbUri = "";
let mongoReplSet = null;

const RESET_MODELS = [
  ProductionTaskDayLedger,
  StaffAttendance,
  TaskProgress,
  ProductionTask,
  ProductionPhase,
  ProductionPlan,
  BusinessStaffProfile,
  BusinessAsset,
  User,
];

function buildProgressApp() {
  const app = express();
  app.use(express.json());
  app.post(
    `${ROUTE_PREFIX}/:taskId/progress`,
    requireAuth,
    requireAnyRole([
      OWNER_ROLE,
      "staff",
    ]),
    businessController.logProductionTaskProgress,
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

function toPlotUnits(plots) {
  return Math.round(
    Math.max(0, Number(plots || 0)) *
      PLOT_UNIT_SCALE,
  );
}

function buildSeededProofs({
  count,
  uploadedBy,
}) {
  return Array.from(
    { length: count },
    (_, index) => ({
      url: `https://example.test/proof-${index + 1}.jpg`,
      publicId: `proof-${index + 1}`,
      filename: `proof-${index + 1}.jpg`,
      mimeType: "image/jpeg",
      sizeBytes: 1024 + index,
      uploadedAt: new Date(
        `2026-04-12T0${Math.min(index, 9)}:00:00.000Z`,
      ),
      uploadedBy,
    }),
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
              bodyText.trim().length > 0
                ? JSON.parse(bodyText)
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

async function postProgress({
  token,
  taskId,
  payload,
}) {
  return requestJson({
    method: "POST",
    routePath: `${ROUTE_PREFIX}/${taskId}/progress`,
    token,
    payload,
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
    assetType: "estate",
    ownershipType: "owned",
    assetClass: "fixed",
    name,
    status: "active",
    currency: "NGN",
    purchaseCost: 5000000,
    purchaseDate: new Date(
      "2026-01-01T00:00:00.000Z",
    ),
    usefulLifeMonths: 120,
    estate: {
      propertyAddress: {
        houseNumber: "1",
        street: "Test Road",
        city: "Ibadan",
        state: "Oyo",
        country: "Nigeria",
      },
      unitMix: [
        {
          unitType: "plot",
          count: 5,
          rentAmount: 0,
          rentPeriod: "yearly",
        },
      ],
      totalUnits: 5,
      rentableUnits: 5,
      occupancyRate: 100,
      rentSummary: {
        totalMonthly: 0,
        totalAnnual: 0,
      },
    },
    createdBy,
  });
}

async function createStaffProfile({
  id,
  userId,
  businessId,
  estateAssetId,
}) {
  return BusinessStaffProfile.create({
    _id: id,
    userId,
    businessId,
    estateAssetId,
    staffRole: STAFF_ROLE_FARMER,
    employeeCode: `EMP-${id.toString().slice(-6)}`,
    employmentStatus: "active",
    hireDate: new Date(
      "2026-01-01T00:00:00.000Z",
    ),
  });
}

async function createPlan({
  id,
  businessId,
  estateAssetId,
  createdBy,
  plantingTargets = null,
}) {
  return ProductionPlan.create({
    _id: id,
    businessId,
    estateAssetId,
    productId:
      new mongoose.Types.ObjectId(),
    title: "Rice Plan Test",
    startDate: new Date(
      "2026-04-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "active",
    createdBy,
    notes: "single progress endpoint test plan",
    aiGenerated: false,
    domainContext: "farm",
    plantingTargets,
    workloadContext: {
      workUnitLabel: "plots",
      workUnitType: "plot",
      totalWorkUnits: 5,
      minStaffPerUnit: 1,
      maxStaffPerUnit: 2,
      activeStaffAvailabilityPercent: 100,
      hasConfirmedWorkloadContext: true,
    },
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
      "2026-04-01T00:00:00.000Z",
    ),
    endDate: new Date(
      "2026-04-30T00:00:00.000Z",
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
  assignedStaffProfileIds = [],
  createdBy,
  weight = 5,
}) {
  return ProductionTask.create({
    _id: id,
    planId,
    phaseId,
    title,
    roleRequired: STAFF_ROLE_FARMER,
    assignedStaffId,
    assignedStaffProfileIds:
      assignedStaffProfileIds.length > 0
        ? assignedStaffProfileIds
        : assignedStaffId
        ? [assignedStaffId]
        : [],
    weight,
    startDate: new Date(
      "2026-04-01T00:00:00.000Z",
    ),
    dueDate: new Date(
      "2026-04-30T00:00:00.000Z",
    ),
    status: "pending",
    instructions: "Test task",
    createdBy,
    assignedBy: createdBy,
    approvalStatus: "approved",
  });
}

async function createActiveAttendance({
  staffProfileId,
  planId,
  taskId,
  workDate,
  actorId,
}) {
  const clockInAt = new Date(
    `${workDate}T08:00:00.000Z`,
  );
  return StaffAttendance.create({
    staffProfileId,
    planId,
    taskId,
    workDate: new Date(
      `${workDate}T00:00:00.000Z`,
    ),
    clockInAt,
    clockOutAt: null,
    clockInBy: actorId,
    notes: "active attendance for endpoint test",
  });
}

async function seedExistingProofDraft({
  ownerId,
  planId,
  taskId,
  staffId,
  workDate = WORK_DATE_NORMALIZED,
  proofCount,
}) {
  return TaskProgress.create({
    taskId,
    planId,
    staffId,
    unitId: null,
    workDate,
    expectedPlots: 5,
    expectedPlotUnits: toPlotUnits(5),
    actualPlots: 0,
    actualPlotUnits: 0,
    unitContribution: 0,
    unitContributionPlotUnits: 0,
    quantityActivityType: "none",
    activityType: "none",
    quantityAmount: 0,
    activityQuantity: 0,
    quantityUnit: "",
    proofCountRequired: proofCount,
    proofCountUploaded: proofCount,
    proofs: buildSeededProofs({
      count: proofCount,
      uploadedBy: ownerId,
    }),
    sessionStatus: "active",
    delayReason: STATUS_NONE,
    notes: "seeded proof draft",
    createdBy: ownerId,
  });
}

async function seedScenario({
  plantingTargets = null,
} = {}) {
  const ownerId =
    new mongoose.Types.ObjectId();
  const staffUserAId =
    new mongoose.Types.ObjectId();
  const staffUserBId =
    new mongoose.Types.ObjectId();
  const businessId = ownerId;

  const estateAId =
    new mongoose.Types.ObjectId();
  const staffProfileAId =
    new mongoose.Types.ObjectId();
  const staffProfileBId =
    new mongoose.Types.ObjectId();
  const planId =
    new mongoose.Types.ObjectId();
  const phaseId =
    new mongoose.Types.ObjectId();
  const taskId =
    new mongoose.Types.ObjectId();

  await createUser({
    id: ownerId,
    businessId,
    role: OWNER_ROLE,
    email: `owner_${ownerId.toString().slice(-6)}@test.local`,
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

  await createEstateAsset({
    id: estateAId,
    businessId,
    createdBy: ownerId,
    name: "Estate A",
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

  await createPlan({
    id: planId,
    businessId,
    estateAssetId: estateAId,
    createdBy: ownerId,
    plantingTargets,
  });
  await createPhase({
    id: phaseId,
    planId,
  });
  await createTask({
    id: taskId,
    planId,
    phaseId,
    title: "Shared Task",
    assignedStaffId:
      staffProfileAId,
    assignedStaffProfileIds: [
      staffProfileAId,
      staffProfileBId,
    ],
    createdBy: ownerId,
    weight: 5,
  });

  return {
    ownerId,
    token: issueOwnerToken(ownerId),
    businessId,
    estateAId,
    planId,
    phaseId,
    taskId,
    staffProfileAId,
    staffProfileBId,
  };
}

async function resetDatabase() {
  await Promise.all(
    RESET_MODELS.map((model) =>
      model.deleteMany({}),
    ),
  );
}

test.before(async () => {
  mongoReplSet =
    await MongoMemoryReplSet.create({
      replSet: {
        count: 1,
        storageEngine: "wiredTiger",
      },
    });
  testDbUri =
    mongoReplSet.getUri(
      "production_task_progress_test",
    );
  await mongoose.connect(testDbUri, {
    serverSelectionTimeoutMS: 15000,
  });
  server = buildProgressApp().listen(0);
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
  await resetDatabase();
  if (mongoose.connection.readyState !== 0) {
    await mongoose.disconnect();
  }
  if (mongoReplSet) {
    await mongoReplSet.stop();
    mongoReplSet = null;
  }
});

test.afterEach(async () => {
  await resetDatabase();
});

test(
  "positive unit contribution without proofs is rejected and leaves the shared ledger untouched",
  async () => {
    const scenario = await seedScenario();
    await createActiveAttendance({
      staffProfileId:
        scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    });

    const response = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "transplanted",
        unitContribution: 1.5,
        activityQuantity: 500,
        delayReason: STATUS_NONE,
        notes: "missing proofs should fail",
      },
    });

    assert.equal(
      response.statusCode,
      HTTP_BAD_REQUEST,
    );
    assert.equal(
      response.body.error,
      "Upload proof images before logging progress",
    );
    assert.equal(
      await TaskProgress.countDocuments({
        taskId: scenario.taskId,
      }),
      0,
    );
    assert.equal(
      await ProductionTaskDayLedger.countDocuments({
        taskId: scenario.taskId,
      }),
      0,
    );
    const activeAttendance =
      await StaffAttendance.findOne({
        taskId: scenario.taskId,
        staffProfileId:
          scenario.staffProfileAId,
      }).lean();
    assert.ok(activeAttendance);
    assert.equal(
      activeAttendance.clockOutAt,
      null,
    );
  },
);

test(
  "no quantity update closes the personal session without changing shared totals",
  async () => {
    const scenario = await seedScenario({
      plantingTargets: {
        materialType: "seed",
        plannedPlantingQuantity: 2000,
        plannedPlantingUnit: "seeds",
        estimatedHarvestQuantity: 500,
        estimatedHarvestUnit: "crates",
      },
    });
    await createActiveAttendance({
      staffProfileId:
        scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    });

    const response = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "none",
        activityQuantity: 0,
        delayReason: STATUS_NONE,
        notes: "clock out without quantity update",
      },
    });

    assert.equal(
      response.statusCode,
      HTTP_OK,
    );
    assert.equal(
      response.body.ledger.unitCompleted,
      0,
    );
    assert.equal(
      response.body.ledger.unitRemaining,
      5,
    );
    assert.equal(
      response.body.ledger.activityCompleted
        .transplanted,
      0,
    );

    const savedAttendance =
      await StaffAttendance.findOne({
        taskId: scenario.taskId,
        staffProfileId:
          scenario.staffProfileAId,
      }).lean();
    assert.ok(savedAttendance?.clockOutAt);

    const savedProgress =
      await TaskProgress.findOne({
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(savedProgress);
    assert.equal(
      savedProgress.sessionStatus,
      "completed",
    );
    assert.equal(
      savedProgress.unitContribution,
      0,
    );
    assert.equal(
      savedProgress.activityType,
      "none",
    );
    assert.equal(
      savedProgress.activityQuantity,
      0,
    );
    assert.equal(
      savedProgress.proofCountRequired,
      0,
    );
    assert.equal(
      savedProgress.proofCountUploaded,
      0,
    );
  },
);

test(
  "single-entry clock-out reuses an open same-day attendance from another task",
  async () => {
    const scenario = await seedScenario();
    const secondaryTaskId =
      new mongoose.Types.ObjectId();

    await createTask({
      id: secondaryTaskId,
      planId: scenario.planId,
      phaseId: scenario.phaseId,
      title: "Sibling Task",
      assignedStaffId:
        scenario.staffProfileAId,
      assignedStaffProfileIds: [
        scenario.staffProfileAId,
      ],
      createdBy: scenario.ownerId,
      weight: 3,
    });

    const openAttendance =
      await createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: secondaryTaskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      });

    await seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId:
        scenario.staffProfileAId,
      proofCount: 4,
    });

    const response = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "none",
        unitContribution: 3.5,
        activityQuantity: 0,
        delayReason: STATUS_NONE,
        notes: "finish current task from shared open attendance",
      },
    });

    assert.equal(
      response.statusCode,
      HTTP_OK,
    );
    assert.equal(
      response.body.ledger.unitCompleted,
      3.5,
    );
    assert.equal(
      response.body.ledger.unitRemaining,
      1.5,
    );

    const savedAttendance =
      await StaffAttendance.findById(
        openAttendance._id,
      ).lean();
    assert.ok(savedAttendance?.clockOutAt);
    assert.equal(
      savedAttendance.taskId.toString(),
      scenario.taskId.toString(),
    );
    assert.equal(
      savedAttendance.planId.toString(),
      scenario.planId.toString(),
    );

    const savedProgress =
      await TaskProgress.findOne({
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(savedProgress);
    assert.equal(
      savedProgress.unitContribution,
      3.5,
    );
    assert.equal(
      savedProgress.proofCountRequired,
      4,
    );
    assert.equal(
      savedProgress.proofCountUploaded,
      4,
    );
    assert.equal(
      savedProgress.sessionStatus,
      "completed",
    );
    assert.ok(savedProgress.clockInTime);
    assert.ok(savedProgress.clockOutTime);
  },
);

test(
  "single-entry production logging shares unit and activity totals across staff for the same day",
  async () => {
    const scenario = await seedScenario({
      plantingTargets: {
        materialType: "seed",
        plannedPlantingQuantity: 2000,
        plannedPlantingUnit: "seeds",
        estimatedHarvestQuantity: 500,
        estimatedHarvestUnit: "crates",
      },
    });

    await Promise.all([
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileBId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        proofCount: 4,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileBId,
        proofCount: 2,
      }),
    ]);

    const firstResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "transplanted",
        unitContribution: 3.5,
        activityQuantity: 500,
        delayReason: STATUS_NONE,
        notes: "staff a shared contribution",
      },
    });

    assert.equal(
      firstResponse.statusCode,
      HTTP_OK,
    );
    assert.equal(
      firstResponse.body.ledger.unitCompleted,
      3.5,
    );
    assert.equal(
      firstResponse.body.ledger.unitRemaining,
      1.5,
    );
    assert.equal(
      firstResponse.body.ledger.activityCompleted
        .transplanted,
      500,
    );
    assert.equal(
      firstResponse.body.ledger.activityRemaining
        .transplanted,
      1500,
    );

    const secondResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileBId.toString(),
        activityType: "transplanted",
        unitContribution: 1.5,
        activityQuantity: 500,
        delayReason: STATUS_NONE,
        notes: "staff b shared contribution",
      },
    });

    assert.equal(
      secondResponse.statusCode,
      HTTP_OK,
    );
    assert.equal(
      secondResponse.body.ledger.unitCompleted,
      5,
    );
    assert.equal(
      secondResponse.body.ledger.unitRemaining,
      0,
    );
    assert.equal(
      secondResponse.body.ledger.status,
      "completed",
    );
    assert.equal(
      secondResponse.body.ledger.activityCompleted
        .transplanted,
      1000,
    );
    assert.equal(
      secondResponse.body.ledger.activityRemaining
        .transplanted,
      1000,
    );

    const ledger =
      await ProductionTaskDayLedger.findOne({
        taskId: scenario.taskId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(ledger);
    assert.equal(
      ledger.unitCompleted,
      5,
    );
    assert.equal(
      ledger.unitRemaining,
      0,
    );
    assert.equal(
      ledger.activityCompleted.transplanted,
      1000,
    );
    assert.equal(
      ledger.activityRemaining.transplanted,
      1000,
    );

    const progressRows =
      await TaskProgress.find({
        taskId: scenario.taskId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.equal(
      progressRows.length,
      2,
    );
    const firstRow =
      progressRows.find(
        (row) =>
          row.staffId.toString() ===
          scenario.staffProfileAId.toString(),
      );
    const secondRow =
      progressRows.find(
        (row) =>
          row.staffId.toString() ===
          scenario.staffProfileBId.toString(),
      );
    assert.equal(
      firstRow.proofCountRequired,
      4,
    );
    assert.equal(
      firstRow.proofCountUploaded,
      4,
    );
    assert.equal(
      secondRow.proofCountRequired,
      2,
    );
    assert.equal(
      secondRow.proofCountUploaded,
      2,
    );
  },
);

test(
  "fresh backend validation blocks activity oversubmission against the shared remaining target",
  async () => {
    const scenario = await seedScenario({
      plantingTargets: {
        materialType: "seed",
        plannedPlantingQuantity: 2000,
        plannedPlantingUnit: "seeds",
        estimatedHarvestQuantity: 500,
        estimatedHarvestUnit: "crates",
      },
    });

    await Promise.all([
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileBId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        proofCount: 2,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileBId,
        proofCount: 1,
      }),
    ]);

    const firstResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "transplanted",
        unitContribution: 2,
        activityQuantity: 1500,
        delayReason: STATUS_NONE,
        notes: "consumes most of the activity target",
      },
    });
    assert.equal(
      firstResponse.statusCode,
      HTTP_OK,
    );

    const secondResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileBId.toString(),
        activityType: "transplanted",
        unitContribution: 1,
        activityQuantity: 600,
        delayReason: STATUS_NONE,
        notes: "tries to exceed activity remaining",
      },
    });

    assert.equal(
      secondResponse.statusCode,
      HTTP_BAD_REQUEST,
    );
    assert.equal(
      secondResponse.body.error,
      "Activity quantity exceeds the remaining shared activity target",
    );
    assert.equal(
      secondResponse.body.activityType,
      "transplanted",
    );
    assert.equal(
      secondResponse.body.maxAllowedActivityQuantity,
      500,
    );

    const ledger =
      await ProductionTaskDayLedger.findOne({
        taskId: scenario.taskId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(ledger);
    assert.equal(
      ledger.unitCompleted,
      2,
    );
    assert.equal(
      ledger.unitRemaining,
      3,
    );
    assert.equal(
      ledger.activityCompleted.transplanted,
      1500,
    );
    assert.equal(
      ledger.activityRemaining.transplanted,
      500,
    );
  },
);

test(
  "decimal production clock-out uses ceiling proof count and closes attendance on success",
  async () => {
    const scenario = await seedScenario({
      plantingTargets: {
        materialType: "seed",
        plannedPlantingQuantity: 2000,
        plannedPlantingUnit: "seeds",
        estimatedHarvestQuantity: 500,
        estimatedHarvestUnit: "crates",
      },
    });

    await Promise.all([
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        proofCount: 2,
      }),
    ]);

    const response = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "planted",
        unitContribution: 1.2,
        activityQuantity: 400,
        delayReason: STATUS_NONE,
        notes: "decimal contribution with ceil proof rule",
      },
    });

    assert.equal(
      response.statusCode,
      HTTP_OK,
    );
    assert.equal(
      response.body.ledger.unitCompleted,
      1.2,
    );
    assert.equal(
      response.body.ledger.unitRemaining,
      3.8,
    );
    assert.equal(
      response.body.ledger.activityCompleted
        .planted,
      400,
    );

    const savedAttendance =
      await StaffAttendance.findOne({
        taskId: scenario.taskId,
        staffProfileId:
          scenario.staffProfileAId,
      }).lean();
    assert.ok(savedAttendance?.clockOutAt);

    const savedProgress =
      await TaskProgress.findOne({
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(savedProgress?.clockOutTime);
    assert.equal(
      savedProgress.proofCountRequired,
      2,
    );
    assert.equal(
      savedProgress.proofCountUploaded,
      2,
    );
    assert.equal(
      savedProgress.activityType,
      "planted",
    );
    assert.equal(
      savedProgress.activityQuantity,
      400,
    );
    assert.equal(
      savedProgress.sessionStatus,
      "completed",
    );
  },
);

test(
  "planted and harvested clock-out saves update their own shared activity buckets",
  async () => {
    const scenario = await seedScenario({
      plantingTargets: {
        materialType: "seed",
        plannedPlantingQuantity: 2000,
        plannedPlantingUnit: "seeds",
        estimatedHarvestQuantity: 500,
        estimatedHarvestUnit: "crates",
      },
    });

    await Promise.all([
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileBId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        proofCount: 1,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileBId,
        proofCount: 2,
      }),
    ]);

    const plantedResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "planted",
        unitContribution: 1,
        activityQuantity: 500,
        delayReason: STATUS_NONE,
        notes: "planted update",
      },
    });
    assert.equal(
      plantedResponse.statusCode,
      HTTP_OK,
    );

    const harvestedResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileBId.toString(),
        activityType: "harvested",
        unitContribution: 2,
        activityQuantity: 120,
        delayReason: STATUS_NONE,
        notes: "harvested update",
      },
    });
    assert.equal(
      harvestedResponse.statusCode,
      HTTP_OK,
    );

    const ledger =
      await ProductionTaskDayLedger.findOne({
        taskId: scenario.taskId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(ledger);
    assert.equal(
      ledger.unitCompleted,
      3,
    );
    assert.equal(
      ledger.activityCompleted.planted,
      500,
    );
    assert.equal(
      ledger.activityCompleted.harvested,
      120,
    );
    assert.equal(
      ledger.activityRemaining.planted,
      1500,
    );
    assert.equal(
      ledger.activityRemaining.harvested,
      380,
    );
  },
);

test(
  "fresh backend validation blocks stale primary unit submissions against the latest shared remaining",
  async () => {
    const scenario = await seedScenario();

    await Promise.all([
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileBId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        proofCount: 4,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileBId,
        proofCount: 2,
      }),
    ]);

    const firstResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileAId.toString(),
        activityType: "none",
        unitContribution: 4,
        activityQuantity: 0,
        delayReason: STATUS_NONE,
        notes: "consumes most of the primary target",
      },
    });
    assert.equal(
      firstResponse.statusCode,
      HTTP_OK,
    );

    const staleResponse = await postProgress({
      token: scenario.token,
      taskId:
        scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId:
          scenario.staffProfileBId.toString(),
        activityType: "none",
        unitContribution: 2,
        activityQuantity: 0,
        delayReason: STATUS_NONE,
        notes: "tries to exceed the remaining shared units",
      },
    });

    assert.equal(
      staleResponse.statusCode,
      HTTP_BAD_REQUEST,
    );
    assert.equal(
      staleResponse.body.error,
      "Actual progress exceeds the remaining planned task target",
    );
    assert.equal(
      staleResponse.body.maxAllowedPlots,
      1,
    );
    assert.equal(
      staleResponse.body.maxAllowedPlotUnits,
      toPlotUnits(1),
    );

    const ledger =
      await ProductionTaskDayLedger.findOne({
        taskId: scenario.taskId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(ledger);
    assert.equal(
      ledger.unitCompleted,
      4,
    );
    assert.equal(
      ledger.unitRemaining,
      1,
    );
  },
);

test(
  "concurrent production clock-out saves do not overrun the shared task target",
  async () => {
    const scenario = await seedScenario();

    await Promise.all([
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileAId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      createActiveAttendance({
        staffProfileId:
          scenario.staffProfileBId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        workDate: WORK_DATE_STRING,
        actorId: scenario.ownerId,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileAId,
        proofCount: 3,
      }),
      seedExistingProofDraft({
        ownerId: scenario.ownerId,
        planId: scenario.planId,
        taskId: scenario.taskId,
        staffId:
          scenario.staffProfileBId,
        proofCount: 3,
      }),
    ]);

    const [firstResponse, secondResponse] =
      await Promise.all([
        postProgress({
          token: scenario.token,
          taskId:
            scenario.taskId.toString(),
          payload: {
            workDate: WORK_DATE_STRING,
            staffId:
              scenario.staffProfileAId.toString(),
            activityType: "none",
            unitContribution: 3,
            activityQuantity: 0,
            delayReason: STATUS_NONE,
            notes: "concurrent close a",
          },
        }),
        postProgress({
          token: scenario.token,
          taskId:
            scenario.taskId.toString(),
          payload: {
            workDate: WORK_DATE_STRING,
            staffId:
              scenario.staffProfileBId.toString(),
            activityType: "none",
            unitContribution: 3,
            activityQuantity: 0,
            delayReason: STATUS_NONE,
            notes: "concurrent close b",
          },
        }),
      ]);

    const statusCodes = [
      firstResponse.statusCode,
      secondResponse.statusCode,
    ].sort((left, right) => left - right);
    assert.deepEqual(
      statusCodes,
      [HTTP_OK, HTTP_BAD_REQUEST],
    );

    const ledger =
      await ProductionTaskDayLedger.findOne({
        taskId: scenario.taskId,
        workDate:
          WORK_DATE_NORMALIZED,
      }).lean();
    assert.ok(ledger);
    assert.ok(
      Number(ledger.unitCompleted) <= 5,
    );
    assert.ok(
      Number(ledger.unitRemaining) >= 0,
    );
    assert.equal(
      ledger.unitCompleted,
      3,
    );
    assert.equal(
      ledger.unitRemaining,
      2,
    );
  },
);
