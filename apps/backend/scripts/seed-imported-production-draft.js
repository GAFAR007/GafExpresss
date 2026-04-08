#!/usr/bin/env node
/**
 * scripts/seed-imported-production-draft.js
 * -----------------------------------------
 * WHAT:
 * - Imports a reviewed production-plan PDF and persists it as a draft plan.
 *
 * WHY:
 * - Gives operators a repeatable backend seed path for document-based drafts.
 * - Reuses the same business-scoped product + plan controllers as the app.
 *
 * HOW:
 * - Resolves the target owner, estate, and product.
 * - Extracts phases/tasks from the source PDF.
 * - Fills any missing planting-target fields with explicit seed overrides.
 * - Creates or updates the draft through the production plan controllers.
 *
 * SAFETY:
 * - Dry-run by default. Pass --execute to write to MongoDB.
 */

const fs = require("fs");
const path = require("path");

require("dotenv").config({
  path: path.resolve(__dirname, "..", ".env"),
  quiet: true,
});

const mongoose = require("mongoose");

const connectDB = require("../config/db");
const User = require("../models/User");
const Product = require("../models/Product");
const BusinessAsset = require("../models/BusinessAsset");
const ProductionPlan = require("../models/ProductionPlan");
const businessProductService = require("../services/business.product.service");
const {
  extractAiDraftSourceDocumentContext,
  buildProductionDraftImportResponse,
} = require("../services/production_plan_import.service");
const {
  createProductionPlan,
  updateProductionPlanDraft,
} = require("../controllers/business.controller");

const args = process.argv.slice(2);
const shouldExecute = args.includes("--execute");
const shouldShowHelp =
  args.includes("--help") || args.includes("-h");

const ownerEmailArg = readArg("--owner-email=");
const businessIdArg = readArg("--business-id=");
const estateNameArg = readArg("--estate-name=");
const estateAssetIdArg = readArg(
  "--estate-asset-id=",
);
const productNameArg = readArg("--product-name=");
const productCategoryArg = readArg(
  "--product-category=",
);
const productSubcategoryArg = readArg(
  "--product-subcategory=",
);
const brandArg = readArg("--brand=");
const planTitleArg = readArg("--plan-title=");
const pdfPathArg =
  readArg("--pdf-path=") ||
  readArg("--source-pdf=") ||
  args.find((value) => !value.startsWith("--")) ||
  "";
const estimatedHarvestQuantityArg = readArg(
  "--estimated-harvest-quantity=",
);
const estimatedHarvestUnitArg = readArg(
  "--estimated-harvest-unit=",
);
const priceArg = readArg("--price=");
const stockArg = readArg("--stock=");

const DEFAULT_PRODUCT_NAME = "Bell Pepper";
const DEFAULT_PRODUCT_CATEGORY = "Farm & Agro";
const DEFAULT_PRODUCT_SUBCATEGORY = "Vegetables";
const DEFAULT_PRODUCT_PACKAGE_TYPE = "crate";
const DEFAULT_PRODUCT_MEASUREMENT_UNIT = "crate";

const PRODUCT_PLANTING_TARGET_DEFAULTS = {
  bell_pepper: {
    materialType: "seedling",
    estimatedHarvestQuantity: 5500,
    estimatedHarvestUnit: "kg",
  },
};

function readArg(prefix) {
  const match = args.find((arg) =>
    arg.startsWith(prefix),
  );
  return match
    ? match.slice(prefix.length).trim()
    : "";
}

function normalizeText(value) {
  return (value || "")
    .toString()
    .trim()
    .replace(/\s+/g, " ");
}

