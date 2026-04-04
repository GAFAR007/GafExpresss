/**
 * services/product_ai.service.js
 * ------------------------------
 * WHAT:
 * - AI draft generator for product details and product taxonomy.
 *
 * WHY:
 * - Keeps AI prompt + parsing logic centralized and testable.
 * - Prevents controllers from handling raw AI responses.
 *
 * HOW:
 * - Builds a strict JSON prompt for the AI provider.
 * - Parses and normalizes the JSON output.
 * - Returns a safe draft payload for UI autofill.
 */

const debug = require('../utils/debug');
const { createAiChatCompletion } = require('./ai.service');
const {
  normalizeOptionalProductText,
  sanitizeProductTaxonomyFields,
  sanitizeProductSellingFields,
} = require('../utils/product_taxonomy');

// WHY: Centralize logging labels for AI draft generation.
const LOG_TAG = 'PRODUCT_AI';
const LOG_START = 'product draft start';
const LOG_SUCCESS = 'product draft success';
const LOG_ERROR = 'product draft error';

// WHY: Keep AI intent values consistent in AI logs.
const AI_OPERATION = 'ProductDraft';
const AI_INTENT = 'generate product draft';
const AI_SOURCE = 'backend';

// WHY: Enforce strict JSON output to reduce parsing errors.
const SYSTEM_PROMPT =
  'You are a product drafting assistant. ' +
  'Return ONLY valid JSON with no markdown, no code fences, and no extra text.';

// WHY: Schema hint keeps output predictable and short.
const DRAFT_SCHEMA_HINT =
  'Return a single JSON object with keys: name, description, category, subcategory, brand, sellingOptions, priceNgn, stock.';

// WHY: Guide AI toward the richer retail taxonomy now used by the UI.
const TAXONOMY_HINT =
  'Choose a broad commerce category and a specific subcategory. ' +
  'Use one of these categories and subcategories when possible: ' +
  'Fashion & Apparel (Tops, T-Shirts, Hoodies, Shirts, Polos, Jeans, Trousers, Shorts, Outerwear); ' +
  'Footwear (Sneakers, Running Shoes, Boots, Loafers, Sandals, Heels, Slippers, School Shoes); ' +
  'Farm & Agro (Grains & Cereals, Legumes, Tubers, Fruits, Vegetables, Herbs & Spices, Seeds & Seedlings, Fertilizers, Farm Tools, Animal Feed); ' +
  'Electronics & Tech (Phones, Laptops, Tablets, Headphones, Smart Watches, Gaming, Cameras, Accessories); ' +
  'Home & Kitchen (Furniture, Decor, Bedding, Cookware, Appliances, Storage, Cleaning Supplies); ' +
  'Beauty & Personal Care (Skincare, Makeup, Haircare, Fragrances, Grooming, Wellness); ' +
  'Sports & Outdoor (Gym Wear, Running Gear, Camping Gear, Bikes, Balls, Protective Gear); ' +
  'Kids & Baby (Baby Clothing, Kids Clothing, Shoes, Toys, Diapers, Feeding Essentials); ' +
  'Books & Office (Books, Stationery, Printers, Office Chairs, Desk Accessories). ' +
  'If the request is clearly a crop, produce item, grain, legume, vegetable, fruit, herb, tuber, fertilizer, farm tool, seedling, or animal feed, set category to Farm & Agro and infer one of those Farm & Agro subcategories. ' +
  'Return sellingOptions as an array of objects shaped like { packageType, quantity, measurementUnit, isDefault }. ' +
  'Examples: Bag of 5 kg rice, Bag of 20 kg rice, Bag of 25 kg beans, Basket of 5 kg pepper, Carton of 10 kg pepper, Piece of 1 piece t-shirt, Bundle of 3 pieces cloth. ' +
  'Use exactly one sellingOptions item with isDefault true. ' +
  'Do not invent or autofill brand; return brand as an empty string unless the user explicitly provides one and insists on keeping it. ' +
  'Return priceNgn and stock as plain numbers.';

