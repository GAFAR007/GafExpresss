/**
 * apps/backend/services/planner/agricultureApiClient.js
 * -----------------------------------------------------
 * WHAT:
 * - External agriculture lifecycle provider adapter for planner V2.
 *
 * WHY:
 * - Planner V2 needs trusted lifecycle inputs for farm products that are not covered by
 *   the local catalog or lifecycle cache.
 * - GEOGLAM provides Africa crop calendar windows for staple crops.
 * - Trefle provides species-level horticulture growth metadata for crops such as tomato,
 *   pepper, onion, and banana.
 *
 * HOW:
 * - Normalizes the incoming farm product into a crop key.
 * - Tries GEOGLAM first when estate country context is present.
 * - Falls back to Trefle species search + detail lookup when a token is configured.
 * - Returns one normalized lifecycle profile plus provider metadata for cache persistence.
 */

const debug = require("../../utils/debug");
const {
  normalizeLifecycleCatalogKey,
  findCatalogLifecycleProfile,
} = require("./lifecycleCatalog");
const {
  buildCropProfileProvenanceEntry,
} = require("./cropProfileSources");

// WHY: Provider base URLs stay configurable so production can override them without code edits.
const GEOGLAM_BASE_URL = (
  process.env
    .PRODUCTION_GEOGLAM_BASE_URL ||
  "https://services8.arcgis.com/zNrTBuYXV2f35M0U/arcgis/rest/services/Sub-national_Crop_Calendars/FeatureServer/0"
)
  .trim()
  .replace(/\/+$/, "");
const TREFLE_BASE_URL = (
  process.env
    .PRODUCTION_TREFLE_BASE_URL ||
  "https://trefle.io/api/v1"
)
  .trim()
  .replace(/\/+$/, "");
const TREFLE_API_TOKEN = (
  process.env.TREFLE_API_TOKEN ||
  process.env
    .PRODUCTION_TREFLE_API_TOKEN ||
  ""
).trim();
const AGRICULTURE_API_TIMEOUT_MS =
  Number(
    process.env
      .PRODUCTION_AGRICULTURE_API_TIMEOUT_MS ||
      12000,
  ) || 12000;

// WHY: GEOGLAM uses season labels per crop family rather than free-form crop names.
const GEOGLAM_CROP_SERIES_BY_KEY =
  Object.freeze({
    beans: [
      "Beans 1",
      "Beans 2",
      "Beans 3",
    ],
    corn: ["Maize 1", "Maize 2"],
    millet: ["Millet 1"],
    rice: ["Rice 1", "Rice 2"],
    sorghum: ["Sorghum 1", "Sorghum 2"],
    teff: ["Teff 1"],
    wheat: [
      "Spring Wheat",
      "Winter Wheat",
    ],
  });

// WHY: Canonical crop aliases keep product naming flexible while provider lookups remain deterministic.
const AGRICULTURE_CROP_ALIASES =
  Object.freeze({
    banana: [
      "banana",
      "bananas",
      "plantain",
      "plantains",
    ],
    beans: [
      "bean",
      "beans",
      "cowpea",
      "soybean",
      "soybeans",
    ],
    cassava: [
      "cassava",
      "manioc",
      "yuca",
    ],
    corn: [
      "corn",
      "maize",
      "sweet corn",
    ],
    millet: ["millet", "pearl millet"],
    onion: [
      "onion",
      "onions",
      "red onion",
      "spring onion",
      "bulb onion",
    ],
    pepper: [
      "pepper",
      "peppers",
      "bell pepper",
      "bell peppers",
      "chili pepper",
      "chili peppers",
      "capsicum",
    ],
    rice: ["rice", "paddy"],
    sorghum: ["sorghum"],
    teff: ["teff"],
    tomato: ["tomato", "tomatoes"],
    wheat: [
      "wheat",
      "spring wheat",
      "winter wheat",
    ],
  });

// WHY: Provider search works best with one clean primary term per crop family.
const PRIMARY_TREFLE_QUERY_BY_KEY =
  Object.freeze({
    banana: "banana",
    beans: "bean",
    cassava: "cassava",
    corn: "maize",
    millet: "millet",
    onion: "onion",
    pepper: "pepper",
    rice: "rice",
    sorghum: "sorghum",
    teff: "teff",
    tomato: "tomato",
    wheat: "wheat",
  });

// WHY: Scientific/genus hints help reject weak substring matches from Trefle search results.
const TREFLE_SCIENTIFIC_HINTS_BY_CROP_KEY =
  Object.freeze({
    banana: ["musa"],
    beans: [
      "phaseolus",
      "vigna",
      "glycine",
    ],
    cassava: ["manihot"],
    corn: ["zea", "zea mays"],
    millet: [
      "pennisetum",
      "cenchrus",
      "eleusine",
    ],
    onion: ["allium", "allium cepa"],
    pepper: [
      "capsicum",
      "piper",
      "piper nigrum",
    ],
    rice: ["oryza", "oryza sativa"],
    sorghum: [
      "sorghum",
      "sorghum bicolor",
    ],
    teff: [
      "eragrostis",
      "eragrostis tef",
    ],
    tomato: [
      "solanum",
      "solanum lycopersicum",
    ],
    wheat: [
      "triticum",
      "triticum aestivum",
    ],
  });

// WHY: Phase templates remain local so the planner preserves one canonical lifecycle contract.
const CANONICAL_PHASES_BY_CROP_KEY =
  Object.freeze({
    banana: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "fruit_development",
      "harvest",
    ],
    beans: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "pod_development",
      "harvest",
    ],
    cassava: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "root_bulking",
      "harvest",
    ],
    corn: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
    millet: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
    onion: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "bulb_development",
      "harvest",
    ],
    pepper: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "fruit_development",
      "harvest",
    ],
    rice: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
    sorghum: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
    teff: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
    tomato: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "fruit_development",
      "harvest",
    ],
    wheat: [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "flowering",
      "grain_fill",
      "harvest",
    ],
  });

// WHY: Country aliases smooth differences between ISO codes, estate labels, and provider labels.
const COUNTRY_NAME_OVERRIDES =
  Object.freeze({
    cd: "Democratic Republic of the Congo",
    cg: "Congo",
    ci: "Cote d'Ivoire",
    ivoire: "Cote d'Ivoire",
    drc: "Democratic Republic of the Congo",
    "ivory coast": "Cote d'Ivoire",
    ke: "Kenya",
    ng: "Nigeria",
    swaziland: "eSwatini",
    sz: "eSwatini",
    tanzania:
      "United Republic of Tanzania",
    tz: "United Republic of Tanzania",
  });

