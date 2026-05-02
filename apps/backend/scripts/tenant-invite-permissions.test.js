/**
 * backend/scripts/tenant-invite-permissions.test.js
 * --------------------------------------------------
 * WHAT:
 * - Verifies tenant invite access allows estate managers and business owners.
 *
 * WHY:
 * - Keeps the permission matrix and controller policy aligned with the product rule.
 *
 * HOW:
 * - Asserts the tenant manage capability is granted to estate managers.
 * - Asserts tenant invite creation follows the same role rule.
 */

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PERMISSION_MODULES,
  PERMISSION_CAPABILITIES,
  canSendTenantInvite,
  hasPermission,
} = require("../config/permissions");

test(
  "estate managers can manage tenant invites",
  () => {
    assert.equal(
      hasPermission({
        actorRole: "staff",
        staffRole: "estate manager",
        module: PERMISSION_MODULES.TENANTS,
        capability:
          PERMISSION_CAPABILITIES.MANAGE,
      }),
      true,
    );
  },
);

test(
  "tenant invite helper allows owners, shareholders, and estate managers only",
  () => {
    assert.equal(
      canSendTenantInvite({
        actorRole: "business_owner",
        staffRole: "",
      }),
      true,
    );
    assert.equal(
      canSendTenantInvite({
        actorRole: "staff",
        staffRole: "shareholder",
      }),
      true,
    );
    assert.equal(
      canSendTenantInvite({
        actorRole: "staff",
        staffRole: "estate manager",
      }),
      true,
    );
    assert.equal(
      canSendTenantInvite({
        actorRole: "staff",
        staffRole: "farm_manager",
      }),
      false,
    );
    assert.equal(
      canSendTenantInvite({
        actorRole: "customer",
        staffRole: "",
      }),
      false,
    );
  },
);
