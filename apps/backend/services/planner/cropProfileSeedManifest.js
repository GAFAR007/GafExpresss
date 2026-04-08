/**
 * apps/backend/services/planner/cropProfileSeedManifest.js
 * --------------------------------------------------------
 * WHAT:
 * - Generated seed manifest for crop/plant/fruit profile expansion.
 *
 * WHY:
 * - Production planning needs a broad curation queue that can be enriched from vetted sources.
 * - Seed entries should be easy to preload while staying clearly separate from verified crop profiles.
 *
 * HOW:
 * - Uses curated base crop + fruit seeds.
 * - Expands each base seed into multiple canonical/popular variant targets.
 * - Marks every record as `seed_manifest` so planner search can ignore it until verified data is imported.
 */

const {
  buildCropProfileProvenanceEntry,
} = require("./cropProfileSources");

const CROP_PROFILE_SEED_MANIFEST_VERSION =
  "2026-03-v1";
const REQUIRED_CROP_TARGET_COUNT = 500;
const REQUIRED_FRUIT_TARGET_COUNT = 250;

const GENERIC_CROP_VARIANTS = Object.freeze([
  { label: "Core", suffix: "" },
  { label: "Common", suffix: "Common" },
  { label: "Early", suffix: "Early" },
  { label: "Late", suffix: "Late" },
  {
    label: "Drought-tolerant",
    suffix: "Drought-tolerant",
  },
  {
    label: "High-yield",
    suffix: "High-yield",
  },
  {
    label: "Market-popular",
    suffix: "Market-popular",
  },
]);

const GENERIC_FRUIT_VARIANTS = Object.freeze([
  { label: "Core", suffix: "" },
  { label: "Common", suffix: "Common" },
  { label: "Premium", suffix: "Premium" },
  {
    label: "Market-popular",
    suffix: "Market-popular",
  },
  {
    label: "Long-shelf-life",
    suffix: "Long-shelf-life",
  },
]);

