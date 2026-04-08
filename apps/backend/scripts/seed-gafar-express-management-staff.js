#!/usr/bin/env node

/**
 * apps/backend/scripts/seed-gafar-express-management-staff.js
 * -----------------------------------------------------------
 * WHAT:
 * - Seeds requested management/family staff accounts for Gafar Express.
 *
 * WHY:
 * - Keeps the request idempotent and avoids rerunning the destructive reset.
 * - Reuses the current business owner + estate already in MongoDB.
 *
 * HOW:
 * - Resolves the Gafar Express business owner by email/company name.
 * - Creates or updates staff users by deterministic email.
 * - Upserts matching BusinessStaffProfile records with supported staff roles.
 *
 * USAGE:
 * - node scripts/seed-gafar-express-management-staff.js
 * - node scripts/seed-gafar-express-management-staff.js --execute
 * - node scripts/seed-gafar-express-management-staff.js --execute --password=Test1234!
 * - node scripts/seed-gafar-express-management-staff.js --execute --owner-email=razakgafar98@outlook.com
 */

require("dotenv").config({ quiet: true });

const bcrypt = require("bcryptjs");
const mongoose = require("mongoose");

const connectDB = require("../config/db");
const User = require("../models/User");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");

const DEFAULT_PASSWORD = "Test1234!";
const DEFAULT_OWNER_EMAIL = "razakgafar98@outlook.com";
const DEFAULT_COMPANY_REGEX = /gafars?\s*e?xpress/i;
const STAFF_EMAIL_DOMAIN = "gafarhydroponyfarmfarm.com";

const ESTATE_LINKED_STAFF_ROLES = new Set([
  "estate_manager",
  "security",
  "maintenance_technician",
  "field_agent",
  "farm_manager",
  "farmer",
  "cleaner",
  "logistics_driver",
  "quality_control_manager",
]);

const STAFF_SEEDS = Object.freeze([
  {
    firstName: "Kudirat",
    lastName: "Gafar",
    email: "kudirat.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000303",
    staffRole: "lawyer",
    notes: "Lawyer and shareholder added by request.",
  },
  {
    firstName: "Sherifat",
    lastName: "Gafar",
    email: "sherifat.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000304",
    staffRole: "shareholder",
    notes: "Shareholder added by request.",
  },
  {
    firstName: "Kemi",
    lastName: "Gafar",
    email: "kemi.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000305",
    staffRole: "quality_control_manager",
    notes: "Shareholder and quality control manager added by request.",
  },
  {
    firstName: "Abdulateef",
    middleName: "Femi",
    lastName: "Gafar",
    email: "abdulateef.femi.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000306",
    staffRole: "shareholder",
    notes: "Shareholder added by request.",
  },
]);

const args = process.argv.slice(2);

function readArg(key) {
  return args.find((arg) => arg.startsWith(`${key}=`))?.slice(key.length + 1);
}

function hasFlag(flag) {
  return args.includes(flag);
}

function slugify(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "");
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function joinNameParts(parts) {
  return parts
    .map((value) => (typeof value === "string" ? value.trim() : ""))
    .filter(Boolean)
    .join(" ");
}

function buildEmail({ firstName, middleName, lastName, domain }) {
  const left = [firstName, middleName, lastName]
    .map((part) => slugify(part))
    .filter(Boolean)
    .join(".");
  return `${left || "staff"}@${domain}`;
}

function lastFourDigits(value) {
  const digits = String(value || "").replace(/\D+/g, "");
  return digits.slice(-4) || null;
}

function incrementPhoneDigits(value, increment) {
  const digits = String(value || "").replace(/\D+/g, "");
  if (!digits) {
    return "";
  }
  return String(Number(digits) + increment).padStart(digits.length, "0");
}

function resolveStaffEmail(seed) {
  return normalizeEmail(
    seed.email ||
      buildEmail({
        firstName: seed.firstName,
        middleName: seed.middleName,
        lastName: seed.lastName,
        domain: STAFF_EMAIL_DOMAIN,
      }),
  );
}

