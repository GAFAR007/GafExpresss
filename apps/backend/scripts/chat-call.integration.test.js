/**
 * backend/scripts/chat-call.integration.test.js
 * ---------------------------------------------
 * WHAT:
 * - Integration tests for chat call lifecycle routes.
 *
 * WHY:
 * - Validates direct-call rules, state transitions, and system messages.
 *
 * HOW:
 * - Uses the real auth middleware + chat controller over HTTP JSON.
 * - Seeds isolated MongoDB fixtures in a reusable test database.
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
const chatController = require("../controllers/chat.controller");
const User = require("../models/User");
const ChatConversation = require("../models/ChatConversation");
const ChatParticipant = require("../models/ChatParticipant");
const ChatMessage = require("../models/ChatMessage");
const ChatCallSession = require("../models/ChatCallSession");

const TEST_LOG_TAG = "CHAT_CALL_TEST";
const TEST_DB_NAME = "chat_call_test";
const TEST_DB_REQUIRED_COLLECTIONS = [
  "users",
  "chatconversations",
  "chatparticipants",
  "chatmessages",
  "chatcallsessions",
];
const TEST_DB_NAME_PATTERN =
  /^(chat_call_test|cct_[a-z0-9]+_[a-z0-9]+)$/;

const HTTP_CREATED = 201;
const HTTP_OK = 200;
const HTTP_BAD_REQUEST = 400;
const HTTP_CONFLICT = 409;

const RESET_MODELS = [
  ChatMessage,
  ChatCallSession,
  ChatParticipant,
  ChatConversation,
  User,
];

let server = null;
let testDbUri = "";

function buildChatCallApp() {
  const app = express();
  app.use(express.json());

  app.post(
    "/chat/calls",
    requireAuth,
    chatController.startCall,
  );
  app.post(
    "/chat/calls/:callId/accept",
    requireAuth,
    chatController.acceptCall,
  );
  app.post(
    "/chat/calls/:callId/end",
    requireAuth,
    chatController.endCall,
  );

  return app;
}

function issueToken({ userId, role }) {
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
  method,
  routePath,
  token,
  payload,
}) {
  return new Promise((resolve, reject) => {
    const payloadText = JSON.stringify(payload || {});
    const request = http.request(
      {
        method,
        hostname: "127.0.0.1",
        port: server.address().port,
        path: routePath,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payloadText),
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
            statusCode: response.statusCode || 0,
            body: parsed,
          });
        });
      },
    );

    request.on("error", reject);
    request.write(payloadText);
    request.end();
  });
}

async function startCall({
  token,
  conversationId,
}) {
  return requestJson({
    method: "POST",
    routePath: "/chat/calls",
    token,
    payload: {
      conversationId,
      mediaMode: "audio",
    },
  });
}

async function acceptCall({
  token,
  callId,
}) {
  return requestJson({
    method: "POST",
    routePath: `/chat/calls/${callId}/accept`,
    token,
    payload: {},
  });
}

async function endCall({
  token,
  callId,
  reason,
}) {
  return requestJson({
    method: "POST",
    routePath: `/chat/calls/${callId}/end`,
    token,
    payload: {
      ...(reason ? { reason } : {}),
    },
  });
}

async function createUser({
  id,
  role,
  businessId = null,
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

async function createConversation({
  id,
  businessId,
  type,
  createdByUserId,
  title = "",
}) {
  return ChatConversation.create({
    _id: id,
    businessId,
    type,
    title,
    createdByUserId,
  });
}

async function addParticipants({
  conversationId,
  userIds,
}) {
  await ChatParticipant.insertMany(
    userIds.map((userId) => ({
      conversationId,
      userId,
      roleAtJoin: "",
    })),
  );
}

async function seedDirectConversation() {
  const ownerId = new mongoose.Types.ObjectId();
  const staffId = new mongoose.Types.ObjectId();
  const conversationId = new mongoose.Types.ObjectId();

  await createUser({
    id: ownerId,
    role: "business_owner",
    email: `owner-${ownerId.toString().slice(-6)}@example.test`,
  });
  await createUser({
    id: staffId,
    role: "staff",
    businessId: ownerId,
    email: `staff-${staffId.toString().slice(-6)}@example.test`,
  });
  await createConversation({
    id: conversationId,
    businessId: ownerId,
    type: "direct",
    createdByUserId: ownerId,
  });
  await addParticipants({
    conversationId,
    userIds: [ownerId, staffId],
  });

  return {
    ownerId,
    staffId,
    conversationId,
  };
}

async function seedGroupConversation() {
  const ownerId = new mongoose.Types.ObjectId();
  const staffAId = new mongoose.Types.ObjectId();
  const staffBId = new mongoose.Types.ObjectId();
  const conversationId = new mongoose.Types.ObjectId();

  await createUser({
    id: ownerId,
    role: "business_owner",
    email: `owner-group-${ownerId.toString().slice(-6)}@example.test`,
  });
  await createUser({
    id: staffAId,
    role: "staff",
    businessId: ownerId,
    email: `staff-a-${staffAId.toString().slice(-6)}@example.test`,
  });
  await createUser({
    id: staffBId,
    role: "staff",
    businessId: ownerId,
    email: `staff-b-${staffBId.toString().slice(-6)}@example.test`,
  });
  await createConversation({
    id: conversationId,
    businessId: ownerId,
    type: "group",
    title: "Ops",
    createdByUserId: ownerId,
  });
  await addParticipants({
    conversationId,
    userIds: [ownerId, staffAId, staffBId],
  });

  return {
    ownerId,
    conversationId,
  };
}

async function purgeTestData() {
  for (const model of RESET_MODELS) {
    await model.deleteMany({});
  }
}

test.before(async () => {
  testDbUri = await resolveReusableTestDbUri({
    baseUri: process.env.MONGO_URI,
    preferredDbName: TEST_DB_NAME,
    requiredCollections: TEST_DB_REQUIRED_COLLECTIONS,
    dbNamePattern: TEST_DB_NAME_PATTERN,
  });

  debug(TEST_LOG_TAG, "Connecting chat call test database", {
    hasMongoUri: Boolean(process.env.MONGO_URI),
    testDbUri,
  });

  await mongoose.connect(testDbUri);
  server = buildChatCallApp().listen(0);
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
});

test.beforeEach(async () => {
  await purgeTestData();
});

test("direct call starts, becomes active, and ends with system events", async () => {
  const seed = await seedDirectConversation();
  const ownerToken = issueToken({
    userId: seed.ownerId,
    role: "business_owner",
  });
  const staffToken = issueToken({
    userId: seed.staffId,
    role: "staff",
  });

  const startResponse = await startCall({
    token: ownerToken,
    conversationId: seed.conversationId.toString(),
  });

  assert.equal(
    startResponse.statusCode,
    HTTP_CREATED,
  );
  assert.equal(
    startResponse.body.call.state,
    "ringing",
  );

  const acceptResponse = await acceptCall({
    token: staffToken,
    callId: startResponse.body.call._id,
  });

  assert.equal(
    acceptResponse.statusCode,
    HTTP_OK,
  );
  assert.equal(
    acceptResponse.body.call.state,
    "active",
  );

  const startedMessage = await ChatMessage.findOne({
    conversationId: seed.conversationId,
    eventType: "call_started",
  }).lean();
  assert.ok(startedMessage);
  assert.equal(
    startedMessage?.type,
    "system",
  );

  const endResponse = await endCall({
    token: ownerToken,
    callId: startResponse.body.call._id,
    reason: "ended",
  });

  assert.equal(
    endResponse.statusCode,
    HTTP_OK,
  );
  assert.equal(
    endResponse.body.call.state,
    "ended",
  );

  const endedMessage = await ChatMessage.findOne({
    conversationId: seed.conversationId,
    eventType: "call_ended",
  }).lean();
  assert.ok(endedMessage);
});

test("group conversations reject voice calls", async () => {
  const seed = await seedGroupConversation();
  const ownerToken = issueToken({
    userId: seed.ownerId,
    role: "business_owner",
  });

  const response = await startCall({
    token: ownerToken,
    conversationId: seed.conversationId.toString(),
  });

  assert.equal(
    response.statusCode,
    HTTP_BAD_REQUEST,
  );
  assert.equal(
    response.body.error,
    "Calls are available only for direct conversations",
  );
});

test("starting a second call while the first is ringing returns conflict", async () => {
  const seed = await seedDirectConversation();
  const ownerToken = issueToken({
    userId: seed.ownerId,
    role: "business_owner",
  });

  const firstResponse = await startCall({
    token: ownerToken,
    conversationId: seed.conversationId.toString(),
  });

  assert.equal(
    firstResponse.statusCode,
    HTTP_CREATED,
  );

  const secondResponse = await startCall({
    token: ownerToken,
    conversationId: seed.conversationId.toString(),
  });

  assert.equal(
    secondResponse.statusCode,
    HTTP_CONFLICT,
  );
  assert.equal(
    secondResponse.body.error,
    "Another call is already ringing or active for this conversation",
  );
  assert.equal(
    secondResponse.body.activeCall?.state,
    "ringing",
  );
});

test("caller can mark an unanswered ringing call as missed", async () => {
  const seed = await seedDirectConversation();
  const ownerToken = issueToken({
    userId: seed.ownerId,
    role: "business_owner",
  });

  const startResponse = await startCall({
    token: ownerToken,
    conversationId: seed.conversationId.toString(),
  });

  const missedResponse = await endCall({
    token: ownerToken,
    callId: startResponse.body.call._id,
    reason: "missed",
  });

  assert.equal(
    missedResponse.statusCode,
    HTTP_OK,
  );
  assert.equal(
    missedResponse.body.call.state,
    "missed",
  );

  const missedMessage = await ChatMessage.findOne({
    conversationId: seed.conversationId,
    eventType: "call_missed",
  }).lean();
  assert.ok(missedMessage);
});