const CROP_BASE_SEEDS = Object.freeze([
  { baseName: "Tomato", profileKind: "crop", category: "vegetable", plantType: "vine", aliases: ["tomato", "tomatoes"] },
  { baseName: "Pepper", profileKind: "crop", category: "vegetable", plantType: "shrub", aliases: ["pepper", "peppers", "capsicum"] },
  { baseName: "Onion", profileKind: "crop", category: "vegetable", plantType: "herb", aliases: ["onion", "onions"] },
  { baseName: "Corn", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["corn", "maize"] },
  { baseName: "Beans", profileKind: "crop", category: "legume", plantType: "vine", aliases: ["beans", "bean"] },
  { baseName: "Rice", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["rice", "paddy"] },
  { baseName: "Yam", profileKind: "crop", category: "tuber", plantType: "vine", aliases: ["yam", "yams"] },
  { baseName: "Cassava", profileKind: "crop", category: "tuber", plantType: "shrub", aliases: ["cassava", "manioc", "yuca"] },
  { baseName: "Cocoa", profileKind: "crop", category: "cash crop", plantType: "tree", aliases: ["cocoa", "cacao"] },
  { baseName: "Potato", profileKind: "crop", category: "tuber", plantType: "herb", aliases: ["potato", "potatoes"] },
  { baseName: "Sweet Potato", profileKind: "crop", category: "tuber", plantType: "vine", aliases: ["sweet potato", "sweet potatoes"] },
  { baseName: "Carrot", profileKind: "crop", category: "root", plantType: "herb", aliases: ["carrot", "carrots"] },
  { baseName: "Cabbage", profileKind: "crop", category: "leafy vegetable", plantType: "herb", aliases: ["cabbage"] },
  { baseName: "Lettuce", profileKind: "crop", category: "leafy vegetable", plantType: "herb", aliases: ["lettuce"] },
  { baseName: "Spinach", profileKind: "crop", category: "leafy vegetable", plantType: "herb", aliases: ["spinach"] },
  { baseName: "Okra", profileKind: "crop", category: "vegetable", plantType: "shrub", aliases: ["okra"] },
  { baseName: "Eggplant", profileKind: "crop", category: "vegetable", plantType: "shrub", aliases: ["eggplant", "aubergine"] },
  { baseName: "Cucumber", profileKind: "crop", category: "vegetable", plantType: "vine", aliases: ["cucumber", "cucumbers"] },
  { baseName: "Pumpkin", profileKind: "crop", category: "cucurbit", plantType: "vine", aliases: ["pumpkin", "pumpkins"] },
  { baseName: "Watermelon", profileKind: "crop", category: "cucurbit", plantType: "vine", aliases: ["watermelon", "watermelons"] },
  { baseName: "Melon", profileKind: "crop", category: "cucurbit", plantType: "vine", aliases: ["melon", "melons"] },
  { baseName: "Groundnut", profileKind: "crop", category: "legume", plantType: "herb", aliases: ["groundnut", "peanut", "peanuts"] },
  { baseName: "Soybean", profileKind: "crop", category: "legume", plantType: "herb", aliases: ["soybean", "soybeans"] },
  { baseName: "Cowpea", profileKind: "crop", category: "legume", plantType: "vine", aliases: ["cowpea", "cowpeas"] },
  { baseName: "Sorghum", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["sorghum"] },
  { baseName: "Millet", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["millet"] },
  { baseName: "Wheat", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["wheat"] },
  { baseName: "Barley", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["barley"] },
  { baseName: "Oat", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["oat", "oats"] },
  { baseName: "Rye", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["rye"] },
  { baseName: "Teff", profileKind: "crop", category: "grain", plantType: "grass", aliases: ["teff"] },
  { baseName: "Chickpea", profileKind: "crop", category: "legume", plantType: "herb", aliases: ["chickpea", "chickpeas"] },
  { baseName: "Pigeon Pea", profileKind: "crop", category: "legume", plantType: "shrub", aliases: ["pigeon pea", "pigeon peas"] },
  { baseName: "Lentil", profileKind: "crop", category: "legume", plantType: "herb", aliases: ["lentil", "lentils"] },
  { baseName: "Pea", profileKind: "crop", category: "legume", plantType: "vine", aliases: ["pea", "peas"] },
  { baseName: "Sesame", profileKind: "crop", category: "oilseed", plantType: "herb", aliases: ["sesame"] },
  { baseName: "Sunflower", profileKind: "crop", category: "oilseed", plantType: "herb", aliases: ["sunflower"] },
  { baseName: "Cotton", profileKind: "crop", category: "fiber", plantType: "shrub", aliases: ["cotton"] },
  { baseName: "Sugarcane", profileKind: "crop", category: "cash crop", plantType: "grass", aliases: ["sugarcane"] },
  { baseName: "Coffee", profileKind: "crop", category: "cash crop", plantType: "shrub", aliases: ["coffee"] },
  { baseName: "Tea", profileKind: "crop", category: "beverage crop", plantType: "shrub", aliases: ["tea"] },
  { baseName: "Ginger", profileKind: "crop", category: "spice", plantType: "herb", aliases: ["ginger"] },
  { baseName: "Turmeric", profileKind: "crop", category: "spice", plantType: "herb", aliases: ["turmeric"] },
  { baseName: "Garlic", profileKind: "crop", category: "spice", plantType: "herb", aliases: ["garlic"] },
  { baseName: "Celery", profileKind: "crop", category: "vegetable", plantType: "herb", aliases: ["celery"] },
  { baseName: "Broccoli", profileKind: "crop", category: "vegetable", plantType: "herb", aliases: ["broccoli"] },
  { baseName: "Cauliflower", profileKind: "crop", category: "vegetable", plantType: "herb", aliases: ["cauliflower"] },
  { baseName: "Beetroot", profileKind: "crop", category: "root", plantType: "herb", aliases: ["beetroot", "beet"] },
  { baseName: "Radish", profileKind: "crop", category: "root", plantType: "herb", aliases: ["radish"] },
  { baseName: "Turnip", profileKind: "crop", category: "root", plantType: "herb", aliases: ["turnip"] },
  { baseName: "Leek", profileKind: "crop", category: "vegetable", plantType: "herb", aliases: ["leek"] },
  { baseName: "Scallion", profileKind: "crop", category: "vegetable", plantType: "herb", aliases: ["scallion", "spring onion"] },
  { baseName: "Zucchini", profileKind: "crop", category: "vegetable", plantType: "vine", aliases: ["zucchini", "courgette"] },
  { baseName: "Squash", profileKind: "crop", category: "vegetable", plantType: "vine", aliases: ["squash"] },
  { baseName: "Plantain", profileKind: "plant", category: "staple crop", plantType: "herb", aliases: ["plantain", "plantains"] },
  { baseName: "Taro", profileKind: "crop", category: "tuber", plantType: "herb", aliases: ["taro"] },
  { baseName: "Cocoyam", profileKind: "crop", category: "tuber", plantType: "herb", aliases: ["cocoyam"] },
  { baseName: "Kale", profileKind: "crop", category: "leafy vegetable", plantType: "herb", aliases: ["kale"] },
  { baseName: "Amaranth", profileKind: "crop", category: "leafy vegetable", plantType: "herb", aliases: ["amaranth"] },
  { baseName: "Jute Mallow", profileKind: "crop", category: "leafy vegetable", plantType: "herb", aliases: ["jute mallow", "ewedu", "molokhia"] },
  { baseName: "Basil", profileKind: "plant", category: "herb", plantType: "herb", aliases: ["basil"] },
  { baseName: "Mint", profileKind: "plant", category: "herb", plantType: "herb", aliases: ["mint"] },
  { baseName: "Rosemary", profileKind: "plant", category: "herb", plantType: "shrub", aliases: ["rosemary"] },
  { baseName: "Thyme", profileKind: "plant", category: "herb", plantType: "shrub", aliases: ["thyme"] },
  { baseName: "Parsley", profileKind: "plant", category: "herb", plantType: "herb", aliases: ["parsley"] },
  { baseName: "Coriander", profileKind: "plant", category: "herb", plantType: "herb", aliases: ["coriander", "cilantro"] },
  { baseName: "Dill", profileKind: "plant", category: "herb", plantType: "herb", aliases: ["dill"] },
  { baseName: "Vanilla", profileKind: "plant", category: "spice", plantType: "vine", aliases: ["vanilla"] },
  { baseName: "Black Pepper", profileKind: "plant", category: "spice", plantType: "vine", aliases: ["black pepper", "peppercorn"] },
  { baseName: "Quinoa", profileKind: "crop", category: "grain", plantType: "herb", aliases: ["quinoa"] },
  { baseName: "Flax", profileKind: "crop", category: "oilseed", plantType: "herb", aliases: ["flax", "linseed"] },
  { baseName: "Canola", profileKind: "crop", category: "oilseed", plantType: "herb", aliases: ["canola", "rapeseed"] },
  { baseName: "Mustard", profileKind: "crop", category: "oilseed", plantType: "herb", aliases: ["mustard"] },
  { baseName: "Moringa", profileKind: "plant", category: "leafy tree crop", plantType: "tree", aliases: ["moringa", "drumstick tree"] },
  { baseName: "Aloe Vera", profileKind: "plant", category: "medicinal plant", plantType: "succulent", aliases: ["aloe vera", "aloe"] },
]);

