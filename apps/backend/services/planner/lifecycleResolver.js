/**
 * apps/backend/services/planner/lifecycleResolver.js
 * --------------------------------------------------
 * WHAT:
 * - Resolves product lifecycle profiles for planner V2.
 *
 * WHY:
 * - Farm-first planning must respect real biological duration bounds and phase order.
 * - Seeded lifecycle records keep known crops fast and deterministic.
 *
 * HOW:
 * - Reuses cached lifecycle profiles first when available.
 * - Falls back to the seeded lifecycle database when cache is missing.
 * - Fails clearly when no trusted lifecycle source is available.
 */

const debug = require("../../utils/debug");
const ProductionLifecycleProfile = require("../../models/ProductionLifecycleProfile");
const {
  DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
} = require("../../utils/production_engine.config");
const {
  buildPlannerValidationError,
  normalizePhaseName,
} = require("./validationEngine");
const {
  findCatalogLifecycleProfile,
  normalizeLifecycleCatalogKey,
} = require("./lifecycleCatalog");
const {
  fetchAgricultureLifecycleProfile,
} = require("./agricultureApiClient");
const {
  findLocalPlannerCropCatalogItem,
} = require("./plannerCropCatalog");

let lifecycleCachePersistenceDisabled = false;
let lifecycleCacheCollectionAvailability = null;
const DEFAULT_LIFECYCLE_NEGATIVE_CACHE_TTL_MS =
  6 * 60 * 60 * 1000;
const LIFECYCLE_NEGATIVE_CACHE_TTL_MS =
  Math.max(
    60 * 1000,
    Number(
      process.env
        .PRODUCTION_LIFECYCLE_NEGATIVE_CACHE_TTL_MS ||
        DEFAULT_LIFECYCLE_NEGATIVE_CACHE_TTL_MS,
    ) || DEFAULT_LIFECYCLE_NEGATIVE_CACHE_TTL_MS,
  );
const lifecycleNegativeCache = new Map();