function normalizeText(value) {
  return (value || "")
    .toString()
    .trim();
}

function toPositiveInteger(value) {
  const parsed = Math.floor(
    Number(value || 0),
  );
  return parsed > 0 ? parsed : null;
}

function dedupeStrings(values) {
  return Array.from(
    new Set(
      values
        .map(normalizeText)
        .filter(Boolean),
    ),
  );
}

function dedupeNormalizedLifecycleStrings(values) {
  return Array.from(
    new Set(
      values
        .map(normalizeLifecycleCatalogKey)
        .filter(Boolean),
    ),
  );
}

function normalizeSlugCandidate(value) {
  return normalizeLifecycleCatalogKey(
    (value || "")
      .toString()
      .replace(/[-_]+/g, " "),
  );
}

function containsNormalizedAlias(
  candidate,
  alias,
) {
  const normalizedCandidate =
    normalizeLifecycleCatalogKey(candidate);
  const normalizedAlias =
    normalizeLifecycleCatalogKey(alias);
  if (
    !normalizedCandidate ||
    !normalizedAlias
  ) {
    return false;
  }
  return (
    normalizedCandidate ===
      normalizedAlias ||
    ` ${normalizedCandidate} `.includes(
      ` ${normalizedAlias} `,
    ) ||
    ` ${normalizedAlias} `.includes(
      ` ${normalizedCandidate} `,
    )
  );
}

function escapeArcGisWhereString(
  value,
) {
  return normalizeText(value).replace(
    /'/g,
    "''",
  );
}

function buildCanonicalPhasesForCrop(
  cropKey,
) {
  const phases =
    CANONICAL_PHASES_BY_CROP_KEY[
      cropKey
    ] || [
      "land_preparation",
      "planting",
      "vegetative_growth",
      "harvest",
    ];
  return [...phases];
}

function humanizeCropKey(cropKey) {
  const normalizedKey =
    normalizeText(cropKey);
  if (!normalizedKey) {
    return "";
  }
  return normalizedKey
    .split(/[\s_-]+/g)
    .filter(Boolean)
    .map(
      (segment) =>
        segment
          .charAt(0)
          .toUpperCase() +
        segment.slice(1),
    )
    .join(" ");
}

function resolveAgricultureCropKey({
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
    for (const [
      cropKey,
      aliases,
    ] of Object.entries(
      AGRICULTURE_CROP_ALIASES,
    )) {
      const normalizedAliases =
        aliases.map(
          normalizeLifecycleCatalogKey,
        );
      if (
        normalizedAliases.some(
          (alias) =>
            candidate === alias ||
            ` ${candidate} `.includes(
              ` ${alias} `,
            ) ||
            ` ${alias} `.includes(
              ` ${candidate} `,
            ),
        )
      ) {
        return cropKey;
      }
    }
  }

  return normalizeLifecycleCatalogKey(
    cropSubtype || productName,
  );
}

function buildAgricultureCatalogSearchEntry(
  cropKey,
) {
  const normalizedCropKey =
    normalizeLifecycleCatalogKey(
      cropKey,
    );
  const canonicalName =
    humanizeCropKey(normalizedCropKey);
  const aliases = dedupeStrings([
    canonicalName,
    ...(
      AGRICULTURE_CROP_ALIASES[
        normalizedCropKey
      ] || []
    ),
  ]);
  const lifecycleProfile =
    findCatalogLifecycleProfile({
      productName: canonicalName,
      cropSubtype: normalizedCropKey,
    });

  return {
    cropKey: normalizedCropKey,
    name: canonicalName,
    aliases,
    source: "planner_catalog",
    minDays:
      lifecycleProfile?.minDays || 0,
    maxDays:
      lifecycleProfile?.maxDays || 0,
    phases: lifecycleProfile?.phases ||
      buildCanonicalPhasesForCrop(
        normalizedCropKey,
      ),
  };
}

function scoreAgricultureCatalogEntry({
  entry,
  normalizedQuery,
}) {
  if (!normalizedQuery) {
    return 1;
  }

  const candidates = [
    entry.cropKey,
    entry.name,
    ...(entry.aliases || []),
  ]
    .map(normalizeLifecycleCatalogKey)
    .filter(Boolean);
  let score = 0;

  for (const candidate of candidates) {
    if (candidate === normalizedQuery) {
      score = Math.max(score, 120);
      continue;
    }
    if (candidate.startsWith(normalizedQuery)) {
      score = Math.max(score, 90);
      continue;
    }
    if (
      ` ${candidate} `.includes(
        ` ${normalizedQuery} `,
      )
    ) {
      score = Math.max(score, 70);
      continue;
    }
    if (
      candidate.includes(normalizedQuery)
    ) {
      score = Math.max(score, 50);
      continue;
    }
    if (
      ` ${normalizedQuery} `.includes(
        ` ${candidate} `,
      )
    ) {
      score = Math.max(score, 35);
    }
  }

  return score;
}

function searchAgricultureCatalog({
  query,
  limit = 8,
}) {
  const safeLimit = Math.min(
    20,
    Math.max(
      1,
      Math.floor(Number(limit) || 8),
    ),
  );
  const normalizedQuery =
    normalizeLifecycleCatalogKey(query);
  const rankedEntries = Object.keys(
    AGRICULTURE_CROP_ALIASES,
  )
    .map((cropKey) => {
      const entry =
        buildAgricultureCatalogSearchEntry(
          cropKey,
        );
      return {
        ...entry,
        score:
          scoreAgricultureCatalogEntry({
            entry,
            normalizedQuery,
          }),
      };
    })
    .filter(
      (entry) =>
        normalizedQuery.length === 0 ||
        entry.score > 0,
    )
    .sort((left, right) => {
      if (right.score != left.score) {
        return right.score - left.score;
      }
      return left.name.localeCompare(
        right.name,
      );
    })
    .slice(0, safeLimit)
    .map(
      ({
        cropKey,
        name,
        aliases,
        source,
        minDays,
        maxDays,
        phases,
      }) => ({
        cropKey,
        name,
        aliases,
        source,
        minDays,
        maxDays,
        phases,
      }),
    );

  return rankedEntries;
}