const FRUIT_BASE_SEEDS = Object.freeze([
  { baseName: "Mango", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["mango", "mangoes"] },
  { baseName: "Orange", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["orange", "oranges"] },
  { baseName: "Pineapple", profileKind: "fruit", category: "tropical fruit", plantType: "herb", aliases: ["pineapple", "pineapples"] },
  { baseName: "Banana", profileKind: "fruit", category: "tropical fruit", plantType: "herb", aliases: ["banana", "bananas"] },
  { baseName: "Apple", profileKind: "fruit", category: "pome fruit", plantType: "tree", aliases: ["apple", "apples"] },
  { baseName: "Pear", profileKind: "fruit", category: "pome fruit", plantType: "tree", aliases: ["pear", "pears"] },
  { baseName: "Peach", profileKind: "fruit", category: "stone fruit", plantType: "tree", aliases: ["peach", "peaches"] },
  { baseName: "Nectarine", profileKind: "fruit", category: "stone fruit", plantType: "tree", aliases: ["nectarine", "nectarines"] },
  { baseName: "Plum", profileKind: "fruit", category: "stone fruit", plantType: "tree", aliases: ["plum", "plums"] },
  { baseName: "Apricot", profileKind: "fruit", category: "stone fruit", plantType: "tree", aliases: ["apricot", "apricots"] },
  { baseName: "Cherry", profileKind: "fruit", category: "stone fruit", plantType: "tree", aliases: ["cherry", "cherries"] },
  { baseName: "Grape", profileKind: "fruit", category: "berry", plantType: "vine", aliases: ["grape", "grapes"] },
  { baseName: "Strawberry", profileKind: "fruit", category: "berry", plantType: "herb", aliases: ["strawberry", "strawberries"] },
  { baseName: "Blueberry", profileKind: "fruit", category: "berry", plantType: "shrub", aliases: ["blueberry", "blueberries"] },
  { baseName: "Raspberry", profileKind: "fruit", category: "berry", plantType: "shrub", aliases: ["raspberry", "raspberries"] },
  { baseName: "Blackberry", profileKind: "fruit", category: "berry", plantType: "shrub", aliases: ["blackberry", "blackberries"] },
  { baseName: "Lemon", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["lemon", "lemons"] },
  { baseName: "Lime", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["lime", "limes"] },
  { baseName: "Grapefruit", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["grapefruit", "grapefruits"] },
  { baseName: "Mandarin", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["mandarin", "mandarins"] },
  { baseName: "Tangerine", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["tangerine", "tangerines"] },
  { baseName: "Guava", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["guava", "guavas"] },
  { baseName: "Papaya", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["papaya", "pawpaw"] },
  { baseName: "Avocado", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["avocado", "avocados"] },
  { baseName: "Coconut", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["coconut", "coconuts"] },
  { baseName: "Pomegranate", profileKind: "fruit", category: "specialty fruit", plantType: "tree", aliases: ["pomegranate", "pomegranates"] },
  { baseName: "Passion Fruit", profileKind: "fruit", category: "tropical fruit", plantType: "vine", aliases: ["passion fruit", "passionfruit"] },
  { baseName: "Dragon Fruit", profileKind: "fruit", category: "tropical fruit", plantType: "cactus", aliases: ["dragon fruit", "pitaya"] },
  { baseName: "Soursop", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["soursop", "graviola"] },
  { baseName: "Custard Apple", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["custard apple", "sugar apple"] },
  { baseName: "Jackfruit", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["jackfruit"] },
  { baseName: "Breadfruit", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["breadfruit"] },
  { baseName: "Fig", profileKind: "fruit", category: "specialty fruit", plantType: "tree", aliases: ["fig", "figs"] },
  { baseName: "Date", profileKind: "fruit", category: "specialty fruit", plantType: "tree", aliases: ["date", "dates"] },
  { baseName: "Olive", profileKind: "fruit", category: "specialty fruit", plantType: "tree", aliases: ["olive", "olives"] },
  { baseName: "Kiwi", profileKind: "fruit", category: "specialty fruit", plantType: "vine", aliases: ["kiwi", "kiwifruit"] },
  { baseName: "Lychee", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["lychee", "litchi"] },
  { baseName: "Longan", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["longan"] },
  { baseName: "Rambutan", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["rambutan"] },
  { baseName: "Star Fruit", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["star fruit", "carambola"] },
  { baseName: "Mulberry", profileKind: "fruit", category: "berry", plantType: "tree", aliases: ["mulberry", "mulberries"] },
  { baseName: "Cranberry", profileKind: "fruit", category: "berry", plantType: "shrub", aliases: ["cranberry", "cranberries"] },
  { baseName: "Gooseberry", profileKind: "fruit", category: "berry", plantType: "shrub", aliases: ["gooseberry", "gooseberries"] },
  { baseName: "Persimmon", profileKind: "fruit", category: "specialty fruit", plantType: "tree", aliases: ["persimmon", "persimmons"] },
  { baseName: "Pomelo", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["pomelo", "pummelo"] },
  { baseName: "Kumquat", profileKind: "fruit", category: "citrus", plantType: "tree", aliases: ["kumquat", "kumquats"] },
  { baseName: "Quince", profileKind: "fruit", category: "pome fruit", plantType: "tree", aliases: ["quince", "quinces"] },
  { baseName: "Water Apple", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["water apple", "rose apple"] },
  { baseName: "Sapodilla", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["sapodilla", "sapota"] },
  { baseName: "Cashew Apple", profileKind: "fruit", category: "tropical fruit", plantType: "tree", aliases: ["cashew apple", "cashew"] },
]);

