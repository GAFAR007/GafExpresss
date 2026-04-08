/**
 * apps/backend/scripts/cleanup-staff-bots.js
 * ------------------------------------------
 * WHAT:
 * - Removes seeded staff bot accounts and related data.
 *
 * WHY:
 * - Keeps test databases clean after QA cycles.
 * - Ensures bot data does not pollute production metrics.
 *
 * HOW:
 * - Resolves owner businessId to scope deletions.
 * - Finds users by bot email pattern.
 * - Deletes staff profiles, invites, attendance, compensation, and users.
 *
 * USAGE:
 * - node scripts/cleanup-staff-bots.js --owner-email=owner@test.com --prefix=bot --domain=test.local
 * - Optional: --roles=asset_manager,farm_manager --dry-run
 */

require("dotenv").config();

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const connectDB = require("../config/db");
const User = require("../models/User");
const BusinessInvite = require("../models/BusinessInvite");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const StaffAttendance = require("../models/StaffAttendance");
const StaffCompensation = require("../models/StaffCompensation");

const DEFAULT_DOMAIN = "test.local";
const DEFAULT_PREFIX = "bot";

const args = process.argv.slice(2);

function readArg(key) {
  return args.find((arg) => arg.startsWith(`${key}=`))?.split("=")[1];
}

function hasFlag(flag) {
  return args.includes(flag);
}

function normalizeEmail(email) {
  return email.toLowerCase().trim();
}

function parseRoles(raw) {
  if (!raw || raw.trim().length === 0) {
    return [];
  }
  if (raw.trim() === "all") return [];
  return raw
    .split(",")
    .map((role) => role.trim())
    .filter(Boolean);
}

async function loadOwner(ownerEmail) {
  const owner = await User.findOne({
    email: normalizeEmail(ownerEmail),
  });

  if (!owner) {
    throw new Error("Owner account not found");
  }

  if (owner.role !== "business_owner") {
    throw new Error("Owner account must be business_owner");
  }

  if (!owner.businessId) {
    throw new Error("Owner businessId is missing");
  }

  return owner;
}

function buildEmailRegex(prefix, domain, roles) {
  const escapedPrefix = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedDomain = domain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (roles.length === 0) {
    return new RegExp(`^${escapedPrefix}\\..+@${escapedDomain}$`, "i");
  }
  const roleGroup = roles
    .map((role) => role.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    .join("|");
  return new RegExp(`^${escapedPrefix}\\.(${roleGroup})\\..+@${escapedDomain}$`, "i");
}

async function run() {
  const ownerEmail = readArg("--owner-email");
  const rolesArg = readArg("--roles");
  const domain = readArg("--domain") || DEFAULT_DOMAIN;
  const prefix = readArg("--prefix") || DEFAULT_PREFIX;
  const isDryRun = hasFlag("--dry-run");

  if (!ownerEmail) {
    throw new Error("--owner-email is required");
  }

  const roles = parseRoles(rolesArg);

  debug("CLEANUP BOTS: start", {
    ownerEmail,
    roles,
    domain,
    prefix,
    dryRun: isDryRun,
  });

  await connectDB();

  const owner = await loadOwner(ownerEmail);
  const emailRegex = buildEmailRegex(prefix, domain, roles);

  const botUsers = await User.find({
    businessId: owner.businessId,
    email: { $regex: emailRegex },
  });

  const userIds = botUsers.map((user) => user._id);
  const emails = botUsers.map((user) => user.email);

  debug("CLEANUP BOTS: matched users", {
    count: userIds.length,
  });

  const staffProfiles = await BusinessStaffProfile.find({
    userId: { $in: userIds },
    businessId: owner.businessId,
  });
  const staffProfileIds = staffProfiles.map((profile) => profile._id);

  if (isDryRun) {
    console.log("Bot cleanup (dry-run) would remove:", {
      count: userIds.length,
      emails,
      staffProfiles: staffProfileIds.length,
    });
    await mongoose.disconnect();
    return;
  }

  await StaffAttendance.deleteMany({
    staffProfileId: { $in: staffProfileIds },
  });

  await StaffCompensation.deleteMany({
    staffProfileId: { $in: staffProfileIds },
  });

  await BusinessStaffProfile.deleteMany({
    _id: { $in: staffProfileIds },
  });

  await BusinessInvite.deleteMany({
    businessId: owner.businessId,
    inviteeEmail: { $in: emails },
  });

  await User.deleteMany({
    _id: { $in: userIds },
  });

  console.log("Bot cleanup complete:", {
    deletedUsers: userIds.length,
    deletedStaffProfiles: staffProfileIds.length,
  });

  await mongoose.disconnect();
}

run().catch((err) => {
  console.error("Cleanup staff bots failed:", err.message);
  process.exit(1);
});
