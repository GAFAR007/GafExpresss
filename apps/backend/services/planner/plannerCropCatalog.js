/**
 * apps/backend/services/planner/plannerCropCatalog.js
 * ---------------------------------------------------
 * WHAT:
 * - Builds an offline-first planner crop catalog for search + lifecycle lookup.
 *
 * WHY:
 * - Production setup should still work when the verified store is sparse or
 *   external agriculture providers are unavailable.
 * - Core crops/fruits/plants already exist in local bootstrap/seed datasets,
 *   so the planner can search them without waiting on runtime imports.
 *
 * HOW:
 * - Combines verified bootstrap crop profiles with the broader seed manifest.
 * - Reuses the local lifecycle catalog to fill lifecycle bounds where possible.
 * - Exposes deterministic search + lookup helpers with memoized catalog data.
 */

const {
  buildCropProfileSeedManifest,
} = require("./cropProfileSeedManifest");
const {
  buildVerifiedCropProfileBootstrap,
} = require("./verifiedCropProfileBootstrap");
const {
  findCatalogLifecycleProfile,
  normalizeLifecycleCatalogKey,
} = require("./lifecycleCatalog");

let cachedPlannerCropCatalog = null;

function normalizeOptionalText(value) {
  return (value || "").toString().trim();
}

function normalizeOptionalArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((entry) =>
      normalizeOptionalText(entry),
    )
    .filter(Boolean);
}

function normalizeLifecycle(entryLifecycle) {
  return {
    product:
      normalizeOptionalText(
        entryLifecycle?.product,
      ) || "",
    minDays:
      Number(entryLifecycle?.minDays || 0) || 0,
    maxDays:
      Number(entryLifecycle?.maxDays || 0) || 0,
    phases:
      normalizeOptionalArray(
        entryLifecycle?.phases,
      ),
  };
}

function resolveEntryLifecycle(entry) {
  const explicitLifecycle =
    entry?.lifecycle &&
    typeof entry.lifecycle === "object" ?
      normalizeLifecycle(entry.lifecycle)
    : null;
  if (
    explicitLifecycle &&
    (explicitLifecycle.minDays > 0 ||
      explicitLifecycle.maxDays > 0)
  ) {
    return explicitLifecycle;
  }

  const catalogLifecycle =
    findCatalogLifecycleProfile({
      productName: entry?.productName,
      cropSubtype: entry?.cropSubtype,
    });
  if (catalogLifecycle) {
    return normalizeLifecycle(
      catalogLifecycle,
    );
  }

  return normalizeLifecycle({
    product: entry?.productName,
  });
}

function buildCatalogItemFromEntry(
  entry,
) {
  const productName =
    normalizeOptionalText(
      entry?.productName,
    );
  const cropSubtype =
    normalizeOptionalText(
      entry?.cropSubtype,
    );
  const lifecycle =
    resolveEntryLifecycle(entry);
  const profileDetails =
    entry?.profileDetails &&
    typeof entry.profileDetails === "object" ?
      entry.profileDetails
    : {};
  const aliases = Array.from(
    new Set(
      [productName, ...(entry?.aliases || [])]
        .map((alias) =>
          normalizeOptionalText(alias),
        )
        .filter(Boolean),
    ),
  );

  return {
    cropKey:
      normalizeLifecycleCatalogKey(
        cropSubtype || productName,
      ),
    name: productName,
    displayName: productName,
    aliases,
    source: "planner_catalog",
    minDays: lifecycle.minDays,
    maxDays: lifecycle.maxDays,
    phases: lifecycle.phases,
    profileKind:
      normalizeOptionalText(
        profileDetails.profileKind,
      ) || "crop",
    category:
      normalizeOptionalText(
        profileDetails.category,
      ),
    variety:
      normalizeOptionalText(
        profileDetails.variety,
      ),
    plantType:
      normalizeOptionalText(
        profileDetails.plantType,
      ),
    summary:
      normalizeOptionalText(
        profileDetails.summary,
      ),
    scientificName:
      normalizeOptionalText(
        profileDetails.scientificName,
      ),
    family:
      normalizeOptionalText(
        profileDetails.family,
      ),
    verificationStatus:
      normalizeOptionalText(
        profileDetails.verificationStatus,
      ),
    climate:
      profileDetails.climate || {},
    soil: profileDetails.soil || {},
    water: profileDetails.water || {},
    propagation:
      profileDetails.propagation || {},
    harvestWindow:
      profileDetails.harvestWindow || {},
    sourceProvenance:
      Array.isArray(
        profileDetails.sourceProvenance,
      ) ?
        profileDetails.sourceProvenance
      : [],
  };
}