const CUSTOM_CROP_VARIANTS =
  Object.freeze({
    Tomato: ["Tomato", "Roma Tomato", "Cherry Tomato", "Beefsteak Tomato", "Plum Tomato", "Heirloom Tomato", "Grape Tomato"],
    Pepper: ["Pepper", "Bell Pepper", "Scotch Bonnet Pepper", "Jalapeno Pepper", "Cayenne Pepper", "Bird's Eye Pepper", "Sweet Pepper"],
    Onion: ["Onion", "Red Onion", "White Onion", "Yellow Onion", "Sweet Onion", "Spring Onion", "Shallot Onion"],
    Corn: ["Corn", "Sweet Corn", "Dent Corn", "Flint Corn", "Popcorn", "Baby Corn", "White Corn"],
    Beans: ["Beans", "Cowpea Bean", "Kidney Bean", "Black Bean", "Navy Bean", "Soybean Bean", "Green Bean"],
    Rice: ["Rice", "Lowland Rice", "Upland Rice", "Long Grain Rice", "Short Grain Rice", "Jasmine Rice", "Basmati Rice"],
    Yam: ["Yam", "White Yam", "Yellow Yam", "Water Yam", "Purple Yam", "Guinea Yam", "Trifoliate Yam"],
    Cassava: ["Cassava", "Sweet Cassava", "Bitter Cassava", "White Cassava", "Yellow Cassava", "Early Cassava", "High-starch Cassava"],
    Cocoa: ["Cocoa", "Amelonado Cocoa", "Forastero Cocoa", "Criollo Cocoa", "Trinitario Cocoa", "Hybrid Cocoa", "Fine Flavor Cocoa"],
  });