function resolveProviderRequestContext(
  context = {},
) {
  return {
    // WHY: Estate address is the most trustworthy location hint for seasonal calendars.
    estateCountry:
      normalizeText(
        context?.estateCountry,
      ) || "",
    estateState:
      normalizeText(
        context?.estateState,
      ) || "",
    country:
      normalizeText(context?.country) ||
      "",
    source:
      normalizeText(context?.source) ||
      "planner_v2",
    route:
      normalizeText(context?.route) ||
      "",
    requestId:
      normalizeText(
        context?.requestId,
      ) || "unknown",
    userRole:
      normalizeText(
        context?.userRole,
      ) || "",
    businessId:
      normalizeText(
        context?.businessId,
      ) || "",
  };
}

function normalizeCountryName(value) {
  const trimmed = normalizeText(value);
  if (!trimmed) {
    return "";
  }

  const normalizedKey =
    normalizeLifecycleCatalogKey(
      trimmed,
    );
  if (
    COUNTRY_NAME_OVERRIDES[
      normalizedKey
    ]
  ) {
    return COUNTRY_NAME_OVERRIDES[
      normalizedKey
    ];
  }

  if (/^[a-z]{2}$/i.test(trimmed)) {
    try {
      const displayNames =
        new Intl.DisplayNames(["en"], {
          type: "region",
        });
      const displayValue =
        displayNames.of(
          trimmed.toUpperCase(),
        ) || "";
      const override =
        COUNTRY_NAME_OVERRIDES[
          normalizeLifecycleCatalogKey(
            displayValue,
          )
        ];
      return (
        override ||
        displayValue ||
        trimmed
      );
    } catch (error) {
      return trimmed;
    }
  }

  return trimmed;
}

function resolveCountryLookupCandidates(
  requestContext,
) {
  return dedupeStrings([
    requestContext.estateCountry,
    normalizeCountryName(
      requestContext.estateCountry,
    ),
    requestContext.country,
    normalizeCountryName(
      requestContext.country,
    ),
  ]);
}

function classifyProviderFailure({
  status = 0,
  error = null,
}) {
  if (
    error?.name === "AbortError" ||
    /timeout/i.test(
      normalizeText(error?.message),
    )
  ) {
    return {
      classification: "PROVIDER_OUTAGE",
      errorCode:
        "PRODUCTION_AGRICULTURE_PROVIDER_TIMEOUT",
      resolutionHint:
        "Retry provider lookup or reduce network latency before generating the plan again.",
    };
  }

  if (status === 400) {
    return {
      classification:
        "PROVIDER_REJECTED_FORMAT",
      errorCode:
        "PRODUCTION_AGRICULTURE_PROVIDER_BAD_REQUEST",
      resolutionHint:
        "Check the provider query format and retry with normalized crop and country inputs.",
    };
  }
  if (
    status === 401 ||
    status === 403
  ) {
    return {
      classification:
        "AUTHENTICATION_ERROR",
      errorCode:
        "PRODUCTION_AGRICULTURE_PROVIDER_AUTH",
      resolutionHint:
        "Configure valid provider credentials before retrying lifecycle generation.",
    };
  }
  if (status === 404) {
    return {
      classification: "INVALID_INPUT",
      errorCode:
        "PRODUCTION_AGRICULTURE_PROVIDER_NOT_FOUND",
      resolutionHint:
        "Retry with a more precise crop name, subtype, or estate country.",
    };
  }
  if (status === 429) {
    return {
      classification: "RATE_LIMITED",
      errorCode:
        "PRODUCTION_AGRICULTURE_PROVIDER_RATE_LIMITED",
      resolutionHint:
        "Retry later or cache the lifecycle result before generating more drafts.",
    };
  }
  if (status >= 500) {
    return {
      classification: "PROVIDER_OUTAGE",
      errorCode:
        "PRODUCTION_AGRICULTURE_PROVIDER_DOWN",
      resolutionHint:
        "Retry later because the agriculture provider is temporarily unavailable.",
    };
  }

  return {
    classification:
      "UNKNOWN_PROVIDER_ERROR",
    errorCode:
      "PRODUCTION_AGRICULTURE_PROVIDER_UNKNOWN",
    resolutionHint:
      "Inspect provider diagnostics and retry once provider availability is confirmed.",
  };
}

