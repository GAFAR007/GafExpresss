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
const multer = require("multer");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");
const { MongoMemoryReplSet } = require("mongodb-memory-server");

require("dotenv").config({
  path: path.resolve(__dirname, "../.env"),
});

const { requireAuth } = require("../middlewares/auth.middleware");
const { requireAnyRole } = require("../middlewares/requireRole.middleware");
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
const staffAttendanceProofService = require("../services/staff_attendance_proof.service");

const ROUTE_PREFIX = "/business/production/tasks";
const ATTENDANCE_ROUTE_PREFIX = "/business/staff/attendance";
const OWNER_ROLE = "business_owner";
const STAFF_ROLE_FARMER = "farmer";
const HTTP_OK = 200;
const HTTP_BAD_REQUEST = 400;
const HTTP_CONFLICT = 409;
const STATUS_NONE = "none";
const WORK_DATE_STRING = "2026-04-12";
const WORK_DATE_NORMALIZED = new Date("2026-04-12T00:00:00.000Z");
const PLOT_UNIT_SCALE = 1000;
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

let server;
let testDbUri = "";
let mongoReplSet = null;
const originalUploadStaffAttendanceProof =
  staffAttendanceProofService.uploadStaffAttendanceProof;
const originalUploadStaffAttendanceProofs =
  staffAttendanceProofService.uploadStaffAttendanceProofs;

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

function parseTaskProgressProofUploads(req, res, next) {
  const contentType = (req.headers["content-type"] || "")
    .toString()
    .toLowerCase();
  if (!contentType.includes("multipart/form-data")) {
    return next();
  }
  return upload.array("proofs", 10)(req, res, next);
}

function parseAttendanceProofUploads(req, res, next) {
  const contentType = (req.headers["content-type"] || "")
    .toString()
    .toLowerCase();
  if (!contentType.includes("multipart/form-data")) {
    return next();
  }
  return upload.fields([
    {
      name: "proof",
      maxCount: 1,
    },
    {
      name: "proofs",
      maxCount: 10,
    },
  ])(req, res, next);
}

function buildProgressApp() {
  const app = express();
  app.use(express.json());
  app.post(
    `${ATTENDANCE_ROUTE_PREFIX}/clock-in`,
    requireAuth,
    requireAnyRole([OWNER_ROLE, "staff"]),
    businessController.clockInStaff,
  );
  app.post(
    `${ATTENDANCE_ROUTE_PREFIX}/clock-out`,
    requireAuth,
    requireAnyRole([OWNER_ROLE, "staff"]),
    businessController.clockOutStaff,
  );
  app.post(
    `${ATTENDANCE_ROUTE_PREFIX}/clock-out-with-proof`,
    requireAuth,
    requireAnyRole([OWNER_ROLE, "staff"]),
    parseAttendanceProofUploads,
    businessController.clockOutStaffWithProof,
  );
  app.post(
    `${ATTENDANCE_ROUTE_PREFIX}/:attendanceId/proof`,
    requireAuth,
    requireAnyRole([OWNER_ROLE, "staff"]),
    parseAttendanceProofUploads,
    businessController.uploadStaffAttendanceProof,
  );
  app.post(
    `${ROUTE_PREFIX}/:taskId/progress`,
    requireAuth,
    requireAnyRole([OWNER_ROLE, "staff"]),
    parseTaskProgressProofUploads,
    businessController.logProductionTaskProgress,
  );
  app.post(
    `${ROUTE_PREFIX}/:taskId/reset-history`,
    requireAuth,
    requireAnyRole([OWNER_ROLE, "staff"]),
    businessController.resetProductionTaskHistory,
  );
  return app;
}

function issueOwnerToken(ownerId) {
  const secret = process.env.JWT_SECRET || "test_jwt_secret";
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
  return Math.round(Math.max(0, Number(plots || 0)) * PLOT_UNIT_SCALE);
}

function buildSeededProofs({ count, uploadedBy }) {
  return Array.from({ length: count }, (_, index) => ({
    url: `https://example.test/proof-${index + 1}.jpg`,
    publicId: `proof-${index + 1}`,
    filename: `proof-${index + 1}.jpg`,
    mimeType: "image/jpeg",
    sizeBytes: 1024 + index,
    uploadedAt: new Date(`2026-04-12T0${Math.min(index, 9)}:00:00.000Z`),
    uploadedBy,
  }));
}

function buildUploadedProofMetadata({ attendanceId, file, unitIndex }) {
  const normalizedFilename = file?.originalname || `proof-${unitIndex}.jpg`;
  const normalizedMimeType = file?.mimetype || "image/jpeg";
  const sanitizedFilename = normalizedFilename.replace(
    /[^a-zA-Z0-9._-]+/g,
    "-",
  );
  return {
    unitIndex: Math.max(1, Number(unitIndex || 1)),
    url: `https://example.test/staff-attendance/${attendanceId}/${unitIndex}/${sanitizedFilename}`,
    publicId: `staff-attendance/${attendanceId}/${unitIndex}/${sanitizedFilename}`,
    filename: normalizedFilename,
    mimeType: normalizedMimeType,
    type: normalizedMimeType.startsWith("image/") ? "image" : "document",
    sizeBytes: file?.size || Buffer.byteLength(file?.buffer || Buffer.alloc(0)),
    uploadedAt: new Date(
      `2026-04-12T${String(
        Math.min(Math.max(1, Number(unitIndex || 1)), 23),
      ).padStart(2, "0")}:00:00.000Z`,
    ),
  };
}