// WHY: Defaults ensure drafts remain usable when AI output is incomplete.
const DEFAULT_NAME = 'New product';
const DEFAULT_DESCRIPTION = '';
const DEFAULT_PRICE_NGN = 0;
const DEFAULT_STOCK = 0;
const DEFAULT_CATEGORY = 'Fashion & Apparel';
const DEFAULT_SUBCATEGORY = 'Tops';
const DEFAULT_BRAND = '';
const DEFAULT_SELLING_OPTIONS = [
  {
    packageType: 'Piece',
    quantity: 1,
    measurementUnit: 'piece',
    isDefault: true,
  },
];
const DEFAULT_SELLING_UNITS = ['Piece'];

const FALLBACK_CATEGORY_BY_SUBCATEGORY = {
  tops: 'Fashion & Apparel',
  't-shirt': 'Fashion & Apparel',
  't-shirts': 'Fashion & Apparel',
  tshirt: 'Fashion & Apparel',
  tshirts: 'Fashion & Apparel',
  hoodies: 'Fashion & Apparel',
  sweatshirt: 'Fashion & Apparel',
  sweatshirts: 'Fashion & Apparel',
  shirts: 'Fashion & Apparel',
  polos: 'Fashion & Apparel',
  jeans: 'Fashion & Apparel',
  chinos: 'Fashion & Apparel',
  sweatpants: 'Fashion & Apparel',
  trousers: 'Fashion & Apparel',
  shorts: 'Fashion & Apparel',
  outerwear: 'Fashion & Apparel',
  sneakers: 'Footwear',
  'running shoes': 'Footwear',
  boots: 'Footwear',
  loafers: 'Footwear',
  sandals: 'Footwear',
  heels: 'Footwear',
  slippers: 'Footwear',
  'school shoes': 'Footwear',
  phones: 'Electronics & Tech',
  smartphones: 'Electronics & Tech',
  laptops: 'Electronics & Tech',
  tablets: 'Electronics & Tech',
  headphones: 'Electronics & Tech',
  'smart watches': 'Electronics & Tech',
  gaming: 'Electronics & Tech',
  cameras: 'Electronics & Tech',
  accessories: 'Electronics & Tech',
  monitors: 'Electronics & Tech',
  rice: 'Farm & Agro',
  'grains & cereals': 'Farm & Agro',
  legumes: 'Farm & Agro',
  tubers: 'Farm & Agro',
  fruits: 'Farm & Agro',
  vegetables: 'Farm & Agro',
  'herbs & spices': 'Farm & Agro',
  'seeds & seedlings': 'Farm & Agro',
  'farm inputs': 'Farm & Agro',
  fertilizers: 'Farm & Agro',
  'farm tools': 'Farm & Agro',
  'animal feed': 'Farm & Agro',
  seeds: 'Farm & Agro',
  fertilizer: 'Farm & Agro',
  produce: 'Farm & Agro',
  livestock: 'Farm & Agro',
  furniture: 'Home & Kitchen',
  decor: 'Home & Kitchen',
  bedding: 'Home & Kitchen',
  cookware: 'Home & Kitchen',
  appliances: 'Home & Kitchen',
  storage: 'Home & Kitchen',
  'cleaning supplies': 'Home & Kitchen',
  skincare: 'Beauty & Personal Care',
  makeup: 'Beauty & Personal Care',
  haircare: 'Beauty & Personal Care',
  fragrances: 'Beauty & Personal Care',
  grooming: 'Beauty & Personal Care',
  wellness: 'Beauty & Personal Care',
  'gym wear': 'Sports & Outdoor',
  'running gear': 'Sports & Outdoor',
  'camping gear': 'Sports & Outdoor',
  bikes: 'Sports & Outdoor',
  balls: 'Sports & Outdoor',
  'protective gear': 'Sports & Outdoor',
  'baby clothing': 'Kids & Baby',
  'kids clothing': 'Kids & Baby',
  shoes: 'Kids & Baby',
  toys: 'Kids & Baby',
  diapers: 'Kids & Baby',
  'feeding essentials': 'Kids & Baby',
  books: 'Books & Office',
  stationery: 'Books & Office',
  printers: 'Books & Office',
  'office chairs': 'Books & Office',
  'desk accessories': 'Books & Office',
};

