/**
 * apps/backend/scripts/refresh-production-lifecycle-store.js
 * ----------------------------------------------------------
 * WHAT:
 * - Prefills the verified production lifecycle store from external agriculture APIs.
 *
 * WHY:
 * - Production planning should not depend on live provider coverage at request time for key crops.
 * - A business can preload tomato/pepper/onion and similar crops into the verified store.
 *
 * HOW:
 * - Connects to MongoDB.
 * - Resolves each requested crop through the verified-store-first external lifecycle resolver.
 * - Persists successful agriculture API lifecycle results into ProductionLifecycleProfile.
 *
 * USAGE:
 * - npm run ops:lifecycle:refresh -- --business-id=<ownerId> --crops=tomato,pepper,onion
 * - Optional: --estate-country=Nigeria --estate-state=Kaduna --country=NG --domain-context=farm
 */

require("dotenv").config();

const mongoose = require("mongoose");
const debug = require("../utils/debug");
const connectDB = require("../config/db");
const {
  resolveVerifiedAgricultureLifecycle,
} = require("../services/planner/lifecycleResolver");

const DEFAULT_DOMAIN_CONTEXT = "farm";
const DEFAULT_CROPS = [
  "tomato",
  "pepper",
  "onion",
  "corn",
  "beans",
  "rice",
  "cassava",
];
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
        .map((entry) => entry.trim())
        .filter(Boolean),
    ),
  );
}

function resolveProviderContext({
  businessId,
  estateCountry,
  estateState,
  country,
}) {
  return {
    route:
      "script:refresh-production-lifecycle-store",
    requestId: `lifecycle-refresh-${Date.now()}`,
    userRole: "system",
    businessId,
    source:
      "ops_refresh_verified_lifecycle_store",
    estateCountry,
    estateState,
    country,
  };
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
      DEFAULT_DOMAIN_CONTEXT
    )
      .toString()
      .trim() || DEFAULT_DOMAIN_CONTEXT;
  const estateCountry =
    (
      readArg("--estate-country") ||
      process.env.PRODUCTION_LIFECYCLE_ESTATE_COUNTRY ||
      ""
    )
      .toString()
      .trim();
  const estateState =
    (
      readArg("--estate-state") ||
      process.env.PRODUCTION_LIFECYCLE_ESTATE_STATE ||
      ""
    )
      .toString()
      .trim();
  const country =
    (
      readArg("--country") ||
      process.env.PRODUCTION_LIFECYCLE_COUNTRY ||
      ""
    )
      .toString()
      .trim();
  const crops =
    normalizeCsvList(
      readArg("--crops") ||
        process.env.PRODUCTION_LIFECYCLE_CROPS ||
        DEFAULT_CROPS.join(","),
    );

  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required before refreshing the lifecycle store.",
    );
  }
  if (!businessId) {
    throw new Error(
      "--business-id or PRODUCTION_LIFECYCLE_BUSINESS_ID is required.",
    );
  }
  if (crops.length === 0) {
    throw new Error(
      "Provide at least one crop via --crops.",
    );
  }

  debug(
    "LIFECYCLE STORE REFRESH: start",
    {
      businessId,
      domainContext,
      cropCount: crops.length,
      estateCountry,
      estateState,
      country,
    },
  );

  await connectDB();

  const context =
    resolveProviderContext({
      businessId,
      estateCountry,
      estateState,
      country,
    });

  const results = [];
  for (const cropName of crops) {
    const resolved =
      await resolveVerifiedAgricultureLifecycle({
        businessId,
        productName: cropName,
        cropSubtype: "",
        domainContext,
        aliases: [cropName],
        context,
      });

    if (!resolved) {
      results.push({
        crop: cropName,
        status: "missing",
        lifecycleSource: "",
        minDays: 0,
        maxDays: 0,
      });
      continue;
    }

    results.push({
      crop: cropName,
      status: "stored",
      lifecycleSource:
        resolved.lifecycleSource,
      minDays:
        resolved.lifecycle.minDays,
      maxDays:
        resolved.lifecycle.maxDays,
    });
  }

  const storedCount = results.filter(
    (entry) => entry.status === "stored",
  ).length;
  const missingCount =
    results.length - storedCount;

  console.log(
    "Lifecycle store refresh complete:",
    {
      businessId,
      domainContext,
      storedCount,
      missingCount,
      results,
    },
  );

  await mongoose.disconnect();
  debug(
    "LIFECYCLE STORE REFRESH: done",
    {
      businessId,
      storedCount,
      missingCount,
    },
  );
}

run().catch(async (error) => {
  console.error(
    "Lifecycle store refresh failed:",
    error.message,
  );
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