async function requestJson({ method, routePath, token, payload }) {
  return new Promise((resolve, reject) => {
    const payloadText = JSON.stringify(payload || {});
    const req = http.request(
      {
        method,
        hostname: "127.0.0.1",
        port: server.address().port,
        path: routePath,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payloadText),
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
              bodyText.trim().length > 0 ? JSON.parse(bodyText) : {};
            resolve({
              statusCode: res.statusCode || 0,
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

async function requestMultipart({
  method = "POST",
  routePath,
  token,
  fields = {},
  files = [],
}) {
  const formData = new FormData();
  Object.entries(fields).forEach(([key, value]) => {
    if (value == null) {
      return;
    }
    formData.append(
      key,
      typeof value === "string" ? value : JSON.stringify(value),
    );
  });
  files.forEach((file) => {
    formData.append(
      file.fieldName || "proof",
      new Blob(
        [file.bytes || Buffer.from(file.content || file.filename || "proof")],
        {
          type: file.contentType || "image/jpeg",
        },
      ),
      file.filename || "proof.jpg",
    );
  });

  const response = await fetch(
    `http://127.0.0.1:${server.address().port}${routePath}`,
    {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
      },
      body: formData,
    },
  );
  const bodyText = await response.text();
  return {
    statusCode: response.status,
    body: bodyText.trim().length > 0 ? JSON.parse(bodyText) : {},
  };
}

async function postProgress({ token, taskId, payload }) {
  return requestJson({
    method: "POST",
    routePath: `${ROUTE_PREFIX}/${taskId}/progress`,
    token,
    payload,
  });
}

async function postProgressMultipart({ token, taskId, fields, files }) {
  return requestMultipart({
    routePath: `${ROUTE_PREFIX}/${taskId}/progress`,
    token,
    fields,
    files,
  });
}

async function postResetTaskHistory({ token, taskId, payload }) {
  return requestJson({
    method: "POST",
    routePath: `${ROUTE_PREFIX}/${taskId}/reset-history`,
    token,
    payload,
  });
}

async function postClockIn({ token, payload }) {
  return requestJson({
    method: "POST",
    routePath: `${ATTENDANCE_ROUTE_PREFIX}/clock-in`,
    token,
    payload,
  });
}

async function postClockOut({ token, payload }) {
  return requestJson({
    method: "POST",
    routePath: `${ATTENDANCE_ROUTE_PREFIX}/clock-out`,
    token,
    payload,
  });
}

async function postClockOutWithProof({ token, fields, files }) {
  return requestMultipart({
    routePath: `${ATTENDANCE_ROUTE_PREFIX}/clock-out-with-proof`,
    token,
    fields,
    files,
  });
}

async function postAttendanceProof({ token, attendanceId, fields, files }) {
  return requestMultipart({
    routePath: `${ATTENDANCE_ROUTE_PREFIX}/${attendanceId}/proof`,
    token,
    fields,
    files,
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

async function createEstateAsset({ id, businessId, createdBy, name }) {
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
    purchaseDate: new Date("2026-01-01T00:00:00.000Z"),
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

async function createStaffProfile({ id, userId, businessId, estateAssetId }) {
  return BusinessStaffProfile.create({
    _id: id,
    userId,
    businessId,
    estateAssetId,
    staffRole: STAFF_ROLE_FARMER,
    employeeCode: `EMP-${id.toString().slice(-6)}`,
    employmentStatus: "active",
    hireDate: new Date("2026-01-01T00:00:00.000Z"),
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
    productId: new mongoose.Types.ObjectId(),
    title: "Rice Plan Test",
    startDate: new Date("2026-04-01T00:00:00.000Z"),
    endDate: new Date("2026-04-30T00:00:00.000Z"),
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

async function createPhase({ id, planId }) {
  return ProductionPhase.create({
    _id: id,
    planId,
    name: "Execution",
    order: 1,
    startDate: new Date("2026-04-01T00:00:00.000Z"),
    endDate: new Date("2026-04-30T00:00:00.000Z"),
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
    startDate: new Date("2026-04-01T00:00:00.000Z"),
    dueDate: new Date("2026-04-30T00:00:00.000Z"),
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
  const clockInAt = new Date(`${workDate}T08:00:00.000Z`);
  return StaffAttendance.create({
    staffProfileId,
    planId,
    taskId,
    workDate: new Date(`${workDate}T00:00:00.000Z`),
    clockInAt,
    clockOutAt: null,
    clockInBy: actorId,
    notes: "active attendance for endpoint test",
    proofs: [],
    requiredProofs: 0,
    proofStatus: "not_required",
    sessionStatus: "open",
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

async function createCompletedProgress({
  ownerId,
  planId,
  taskId,
  staffId,
  attendanceId = null,
  workDate = WORK_DATE_NORMALIZED,
  actualPlots = 1,
  proofCount = 1,
  approved = false,
  notes = "completed progress",
}) {
  return TaskProgress.create({
    taskId,
    planId,
    staffId,
    attendanceId,
    unitId: null,
    workDate,
    expectedPlots: 5,
    expectedPlotUnits: toPlotUnits(5),
    actualPlots,
    actualPlotUnits: toPlotUnits(actualPlots),
    unitContribution: actualPlots,
    unitContributionPlotUnits: toPlotUnits(actualPlots),
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
    sessionStatus: "completed",
    delayReason: STATUS_NONE,
    notes,
    createdBy: ownerId,
    approvedBy: approved ? ownerId : null,
    approvedAt: approved ? new Date("2026-04-12T18:00:00.000Z") : null,
  });
}

async function seedScenario({ plantingTargets = null } = {}) {
  const ownerId = new mongoose.Types.ObjectId();
  const staffUserAId = new mongoose.Types.ObjectId();
  const staffUserBId = new mongoose.Types.ObjectId();
  const businessId = ownerId;

  const estateAId = new mongoose.Types.ObjectId();
  const staffProfileAId = new mongoose.Types.ObjectId();
  const staffProfileBId = new mongoose.Types.ObjectId();
  const planId = new mongoose.Types.ObjectId();
  const phaseId = new mongoose.Types.ObjectId();
  const taskId = new mongoose.Types.ObjectId();

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
    assignedStaffId: staffProfileAId,
    assignedStaffProfileIds: [staffProfileAId, staffProfileBId],
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
  await Promise.all(RESET_MODELS.map((model) => model.deleteMany({})));
}

test.before(async () => {
  staffAttendanceProofService.uploadStaffAttendanceProof = async ({
    attendanceId,
    file,
    unitIndex = 1,
  }) =>
    buildUploadedProofMetadata({
      attendanceId,
      file,
      unitIndex,
    });
  staffAttendanceProofService.uploadStaffAttendanceProofs = async ({
    attendanceId,
    files,
    startingUnitIndex = 1,
  }) =>
    Promise.all(
      (files || []).map((file, index) =>
        buildUploadedProofMetadata({
          attendanceId,
          file,
          unitIndex: Number(startingUnitIndex) + index,
        }),
      ),
    );
  mongoReplSet = await MongoMemoryReplSet.create({
    replSet: {
      count: 1,
      storageEngine: "wiredTiger",
    },
  });
  testDbUri = mongoReplSet.getUri("production_task_progress_test");
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
  staffAttendanceProofService.uploadStaffAttendanceProof =
    originalUploadStaffAttendanceProof;
  staffAttendanceProofService.uploadStaffAttendanceProofs =
    originalUploadStaffAttendanceProofs;
});

test.afterEach(async () => {
  await resetDatabase();
});

test("clock-out without proof leaves attendance pending_proof and blocks the next clock-in", async () => {
  const scenario = await seedScenario();
  const clockInResponse = await postClockIn({
    token: scenario.token,
    payload: {
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      notes: "manager clocked in staff A",
    },
  });

  assert.equal(clockInResponse.statusCode, 201);
  const attendanceId = clockInResponse.body.attendance?._id;
  assert.ok(attendanceId);

  const clockOutResponse = await postClockOut({
    token: scenario.token,
    payload: {
      attendanceId,
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      requiredProofs: 1,
      notes: "clocked out without uploading proof",
    },
  });

  assert.equal(clockOutResponse.statusCode, HTTP_OK);
  assert.equal(
    clockOutResponse.body.attendance?.sessionStatus,
    "pending_proof",
  );
  assert.equal(clockOutResponse.body.attendance?.proofStatus, "missing");
  assert.equal(clockOutResponse.body.attendance?.requiredProofs, 1);
  assert.equal(clockOutResponse.body.attendance?.proofs?.length, 0);
  assert.equal(
    clockOutResponse.body.attendance?.clockOutAudit?.requiredProofs,
    1,
  );

  const savedAttendance = await StaffAttendance.findById(attendanceId).lean();
  assert.ok(savedAttendance?.clockOutAt);
  assert.equal(savedAttendance?.sessionStatus, "pending_proof");
  assert.equal(savedAttendance?.proofStatus, "missing");

  const blockedClockInResponse = await postClockIn({
    token: scenario.token,
    payload: {
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: "2026-04-13",
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      notes: "this should be blocked until proof is uploaded",
    },
  });

  assert.equal(blockedClockInResponse.statusCode, HTTP_CONFLICT);
  assert.equal(
    blockedClockInResponse.body.error,
    "Upload the missing proof for the previous attendance session before clocking in again",
  );
  assert.equal(blockedClockInResponse.body.attendance?._id, attendanceId);
  assert.equal(
    blockedClockInResponse.body.attendance?.sessionStatus,
    "pending_proof",
  );
});

test("clock-out-with-proof completes attendance in one request with multiple proofs", async () => {
  const scenario = await seedScenario();
  const clockInResponse = await postClockIn({
    token: scenario.token,
    payload: {
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      notes: "manager clocked in for single-step proof test",
    },
  });
  const attendanceId = clockInResponse.body.attendance?._id;
  assert.ok(attendanceId);

  const clockOutWithProofResponse = await postClockOutWithProof({
    token: scenario.token,
    fields: {
      attendanceId,
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      requiredProofs: 2,
      unitIndex: 1,
      notes: "clock-out completed with proof in one request",
      clockOutAudit: {
        workDate: WORK_DATE_STRING,
        planId: scenario.planId.toString(),
        taskId: scenario.taskId.toString(),
        staffProfileId: scenario.staffProfileAId.toString(),
        requiredProofs: 2,
        notes: "single-step clock-out with proof",
      },
    },
    files: [
      {
        fieldName: "proofs",
        filename: "clock-out-proof-1.jpg",
      },
      {
        fieldName: "proofs",
        filename: "clock-out-proof-2.jpg",
      },
    ],
  });

  assert.equal(clockOutWithProofResponse.statusCode, HTTP_OK);
  assert.equal(
    clockOutWithProofResponse.body.message,
    "Clock-out with proof recorded successfully",
  );
  assert.equal(
    clockOutWithProofResponse.body.attendance?.sessionStatus,
    "completed",
  );
  assert.equal(
    clockOutWithProofResponse.body.attendance?.proofStatus,
    "complete",
  );
  assert.equal(clockOutWithProofResponse.body.attendance?.requiredProofs, 2);
  assert.equal(clockOutWithProofResponse.body.attendance?.proofs?.length, 2);
  assert.equal(
    clockOutWithProofResponse.body.attendance?.proofs?.[0]?.filename,
    "clock-out-proof-1.jpg",
  );
  assert.equal(
    clockOutWithProofResponse.body.attendance?.proofs?.[1]?.filename,
    "clock-out-proof-2.jpg",
  );
  assert.equal(
    clockOutWithProofResponse.body.attendance?.proofFilename,
    "clock-out-proof-1.jpg",
  );
  assert.equal(
    clockOutWithProofResponse.body.attendance?.clockOutAudit?.requiredProofs,
    2,
  );

  const savedAttendance = await StaffAttendance.findById(attendanceId).lean();
  assert.ok(savedAttendance?.clockOutAt);
  assert.equal(savedAttendance?.sessionStatus, "completed");
  assert.equal(savedAttendance?.proofStatus, "complete");
  assert.equal(savedAttendance?.proofs?.length, 2);
});

test("proof uploads can accumulate multiple units and retry an existing unit", async () => {
  const scenario = await seedScenario();
  const clockInResponse = await postClockIn({
    token: scenario.token,
    payload: {
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
    },
  });
  const attendanceId = clockInResponse.body.attendance?._id;
  assert.ok(attendanceId);

  const clockOutResponse = await postClockOut({
    token: scenario.token,
    payload: {
      attendanceId,
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      requiredProofs: 2,
    },
  });
  assert.equal(clockOutResponse.statusCode, HTTP_OK);
  assert.equal(
    clockOutResponse.body.attendance?.sessionStatus,
    "pending_proof",
  );

  const firstProofResponse = await postAttendanceProof({
    token: scenario.token,
    attendanceId,
    fields: {
      unitIndex: 1,
      requiredProofs: 2,
      clockOutAudit: {
        workDate: WORK_DATE_STRING,
        planId: scenario.planId.toString(),
        taskId: scenario.taskId.toString(),
        staffProfileId: scenario.staffProfileAId.toString(),
        requiredProofs: 2,
        notes: "first proof upload",
      },
    },
    files: [
      {
        fieldName: "proof",
        filename: "unit-1.jpg",
      },
    ],
  });

  assert.equal(firstProofResponse.statusCode, HTTP_OK);
  assert.equal(
    firstProofResponse.body.attendance?.sessionStatus,
    "pending_proof",
  );
  assert.equal(firstProofResponse.body.attendance?.proofStatus, "missing");
  assert.equal(firstProofResponse.body.attendance?.proofs?.length, 1);
  assert.equal(
    firstProofResponse.body.attendance?.proofs?.[0]?.filename,
    "unit-1.jpg",
  );

  const secondProofResponse = await postAttendanceProof({
    token: scenario.token,
    attendanceId,
    fields: {
      unitIndex: 2,
      requiredProofs: 2,
    },
    files: [
      {
        fieldName: "proof",
        filename: "unit-2-first-pass.jpg",
      },
    ],
  });

  assert.equal(secondProofResponse.statusCode, HTTP_OK);
  assert.equal(secondProofResponse.body.attendance?.sessionStatus, "completed");
  assert.equal(secondProofResponse.body.attendance?.proofStatus, "complete");
  assert.equal(secondProofResponse.body.attendance?.proofs?.length, 2);
  assert.equal(
    secondProofResponse.body.attendance?.proofs?.[1]?.filename,
    "unit-2-first-pass.jpg",
  );

  const retryProofResponse = await postAttendanceProof({
    token: scenario.token,
    attendanceId,
    fields: {
      unitIndex: 2,
      requiredProofs: 2,
    },
    files: [
      {
        fieldName: "proof",
        filename: "unit-2-retry.jpg",
      },
    ],
  });

  assert.equal(retryProofResponse.statusCode, HTTP_OK);
  assert.equal(retryProofResponse.body.attendance?.sessionStatus, "completed");
  assert.equal(retryProofResponse.body.attendance?.proofs?.length, 2);
  assert.equal(
    retryProofResponse.body.attendance?.proofs?.[0]?.filename,
    "unit-1.jpg",
  );
  assert.equal(
    retryProofResponse.body.attendance?.proofs?.[1]?.filename,
    "unit-2-retry.jpg",
  );

  const savedAttendance = await StaffAttendance.findById(attendanceId).lean();
  assert.equal(savedAttendance?.proofs?.length, 2);
  assert.equal(savedAttendance?.proofs?.[1]?.filename, "unit-2-retry.jpg");
});

test("production progress proof upload and quick clock-out-with-proof end in the same completed attendance state", async () => {
  const scenario = await seedScenario();
  const quickClockInResponse = await postClockIn({
    token: scenario.token,
    payload: {
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
    },
  });
  const quickAttendanceId = quickClockInResponse.body.attendance?._id;
  assert.ok(quickAttendanceId);

  const quickClockOutResponse = await postClockOutWithProof({
    token: scenario.token,
    fields: {
      attendanceId: quickAttendanceId,
      staffProfileId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
      requiredProofs: 1,
    },
    files: [
      {
        fieldName: "proof",
        filename: "quick-clock-out-proof.jpg",
      },
    ],
  });

  assert.equal(quickClockOutResponse.statusCode, HTTP_OK);

  const wizardClockInResponse = await postClockIn({
    token: scenario.token,
    payload: {
      staffProfileId: scenario.staffProfileBId.toString(),
      workDate: WORK_DATE_STRING,
      planId: scenario.planId.toString(),
      taskId: scenario.taskId.toString(),
    },
  });
  const wizardAttendanceId = wizardClockInResponse.body.attendance?._id;
  assert.ok(wizardAttendanceId);

  const wizardProgressResponse = await postProgressMultipart({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    fields: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileBId.toString(),
      activityType: "transplanted",
      unitContribution: 1,
      activityQuantity: 250,
      delayReason: STATUS_NONE,
      notes: "wizard save closes attendance with proof",
    },
    files: [
      {
        fieldName: "proofs",
        filename: "wizard-proof.jpg",
      },
    ],
  });

  assert.equal(wizardProgressResponse.statusCode, HTTP_OK);

  const quickAttendance =
    await StaffAttendance.findById(quickAttendanceId).lean();
  const wizardAttendance =
    await StaffAttendance.findById(wizardAttendanceId).lean();
  const wizardProgress = await TaskProgress.findOne({
    taskId: scenario.taskId,
    staffId: scenario.staffProfileBId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();

  assert.ok(quickAttendance);
  assert.ok(wizardAttendance);
  assert.ok(wizardProgress);
  assert.equal(wizardProgress?.attendanceId?.toString(), wizardAttendanceId);
  assert.equal(wizardProgress?.proofCountRequired, 1);
  assert.equal(wizardProgress?.proofCountUploaded, 1);
  assert.equal(wizardProgress?.proofs?.length, 1);
  assert.equal(wizardProgress?.proofs?.[0]?.filename, "wizard-proof.jpg");

  [quickAttendance, wizardAttendance].forEach((attendance) => {
    assert.ok(attendance.clockOutAt);
    assert.equal(attendance.sessionStatus, "completed");
    assert.equal(attendance.proofStatus, "complete");
    assert.equal(attendance.requiredProofs, 1);
    assert.equal(attendance.proofs?.length, 1);
    assert.ok(attendance.clockOutAudit);
  });
});

test("positive unit contribution without proofs is rejected and leaves the shared ledger untouched", async () => {
  const scenario = await seedScenario();
  await createActiveAttendance({
    staffProfileId: scenario.staffProfileAId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    workDate: WORK_DATE_STRING,
    actorId: scenario.ownerId,
  });

  const response = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "transplanted",
      unitContribution: 1.5,
      activityQuantity: 500,
      delayReason: STATUS_NONE,
      notes: "missing proofs should fail",
    },
  });

  assert.equal(response.statusCode, HTTP_BAD_REQUEST);
  assert.equal(
    response.body.error,
    "Complete attendance proof before saving or batching production progress.",
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
  const activeAttendance = await StaffAttendance.findOne({
    taskId: scenario.taskId,
    staffProfileId: scenario.staffProfileAId,
  }).lean();
  assert.ok(activeAttendance);
  assert.equal(activeAttendance.clockOutAt, null);
});

test("no quantity update reuses proof-backed attendance without changing shared totals", async () => {
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
    staffProfileId: scenario.staffProfileAId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    workDate: WORK_DATE_STRING,
    actorId: scenario.ownerId,
  });
  await seedExistingProofDraft({
    ownerId: scenario.ownerId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    proofCount: 1,
  });

  const response = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "none",
      activityQuantity: 0,
      delayReason: STATUS_NONE,
      notes: "clock out without quantity update",
    },
  });

  assert.equal(response.statusCode, HTTP_OK);
  assert.equal(response.body.ledger.unitCompleted, 0);
  assert.equal(response.body.ledger.unitRemaining, 5);
  assert.equal(response.body.ledger.activityCompleted.transplanted, 0);

  const savedAttendance = await StaffAttendance.findOne({
    taskId: scenario.taskId,
    staffProfileId: scenario.staffProfileAId,
  }).lean();
  assert.ok(savedAttendance?.clockOutAt);

  const savedProgress = await TaskProgress.findOne({
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(savedProgress);
  assert.equal(savedProgress.sessionStatus, "completed");
  assert.equal(savedProgress.unitContribution, 0);
  assert.equal(savedProgress.activityType, "none");
  assert.equal(savedProgress.activityQuantity, 0);
  assert.equal(savedProgress.proofCountRequired, 1);
  assert.equal(savedProgress.proofCountUploaded, 1);
});

test("single-entry clock-out reuses an open same-day attendance from another task", async () => {
  const scenario = await seedScenario();
  const secondaryTaskId = new mongoose.Types.ObjectId();

  await createTask({
    id: secondaryTaskId,
    planId: scenario.planId,
    phaseId: scenario.phaseId,
    title: "Sibling Task",
    assignedStaffId: scenario.staffProfileAId,
    assignedStaffProfileIds: [scenario.staffProfileAId],
    createdBy: scenario.ownerId,
    weight: 3,
  });

  const openAttendance = await createActiveAttendance({
    staffProfileId: scenario.staffProfileAId,
    planId: scenario.planId,
    taskId: secondaryTaskId,
    workDate: WORK_DATE_STRING,
    actorId: scenario.ownerId,
  });

  await seedExistingProofDraft({
    ownerId: scenario.ownerId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    proofCount: 4,
  });

  const response = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "none",
      unitContribution: 3.5,
      activityQuantity: 0,
      delayReason: STATUS_NONE,
      notes: "finish current task from shared open attendance",
    },
  });

  assert.equal(response.statusCode, HTTP_OK);
  assert.equal(response.body.ledger.unitCompleted, 3.5);
  assert.equal(response.body.ledger.unitRemaining, 1.5);

  const savedAttendance = await StaffAttendance.findById(
    openAttendance._id,
  ).lean();
  assert.ok(savedAttendance?.clockOutAt);
  assert.equal(savedAttendance.taskId.toString(), scenario.taskId.toString());
  assert.equal(savedAttendance.planId.toString(), scenario.planId.toString());

  const savedProgress = await TaskProgress.findOne({
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(savedProgress);
  assert.equal(savedProgress.unitContribution, 3.5);
  assert.equal(savedProgress.proofCountRequired, 4);
  assert.equal(savedProgress.proofCountUploaded, 4);
  assert.equal(savedProgress.sessionStatus, "completed");
  assert.ok(savedProgress.clockInTime);
  assert.ok(savedProgress.clockOutTime);
});

test("single-entry production logging shares unit and activity totals across staff for the same day", async () => {
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
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    createActiveAttendance({
      staffProfileId: scenario.staffProfileBId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 4,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileBId,
      proofCount: 2,
    }),
  ]);

  const firstResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "transplanted",
      unitContribution: 3.5,
      activityQuantity: 500,
      delayReason: STATUS_NONE,
      notes: "staff a shared contribution",
    },
  });

  assert.equal(firstResponse.statusCode, HTTP_OK);
  assert.equal(firstResponse.body.ledger.unitCompleted, 3.5);
  assert.equal(firstResponse.body.ledger.unitRemaining, 1.5);
  assert.equal(firstResponse.body.ledger.activityCompleted.transplanted, 500);
  assert.equal(firstResponse.body.ledger.activityRemaining.transplanted, 1500);

  const secondResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileBId.toString(),
      activityType: "transplanted",
      unitContribution: 1.5,
      activityQuantity: 500,
      delayReason: STATUS_NONE,
      notes: "staff b shared contribution",
    },
  });

  assert.equal(secondResponse.statusCode, HTTP_OK);
  assert.equal(secondResponse.body.ledger.unitCompleted, 5);
  assert.equal(secondResponse.body.ledger.unitRemaining, 0);
  assert.equal(secondResponse.body.ledger.status, "completed");
  assert.equal(secondResponse.body.ledger.activityCompleted.transplanted, 1000);
  assert.equal(secondResponse.body.ledger.activityRemaining.transplanted, 1000);

  const ledger = await ProductionTaskDayLedger.findOne({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(ledger);
  assert.equal(ledger.unitCompleted, 5);
  assert.equal(ledger.unitRemaining, 0);
  assert.equal(ledger.activityCompleted.transplanted, 1000);
  assert.equal(ledger.activityRemaining.transplanted, 1000);

  const progressRows = await TaskProgress.find({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.equal(progressRows.length, 2);
  const firstRow = progressRows.find(
    (row) => row.staffId.toString() === scenario.staffProfileAId.toString(),
  );
  const secondRow = progressRows.find(
    (row) => row.staffId.toString() === scenario.staffProfileBId.toString(),
  );
  assert.equal(firstRow.proofCountRequired, 4);
  assert.equal(firstRow.proofCountUploaded, 4);
  assert.equal(secondRow.proofCountRequired, 2);
  assert.equal(secondRow.proofCountUploaded, 2);
});

test("createNewEntry appends a second count for the same staff and day without overwriting the latest saved row", async () => {
  const scenario = await seedScenario({
    plantingTargets: {
      materialType: "seedling",
      plannedPlantingQuantity: 2000,
      plannedPlantingUnit: "seedlings",
      estimatedHarvestQuantity: 400,
      estimatedHarvestUnit: "kg",
    },
  });

  await Promise.all([
    createActiveAttendance({
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 2,
    }),
  ]);

  const firstResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      unitContribution: 2,
      activityType: "transplanted",
      activityQuantity: 400,
      delayReason: STATUS_NONE,
      notes: "first count",
    },
  });

  assert.equal(firstResponse.statusCode, HTTP_OK);
  assert.equal(firstResponse.body.progress.entryIndex, 1);

  const secondResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      unitContribution: 1,
      activityType: "transplanted",
      activityQuantity: 150,
      createNewEntry: true,
      delayReason: STATUS_NONE,
      notes: "second count",
    },
  });

  assert.equal(secondResponse.statusCode, HTTP_OK);
  assert.equal(secondResponse.body.progress.entryIndex, 2);
  assert.equal(secondResponse.body.ledger.unitCompleted, 3);
  assert.equal(secondResponse.body.ledger.unitRemaining, 2);

  const progressRows = await TaskProgress.find({
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    workDate: WORK_DATE_NORMALIZED,
  })
    .sort({ entryIndex: 1 })
    .lean();

  assert.equal(progressRows.length, 2);
  assert.equal(progressRows[0].entryIndex, 1);
  assert.equal(progressRows[0].unitContribution, 2);
  assert.equal(progressRows[1].entryIndex, 2);
  assert.equal(progressRows[1].unitContribution, 1);
});

test("fresh backend validation blocks activity oversubmission against the shared remaining target", async () => {
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
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    createActiveAttendance({
      staffProfileId: scenario.staffProfileBId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 2,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileBId,
      proofCount: 1,
    }),
  ]);

  const firstResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "transplanted",
      unitContribution: 2,
      activityQuantity: 1500,
      delayReason: STATUS_NONE,
      notes: "consumes most of the activity target",
    },
  });
  assert.equal(firstResponse.statusCode, HTTP_OK);

  const secondResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileBId.toString(),
      activityType: "transplanted",
      unitContribution: 1,
      activityQuantity: 600,
      delayReason: STATUS_NONE,
      notes: "tries to exceed activity remaining",
    },
  });

  assert.equal(secondResponse.statusCode, HTTP_BAD_REQUEST);
  assert.equal(
    secondResponse.body.error,
    "Activity quantity exceeds the remaining shared activity target",
  );
  assert.equal(secondResponse.body.activityType, "transplanted");
  assert.equal(secondResponse.body.maxAllowedActivityQuantity, 500);

  const ledger = await ProductionTaskDayLedger.findOne({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(ledger);
  assert.equal(ledger.unitCompleted, 2);
  assert.equal(ledger.unitRemaining, 3);
  assert.equal(ledger.activityCompleted.transplanted, 1500);
  assert.equal(ledger.activityRemaining.transplanted, 500);
});

