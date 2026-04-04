/**
 * apps/backend/scripts/seed-staff-bots.js
 * --------------------------------------
 * WHAT:
 * - Seeds staff "bot" users and auto-accepts staff invites for testing.
 *
 * WHY:
 * - Solo testing is hard; this creates predictable staff profiles quickly.
 * - Produces ready-to-use bot logins + tokens for QA.
 *
 * HOW:
 * - Creates customer users (if missing) and marks NIN verified.
 * - Creates a staff invite record (token hash stored).
 * - Applies the same role + profile updates used in invite acceptance.
 * - Uses per-role bot counts and realistic names with a subtle [BOT] suffix.
 * - Blocks re-seeding bots in live-looking databases when bots already exist.
 * - Prints bot credentials and tokens for quick use.
 *
 * USAGE:
 * - node scripts/seed-staff-bots.js --owner-email=owner@test.com --roles=asset_manager,farm_manager --count=2
 * - Optional: --password=Test1234! --domain=test.local --prefix=bot --estate-asset-id=... --dry-run
 */

require("dotenv").config();

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const mongoose = require("mongoose");
const debug = require("../utils/debug");
const connectDB = require("../config/db");
const { signToken } = require("../config/jwt");
const { registerUser } = require("../services/auth.service");
const User = require("../models/User");
const BusinessInvite = require("../models/BusinessInvite");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const BusinessAsset = require("../models/BusinessAsset");

// WHY: Keep staff role validation aligned with schema enums.
const STAFF_ROLES = BusinessStaffProfile.STAFF_ROLES || [];

const DEFAULT_PASSWORD = "Test1234!";
const DEFAULT_DOMAIN = "test.local";
const DEFAULT_PREFIX = "bot";
const DEFAULT_COUNT = 1;
const DEFAULT_ROLE_COUNT = 1;
const DEFAULT_DOB = "1990-01-01";
const DEFAULT_MIDDLE_NAME = "Test";
const DEFAULT_COMPANY_DOMAIN = "gafexpress.test";
const DEFAULT_PROFILE_IMAGE_BASE =
  "https://example.com/bots/profile";
const DEFAULT_BUSINESS_INDUSTRY = "Agriculture";
const DEFAULT_BUSINESS_TAX_ID = "TAX-TEST-0001";
const DEFAULT_OUTPUT_JSON = "seeded-staff-bots.json";
const DEFAULT_OUTPUT_CSV = "seeded-staff-bots.csv";
const SAFE_DB_NAME_REGEX = /(test|dev|local|sandbox|qa)/i;
const BOT_NAME_SUFFIX = "[BOT]";
const NAME_SEED_BASE = 37;
const NAME_SEED_MULTIPLIER = 7;

const ROLE_DEFAULT_COUNTS = {
  asset_manager: 1,
  farm_manager: 1,
  estate_manager: 1,
  accountant: 1,
  field_agent: 1,
  cleaner: 1,
  farmer: 14,
  inventory_keeper: 1,
  auditor: 1,
  security: 1,
  maintenance_technician: 1,
  logistics_driver: 1,
};

const ESTATE_LINKED_ROLES = new Set([
  "estate_manager",
  "security",
  "maintenance_technician",
  "field_agent",
  "farm_manager",
  "farmer",
  "cleaner",
]);

const BUSINESS_WIDE_EXTRA_COUNTS = {
  accountant: 2,
  auditor: 2,
  inventory_keeper: 1,
  asset_manager: 1,
  logistics_driver: 1,
  cleaner: 1,
};

const BOT_FIRST_NAMES = [
  "Daniel",
  "Aisha",
  "Chinedu",
  "Grace",
  "Ibrahim",
  "Tomiwa",
  "Zainab",
  "Samuel",
  "Amaka",
  "Yusuf",
  "Blessing",
  "Musa",
  "Chioma",
  "Femi",
  "Kemi",
  "Emeka",
  "Halima",
  "Segun",
  "Sade",
  "Nkechi",
];