const CUSTOM_FRUIT_VARIANTS =
  Object.freeze({
    Mango: ["Mango", "Kent Mango", "Keitt Mango", "Tommy Atkins Mango", "Ataulfo Mango"],
    Orange: ["Orange", "Navel Orange", "Valencia Orange", "Blood Orange", "Sweet Orange"],
    Pineapple: ["Pineapple", "Smooth Cayenne Pineapple", "MD2 Pineapple", "Sugarloaf Pineapple", "Queen Pineapple"],
    Banana: ["Banana", "Cavendish Banana", "Lady Finger Banana", "Red Banana", "Cooking Banana"],
    Apple: ["Apple", "Gala Apple", "Fuji Apple", "Granny Smith Apple", "Red Delicious Apple"],
    Grape: ["Grape", "Table Grape", "Seedless Grape", "Red Grape", "White Grape"],
    Avocado: ["Avocado", "Hass Avocado", "Fuerte Avocado", "Reed Avocado", "Bacon Avocado"],
    Guava: ["Guava", "White Guava", "Pink Guava", "Apple Guava", "Tropical Guava"],
    Papaya: ["Papaya", "Solo Papaya", "Red Lady Papaya", "Maradol Papaya", "Sunrise Papaya"],
    Coconut: ["Coconut", "Tall Coconut", "Dwarf Coconut", "Green Coconut", "Hybrid Coconut"],
  });

function buildGenericVariantEntries(
  baseName,
  variants,
) {
  return variants.map((variant) => ({
    productName:
      variant.suffix ?
        `${baseName} (${variant.suffix})`
      : baseName,
    variety:
      variant.label === "Core" ?
        ""
      : variant.label,
  }));
}

function buildSeedVariantEntries(seed) {
  const customVariants =
    seed.profileKind === "fruit" ?
      CUSTOM_FRUIT_VARIANTS[
        seed.baseName
      ]
    : CUSTOM_CROP_VARIANTS[
        seed.baseName
      ];
  if (
    Array.isArray(customVariants) &&
    customVariants.length > 0
  ) {
    return customVariants.map(
      (productName, index) => ({
        productName,
        variety:
          index === 0 ?
            ""
          : productName
              .replace(
                new RegExp(
                  `^${seed.baseName}\\s*`,
                  "i",
                ),
                "",
              )
              .trim() || productName,
      }),
    );
  }

  return buildGenericVariantEntries(
    seed.baseName,
    seed.profileKind === "fruit" ?
      GENERIC_FRUIT_VARIANTS
    : GENERIC_CROP_VARIANTS,
  );
}

function buildSeedProfileSummary(seed) {
  return [
    `${seed.baseName} ${seed.profileKind} seed target.`,
    "Await vetted source import before planner verification.",
  ].join(" ");
}