test("decimal production clock-out uses ceiling proof count and closes attendance on success", async () => {
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
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 2,
    }),
  ]);

  const response = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "planted",
      unitContribution: 1.2,
      activityQuantity: 400,
      delayReason: STATUS_NONE,
      notes: "decimal contribution with ceil proof rule",
    },
  });

  assert.equal(response.statusCode, HTTP_OK);
  assert.equal(response.body.ledger.unitCompleted, 1.2);
  assert.equal(response.body.ledger.unitRemaining, 3.8);
  assert.equal(response.body.ledger.activityCompleted.planted, 400);

  const savedAttendance = await StaffAttendance.findOne({
    taskId: scenario.taskId,
    staffProfileId: scenario.staffProfileAId,
  }).lean();
  assert.ok(savedAttendance?.clockOutAt);

  const savedProgress = await TaskProgress.findOne({
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(savedProgress?.clockOutTime);
  assert.equal(savedProgress.proofCountRequired, 2);
  assert.equal(savedProgress.proofCountUploaded, 2);
  assert.equal(savedProgress.activityType, "planted");
  assert.equal(savedProgress.activityQuantity, 400);
  assert.equal(savedProgress.sessionStatus, "completed");
});

test("planted and harvested clock-out saves update their own shared activity buckets", async () => {
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
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    createActiveAttendance({
      staffProfileId: scenario.staffProfileBId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 1,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileBId,
      proofCount: 2,
    }),
  ]);

  const plantedResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "planted",
      unitContribution: 1,
      activityQuantity: 500,
      delayReason: STATUS_NONE,
      notes: "planted update",
    },
  });
  assert.equal(plantedResponse.statusCode, HTTP_OK);

  const harvestedResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileBId.toString(),
      activityType: "harvested",
      unitContribution: 2,
      activityQuantity: 120,
      delayReason: STATUS_NONE,
      notes: "harvested update",
    },
  });
  assert.equal(harvestedResponse.statusCode, HTTP_OK);

  const ledger = await ProductionTaskDayLedger.findOne({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(ledger);
  assert.equal(ledger.unitCompleted, 3);
  assert.equal(ledger.activityCompleted.planted, 500);
  assert.equal(ledger.activityCompleted.harvested, 120);
  assert.equal(ledger.activityRemaining.planted, 1500);
  assert.equal(ledger.activityRemaining.harvested, 380);
});