function resolveVerificationPriority(
  verificationStatus,
) {
  switch (
    normalizeOptionalText(
      verificationStatus,
    )
  ) {
    case "manual_verified":
      return 5;
    case "source_verified":
      return 4;
    case "review_required":
      return 3;
    case "source_pending":
      return 2;
    case "seed_manifest":
      return 1;
    default:
      return 0;
  }
}

function compareCatalogItems(
  left,
  right,
) {
  const leftVerification =
    resolveVerificationPriority(
      left?.verificationStatus,
    );
  const rightVerification =
    resolveVerificationPriority(
      right?.verificationStatus,
    );
  if (
    rightVerification !== leftVerification
  ) {
    return (
      rightVerification -
      leftVerification
    );
  }

  const leftLifecycle =
    Number(left?.minDays || 0) > 0 ||
    Number(left?.maxDays || 0) > 0;
  const rightLifecycle =
    Number(right?.minDays || 0) > 0 ||
    Number(right?.maxDays || 0) > 0;
  if (leftLifecycle !== rightLifecycle) {
    return rightLifecycle ? 1 : -1;
  }

  return normalizeOptionalText(
    left?.name,
  ).localeCompare(
    normalizeOptionalText(right?.name),
  );
}

function buildPlannerCropCatalog() {
  if (cachedPlannerCropCatalog) {
    return cachedPlannerCropCatalog;
  }

  const bootstrapEntries =
    buildVerifiedCropProfileBootstrap({
      domainContext: "farm",
    });
  const manifestEntries =
    buildCropProfileSeedManifest({
      domainContext: "farm",
    });

  const combinedItems = [
    ...bootstrapEntries.map(
      buildCatalogItemFromEntry,
    ),
    ...manifestEntries.map(
      buildCatalogItemFromEntry,
    ),
  ]
    .filter(
      (item) =>
        normalizeOptionalText(item.name) &&
        normalizeOptionalText(item.cropKey),
    )
    .sort(compareCatalogItems);

  const dedupedItems = [];
  const seenKeys = new Set();
  for (const item of combinedItems) {
    const dedupeKey = [
      normalizeLifecycleCatalogKey(
        item.name,
      ),
      normalizeLifecycleCatalogKey(
        item.cropKey,
      ),
    ].join("::");
    if (!dedupeKey || seenKeys.has(dedupeKey)) {
      continue;
    }
    seenKeys.add(dedupeKey);
    dedupedItems.push(item);
  }

  cachedPlannerCropCatalog = dedupedItems;
  return cachedPlannerCropCatalog;
}

