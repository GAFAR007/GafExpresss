/**
 * apps/backend/services/planner/lifecycleCatalog.js
 * ------------------------------------------------
 * WHAT:
 * - Local lifecycle catalog for planner V2 farm products.
 *
 * WHY:
 * - Local biological defaults are the safest first resolver for common crops.
 * - Catalog data avoids unnecessary API/AI calls for known lifecycle patterns.
 *
 * HOW:
 * - Maps normalized crop keys and aliases to lifecycle definitions.
 * - Exposes a lookup helper that returns a cloned lifecycle profile.
 */

const LIFECYCLE_CATALOG = Object.freeze({
  corn: Object.freeze({
    product: "Corn",
    minDays: 90,
    maxDays: 120,
    aliases: ["corn", "maize", "sweet corn"],
    phases: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
  }),
  beans: Object.freeze({
    product: "Beans",
    minDays: 60,
    maxDays: 90,
    aliases: ["bean", "beans", "cowpea", "soybean"],
    phases: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "pod_development",
      "harvest",
    ],
  }),
  pepper: Object.freeze({
    product: "Pepper",
    minDays: 90,
    maxDays: 150,
    aliases: [
      "pepper",
      "peppers",
      "bell pepper",
      "bell peppers",
      "chili pepper",
      "chili peppers",
      "capsicum",
    ],
    phases: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "fruit_development",
      "harvest",
    ],
  }),
  rice: Object.freeze({
    product: "Rice",
    minDays: 90,
    maxDays: 150,
    aliases: ["rice", "paddy"],
    phases: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
  }),
  cassava: Object.freeze({
    product: "Cassava",
    minDays: 240,
    maxDays: 360,
    aliases: ["cassava", "manioc", "yuca"],
    phases: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "grain_fill",
      "harvest",
    ],
  }),
});

function normalizeLifecycleCatalogKey(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function cloneLifecycleDefinition(definition) {
  return {
    product: definition.product,
    minDays: Number(definition.minDays || 0),
    maxDays: Number(definition.maxDays || 0),
    phases: [...(definition.phases || [])],
  };
}

function matchesLifecycleAlias({
  candidate,
  alias,
}) {
  if (!candidate || !alias) {
    return false;
  }
  if (candidate === alias || alias === candidate) {
    return true;
  }
  const paddedCandidate = ` ${candidate} `;
  const paddedAlias = ` ${alias} `;
  return (
    paddedCandidate.includes(` ${alias} `) ||
    paddedAlias.includes(` ${candidate} `)
  );
}

function findCatalogLifecycleProfile({
  productName,
  cropSubtype,
}) {
  const candidates = [
    cropSubtype,
    productName,
  ]
    .map(normalizeLifecycleCatalogKey)
    .filter(Boolean);

  for (const candidate of candidates) {
    for (const definition of Object.values(LIFECYCLE_CATALOG)) {
      const aliases = [
        definition.product,
        ...(definition.aliases || []),
      ].map(normalizeLifecycleCatalogKey);
      if (
        aliases.some((alias) =>
          matchesLifecycleAlias({
            candidate,
            alias,
          }),
        )
      ) {
        return cloneLifecycleDefinition(definition);
      }
    }
  }

  return null;
}

module.exports = {
  LIFECYCLE_CATALOG,
  normalizeLifecycleCatalogKey,
  findCatalogLifecycleProfile,
  matchesLifecycleAlias,
};