function buildCropProfileSeedManifest({
  domainContext = "farm",
} = {}) {
  const manifestEntries = [
    ...CROP_BASE_SEEDS.flatMap((seed) =>
      buildSeedVariantEntries(seed).map(
        (variantEntry) => ({
          productName:
            variantEntry.productName,
          cropSubtype: "",
          domainContext,
          aliases: [
            seed.baseName,
            ...(seed.aliases || []),
          ],
          metadata: {
            manifestVersion:
              CROP_PROFILE_SEED_MANIFEST_VERSION,
            seedGroup: "crop_or_plant",
            baseName: seed.baseName,
            variantLabel:
              variantEntry.variety || "Core",
            importTargetSources: [
              "fao_ecocrop",
              "world_flora_online",
              "usda_grin",
              "trefle",
              "geoglam",
            ],
          },
          profileDetails: {
            profileKind:
              seed.profileKind,
            category: seed.category,
            variety:
              variantEntry.variety,
            plantType: seed.plantType,
            summary:
              buildSeedProfileSummary(seed),
            scientificName: "",
            family: "",
            verificationStatus:
              "seed_manifest",
            lifecycleStatus:
              "missing",
            climate: {},
            soil: {},
            water: {},
            propagation: {},
            harvestWindow: {},
            sourceProvenance: [
              buildCropProfileProvenanceEntry(
                {
                  sourceKey:
                    "manifest_seed",
                  citation:
                    "Generated crop profile seed manifest target.",
                  notes:
                    `Manifest ${CROP_PROFILE_SEED_MANIFEST_VERSION} queued for vetted-source enrichment.`,
                  confidence: 0.4,
                  verificationStatus:
                    "seed_manifest",
                },
              ),
            ],
          },
        }),
      ),
    ),
    ...FRUIT_BASE_SEEDS.flatMap((seed) =>
      buildSeedVariantEntries(seed).map(
        (variantEntry) => ({
          productName:
            variantEntry.productName,
          cropSubtype: "",
          domainContext,
          aliases: [
            seed.baseName,
            ...(seed.aliases || []),
          ],
          metadata: {
            manifestVersion:
              CROP_PROFILE_SEED_MANIFEST_VERSION,
            seedGroup: "fruit",
            baseName: seed.baseName,
            variantLabel:
              variantEntry.variety || "Core",
            importTargetSources: [
              "world_flora_online",
              "usda_grin",
              "trefle",
            ],
          },
          profileDetails: {
            profileKind:
              seed.profileKind,
            category: seed.category,
            variety:
              variantEntry.variety,
            plantType: seed.plantType,
            summary:
              buildSeedProfileSummary(seed),
            scientificName: "",
            family: "",
            verificationStatus:
              "seed_manifest",
            lifecycleStatus:
              "missing",
            climate: {},
            soil: {},
            water: {},
            propagation: {},
            harvestWindow: {},
            sourceProvenance: [
              buildCropProfileProvenanceEntry(
                {
                  sourceKey:
                    "manifest_seed",
                  citation:
                    "Generated fruit profile seed manifest target.",
                  notes:
                    `Manifest ${CROP_PROFILE_SEED_MANIFEST_VERSION} queued for vetted-source enrichment.`,
                  confidence: 0.4,
                  verificationStatus:
                    "seed_manifest",
                },
              ),
            ],
          },
        }),
      ),
    ),
  ];

  const cropTargetCount =
    manifestEntries.filter(
      (entry) =>
        entry.profileDetails
          ?.profileKind !== "fruit",
    ).length;
  const fruitTargetCount =
    manifestEntries.filter(
      (entry) =>
        entry.profileDetails
          ?.profileKind === "fruit",
    ).length;

  if (
    cropTargetCount <
      REQUIRED_CROP_TARGET_COUNT ||
    fruitTargetCount <
      REQUIRED_FRUIT_TARGET_COUNT
  ) {
    throw new Error(
      `Seed manifest is undersized. Crops/plants=${cropTargetCount}, fruits=${fruitTargetCount}.`,
    );
  }

  return manifestEntries;
}

module.exports = {
  CROP_PROFILE_SEED_MANIFEST_VERSION,
  REQUIRED_CROP_TARGET_COUNT,
  REQUIRED_FRUIT_TARGET_COUNT,
  CROP_BASE_SEEDS,
  FRUIT_BASE_SEEDS,
  buildCropProfileSeedManifest,
};