const FALLBACK_SUBCATEGORY_BY_CATEGORY = {
  'Fashion & Apparel': 'Tops',
  Footwear: 'Sneakers',
  'Farm & Agro': 'Grains & Cereals',
  'Electronics & Tech': 'Phones',
  'Home & Kitchen': 'Furniture',
  'Beauty & Personal Care': 'Skincare',
  'Sports & Outdoor': 'Gym Wear',
  'Kids & Baby': 'Baby Clothing',
  'Books & Office': 'Books',
};

const FALLBACK_SUBCATEGORY_BY_KEYWORD = {
  't-shirts': 'T-Shirts',
  't-shirt': 'T-Shirts',
  tshirts: 'T-Shirts',
  tshirt: 'T-Shirts',
  sweatshirts: 'Hoodies',
  sweatshirt: 'Hoodies',
  hoodies: 'Hoodies',
  hoodie: 'Hoodies',
  shirts: 'Shirts',
  shirt: 'Shirts',
  polos: 'Polos',
  polo: 'Polos',
  jeans: 'Jeans',
  jean: 'Jeans',
  trousers: 'Trousers',
  trouser: 'Trousers',
  chinos: 'Trousers',
  chino: 'Trousers',
  sweatpants: 'Trousers',
  shorts: 'Shorts',
  outerwear: 'Outerwear',
  tops: 'Tops',
  top: 'Tops',
  sneakers: 'Sneakers',
  sneaker: 'Sneakers',
  'running shoes': 'Running Shoes',
  'running shoe': 'Running Shoes',
  boots: 'Boots',
  boot: 'Boots',
  loafers: 'Loafers',
  loafer: 'Loafers',
  sandals: 'Sandals',
  sandal: 'Sandals',
  heels: 'Heels',
  heel: 'Heels',
  slippers: 'Slippers',
  slipper: 'Slippers',
  'school shoes': 'School Shoes',
  'school shoe': 'School Shoes',
  bean: 'Legumes',
  beans: 'Legumes',
  cowpea: 'Legumes',
  soybean: 'Legumes',
  soybeans: 'Legumes',
  groundnut: 'Legumes',
  rice: 'Grains & Cereals',
  maize: 'Grains & Cereals',
  corn: 'Grains & Cereals',
  wheat: 'Grains & Cereals',
  millet: 'Grains & Cereals',
  sorghum: 'Grains & Cereals',
  pepper: 'Vegetables',
  peppers: 'Vegetables',
  tomato: 'Vegetables',
  tomatoes: 'Vegetables',
  okra: 'Vegetables',
  onion: 'Vegetables',
  onions: 'Vegetables',
  cabbage: 'Vegetables',
  lettuce: 'Vegetables',
  mango: 'Fruits',
  orange: 'Fruits',
  pineapple: 'Fruits',
  banana: 'Fruits',
  yam: 'Tubers',
  cassava: 'Tubers',
  potato: 'Tubers',
  potatoes: 'Tubers',
  ginger: 'Herbs & Spices',
  garlic: 'Herbs & Spices',
  turmeric: 'Herbs & Spices',
  seed: 'Seeds & Seedlings',
  seeds: 'Seeds & Seedlings',
  seedling: 'Seeds & Seedlings',
  seedlings: 'Seeds & Seedlings',
  fertilizer: 'Fertilizers',
  fertilizers: 'Fertilizers',
  pesticide: 'Fertilizers',
  pesticides: 'Fertilizers',
  herbicide: 'Fertilizers',
  'farm tools': 'Farm Tools',
  'farm tool': 'Farm Tools',
  tractor: 'Farm Tools',
  hoe: 'Farm Tools',
  feed: 'Animal Feed',
  smartphones: 'Phones',
  smartphone: 'Phones',
  phones: 'Phones',
  phone: 'Phones',
  laptops: 'Laptops',
  laptop: 'Laptops',
  tablets: 'Tablets',
  tablet: 'Tablets',
  headphones: 'Headphones',
  headphone: 'Headphones',
  'smart watches': 'Smart Watches',
  'smart watch': 'Smart Watches',
  gaming: 'Gaming',
  cameras: 'Cameras',
  camera: 'Cameras',
  accessories: 'Accessories',
  accessory: 'Accessories',
  furniture: 'Furniture',
  decor: 'Decor',
  bedding: 'Bedding',
  cookware: 'Cookware',
  appliances: 'Appliances',
  appliance: 'Appliances',
  storage: 'Storage',
  'cleaning supplies': 'Cleaning Supplies',
  skincare: 'Skincare',
  makeup: 'Makeup',
  haircare: 'Haircare',
  fragrances: 'Fragrances',
  fragrance: 'Fragrances',
  grooming: 'Grooming',
  wellness: 'Wellness',
  'gym wear': 'Gym Wear',
  'running gear': 'Running Gear',
  'camping gear': 'Camping Gear',
  bikes: 'Bikes',
  bike: 'Bikes',
  balls: 'Balls',
  ball: 'Balls',
  'protective gear': 'Protective Gear',
  'baby clothing': 'Baby Clothing',
  'kids clothing': 'Kids Clothing',
  toys: 'Toys',
  toy: 'Toys',
  diapers: 'Diapers',
  diaper: 'Diapers',
  'feeding essentials': 'Feeding Essentials',
  books: 'Books',
  book: 'Books',
  stationery: 'Stationery',
  printers: 'Printers',
  printer: 'Printers',
  'office chairs': 'Office Chairs',
  'office chair': 'Office Chairs',
  'desk accessories': 'Desk Accessories',
};

