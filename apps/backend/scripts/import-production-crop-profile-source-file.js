/**
 * apps/backend/scripts/import-production-crop-profile-source-file.js
 * ------------------------------------------------------------------
 * WHAT:
 * - Imports vetted crop profile snapshot data into the crop profile store.
 *
 * WHY:
 * - Production-grade crop details should come from reviewed source snapshots rather than ad hoc live calls.
 * - This importer upgrades seed targets into source-backed crop profiles and can persist lifecycle when present.
 *
 * USAGE:
 * - npm run ops:crop-profiles:import -- --business-id=<ownerId> --file=./tmp/crop-profiles.json --source-key=fao_ecocrop
 */

require("dotenv").config();

const fs = require("fs");
const path = require("path");
const mongoose = require("mongoose");
const connectDB = require("../config/db");
const debug = require("../utils/debug");
const {
  persistImportedCropProfile,
} = require("../services/planner/lifecycleResolver");
const {
  buildCropProfileProvenanceEntry,
  resolveCropProfileSourceDescriptor,
  normalizeCropProfileSourceKey,
} = require("../services/planner/cropProfileSources");

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

function readJsonFile(filePath) {
  const absolutePath =
    path.resolve(process.cwd(), filePath);
  const rawText = fs.readFileSync(
    absolutePath,
    "utf8",
  );
  const parsed =
    JSON.parse(rawText);
  if (Array.isArray(parsed)) {
    return parsed;
  }
  if (
    parsed &&
    Array.isArray(parsed.items)
  ) {
    return parsed.items;
  }
  throw new Error(
    "Import file must be an array or an object with an items array.",
  );
}