test("fresh backend validation blocks stale primary unit submissions against the latest shared remaining", async () => {
  const scenario = await seedScenario();

  await Promise.all([
    createActiveAttendance({
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    createActiveAttendance({
      staffProfileId: scenario.staffProfileBId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 4,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileBId,
      proofCount: 2,
    }),
  ]);

  const firstResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileAId.toString(),
      activityType: "none",
      unitContribution: 4,
      activityQuantity: 0,
      delayReason: STATUS_NONE,
      notes: "consumes most of the primary target",
    },
  });
  assert.equal(firstResponse.statusCode, HTTP_OK);

  const staleResponse = await postProgress({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      workDate: WORK_DATE_STRING,
      staffId: scenario.staffProfileBId.toString(),
      activityType: "none",
      unitContribution: 2,
      activityQuantity: 0,
      delayReason: STATUS_NONE,
      notes: "tries to exceed the remaining shared units",
    },
  });

  assert.equal(staleResponse.statusCode, HTTP_BAD_REQUEST);
  assert.equal(
    staleResponse.body.error,
    "Actual progress exceeds the remaining planned task target",
  );
  assert.equal(staleResponse.body.maxAllowedPlots, 1);
  assert.equal(staleResponse.body.maxAllowedPlotUnits, toPlotUnits(1));

  const ledger = await ProductionTaskDayLedger.findOne({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(ledger);
  assert.equal(ledger.unitCompleted, 4);
  assert.equal(ledger.unitRemaining, 1);
});