const FALLBACK_SELLING_OPTIONS_BY_SUBCATEGORY = {
  rice: [
    { packageType: 'Bag', quantity: 5, measurementUnit: 'kg', isDefault: true },
    { packageType: 'Bag', quantity: 20, measurementUnit: 'kg', isDefault: false },
    { packageType: 'Sack', quantity: 50, measurementUnit: 'kg', isDefault: false },
  ],
  'grains & cereals': [
    { packageType: 'Bag', quantity: 5, measurementUnit: 'kg', isDefault: true },
    { packageType: 'Bag', quantity: 25, measurementUnit: 'kg', isDefault: false },
    { packageType: 'Sack', quantity: 50, measurementUnit: 'kg', isDefault: false },
  ],
  legumes: [
    { packageType: 'Bag', quantity: 5, measurementUnit: 'kg', isDefault: true },
    { packageType: 'Bag', quantity: 25, measurementUnit: 'kg', isDefault: false },
    { packageType: 'Sack', quantity: 50, measurementUnit: 'kg', isDefault: false },
  ],
  fruits: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Basket', quantity: 5, measurementUnit: 'kg', isDefault: false },
    { packageType: 'Crate', quantity: 20, measurementUnit: 'kg', isDefault: false },
  ],
  vegetables: [
    { packageType: 'Basket', quantity: 5, measurementUnit: 'kg', isDefault: true },
    { packageType: 'Bag', quantity: 20, measurementUnit: 'kg', isDefault: false },
    { packageType: 'Carton', quantity: 10, measurementUnit: 'kg', isDefault: false },
  ],
  't-shirts': [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Bundle', quantity: 3, measurementUnit: 'piece', isDefault: false },
    { packageType: 'Bale', quantity: 20, measurementUnit: 'piece', isDefault: false },
  ],
  tshirts: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Bundle', quantity: 3, measurementUnit: 'piece', isDefault: false },
    { packageType: 'Bale', quantity: 20, measurementUnit: 'piece', isDefault: false },
  ],
  tshirt: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Bundle', quantity: 3, measurementUnit: 'piece', isDefault: false },
  ],
  hoodies: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Bundle', quantity: 2, measurementUnit: 'piece', isDefault: false },
    { packageType: 'Bale', quantity: 10, measurementUnit: 'piece', isDefault: false },
  ],
  jeans: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Bundle', quantity: 3, measurementUnit: 'piece', isDefault: false },
    { packageType: 'Bale', quantity: 12, measurementUnit: 'piece', isDefault: false },
  ],
  sneakers: [
    { packageType: 'Pair', quantity: 1, measurementUnit: 'pair', isDefault: true },
    { packageType: 'Carton', quantity: 12, measurementUnit: 'pair', isDefault: false },
  ],
  sandals: [
    { packageType: 'Pair', quantity: 1, measurementUnit: 'pair', isDefault: true },
    { packageType: 'Carton', quantity: 12, measurementUnit: 'pair', isDefault: false },
  ],
  boots: [
    { packageType: 'Pair', quantity: 1, measurementUnit: 'pair', isDefault: true },
    { packageType: 'Carton', quantity: 6, measurementUnit: 'pair', isDefault: false },
  ],
  phones: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Carton', quantity: 10, measurementUnit: 'piece', isDefault: false },
  ],
  laptops: [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Carton', quantity: 5, measurementUnit: 'piece', isDefault: false },
  ],
};