const BOT_LAST_NAMES = [
  "Okafor",
  "Bello",
  "Ibrahim",
  "Adeyemi",
  "Nwosu",
  "Balogun",
  "Okoro",
  "Yusuf",
  "Eze",
  "Olawale",
  "Onyeka",
  "Salami",
  "Udo",
  "Suleiman",
  "Chukwu",
  "Adebayo",
  "Mohammed",
  "Okeke",
  "Iroko",
  "Abiola",
];
const DEFAULT_TTL_DAYS = Number(
  process.env.BUSINESS_INVITE_TTL_DAYS || 7,
);

const STAFF_STATUS_ACTIVE = "active";
const ROLE_CUSTOMER = "customer";
const ROLE_STAFF = "staff";

const args = process.argv.slice(2);

function readArg(key) {
  return args.find((arg) => arg.startsWith(`${key}=`))?.split("=")[1];
}

function hasFlag(flag) {
  return args.includes(flag);
}

function parseRoles(raw) {
  if (!raw || raw.trim().length === 0) {
    return ["asset_manager"];
  }
  if (raw.trim() === "all") return STAFF_ROLES;
  return raw
    .split(",")
    .map((role) => role.trim())
    .filter(Boolean);
}

function parseCount(raw) {
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_COUNT;
  const normalized = Math.floor(parsed);
  return normalized < DEFAULT_COUNT ? DEFAULT_COUNT : normalized;
}

function normalizeEmail(email) {
  return email.toLowerCase().trim();
}

function resolveRoleCounts({ roles, count }) {
  // WHY: Provide strategic per-role defaults while allowing a global override.
  return roles.reduce((acc, role) => {
    if (count) {
      acc[role] = count;
      return acc;
    }
    acc[role] = ROLE_DEFAULT_COUNTS[role] ?? DEFAULT_ROLE_COUNT;
    return acc;
  }, {});
}

function resolveExtraRoleCounts({ roles }) {
  // WHY: Add optional business-wide staff on top of the base allocation.
  return roles.reduce((acc, role) => {
    acc[role] = BUSINESS_WIDE_EXTRA_COUNTS[role] ?? 0;
    return acc;
  }, {});
}

function isEstateLinkedRole(role) {
  // WHY: Keep estate assignment rules centralized.
  return ESTATE_LINKED_ROLES.has(role);
}

function resolveEstateAssignment({
  role,
  estateAssetId,
  isBusinessWide,
}) {
  // WHY: Ensure business-wide bots remain unassigned to estates.
  if (isBusinessWide) return null;
  if (!estateAssetId) return null;
  return isEstateLinkedRole(role) ? estateAssetId : null;
}

function buildBotIdentity(roleIndex, botIndex) {
  // WHY: Use deterministic, human-like names so QA can recognize bots quickly.
  // WHY: Mix role + index with a non-multiple base to avoid repeats across roles.
  const seed =
    roleIndex * NAME_SEED_BASE +
    botIndex * NAME_SEED_MULTIPLIER;
  const firstName =
    BOT_FIRST_NAMES[seed % BOT_FIRST_NAMES.length];
  const lastName =
    BOT_LAST_NAMES[(seed * NAME_SEED_MULTIPLIER) % BOT_LAST_NAMES.length];
  const lastNameWithSuffix = `${lastName} ${BOT_NAME_SUFFIX}`;
  return {
    firstName,
    lastName: lastNameWithSuffix,
    fullName: `${firstName} ${lastNameWithSuffix}`,
  };
}

function applyBotIdentityDefaults({ user, botIdentity }) {
  // WHY: Ensure every bot shows a subtle [BOT] marker in UI names.
  if (!user.firstName) {
    user.firstName = botIdentity.firstName;
  }
  if (!user.lastName || !user.lastName.includes(BOT_NAME_SUFFIX)) {
    user.lastName = botIdentity.lastName;
  }
  if (!user.name || !user.name.includes(BOT_NAME_SUFFIX)) {
    user.name = botIdentity.fullName;
  }
}

function resolveMongoDbName() {
  // WHY: Guard against seeding bots into the wrong database.
  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is missing; set it before seeding bots.");
  }
  try {
    const mongoUrl = new URL(process.env.MONGO_URI);
    const dbName = mongoUrl.pathname.replace(/^\//, "");
    if (!dbName) {
      throw new Error("MONGO_URI does not include a database name.");
    }
    return dbName;
  } catch (error) {
    throw new Error(
      `MONGO_URI is invalid; cannot resolve database name. ${error.message}`,
    );
  }
}

