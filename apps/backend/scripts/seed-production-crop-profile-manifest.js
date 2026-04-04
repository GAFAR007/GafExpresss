/**
 * apps/backend/scripts/seed-production-crop-profile-manifest.js
 * -------------------------------------------------------------
 * WHAT:
 * - Seeds the crop profile store with generated manifest targets.
 *
 * WHY:
 * - A large seed queue lets the team preload 500+ crop/plant targets and 250+ fruit targets
 *   before vetted source imports fill in trusted agronomy details.
 *
 * USAGE:
 * - npm run ops:crop-profiles:seed -- --business-id=<ownerId>
 * - npm run ops:crop-profiles:seed -- --business-id=<ownerId> --limit=50
 */

require("dotenv").config();

const mongoose = require("mongoose");
const connectDB = require("../config/db");
const debug = require("../utils/debug");
const {
  buildCropProfileSeedManifest,
  CROP_PROFILE_SEED_MANIFEST_VERSION,
} = require("../services/planner/cropProfileSeedManifest");
const {
  persistCropProfileSeedEntry,
} = require("../services/planner/lifecycleResolver");

const args = process.argv.slice(2);

function readArg(key) {
  return args
    .find((arg) => arg.startsWith(`${key}=`))
    ?.slice(`${key}=`.length);
}

function toPositiveInteger(value) {
  const parsed = Math.floor(
    Number(value || 0),
  );
  return parsed > 0 ? parsed : null;
}

async function run() {
  const businessId =
    (
      readArg("--business-id") ||
      process.env.BUSINESS_ID ||
      process.env.PRODUCTION_LIFECYCLE_BUSINESS_ID ||
      ""
    )
      .toString()
      .trim();
  const domainContext =
    (
      readArg("--domain-context") ||
      process.env.PRODUCTION_LIFECYCLE_DOMAIN_CONTEXT ||
      "farm"
    )
      .toString()
      .trim() || "farm";
  const limit =
    toPositiveInteger(
      readArg("--limit"),
    ) || null;

  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required before seeding the crop profile manifest.",
    );
  }
  if (!businessId) {
    throw new Error(
      "--business-id or BUSINESS_ID is required.",
    );
  }

  await connectDB();

  const manifest =
    buildCropProfileSeedManifest({
      domainContext,
    });
  const targetEntries =
    limit ?
      manifest.slice(0, limit)
    : manifest;

  let storedCount = 0;
  for (const entry of targetEntries) {
    const stored =
      await persistCropProfileSeedEntry({
        businessId,
        productName:
          entry.productName,
        cropSubtype:
          entry.cropSubtype,
        domainContext:
          entry.domainContext,
        aliases: entry.aliases,
        metadata: entry.metadata,
        profileDetails:
          entry.profileDetails,
      });
    if (stored) {
      storedCount += 1;
    }
  }

  debug(
    "CROP PROFILE MANIFEST SEED: complete",
    {
      businessId,
      domainContext,
      manifestVersion:
        CROP_PROFILE_SEED_MANIFEST_VERSION,
      requestedCount:
        targetEntries.length,
      storedCount,
    },
  );

  console.log(
    "Crop profile manifest seed complete:",
    {
      businessId,
      domainContext,
      manifestVersion:
        CROP_PROFILE_SEED_MANIFEST_VERSION,
      requestedCount:
        targetEntries.length,
      storedCount,
    },
  );

  await mongoose.disconnect();
}

run().catch(async (error) => {
  console.error(
    "Crop profile manifest seed failed:",
    error.message,
  );
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