function scoreCatalogItem({
  item,
  normalizedQuery,
}) {
  const verificationPriority =
    resolveVerificationPriority(
      item?.verificationStatus,
    );
  const hasLifecycle =
    Number(item?.minDays || 0) > 0 ||
    Number(item?.maxDays || 0) > 0;

  if (!normalizedQuery) {
    return (
      verificationPriority * 100 +
      (hasLifecycle ? 25 : 0)
    );
  }

  const exactCandidates = [
    item?.name,
    item?.cropKey,
    ...(item?.aliases || []),
  ].map(normalizeLifecycleCatalogKey);
  if (
    exactCandidates.includes(
      normalizedQuery,
    )
  ) {
    return (
      1000 +
      verificationPriority * 40 +
      (hasLifecycle ? 20 : 0)
    );
  }

  let score = 0;
  const nameKey =
    normalizeLifecycleCatalogKey(
      item?.name,
    );
  const cropKey =
    normalizeLifecycleCatalogKey(
      item?.cropKey,
    );
  const aliasKeys = normalizeOptionalArray(
    item?.aliases,
  ).map(normalizeLifecycleCatalogKey);
  const categoryKey =
    normalizeLifecycleCatalogKey(
      item?.category,
    );
  const varietyKey =
    normalizeLifecycleCatalogKey(
      item?.variety,
    );
  const profileKindKey =
    normalizeLifecycleCatalogKey(
      item?.profileKind,
    );
  const plantTypeKey =
    normalizeLifecycleCatalogKey(
      item?.plantType,
    );

  if (
    aliasKeys.some((alias) =>
      alias === normalizedQuery,
    )
  ) {
    return (
      560 +
      verificationPriority * 40 +
      (hasLifecycle ? 20 : 0)
    );
  }

  if (
    nameKey.startsWith(normalizedQuery) ||
    cropKey.startsWith(normalizedQuery)
  ) {
    score = Math.max(score, 720);
  }
  if (
    aliasKeys.some((alias) =>
      alias.startsWith(
        normalizedQuery,
      ),
    )
  ) {
    score = Math.max(score, 620);
  }
  if (
    nameKey.includes(normalizedQuery) ||
    cropKey.includes(normalizedQuery)
  ) {
    score = Math.max(score, 500);
  }
  if (
    aliasKeys.some((alias) =>
      alias.includes(
        normalizedQuery,
      ),
    )
  ) {
    score = Math.max(score, 420);
  }
  if (
    [
      categoryKey,
      varietyKey,
      profileKindKey,
      plantTypeKey,
    ].some((field) =>
      field.includes(
        normalizedQuery,
      ),
    )
  ) {
    score = Math.max(score, 280);
  }

  return (
    score +
    verificationPriority * 40 +
    (hasLifecycle ? 20 : 0)
  );
}

function searchLocalPlannerCropCatalog({
  query,
  limit = 8,
}) {
  const normalizedQuery =
    normalizeLifecycleCatalogKey(query);
  const safeLimit = Math.min(
    20,
    Math.max(
      1,
      Math.floor(Number(limit) || 8),
    ),
  );
  const items = buildPlannerCropCatalog();

  return items
    .map((item) => ({
      item,
      score: scoreCatalogItem({
        item,
        normalizedQuery,
      }),
    }))
    .filter(
      (entry) =>
        !normalizedQuery || entry.score > 0,
    )
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      return compareCatalogItems(
        left.item,
        right.item,
      );
    })
    .slice(0, safeLimit)
    .map((entry) => entry.item);
}

function findLocalPlannerCropCatalogItem({
  productName,
  cropSubtype = "",
}) {
  const candidates = [
    cropSubtype,
    productName,
  ]
    .map(normalizeLifecycleCatalogKey)
    .filter(Boolean);
  if (candidates.length === 0) {
    return null;
  }

  const items = buildPlannerCropCatalog();
  for (const candidate of candidates) {
    const exactMatch = items.find((item) => {
      const searchableValues = [
        item.name,
        item.cropKey,
        ...(item.aliases || []),
      ].map(normalizeLifecycleCatalogKey);
      return searchableValues.includes(
        candidate,
      );
    });
    if (exactMatch) {
      return exactMatch;
    }
  }

  for (const candidate of candidates) {
    const fuzzyMatch = items.find((item) => {
      const searchableValues = [
        item.name,
        item.cropKey,
        ...(item.aliases || []),
      ].map(normalizeLifecycleCatalogKey);
      return searchableValues.some(
        (value) =>
          value.includes(candidate) ||
          candidate.includes(value),
      );
    });
    if (fuzzyMatch) {
      return fuzzyMatch;
    }
  }

  return null;
}

module.exports = {
  buildPlannerCropCatalog,
  searchLocalPlannerCropCatalog,
  findLocalPlannerCropCatalogItem,
};
