/**
 * scripts/normalize-rent-kobo.js
 * --------------------------------
 * WHAT:
 * - Normalizes stored rent amounts to kobo for estate unit mixes and tenant applications.
 *
 * WHY:
 * - Paystack expects minor units (kobo), and rent amounts must be consistent in storage.
 * - Legacy data may have rent amounts stored in naira, causing under-charged payments.
 *
 * HOW:
 * - Loads estate assets and tenant applications.
 * - Converts rentAmount to kobo when values are below a kobo threshold (or forced).
 * - Supports dry-run mode and threshold overrides.
 */

require("dotenv").config();

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const connectDB = require("../config/db");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");

// WHY: Paystack uses kobo for NGN, so multiply naira by 100.
const NAIRA_TO_KOBO = 100;

// WHY: Values below this are assumed to be naira (not kobo).
const DEFAULT_KOBO_THRESHOLD = 1_000_000;

const args = process.argv.slice(2);
const isDryRun = args.includes("--dry-run");
const forceAll = args.includes("--force-all");
const thresholdArg = args.find((arg) => arg.startsWith("--threshold="));

function parseThreshold() {
  // WHY: Allow CLI override to tune conversion safety.
  if (!thresholdArg) return DEFAULT_KOBO_THRESHOLD;
  const raw = thresholdArg.split("=")[1];
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error("Invalid --threshold value");
  }
  return value;
}

function shouldConvert(amount, threshold) {
  // WHY: Skip invalid amounts and avoid double-conversion by default.
  if (!Number.isFinite(amount) || amount <= 0) return false;
  if (forceAll) return true;
  return amount < threshold;
}

async function normalizeAssets(threshold) {
  debug("NORMALIZE RENT: assets start", {
    dryRun: isDryRun,
    threshold,
    forceAll,
  });

  const assets = await BusinessAsset.find({
    assetType: "estate",
    "estate.unitMix.0": { $exists: true },
  });

  debug("NORMALIZE RENT: assets loaded", {
    count: assets.length,
  });

  let updatedAssets = 0;
  let updatedUnits = 0;

  for (const asset of assets) {
    const unitMix = Array.isArray(asset.estate?.unitMix)
      ? asset.estate.unitMix
      : [];
    let changed = 0;

    for (const unit of unitMix) {
      const rawRent = Number(unit?.rentAmount ?? 0);
      if (!shouldConvert(rawRent, threshold)) {
        continue;
      }
      // WHY: Normalize to kobo to align with payment expectations.
      unit.rentAmount = Math.round(rawRent * NAIRA_TO_KOBO);
      changed += 1;
      updatedUnits += 1;
    }

    if (changed > 0) {
      updatedAssets += 1;
      asset.markModified("estate.unitMix");
      debug("NORMALIZE RENT: asset updated", {
        assetId: asset._id.toString(),
        changedUnits: changed,
      });
      if (!isDryRun) {
        await asset.save();
      }
    }
  }

  return {
    updatedAssets,
    updatedUnits,
  };
}

async function normalizeTenantApplications(threshold) {
  debug("NORMALIZE RENT: applications start", {
    dryRun: isDryRun,
    threshold,
    forceAll,
  });

  const applications = await BusinessTenantApplication.find({});
  debug("NORMALIZE RENT: applications loaded", {
    count: applications.length,
  });

  let updatedApplications = 0;

  for (const application of applications) {
    const rawRent = Number(application.rentAmount ?? 0);
    if (!shouldConvert(rawRent, threshold)) {
      continue;
    }
    // WHY: Normalize stored rent amounts so payment math stays consistent.
    application.rentAmount = Math.round(rawRent * NAIRA_TO_KOBO);
    updatedApplications += 1;
    debug("NORMALIZE RENT: application updated", {
      applicationId: application._id.toString(),
    });
    if (!isDryRun) {
      await application.save();
    }
  }

  return {
    updatedApplications,
  };
}

async function run() {
  const threshold = parseThreshold();
  debug("NORMALIZE RENT: start", {
    dryRun: isDryRun,
    threshold,
    forceAll,
  });

  await connectDB();

  const assetResult = await normalizeAssets(threshold);
  const applicationResult =
    await normalizeTenantApplications(threshold);

  console.log("Normalize rent complete:", {
    dryRun: isDryRun,
    threshold,
    forceAll,
    ...assetResult,
    ...applicationResult,
  });

  await mongoose.disconnect();
  debug("NORMALIZE RENT: done");
}

run().catch((err) => {
  console.error("Normalize rent failed:", err.message);
  process.exit(1);
});