const FALLBACK_SELLING_OPTIONS_BY_CATEGORY = {
  'Fashion & Apparel': [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Bundle', quantity: 3, measurementUnit: 'piece', isDefault: false },
  ],
  Footwear: [
    { packageType: 'Pair', quantity: 1, measurementUnit: 'pair', isDefault: true },
    { packageType: 'Carton', quantity: 12, measurementUnit: 'pair', isDefault: false },
  ],
  'Farm & Agro': [
    { packageType: 'Bag', quantity: 5, measurementUnit: 'kg', isDefault: true },
    { packageType: 'Bag', quantity: 20, measurementUnit: 'kg', isDefault: false },
    { packageType: 'Crate', quantity: 20, measurementUnit: 'kg', isDefault: false },
  ],
  'Electronics & Tech': [
    { packageType: 'Piece', quantity: 1, measurementUnit: 'piece', isDefault: true },
    { packageType: 'Carton', quantity: 10, measurementUnit: 'piece', isDefault: false },
  ],
};

const FALLBACK_SELLING_UNITS_BY_SUBCATEGORY = {
  sandals: ['Pair', 'Box', 'Carton'],
  sneakers: ['Pair', 'Box', 'Carton'],
  boots: ['Pair', 'Box', 'Carton'],
  loafers: ['Pair', 'Box', 'Carton'],
  heels: ['Pair', 'Box', 'Carton'],
  slippers: ['Pair', 'Box', 'Carton'],
  'running shoes': ['Pair', 'Box', 'Carton'],
  'school shoes': ['Pair', 'Box', 'Carton'],
  tops: ['Piece', 'Pack', 'Bale'],
  't-shirts': ['Piece', 'Pack', 'Bale'],
  tshirts: ['Piece', 'Pack', 'Bale'],
  tshirt: ['Piece', 'Pack', 'Bale'],
  hoodies: ['Piece', 'Pack', 'Bale'],
  sweatshirts: ['Piece', 'Pack', 'Bale'],
  shirts: ['Piece', 'Pack', 'Bale'],
  polos: ['Piece', 'Pack', 'Bale'],
  jeans: ['Piece', 'Pack', 'Bale'],
  chinos: ['Piece', 'Pack', 'Bale'],
  sweatpants: ['Piece', 'Pack', 'Bale'],
  trousers: ['Piece', 'Pack', 'Bale'],
  shorts: ['Piece', 'Pack', 'Bale'],
  outerwear: ['Piece', 'Pack', 'Bale'],
  phones: ['Piece', 'Box', 'Carton'],
  laptops: ['Piece', 'Box', 'Carton'],
  tablets: ['Piece', 'Box', 'Carton'],
  headphones: ['Piece', 'Box', 'Carton'],
  'smart watches': ['Piece', 'Box', 'Carton'],
  rice: ['Bag', 'Sack', 'Carton'],
  grains: ['Bag', 'Sack', 'Carton'],
  cereals: ['Bag', 'Sack', 'Carton'],
  legumes: ['Bag', 'Sack', 'Carton'],
  fruits: ['Piece', 'Pack', 'Crate', 'Basket'],
  vegetables: ['Bunch', 'Pack', 'Bag', 'Crate'],
  'animal feed': ['Bag', 'Sack', 'Carton'],
  fertilizers: ['Bag', 'Sack', 'Carton'],
  'farm tools': ['Piece', 'Set', 'Box'],
};