function isTestLikeDatabase(dbName) {
  // WHY: Allow bots by default only for clearly non-production databases.
  return SAFE_DB_NAME_REGEX.test(dbName);
}

function buildEmailRegex(prefix, domain, roles) {
  // WHY: Detect existing bots reliably using the same email rules as cleanup.
  const escapedPrefix = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedDomain = domain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (!roles || roles.length === 0) {
    return new RegExp(`^${escapedPrefix}\\..+@${escapedDomain}$`, "i");
  }
  const roleGroup = roles
    .map((role) => role.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    .join("|");
  return new RegExp(`^${escapedPrefix}\\.(${roleGroup})\\..+@${escapedDomain}$`, "i");
}

async function enforceSeedSafety({
  prefix,
  domain,
}) {
  // WHY: Prevent repeated bot seeding in live databases.
  const dbName = resolveMongoDbName();
  const isTestLike = isTestLikeDatabase(dbName);

  debug("SEED BOTS: safety guard check", {
    dbName,
    isTestLike,
    prefix,
    domain,
  });

  if (isTestLike) {
    debug("SEED BOTS: safety guard pass", {
      dbName,
      reason: "test-like database name",
    });
    return;
  }

  const emailRegex = buildEmailRegex(prefix, domain, []);
  const existingBot = await User.findOne({
    email: { $regex: emailRegex },
  }).select("email");

  if (existingBot) {
    debug("SEED BOTS: safety guard blocked", {
      dbName,
      matchedEmail: existingBot.email,
    });
    throw new Error(
      `Safety guard blocked bot seeding because "${dbName}" looks live and existing bot accounts were found. ` +
        "Clean up bots first or seed into a test database.",
    );
  }

  debug("SEED BOTS: safety guard warning", {
    dbName,
    reason: "live-looking database with no existing bots",
  });
}

function resolveOutputPath(fileName) {
  // WHY: Always resolve output paths from the script working directory.
  return path.resolve(process.cwd(), fileName);
}

function escapeCsv(value) {
  if (value === null || value === undefined) return "";
  const text = value.toString();
  if (text.includes(",") || text.includes("\"") || text.includes("\n")) {
    return `"${text.replace(/\"/g, "\"\"")}"`;
  }
  return text;
}

function toCsv(rows, headers) {
  const lines = [headers.join(",")];
  for (const row of rows) {
    const line = headers.map((key) => escapeCsv(row[key]));
    lines.push(line.join(","));
  }
  return lines.join("\n");
}

function formatRoleName(role) {
  return role
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function buildPhone(roleIndex, botIndex) {
  // WHY: Generate deterministic, unique phone numbers for bots.
  const roleToken = roleIndex.toString().padStart(2, "0");
  const botToken = botIndex.toString().padStart(6, "0");
  return `+23480${roleToken}${botToken}`;
}

function buildNinHash(value) {
  // WHY: Store a deterministic placeholder hash for seeded NIN.
  return crypto.createHash("sha256").update(value).digest("hex");
}

function buildProfileImageUrl(role, botIndex) {
  // WHY: Deterministic image URLs make bots easier to recognize.
  return `${DEFAULT_PROFILE_IMAGE_BASE}/${role}-${botIndex}.png`;
}

function buildAddress(roleIndex, botIndex, label) {
  // WHY: Provide a complete address payload for test profiles.
  const roleToken = roleIndex.toString().padStart(2, "0");
  const botToken = botIndex.toString().padStart(4, "0");
  return {
    houseNumber: `${roleToken}${botToken}`,
    street: `${label} Street`,
    city: "Lagos",
    state: "Lagos",
    postalCode: "100001",
    lga: "Ikeja",
    country: "NG",
    landmark: "Seeded bot landmark",
    isVerified: true,
    verifiedAt: new Date(),
    verificationSource: "seed",
    formattedAddress: `${roleToken}${botToken} ${label} Street, Lagos`,
    placeId: `seed-${label.toLowerCase()}-${roleToken}-${botToken}`,
    lat: 6.5244,
    lng: 3.3792,
  };
}

function buildCompanyProfile(role, botIndex, phone) {
  const roleTitle = formatRoleName(role);
  const botToken = botIndex.toString().padStart(4, "0");
  const companyName = `GafExpress ${roleTitle} ${botToken} ${BOT_NAME_SUFFIX}`;
  const companyEmail = `bot.${role}.${botToken}@${DEFAULT_COMPANY_DOMAIN}`;
  return {
    companyName,
    companyEmail,
    companyPhone: phone,
    companyWebsite: `https://gafexpress.test/${role}/${botToken}`,
    businessIndustry: DEFAULT_BUSINESS_INDUSTRY,
    businessTaxId: DEFAULT_BUSINESS_TAX_ID,
  };
}

function buildDirector(role, botIndex, phone, directorName) {
  const roleTitle = formatRoleName(role);
  const botToken = botIndex.toString().padStart(4, "0");
  return {
    name: directorName || `${roleTitle} ${botToken} ${BOT_NAME_SUFFIX}`,
    role: "Director",
    email: `director.${role}.${botToken}@${DEFAULT_COMPANY_DOMAIN}`,
    phone,
  };
}

function applyVerificationFlags(user) {
  // WHY: Bots must be treated as fully verified for testing flows.
  user.isEmailVerified = true;
  user.isPhoneVerified = true;
  user.isNinVerified = true;
  user.ninLast4 = user.ninLast4 || "0000";
  user.ninHash = user.ninHash || buildNinHash(user.email);
}

function applyProfileDefaults({
  user,
  role,
  roleIndex,
  botIndex,
  botIdentity,
}) {
  // WHY: Use deterministic bot identity so names remain stable across runs.
  // WHY: Keep bot identity consistent between new and existing records.
  const identity =
    botIdentity || buildBotIdentity(roleIndex, botIndex);
  const phone = buildPhone(roleIndex, botIndex);
  const homeAddress = buildAddress(roleIndex, botIndex, "Home");
  const companyAddress = buildAddress(roleIndex, botIndex, "Company");
  const companyProfile = buildCompanyProfile(role, botIndex, phone);

  applyBotIdentityDefaults({
    user,
    botIdentity: identity,
  });

  user.phone = user.phone?.trim().length > 0 ? user.phone : phone;
  user.middleName = user.middleName || DEFAULT_MIDDLE_NAME;
  user.dob = user.dob || DEFAULT_DOB;
  user.profileImageUrl =
    user.profileImageUrl || buildProfileImageUrl(role, botIndex);
  user.accountType = user.accountType || "personal";

  if (!user.homeAddress) {
    user.homeAddress = homeAddress;
  }
  if (!user.companyAddress) {
    user.companyAddress = companyAddress;
  }
  if (!user.businessRegisteredAddress) {
    user.businessRegisteredAddress = companyAddress;
  }

  user.companyName =
    user.companyName || companyProfile.companyName;
  user.companyEmail =
    user.companyEmail || companyProfile.companyEmail;
  user.companyPhone =
    user.companyPhone || companyProfile.companyPhone;
  user.companyWebsite =
    user.companyWebsite || companyProfile.companyWebsite;
  user.businessIndustry =
    user.businessIndustry || companyProfile.businessIndustry;
  user.businessTaxId =
    user.businessTaxId || companyProfile.businessTaxId;

  if (!Array.isArray(user.businessDirectors) || user.businessDirectors.length === 0) {
    user.businessDirectors = [
      buildDirector(role, botIndex, phone, identity.fullName),
    ];
  }
}

function generateToken() {
  return crypto.randomBytes(24).toString("hex");
}

function hashToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

function inviteExpiryDate() {
  const now = new Date();
  now.setDate(now.getDate() + DEFAULT_TTL_DAYS);
  return now;
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

async function resolveEstateAsset({
  estateAssetId,
  businessId,
}) {
  if (!estateAssetId) return null;
  const asset = await BusinessAsset.findById(
    estateAssetId,
  ).select("assetType businessId name");

  if (!asset) {
    throw new Error("Estate asset not found");
  }
  if (asset.assetType !== "estate") {
    throw new Error("Estate asset must be of type estate");
  }
  if (asset.businessId.toString() !== businessId.toString()) {
    throw new Error("Estate asset belongs to another business");
  }

  return asset;
}

async function ensureBotUser({
  email,
  password,
  roleIndex,
  botIndex,
  role,
  botIdentity,
  dryRun,
}) {
  const normalizedEmail = normalizeEmail(email);
  const existing = await User.findOne({ email: normalizedEmail });

  if (existing) {
    if (existing.role !== ROLE_CUSTOMER) {
      debug("SEED BOTS: existing user not customer", {
        email: normalizedEmail,
        role: existing.role,
      });
      return { user: existing, created: false, skipped: true };
    }

    applyProfileDefaults({
      user: existing,
      role,
      roleIndex,
      botIndex,
      botIdentity,
    });
    applyVerificationFlags(existing);

    if (!dryRun) {
      await existing.save();
    }

    return { user: existing, created: false, skipped: false };
  }

  if (dryRun) {
    debug("SEED BOTS: dry-run create user", { email: normalizedEmail });
    return { user: null, created: true, skipped: false };
  }

  const identity =
    botIdentity || buildBotIdentity(roleIndex, botIndex);
  const firstName = identity.firstName;
  const lastName = identity.lastName;

  const registered = await registerUser({
    firstName,
    lastName,
    name: identity.fullName,
    email: normalizedEmail,
    password,
    confirmPassword: password,
    role: ROLE_CUSTOMER,
  });

  const user = await User.findById(registered.id);
  if (!user) {
    throw new Error("Failed to load created user");
  }

  applyProfileDefaults({
    user,
    role,
    roleIndex,
    botIndex,
    botIdentity: identity,
  });
  applyVerificationFlags(user);
  await user.save();

  return { user, created: true, skipped: false };
}

async function createStaffInvite({
  businessId,
  inviterId,
  inviteeEmail,
  staffRole,
  estateAssetId,
  dryRun,
}) {
  const normalizedEmail = normalizeEmail(inviteeEmail);
  const token = generateToken();
  const tokenHash = hashToken(token);
  const tokenExpiresAt = inviteExpiryDate();

  if (!dryRun) {
    await BusinessInvite.updateMany(
      {
        businessId,
        inviteeEmail: normalizedEmail,
        status: "pending",
      },
      {
        $set: {
          status: "cancelled",
          cancelledAt: new Date(),
        },
      },
    );
  }

  if (dryRun) {
    debug("SEED BOTS: dry-run invite create", {
      inviteeEmail: normalizedEmail,
      staffRole,
    });
    return {
      invite: null,
      token,
    };
  }

  const invite = await BusinessInvite.create({
    businessId,
    inviterId,
    inviteeEmail: normalizedEmail,
    role: ROLE_STAFF,
    staffRole,
    estateAssetId: estateAssetId || null,
    tokenHash,
    tokenExpiresAt,
    status: "pending",
    agreementText: "",
  });

  return { invite, token };
}

async function acceptStaffInvite({
  invite,
  user,
  businessId,
  staffRole,
  estateAssetId,
  dryRun,
}) {
  if (dryRun) {
    debug("SEED BOTS: dry-run accept invite", {
      userId: user?._id?.toString(),
      staffRole,
    });
    return;
  }

  user.role = ROLE_STAFF;
  user.businessId = businessId;
  user.estateAssetId = estateAssetId || null;
  await user.save();

  const existingProfile = await BusinessStaffProfile.findOne({
    userId: user._id,
    businessId,
  });

  if (existingProfile) {
    existingProfile.staffRole = staffRole;
    existingProfile.estateAssetId = estateAssetId || null;
    existingProfile.status = STAFF_STATUS_ACTIVE;
    await existingProfile.save();
  } else {
    await BusinessStaffProfile.create({
      userId: user._id,
      businessId,
      staffRole,
      estateAssetId: estateAssetId || null,
      status: STAFF_STATUS_ACTIVE,
    });
  }

  if (invite) {
    invite.status = "accepted";
    invite.acceptedBy = user._id;
    invite.acceptedAt = new Date();
    await invite.save();
  }
}

async function run() {
  const ownerEmail = readArg("--owner-email");
  const rolesArg = readArg("--roles");
  const countArg = readArg("--count");
  const domain = readArg("--domain") || DEFAULT_DOMAIN;
  const prefix = readArg("--prefix") || DEFAULT_PREFIX;
  const password = readArg("--password") || DEFAULT_PASSWORD;
  const estateAssetId = readArg("--estate-asset-id") || null;
  const outputJsonArg = readArg("--output-json");
  const outputCsvArg = readArg("--output-csv");
  const isDryRun = hasFlag("--dry-run");

  if (!ownerEmail) {
    throw new Error("--owner-email is required");
  }

  const roles = parseRoles(rolesArg);
  const invalidRoles = roles.filter(
    (role) => !STAFF_ROLES.includes(role),
  );
  if (invalidRoles.length > 0) {
    throw new Error(
      `Invalid staff roles: ${invalidRoles.join(", ")}`,
    );
  }

  const count = countArg ? parseCount(countArg) : null;
  // WHY: Use strategic defaults unless a global count override is provided.
  const roleCounts = resolveRoleCounts({ roles, count });
  // WHY: Add business-wide extras on top of the base allocation.
  const extraRoleCounts = resolveExtraRoleCounts({ roles });
  // WHY: Provide an easy summary for logs and exported files.
  const baseCount = Object.values(roleCounts).reduce(
    (sum, value) => sum + value,
    0,
  );
  const extraCount = Object.values(extraRoleCounts).reduce(
    (sum, value) => sum + value,
    0,
  );
  const totalCount = baseCount + extraCount;

  debug("SEED BOTS: start", {
    ownerEmail,
    roles,
    count,
    roleCounts,
    extraRoleCounts,
    baseCount,
    extraCount,
    totalCount,
    domain,
    prefix,
    outputJson: outputJsonArg || DEFAULT_OUTPUT_JSON,
    outputCsv: outputCsvArg || DEFAULT_OUTPUT_CSV,
    dryRun: isDryRun,
    hasEstate: Boolean(estateAssetId),
  });

  await connectDB();

  await enforceSeedSafety({
    prefix,
    domain,
  });

  const owner = await loadOwner(ownerEmail);
  const estateAsset = await resolveEstateAsset({
    estateAssetId,
    businessId: owner.businessId,
  });
  const estateAssetResolvedId = estateAsset?._id || null;
  const estateLinkedRoles = Array.from(ESTATE_LINKED_ROLES);

  const results = [];

  for (const [roleIndex, role] of roles.entries()) {
    // WHY: Role-specific counts enable strategic bot coverage.
    const roleCount = roleCounts[role] || 0;
    const roleExtraCount = extraRoleCounts[role] || 0;
    const roleEstateAssignment = resolveEstateAssignment({
      role,
      estateAssetId: estateAssetResolvedId,
      isBusinessWide: false,
    });
    debug("SEED BOTS: role batch", {
      role,
      roleCount,
      roleExtraCount,
      estateLinked: isEstateLinkedRole(role),
      estateAssetId: roleEstateAssignment
        ? roleEstateAssignment.toString()
        : null,
    });
    for (let i = 1; i <= roleCount; i += 1) {
      // WHY: Deterministic names keep bot identities stable.
      const botIdentity = buildBotIdentity(roleIndex + 1, i);
      const email = `${prefix}.${role}.${i}@${domain}`;
      const { user, created, skipped } = await ensureBotUser({
        email,
        password,
        roleIndex: roleIndex + 1,
        botIndex: i,
        role,
        botIdentity,
        dryRun: isDryRun,
      });

      if (skipped) {
        results.push({
          email,
          staffRole: role,
          status: "skipped (existing non-customer)",
        });
        continue;
      }

      if (!user && isDryRun) {
        results.push({
          email,
          staffRole: role,
          status: "dry-run (user not created)",
        });
        continue;
      }

      const { invite } = await createStaffInvite({
        businessId: owner.businessId,
        inviterId: owner._id,
        inviteeEmail: email,
        staffRole: role,
        estateAssetId: roleEstateAssignment,
        dryRun: isDryRun,
      });

      await acceptStaffInvite({
        invite,
        user,
        businessId: owner.businessId,
        staffRole: role,
        estateAssetId: roleEstateAssignment,
        dryRun: isDryRun,
      });

      const token = isDryRun
        ? "[dry-run]"
        : signToken({
            id: user._id,
            role: ROLE_STAFF,
          });

      results.push({
        email,
        password,
        staffRole: role,
        userId: user._id.toString(),
        phone: user.phone,
        isEmailVerified: user.isEmailVerified,
        isPhoneVerified: user.isPhoneVerified,
        isNinVerified: user.isNinVerified,
        profileImageUrl: user.profileImageUrl,
        companyName: user.companyName,
        companyEmail: user.companyEmail,
        token,
        status: created ? "created" : "updated",
      });
    }

    if (roleExtraCount <= 0) continue;
    // WHY: Business-wide extras should never inherit estate assignment.
    debug("SEED BOTS: role extra batch", {
      role,
      roleExtraCount,
      estateAssetId: null,
    });
    for (let i = 1; i <= roleExtraCount; i += 1) {
      const extraIndex = roleCount + i;
      // WHY: Offset indices so extra bots do not collide with base emails.
      const botIdentity = buildBotIdentity(roleIndex + 1, extraIndex);
      const email = `${prefix}.${role}.${extraIndex}@${domain}`;
      const { user, created, skipped } = await ensureBotUser({
        email,
        password,
        roleIndex: roleIndex + 1,
        botIndex: extraIndex,
        role,
        botIdentity,
        dryRun: isDryRun,
      });

      if (skipped) {
        results.push({
          email,
          staffRole: role,
          status: "skipped (existing non-customer)",
        });
        continue;
      }

      if (!user && isDryRun) {
        results.push({
          email,
          staffRole: role,
          status: "dry-run (user not created)",
        });
        continue;
      }

      const { invite } = await createStaffInvite({
        businessId: owner.businessId,
        inviterId: owner._id,
        inviteeEmail: email,
        staffRole: role,
        estateAssetId: null,
        dryRun: isDryRun,
      });

      await acceptStaffInvite({
        invite,
        user,
        businessId: owner.businessId,
        staffRole: role,
        estateAssetId: null,
        dryRun: isDryRun,
      });

      const token = isDryRun
        ? "[dry-run]"
        : signToken({
            id: user._id,
            role: ROLE_STAFF,
          });

      results.push({
        email,
        password,
        staffRole: role,
        userId: user._id.toString(),
        phone: user.phone,
        isEmailVerified: user.isEmailVerified,
        isPhoneVerified: user.isPhoneVerified,
        isNinVerified: user.isNinVerified,
        profileImageUrl: user.profileImageUrl,
        companyName: user.companyName,
        companyEmail: user.companyEmail,
        token,
        status: created ? "created" : "updated",
      });
    }
  }

  const outputJsonPath = resolveOutputPath(
    outputJsonArg || DEFAULT_OUTPUT_JSON,
  );
  const outputCsvPath = resolveOutputPath(
    outputCsvArg || DEFAULT_OUTPUT_CSV,
  );

  // WHY: Include metadata so files are reusable without guessing context.
  const payload = {
    generatedAt: new Date().toISOString(),
    ownerEmail,
    roles,
    count,
    roleCounts,
    extraRoleCounts,
    baseCount,
    extraCount,
    totalCount,
    domain,
    prefix,
    estateLinkedRoles,
    businessWideExtraCounts: BUSINESS_WIDE_EXTRA_COUNTS,
    estateAssetId: estateAssetId || null,
    dryRun: isDryRun,
    results,
  };

  try {
    fs.writeFileSync(
      outputJsonPath,
      JSON.stringify(payload, null, 2),
      "utf8",
    );
    debug("SEED BOTS: JSON exported", { outputJsonPath });
  } catch (err) {
    console.error("Seed staff bots JSON export failed:", err.message);
  }

  try {
    const headers = [
      "email",
      "password",
      "staffRole",
      "userId",
      "phone",
      "isEmailVerified",
      "isPhoneVerified",
      "isNinVerified",
      "profileImageUrl",
      "companyName",
      "companyEmail",
      "token",
      "status",
    ];
    const csv = toCsv(results, headers);
    fs.writeFileSync(outputCsvPath, csv, "utf8");
    debug("SEED BOTS: CSV exported", { outputCsvPath });
  } catch (err) {
    console.error("Seed staff bots CSV export failed:", err.message);
  }

  console.log("Seeded staff bots:", results);

  if (!isDryRun) {
    await mongoose.disconnect();
  }

  debug("SEED BOTS: done");
}

run().catch((err) => {
  console.error("Seed staff bots failed:", err.message);
  process.exit(1);
});