async function requestJsonFromProvider({
  providerName,
  operationName,
  intent,
  url,
  requestContext,
}) {
  // WHY: Each provider request needs deterministic diagnostics for support and fallback analysis.
  debug(
    "PLANNER_V2_AGRICULTURE_API: PROVIDER_CALL_START",
    {
      requestId:
        requestContext.requestId,
      route: requestContext.route,
      step: "PROVIDER_CALL_START",
      layer: "provider",
      operation: operationName,
      intent,
      serviceName: providerName,
      businessIdPresent: Boolean(
        requestContext.businessId,
      ),
      businessId:
        requestContext.businessId ||
        null,
      userRole:
        requestContext.userRole || null,
      source: requestContext.source,
      country:
        requestContext.estateCountry ||
        requestContext.country ||
        null,
      hasEstateState: Boolean(
        requestContext.estateState,
      ),
      url,
    },
  );

  const controller =
    new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    AGRICULTURE_API_TIMEOUT_MS,
  );

  try {
    const response = await fetch(url, {
      method: "GET",
      signal: controller.signal,
    });
    const rawBody =
      await response.text();
    let parsedBody = null;
    try {
      parsedBody =
        rawBody ?
          JSON.parse(rawBody)
        : null;
    } catch (error) {
      parsedBody = null;
    }

    if (!response.ok) {
      const failure =
        classifyProviderFailure({
          status: response.status,
        });
      // WHY: Provider failures should be logged and swallowed so the next provider can still run.
      debug(
        "PLANNER_V2_AGRICULTURE_API: PROVIDER_CALL_FAIL",
        {
          requestId:
            requestContext.requestId,
          route: requestContext.route,
          step: "PROVIDER_CALL_FAIL",
          layer: "provider",
          operation: operationName,
          intent,
          serviceName: providerName,
          businessIdPresent: Boolean(
            requestContext.businessId,
          ),
          businessId:
            requestContext.businessId ||
            null,
          userRole:
            requestContext.userRole ||
            null,
          source: requestContext.source,
          country:
            requestContext.estateCountry ||
            requestContext.country ||
            null,
          hasEstateState: Boolean(
            requestContext.estateState,
          ),
          httpStatus: response.status,
          providerErrorCode:
            normalizeText(
              parsedBody?.code ||
                parsedBody?.error ||
                parsedBody?.status,
            ) || null,
          providerMessage:
            normalizeText(
              parsedBody?.message ||
                parsedBody?.messages ||
                rawBody,
            ) || null,
          classification:
            failure.classification,
          error_code: failure.errorCode,
          resolution_hint:
            failure.resolutionHint,
        },
      );
      return null;
    }

    debug(
      "PLANNER_V2_AGRICULTURE_API: PROVIDER_CALL_OK",
      {
        requestId:
          requestContext.requestId,
        route: requestContext.route,
        step: "PROVIDER_CALL_OK",
        layer: "provider",
        operation: operationName,
        intent,
        serviceName: providerName,
        businessIdPresent: Boolean(
          requestContext.businessId,
        ),
        businessId:
          requestContext.businessId ||
          null,
        userRole:
          requestContext.userRole ||
          null,
        source: requestContext.source,
        country:
          requestContext.estateCountry ||
          requestContext.country ||
          null,
        httpStatus: response.status,
      },
    );
    return parsedBody;
  } catch (error) {
    const failure =
      classifyProviderFailure({
        error,
      });
    debug(
      "PLANNER_V2_AGRICULTURE_API: PROVIDER_CALL_FAIL",
      {
        requestId:
          requestContext.requestId,
        route: requestContext.route,
        step: "PROVIDER_CALL_FAIL",
        layer: "provider",
        operation: operationName,
        intent,
        serviceName: providerName,
        businessIdPresent: Boolean(
          requestContext.businessId,
        ),
        businessId:
          requestContext.businessId ||
          null,
        userRole:
          requestContext.userRole ||
          null,
        source: requestContext.source,
        country:
          requestContext.estateCountry ||
          requestContext.country ||
          null,
        hasEstateState: Boolean(
          requestContext.estateState,
        ),
        httpStatus: 0,
        providerErrorCode: null,
        providerMessage:
          normalizeText(
            error?.message,
          ) ||
          "provider_request_failed",
        classification:
          failure.classification,
        error_code: failure.errorCode,
        resolution_hint:
          failure.resolutionHint,
      },
    );
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function computeWrappedDayDistance(
  startDay,
  endDay,
) {
  const normalizedStart =
    toPositiveInteger(startDay);
  const normalizedEnd =
    toPositiveInteger(endDay);
  if (
    !normalizedStart ||
    !normalizedEnd
  ) {
    return null;
  }
  if (
    normalizedEnd >= normalizedStart
  ) {
    return (
      normalizedEnd -
      normalizedStart +
      1
    );
  }
  return (
    365 -
    normalizedStart +
    normalizedEnd +
    1
  );
}

function normalizeGeoglamFeaturesToLifecycle({
  cropKey,
  productName,
  country,
  features,
}) {
  const rows = (
    Array.isArray(features) ? features
    : [])
    .map((feature) =>
      feature?.attributes ?
        feature.attributes
      : feature,
    )
    .filter(Boolean);
  if (rows.length === 0) {
    return null;
  }

  const seasonalWindows = rows
    .map((row) => {
      const plantingDays =
        toPositiveInteger(
          row?.planting,
        );
      const harvestDays =
        computeWrappedDayDistance(
          row?.planting,
          row?.harvest,
        );
      const seasonEndDays =
        computeWrappedDayDistance(
          row?.planting,
          row?.endofseaso,
        ) || harvestDays;
      if (
        !plantingDays ||
        !harvestDays
      ) {
        return null;
      }
      return {
        crop:
          normalizeText(row?.crop) ||
          null,
        region:
          normalizeText(row?.region) ||
          null,
        plantingDays,
        harvestDays,
        seasonEndDays,
        vegetativeStartDay:
          toPositiveInteger(
            row?.vegetative,
          ),
        harvestStartDay:
          toPositiveInteger(
            row?.harvest,
          ),
        seasonEndDay: toPositiveInteger(
          row?.endofseaso,
        ),
      };
    })
    .filter(Boolean);
  if (seasonalWindows.length === 0) {
    return null;
  }

  const minDays = Math.max(
    1,
    Math.min(
      ...seasonalWindows.map(
        (entry) => entry.harvestDays,
      ),
    ),
  );
  const maxDays = Math.max(
    minDays,
    Math.max(
      ...seasonalWindows.map(
        (entry) =>
          entry.seasonEndDays ||
          entry.harvestDays,
      ),
    ),
  );

  return {
    product:
      normalizeText(productName) ||
      humanizeCropKey(cropKey) ||
      "Farm product",
    minDays,
    maxDays,
    phases:
      buildCanonicalPhasesForCrop(
        cropKey,
      ),
    metadata: {
      sourceType:
        "geoglam_subnational_crop_calendar",
      providerKey: "geoglam",
      lifecycleSource:
        "agriculture_api_geoglam",
      country:
        normalizeText(country) || null,
      cropKey:
        normalizeText(cropKey) || null,
      matchedCropSeries: dedupeStrings(
        seasonalWindows.map(
          (entry) => entry.crop,
        ),
      ),
      regionCount: dedupeStrings(
        seasonalWindows.map(
          (entry) => entry.region,
        ),
      ).length,
      sampleRegions: dedupeStrings(
        seasonalWindows.map(
          (entry) => entry.region,
        ),
      ).slice(0, 6),
      plantingDayOfYearRange: {
        min: Math.min(
          ...seasonalWindows.map(
            (entry) =>
              entry.plantingDays,
          ),
        ),
        max: Math.max(
          ...seasonalWindows.map(
            (entry) =>
              entry.plantingDays,
          ),
        ),
      },
      harvestDayOfYearRange: {
        min: Math.min(
          ...seasonalWindows.map(
            (entry) =>
              entry.harvestStartDay ||
              entry.seasonEndDay ||
              entry.plantingDays,
          ),
        ),
        max: Math.max(
          ...seasonalWindows.map(
            (entry) =>
              entry.harvestStartDay ||
              entry.seasonEndDay ||
              entry.plantingDays,
          ),
        ),
      },
    },
  };
}

async function fetchGeoglamLifecycleProfile({
  cropKey,
  productName,
  requestContext,
}) {
  const cropSeries =
    GEOGLAM_CROP_SERIES_BY_KEY[
      cropKey
    ] || null;
  if (
    !cropSeries ||
    cropSeries.length === 0
  ) {
    debug(
      "PLANNER_V2_AGRICULTURE_API: provider skipped",
      {
        provider: "geoglam",
        reason:
          "crop_not_supported_by_geoglam",
        cropKey,
      },
    );
    return null;
  }

  const countryCandidates =
    resolveCountryLookupCandidates(
      requestContext,
    );
  if (countryCandidates.length === 0) {
    debug(
      "PLANNER_V2_AGRICULTURE_API: provider skipped",
      {
        provider: "geoglam",
        reason:
          "country_context_missing",
        cropKey,
      },
    );
    return null;
  }

  for (const country of countryCandidates) {
    const url = new URL(
      `${GEOGLAM_BASE_URL}/query`,
    );
    // WHY: Country-only query keeps the ArcGIS call cheap while local filtering controls crop matching.
    url.searchParams.set(
      "where",
      `country='${escapeArcGisWhereString(
        country,
      )}'`,
    );
    url.searchParams.set(
      "outFields",
      "country,region,crop,planting,vegetative,harvest,endofseaso,outofseaso",
    );
    url.searchParams.set(
      "returnGeometry",
      "false",
    );
    url.searchParams.set("f", "json");

    const payload =
      await requestJsonFromProvider({
        providerName: "GEOGLAM",
        operationName:
          "FetchCropCalendar",
        intent:
          "resolve farm lifecycle from Africa sub-national crop calendars",
        url: url.toString(),
        requestContext,
      });
    if (!payload) {
      continue;
    }

    const matchingFeatures = (
      Array.isArray(payload?.features) ?
        payload.features
      : []).filter((feature) =>
      cropSeries.includes(
        normalizeText(
          feature?.attributes?.crop,
        ),
      ),
    );
    if (matchingFeatures.length === 0) {
      continue;
    }

    return normalizeGeoglamFeaturesToLifecycle(
      {
        cropKey,
        productName,
        country,
        features: matchingFeatures,
      },
    );
  }

  return null;
}

function buildTrefleSearchTerms({
  cropKey,
  productName,
  cropSubtype,
}) {
  return dedupeNormalizedLifecycleStrings([
    cropSubtype,
    PRIMARY_TREFLE_QUERY_BY_KEY[
      cropKey
    ],
    productName,
  ]);
}

function scoreTrefleSpeciesMatch({
  species,
  cropKey,
  searchTerm,
}) {
  const normalizedCommonName =
    normalizeLifecycleCatalogKey(
      species?.common_name,
    );
  const normalizedScientificName =
    normalizeLifecycleCatalogKey(
      species?.scientific_name,
    );
  const normalizedSlug =
    normalizeSlugCandidate(
      species?.slug,
    );
  const normalizedGenus =
    normalizeLifecycleCatalogKey(
      species?.genus,
    );
  const normalizedSearch =
    normalizeLifecycleCatalogKey(
      searchTerm,
    );
  const normalizedAliases =
    dedupeNormalizedLifecycleStrings([
      cropKey,
      normalizedSearch,
      ...(
        AGRICULTURE_CROP_ALIASES[
          cropKey
        ] || []
      ),
    ]);
  const scientificHints =
    dedupeNormalizedLifecycleStrings(
      TREFLE_SCIENTIFIC_HINTS_BY_CROP_KEY[
        cropKey
      ] || [],
    );
  const exactCommonNameMatch =
    normalizedAliases.some(
      (alias) =>
        normalizedCommonName === alias,
    );
  const exactSlugMatch =
    normalizedAliases.some(
      (alias) =>
        normalizedSlug === alias,
    );
  const wholeCommonNameMatch =
    normalizedAliases.some((alias) =>
      containsNormalizedAlias(
        normalizedCommonName,
        alias,
      ),
    );
  const wholeSlugMatch =
    normalizedAliases.some((alias) =>
      containsNormalizedAlias(
        normalizedSlug,
        alias,
      ),
    );
  const scientificAliasMatch =
    normalizedAliases.some((alias) =>
      containsNormalizedAlias(
        normalizedScientificName,
        alias,
      ),
    );
  const scientificHintMatch =
    scientificHints.some(
      (hint) =>
        containsNormalizedAlias(
          normalizedScientificName,
          hint,
        ) ||
        containsNormalizedAlias(
          normalizedGenus,
          hint,
        ) ||
        containsNormalizedAlias(
          normalizedSlug,
          hint,
        ),
    );
  const isRankSpecies =
    normalizeText(species?.rank) ===
    "species";
  const isVegetable =
    species?.vegetable === true;
  const isEdible =
    species?.edible === true;
  const isAgricultureLike =
    isVegetable ||
    isEdible ||
    scientificHintMatch;

  if (
    !exactCommonNameMatch &&
    !exactSlugMatch &&
    !scientificHintMatch &&
    !(
      isAgricultureLike &&
      (
        wholeCommonNameMatch ||
        wholeSlugMatch ||
        scientificAliasMatch
      )
    )
  ) {
    return 0;
  }

  let score = 0;
  if (exactCommonNameMatch) {
    score += 180;
  }
  if (exactSlugMatch) {
    score += 170;
  }
  if (scientificHintMatch) {
    score += 120;
  }
  if (
    isAgricultureLike &&
    (
      wholeCommonNameMatch ||
      wholeSlugMatch
    )
  ) {
    score += 90;
  }
  if (
    isAgricultureLike &&
    scientificAliasMatch
  ) {
    score += 55;
  }
  if (isRankSpecies) {
    score += 8;
  }
  if (isVegetable) {
    score += 25;
  }
  if (isEdible) {
    score += 20;
  }
  if (species?.id) {
    score += 2;
  }
  return score;
}

function pickBestTrefleSpeciesMatch({
  speciesList,
  cropKey,
  searchTerm,
}) {
  const rankedMatches =
    (Array.isArray(speciesList) ?
      speciesList
    : []
    )
      .map((species) => ({
        species,
        score: scoreTrefleSpeciesMatch({
          species,
          cropKey,
          searchTerm,
        }),
      }))
      .sort((left, right) => {
        if (
          right.score !== left.score
        ) {
          return (
            right.score - left.score
          );
        }
        return (
          Number(
            left.species?.id || 0,
          ) -
          Number(right.species?.id || 0)
        );
      });
  const bestMatch =
    rankedMatches[0] || null;
  if (!bestMatch || bestMatch.score < 80) {
    return null;
  }
  return bestMatch.species;
}

function resolveTrefleTemperatureCelsius(
  value,
) {
  if (
    typeof value?.deg_c === "number"
  ) {
    return value.deg_c;
  }
  if (
    typeof value?.deg_f === "number"
  ) {
    return Number(
      (
        ((value.deg_f - 32) * 5) /
        9
      ).toFixed(2),
    );
  }
  return null;
}

function resolveTrefleMillimeters(
  value,
) {
  if (typeof value?.mm === "number") {
    return value.mm;
  }
  return null;
}

function normalizeTrefleSpeciesToLifecycle({
  cropKey,
  productName,
  species,
}) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  const averageDays = toPositiveInteger(
    growth?.days_to_harvest,
  );
  const growthMonths = dedupeStrings(
    (
      Array.isArray(
        growth?.growth_months,
      )
    ) ?
      growth.growth_months
    : [],
  );
  const monthDerivedDays =
    growthMonths.length > 0 ?
      growthMonths.length * 30
    : null;
  const baseDays =
    averageDays ||
    monthDerivedDays ||
    null;
  if (!baseDays) {
    return null;
  }

  const minDays = Math.max(
    1,
    Math.floor(baseDays * 0.9),
  );
  const maxDays = Math.max(
    minDays,
    Math.ceil(baseDays * 1.1),
  );

  return {
    product:
      normalizeText(
        species?.common_name,
      ) ||
      normalizeText(productName) ||
      humanizeCropKey(cropKey) ||
      normalizeText(
        species?.scientific_name,
      ) ||
      "Farm product",
    minDays,
    maxDays,
    phases:
      buildCanonicalPhasesForCrop(
        cropKey,
      ),
    metadata: {
      sourceType: "trefle_species",
      providerKey: "trefle",
      lifecycleSource:
        "agriculture_api_trefle",
      cropKey:
        normalizeText(cropKey) || null,
      trefleSpeciesId:
        species?.id || null,
      trefleSlug:
        normalizeText(species?.slug) ||
        null,
      scientificName:
        normalizeText(
          species?.scientific_name,
        ) || null,
      rank:
        normalizeText(species?.rank) ||
        null,
      family:
        normalizeText(
          species?.family,
        ) || null,
      daysToHarvest:
        averageDays || null,
      growthMonths,
      sowing:
        normalizeText(growth?.sowing) ||
        null,
      phMinimum:
        Number(growth?.ph_minimum) ||
        null,
      phMaximum:
        Number(growth?.ph_maximum) ||
        null,
      minimumTemperatureC:
        resolveTrefleTemperatureCelsius(
          growth?.minimum_temperature,
        ),
      maximumTemperatureC:
        resolveTrefleTemperatureCelsius(
          growth?.maximum_temperature,
        ),
      minimumPrecipitationMm:
        resolveTrefleMillimeters(
          growth?.minimum_precipitation,
        ),
      maximumPrecipitationMm:
        resolveTrefleMillimeters(
          growth?.maximum_precipitation,
        ),
    },
  };
}