const FALLBACK_SELLING_UNITS_BY_CATEGORY = {
  'Fashion & Apparel': ['Piece', 'Pack', 'Bale'],
  Footwear: ['Pair', 'Box', 'Carton'],
  'Farm & Agro': ['Bag', 'Sack', 'Pack', 'Crate'],
  'Electronics & Tech': ['Piece', 'Box', 'Carton'],
  'Home & Kitchen': ['Piece', 'Set', 'Box', 'Carton'],
  'Beauty & Personal Care': ['Piece', 'Pack', 'Bottle', 'Jar'],
  'Sports & Outdoor': ['Piece', 'Set', 'Pack', 'Box'],
  'Kids & Baby': ['Piece', 'Pack', 'Set', 'Carton'],
  'Books & Office': ['Piece', 'Pack', 'Box', 'Carton'],
};

function buildUserPrompt({ prompt }) {
  // WHY: Keep the prompt short to stay under token limits.
  return [
    `User request: ${prompt}`,
    DRAFT_SCHEMA_HINT,
    TAXONOMY_HINT,
  ].join('\n');
}

function extractJsonBlock(text) {
  // WHY: Capture the first JSON object even if extra text slips in.
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end < 0 || end <= start) {
    return null;
  }
  return text.slice(start, end + 1);
}