test("concurrent production clock-out saves do not overrun the shared task target", async () => {
  const scenario = await seedScenario();

  await Promise.all([
    createActiveAttendance({
      staffProfileId: scenario.staffProfileAId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    createActiveAttendance({
      staffProfileId: scenario.staffProfileBId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      workDate: WORK_DATE_STRING,
      actorId: scenario.ownerId,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileAId,
      proofCount: 3,
    }),
    seedExistingProofDraft({
      ownerId: scenario.ownerId,
      planId: scenario.planId,
      taskId: scenario.taskId,
      staffId: scenario.staffProfileBId,
      proofCount: 3,
    }),
  ]);

  const [firstResponse, secondResponse] = await Promise.all([
    postProgress({
      token: scenario.token,
      taskId: scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId: scenario.staffProfileAId.toString(),
        activityType: "none",
        unitContribution: 3,
        activityQuantity: 0,
        delayReason: STATUS_NONE,
        notes: "concurrent close a",
      },
    }),
    postProgress({
      token: scenario.token,
      taskId: scenario.taskId.toString(),
      payload: {
        workDate: WORK_DATE_STRING,
        staffId: scenario.staffProfileBId.toString(),
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
  assert.deepEqual(statusCodes, [HTTP_OK, HTTP_BAD_REQUEST]);

  const ledger = await ProductionTaskDayLedger.findOne({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(ledger);
  assert.ok(Number(ledger.unitCompleted) <= 5);
  assert.ok(Number(ledger.unitRemaining) >= 0);
  assert.equal(ledger.unitCompleted, 3);
  assert.equal(ledger.unitRemaining, 2);
});

test("reset-history clears one staff task/day attendance and progress, then recomputes the shared ledger", async () => {
  const scenario = await seedScenario();
  const resettableAttendance = await StaffAttendance.create({
    staffProfileId: scenario.staffProfileAId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    // WHY: Exercise the reset fallback when attendance workDate drifted off the true work day.
    workDate: new Date("2026-04-11T00:00:00.000Z"),
    clockInAt: new Date("2026-04-12T08:06:00.000Z"),
    clockOutAt: new Date("2026-04-12T20:49:00.000Z"),
    durationMinutes: 763,
    clockInBy: scenario.ownerId,
    clockOutBy: scenario.ownerId,
    notes: "resettable attendance",
    proofs: buildSeededProofs({
      count: 1,
      uploadedBy: scenario.ownerId,
    }),
    requiredProofs: 1,
    proofStatus: "complete",
    sessionStatus: "completed",
  });
  const progressA = await createCompletedProgress({
    ownerId: scenario.ownerId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    attendanceId: resettableAttendance._id,
    actualPlots: 2,
    proofCount: 1,
    notes: "reset this staff history",
  });
  const progressB = await createCompletedProgress({
    ownerId: scenario.ownerId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    staffId: scenario.staffProfileBId,
    actualPlots: 1,
    proofCount: 1,
    notes: "keep this staff history",
  });

  const response = await postResetTaskHistory({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      staffId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
      notes: "manager reset from workspace",
    },
  });

  assert.equal(response.statusCode, HTTP_OK);
  assert.equal(response.body.message, "Production history reset successfully");
  assert.equal(response.body.deletedProgressCount, 1);
  assert.equal(response.body.deletedAttendanceCount, 1);
  assert.equal(response.body.staffId, scenario.staffProfileAId.toString());
  assert.equal(response.body.workDate, WORK_DATE_NORMALIZED.toISOString());
  assert.equal(response.body.ledger.unitCompleted, 1);
  assert.equal(response.body.ledger.unitRemaining, 4);

  const deletedProgress = await TaskProgress.findById(progressA._id).lean();
  const remainingProgress = await TaskProgress.findById(progressB._id).lean();
  const deletedAttendance = await StaffAttendance.findById(
    resettableAttendance._id,
  ).lean();
  const remainingLedger = await ProductionTaskDayLedger.findOne({
    taskId: scenario.taskId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();

  assert.equal(deletedProgress, null);
  assert.equal(deletedAttendance, null);
  assert.ok(remainingProgress);
  assert.equal(
    remainingProgress.staffId.toString(),
    scenario.staffProfileBId.toString(),
  );
  assert.ok(remainingLedger);
  assert.equal(remainingLedger.unitCompleted, 1);
  assert.equal(remainingLedger.unitRemaining, 4);
});

test("reset-history refuses to delete approved progress rows", async () => {
  const scenario = await seedScenario();
  await createCompletedProgress({
    ownerId: scenario.ownerId,
    planId: scenario.planId,
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    actualPlots: 2,
    proofCount: 1,
    approved: true,
    notes: "approved progress cannot be reset automatically",
  });

  const response = await postResetTaskHistory({
    token: scenario.token,
    taskId: scenario.taskId.toString(),
    payload: {
      staffId: scenario.staffProfileAId.toString(),
      workDate: WORK_DATE_STRING,
    },
  });

  assert.equal(response.statusCode, HTTP_CONFLICT);
  assert.equal(
    response.body.error,
    "Approved progress must be reviewed manually before resetting this production history",
  );
  assert.equal(response.body.approvedProgressCount, 1);

  const remainingProgress = await TaskProgress.findOne({
    taskId: scenario.taskId,
    staffId: scenario.staffProfileAId,
    workDate: WORK_DATE_NORMALIZED,
  }).lean();
  assert.ok(remainingProgress);
  assert.ok(remainingProgress.approvedAt);
});