async function fetchTrefleLifecycleProfile({
  cropKey,
  productName,
  cropSubtype,
  requestContext,
}) {
  if (!TREFLE_API_TOKEN) {
    debug(
      "PLANNER_V2_AGRICULTURE_API: provider skipped",
      {
        provider: "trefle",
        reason: "token_missing",
        resolutionHint:
          "Set TREFLE_API_TOKEN before relying on Trefle lifecycle fallback.",
      },
    );
    return null;
  }

  const searchTerms =
    buildTrefleSearchTerms({
      cropKey,
      productName,
      cropSubtype,
    });
  for (const searchTerm of searchTerms) {
    const searchUrl = new URL(
      `${TREFLE_BASE_URL}/species/search`,
    );
    searchUrl.searchParams.set(
      "q",
      searchTerm,
    );
    searchUrl.searchParams.set(
      "token",
      TREFLE_API_TOKEN,
    );

    const searchPayload =
      await requestJsonFromProvider({
        providerName: "Trefle",
        operationName: "SearchSpecies",
        intent:
          "resolve crop lifecycle from species search results",
        url: searchUrl.toString(),
        requestContext,
      });
    if (!searchPayload) {
      continue;
    }

    const match =
      pickBestTrefleSpeciesMatch({
        speciesList:
          searchPayload?.data,
        cropKey,
        searchTerm,
      });
    if (!match) {
      continue;
    }

    const detailPath =
      normalizeText(
        match?.links?.self,
      ) ||
      `/species/${encodeURIComponent(
        normalizeText(
          match?.slug || match?.id,
        ),
      )}`;
    const detailUrl = detailPath.startsWith(
      "http",
    )
      ? new URL(detailPath)
      : new URL(
          detailPath,
          `${TREFLE_BASE_URL}/`,
        );
    detailUrl.searchParams.set(
      "token",
      TREFLE_API_TOKEN,
    );

    const detailPayload =
      await requestJsonFromProvider({
        providerName: "Trefle",
        operationName:
          "FetchSpeciesDetail",
        intent:
          "resolve crop lifecycle from species growth metadata",
        url: detailUrl.toString(),
        requestContext,
      });
    if (!detailPayload) {
      continue;
    }

    const lifecycle =
      normalizeTrefleSpeciesToLifecycle(
        {
          cropKey,
          productName,
          species:
            detailPayload?.data ||
            detailPayload,
        },
      );
    if (lifecycle) {
      return lifecycle;
    }
  }

  return null;
}