function parseNumber(value, fallback) {
  const parsed = Number(value);
  if (Number.isNaN(parsed)) return fallback;
  return parsed;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function promptIncludesKeyword(prompt, keyword) {
  const pattern = new RegExp(
    `(?:^|[^a-z0-9])${escapeRegExp(keyword)}(?:$|[^a-z0-9])`
  );
  return pattern.test(prompt);
}

function inferSubcategoryFromPrompt(prompt) {
  const lowerPrompt = (prompt || '').trim().toLowerCase();
  if (!lowerPrompt) {
    return '';
  }

  for (const [keyword, subcategory] of Object.entries(FALLBACK_SUBCATEGORY_BY_KEYWORD)) {
    if (promptIncludesKeyword(lowerPrompt, keyword)) {
      return subcategory;
    }
  }

  return '';
}

function inferSellingFields({ category, subcategory }) {
  const subcategoryKey = (subcategory || '').trim().toLowerCase();
  const categoryKey = (category || '').trim();
  const structuredFallback =
    FALLBACK_SELLING_OPTIONS_BY_SUBCATEGORY[subcategoryKey] ||
    FALLBACK_SELLING_OPTIONS_BY_CATEGORY[categoryKey];

  if (structuredFallback) {
    return sanitizeProductSellingFields({
      sellingOptions: structuredFallback,
    });
  }

  const fallbackUnits =
    FALLBACK_SELLING_UNITS_BY_SUBCATEGORY[subcategoryKey] ||
    FALLBACK_SELLING_UNITS_BY_CATEGORY[categoryKey] ||
    DEFAULT_SELLING_UNITS;

  return sanitizeProductSellingFields({
    sellingUnits: fallbackUnits,
    defaultSellingUnit: fallbackUnits[0] || DEFAULT_SELLING_OPTIONS[0].packageType,
  });
}

function normalizeDraft(raw, { promptText = '' } = {}) {
  // WHY: Normalize fields to safe types for UI autofill.
  const priceNgn = Math.max(
    0,
    Math.round(parseNumber(raw?.priceNgn, DEFAULT_PRICE_NGN))
  );
  const stock = Math.max(
    0,
    Math.round(parseNumber(raw?.stock, DEFAULT_STOCK))
  );
  const rawCategory = normalizeOptionalProductText(raw?.category, 80);
  const rawSubcategory = normalizeOptionalProductText(raw?.subcategory, 80);
  const inferredSubcategory = inferSubcategoryFromPrompt(promptText);
  const fallbackCategory =
    rawCategory ||
    FALLBACK_CATEGORY_BY_SUBCATEGORY[
      (rawSubcategory || inferredSubcategory).toLowerCase()
    ] ||
    DEFAULT_CATEGORY;
  const fallbackSubcategory =
    rawSubcategory ||
    inferredSubcategory ||
    FALLBACK_SUBCATEGORY_BY_CATEGORY[fallbackCategory] ||
    DEFAULT_SUBCATEGORY;
  const taxonomy = sanitizeProductTaxonomyFields({
    category: fallbackCategory,
    subcategory: fallbackCategory ? fallbackSubcategory : DEFAULT_SUBCATEGORY,
    brand: DEFAULT_BRAND,
  });
  let selling = sanitizeProductSellingFields({
    sellingOptions: raw?.sellingOptions,
    sellingUnits: raw?.sellingUnits,
    defaultSellingUnit: raw?.defaultSellingUnit,
  });

  if (selling.sellingUnits.length === 0) {
    selling = inferSellingFields({
      category: taxonomy.category,
      subcategory: taxonomy.subcategory,
    });
  }

  return {
    name: raw?.name?.toString().trim() || DEFAULT_NAME,
    description:
      raw?.description?.toString().trim() || DEFAULT_DESCRIPTION,
    category: taxonomy.category || DEFAULT_CATEGORY,
    subcategory:
      taxonomy.subcategory ||
      FALLBACK_SUBCATEGORY_BY_CATEGORY[taxonomy.category || DEFAULT_CATEGORY] ||
      DEFAULT_SUBCATEGORY,
    brand: DEFAULT_BRAND,
    sellingOptions:
      selling.sellingOptions.length > 0
        ? selling.sellingOptions
        : DEFAULT_SELLING_OPTIONS,
    sellingUnits: selling.sellingUnits,
    defaultSellingUnit: selling.defaultSellingUnit || DEFAULT_SELLING_OPTIONS[0].packageType,
    priceNgn,
    stock,
  };
}

function parseAiDraft(content) {
  const jsonBlock = extractJsonBlock(content || '');
  if (!jsonBlock) {
    throw new Error('AI response missing JSON payload');
  }

  let parsed = null;
  try {
    parsed = JSON.parse(jsonBlock);
  } catch (error) {
    throw new Error('AI response JSON parse failed');
  }

  return parsed;
}

async function generateProductDraft({
  prompt,
  useReasoning,
  context,
}) {
  debug(LOG_TAG, [LOG_START, { hasPrompt: Boolean(prompt) }]);

  try {
    const aiResponse = await createAiChatCompletion({
      messages: [
        { role: 'user', content: buildUserPrompt({ prompt }) },
      ],
      systemPrompt: SYSTEM_PROMPT,
      useReasoning,
      context: {
        ...context,
        operation: AI_OPERATION,
        intent: AI_INTENT,
        source: AI_SOURCE,
      },
    });

    const draft = normalizeDraft(parseAiDraft(aiResponse.content), {
      promptText: prompt,
    });

    debug(LOG_TAG, [LOG_SUCCESS, { hasDraft: Boolean(draft?.name) }]);
    return draft;
  } catch (error) {
    debug(LOG_TAG, [
      LOG_ERROR,
      {
        error: error?.message || 'unknown error',
        resolution_hint:
          'Check prompt clarity and AI configuration before retrying.',
        reason: 'product_draft_failed',
      },
    ]);
    throw error;
  }
}

module.exports = {
  generateProductDraft,
};