function escapeRegexPattern(value) {
  return (value || "")
    .toString()
    .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isCollectionLimitError(error) {
  const message = (error?.message || "")
    .toString()
    .toLowerCase();
  return (
    message.includes("cannot create a new collection") ||
    message.includes("already using") ||
    message.includes("too many collections")
  );
}

async function resolveLifecycleCacheCollectionAvailability() {
  if (lifecycleCachePersistenceDisabled) {
    return false;
  }
  if (lifecycleCacheCollectionAvailability !== null) {
    return lifecycleCacheCollectionAvailability;
  }

  const database = ProductionLifecycleProfile?.db?.db;
  const collectionName =
    ProductionLifecycleProfile?.collection?.collectionName;
  if (
    !database ||
    typeof database.listCollections !== "function" ||
    !collectionName
  ) {
    lifecycleCacheCollectionAvailability = false;
    return lifecycleCacheCollectionAvailability;
  }

  try {
    const collections = await database
      .listCollections(
        { name: collectionName },
        { nameOnly: true },
      )
      .toArray();
    lifecycleCacheCollectionAvailability =
      collections.some(
        (entry) => entry?.name === collectionName,
      );
    return lifecycleCacheCollectionAvailability;
  } catch (error) {
    if (isCollectionLimitError(error)) {
      lifecycleCachePersistenceDisabled = true;
    }
    lifecycleCacheCollectionAvailability = false;
    debug(
      "PLANNER_V2_LIFECYCLE: cache collection lookup skipped",
      {
        intent:
          "planner should continue even when lifecycle cache collection lookup is unavailable",
        collectionName,
        cacheDisabled:
          lifecycleCachePersistenceDisabled,
        reason:
          error?.message ||
          "unknown_cache_collection_lookup_error",
      },
    );
    return lifecycleCacheCollectionAvailability;
  }
}

function buildLifecycleNegativeCacheKey({
  businessId,
  productKey,
  cropSubtype,
  domainContext,
}) {
  const normalizedProductKey =
    normalizeLifecycleCatalogKey(productKey);
  if (!normalizedProductKey) {
    return "";
  }
  return [
    businessId?.toString?.() || "global",
    normalizedProductKey,
    normalizeLifecycleCatalogKey(cropSubtype),
    domainContext || DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  ].join("::");
}

function readNegativeLifecycleCache(scope) {
  const cacheKey =
    buildLifecycleNegativeCacheKey(scope);
  if (!cacheKey) {
    return null;
  }
  const entry =
    lifecycleNegativeCache.get(cacheKey) || null;
  if (!entry) {
    return null;
  }
  if (entry.expiresAt <= Date.now()) {
    lifecycleNegativeCache.delete(cacheKey);
    return null;
  }
  return entry;
}

function writeNegativeLifecycleCache(scope) {
  const cacheKey =
    buildLifecycleNegativeCacheKey(scope);
  if (!cacheKey) {
    return;
  }
  lifecycleNegativeCache.set(cacheKey, {
    expiresAt:
      Date.now() +
      LIFECYCLE_NEGATIVE_CACHE_TTL_MS,
  });
}

function clearNegativeLifecycleCache(scope) {
  const cacheKey =
    buildLifecycleNegativeCacheKey(scope);
  if (!cacheKey) {
    return;
  }
  lifecycleNegativeCache.delete(cacheKey);
}

function normalizeLifecycleAliases(values) {
  return Array.from(
    new Set(
      (Array.isArray(values) ? values : [values])
        .flatMap((value) => value)
        .map((value) =>
          (value == null ? "" : value.toString()).trim(),
        )
        .filter(Boolean),
    ),
  );
}

function buildLifecycleAliasCandidates({
  productName,
  productKey,
  cropSubtype,
  lifecycle,
  metadata = {},
  aliases = [],
}) {
  return normalizeLifecycleAliases([
    ...(Array.isArray(aliases) ? aliases : []),
    productName,
    lifecycle?.product,
    productKey,
    cropSubtype,
    metadata?.scientificName,
    metadata?.trefleSlug,
  ]);
}

function normalizeOptionalText(value) {
  return (value == null ? "" : value.toString()).trim();
}

function normalizeOptionalNumber(value) {
  if (value == null || value === "") {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeStringList(values) {
  return Array.from(
    new Set(
      (Array.isArray(values) ? values : [values])
        .flatMap((entry) => entry)
        .map((entry) => normalizeOptionalText(entry))
        .filter(Boolean),
    ),
  );
}

function normalizeProfileKind(value) {
  const normalized =
    normalizeOptionalText(value).toLowerCase();
  if (
    normalized === "fruit" ||
    normalized === "plant"
  ) {
    return normalized;
  }
  return "crop";
}

function normalizeVerificationStatus(value) {
  const normalized =
    normalizeOptionalText(value).toLowerCase();
  if (
    normalized === "seed_manifest" ||
    normalized === "source_verified" ||
    normalized === "review_required" ||
    normalized === "manual_verified"
  ) {
    return normalized;
  }
  return "source_pending";
}

function normalizeLifecycleStatus(value) {
  const normalized =
    normalizeOptionalText(value).toLowerCase();
  if (
    normalized === "verified" ||
    normalized === "estimated"
  ) {
    return normalized;
  }
  return "missing";
}

function normalizeClimateDetails(value = {}) {
  return {
    climateZones:
      normalizeStringList(
        value?.climateZones,
      ),
    lightPreference:
      normalizeOptionalText(
        value?.lightPreference,
      ),
    humidityPreference:
      normalizeOptionalText(
        value?.humidityPreference,
      ),
    temperatureMinC:
      normalizeOptionalNumber(
        value?.temperatureMinC,
      ),
    temperatureMaxC:
      normalizeOptionalNumber(
        value?.temperatureMaxC,
      ),
    rainfallMinMm:
      normalizeOptionalNumber(
        value?.rainfallMinMm,
      ),
    rainfallMaxMm:
      normalizeOptionalNumber(
        value?.rainfallMaxMm,
      ),
    notes:
      normalizeOptionalText(value?.notes),
  };
}

function normalizeSoilDetails(value = {}) {
  return {
    textures:
      normalizeStringList(value?.textures),
    drainage:
      normalizeOptionalText(value?.drainage),
    fertility:
      normalizeOptionalText(value?.fertility),
    phMin:
      normalizeOptionalNumber(value?.phMin),
    phMax:
      normalizeOptionalNumber(value?.phMax),
    notes:
      normalizeOptionalText(value?.notes),
  };
}

function normalizeWaterDetails(value = {}) {
  return {
    requirement:
      normalizeOptionalText(
        value?.requirement,
      ),
    irrigationNotes:
      normalizeOptionalText(
        value?.irrigationNotes,
      ),
    minimumPrecipitationMm:
      normalizeOptionalNumber(
        value?.minimumPrecipitationMm,
      ),
    maximumPrecipitationMm:
      normalizeOptionalNumber(
        value?.maximumPrecipitationMm,
      ),
  };
}

function normalizePropagationDetails(
  value = {},
) {
  return {
    methods:
      normalizeStringList(value?.methods),
    notes:
      normalizeOptionalText(value?.notes),
  };
}

function normalizeHarvestWindowDetails(
  value = {},
) {
  return {
    earliestDays:
      normalizeOptionalNumber(
        value?.earliestDays,
      ),
    latestDays:
      normalizeOptionalNumber(
        value?.latestDays,
      ),
    seasons:
      normalizeStringList(value?.seasons),
    notes:
      normalizeOptionalText(value?.notes),
  };
}

function normalizeSourceProvenanceEntries(
  entries = [],
) {
  return (Array.isArray(entries) ? entries : [])
    .map((entry) => ({
      sourceKey:
        normalizeOptionalText(entry?.sourceKey),
      sourceLabel:
        normalizeOptionalText(entry?.sourceLabel),
      authority:
        normalizeOptionalText(entry?.authority),
      sourceUrl:
        normalizeOptionalText(entry?.sourceUrl),
      citation:
        normalizeOptionalText(entry?.citation),
      license:
        normalizeOptionalText(entry?.license),
      externalId:
        normalizeOptionalText(entry?.externalId),
      confidence:
        normalizeOptionalNumber(
          entry?.confidence,
        ),
      verificationStatus:
        normalizeVerificationStatus(
          entry?.verificationStatus,
        ),
      fetchedAt:
        entry?.fetchedAt ?
          new Date(entry.fetchedAt)
        : null,
      notes:
        normalizeOptionalText(entry?.notes),
    }))
    .filter(
      (entry) =>
        entry.sourceKey ||
        entry.sourceLabel ||
        entry.authority ||
        entry.sourceUrl,
    );
}

function isLifecycleReadyProfile(profile) {
  const minDays =
    Number(profile?.minDays || 0) || 0;
  const maxDays =
    Number(profile?.maxDays || 0) || 0;
  return (
    normalizeLifecycleStatus(
      profile?.lifecycleStatus,
    ) === "verified" &&
    minDays > 0 &&
    maxDays >= minDays &&
    Array.isArray(profile?.phases) &&
    profile.phases.length > 0
  );
}

function buildProfileSummary({
  productName,
  category,
  scientificName,
  family,
}) {
  const segments = [
    normalizeOptionalText(category),
    normalizeOptionalText(scientificName),
    normalizeOptionalText(family),
  ].filter(Boolean);
  if (segments.length === 0) {
    return normalizeOptionalText(productName);
  }
  return segments.join(" | ");
}

function buildStoredCropProfilePatch({
  productName,
  profileKind = "crop",
  category = "",
  variety = "",
  plantType = "",
  summary = "",
  scientificName = "",
  family = "",
  climate = {},
  soil = {},
  water = {},
  propagation = {},
  harvestWindow = {},
  verificationStatus = "source_pending",
  lifecycleStatus = "missing",
  sourceProvenance = [],
}) {
  return {
    productName:
      normalizeOptionalText(productName),
    profileKind:
      normalizeProfileKind(profileKind),
    category:
      normalizeOptionalText(category),
    variety:
      normalizeOptionalText(variety),
    plantType:
      normalizeOptionalText(plantType),
    summary:
      normalizeOptionalText(summary),
    scientificName:
      normalizeOptionalText(
        scientificName,
      ),
    family:
      normalizeOptionalText(family),
    climate:
      normalizeClimateDetails(climate),
    soil:
      normalizeSoilDetails(soil),
    water:
      normalizeWaterDetails(water),
    propagation:
      normalizePropagationDetails(
        propagation,
      ),
    harvestWindow:
      normalizeHarvestWindowDetails(
        harvestWindow,
      ),
    verificationStatus:
      normalizeVerificationStatus(
        verificationStatus,
      ),
    lifecycleStatus:
      normalizeLifecycleStatus(
        lifecycleStatus,
      ),
    sourceProvenance:
      normalizeSourceProvenanceEntries(
        sourceProvenance,
      ),
  };
}

function hasOwnField(object, field) {
  return Boolean(
    object &&
      Object.prototype.hasOwnProperty.call(
        object,
        field,
      ),
  );
}

function resolvePreferredTextValue({
  incoming,
  fallback = "",
}) {
  const normalizedIncoming =
    normalizeOptionalText(incoming);
  if (normalizedIncoming) {
    return normalizedIncoming;
  }
  return normalizeOptionalText(fallback);
}

function mergeNormalizedDetailObject({
  existingValue,
  incomingValue,
  normalizer,
}) {
  const normalizedExisting =
    normalizer(existingValue || {});
  if (
    !incomingValue ||
    typeof incomingValue !== "object" ||
    Array.isArray(incomingValue)
  ) {
    return normalizedExisting;
  }
  return normalizer({
    ...normalizedExisting,
    ...incomingValue,
  });
}

function mergeSourceProvenanceEntries(
  existingEntries = [],
  incomingEntries = [],
) {
  const seenKeys = new Set();
  return normalizeSourceProvenanceEntries([
    ...(Array.isArray(existingEntries) ?
      existingEntries
    : []),
    ...(Array.isArray(incomingEntries) ?
      incomingEntries
    : []),
  ]).filter((entry) => {
    const dedupeKey = [
      normalizeOptionalText(entry?.sourceKey)
        .toLowerCase(),
      normalizeOptionalText(
        entry?.externalId,
      ).toLowerCase(),
      normalizeOptionalText(entry?.sourceUrl)
        .toLowerCase(),
      normalizeOptionalText(entry?.citation)
        .toLowerCase(),
    ].join("::");
    if (seenKeys.has(dedupeKey)) {
      return false;
    }
    seenKeys.add(dedupeKey);
    return true;
  });
}

function buildMergedCropProfilePatch({
  productName,
  existingProfile = null,
  profileDetails = {},
  lifecycle = null,
}) {
  const existingLifecycleReady =
    isLifecycleReadyProfile(existingProfile);
  const resolvedProductName =
    resolvePreferredTextValue({
      incoming: productName,
      fallback: existingProfile?.productName,
    });
  const resolvedScientificName =
    resolvePreferredTextValue({
      incoming: profileDetails?.scientificName,
      fallback:
        existingProfile?.scientificName,
    });
  const resolvedFamily =
    resolvePreferredTextValue({
      incoming: profileDetails?.family,
      fallback: existingProfile?.family,
    });
  const resolvedCategory =
    resolvePreferredTextValue({
      incoming: profileDetails?.category,
      fallback: existingProfile?.category,
    });
  const resolvedSummary =
    resolvePreferredTextValue({
      incoming: profileDetails?.summary,
      fallback: existingProfile?.summary,
    }) ||
    buildProfileSummary({
      productName: resolvedProductName,
      category: resolvedCategory,
      scientificName:
        resolvedScientificName,
      family: resolvedFamily,
    });
  const requestedLifecycleStatus =
    hasOwnField(
      profileDetails,
      "lifecycleStatus",
    ) ?
      profileDetails.lifecycleStatus
    : existingProfile?.lifecycleStatus;
  const resolvedLifecycleStatus =
    lifecycle ?
      requestedLifecycleStatus ||
      "verified"
    : existingLifecycleReady ?
      existingProfile?.lifecycleStatus ||
      "verified"
    : requestedLifecycleStatus ||
      existingProfile?.lifecycleStatus ||
      "missing";
  const requestedVerificationStatus =
    hasOwnField(
      profileDetails,
      "verificationStatus",
    ) ?
      profileDetails.verificationStatus
    : existingProfile?.verificationStatus;

  return buildStoredCropProfilePatch({
    productName: resolvedProductName,
    profileKind:
      hasOwnField(profileDetails, "profileKind") ?
        profileDetails.profileKind
      : existingProfile?.profileKind,
    category: resolvedCategory,
    variety: resolvePreferredTextValue({
      incoming: profileDetails?.variety,
      fallback: existingProfile?.variety,
    }),
    plantType: resolvePreferredTextValue({
      incoming: profileDetails?.plantType,
      fallback: existingProfile?.plantType,
    }),
    summary: resolvedSummary,
    scientificName: resolvedScientificName,
    family: resolvedFamily,
    climate: mergeNormalizedDetailObject({
      existingValue:
        existingProfile?.climate,
      incomingValue:
        profileDetails?.climate,
      normalizer:
        normalizeClimateDetails,
    }),
    soil: mergeNormalizedDetailObject({
      existingValue: existingProfile?.soil,
      incomingValue: profileDetails?.soil,
      normalizer: normalizeSoilDetails,
    }),
    water: mergeNormalizedDetailObject({
      existingValue:
        existingProfile?.water,
      incomingValue:
        profileDetails?.water,
      normalizer: normalizeWaterDetails,
    }),
    propagation:
      mergeNormalizedDetailObject({
        existingValue:
          existingProfile?.propagation,
        incomingValue:
          profileDetails?.propagation,
        normalizer:
          normalizePropagationDetails,
      }),
    harvestWindow:
      mergeNormalizedDetailObject({
        existingValue:
          existingProfile?.harvestWindow,
        incomingValue:
          profileDetails?.harvestWindow,
        normalizer:
          normalizeHarvestWindowDetails,
      }),
    verificationStatus:
      requestedVerificationStatus,
    lifecycleStatus:
      resolvedLifecycleStatus,
    sourceProvenance:
      mergeSourceProvenanceEntries(
        existingProfile?.sourceProvenance,
        profileDetails?.sourceProvenance,
      ),
  });
}

function normalizeLifecycleProfileShape(profile) {
  const minDays = Math.max(
    1,
    Math.floor(Number(profile?.minDays || 0)),
  );
  const maxDays = Math.max(
    minDays,
    Math.floor(Number(profile?.maxDays || 0)),
  );
  const phases = Array.from(
    new Set(
      (Array.isArray(profile?.phases) ? profile.phases : [])
        .map((entry) => normalizePhaseName(entry))
        .filter(Boolean),
    ),
  );
  if (minDays < 1 || maxDays < minDays || phases.length === 0) {
    throw buildPlannerValidationError({
      message:
        "Lifecycle resolver returned an invalid lifecycle profile.",
      errorCode:
        "PRODUCTION_AI_PLANNER_V2_LIFECYCLE_INVALID",
      resolutionHint:
        "Ensure lifecycle resolution returns minDays, maxDays, and canonical phases.",
      details: {
        minDays,
        maxDays,
        phases,
      },
    });
  }
  return {
    product: (profile?.product || "").toString().trim(),
    minDays,
    maxDays,
    phases,
  };
}

function resolveStoredLifecycleSource(profile) {
  const storedSource = (profile?.source || "")
    .toString()
    .trim();
  if (storedSource === "agriculture_api") {
    return "verified_store";
  }
  if (storedSource === "catalog") {
    return "catalog";
  }
  if (storedSource === "ai_estimate") {
    return "ai_estimate";
  }
  return "cache";
}

async function resolveLocalPlannerCatalogLifecycleProfile({
  businessId,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
}) {
  const localItem =
    findLocalPlannerCropCatalogItem({
      productName,
      cropSubtype,
    });
  if (!localItem) {
    return null;
  }

  const minDays =
    Number(localItem.minDays || 0) || 0;
  const maxDays =
    Number(localItem.maxDays || 0) || 0;
  const phases =
    Array.isArray(localItem.phases) ?
      localItem.phases
        .map((entry) =>
          normalizePhaseName(entry),
        )
        .filter(Boolean)
    : [];
  if (
    minDays < 1 ||
    maxDays < minDays ||
    phases.length === 0
  ) {
    return null;
  }

  const lifecycle =
    normalizeLifecycleProfileShape({
      product:
        localItem.name ||
        productName ||
        cropSubtype,
      minDays,
      maxDays,
      phases,
    });
  if (
    lifecycle.minDays < 1 ||
    lifecycle.maxDays < 1 ||
    lifecycle.phases.length === 0
  ) {
    return null;
  }

  const normalizedProductName =
    (productName || "").toString().trim();
  const normalizedCropSubtype =
    (cropSubtype || "").toString().trim();
  const productKey =
    normalizeLifecycleCatalogKey(
      normalizedCropSubtype ||
        normalizedProductName ||
        localItem.cropKey ||
        localItem.name,
    );

  clearNegativeLifecycleCache({
    businessId,
    productKey,
    cropSubtype: normalizedCropSubtype,
    domainContext,
  });

  await persistLifecycleProfile({
    businessId,
    productKey,
    productName:
      lifecycle.product ||
      normalizedProductName ||
      localItem.name,
    cropSubtype: normalizedCropSubtype,
    domainContext,
    lifecycle,
    source: "catalog",
    sourceConfidence: 1,
    metadata: {
      sourceType: "planner_catalog",
    },
    aliases: Array.isArray(localItem.aliases) ?
      localItem.aliases
    : [],
    profileDetails:
      buildStoredCropProfilePatch({
        productName:
          lifecycle.product ||
          normalizedProductName ||
          localItem.name,
        profileKind:
          localItem.profileKind || "crop",
        category:
          localItem.category || "",
        variety:
          localItem.variety || "",
        plantType:
          localItem.plantType || "",
        summary:
          localItem.summary || "",
        scientificName:
          localItem.scientificName || "",
        family:
          localItem.family || "",
        climate:
          localItem.climate || {},
        soil: localItem.soil || {},
        water: localItem.water || {},
        propagation:
          localItem.propagation || {},
        harvestWindow:
          localItem.harvestWindow || {},
        verificationStatus:
          localItem.verificationStatus ||
          "manual_verified",
        lifecycleStatus: "verified",
        sourceProvenance:
          Array.isArray(
            localItem.sourceProvenance,
          ) ?
            localItem.sourceProvenance
          : [],
      }),
  });

  return {
    lifecycle,
    lifecycleSource: "planner_catalog",
  };
}

function scoreStoredLifecycleProfileSearch({
  profile,
  normalizedQuery,
}) {
  if (!normalizedQuery) {
    return 1;
  }

  const candidates = [
    profile?.productName,
    profile?.productKey,
    ...(Array.isArray(profile?.aliases) ? profile.aliases : []),
  ]
    .map(normalizeLifecycleCatalogKey)
    .filter(Boolean);
  let score = 0;

  for (const candidate of candidates) {
    if (candidate === normalizedQuery) {
      score = Math.max(score, 220);
      continue;
    }
    if (candidate.startsWith(normalizedQuery)) {
      score = Math.max(score, 150);
      continue;
    }
    if (` ${candidate} `.includes(` ${normalizedQuery} `)) {
      score = Math.max(score, 115);
      continue;
    }
    if (candidate.includes(normalizedQuery)) {
      score = Math.max(score, 80);
    }
  }

  return score;
}

async function findStoredLifecycleProfile({
  businessId,
  productKey,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  source = null,
}) {
  if (!(await resolveLifecycleCacheCollectionAvailability())) {
    return null;
  }

  const query = {
    businessId,
    productKey,
    cropSubtype: (cropSubtype || "").toString().trim(),
    domainContext:
      domainContext || DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  };
  if (source) {
    query.source = source;
  }

  return ProductionLifecycleProfile.findOne(query)
    .sort({ resolvedAt: -1 })
    .lean();
}

async function searchStoredLifecycleProfiles({
  businessId,
  query,
  limit = 8,
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
}) {
  const trimmedQuery = (query || "")
    .toString()
    .trim();
  const normalizedQuery =
    normalizeLifecycleCatalogKey(trimmedQuery);
  const safeLimit = Math.min(
    20,
    Math.max(
      1,
      Math.floor(Number(limit) || 8),
    ),
  );
  if (!(await resolveLifecycleCacheCollectionAvailability())) {
    return [];
  }

  const rawRegex = new RegExp(
    escapeRegexPattern(trimmedQuery),
    "i",
  );
  const normalizedRegex = new RegExp(
    escapeRegexPattern(normalizedQuery),
    "i",
  );
  const profiles = await ProductionLifecycleProfile.find({
    businessId,
    domainContext:
      domainContext || DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
    lifecycleStatus: "verified",
    verificationStatus: {
      $in: [
        "source_verified",
        "manual_verified",
      ],
    },
    $or: [
      { productName: rawRegex },
      { productKey: normalizedRegex },
      { aliases: rawRegex },
      { aliases: normalizedRegex },
    ],
  })
    .sort({ resolvedAt: -1, updatedAt: -1 })
    .limit(Math.max(safeLimit * 4, safeLimit))
    .lean();

  const seenKeys = new Set();
  return profiles
    .map((profile) => ({
      profile,
      score: scoreStoredLifecycleProfileSearch({
        profile,
        normalizedQuery,
      }),
    }))
    .filter(
      (entry) =>
        entry.score > 0 &&
        isLifecycleReadyProfile(
          entry.profile,
        ),
    )
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      return (left.profile?.productName || "")
        .toString()
        .localeCompare(
          (right.profile?.productName || "")
            .toString(),
        );
    })
    .map(({ profile }) => ({
      cropKey:
        (profile?.productKey || "").toString().trim(),
      name:
        (profile?.productName || "").toString().trim(),
      aliases: buildLifecycleAliasCandidates({
        productName: profile?.productName,
        productKey: profile?.productKey,
        cropSubtype: profile?.cropSubtype,
        lifecycle: {
          product: profile?.productName,
        },
        metadata:
          (
            profile?.metadata &&
            typeof profile.metadata === "object"
          ) ?
            profile.metadata
          : {},
        aliases: profile?.aliases,
      }),
      source: "verified_store",
      minDays:
        Number(profile?.minDays || 0) || 0,
      maxDays:
        Number(profile?.maxDays || 0) || 0,
      phases: Array.isArray(profile?.phases) ?
        profile.phases
      : [],
      profileKind:
        normalizeProfileKind(
          profile?.profileKind,
        ),
      category:
        normalizeOptionalText(
          profile?.category,
        ),
      variety:
        normalizeOptionalText(
          profile?.variety,
        ),
      plantType:
        normalizeOptionalText(
          profile?.plantType,
        ),
      summary:
        normalizeOptionalText(
          profile?.summary,
        ) ||
        buildProfileSummary({
          productName:
            profile?.productName,
          category:
            profile?.category,
          scientificName:
            profile?.scientificName,
          family: profile?.family,
        }),
      scientificName:
        normalizeOptionalText(
          profile?.scientificName,
        ),
      family:
        normalizeOptionalText(
          profile?.family,
        ),
      verificationStatus:
        normalizeVerificationStatus(
          profile?.verificationStatus,
        ),
      climate:
        normalizeClimateDetails(
          profile?.climate,
        ),
      soil:
        normalizeSoilDetails(
          profile?.soil,
        ),
      water:
        normalizeWaterDetails(
          profile?.water,
        ),
      propagation:
        normalizePropagationDetails(
          profile?.propagation,
        ),
      harvestWindow:
        normalizeHarvestWindowDetails(
          profile?.harvestWindow,
        ),
      sourceProvenance:
        normalizeSourceProvenanceEntries(
          profile?.sourceProvenance,
        ),
    }))
    .filter((item) => {
      const displayKey = [
        normalizeLifecycleCatalogKey(item.name),
        normalizeLifecycleCatalogKey(item.cropKey),
      ].join("::");
      if (!displayKey) {
        return false;
      }
      if (seenKeys.has(displayKey)) {
        return false;
      }
      seenKeys.add(displayKey);
      return true;
    })
    .slice(0, safeLimit);
}

async function persistVerifiedAgricultureLifecycleProfile({
  businessId,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  lifecycle,
  metadata = {},
  aliases = [],
  profileKind = "crop",
  category = "",
  variety = "",
  plantType = "",
  summary = "",
  scientificName = "",
  family = "",
  climate = {},
  soil = {},
  water = {},
  propagation = {},
  harvestWindow = {},
  sourceProvenance = [],
}) {
  const normalizedProductName =
    (productName || "").toString().trim();
  const normalizedCropSubtype =
    (cropSubtype || "").toString().trim();
  const normalizedLifecycle =
    normalizeLifecycleProfileShape(lifecycle);
  const productKey = normalizeLifecycleCatalogKey(
    normalizedCropSubtype ||
      normalizedProductName ||
      normalizedLifecycle.product,
  );
  if (!productKey) {
    return normalizedLifecycle;
  }

  await persistLifecycleProfile({
    businessId,
    productKey,
    productName:
      normalizedLifecycle.product ||
      normalizedProductName ||
      productKey,
    cropSubtype: normalizedCropSubtype,
    domainContext,
    lifecycle: normalizedLifecycle,
    source: "agriculture_api",
    sourceConfidence: 0.9,
    metadata: {
      sourceType:
        metadata?.sourceType ||
        "agriculture_api",
      ...metadata,
    },
    aliases: buildLifecycleAliasCandidates({
      productName:
        normalizedProductName ||
        normalizedLifecycle.product,
      productKey,
      cropSubtype: normalizedCropSubtype,
      lifecycle: normalizedLifecycle,
      metadata,
      aliases,
    }),
    profileDetails:
      buildStoredCropProfilePatch({
        productName:
          normalizedLifecycle.product ||
          normalizedProductName,
        profileKind,
        category,
        variety,
        plantType,
        summary:
          summary ||
          buildProfileSummary({
            productName:
              normalizedLifecycle.product ||
              normalizedProductName,
            category,
            scientificName:
              scientificName ||
              metadata?.scientificName,
            family:
              family ||
              metadata?.family,
          }),
        scientificName:
          scientificName ||
          metadata?.scientificName,
        family:
          family || metadata?.family,
        climate: {
          ...climate,
          temperatureMinC:
            climate?.temperatureMinC ??
            metadata?.minimumTemperatureC,
          temperatureMaxC:
            climate?.temperatureMaxC ??
            metadata?.maximumTemperatureC,
          rainfallMinMm:
            climate?.rainfallMinMm ??
            metadata?.minimumPrecipitationMm,
          rainfallMaxMm:
            climate?.rainfallMaxMm ??
            metadata?.maximumPrecipitationMm,
        },
        soil: {
          ...soil,
          phMin:
            soil?.phMin ??
            metadata?.phMinimum,
          phMax:
            soil?.phMax ??
            metadata?.phMaximum,
        },
        water: {
          ...water,
          minimumPrecipitationMm:
            water?.minimumPrecipitationMm ??
            metadata?.minimumPrecipitationMm,
          maximumPrecipitationMm:
            water?.maximumPrecipitationMm ??
            metadata?.maximumPrecipitationMm,
        },
        propagation,
        harvestWindow: {
          ...harvestWindow,
          earliestDays:
            harvestWindow?.earliestDays ??
            normalizedLifecycle.minDays,
          latestDays:
            harvestWindow?.latestDays ??
            normalizedLifecycle.maxDays,
        },
        verificationStatus:
          "source_verified",
        lifecycleStatus: "verified",
        sourceProvenance: [
          ...sourceProvenance,
          {
            sourceKey:
              metadata?.providerKey ||
              metadata?.lifecycleSource ||
              "agriculture_api",
            sourceLabel:
              metadata?.providerKey ||
              metadata?.lifecycleSource ||
              "Agriculture API",
            authority:
              metadata?.providerKey ===
              "trefle" ?
                "Trefle"
              : metadata?.providerKey ===
                  "geoglam" ?
                  "GEOGLAM"
                : "Agriculture API",
            sourceUrl:
              metadata?.sourceUrl || "",
            citation:
              metadata?.citation || "",
            license:
              metadata?.license || "",
            externalId:
              normalizeOptionalText(
                metadata?.trefleSpeciesId,
              ) ||
              normalizeOptionalText(
                metadata?.trefleSlug,
              ),
            confidence: 0.9,
            verificationStatus:
              "source_verified",
            fetchedAt: new Date(),
            notes:
              "Imported from external agriculture provider.",
          },
        ],
      }),
  });

  clearNegativeLifecycleCache({
    businessId,
    productKey,
    cropSubtype: normalizedCropSubtype,
    domainContext,
  });
  return normalizedLifecycle;
}

async function resolveVerifiedAgricultureLifecycle({
  businessId,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  context = {},
  aliases = [],
}) {
  const normalizedProductName =
    (productName || "").toString().trim();
  const normalizedCropSubtype =
    (cropSubtype || "").toString().trim();
  const productKey = normalizeLifecycleCatalogKey(
    normalizedCropSubtype || normalizedProductName,
  );

  const stored =
    await findStoredLifecycleProfile({
      businessId,
      productKey,
      cropSubtype: normalizedCropSubtype,
      domainContext,
    });
  if (stored && isLifecycleReadyProfile(stored)) {
    clearNegativeLifecycleCache({
      businessId,
      productKey,
      cropSubtype: normalizedCropSubtype,
      domainContext,
    });
    return {
      lifecycle: normalizeLifecycleProfileShape({
        product: stored.productName,
        minDays: stored.minDays,
        maxDays: stored.maxDays,
        phases: stored.phases,
      }),
      lifecycleSource:
        resolveStoredLifecycleSource(stored),
    };
  }

  const searchQuery = [
    normalizedProductName,
    normalizedCropSubtype,
  ]
    .filter(Boolean)
    .join(" ")
    .trim();
  if (!searchQuery) {
    return null;
  }
  const storedMatches =
    await searchStoredLifecycleProfiles({
      businessId,
      query: searchQuery,
      limit: 5,
      domainContext,
    });
  const matchedStored =
    storedMatches.find((profile) => {
      const normalizedName =
        normalizeLifecycleCatalogKey(
          profile?.name,
        );
      const normalizedCropKey =
        normalizeLifecycleCatalogKey(
          profile?.cropKey,
        );
      return (
        normalizedName ===
          normalizeLifecycleCatalogKey(
            normalizedProductName,
          ) ||
        normalizedCropKey === productKey
      );
    }) || storedMatches[0] || null;
  if (!matchedStored) {
    return null;
  }
  clearNegativeLifecycleCache({
    businessId,
    productKey,
    cropSubtype: normalizedCropSubtype,
    domainContext,
  });
  return {
    lifecycle: normalizeLifecycleProfileShape({
      product: matchedStored.name,
      minDays: matchedStored.minDays,
      maxDays: matchedStored.maxDays,
      phases: matchedStored.phases,
    }),
    lifecycleSource:
      (matchedStored.source || "verified_store")
        .toString()
        .trim() || "verified_store",
  };
}

async function upsertStoredCropProfile({
  businessId,
  productKey,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  lifecycle = null,
  source = "source_import",
  sourceConfidence = 1,
  metadata = {},
  aliases = [],
  profileDetails = {},
  preserveVerifiedLifecycle = true,
}) {
  if (lifecycleCachePersistenceDisabled) {
    return null;
  }

  const normalizedCropSubtype =
    normalizeOptionalText(cropSubtype);
  const normalizedLifecycle =
    lifecycle ?
      normalizeLifecycleProfileShape(lifecycle)
    : null;
  const normalizedProductKey =
    normalizeLifecycleCatalogKey(
      productKey ||
        normalizedCropSubtype ||
        productName ||
        normalizedLifecycle?.product,
    );
  const normalizedProductName =
    resolvePreferredTextValue({
      incoming:
        productName ||
        normalizedLifecycle?.product,
      fallback: normalizedProductKey,
    });
  if (!normalizedProductKey) {
    return null;
  }

  const scopeQuery = {
    businessId,
    productKey: normalizedProductKey,
    cropSubtype: normalizedCropSubtype,
    domainContext:
      domainContext ||
      DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  };

  try {
    const existing =
      await ProductionLifecycleProfile.findOne(
        scopeQuery,
      ).lean();
    const existingLifecycleReady =
      isLifecycleReadyProfile(existing);
    const mergedProfileDetails =
      buildMergedCropProfilePatch({
        productName: normalizedProductName,
        existingProfile: existing,
        profileDetails,
        lifecycle: normalizedLifecycle,
      });
    const mergedMetadata =
      (
        existing?.metadata &&
        typeof existing.metadata === "object"
      ) ?
        {
          ...existing.metadata,
          ...metadata,
        }
      : {
          ...metadata,
        };

    const mergedAliases =
      buildLifecycleAliasCandidates({
        productName: normalizedProductName,
        productKey:
          normalizedProductKey,
        cropSubtype:
          normalizedCropSubtype,
        lifecycle:
          normalizedLifecycle || {
            product:
              normalizedProductName,
          },
        metadata: mergedMetadata,
        aliases: normalizeLifecycleAliases([
          ...(Array.isArray(existing?.aliases) ?
            existing.aliases
          : []),
          ...(Array.isArray(aliases) ?
            aliases
          : []),
        ]),
      });

    let resolvedSource = source;
    let resolvedSourceConfidence =
      sourceConfidence;
    let resolvedMinDays = null;
    let resolvedMaxDays = null;
    let resolvedPhases = [];
    let resolvedLastVerifiedAt = null;

    if (normalizedLifecycle) {
      resolvedMinDays =
        normalizedLifecycle.minDays;
      resolvedMaxDays =
        normalizedLifecycle.maxDays;
      resolvedPhases =
        normalizedLifecycle.phases;
      resolvedLastVerifiedAt =
        source === "agriculture_api" ||
        mergedProfileDetails.verificationStatus ===
          "source_verified" ||
        mergedProfileDetails.verificationStatus ===
          "manual_verified" ?
          new Date()
        : existing?.lastVerifiedAt || null;
    } else if (
      preserveVerifiedLifecycle &&
      existingLifecycleReady
    ) {
      resolvedSource =
        existing?.source || source;
      resolvedSourceConfidence =
        Number(
          existing?.sourceConfidence,
        ) || sourceConfidence;
      resolvedMinDays =
        Number(existing?.minDays) || null;
      resolvedMaxDays =
        Number(existing?.maxDays) || null;
      resolvedPhases =
        Array.isArray(existing?.phases) ?
          existing.phases
        : [];
      resolvedLastVerifiedAt =
        existing?.lastVerifiedAt || null;
    } else {
      resolvedSource =
        source === "manifest_seed" &&
        existing?.source ?
          existing.source
        : source;
      resolvedSourceConfidence =
        source === "manifest_seed" &&
        Number(existing?.sourceConfidence) > 0 ?
          Number(existing.sourceConfidence)
        : sourceConfidence;
      resolvedMinDays = null;
      resolvedMaxDays = null;
      resolvedPhases = [];
      resolvedLastVerifiedAt =
        existing?.lastVerifiedAt || null;
    }

    await ProductionLifecycleProfile.findOneAndUpdate(
      scopeQuery,
      {
        $set: {
          productName:
            normalizedProductName,
          aliases: mergedAliases,
          profileKind:
            mergedProfileDetails.profileKind,
          category:
            mergedProfileDetails.category,
          variety:
            mergedProfileDetails.variety,
          plantType:
            mergedProfileDetails.plantType,
          summary:
            mergedProfileDetails.summary,
          scientificName:
            mergedProfileDetails.scientificName,
          family:
            mergedProfileDetails.family,
          climate:
            mergedProfileDetails.climate,
          soil:
            mergedProfileDetails.soil,
          water:
            mergedProfileDetails.water,
          propagation:
            mergedProfileDetails.propagation,
          harvestWindow:
            mergedProfileDetails.harvestWindow,
          minDays: resolvedMinDays,
          maxDays: resolvedMaxDays,
          phases: resolvedPhases,
          lifecycleStatus:
            mergedProfileDetails.lifecycleStatus,
          source: resolvedSource,
          sourceConfidence:
            resolvedSourceConfidence,
          verificationStatus:
            mergedProfileDetails.verificationStatus,
          sourceProvenance:
            mergedProfileDetails.sourceProvenance,
          metadata: mergedMetadata,
          lastVerifiedAt:
            resolvedLastVerifiedAt,
          resolvedAt: new Date(),
        },
      },
      {
        upsert: true,
        new: true,
        setDefaultsOnInsert: true,
      },
    );
    lifecycleCacheCollectionAvailability = true;
    return {
      productKey: normalizedProductKey,
      productName: normalizedProductName,
      lifecycleReady:
        normalizedLifecycle ?
          true
        : existingLifecycleReady,
    };
  } catch (error) {
    if (isCollectionLimitError(error)) {
      lifecycleCachePersistenceDisabled = true;
      lifecycleCacheCollectionAvailability = false;
    }
    debug(
      "PLANNER_V2_LIFECYCLE: crop profile upsert skipped",
      {
        intent:
          "planner should continue even when crop profile persistence is unavailable",
        businessId:
          businessId?.toString?.() || null,
        productKey:
          normalizedProductKey,
        source,
        cacheDisabled:
          lifecycleCachePersistenceDisabled,
        reason:
          error?.message ||
          "unknown_crop_profile_upsert_error",
      },
    );
    return null;
  }
}

async function persistCropProfileSeedEntry({
  businessId,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  aliases = [],
  metadata = {},
  profileDetails = {},
}) {
  return upsertStoredCropProfile({
    businessId,
    productName,
    cropSubtype,
    domainContext,
    source: "manifest_seed",
    sourceConfidence: 0.4,
    metadata,
    aliases,
    profileDetails: {
      ...profileDetails,
      verificationStatus:
        profileDetails?.verificationStatus ||
        "seed_manifest",
      lifecycleStatus:
        profileDetails?.lifecycleStatus ||
        "missing",
    },
    preserveVerifiedLifecycle: true,
  });
}

async function persistImportedCropProfile({
  businessId,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  lifecycle = null,
  source = "source_import",
  sourceConfidence = 0.85,
  metadata = {},
  aliases = [],
  profileDetails = {},
}) {
  return upsertStoredCropProfile({
    businessId,
    productName,
    cropSubtype,
    domainContext,
    lifecycle,
    source,
    sourceConfidence,
    metadata,
    aliases,
    profileDetails,
    preserveVerifiedLifecycle: true,
  });
}

async function persistLifecycleProfile({
  businessId,
  productKey,
  productName,
  cropSubtype,
  domainContext,
  lifecycle,
  source,
  sourceConfidence = 1,
  metadata = {},
  aliases = [],
  profileDetails = {},
}) {
  return upsertStoredCropProfile({
    businessId,
    productKey,
    productName,
    cropSubtype,
    domainContext,
    lifecycle,
    source,
    sourceConfidence,
    metadata,
    aliases,
    profileDetails,
    preserveVerifiedLifecycle: false,
  });
}

async function resolveLifecycleProfile({
  businessId,
  productName,
  cropSubtype = "",
  domainContext = DEFAULT_PRODUCTION_DOMAIN_CONTEXT,
  productDescription = "",
  useReasoning = false,
  context = {},
}) {
  const normalizedProductName =
    (productName || "").toString().trim();
  const normalizedCropSubtype =
    (cropSubtype || "").toString().trim();
  const productKey = normalizeLifecycleCatalogKey(
    normalizedCropSubtype || normalizedProductName,
  );

  debug(
    "PLANNER_V2_LIFECYCLE: start",
    {
      intent:
        "resolve biological lifecycle before AI phase/task planning",
      businessId: businessId?.toString?.() || null,
      productKey,
      productName: normalizedProductName,
      cropSubtype: normalizedCropSubtype,
      domainContext,
    },
  );

  const cached =
    await findStoredLifecycleProfile({
      businessId,
      productKey,
      cropSubtype: normalizedCropSubtype,
      domainContext,
    });
  if (cached) {
    if (!isLifecycleReadyProfile(cached)) {
      debug(
        "PLANNER_V2_LIFECYCLE: stored profile skipped",
        {
          intent:
            "ignore crop profile rows that do not yet contain verified lifecycle bounds",
          businessId:
            businessId?.toString?.() || null,
          productKey,
          cropSubtype:
            normalizedCropSubtype,
          domainContext,
          verificationStatus:
            cached?.verificationStatus ||
            null,
          lifecycleStatus:
            cached?.lifecycleStatus ||
            null,
        },
      );
    } else {
    clearNegativeLifecycleCache({
      businessId,
      productKey,
      cropSubtype: normalizedCropSubtype,
      domainContext,
    });
    return {
      lifecycle: normalizeLifecycleProfileShape({
        product: cached.productName,
        minDays: cached.minDays,
        maxDays: cached.maxDays,
        phases: cached.phases,
      }),
      lifecycleSource:
        resolveStoredLifecycleSource(cached),
    };
    }
  }

  const searchQuery = [
    normalizedProductName,
    normalizedCropSubtype,
  ]
    .filter(Boolean)
    .join(" ")
    .trim();
  const storedMatches =
    await searchStoredLifecycleProfiles({
      businessId,
      query: searchQuery,
      limit: 5,
      domainContext,
    });
  const matchedStored =
    storedMatches.find((profile) => {
      const normalizedName =
        normalizeLifecycleCatalogKey(
          profile?.name,
        );
      const normalizedCropKey =
        normalizeLifecycleCatalogKey(
          profile?.cropKey,
        );
      return (
        normalizedName ===
          normalizeLifecycleCatalogKey(
            normalizedProductName,
          ) ||
        normalizedCropKey === productKey
      );
    }) || storedMatches[0] || null;
  if (matchedStored) {
    clearNegativeLifecycleCache({
      businessId,
      productKey,
      cropSubtype: normalizedCropSubtype,
      domainContext,
    });
    return {
      lifecycle: normalizeLifecycleProfileShape({
        product: matchedStored.name,
        minDays: matchedStored.minDays,
        maxDays: matchedStored.maxDays,
        phases: matchedStored.phases,
      }),
      lifecycleSource:
        (matchedStored.source || "verified_store")
          .toString()
          .trim() || "verified_store",
    };
  }

  throw buildPlannerValidationError({
    message:
      "Product lifecycle data is unavailable for this farm product.",
    errorCode:
      "PRODUCTION_AI_PLANNER_V2_LIFECYCLE_UNAVAILABLE",
    resolutionHint:
      "Use a crop with verified lifecycle store coverage or seed the crop database with verified lifecycle records before generating the plan.",
    details: {
      productName: normalizedProductName,
      cropSubtype: normalizedCropSubtype,
      domainContext,
      lifecycleSourcesChecked: [
        "verified_store",
      ],
      hasProductDescription: Boolean(
        (productDescription || "").toString().trim(),
      ),
    },
    retryAllowed: false,
    retryReason: "missing_lifecycle_data",
    classification: "MISSING_REQUIRED_FIELD",
    statusCode: 422,
  });
}

module.exports = {
  resolveLifecycleProfile,
  searchStoredLifecycleProfiles,
  persistVerifiedAgricultureLifecycleProfile,
  persistCropProfileSeedEntry,
  persistImportedCropProfile,
  resolveVerifiedAgricultureLifecycle,
  upsertStoredCropProfile,
  buildStoredCropProfilePatch,
  normalizeProfileKind,
  normalizeVerificationStatus,
  normalizeLifecycleStatus,
  normalizeClimateDetails,
  normalizeSoilDetails,
  normalizeWaterDetails,
  normalizePropagationDetails,
  normalizeHarvestWindowDetails,
  normalizeSourceProvenanceEntries,
  isLifecycleReadyProfile,
};