function scoreTrefleCatalogSearchResult({
  species,
  query,
}) {
  const normalizedQuery =
    normalizeLifecycleCatalogKey(query);
  if (!normalizedQuery) {
    return 0;
  }

  const candidates = [
    species?.common_name,
    species?.scientific_name,
    normalizeSlugCandidate(
      species?.slug,
    ),
  ]
    .map(normalizeLifecycleCatalogKey)
    .filter(Boolean);
  let score = 0;

  for (const candidate of candidates) {
    if (candidate === normalizedQuery) {
      score = Math.max(score, 180);
      continue;
    }
    if (
      candidate.startsWith(
        normalizedQuery,
      )
    ) {
      score = Math.max(score, 130);
      continue;
    }
    if (
      ` ${candidate} `.includes(
        ` ${normalizedQuery} `,
      )
    ) {
      score = Math.max(score, 95);
      continue;
    }
    if (
      candidate.includes(normalizedQuery)
    ) {
      score = Math.max(score, 70);
    }
  }

  if (species?.vegetable === true) {
    score += 20;
  }
  if (species?.edible === true) {
    score += 15;
  }
  if (
    normalizeText(species?.rank) ===
    "species"
  ) {
    score += 5;
  }

  return score;
}

async function fetchTrefleSpeciesDetail({
  species,
  requestContext,
}) {
  const detailPath =
    normalizeText(
      species?.links?.self,
    ) ||
    `/species/${encodeURIComponent(
      normalizeText(
        species?.slug || species?.id,
      ),
    )}`;
  const detailUrl = detailPath.startsWith(
    "http",
  )
    ? new URL(detailPath)
    : new URL(
        detailPath,
        `${TREFLE_BASE_URL}/`,
      );
  detailUrl.searchParams.set(
    "token",
    TREFLE_API_TOKEN,
  );

  return requestJsonFromProvider({
    providerName: "Trefle",
    operationName:
      "FetchSpeciesDetail",
    intent:
      "load crop search detail from species metadata",
    url: detailUrl.toString(),
    requestContext,
  });
}

