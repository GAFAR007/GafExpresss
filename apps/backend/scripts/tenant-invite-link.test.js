/**
 * backend/scripts/tenant-invite-link.test.js
 * -----------------------------------------
 * WHAT:
 * - Verifies tenant invite links can be created with or without email delivery.
 *
 * WHY:
 * - Confirms the new "create request link" path does not send email.
 * - Guards the existing email-delivery path so the two actions stay distinct.
 *
 * HOW:
 * - Loads the invite service with stubbed model/email dependencies.
 * - Asserts the link-only flow skips email while still returning a usable URL.
 */

const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");

const servicePath = path.resolve(
  __dirname,
  "../services/business_invite.service.js",
);
const emailServicePath = path.resolve(
  __dirname,
  "../services/email.service.js",
);
const businessInviteModelPath = path.resolve(
  __dirname,
  "../models/BusinessInvite.js",
);
const debugPath = path.resolve(
  __dirname,
  "../utils/debug.js",
);

function loadInviteService({
  create = async () => ({
    _id: "invite-id",
    agreementText: "",
  }),
  updateMany = async () => ({
    acknowledged: true,
  }),
  sendEmail = async () => {},
} = {}) {
  const originalLoad = Module._load;
  const previousCache = {
    service: require.cache[servicePath],
    email: require.cache[emailServicePath],
    model: require.cache[businessInviteModelPath],
    debug: require.cache[debugPath],
  };

  delete require.cache[servicePath];
  delete require.cache[emailServicePath];
  delete require.cache[businessInviteModelPath];
  delete require.cache[debugPath];

  Module._load = function patchedLoad(
    request,
    parent,
    isMain,
  ) {
    const resolved = Module._resolveFilename(
      request,
      parent,
      isMain,
    );

    if (resolved === emailServicePath) {
      return { sendEmail };
    }
    if (resolved === businessInviteModelPath) {
      return {
        updateMany,
        create,
        findOne: async () => null,
      };
    }
    if (resolved === debugPath) {
      return () => {};
    }

    return originalLoad.apply(this, arguments);
  };

  try {
    return require(servicePath);
  } finally {
    Module._load = originalLoad;

    if (previousCache.service) {
      require.cache[servicePath] = previousCache.service;
    } else {
      delete require.cache[servicePath];
    }
    if (previousCache.email) {
      require.cache[emailServicePath] = previousCache.email;
    } else {
      delete require.cache[emailServicePath];
    }
    if (previousCache.model) {
      require.cache[businessInviteModelPath] =
        previousCache.model;
    } else {
      delete require.cache[businessInviteModelPath];
    }
    if (previousCache.debug) {
      require.cache[debugPath] = previousCache.debug;
    } else {
      delete require.cache[debugPath];
    }
  }
}

test(
  "createInvite skips email when creating a request link",
  async () => {
    const sendEmailCalls = [];
    const originalBaseUrl = process.env.FRONTEND_BASE_URL;
    process.env.FRONTEND_BASE_URL =
      "https://example.test";

    try {
      const service = loadInviteService({
        sendEmail: async (payload) => {
          sendEmailCalls.push(payload);
        },
        create: async (doc) => ({
          _id: "invite-id",
          agreementText: doc.agreementText,
          role: doc.role,
        }),
      });

      const result = await service.createInvite({
        businessId: "64f000000000000000000001",
        inviterId: "64f000000000000000000002",
        inviteeEmail: "tenant@example.com",
        role: "tenant",
        estateAssetId: "64f000000000000000000003",
        agreementText: "tenant agreement",
        shouldSendEmail: false,
      });

      assert.equal(sendEmailCalls.length, 0);
      assert.equal(result.invite.role, "tenant");
      assert.match(
        result.inviteLink,
        /^https:\/\/example\.test\/business-invite\?token=/,
      );
    } finally {
      if (typeof originalBaseUrl === "undefined") {
        delete process.env.FRONTEND_BASE_URL;
      } else {
        process.env.FRONTEND_BASE_URL = originalBaseUrl;
      }
    }
  },
);

test(
  "createInvite still sends email when requested",
  async () => {
    const sendEmailCalls = [];
    const originalBaseUrl = process.env.FRONTEND_BASE_URL;
    process.env.FRONTEND_BASE_URL =
      "https://example.test";

    try {
      const service = loadInviteService({
        sendEmail: async (payload) => {
          sendEmailCalls.push(payload);
        },
        create: async (doc) => ({
          _id: "invite-id",
          agreementText: doc.agreementText,
          role: doc.role,
        }),
      });

      const result = await service.createInvite({
        businessId: "64f000000000000000000001",
        inviterId: "64f000000000000000000002",
        inviteeEmail: "tenant@example.com",
        role: "tenant",
        estateAssetId: "64f000000000000000000003",
        agreementText: "tenant agreement",
        shouldSendEmail: true,
      });

      assert.equal(sendEmailCalls.length, 1);
      assert.equal(
        sendEmailCalls[0].toEmail,
        "tenant@example.com",
      );
      assert.equal(result.invite.role, "tenant");
      assert.match(
        result.inviteLink,
        /^https:\/\/example\.test\/business-invite\?token=/,
      );
    } finally {
      if (typeof originalBaseUrl === "undefined") {
        delete process.env.FRONTEND_BASE_URL;
      } else {
        process.env.FRONTEND_BASE_URL = originalBaseUrl;
      }
    }
  },
);
