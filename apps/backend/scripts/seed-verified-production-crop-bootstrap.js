/**
 * apps/backend/scripts/seed-verified-production-crop-bootstrap.js
 * ---------------------------------------------------------------
 * WHAT:
 * - Loads the curated verified crop bootstrap dataset into the production crop profile store.
 *
 * WHY:
 * - Core planner crops should be available as verified profiles even before large source snapshots are imported.
 * - This script keeps verified bootstrap records separate from the broader seed manifest queue.
 *
 * USAGE:
 * - npm run ops:crop-profiles:bootstrap -- --business-id=<ownerId>
 * - npm run ops:crop-profiles:bootstrap -- --business-id=<ownerId> --products=tomato,pepper,mango
 */

require("dotenv").config();

const mongoose = require("mongoose");
const connectDB = require("../config/db");
const debug = require("../utils/debug");
const {
  buildVerifiedCropProfileBootstrap,
  VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
} = require("../services/planner/verifiedCropProfileBootstrap");
const {
  persistImportedCropProfile,
} = require("../services/planner/lifecycleResolver");

const args = process.argv.slice(2);

function readArg(key) {
  return args
    .find((arg) => arg.startsWith(`${key}=`))
    ?.slice(`${key}=`.length);
}

function normalizeCsvList(value) {
  return Array.from(
    new Set(
      (value || "")
        .toString()
        .split(",")
        .map((entry) =>
          entry.toString().trim().toLowerCase(),
        )
        .filter(Boolean),
    ),
  );
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
  const selectedProducts =
    normalizeCsvList(
      readArg("--products") ||
        process.env
          .PRODUCTION_BOOTSTRAP_PRODUCTS ||
        "",
    );

  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required before seeding the verified crop bootstrap.",
    );
  }
  if (!businessId) {
    throw new Error(
      "--business-id or BUSINESS_ID is required.",
    );
  }

  await connectDB();

  const bootstrapEntries =
    buildVerifiedCropProfileBootstrap({
      domainContext,
    });
  const targetEntries =
    selectedProducts.length === 0 ?
      bootstrapEntries
    : bootstrapEntries.filter((entry) => {
        const haystack = [
          entry.productName,
          ...(Array.isArray(entry.aliases) ?
            entry.aliases
          : []),
        ]
          .map((value) =>
            value
              .toString()
              .trim()
              .toLowerCase(),
          )
          .filter(Boolean);
        return selectedProducts.some((needle) =>
          haystack.includes(needle),
        );
      });

  let storedCount = 0;
  let lifecycleCount = 0;

  for (const entry of targetEntries) {
    const stored =
      await persistImportedCropProfile({
        businessId,
        productName: entry.productName,
        cropSubtype: entry.cropSubtype,
        domainContext:
          entry.domainContext,
        lifecycle: entry.lifecycle,
        source: "source_import",
        sourceConfidence: 0.98,
        metadata: {
          bootstrapVersion:
            VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
          bootstrapKind:
            "verified_core_crop_profile",
          ...(
            entry.metadata &&
            typeof entry.metadata === "object"
          ) ?
            entry.metadata
          : {},
        },
        aliases: entry.aliases,
        profileDetails:
          entry.profileDetails,
      });
    if (!stored) {
      continue;
    }
    storedCount += 1;
    lifecycleCount += 1;
  }

  debug(
    "VERIFIED CROP PROFILE BOOTSTRAP: complete",
    {
      businessId,
      domainContext,
      bootstrapVersion:
        VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
      requestedCount:
        targetEntries.length,
      storedCount,
      lifecycleCount,
    },
  );

  console.log(
    "Verified crop profile bootstrap complete:",
    {
      businessId,
      domainContext,
      bootstrapVersion:
        VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
      requestedCount:
        targetEntries.length,
      storedCount,
      lifecycleCount,
    },
  );

  await mongoose.disconnect();
}

run().catch(async (error) => {
  console.error(
    "Verified crop profile bootstrap failed:",
    error.message,
  );
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