function resolveTrefleProfileKind(species) {
  if (species?.fruit === true) {
    return "fruit";
  }
  if (
    species?.vegetable === true ||
    species?.edible === true
  ) {
    return "crop";
  }
  return "plant";
}

function resolveTrefleCategory(species) {
  if (species?.fruit === true) {
    return "fruit";
  }
  if (species?.vegetable === true) {
    return "vegetable";
  }
  if (species?.edible === true) {
    return "edible plant";
  }
  return "plant";
}

function resolveTreflePlantType(species) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  return (
    normalizeText(growth?.growth_habit) ||
    normalizeText(growth?.growth_form) ||
    normalizeText(growth?.duration) ||
    ""
  );
}

function buildTrefleClimateDetails(species) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  return {
    climateZones: [],
    lightPreference:
      normalizeText(growth?.light),
    humidityPreference:
      normalizeText(
        growth?.atmospheric_humidity,
      ),
    temperatureMinC:
      resolveTrefleTemperatureCelsius(
        growth?.minimum_temperature,
      ),
    temperatureMaxC:
      resolveTrefleTemperatureCelsius(
        growth?.maximum_temperature,
      ),
    rainfallMinMm:
      resolveTrefleMillimeters(
        growth?.minimum_precipitation,
      ),
    rainfallMaxMm:
      resolveTrefleMillimeters(
        growth?.maximum_precipitation,
      ),
    notes: dedupeStrings([
      normalizeText(growth?.growth_rate),
      normalizeText(growth?.sowing),
    ]).join(" | "),
  };
}

function buildTrefleSoilDetails(species) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  return {
    textures: dedupeStrings([
      normalizeText(growth?.soil_texture),
    ]),
    drainage:
      normalizeText(
        growth?.soil_salinity,
      ),
    fertility:
      normalizeText(
        growth?.soil_nutriments,
      ),
    phMin:
      Number(growth?.ph_minimum) ||
      null,
    phMax:
      Number(growth?.ph_maximum) ||
      null,
    notes: dedupeStrings([
      normalizeText(growth?.soil_humidity),
    ]).join(" | "),
  };
}

function buildTrefleWaterDetails(species) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  return {
    requirement:
      normalizeText(
        growth?.soil_humidity,
      ),
    irrigationNotes:
      normalizeText(growth?.sowing),
    minimumPrecipitationMm:
      resolveTrefleMillimeters(
        growth?.minimum_precipitation,
      ),
    maximumPrecipitationMm:
      resolveTrefleMillimeters(
        growth?.maximum_precipitation,
      ),
  };
}

function buildTreflePropagationDetails(
  species,
) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  return {
    methods: dedupeStrings([
      normalizeText(growth?.sowing) ?
        "seed"
      : "",
    ]),
    notes:
      normalizeText(growth?.sowing),
  };
}

function buildTrefleHarvestWindowDetails({
  species,
  lifecycle,
}) {
  const growth =
    (
      species?.growth &&
      typeof species.growth === "object"
    ) ?
      species.growth
    : {};
  return {
    earliestDays:
      Number(lifecycle?.minDays || 0) ||
      null,
    latestDays:
      Number(lifecycle?.maxDays || 0) ||
      null,
    seasons: dedupeStrings(
      Array.isArray(growth?.fruit_months) ?
        growth.fruit_months
      : [],
    ),
    notes: "",
  };
}

function buildTrefleSourceProvenance(species) {
  return [
    buildCropProfileProvenanceEntry({
      sourceKey: "trefle",
      externalId:
        normalizeText(species?.id) ||
        normalizeText(species?.slug),
      sourceUrl:
        normalizeText(
          species?.links?.self,
        ) || "",
      citation: dedupeStrings([
        normalizeText(
          species?.scientific_name,
        ),
        normalizeText(species?.family),
      ]).join(" | "),
      notes:
        "Imported from Trefle species detail.",
      confidence: 0.9,
      verificationStatus:
        "source_verified",
    }),
  ];
}

function buildTrefleCatalogItem({
  query,
  species,
  detailSpecies,
}) {
  const resolvedSpecies =
    (
      detailSpecies &&
      typeof detailSpecies ===
        "object"
    ) ?
      detailSpecies
    : species;
  const candidateName =
    normalizeText(
      resolvedSpecies?.common_name,
    ) ||
    normalizeText(
      resolvedSpecies?.scientific_name,
    ) ||
    normalizeText(
      species?.common_name,
    ) ||
    normalizeText(
      species?.scientific_name,
    ) ||
    humanizeCropKey(
      resolveAgricultureCropKey({
        productName: query,
        cropSubtype: "",
      }),
    );
  const cropKey =
    resolveAgricultureCropKey({
      productName: candidateName,
      cropSubtype: "",
    });
  const canonicalName =
    normalizeText(candidateName) ||
    humanizeCropKey(cropKey) ||
    "Farm crop";
  const lifecycle =
    normalizeTrefleSpeciesToLifecycle({
      cropKey,
      productName: canonicalName,
      species: resolvedSpecies,
    });
  const profileKind =
    resolveTrefleProfileKind(
      resolvedSpecies,
    );
  const category =
    resolveTrefleCategory(
      resolvedSpecies,
    );
  const scientificName =
    normalizeText(
      resolvedSpecies?.scientific_name,
    );
  const family =
    normalizeText(
      resolvedSpecies?.family,
    );
  const summary = dedupeStrings([
    canonicalName,
    scientificName,
    family,
    category,
  ]).join(" | ");

  return {
    cropKey:
      normalizeText(cropKey) || "",
    name: canonicalName,
    aliases: dedupeStrings([
      canonicalName,
      resolvedSpecies?.common_name,
      resolvedSpecies?.scientific_name,
      normalizeSlugCandidate(
        resolvedSpecies?.slug,
      ),
      ...(
        AGRICULTURE_CROP_ALIASES[
          cropKey
        ] || []
      ),
    ]),
    source:
      lifecycle?.metadata
        ?.lifecycleSource ||
      "agriculture_api_trefle",
    minDays:
      Number(
        lifecycle?.minDays || 0,
      ) || 0,
    maxDays:
      Number(
        lifecycle?.maxDays || 0,
      ) || 0,
    phases:
      Array.isArray(
        lifecycle?.phases,
      ) ?
        lifecycle.phases
      : [],
    profileKind,
    category,
    variety: "",
    plantType:
      resolveTreflePlantType(
        resolvedSpecies,
      ),
    summary,
    scientificName,
    family,
    verificationStatus:
      lifecycle ?
        "source_verified"
      : "source_pending",
    climate:
      buildTrefleClimateDetails(
        resolvedSpecies,
      ),
    soil:
      buildTrefleSoilDetails(
        resolvedSpecies,
      ),
    water:
      buildTrefleWaterDetails(
        resolvedSpecies,
      ),
    propagation:
      buildTreflePropagationDetails(
        resolvedSpecies,
      ),
    harvestWindow:
      buildTrefleHarvestWindowDetails({
        species: resolvedSpecies,
        lifecycle,
      }),
    sourceProvenance:
      buildTrefleSourceProvenance(
        resolvedSpecies,
      ),
  };
}

