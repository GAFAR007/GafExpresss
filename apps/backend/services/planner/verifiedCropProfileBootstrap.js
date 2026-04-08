/**
 * apps/backend/services/planner/verifiedCropProfileBootstrap.js
 * -------------------------------------------------------------
 * WHAT:
 * - Curated planner-ready bootstrap crop profiles for core production crops and fruits.
 *
 * WHY:
 * - Seed manifest records are intentionally unverified and should not drive planner biology.
 * - Core crops need a separate, source-cited baseline that can be loaded into the store
 *   before broader dataset imports are available.
 *
 * HOW:
 * - Defines manually reviewed crop profiles with lifecycle bounds, agronomy details, and provenance.
 * - Keeps the bootstrap scope deliberately small and high-signal: common staple crops and fruits first.
 * - Exports a builder so scripts can persist these profiles with business scoping.
 */

const {
  buildCropProfileProvenanceEntry,
} = require("./cropProfileSources");

const VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION =
  "2026-03-v1";

function buildBootstrapProvenance({
  sourceKey,
  sourceUrl,
  citation,
  notes,
  confidence = 0.95,
}) {
  return buildCropProfileProvenanceEntry({
    sourceKey,
    sourceUrl,
    citation,
    notes,
    confidence,
    verificationStatus: "source_verified",
  });
}

function buildBootstrapEntry({
  productName,
  cropSubtype = "",
  aliases = [],
  lifecycle,
  metadata = {},
  profileDetails = {},
}) {
  return {
    productName,
    cropSubtype,
    aliases: Array.from(
      new Set(
        [productName, ...aliases]
          .map((entry) =>
            (entry || "").toString().trim(),
          )
          .filter(Boolean),
      ),
    ),
    lifecycle: {
      product: productName,
      minDays: lifecycle.minDays,
      maxDays: lifecycle.maxDays,
      phases: lifecycle.phases,
    },
    metadata: {
      bootstrapVersion:
        VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
      bootstrapTier: "core_verified",
      ...metadata,
    },
    profileDetails: {
      verificationStatus:
        "manual_verified",
      lifecycleStatus: "verified",
      ...profileDetails,
      sourceProvenance:
        profileDetails.sourceProvenance,
    },
  };
}