function normalizeProductKey(value) {
  return normalizeText(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function escapeRegExp(value) {
  return (value || "")
    .toString()
    .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizePositiveNumber(value) {
  if (value == null || value === "") {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

function normalizeNonNegativeNumber(
  value,
  fallback = 0,
) {
  if (value == null || value === "") {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return parsed;
}

function detectDocumentTitle(text) {
  const lines = (text || "")
    .split(/\r?\n/)
    .map((line) => normalizeText(line))
    .filter(Boolean);
  return (
    lines.find(
      (line) =>
        /production plan/i.test(line) &&
        !/^phase\s+\d+/i.test(line),
    ) || ""
  );
}

function buildSeedMarker({
  fileName,
  estateName,
  productName,
}) {
  return `[seed-imported-production-draft:${normalizeText(fileName)}:${normalizeProductKey(productName)}:${normalizeProductKey(estateName)}]`;
}

function buildSeedNotes({
  baseNotes,
  fileName,
  estateName,
  ownerName,
  productName,
}) {
  return [
    normalizeText(baseNotes),
    `Imported from ${fileName}.`,
    `Seed target estate: ${estateName}.`,
    `Seed target owner: ${ownerName}.`,
    buildSeedMarker({
      fileName,
      estateName,
      productName,
    }),
  ]
    .filter(Boolean)
    .join(" ");
}

function mergePlantingTargets({
  plantingTargets,
  productName,
  estimatedHarvestQuantity,
  estimatedHarvestUnit,
}) {
  const normalizedProductKey =
    normalizeProductKey(productName);
  const fallbackTargets =
    PRODUCT_PLANTING_TARGET_DEFAULTS[
      normalizedProductKey
    ] || {};

  const resolvedHarvestQuantity =
    normalizePositiveNumber(
      estimatedHarvestQuantity,
    ) ||
    normalizePositiveNumber(
      plantingTargets?.estimatedHarvestQuantity,
    ) ||
    normalizePositiveNumber(
      fallbackTargets.estimatedHarvestQuantity,
    );
  const resolvedHarvestUnit = normalizeText(
    estimatedHarvestUnit ||
      plantingTargets?.estimatedHarvestUnit ||
      fallbackTargets.estimatedHarvestUnit,
  ).toLowerCase();

  return {
    materialType:
      normalizeText(
        plantingTargets?.materialType ||
          fallbackTargets.materialType,
      ).toLowerCase() || "seedling",
    plannedPlantingQuantity:
      normalizePositiveNumber(
        plantingTargets?.plannedPlantingQuantity,
      ) || null,
    plannedPlantingUnit:
      normalizeText(
        plantingTargets?.plannedPlantingUnit,
      ).toLowerCase() || "",
    estimatedHarvestQuantity:
      resolvedHarvestQuantity || null,
    estimatedHarvestUnit:
      resolvedHarvestUnit || "",
  };
}

function hasCompletePlantingTargets(
  plantingTargets,
) {
  return Boolean(
    normalizeText(
      plantingTargets?.materialType,
    ) &&
    normalizeText(
      plantingTargets?.plannedPlantingUnit,
    ) &&
    normalizeText(
      plantingTargets?.estimatedHarvestUnit,
    ) &&
    Number(
      plantingTargets?.plannedPlantingQuantity,
    ) > 0 &&
    Number(
      plantingTargets?.estimatedHarvestQuantity,
    ) > 0,
  );
}

function buildMockResponse() {
  let statusCode = 200;
  let resolveJson;
  const response = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(payload) {
      resolveJson({
        statusCode,
        payload,
      });
      return this;
    },
  };

  const promise = new Promise((resolve) => {
    resolveJson = resolve;
  });

  return {
    response,
    promise,
  };
}

async function invokeController({
  handler,
  userId,
  body,
  params = {},
}) {
  const { response, promise } =
    buildMockResponse();
  const request = {
    user: {
      sub: userId,
    },
    params,
    body,
  };

  await handler(request, response);
  return promise;
}

function printHelp() {
  console.log(`
Import and seed a production plan draft from a source PDF

Usage:
 node scripts/seed-imported-production-draft.js [options] <pdf-path>

Options:
 --execute                             Persist changes. Dry-run is the default.
 --owner-email=<email>                 Target business owner email.
 --business-id=<id>                    Target business owner id.
 --estate-name=<name>                  Target estate name.
 --estate-asset-id=<id>                Target estate asset id.
 --pdf-path=<path>                     Source PDF path.
 --product-name=<name>                 Product name. Defaults to Bell Pepper.
 --product-category=<value>            Product category. Defaults to Farm & Agro.
 --product-subcategory=<value>         Product subcategory. Defaults to Vegetables.
 --brand=<value>                       Product brand. Defaults to owner company name.
 --plan-title=<value>                  Override the imported plan title.
 --estimated-harvest-quantity=<value>  Override missing harvest target quantity.
 --estimated-harvest-unit=<value>      Override missing harvest target unit.
 --price=<value>                       Product price. Defaults to 0.
 --stock=<value>                       Product stock. Defaults to 0.
 --help                                Show this help and exit.

Examples:
 node scripts/seed-imported-production-draft.js \\
   --owner-email=olabodeadams@gafarhydroponyfarmfarm.com \\
   --estate-name="Olabode's Estate" \\
   --execute \\
   /Users/gafar/Downloads/bell_pepper_greenhouse_plan_filled.pdf
 `);
}

async function resolveOwner() {
  if (businessIdArg) {
    return User.findOne({
      _id: businessIdArg,
      role: "business_owner",
    });
  }
  if (ownerEmailArg) {
    return User.findOne({
      email: ownerEmailArg,
      role: "business_owner",
    });
  }
  throw new Error(
    "Provide --owner-email or --business-id.",
  );
}

async function resolveEstate({ businessId }) {
  if (estateAssetIdArg) {
    return BusinessAsset.findOne({
      _id: estateAssetIdArg,
      businessId,
      assetType: "estate",
    });
  }
  if (estateNameArg) {
    return BusinessAsset.findOne({
      businessId,
      assetType: "estate",
      name: {
        $regex: `^${escapeRegExp(
          estateNameArg,
        )}$`,
        $options: "i",
      },
    });
  }
  throw new Error(
    "Provide --estate-name or --estate-asset-id.",
  );
}

async function resolveOrCreateProduct({
  owner,
  businessId,
  productName,
}) {
  const existingProduct = await Product.findOne({
    businessId,
    name: {
      $regex: `^${escapeRegExp(productName)}$`,
      $options: "i",
    },
  });
  if (existingProduct) {
    return {
      product: existingProduct,
      created: false,
    };
  }

  if (!shouldExecute) {
    return {
      product: {
        _id: "DRY_RUN_PRODUCT_ID",
        name: productName,
      },
      created: true,
    };
  }

  const createdProduct =
    await businessProductService.createProduct({
      data: {
        name: productName,
        description: `Imported production output placeholder for ${productName} at ${owner.companyName || owner.name}.`,
        category:
          productCategoryArg ||
          DEFAULT_PRODUCT_CATEGORY,
        subcategory:
          productSubcategoryArg ||
          DEFAULT_PRODUCT_SUBCATEGORY,
        brand:
          brandArg ||
          owner.companyName ||
          owner.name,
        sellingOptions: [
          {
            packageType:
              DEFAULT_PRODUCT_PACKAGE_TYPE,
            quantity: 1,
            measurementUnit:
              DEFAULT_PRODUCT_MEASUREMENT_UNIT,
            isDefault: true,
          },
        ],
        price: normalizeNonNegativeNumber(
          priceArg,
          0,
        ),
        stock: normalizeNonNegativeNumber(
          stockArg,
          0,
        ),
        isActive: false,
        productionState: "planned",
      },
      actor: {
        id: owner._id,
        role: owner.role,
      },
      businessId,
    });

  return {
    product: createdProduct,
    created: true,
  };
}

async function findExistingSeededDraft({
  businessId,
  estateAssetId,
  productId,
  seedMarker,
}) {
  return ProductionPlan.findOne({
    businessId,
    estateAssetId,
    productId,
    status: "draft",
    notes: {
      $regex: escapeRegExp(seedMarker),
    },
  }).sort({ updatedAt: -1 });
}

async function main() {
  if (shouldShowHelp) {
    printHelp();
    return;
  }

  if (!pdfPathArg) {
    throw new Error(
      "A source PDF path is required.",
    );
  }

  const absolutePdfPath =
    path.resolve(pdfPathArg);
  if (!fs.existsSync(absolutePdfPath)) {
    throw new Error(
      `Source PDF not found: ${absolutePdfPath}`,
    );
  }

  await connectDB();

  const owner = await resolveOwner();
  if (!owner) {
    throw new Error(
      "Target business owner not found.",
    );
  }

  const estate = await resolveEstate({
    businessId: owner._id,
  });
  if (!estate) {
    throw new Error(
      "Target estate not found for the selected business owner.",
    );
  }

  const productName =
    normalizeText(productNameArg) ||
    DEFAULT_PRODUCT_NAME;
  const { product, created: productCreated } =
    await resolveOrCreateProduct({
      owner,
      businessId: owner._id,
      productName,
    });

  const fileName = path.basename(absolutePdfPath);
  const sourceDocumentContext =
    extractAiDraftSourceDocumentContext({
      fileName,
      extension: "pdf",
      contentBase64: fs
        .readFileSync(absolutePdfPath)
        .toString("base64"),
    });
  if (!sourceDocumentContext?.text) {
    throw new Error(
      "Could not extract planning text from the source PDF.",
    );
  }

  const importedTitle =
    normalizeText(planTitleArg) ||
    detectDocumentTitle(
      sourceDocumentContext.text,
    ) ||
    `${productName} Production Plan`;
  const importResponse =
    buildProductionDraftImportResponse({
      sourceDocumentContext,
      estateAssetId: estate._id.toString(),
      productId: product._id.toString(),
      productName,
      domainContext: "farm",
      plantingTargets: {},
      titleFallback: importedTitle,
    });
  if (!importResponse?.draft?.phases?.length) {
    throw new Error(
      "Could not build an imported draft from the source PDF.",
    );
  }

  const plantingTargets = mergePlantingTargets({
    plantingTargets:
      importResponse.draft.plantingTargets,
    productName,
    estimatedHarvestQuantity:
      estimatedHarvestQuantityArg,
    estimatedHarvestUnit: estimatedHarvestUnitArg,
  });
  if (
    !hasCompletePlantingTargets(plantingTargets)
  ) {
    throw new Error(
      "Imported draft is missing required planting targets. Provide --estimated-harvest-quantity and --estimated-harvest-unit.",
    );
  }

  const seedMarker = buildSeedMarker({
    fileName,
    estateName: estate.name,
    productName,
  });
  const notes = buildSeedNotes({
    baseNotes: importResponse.draft.notes,
    fileName,
    estateName: estate.name,
    ownerName: owner.name,
    productName,
  });
  const existingDraft =
    product?._id &&
    !String(product._id).startsWith("DRY_RUN_")
      ? await findExistingSeededDraft({
          businessId: owner._id,
          estateAssetId: estate._id,
          productId: product._id,
          seedMarker,
        })
      : null;

  const payload = {
    saveMode: "draft",
    estateAssetId: estate._id.toString(),
    productId: product._id.toString(),
    title: importedTitle,
    notes,
    aiGenerated: false,
    domainContext: "farm",
    startDate: importResponse.draft.startDate,
    endDate: importResponse.draft.endDate,
    plantingTargets,
    phases: importResponse.draft.phases,
  };

  const summary = {
    execute: shouldExecute,
    owner: {
      id: owner._id.toString(),
      email: owner.email,
      name: owner.name,
      companyName: owner.companyName,
    },
    estate: {
      id: estate._id.toString(),
      name: estate.name,
    },
    product: {
      id: product._id.toString(),
      name: product.name,
      created: productCreated,
    },
    existingDraftId:
      existingDraft?._id?.toString() || null,
    sourceDocument: {
      path: absolutePdfPath,
      fileName,
      taskLineEstimate:
        sourceDocumentContext.taskLineEstimate,
    },
    draft: {
      title: payload.title,
      startDate: payload.startDate,
      endDate: payload.endDate,
      phaseCount: payload.phases.length,
      taskCount: payload.phases.reduce(
        (sum, phase) =>
          sum +
          (Array.isArray(phase.tasks)
            ? phase.tasks.length
            : 0),
        0,
      ),
      plantingTargets,
    },
  };

  if (!shouldExecute) {
    console.log(
      JSON.stringify(
        {
          ...summary,
          action: existingDraft
            ? "would_update_existing_draft"
            : "would_create_new_draft",
        },
        null,
        2,
      ),
    );
    return;
  }

  const controllerResult = existingDraft
    ? await invokeController({
        handler: updateProductionPlanDraft,
        userId: owner._id.toString(),
        params: {
          id: existingDraft._id.toString(),
        },
        body: payload,
      })
    : await invokeController({
        handler: createProductionPlan,
        userId: owner._id.toString(),
        body: payload,
      });

  if (controllerResult.statusCode >= 400) {
    throw new Error(
      controllerResult.payload?.error ||
        `Draft seed failed with status ${controllerResult.statusCode}.`,
    );
  }

  console.log(
    JSON.stringify(
      {
        ...summary,
        action: existingDraft
          ? "updated_existing_draft"
          : "created_new_draft",
        result: {
          statusCode: controllerResult.statusCode,
          message:
            controllerResult.payload?.message ||
            "",
          planId:
            controllerResult.payload?.plan?._id?.toString() ||
            null,
          phaseCount: Array.isArray(
            controllerResult.payload?.phases,
          )
            ? controllerResult.payload.phases
                .length
            : 0,
          taskCount: Array.isArray(
            controllerResult.payload?.tasks,
          )
            ? controllerResult.payload.tasks
                .length
            : 0,
        },
      },
      null,
      2,
    ),
  );
}

main()
  .catch((error) => {
    console.error(
      error?.stack || error?.message || error,
    );
    process.exitCode = 1;
  })
  .finally(async () => {
    if (mongoose.connection.readyState !== 0) {
      await mongoose.disconnect();
    }
  });