function resolveEstateAssetId({ estateAsset, staffRole }) {
  if (!estateAsset) {
    return null;
  }
  return ESTATE_LINKED_STAFF_ROLES.has(staffRole)
    ? estateAsset._id
    : null;
}

function resolveStaffCompanyName({
  ownerUser,
  estateAsset,
  staffRole,
}) {
  if (ESTATE_LINKED_STAFF_ROLES.has(staffRole)) {
    return estateAsset?.name || ownerUser.companyName || "Gafar Express";
  }
  return ownerUser.companyName || estateAsset?.name || "Gafar Express";
}

async function resolveAvailablePhone({
  preferredPhone,
  currentUserId,
  reservedPhones,
}) {
  const normalizedPreferredPhone = String(preferredPhone || "").trim();

  if (!normalizedPreferredPhone) {
    return "";
  }

  for (let offset = 0; offset < 100; offset += 1) {
    const candidatePhone = incrementPhoneDigits(
      normalizedPreferredPhone,
      offset,
    );

    if (reservedPhones?.has(candidatePhone)) {
      continue;
    }

    const conflictUser = await User.findOne({
      phone: candidatePhone,
    }).select("_id");

    if (
      !conflictUser ||
      String(conflictUser._id) === String(currentUserId)
    ) {
      return candidatePhone;
    }
  }

  return "";
}

async function findOwnerUser(ownerEmail) {
  const normalizedOwnerEmail = normalizeEmail(ownerEmail);

  if (normalizedOwnerEmail) {
    return User.findOne({
      role: "business_owner",
      email: normalizedOwnerEmail,
    });
  }

  return User.findOne({
    role: "business_owner",
    $or: [
      { email: DEFAULT_OWNER_EMAIL },
      { companyName: { $regex: DEFAULT_COMPANY_REGEX } },
    ],
  }).sort({ createdAt: 1 });
}

async function findPrimaryEstate(ownerUserId) {
  return BusinessAsset.findOne({
    businessId: ownerUserId,
    assetType: "estate",
    deletedAt: null,
  }).sort({ createdAt: 1 });
}

async function seedStaffRecord({
  ownerUser,
  estateAsset,
  seed,
  passwordHash,
  reservedPhones,
  shouldExecute,
}) {
  const fullName = joinNameParts([
    seed.firstName,
    seed.middleName,
    seed.lastName,
  ]);
  const email = resolveStaffEmail(seed);
  const existingUser = await User.findOne({ email });

  if (
    existingUser?.businessId &&
    String(existingUser.businessId) !== String(ownerUser._id)
  ) {
    throw new Error(
      `Existing user ${email} belongs to a different business (${existingUser.businessId}).`,
    );
  }

  const userId = existingUser?._id || new mongoose.Types.ObjectId();
  const assignedEstateId = resolveEstateAssetId({
    estateAsset,
    staffRole: seed.staffRole,
  });
  const preferredPhone =
    existingUser?.phone && existingUser.phone.trim().length > 0
      ? existingUser.phone.trim()
      : seed.phone;
  const resolvedPhone = await resolveAvailablePhone({
    preferredPhone,
    currentUserId: userId,
    reservedPhones,
  });

  if (resolvedPhone) {
    reservedPhones.add(resolvedPhone);
  }

  const companyName = resolveStaffCompanyName({
    ownerUser,
    estateAsset,
    staffRole: seed.staffRole,
  });
  const existingProfile = existingUser
    ? await BusinessStaffProfile.findOne({
        userId: existingUser._id,
        businessId: ownerUser._id,
      })
    : null;
  const action = existingUser ? "updated" : "created";

  const summary = {
    action,
    name: fullName,
    email,
    phone: resolvedPhone,
    staffRole: seed.staffRole,
    secondaryTitles: seed.notes,
    companyName,
    estateAssetId: assignedEstateId ? String(assignedEstateId) : null,
    userId: String(userId),
    staffProfileId: existingProfile?._id ? String(existingProfile._id) : null,
  };

  if (!shouldExecute) {
    return summary;
  }

  const userPayload = {
    name: fullName,
    firstName: seed.firstName,
    middleName: seed.middleName || undefined,
    lastName: seed.lastName,
    email,
    role: "staff",
    businessId: ownerUser._id,
    estateAssetId: assignedEstateId,
    accountType: "personal",
    companyName,
    isActive: true,
    isEmailVerified: true,
    isPhoneVerified: Boolean(resolvedPhone),
    isNinVerified: Boolean(resolvedPhone),
    ninLast4: resolvedPhone ? lastFourDigits(resolvedPhone) : null,
  };

  if (resolvedPhone) {
    userPayload.phone = resolvedPhone;
  }

  if (existingUser) {
    await User.updateOne(
      { _id: existingUser._id },
      {
        $set: userPayload,
        ...(resolvedPhone
          ? {}
          : {
              $unset: {
                phone: "",
              },
            }),
      },
    );
  } else {
    await User.create({
      _id: userId,
      ...userPayload,
      passwordHash,
    });
  }

  const profile = await BusinessStaffProfile.findOneAndUpdate(
    {
      userId,
      businessId: ownerUser._id,
    },
    {
      $set: {
        staffRole: seed.staffRole,
        estateAssetId: assignedEstateId,
        status: "active",
        notes: seed.notes || "",
      },
      $setOnInsert: {
        startDate: new Date(),
      },
    },
    {
      new: true,
      upsert: true,
      setDefaultsOnInsert: true,
    },
  );

  return {
    ...summary,
    staffProfileId: String(profile._id),
  };
}