const VERIFIED_CROP_PROFILE_BOOTSTRAP_ENTRIES =
  Object.freeze([
    buildBootstrapEntry({
      productName: "Tomato",
      aliases: [
        "tomato",
        "tomatoes",
        "solanum lycopersicum",
      ],
      lifecycle: {
        minDays: 93,
        maxDays: 120,
        phases: [
          "nursery",
          "transplant_establishment",
          "vegetative_growth",
          "flowering",
          "fruit_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "tomato",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "",
        plantType: "vine",
        summary:
          "Warm-season tomato profile for open-field or protected cultivation with nursery, fruiting, and repeat-harvest phases.",
        scientificName:
          "Solanum lycopersicum",
        family: "Solanaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 30,
          notes:
            "Tomatoes need a long frost-free season and warm, sunny conditions.",
        },
        soil: {
          textures: [
            "loam",
            "sandy loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate to high organic matter",
          phMin: 5.5,
          phMax: 7,
          notes:
            "Avoid waterlogged soil and maintain mulch or organic matter to stabilize moisture.",
        },
        water: {
          requirement:
            "moderate to high",
          irrigationNotes:
            "Maintain consistent soil moisture; about 25 mm per week is a practical minimum baseline.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Common commercial flow starts seed indoors, then transplants after frost risk has passed.",
        },
        harvestWindow: {
          earliestDays: 93,
          latestDays: 120,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Harvest repeats over several weeks depending on determinate or indeterminate habit.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension crop planning tables list 28-35 days from seeding to transplant and 65-85 days from transplant to first harvest for slicer/Roma tomatoes.",
            notes:
              "Used for tomato total crop-cycle range and repeat-harvest expectation.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-tomatoes",
            citation:
              "University of Minnesota Extension tomato guide describes full-sun, long frost-free production with pH 5.5-7 and roughly 25 mm weekly water needs.",
            notes:
              "Used for tomato climate, soil, and watering guidance.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Roma Tomato",
      aliases: [
        "roma tomato",
        "plum tomato",
        "processing tomato",
      ],
      lifecycle: {
        minDays: 93,
        maxDays: 120,
        phases: [
          "nursery",
          "transplant_establishment",
          "vegetative_growth",
          "flowering",
          "fruit_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "roma_tomato",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "Roma",
        plantType: "vine",
        summary:
          "Determinate or semi-determinate plum tomato profile commonly used for processing and bulk harvest.",
        scientificName:
          "Solanum lycopersicum",
        family: "Solanaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 30,
          notes:
            "Roma types benefit from warm, sunny conditions and low disease pressure during fruit fill.",
        },
        soil: {
          textures: [
            "loam",
            "sandy loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate to high organic matter",
          phMin: 5.5,
          phMax: 7,
          notes:
            "Consistent fertility supports uniform fruit set for processing harvests.",
        },
        water: {
          requirement:
            "moderate to high",
          irrigationNotes:
            "Keep soil moisture stable to reduce blossom-end rot and cracking.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Commercial Roma production commonly uses raised seedlings or nursery plugs.",
        },
        harvestWindow: {
          earliestDays: 93,
          latestDays: 120,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Often harvested in a concentrated window for processing or bulk market supply.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension groups slicer and Roma tomatoes at 28-35 nursery days plus 65-85 days to first harvest.",
            notes:
              "Used for Roma total crop-cycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-tomatoes",
            citation:
              "University of Minnesota Extension tomato guide provides tomato climate, pH, and irrigation guidance applicable to Roma types.",
            notes:
              "Used for shared tomato agronomy details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Cherry Tomato",
      aliases: [
        "cherry tomato",
        "small-fruited tomato",
      ],
      lifecycle: {
        minDays: 78,
        maxDays: 105,
        phases: [
          "nursery",
          "transplant_establishment",
          "vegetative_growth",
          "flowering",
          "fruit_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "cherry_tomato",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "Cherry",
        plantType: "vine",
        summary:
          "Fast-fruiting tomato profile for cherry and cocktail types with an earlier harvest start than slicer tomatoes.",
        scientificName:
          "Solanum lycopersicum",
        family: "Solanaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 30,
          notes:
            "Smaller-fruited tomatoes often harvest earlier once fruit set begins.",
        },
        soil: {
          textures: [
            "loam",
            "sandy loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate to high organic matter",
          phMin: 5.5,
          phMax: 7,
          notes:
            "Balanced fertility and mulching help maintain steady fruit quality.",
        },
        water: {
          requirement:
            "moderate to high",
          irrigationNotes:
            "Maintain consistent soil moisture to reduce fruit cracking.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Cherry tomatoes are usually transplanted after nursery establishment.",
        },
        harvestWindow: {
          earliestDays: 78,
          latestDays: 105,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Harvest is frequent and can extend for weeks under indeterminate growth.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension lists 28-35 days from seeding to transplant and 50-70 days from transplant to first harvest for cherry tomatoes.",
            notes:
              "Used for cherry tomato lifecycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-tomatoes",
            citation:
              "University of Minnesota Extension tomato guide provides shared tomato climate, soil, and watering baselines.",
            notes:
              "Used for agronomy details that also apply to cherry tomatoes.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Pepper",
      aliases: [
        "pepper",
        "capsicum",
        "peppers",
      ],
      lifecycle: {
        minDays: 85,
        maxDays: 120,
        phases: [
          "nursery",
          "transplant_establishment",
          "vegetative_growth",
          "flowering",
          "fruit_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "pepper",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "",
        plantType: "shrub",
        summary:
          "Warm-season capsicum profile spanning sweet and mildly hot fresh-market pepper systems.",
        scientificName:
          "Capsicum annuum",
        family: "Solanaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 32,
          notes:
            "Peppers perform best in warm, sunny seasons and should be transplanted once nights stay above 10 C.",
        },
        soil: {
          textures: [
            "loam",
            "sandy loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate organic matter",
          phMin: 6.5,
          phMax: 7,
          notes:
            "Avoid high nitrogen rates that delay fruiting.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Keep soil moisture even; roughly 25 mm weekly and more often on sandy soils.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Commercial pepper flows commonly raise seedlings indoors for about 8 weeks before field transplanting.",
        },
        harvestWindow: {
          earliestDays: 85,
          latestDays: 120,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Harvest repeats through successive pickings once mature fruit begins forming.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension lists bell peppers at 35-50 days from seeding to transplant and 50-70 days from transplant to first harvest.",
            notes:
              "Used as the baseline pepper crop-cycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-peppers",
            citation:
              "University of Minnesota Extension pepper guide states peppers do best at pH 6.5-7, with consistent soil moisture and warm nights above 50 F.",
            notes:
              "Used for pepper agronomy details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Bell Pepper",
      aliases: [
        "bell pepper",
        "sweet pepper",
      ],
      lifecycle: {
        minDays: 85,
        maxDays: 120,
        phases: [
          "nursery",
          "transplant_establishment",
          "vegetative_growth",
          "flowering",
          "fruit_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "bell_pepper",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "Bell",
        plantType: "shrub",
        summary:
          "Sweet pepper profile optimized for fresh-market bell production and repeated pick harvests.",
        scientificName:
          "Capsicum annuum",
        family: "Solanaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 32,
          notes:
            "Bell pepper quality is strongest in warm, sunny weather with stable night temperatures.",
        },
        soil: {
          textures: [
            "loam",
            "sandy loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate organic matter",
          phMin: 6.5,
          phMax: 7,
          notes:
            "Moisture stress weakens flowers and small fruits and can increase blossom-end rot risk.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Provide about 25 mm water weekly, increasing frequency in sandy soils.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Bell peppers are generally transplanted after 35-50 nursery days.",
        },
        harvestWindow: {
          earliestDays: 85,
          latestDays: 120,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Green harvest can begin before full color change; repeated pickings continue for 6-8 weeks or more.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension crop planning tables use bell pepper at 35-50 nursery days plus 50-70 days to first harvest.",
            notes:
              "Used for bell pepper total crop-cycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-peppers",
            citation:
              "University of Minnesota Extension pepper guide provides bell pepper soil pH and irrigation guidance.",
            notes:
              "Used for bell pepper climate, soil, and water details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Scotch Bonnet Pepper",
      aliases: [
        "scotch bonnet",
        "scotch bonnet pepper",
      ],
      lifecycle: {
        minDays: 95,
        maxDays: 130,
        phases: [
          "nursery",
          "transplant_establishment",
          "vegetative_growth",
          "flowering",
          "fruit_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey:
          "scotch_bonnet_pepper",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "Scotch Bonnet",
        plantType: "shrub",
        summary:
          "Hot pepper profile for Scotch Bonnet production, typically slightly longer to mature than bell pepper types.",
        scientificName:
          "Capsicum chinense",
        family: "Solanaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate to high",
          temperatureMinC: 20,
          temperatureMaxC: 32,
          notes:
            "Hot pepper types need a warm, extended growing period to develop mature color and pungency.",
        },
        soil: {
          textures: [
            "loam",
            "sandy loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate organic matter",
          phMin: 6.5,
          phMax: 7,
          notes:
            "Avoid prolonged drought stress during flowering and fruit fill.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Maintain even moisture; increase irrigation frequency in sandy or hot conditions.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Nursery starts are preferred to capture a longer hot-season fruiting window.",
        },
        harvestWindow: {
          earliestDays: 95,
          latestDays: 130,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Typically harvested repeatedly once fruits reach mature size and target color.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension bell and hot pepper planning ranges were used as the minimum baseline, then widened for slower hot pepper maturity.",
            notes:
              "Used as the production baseline for Scotch Bonnet lifecycle.",
            confidence: 0.9,
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-peppers",
            citation:
              "University of Minnesota Extension pepper guide provides shared pepper soil, moisture, and warm-season production guidance.",
            notes:
              "Used for hot pepper agronomy details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Onion",
      aliases: [
        "onion",
        "onions",
        "allium cepa",
      ],
      lifecycle: {
        minDays: 90,
        maxDays: 160,
        phases: [
          "nursery_or_set_preparation",
          "establishment",
          "leaf_growth",
          "bulb_initiation",
          "bulb_fill",
          "harvest",
          "curing",
        ],
      },
      metadata: {
        bootstrapKey: "onion",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "",
        plantType: "herb",
        summary:
          "Bulb onion profile covering seed, transplant, or set-based production with curing at the end of the harvest window.",
        scientificName:
          "Allium cepa",
        family: "Amaryllidaceae",
        climate: {
          climateZones: [
            "cool_temperate",
            "warm_temperate",
            "subtropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 10,
          temperatureMaxC: 28,
          notes:
            "Cool conditions support establishment, while day length and season determine bulb initiation.",
        },
        soil: {
          textures: [
            "loam",
            "silt loam",
          ],
          drainage: "well-drained",
          fertility:
            "high organic matter",
          phMin: 6,
          phMax: 7,
          notes:
            "Onions are shallow-rooted and benefit from friable soils with good nitrogen availability.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Keep root zone consistently moist through bulb fill; reduce moisture near curing.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
            "set",
          ],
          notes:
            "Cycle length varies significantly by planting material; seedling transplants extend the total cycle.",
        },
        harvestWindow: {
          earliestDays: 90,
          latestDays: 160,
          seasons: [
            "cool_season",
            "warm_season",
          ],
          notes:
            "Harvest when tops fall and dry; cure in a warm, ventilated space before storage.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension lists onions at 10-12 weeks from seeding to transplant and 90 days from transplant to first harvest.",
            notes:
              "Used to anchor the upper onion lifecycle range while preserving shorter set-based harvests.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-onions",
            citation:
              "University of Minnesota Extension onion guide states onions need full sun, well-drained high-organic-matter soil, pH 6.0-7.0, and constant moisture.",
            notes:
              "Used for onion soil, light, and watering details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Red Onion",
      aliases: [
        "red onion",
        "purple onion",
      ],
      lifecycle: {
        minDays: 90,
        maxDays: 160,
        phases: [
          "nursery_or_set_preparation",
          "establishment",
          "leaf_growth",
          "bulb_initiation",
          "bulb_fill",
          "harvest",
          "curing",
        ],
      },
      metadata: {
        bootstrapKey: "red_onion",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "vegetable",
        variety: "Red",
        plantType: "herb",
        summary:
          "Red bulb onion profile for fresh-market and storage systems where bulb color and cure quality matter.",
        scientificName:
          "Allium cepa",
        family: "Amaryllidaceae",
        climate: {
          climateZones: [
            "cool_temperate",
            "warm_temperate",
            "subtropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 10,
          temperatureMaxC: 28,
          notes:
            "Bulb initiation depends on adapted day-length type and smooth establishment conditions.",
        },
        soil: {
          textures: [
            "loam",
            "silt loam",
          ],
          drainage: "well-drained",
          fertility:
            "high organic matter",
          phMin: 6,
          phMax: 7,
          notes:
            "Nutrient balance and dry cure conditions support bulb firmness and shelf life.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Maintain even moisture through bulb fill; avoid extended saturation.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
            "set",
          ],
          notes:
            "Often grown from transplants or sets in commercial fresh-market systems.",
        },
        harvestWindow: {
          earliestDays: 90,
          latestDays: 160,
          seasons: [
            "cool_season",
            "warm_season",
          ],
          notes:
            "Allow a full cure for storage-oriented harvests.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension transplant planning window for onions was used as the base crop-cycle reference.",
            notes:
              "Used for red onion lifecycle baseline.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-onions",
            citation:
              "University of Minnesota Extension onion guide provides shared full-sun, pH, and moisture guidance for bulb onions.",
            notes:
              "Used for red onion agronomy details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Corn",
      aliases: [
        "corn",
        "maize",
        "zea mays",
      ],
      lifecycle: {
        minDays: 70,
        maxDays: 100,
        phases: [
          "germination",
          "vegetative_growth",
          "tasseling",
          "silking",
          "grain_fill",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "corn",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "grain",
        variety: "",
        plantType: "grass",
        summary:
          "Direct-seeded maize profile for warm-season production with pollination-sensitive tasseling and silking stages.",
        scientificName:
          "Zea mays",
        family: "Poaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 16,
          temperatureMaxC: 32,
          notes:
            "Corn is a warm-season grass crop that benefits from warm soils and uninterrupted sunlight.",
        },
        soil: {
          textures: [
            "loam",
            "silt loam",
            "clay loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate to high",
          phMin: 5.8,
          phMax: 7,
          notes:
            "Uniform fertility and field moisture are especially important during tasseling and grain fill.",
        },
        water: {
          requirement:
            "moderate to high",
          irrigationNotes:
            "Moisture stress during tasseling and silking reduces yield sharply.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: ["seed"],
          notes:
            "Direct seed once soil is warm enough for rapid germination.",
        },
        harvestWindow: {
          earliestDays: 70,
          latestDays: 100,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Fresh-market corn harvest is brief and closely tied to silk dry-down and kernel maturity.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension lists sweet corn at 70-85 days to maturity with a short harvest window.",
            notes:
              "Used as the baseline lifecycle band for table corn/maize planning.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-sweet-corn",
            citation:
              "University of Minnesota Extension sweet corn guide states seeds germinate best near 60 F and documents variety maturity ranges from about 67 to 87 days.",
            notes:
              "Used for corn establishment and harvest timing notes.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Sweet Corn",
      aliases: [
        "sweet corn",
        "fresh corn",
      ],
      lifecycle: {
        minDays: 67,
        maxDays: 87,
        phases: [
          "germination",
          "vegetative_growth",
          "tasseling",
          "silking",
          "grain_fill",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "sweet_corn",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "grain",
        variety: "Sweet",
        plantType: "grass",
        summary:
          "Fresh-market sweet corn profile with fast maturity and a narrow harvest window around milk stage.",
        scientificName:
          "Zea mays",
        family: "Poaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 16,
          temperatureMaxC: 32,
          notes:
            "Sweet corn should be direct-seeded into warm soil for strong emergence.",
        },
        soil: {
          textures: [
            "loam",
            "silt loam",
            "clay loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate to high",
          phMin: 5.8,
          phMax: 7,
          notes:
            "Good nutrient supply and steady moisture are needed for ear quality.",
        },
        water: {
          requirement:
            "moderate to high",
          irrigationNotes:
            "Avoid drought at tasseling and silking; it reduces kernel set.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: ["seed"],
          notes:
            "Sweet corn is direct-seeded rather than transplanted.",
        },
        harvestWindow: {
          earliestDays: 67,
          latestDays: 87,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Harvest when kernels are full and milky; silk dry-down generally trails by about 18-24 days.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-sweet-corn",
            citation:
              "University of Minnesota Extension sweet corn variety table shows maturity values from about 67 to 87 days.",
            notes:
              "Used for sweet corn lifecycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension planning tables list sweet corn at 70-85 days with a short harvest window.",
            notes:
              "Used to reinforce sweet corn harvest timing.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Beans",
      aliases: [
        "beans",
        "bean",
        "common bean",
        "phaseolus vulgaris",
      ],
      lifecycle: {
        minDays: 50,
        maxDays: 70,
        phases: [
          "germination",
          "vegetative_growth",
          "flowering",
          "pod_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "beans",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "legume",
        variety: "",
        plantType: "vine",
        summary:
          "Common bean profile covering bush and climbing snap or shell bean systems with a short to medium crop cycle.",
        scientificName:
          "Phaseolus vulgaris",
        family: "Fabaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical_highland",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 30,
          notes:
            "Beans are warm-season crops and are frost sensitive.",
        },
        soil: {
          textures: [
            "clay loam",
            "silt loam",
            "loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate organic matter",
          phMin: 6,
          phMax: 7,
          notes:
            "Common beans perform best in slightly acidic to neutral soils with good drainage.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Around 25 mm per week is a practical production baseline; sandy soils need more frequent irrigation.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: ["seed"],
          notes:
            "Beans are normally direct-seeded after soils warm sufficiently for rapid emergence.",
        },
        harvestWindow: {
          earliestDays: 50,
          latestDays: 70,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Snap bean harvest begins before seed bulge; shell and dry bean systems extend later.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension lists green beans at about 50-55 days to maturity and common short-season summer succession use.",
            notes:
              "Used for bean crop-cycle baseline.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-beans",
            citation:
              "University of Minnesota Extension bean guide states beans grow best at pH 6-7 in well-drained loams and about one inch of water per week.",
            notes:
              "Used for bean soil and irrigation details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Green Beans",
      aliases: [
        "green beans",
        "snap beans",
        "string beans",
      ],
      lifecycle: {
        minDays: 50,
        maxDays: 55,
        phases: [
          "germination",
          "vegetative_growth",
          "flowering",
          "pod_set",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "green_beans",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "legume",
        variety: "Green",
        plantType: "vine",
        summary:
          "Snap bean profile for tender pod production with an early, compressed harvest window.",
        scientificName:
          "Phaseolus vulgaris",
        family: "Fabaceae",
        climate: {
          climateZones: [
            "warm_temperate",
            "subtropical",
            "tropical_highland",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 18,
          temperatureMaxC: 30,
          notes:
            "Green beans are fast warm-season crops and do not tolerate frost.",
        },
        soil: {
          textures: [
            "clay loam",
            "silt loam",
            "loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate organic matter",
          phMin: 6,
          phMax: 7,
          notes:
            "Avoid poorly drained sites and excessive nitrogen.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Target around 25 mm water weekly and avoid soil drying during flowering and pod fill.",
          minimumPrecipitationMm: 25,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: ["seed"],
          notes:
            "Snap beans are direct-seeded and often planted in successions for continuous supply.",
        },
        harvestWindow: {
          earliestDays: 50,
          latestDays: 55,
          seasons: [
            "warm_season",
            "summer",
          ],
          notes:
            "Harvest when pods are still succulent and before seeds bulge strongly.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetable-growing-guides-farmers/crop-and-field-planning-tools-vegetable-farmers",
            citation:
              "University of Minnesota Extension lists green beans, bush type, at 50-55 days to maturity.",
            notes:
              "Used for green bean lifecycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "umn_extension",
            sourceUrl:
              "https://extension.umn.edu/vegetables/growing-beans",
            citation:
              "University of Minnesota Extension bean guide provides soil pH, soil texture, and watering guidance for common beans.",
            notes:
              "Used for snap bean agronomy details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Rice",
      aliases: [
        "rice",
        "paddy",
        "oryza sativa",
      ],
      lifecycle: {
        minDays: 100,
        maxDays: 140,
        phases: [
          "nursery_or_direct_seed",
          "establishment",
          "tillering",
          "panicle_initiation",
          "heading",
          "grain_fill",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "rice",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "grain",
        variety: "",
        plantType: "grass",
        summary:
          "Lowland or managed-water rice profile with short to medium duration cultivars and clear reproductive timing.",
        scientificName:
          "Oryza sativa",
        family: "Poaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "high",
          temperatureMinC: 20,
          temperatureMaxC: 35,
          notes:
            "Rice performs best in warm, humid conditions with reliable water control.",
        },
        soil: {
          textures: [
            "silt loam",
            "clay loam",
            "clay",
          ],
          drainage:
            "controlled water retention",
          fertility:
            "moderate to high",
          phMin: 5,
          phMax: 7,
          notes:
            "Lowland systems benefit from level fields and soils that can retain standing water without prolonged cracking.",
        },
        water: {
          requirement: "high",
          irrigationNotes:
            "Water control is central to crop establishment, tillering, and grain filling in paddy systems.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Rice may be direct seeded or transplanted depending on the production system.",
        },
        harvestWindow: {
          earliestDays: 100,
          latestDays: 140,
          seasons: [
            "rainy_season",
            "irrigated_cycle",
          ],
          notes:
            "Short-duration varieties generally mature first; medium-duration varieties extend the production calendar.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "irri",
            sourceUrl:
              "https://www.knowledgebank.irri.org/step-by-step-production/pre-planting/crop-calendar",
            citation:
              "IRRI Rice Knowledge Bank states short-duration varieties take 100-120 days and medium-duration varieties 120-140 days.",
            notes:
              "Used for generic rice lifecycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey: "irri",
            sourceUrl:
              "https://www.knowledgebank.irri.org/training/fact-sheets/item/when-to-harvest-fact-sheet",
            citation:
              "IRRI harvest guidance notes early varieties around 110 days after sowing and medium varieties around 113-125 days.",
            notes:
              "Used to validate rice harvest timing and grain-fill window.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Jasmine Rice",
      aliases: [
        "jasmine rice",
        "aromatic rice",
      ],
      lifecycle: {
        minDays: 105,
        maxDays: 135,
        phases: [
          "nursery_or_direct_seed",
          "establishment",
          "tillering",
          "panicle_initiation",
          "heading",
          "grain_fill",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "jasmine_rice",
        bootstrapGroup:
          "critical_crop_variant",
      },
      profileDetails: {
        profileKind: "crop",
        category: "grain",
        variety: "Jasmine",
        plantType: "grass",
        summary:
          "Aromatic rice profile aligned to short-to-medium duration transplanted or direct-seeded production systems.",
        scientificName:
          "Oryza sativa",
        family: "Poaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "high",
          temperatureMinC: 20,
          temperatureMaxC: 35,
          notes:
            "Jasmine-type production benefits from warm, humid seasons and good harvest-timing discipline for grain quality.",
        },
        soil: {
          textures: [
            "silt loam",
            "clay loam",
            "clay",
          ],
          drainage:
            "controlled water retention",
          fertility:
            "moderate to high",
          phMin: 5,
          phMax: 7,
          notes:
            "Field leveling and bunding improve water management and grain uniformity.",
        },
        water: {
          requirement: "high",
          irrigationNotes:
            "Maintain controlled water availability through tillering and reproductive stages.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed",
            "transplant",
          ],
          notes:
            "Jasmine rice is typically managed in irrigated or seasonal lowland systems.",
        },
        harvestWindow: {
          earliestDays: 105,
          latestDays: 135,
          seasons: [
            "rainy_season",
            "irrigated_cycle",
          ],
          notes:
            "Harvest close to physiological maturity to protect aroma and milling quality.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "irri",
            sourceUrl:
              "https://www.knowledgebank.irri.org/step-by-step-production/pre-planting/crop-calendar",
            citation:
              "IRRI short and medium duration crop calendar windows were used to frame an aromatic rice lifecycle.",
            notes:
              "Used for jasmine rice lifecycle band.",
            confidence: 0.92,
          }),
          buildBootstrapProvenance({
            sourceKey: "irri",
            sourceUrl:
              "https://www.knowledgebank.irri.org/training/fact-sheets/item/when-to-harvest-fact-sheet",
            citation:
              "IRRI harvest fact sheet gives early to medium rice harvest timing after sowing and heading.",
            notes:
              "Used for jasmine rice harvest guidance.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Yam",
      aliases: [
        "yam",
        "yams",
        "dioscorea",
      ],
      lifecycle: {
        minDays: 210,
        maxDays: 270,
        phases: [
          "set_preparation",
          "sprouting",
          "vine_growth",
          "tuber_initiation",
          "tuber_bulking",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "yam",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "tuber",
        variety: "",
        plantType: "vine",
        summary:
          "Staple yam profile for ware yam production with sett establishment, vine training, tuber bulking, and dry-down harvest.",
        scientificName:
          "Dioscorea rotundata",
        family: "Dioscoreaceae",
        climate: {
          climateZones: [
            "humid_tropical",
            "subhumid_tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate to high",
          temperatureMinC: 20,
          temperatureMaxC: 32,
          notes:
            "Yam needs a long warm season for vine growth and tuber bulking.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate organic matter",
          phMin: 5.5,
          phMax: 7,
          notes:
            "Loose, friable soil supports tuber expansion and reduces harvest damage.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Adequate seasonal moisture supports vine growth and tuber fill; avoid long waterlogging periods.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "seed_yam",
            "setts",
          ],
          notes:
            "Ware yam production typically starts from seed yam pieces or setts and requires staking or trellising.",
        },
        harvestWindow: {
          earliestDays: 210,
          latestDays: 270,
          seasons: [
            "rainy_season",
            "late_rainy_season",
          ],
          notes:
            "Harvest after canopy senescence and dry-down; earlier harvest is used for seed yam systems.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "iita",
            sourceUrl:
              "https://biblio.iita.org/documents/U16BkIitaStandardNothomNodev.PDF-f436432e9bafda38c621234407a08d14.pdf",
            citation:
              "IITA yam variety evaluation protocol states yam could be harvested between 7 and 9 months after planting depending on species and maturity duration.",
            notes:
              "Used for generic ware yam lifecycle range.",
          }),
          buildBootstrapProvenance({
            sourceKey: "iita",
            sourceUrl:
              "https://biblio.iita.org/documents/U14ManAighewiSeedNothomNodev.pdf-8bef3fbbef76c2e0f3c6b8bc433d3f91.pdf",
            citation:
              "IITA seed yam manual describes propagation by seed yam pieces and earlier seed-yam harvest around 5-6 months.",
            notes:
              "Used to support yam propagation methods and explain shorter seed-yam cycles.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Cassava",
      aliases: [
        "cassava",
        "manioc",
        "yuca",
        "manihot esculenta",
      ],
      lifecycle: {
        minDays: 270,
        maxDays: 360,
        phases: [
          "stem_cutting_establishment",
          "canopy_development",
          "root_initiation",
          "root_bulking",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "cassava",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "tuber",
        variety: "",
        plantType: "shrub",
        summary:
          "Cassava root crop profile for stem-cutting establishment and long in-field bulking to starch maturity.",
        scientificName:
          "Manihot esculenta",
        family: "Euphorbiaceae",
        climate: {
          climateZones: [
            "humid_tropical",
            "subhumid_tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 20,
          temperatureMaxC: 32,
          notes:
            "Cassava is drought tolerant once established but performs best with warm temperatures and a full season.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate",
          phMin: 5,
          phMax: 7,
          notes:
            "Roots enlarge best in friable soil; soggy conditions increase deterioration and harvest damage.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Cassava tolerates dry spells but yield is better with adequate seasonal moisture and low waterlogging pressure.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "stem_cuttings",
          ],
          notes:
            "Plant with healthy 25 cm stem cuttings containing 5-7 nodes from mature stems.",
        },
        harvestWindow: {
          earliestDays: 270,
          latestDays: 360,
          seasons: [
            "rainfed_cycle",
            "dry_season_harvest",
          ],
          notes:
            "Starch and dry matter often peak around 9-12 months, though some varieties remain longer in the field.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "iita",
            sourceUrl:
              "https://biblio.iita.org/documents/U14ManAbassGrowingNothomDev.pdf-9664599408fadb7d773c23338e5a5a47.pdf",
            citation:
              "IITA cassava guide states optimum starch and dry matter yield is usually highest 9-12 months after planting, with some varieties maturing in 15-18 months.",
            notes:
              "Used for cassava lifecycle band.",
          }),
          buildBootstrapProvenance({
            sourceKey: "iita",
            sourceUrl:
              "https://biblio.iita.org/documents/U14ManAbassGrowingNothomDev.pdf-9664599408fadb7d773c23338e5a5a47.pdf",
            citation:
              "IITA cassava guide recommends 25 cm stem cuttings with 5-7 nodes taken from 10-12 month old mature plants.",
            notes:
              "Used for cassava propagation details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Cocoa",
      aliases: [
        "cocoa",
        "cacao",
        "theobroma cacao",
      ],
      lifecycle: {
        minDays: 1095,
        maxDays: 1825,
        phases: [
          "establishment",
          "canopy_development",
          "flowering",
          "pod_set",
          "pod_fill",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "cocoa",
        bootstrapGroup:
          "critical_crop",
      },
      profileDetails: {
        profileKind: "crop",
        category: "cash crop",
        variety: "",
        plantType: "tree",
        summary:
          "Perennial cocoa profile for shaded tropical production with multi-year establishment before commercial pod harvest.",
        scientificName:
          "Theobroma cacao",
        family: "Malvaceae",
        climate: {
          climateZones: [
            "humid_tropical",
          ],
          lightPreference:
            "partial shade to filtered sun",
          humidityPreference:
            "high",
          temperatureMinC: 18,
          temperatureMaxC: 32,
          rainfallMinMm: 1500,
          rainfallMaxMm: 2000,
          notes:
            "Cocoa performs best in hot, humid equatorial environments with evenly distributed rainfall and shade in early years.",
        },
        soil: {
          textures: [
            "loam",
            "clay loam",
          ],
          drainage:
            "good drainage with water retention",
          fertility:
            "high organic matter",
          phMin: 5,
          phMax: 7.5,
          notes:
            "Deep soil with coarse particles, nutrient reserves, and both drainage and moisture-holding capacity is preferred.",
        },
        water: {
          requirement: "high",
          irrigationNotes:
            "Cocoa is sensitive to soil water deficit; dry spells under 100 mm rainfall per month should stay under three months.",
          minimumPrecipitationMm: 1500,
          maximumPrecipitationMm: 2000,
        },
        propagation: {
          methods: [
            "seedling",
            "grafted_seedling",
            "budded_seedling",
          ],
          notes:
            "Nursery-raised seedlings or grafted planting material are used in commercial establishment programs.",
        },
        harvestWindow: {
          earliestDays: 1095,
          latestDays: 1825,
          seasons: [
            "main_crop",
            "mid_crop",
          ],
          notes:
            "Trees are perennial; first meaningful harvest usually follows multi-year establishment and then recurs seasonally.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "icco",
            sourceUrl:
              "https://www.icco.org/growing-cocoa/",
            citation:
              "ICCO growing cocoa guidance states cocoa grows best with 18-32 C temperatures, 1500-2000 mm annual rainfall, high humidity, shade in early years, and pH 5.0-7.5 soils.",
            notes:
              "Used for cocoa climate, soil, and water details.",
          }),
          buildBootstrapProvenance({
            sourceKey: "icco",
            sourceUrl:
              "https://www.icco.org/faq/",
            citation:
              "ICCO FAQ states cocoa grows best in tropical belts near the equator and needs protection from direct sunlight and excessive winds.",
            notes:
              "Used to reinforce cocoa environment and shade requirements.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Mango",
      aliases: [
        "mango",
        "mangoes",
        "mangifera indica",
      ],
      lifecycle: {
        minDays: 1095,
        maxDays: 1825,
        phases: [
          "establishment",
          "canopy_development",
          "flowering",
          "fruit_set",
          "fruit_development",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "mango",
        bootstrapGroup:
          "critical_fruit",
      },
      profileDetails: {
        profileKind: "fruit",
        category: "tropical fruit",
        variety: "",
        plantType: "tree",
        summary:
          "Tropical mango tree profile for orchard planning, with first bearing after establishment and 100-150 day fruit development after bloom.",
        scientificName:
          "Mangifera indica",
        family: "Anacardiaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 20,
          temperatureMaxC: 32,
          notes:
            "Warm, frost-free sites with dry weather during bloom improve fruit set.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
            "calcareous soil",
          ],
          drainage: "well-drained",
          fertility:
            "moderate",
          phMin: 5.5,
          phMax: 7.8,
          notes:
            "Mango tolerates both neutral and higher-pH calcareous soils when micronutrients are managed.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Water young trees regularly through establishment; mature trees need less frequent irrigation outside prolonged dry periods.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "grafted_seedling",
          ],
          notes:
            "Commercial orchards rely on grafted trees for earlier and more predictable bearing.",
        },
        harvestWindow: {
          earliestDays: 1095,
          latestDays: 1825,
          seasons: [
            "late_spring",
            "summer",
          ],
          notes:
            "First bearing typically begins in 3-5 years; individual fruits mature about 100-150 days after flowering.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://ask.ifas.ufl.edu/publication/MG216",
            citation:
              "UF/IFAS mango guidance states grafted trees begin to bear 3-5 years after planting and fruit take 100-150 days from flowering to maturity.",
            notes:
              "Used for mango establishment and fruiting-cycle timing.",
          }),
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://ask.ifas.ufl.edu/publication/MG216",
            citation:
              "UF/IFAS mango guidance recommends full sun, warm sites that do not flood, regular watering during establishment, and notes tolerance of high-pH soils via rootstock and micronutrient management.",
            notes:
              "Used for mango climate, water, and soil details.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Kent Mango",
      aliases: [
        "kent mango",
      ],
      lifecycle: {
        minDays: 1095,
        maxDays: 1825,
        phases: [
          "establishment",
          "canopy_development",
          "flowering",
          "fruit_set",
          "fruit_development",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "kent_mango",
        bootstrapGroup:
          "critical_fruit_variant",
      },
      profileDetails: {
        profileKind: "fruit",
        category: "tropical fruit",
        variety: "Kent",
        plantType: "tree",
        summary:
          "Popular commercial mango variety profile used for orchard planning where a late-season dessert mango is desired.",
        scientificName:
          "Mangifera indica",
        family: "Anacardiaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 20,
          temperatureMaxC: 32,
          notes:
            "Kent mango requires the same frost-free, sunny orchard conditions as other grafted mango cultivars.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
            "calcareous soil",
          ],
          drainage: "well-drained",
          fertility:
            "moderate",
          phMin: 5.5,
          phMax: 7.8,
          notes:
            "Nutrient and micronutrient management are important in calcareous soils.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Support establishment with regular irrigation, then reduce frequency for mature trees except in prolonged dry spells.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "grafted_seedling",
          ],
          notes:
            "Kent mango is typically propagated by grafting for true-to-type fruiting.",
        },
        harvestWindow: {
          earliestDays: 1095,
          latestDays: 1825,
          seasons: [
            "summer",
          ],
          notes:
            "Uses the same early bearing window as grafted mango trees with cultivar-dependent harvest timing.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://gardeningsolutions.ifas.ufl.edu/plants/edibles/fruits/mango.html",
            citation:
              "UF/IFAS Gardening Solutions lists mango as a full-sun tropical fruit tree and cites named cultivars including Kent for home and orchard planting.",
            notes:
              "Used to support cultivar availability and shared agronomy for Kent mango.",
          }),
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://ask.ifas.ufl.edu/publication/MG216",
            citation:
              "UF/IFAS mango production guidance provides 3-5 year bearing time and 100-150 day fruit development timing for grafted mango trees.",
            notes:
              "Used for Kent mango lifecycle timing.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Orange",
      aliases: [
        "orange",
        "sweet orange",
        "citrus sinensis",
      ],
      lifecycle: {
        minDays: 1460,
        maxDays: 1825,
        phases: [
          "establishment",
          "canopy_development",
          "flowering",
          "fruit_set",
          "fruit_development",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "orange",
        bootstrapGroup:
          "critical_fruit",
      },
      profileDetails: {
        profileKind: "fruit",
        category: "citrus",
        variety: "",
        plantType: "tree",
        summary:
          "Sweet orange profile for grafted orchard trees, with full-sun establishment and multi-year juvenile growth before bearing.",
        scientificName:
          "Citrus sinensis",
        family: "Rutaceae",
        climate: {
          climateZones: [
            "subtropical",
            "warm_temperate",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 15,
          temperatureMaxC: 32,
          notes:
            "Sweet oranges need frost-protected warm sites; cold snaps are a major limiting factor.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate",
          phMin: 6,
          phMax: 6.5,
          notes:
            "Keep root flare at soil level and avoid poorly drained frost-pocket sites.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Young citrus trees need consistent water during establishment and more frequent irrigation in hot dry periods.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "grafted_tree",
            "budded_tree",
          ],
          notes:
            "Commercial citrus is established from grafted nursery trees on selected rootstocks.",
        },
        harvestWindow: {
          earliestDays: 1460,
          latestDays: 1825,
          seasons: [
            "winter",
            "spring",
          ],
          notes:
            "Young grafted oranges generally need several years before flowering and fruiting, then harvest season varies by cultivar.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "clemson_extension",
            sourceUrl:
              "https://hgic.clemson.edu/factsheet/in-ground-citrus-production/",
            citation:
              "Clemson Extension states young grafted oranges must grow for about 5 years before they flower and produce fruit and recommends full sun, well-drained soil, and pH 6.0-6.5.",
            notes:
              "Used for orange lifecycle, site selection, and soil guidance.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Navel Orange",
      aliases: [
        "navel orange",
      ],
      lifecycle: {
        minDays: 1460,
        maxDays: 1825,
        phases: [
          "establishment",
          "canopy_development",
          "flowering",
          "fruit_set",
          "fruit_development",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "navel_orange",
        bootstrapGroup:
          "critical_fruit_variant",
      },
      profileDetails: {
        profileKind: "fruit",
        category: "citrus",
        variety: "Navel",
        plantType: "tree",
        summary:
          "Popular sweet orange cultivar profile for fresh-market navel production.",
        scientificName:
          "Citrus sinensis",
        family: "Rutaceae",
        climate: {
          climateZones: [
            "subtropical",
            "warm_temperate",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 15,
          temperatureMaxC: 32,
          notes:
            "Navel oranges share the same frost-sensitive citrus orchard requirements as other sweet oranges.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
          ],
          drainage: "well-drained",
          fertility:
            "moderate",
          phMin: 6,
          phMax: 6.5,
          notes:
            "Well-drained citrus soil and protected orchard placement improve survival and fruit quality.",
        },
        water: {
          requirement:
            "moderate",
          irrigationNotes:
            "Young trees need regular water until fully established.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "grafted_tree",
            "budded_tree",
          ],
          notes:
            "Navel oranges are propagated on rootstocks in nursery systems.",
        },
        harvestWindow: {
          earliestDays: 1460,
          latestDays: 1825,
          seasons: [
            "winter",
            "spring",
          ],
          notes:
            "Once bearing, navel harvest generally lands in the cool-season citrus window.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey:
              "clemson_extension",
            sourceUrl:
              "https://hgic.clemson.edu/factsheet/in-ground-citrus-production/",
            citation:
              "Clemson Extension citrus guidance provides the core juvenile period and site requirements for grafted oranges.",
            notes:
              "Used for navel orange orchard baseline.",
          }),
          buildBootstrapProvenance({
            sourceKey:
              "arizona_extension",
            sourceUrl:
              "https://extension.arizona.edu/publication/low-desert-citrus-varieties",
            citation:
              "University of Arizona citrus harvest tables include navel orange seasonal harvest timing in low-desert production.",
            notes:
              "Used to support the cool-season harvest expectation for navel oranges.",
            confidence: 0.9,
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "Pineapple",
      aliases: [
        "pineapple",
        "pineapples",
        "ananas comosus",
      ],
      lifecycle: {
        minDays: 540,
        maxDays: 730,
        phases: [
          "vegetative_growth",
          "flower_induction",
          "flowering",
          "fruit_development",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "pineapple",
        bootstrapGroup:
          "critical_fruit",
      },
      profileDetails: {
        profileKind: "fruit",
        category: "tropical fruit",
        variety: "",
        plantType: "herb",
        summary:
          "Pineapple profile for tropical field or garden systems with a long vegetative phase and a single primary fruit per plant.",
        scientificName:
          "Ananas comosus",
        family: "Bromeliaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 20,
          temperatureMaxC: 30,
          notes:
            "Pineapple growth slows below 15.5 C and above 32 C, and plants are frost sensitive.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
          ],
          drainage: "very well-drained",
          fertility:
            "moderate",
          phMin: 4.5,
          phMax: 6.5,
          notes:
            "Avoid long periods of high soil moisture to reduce root rot pressure.",
        },
        water: {
          requirement:
            "low to moderate",
          irrigationNotes:
            "Pineapple tolerates dry weather but fruits better with moisture support and well-drained soils.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "crown",
            "sucker",
            "slip",
          ],
          notes:
            "Field establishment commonly uses crowns, slips, or suckers rather than seed.",
        },
        harvestWindow: {
          earliestDays: 540,
          latestDays: 730,
          seasons: [
            "year_round",
          ],
          notes:
            "Planting to harvest varies by cultivar and climate; ratoon crops can follow the plant crop.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://ask.ifas.ufl.edu/publication/MG055",
            citation:
              "UF/IFAS pineapple guide states planting to harvest typically ranges 18-24 months and optimum growth is around 20-30 C.",
            notes:
              "Used for pineapple lifecycle and climate range.",
          }),
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://gardeningsolutions.ifas.ufl.edu/plants/edibles/fruits/pineapple/",
            citation:
              "UF/IFAS Gardening Solutions describes pineapple flowering and fruit development timing and notes a total wait of roughly 18-32 months depending on care and starting material.",
            notes:
              "Used for pineapple harvest timing notes and propagation context.",
          }),
        ],
      },
    }),
    buildBootstrapEntry({
      productName: "MD2 Pineapple",
      aliases: [
        "md2 pineapple",
        "gold pineapple",
      ],
      lifecycle: {
        minDays: 540,
        maxDays: 700,
        phases: [
          "vegetative_growth",
          "flower_induction",
          "flowering",
          "fruit_development",
          "harvest",
        ],
      },
      metadata: {
        bootstrapKey: "md2_pineapple",
        bootstrapGroup:
          "critical_fruit_variant",
      },
      profileDetails: {
        profileKind: "fruit",
        category: "tropical fruit",
        variety: "MD2",
        plantType: "herb",
        summary:
          "Commercial fresh-market pineapple cultivar profile for MD2 and similar modern sweet pineapple systems.",
        scientificName:
          "Ananas comosus",
        family: "Bromeliaceae",
        climate: {
          climateZones: [
            "subtropical",
            "tropical",
          ],
          lightPreference:
            "full sun",
          humidityPreference:
            "moderate",
          temperatureMinC: 20,
          temperatureMaxC: 30,
          notes:
            "MD2 performs best under warm frost-free conditions with good light and drainage.",
        },
        soil: {
          textures: [
            "sandy loam",
            "loam",
          ],
          drainage: "very well-drained",
          fertility:
            "moderate",
          phMin: 4.5,
          phMax: 6.5,
          notes:
            "Good drainage is critical to avoid root rot and protect fruit quality.",
        },
        water: {
          requirement:
            "low to moderate",
          irrigationNotes:
            "Moderate moisture is beneficial, but avoid long wet periods around the root zone.",
          minimumPrecipitationMm: null,
          maximumPrecipitationMm: null,
        },
        propagation: {
          methods: [
            "crown",
            "sucker",
            "slip",
          ],
          notes:
            "Commercial propagation uses vegetative planting material for uniform orchards.",
        },
        harvestWindow: {
          earliestDays: 540,
          latestDays: 700,
          seasons: [
            "year_round",
          ],
          notes:
            "MD2 is frequently managed for consistent commercial fresh-fruit harvest quality.",
        },
        sourceProvenance: [
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://ask.ifas.ufl.edu/publication/MG055",
            citation:
              "UF/IFAS pineapple guidance provides the core planting-to-harvest range and climate suitability used for MD2 planning.",
            notes:
              "Used for MD2 pineapple lifecycle baseline.",
          }),
          buildBootstrapProvenance({
            sourceKey: "uf_ifas",
            sourceUrl:
              "https://gardeningsolutions.ifas.ufl.edu/plants/edibles/fruits/pineapple/",
            citation:
              "UF/IFAS pineapple overview describes the single-fruit crop cycle and flowering-to-ripening sequence that apply to modern dessert pineapple cultivars.",
            notes:
              "Used for MD2 harvest-flow notes.",
            confidence: 0.9,
          }),
        ],
      },
    }),
  ]);

function buildVerifiedCropProfileBootstrap({
  domainContext = "farm",
} = {}) {
  return VERIFIED_CROP_PROFILE_BOOTSTRAP_ENTRIES.map(
    (entry) => ({
      ...entry,
      domainContext,
      metadata: {
        ...entry.metadata,
        bootstrapVersion:
          VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
      },
    }),
  );
}

module.exports = {
  VERIFIED_CROP_PROFILE_BOOTSTRAP_VERSION,
  VERIFIED_CROP_PROFILE_BOOTSTRAP_ENTRIES,
  buildVerifiedCropProfileBootstrap,
};