function buildLifecycleFromItem(item) {
  const minDays = Math.floor(
    Number(item?.lifecycle?.minDays ??
      item?.minDays ??
      0),
  );
  const maxDays = Math.floor(
    Number(item?.lifecycle?.maxDays ??
      item?.maxDays ??
      0),
  );
  const phases = Array.isArray(
    item?.lifecycle?.phases,
  ) ?
      item.lifecycle.phases
    : Array.isArray(item?.phases) ?
      item.phases
    : [];
  if (
    minDays > 0 &&
    maxDays >= minDays &&
    phases.length > 0
  ) {
    return {
      product:
        item?.productName ||
        item?.name ||
        "",
      minDays,
      maxDays,
      phases,
    };
  }
  return null;
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
  const filePath =
    (
      readArg("--file") ||
      process.env.CROP_PROFILE_IMPORT_FILE ||
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
  const sourceKey =
    normalizeCropProfileSourceKey(
      readArg("--source-key") ||
        process.env.CROP_PROFILE_SOURCE_KEY ||
        "source_import",
    );
  const onlyKinds =
    normalizeCsvList(
      readArg("--kinds") ||
        process.env.CROP_PROFILE_IMPORT_KINDS ||
        "",
    );

  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required before importing crop profile source files.",
    );
  }
  if (!businessId) {
    throw new Error(
      "--business-id or BUSINESS_ID is required.",
    );
  }
  if (!filePath) {
    throw new Error(
      "--file or CROP_PROFILE_IMPORT_FILE is required.",
    );
  }

  const sourceDescriptor =
    resolveCropProfileSourceDescriptor(
      sourceKey,
    );
  const rawItems =
    readJsonFile(filePath);
  const filteredItems =
    onlyKinds.length === 0 ?
      rawItems
    : rawItems.filter((item) =>
        onlyKinds.includes(
          (
            item?.profileDetails
              ?.profileKind ||
            item?.profileKind ||
            ""
          )
            .toString()
            .trim(),
        ),
      );

  await connectDB();

  let storedCount = 0;
  let lifecycleCount = 0;

  for (const item of filteredItems) {
    const productName =
      (
        item?.productName ||
        item?.name ||
        ""
      )
        .toString()
        .trim();
    if (!productName) {
      continue;
    }

    const lifecycle =
      buildLifecycleFromItem(item);
    const mergedProfileDetails = {
      ...(
        item?.profileDetails &&
        typeof item.profileDetails ===
          "object"
      ) ?
        item.profileDetails
      : {},
      profileKind:
        item?.profileKind ||
        item?.profileDetails
          ?.profileKind ||
        "crop",
      category:
        item?.category ||
        item?.profileDetails
          ?.category ||
        "",
      variety:
        item?.variety ||
        item?.profileDetails?.variety ||
        "",
      plantType:
        item?.plantType ||
        item?.profileDetails
          ?.plantType ||
        "",
      summary:
        item?.summary ||
        item?.profileDetails?.summary ||
        "",
      scientificName:
        item?.scientificName ||
        item?.profileDetails
          ?.scientificName ||
        "",
      family:
        item?.family ||
        item?.profileDetails?.family ||
        "",
      climate:
        item?.climate ||
        item?.profileDetails?.climate ||
        {},
      soil:
        item?.soil ||
        item?.profileDetails?.soil ||
        {},
      water:
        item?.water ||
        item?.profileDetails?.water ||
        {},
      propagation:
        item?.propagation ||
        item?.profileDetails
          ?.propagation ||
        {},
      harvestWindow:
        item?.harvestWindow ||
        item?.profileDetails
          ?.harvestWindow ||
        {},
      verificationStatus:
        item?.verificationStatus ||
        item?.profileDetails
          ?.verificationStatus ||
        (
          lifecycle ?
            sourceDescriptor.verificationStatus
          : "source_pending"
        ),
      lifecycleStatus:
        item?.lifecycleStatus ||
        item?.profileDetails
          ?.lifecycleStatus ||
        (lifecycle ?
          "verified"
        : "missing"),
      sourceProvenance: [
        buildCropProfileProvenanceEntry({
          sourceKey,
          sourceUrl:
            item?.sourceUrl || "",
          externalId:
            item?.externalId || "",
          citation:
            item?.citation || "",
          notes:
            `Imported from source file ${path.basename(filePath)}.`,
          confidence:
            item?.sourceConfidence ??
            0.9,
          verificationStatus:
            item?.verificationStatus ||
            item?.profileDetails
              ?.verificationStatus ||
            sourceDescriptor.verificationStatus,
        }),
        ...(
          Array.isArray(
            item?.profileDetails
              ?.sourceProvenance,
          ) ?
            item.profileDetails
              .sourceProvenance
          : []
        ),
      ],
    };

    const stored =
      await persistImportedCropProfile({
        businessId,
        productName,
        cropSubtype:
          (
            item?.cropSubtype || ""
          )
            .toString()
            .trim(),
        domainContext:
          (
            item?.domainContext ||
            domainContext
          )
            .toString()
            .trim() || domainContext,
        lifecycle,
        source:
          item?.source ||
          "source_import",
        sourceConfidence:
          Number(
            item?.sourceConfidence ??
              0.9,
          ) || 0.9,
        metadata: {
          importedFromFile:
            path.basename(filePath),
          importSourceKey: sourceKey,
          ...(
            item?.metadata &&
            typeof item.metadata ===
              "object"
          ) ?
            item.metadata
          : {},
        },
        aliases: Array.isArray(
          item?.aliases,
        ) ?
          item.aliases
        : [],
        profileDetails:
          mergedProfileDetails,
      });
    if (!stored) {
      continue;
    }
    storedCount += 1;
    if (lifecycle) {
      lifecycleCount += 1;
    }
  }

  debug(
    "CROP PROFILE SOURCE IMPORT: complete",
    {
      businessId,
      filePath:
        path.basename(filePath),
      sourceKey,
      importedCount:
        filteredItems.length,
      storedCount,
      lifecycleCount,
    },
  );

  console.log(
    "Crop profile source import complete:",
    {
      businessId,
      filePath:
        path.basename(filePath),
      sourceKey,
      importedCount:
        filteredItems.length,
      storedCount,
      lifecycleCount,
    },
  );

  await mongoose.disconnect();
}

run().catch(async (error) => {
  console.error(
    "Crop profile source import failed:",
    error.message,
  );
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