async function searchExternalAgricultureCatalog({
  query,
  limit = 8,
  context = {},
}) {
  const normalizedQuery =
    normalizeText(query);
  const safeLimit = Math.min(
    12,
    Math.max(
      1,
      Math.floor(Number(limit) || 8),
    ),
  );
  if (!normalizedQuery) {
    return [];
  }
  if (!TREFLE_API_TOKEN) {
    debug(
      "PLANNER_V2_AGRICULTURE_API: provider skipped",
      {
        provider: "trefle",
        reason: "token_missing_for_crop_search",
      },
    );
    return [];
  }

  const requestContext =
    resolveProviderRequestContext(
      context,
    );
  const searchUrl = new URL(
    `${TREFLE_BASE_URL}/species/search`,
  );
  searchUrl.searchParams.set(
    "q",
    normalizedQuery,
  );
  searchUrl.searchParams.set(
    "token",
    TREFLE_API_TOKEN,
  );

  const searchPayload =
    await requestJsonFromProvider({
      providerName: "Trefle",
      operationName: "SearchSpecies",
      intent:
        "search external agriculture crops for assistant picker",
      url: searchUrl.toString(),
      requestContext,
    });
  if (!searchPayload) {
    return [];
  }

  const rankedSpecies = (
    Array.isArray(searchPayload?.data) ?
      searchPayload.data
    : []
  )
    .map((species) => ({
      species,
      score:
        scoreTrefleCatalogSearchResult({
          species,
          query: normalizedQuery,
        }),
    }))
    .filter((entry) => entry.score > 0)
    .sort((left, right) => {
      if (right.score !== left.score) {
        return (
          right.score - left.score
        );
      }
      return (
        Number(
          left.species?.id || 0,
        ) -
        Number(right.species?.id || 0)
      );
    })
    .slice(0, safeLimit);

  const items = await Promise.all(
    rankedSpecies.map(
      async ({ species }) => {
        const detailPayload =
          await fetchTrefleSpeciesDetail({
            species,
            requestContext,
          });
        return buildTrefleCatalogItem({
          query: normalizedQuery,
          species,
          detailSpecies:
            detailPayload?.data ||
            detailPayload ||
            species,
        });
      },
    ),
  );

  const seenKeys = new Set();
  return items.filter((item) => {
    const hasLifecycleDays =
      Number(item?.minDays || 0) > 0 ||
      Number(item?.maxDays || 0) > 0;
    if (!hasLifecycleDays) {
      return false;
    }
    const displayKey = [
      normalizeLifecycleCatalogKey(
        item?.name,
      ),
      normalizeLifecycleCatalogKey(
        item?.cropKey,
      ),
    ].join("::");
    if (!displayKey) {
      return false;
    }
    if (seenKeys.has(displayKey)) {
      return false;
    }
    seenKeys.add(displayKey);
    return true;
  });
}

async function fetchAgricultureLifecycleProfile({
  productName,
  cropSubtype,
  domainContext,
  context = {},
}) {
  const requestContext =
    resolveProviderRequestContext(
      context,
    );
  const cropKey =
    resolveAgricultureCropKey({
      productName,
      cropSubtype,
    });

  // WHY: External provider work only makes sense for the farm-first planner path.
  if (
    normalizeText(domainContext) !==
    "farm"
  ) {
    debug(
      "PLANNER_V2_AGRICULTURE_API: skipped",
      {
        reason: "domain_not_supported",
        domainContext,
        cropKey,
      },
    );
    return null;
  }

  debug(
    "PLANNER_V2_AGRICULTURE_API: SERVICE_START",
    {
      requestId:
        requestContext.requestId,
      route: requestContext.route,
      step: "SERVICE_START",
      layer: "provider",
      operation:
        "ResolveLifecycleProfile",
      intent:
        "resolve trusted external farm lifecycle data before planner scheduling",
      businessIdPresent: Boolean(
        requestContext.businessId,
      ),
      businessId:
        requestContext.businessId ||
        null,
      userRole:
        requestContext.userRole || null,
      source: requestContext.source,
      country:
        requestContext.estateCountry ||
        requestContext.country ||
        null,
      cropKey,
      productName,
      cropSubtype,
    },
  );

  // WHY: GEOGLAM is the preferred first provider because it gives Africa crop-season timing.
  const geoglamLifecycle =
    await fetchGeoglamLifecycleProfile({
      cropKey,
      productName,
      requestContext,
    });
  if (geoglamLifecycle) {
    return geoglamLifecycle;
  }

  // WHY: Trefle fills species-level gaps for horticulture crops when GEOGLAM has no coverage.
  const trefleLifecycle =
    await fetchTrefleLifecycleProfile({
      cropKey,
      productName,
      cropSubtype,
      requestContext,
    });
  if (trefleLifecycle) {
    return trefleLifecycle;
  }

  debug(
    "PLANNER_V2_AGRICULTURE_API: skipped",
    {
      intent:
        "external agriculture providers did not return lifecycle data",
      productName,
      cropSubtype,
      domainContext,
      cropKey,
      country:
        requestContext.estateCountry ||
        requestContext.country ||
        null,
    },
  );
  return null;
}

module.exports = {
  fetchAgricultureLifecycleProfile,
  searchExternalAgricultureCatalog,
  searchAgricultureCatalog,
  resolveAgricultureCropKey,
  humanizeCropKey,
  __test__: {
    buildCanonicalPhasesForCrop,
    normalizeGeoglamFeaturesToLifecycle,
    normalizeTrefleSpeciesToLifecycle,
    resolveAgricultureCropKey,
    resolveCountryLookupCandidates,
  },
};