async function main() {
  const shouldExecute = hasFlag("--execute");
  const ownerEmail = readArg("--owner-email");
  const password = readArg("--password") || DEFAULT_PASSWORD;

  if (!BusinessStaffProfile.STAFF_ROLES.includes("lawyer")) {
    throw new Error(
      "Expected staff role `lawyer` is unavailable. Apply the enum changes before running this seed.",
    );
  }

  if (!BusinessStaffProfile.STAFF_ROLES.includes("quality_control_manager")) {
    throw new Error(
      "Expected staff role `quality_control_manager` is unavailable. Apply the enum changes before running this seed.",
    );
  }

  if (!BusinessStaffProfile.STAFF_ROLES.includes("shareholder")) {
    throw new Error(
      "Expected staff role `shareholder` is unavailable. Apply the enum changes before running this seed.",
    );
  }

  await connectDB();

  try {
    const ownerUser = await findOwnerUser(ownerEmail);

    if (!ownerUser) {
      throw new Error(
        "Could not find the Gafar Express business owner. Pass --owner-email to target the correct account.",
      );
    }

    const estateAsset = await findPrimaryEstate(ownerUser._id);

    if (!estateAsset) {
      throw new Error(
        `No active estate asset found for owner ${ownerUser.email}.`,
      );
    }

    const passwordHash = shouldExecute
      ? await bcrypt.hash(password, 10)
      : null;
    const results = [];
    const reservedPhones = new Set();

    for (const seed of STAFF_SEEDS) {
      results.push(
        await seedStaffRecord({
          ownerUser,
          estateAsset,
          seed,
          passwordHash,
          reservedPhones,
          shouldExecute,
        }),
      );
    }

    console.log(
      JSON.stringify(
        {
          shouldExecute,
          owner: {
            id: String(ownerUser._id),
            email: ownerUser.email,
            name: ownerUser.name,
            companyName: ownerUser.companyName || null,
          },
          estate: {
            id: String(estateAsset._id),
            name: estateAsset.name,
          },
          defaultPassword: shouldExecute ? password : DEFAULT_PASSWORD,
          staff: results,
        },
        null,
        2,
      ),
    );

    if (!shouldExecute) {
      console.log(
        "Dry run only. Re-run with --execute to create or update the staff records.",
      );
    }
  } finally {
    await mongoose.disconnect();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
