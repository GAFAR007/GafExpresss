/**
 * apps/backend/scripts/seed-business-fashion-apparel-products.js
 * -------------------------------------------------------------
 * WHAT:
 * - Seeds storefront business products across all catalog categories with
 *   realistic names and image galleries.
 *
 * WHY:
 * - Gives a verified business owner ready-to-browse inventory across every
 *   storefront category/subcategory without manual product creation.
 * - Uses the same product service and sanitizers as normal backend product creation.
 *
 * HOW:
 * - Resolves a business owner/staff user by email.
 * - Creates one product for each supported category/subcategory.
 * - Stores a primary image plus multiple gallery URLs per product.
 * - Skips products that already exist for the same business, category, and name.
 *
 * USAGE:
 * - node scripts/seed-business-fashion-apparel-products.js --owner-email=razakgafar98@outlook.com
 * - Optional: --dry-run
 */

require("dotenv").config();

const mongoose = require("mongoose");
const connectDB = require("../config/db");
const Product = require("../models/Product");
const User = require("../models/User");
const { createProduct } = require("../services/business.product.service");
const debug = require("../utils/debug");

const SCRIPT_TAG = "SEED_BUSINESS_CATALOG_PRODUCTS";
const DEFAULT_OWNER_EMAIL = "razakgafar98@outlook.com";
const FASHION_CATEGORY = "Fashion & Apparel";
const FOOTWEAR_CATEGORY = "Footwear";
const FARM_CATEGORY = "Farm & Agro";
const ELECTRONICS_CATEGORY = "Electronics & Tech";
const HOME_CATEGORY = "Home & Kitchen";
const BEAUTY_CATEGORY = "Beauty & Personal Care";
const SPORTS_CATEGORY = "Sports & Outdoor";
const KIDS_CATEGORY = "Kids & Baby";
const BOOKS_CATEGORY = "Books & Office";
const DEFAULT_BRAND = "GafExpress Apparel";
const args = process.argv.slice(2);

function readArg(key) {
  return args.find((arg) => arg.startsWith(`${key}=`))?.split("=")[1]?.trim();
}

function hasFlag(flag) {
  return args.includes(flag);
}

function toKobo(amountNgn) {
  return Math.round(Number(amountNgn || 0) * 100);
}

function buildUnsplashImageUrl(photoId) {
  // WHY: Keep all product images in a consistent storefront-friendly ratio.
  return `https://images.unsplash.com/${photoId}?auto=format&fit=crop&w=1200&q=80`;
}

function resolveOwnerBrand(owner) {
  const fullName = [
    owner?.firstName,
    owner?.middleName,
    owner?.lastName,
  ]
    .filter(Boolean)
    .join(" ")
    .trim();
  const emailName = owner?.email?.split("@")?.[0]?.trim();

  return (
    owner?.companyName?.trim() ||
    owner?.name?.trim() ||
    (fullName ? `${fullName} Apparel` : "") ||
    (emailName ? `${emailName} Apparel` : "") ||
    DEFAULT_BRAND
  );
}

function resolveBusinessScope(owner) {
  // WHY: Owners usually carry businessId=self, but fall back safely when missing.
  if (owner?.businessId) {
    return owner.businessId;
  }
  if (owner?.role === "business_owner") {
    return owner._id;
  }
  return null;
}

function buildImagePayload(photoIds) {
  const imageUrls = photoIds.map((photoId) => buildUnsplashImageUrl(photoId));

  return {
    imageUrl: imageUrls[0] || "",
    imageUrls,
    imageAssets: imageUrls.map((url) => ({
      url,
      publicId: "",
    })),
  };
}

function buildFashionSellingOptions(packQuantity = 3, baleQuantity = 12) {
  return [
    {
      packageType: "Piece",
      quantity: 1,
      measurementUnit: "piece",
      isDefault: true,
    },
    {
      packageType: "Pack",
      quantity: packQuantity,
      measurementUnit: "piece",
      isDefault: false,
    },
    {
      packageType: "Bale",
      quantity: baleQuantity,
      measurementUnit: "piece",
      isDefault: false,
    },
  ];
}

function buildFootwearSellingOptions(boxQuantity = 6, cartonQuantity = 12) {
  return [
    {
      packageType: "Pair",
      quantity: 1,
      measurementUnit: "pair",
      isDefault: true,
    },
    {
      packageType: "Box",
      quantity: boxQuantity,
      measurementUnit: "pair",
      isDefault: false,
    },
    {
      packageType: "Carton",
      quantity: cartonQuantity,
      measurementUnit: "pair",
      isDefault: false,
    },
  ];
}

function buildFarmSellingOptions(defaultOption, bulkOptions = []) {
  return [
    {
      packageType: defaultOption.packageType,
      quantity: defaultOption.quantity,
      measurementUnit: defaultOption.measurementUnit,
      isDefault: true,
    },
    ...bulkOptions.map((option) => ({
      packageType: option.packageType,
      quantity: option.quantity,
      measurementUnit: option.measurementUnit,
      isDefault: false,
    })),
  ];
}

function buildCatalogSellingOptions(defaultOption, bulkOptions = []) {
  return buildFarmSellingOptions(defaultOption, bulkOptions);
}

function buildFashionProductBlueprints(brand) {
  return [
    {
      name: "Ribbed Square-Neck Knit Top",
      description:
        "Soft stretch rib-knit top with a clean square neckline and body-skimming fit for easy day-to-night styling.",
      category: FASHION_CATEGORY,
      subcategory: "Tops",
      brand,
      sellingOptions: buildFashionSellingOptions(3, 18),
      price: toKobo(18500),
      stock: 74,
      ...buildImagePayload([
        "photo-1434389677669-e08b4cac3105",
        "photo-1496747611176-843222e1e57c",
        "photo-1483985988355-763728e1935b",
      ]),
    },
    {
      name: "Heavyweight Oversized Cotton T-Shirt",
      description:
        "Premium oversized cotton tee with a dense handfeel, dropped shoulders, and a neat rib collar.",
      category: FASHION_CATEGORY,
      subcategory: "T-Shirts",
      brand,
      sellingOptions: buildFashionSellingOptions(3, 24),
      price: toKobo(16500),
      stock: 96,
      ...buildImagePayload([
        "photo-1521572163474-6864f9cf17ab",
        "photo-1581655353564-df123a1eb820",
        "photo-1576566588028-4147f3842f27",
      ]),
    },
    {
      name: "Brushed Fleece Pullover Hoodie",
      description:
        "Warm brushed fleece hoodie with a roomy kangaroo pocket, rib trims, and a relaxed everyday silhouette.",
      category: FASHION_CATEGORY,
      subcategory: "Hoodies",
      brand,
      sellingOptions: buildFashionSellingOptions(2, 12),
      price: toKobo(34500),
      stock: 58,
      ...buildImagePayload([
        "photo-1556821840-3a63f95609a7",
        "photo-1578587018452-892bacefd3f2",
        "photo-1554568218-0f1715e72254",
      ]),
    },
    {
      name: "Crisp Oxford Button-Down Shirt",
      description:
        "Smart cotton Oxford shirt with a structured collar, button cuffs, and a clean regular fit.",
      category: FASHION_CATEGORY,
      subcategory: "Shirts",
      brand,
      sellingOptions: buildFashionSellingOptions(3, 18),
      price: toKobo(27500),
      stock: 61,
      ...buildImagePayload([
        "photo-1596755094514-f87e34085b2c",
        "photo-1598033129183-c4f50c736f10",
        "photo-1603252109303-2751441dd157",
      ]),
    },
    {
      name: "Textured Pique Polo Shirt",
      description:
        "Breathable pique polo with a soft collar, two-button placket, and a polished casual profile.",
      category: FASHION_CATEGORY,
      subcategory: "Polos",
      brand,
      sellingOptions: buildFashionSellingOptions(3, 18),
      price: toKobo(24500),
      stock: 66,
      ...buildImagePayload([
        "photo-1581655353564-df123a1eb820",
        "photo-1523381294911-8d3cead13475",
        "photo-1529139574466-a303027c1d8b",
      ]),
    },
    {
      name: "Straight-Leg Mid-Wash Denim Jeans",
      description:
        "Mid-rise straight-leg jeans cut from durable washed denim with classic five-pocket detailing.",
      category: FASHION_CATEGORY,
      subcategory: "Jeans",
      brand,
      sellingOptions: buildFashionSellingOptions(2, 12),
      price: toKobo(39500),
      stock: 52,
      ...buildImagePayload([
        "photo-1541099649105-f69ad21f3246",
        "photo-1473966968600-fa801b869a1a",
        "photo-1604176354204-9268737828e4",
      ]),
    },
    {
      name: "Tailored Pleated Wide-Leg Trousers",
      description:
        "Fluid wide-leg trousers with sharp front pleats, belt loops, and a tailored drape for office or evening wear.",
      category: FASHION_CATEGORY,
      subcategory: "Trousers",
      brand,
      sellingOptions: buildFashionSellingOptions(2, 12),
      price: toKobo(36500),
      stock: 49,
      ...buildImagePayload([
        "photo-1594633312681-425c7b97ccd1",
        "photo-1509551388413-e18d0ac5d495",
        "photo-1473966968600-fa801b869a1a",
      ]),
    },
    {
      name: "Relaxed Cotton Cargo Shorts",
      description:
        "Utility-inspired cotton cargo shorts with roomy pockets, a relaxed thigh, and an above-knee finish.",
      category: FASHION_CATEGORY,
      subcategory: "Shorts",
      brand,
      sellingOptions: buildFashionSellingOptions(3, 18),
      price: toKobo(22500),
      stock: 68,
      ...buildImagePayload([
        "photo-1591195853828-11db59a44f6b",
        "photo-1515886657613-9f3515b0c78f",
        "photo-1506629082955-511b1aa562c8",
      ]),
    },
    {
      name: "Quilted Puffer Zip Jacket",
      description:
        "Lightweight quilted puffer jacket with a full zip, stand collar, and insulated layering comfort.",
      category: FASHION_CATEGORY,
      subcategory: "Outerwear",
      brand,
      sellingOptions: buildFashionSellingOptions(2, 10),
      price: toKobo(59500),
      stock: 43,
      ...buildImagePayload([
        "photo-1591047139829-d91aecb6caea",
        "photo-1544022613-e87ca75a784a",
        "photo-1539533018447-63fcce2678e3",
      ]),
    },
  ];
}

function buildFootwearProductBlueprints(brand) {
  return [
    {
      name: "Classic Leather Court Sneakers",
      description:
        "Low-top court sneakers with smooth leather uppers, cushioned insoles, and a durable rubber cupsole for everyday styling.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Sneakers",
      brand,
      sellingOptions: buildFootwearSellingOptions(6, 18),
      price: toKobo(48500),
      stock: 64,
      ...buildImagePayload([
        "photo-1542291026-7eec264c27ff",
        "photo-1549298916-b41d501d3772",
        "photo-1556906781-9a412961c28c",
      ]),
    },
    {
      name: "Breathable Mesh Performance Running Shoes",
      description:
        "Lightweight running shoes with engineered mesh ventilation, responsive foam cushioning, and a grippy outsole for training runs.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Running Shoes",
      brand,
      sellingOptions: buildFootwearSellingOptions(6, 18),
      price: toKobo(52500),
      stock: 71,
      ...buildImagePayload([
        "photo-1460353581641-37baddab0fa2",
        "photo-1539185441755-769473a23570",
        "photo-1600185365483-26d7a4cc7519",
      ]),
    },
    {
      name: "Lug-Sole Leather Chelsea Boots",
      description:
        "Polished Chelsea boots with elastic side panels, pull tabs, and a chunky lug sole for smart cold-weather outfits.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Boots",
      brand,
      sellingOptions: buildFootwearSellingOptions(4, 12),
      price: toKobo(64500),
      stock: 39,
      ...buildImagePayload([
        "photo-1520639888713-7851133b1ed0",
        "photo-1543163521-1bf539c55dd2",
        "photo-1608256246200-53e635b5b65f",
      ]),
    },
    {
      name: "Soft Suede Penny Loafers",
      description:
        "Refined penny loafers in soft suede with a padded footbed, stitched apron toe, and an easy slip-on profile.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Loafers",
      brand,
      sellingOptions: buildFootwearSellingOptions(6, 12),
      price: toKobo(45500),
      stock: 57,
      ...buildImagePayload([
        "photo-1614252369475-531eba835eb1",
        "photo-1603808033192-082d6919d3e1",
        "photo-1616406432452-07bc5938759d",
      ]),
    },
    {
      name: "Comfort Strap Everyday Sandals",
      description:
        "Open-toe strap sandals with a contoured footbed, adjustable buckle straps, and a flexible outsole for all-day comfort.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Sandals",
      brand,
      sellingOptions: buildFootwearSellingOptions(8, 24),
      price: toKobo(29500),
      stock: 83,
      ...buildImagePayload([
        "photo-1603487742131-4160ec999306",
        "photo-1622920799137-86c891159e44",
        "photo-1531310197839-ccf54634509e",
      ]),
    },
    {
      name: "Block Heel Slingback Pumps",
      description:
        "Elegant slingback heels with a stable block heel, pointed toe, and a padded insole for dressy work and evening looks.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Heels",
      brand,
      sellingOptions: buildFootwearSellingOptions(6, 12),
      price: toKobo(42500),
      stock: 46,
      ...buildImagePayload([
        "photo-1543163521-1bf539c55dd2",
        "photo-1515347619252-60a4bf4fff4f",
        "photo-1601924638867-3ec3a565e78b",
      ]),
    },
    {
      name: "Plush Cross-Band Indoor Slippers",
      description:
        "Soft cushioned slippers with plush cross-band straps, a molded footbed, and a lightweight non-slip sole for lounging.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "Slippers",
      brand,
      sellingOptions: buildFootwearSellingOptions(8, 24),
      price: toKobo(18500),
      stock: 98,
      ...buildImagePayload([
        "photo-1603487742131-4160ec999306",
        "photo-1562273138-f46be4ebdf33",
        "photo-1573148195900-7845dcb9b127",
      ]),
    },
    {
      name: "Classic Polished Leather School Shoes",
      description:
        "Durable black leather school shoes with a supportive cushioned collar, neat lace-up fastening, and a sturdy grip sole.",
      category: FOOTWEAR_CATEGORY,
      subcategory: "School Shoes",
      brand,
      sellingOptions: buildFootwearSellingOptions(6, 18),
      price: toKobo(33500),
      stock: 88,
      ...buildImagePayload([
        "photo-1549298916-b41d501d3772",
        "photo-1560769629-975ec94e6a86",
        "photo-1603808033192-082d6919d3e1",
      ]),
    },
  ];
}

function buildFarmProductBlueprints(brand) {
  return [
    {
      name: "Premium Stone-Cleaned Ofada Rice",
      description:
        "Aromatic stone-cleaned Ofada rice with firm whole grains, rich local flavor, and excellent cooking yield for family meals and catering.",
      category: FARM_CATEGORY,
      subcategory: "Grains & Cereals",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Bag", quantity: 5, measurementUnit: "kg" },
        [
          { packageType: "Sack", quantity: 25, measurementUnit: "kg" },
          { packageType: "Carton", quantity: 50, measurementUnit: "kg" },
        ],
      ),
      price: toKobo(21500),
      stock: 120,
      ...buildImagePayload([
        "photo-1586201375761-83865001e31c",
        "photo-1516684669134-de6f7c473a2a",
        "photo-1604908554162-f8b9c50a6bba",
      ]),
    },
    {
      name: "Handpicked Brown Honey Beans",
      description:
        "Cleaned brown honey beans with a naturally sweet taste, low chaff content, and a creamy texture ideal for moi-moi, akara, and stews.",
      category: FARM_CATEGORY,
      subcategory: "Legumes",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Bag", quantity: 2, measurementUnit: "kg" },
        [
          { packageType: "Sack", quantity: 10, measurementUnit: "kg" },
          { packageType: "Sack", quantity: 25, measurementUnit: "kg" },
        ],
      ),
      price: toKobo(9800),
      stock: 140,
      ...buildImagePayload([
        "photo-1582281298055-e25b84a30b0b",
        "photo-1515543237350-b3eea1ec8082",
        "photo-1603046891726-36bfd957e0bf",
      ]),
    },
    {
      name: "Fresh White Yam Tuber Bundle",
      description:
        "Firm fresh white yam tubers with smooth flesh and excellent boiling or pounding quality, packed for household and retail buyers.",
      category: FARM_CATEGORY,
      subcategory: "Tubers",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Bundle", quantity: 5, measurementUnit: "piece" },
        [
          { packageType: "Sack", quantity: 20, measurementUnit: "piece" },
          { packageType: "Crate", quantity: 40, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(26500),
      stock: 75,
      ...buildImagePayload([
        "photo-1518977676601-b53f82aba655",
        "photo-1594282418426-62d71b2a9335",
        "photo-1574323347407-f5e1ad6d020b",
      ]),
    },
    {
      name: "Sweet Tropical Pineapple Crate",
      description:
        "Naturally sweet fresh pineapples with golden flesh and bright acidity, selected for juicing, snacking, and fruit display counters.",
      category: FARM_CATEGORY,
      subcategory: "Fruits",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Crate", quantity: 12, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 24, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(2500),
      stock: 180,
      ...buildImagePayload([
        "photo-1550258987-190a2d41a8ba",
        "photo-1589820296156-2454bb8a6ad1",
        "photo-1490885578174-acda8905c2c6",
      ]),
    },
    {
      name: "Farm Fresh Roma Tomato Basket",
      description:
        "Bright red Roma tomatoes with firm texture and balanced sweetness, harvested for sauces, stews, salads, and market resale.",
      category: FARM_CATEGORY,
      subcategory: "Vegetables",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Basket", quantity: 5, measurementUnit: "kg" },
        [
          { packageType: "Crate", quantity: 20, measurementUnit: "kg" },
          { packageType: "Sack", quantity: 40, measurementUnit: "kg" },
        ],
      ),
      price: toKobo(14500),
      stock: 95,
      ...buildImagePayload([
        "photo-1592841200221-a6898f307baa",
        "photo-1561136594-7f68413baa99",
        "photo-1592924357228-91a4daadcfea",
      ]),
    },
    {
      name: "Sun-Dried Ginger and Turmeric Spice Mix",
      description:
        "Aromatic sun-dried ginger and turmeric blend with bold warming notes, ideal for tea, seasoning blends, marinades, and wellness recipes.",
      category: FARM_CATEGORY,
      subcategory: "Herbs & Spices",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Pack", quantity: 250, measurementUnit: "g" },
        [
          { packageType: "Bag", quantity: 1, measurementUnit: "kg" },
          { packageType: "Carton", quantity: 5, measurementUnit: "kg" },
        ],
      ),
      price: toKobo(6200),
      stock: 160,
      ...buildImagePayload([
        "photo-1596040033229-a9821ebd058d",
        "photo-1604908554049-10f9fba09015",
        "photo-1615485500704-8e990f9900f7",
      ]),
    },
    {
      name: "Hybrid Tomato Seedlings Starter Tray",
      description:
        "Healthy hybrid tomato seedlings raised in nursery trays with strong stems and active root growth for quick transplant establishment.",
      category: FARM_CATEGORY,
      subcategory: "Seeds & Seedlings",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Tray", quantity: 128, measurementUnit: "piece" },
        [
          { packageType: "Pack", quantity: 256, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 512, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(18500),
      stock: 60,
      ...buildImagePayload([
        "photo-1523348837708-15d4a09cfac2",
        "photo-1587300003388-59208cc962cb",
        "photo-1464226184884-fa280b87c399",
      ]),
    },
    {
      name: "Balanced NPK 15-15-15 Fertilizer Granules",
      description:
        "Balanced granular NPK fertilizer formulated to support root development, plant vigor, and improved yield across mixed crop farms.",
      category: FARM_CATEGORY,
      subcategory: "Fertilizers",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Bag", quantity: 5, measurementUnit: "kg" },
        [
          { packageType: "Sack", quantity: 25, measurementUnit: "kg" },
          { packageType: "Sack", quantity: 50, measurementUnit: "kg" },
        ],
      ),
      price: toKobo(24500),
      stock: 82,
      ...buildImagePayload([
        "photo-1416879595882-3373a0480b5b",
        "photo-1463123081488-789f998ac9c4",
        "photo-1589923188900-85dae523342b",
      ]),
    },
    {
      name: "Forged Steel Hand Hoe and Cultivator Set",
      description:
        "Durable forged steel hand hoe and cultivator set with smooth wooden handles for land preparation, weeding, and garden bed maintenance.",
      category: FARM_CATEGORY,
      subcategory: "Farm Tools",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Pack", quantity: 4, measurementUnit: "set" },
          { packageType: "Carton", quantity: 12, measurementUnit: "set" },
        ],
      ),
      price: toKobo(19500),
      stock: 68,
      ...buildImagePayload([
        "photo-1416879595882-3373a0480b5b",
        "photo-1585320806297-9794b3e4eeae",
        "photo-1500937386664-56d1dfef3854",
      ]),
    },
    {
      name: "High-Protein Layer Poultry Feed",
      description:
        "Nutrient-rich layer poultry feed blended for strong shell quality, consistent egg production, and balanced flock nutrition.",
      category: FARM_CATEGORY,
      subcategory: "Animal Feed",
      brand,
      sellingOptions: buildFarmSellingOptions(
        { packageType: "Bag", quantity: 5, measurementUnit: "kg" },
        [
          { packageType: "Sack", quantity: 25, measurementUnit: "kg" },
          { packageType: "Sack", quantity: 50, measurementUnit: "kg" },
        ],
      ),
      price: toKobo(17500),
      stock: 105,
      ...buildImagePayload([
        "photo-1548550023-2bdb3c5beed7",
        "photo-1563281577-a7be47e20db9",
        "photo-1500595046743-cd271d694d30",
      ]),
    },
  ];
}

function buildElectronicsProductBlueprints(brand) {
  return [
    {
      name: "AeroMax 5G AMOLED Smartphone",
      description:
        "Unlocked dual-SIM 5G smartphone with a vivid AMOLED display, high-capacity battery, and a multi-lens camera system for daily work and content.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Phones",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 4, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 12, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(285000),
      stock: 38,
      ...buildImagePayload([
        "photo-1511707171634-5f897ff02aa9",
        "photo-1592750475338-74b7b21085ab",
        "photo-1512499617640-c2f999fe1f7c",
      ]),
    },
    {
      name: "UltraBook Pro 14-Inch Business Laptop",
      description:
        "Slim 14-inch laptop with a fast SSD, crisp display, long battery life, and a comfortable keyboard for business productivity and school work.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Laptops",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 2, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 6, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(645000),
      stock: 24,
      ...buildImagePayload([
        "photo-1496181133206-80ce9b88a853",
        "photo-1517336714731-489689fd1ca8",
        "photo-1531297484001-80022131f5a1",
      ]),
    },
    {
      name: "VisionPad 11-Inch Android Tablet",
      description:
        "Portable 11-inch tablet with a bright touchscreen, stereo speakers, and expandable storage for streaming, reading, and light productivity.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Tablets",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 4, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 10, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(225000),
      stock: 31,
      ...buildImagePayload([
        "photo-1544244015-0df4b3ffc6b0",
        "photo-1585790050230-5dd28404ccb9",
        "photo-1561154464-82e9adf32764",
      ]),
    },
    {
      name: "Studio ANC Wireless Over-Ear Headphones",
      description:
        "Wireless over-ear headphones with active noise cancellation, deep bass tuning, soft cushions, and quick charging for travel and office focus.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Headphones",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 24, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(88500),
      stock: 54,
      ...buildImagePayload([
        "photo-1505740420928-5e560c06d30e",
        "photo-1484704849700-f032a568e944",
        "photo-1583394838336-acd977736f90",
      ]),
    },
    {
      name: "ActiveFit GPS Smart Watch",
      description:
        "Water-resistant smart watch with health tracking, workout modes, GPS route logging, and message notifications in a lightweight daily-wear case.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Smart Watches",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 18, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(96500),
      stock: 47,
      ...buildImagePayload([
        "photo-1523275335684-37898b6baf30",
        "photo-1544117519-31a4b719223d",
        "photo-1434493789847-2f02dc6ca35d",
      ]),
    },
    {
      name: "NextWave RGB Wireless Gaming Controller",
      description:
        "Responsive wireless gaming controller with textured grips, dual vibration motors, programmable buttons, and RGB accents for console and PC play.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Gaming",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 8, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 24, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(72500),
      stock: 59,
      ...buildImagePayload([
        "photo-1606144042614-b2417e99c4e3",
        "photo-1598550476439-6847785fcea6",
        "photo-1550745165-9bc0b252726f",
      ]),
    },
    {
      name: "CreatorShot 4K Mirrorless Camera",
      description:
        "Compact mirrorless camera with fast autofocus, 4K video recording, and interchangeable lens support for product shoots, vlogs, and events.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Cameras",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 2, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 6, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(485000),
      stock: 18,
      ...buildImagePayload([
        "photo-1516035069371-29a1b244cc32",
        "photo-1495121553079-4c61bcce1894",
        "photo-1502920917128-1aa500764cbd",
      ]),
    },
    {
      name: "MagSafe Travel Charger and Cable Kit",
      description:
        "Compact tech accessory kit with a magnetic charger puck, braided USB-C cables, and a storage pouch for phones, tablets, and earbuds.",
      category: ELECTRONICS_CATEGORY,
      subcategory: "Accessories",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Pack", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 10, measurementUnit: "set" },
          { packageType: "Carton", quantity: 30, measurementUnit: "set" },
        ],
      ),
      price: toKobo(18500),
      stock: 130,
      ...buildImagePayload([
        "photo-1583863788434-e58a36330cf0",
        "photo-1586953208448-b95a79798f07",
        "photo-1601524909162-ae8725290836",
      ]),
    },
  ];
}

function buildHomeKitchenProductBlueprints(brand) {
  return [
    {
      name: "Scandinavian Oak Two-Seater Sofa",
      description:
        "Compact two-seater sofa with soft woven upholstery, rounded oak legs, and supportive cushions for living rooms, studios, and lounge corners.",
      category: HOME_CATEGORY,
      subcategory: "Furniture",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Set", quantity: 2, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 4, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(285000),
      stock: 16,
      ...buildImagePayload([
        "photo-1555041469-a586c61ea9bc",
        "photo-1493663284031-b7e3aefcae8e",
        "photo-1586023492125-27b2c045efd7",
      ]),
    },
    {
      name: "Handcrafted Ceramic Table Vase Set",
      description:
        "Decorative ceramic vase set with matte glaze finishes and sculptural silhouettes for shelves, dining consoles, and bedside styling.",
      category: HOME_CATEGORY,
      subcategory: "Decor",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "set" },
          { packageType: "Carton", quantity: 18, measurementUnit: "set" },
        ],
      ),
      price: toKobo(26500),
      stock: 52,
      ...buildImagePayload([
        "photo-1493663284031-b7e3aefcae8e",
        "photo-1513519245088-0e12902e35ca",
        "photo-1493809842364-78817add7ffb",
      ]),
    },
    {
      name: "Hotel-Soft Cotton Duvet Bedding Set",
      description:
        "Breathable cotton duvet bedding set with pillowcases and a smooth sateen finish for a fresh hotel-style bedroom update.",
      category: HOME_CATEGORY,
      subcategory: "Bedding",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 4, measurementUnit: "set" },
          { packageType: "Carton", quantity: 12, measurementUnit: "set" },
        ],
      ),
      price: toKobo(38500),
      stock: 44,
      ...buildImagePayload([
        "photo-1505693416388-ac5ce068fe85",
        "photo-1560448204-e02f11c3d0e2",
        "photo-1505693314120-0d443867891c",
      ]),
    },
    {
      name: "Nonstick Granite Cookware Pot Set",
      description:
        "Multi-piece nonstick cookware set with heat-resistant handles, tight-fit glass lids, and easy-clean granite coating for daily home cooking.",
      category: HOME_CATEGORY,
      subcategory: "Cookware",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 2, measurementUnit: "set" },
          { packageType: "Carton", quantity: 6, measurementUnit: "set" },
        ],
      ),
      price: toKobo(58500),
      stock: 37,
      ...buildImagePayload([
        "photo-1556909114-f6e7ad7d3136",
        "photo-1556911220-bff31c812dba",
        "photo-1514516870926-20598999d7a5",
      ]),
    },
    {
      name: "Digital Air Fryer and Oven Combo",
      description:
        "Countertop air fryer oven combo with preset cooking modes, a clear viewing window, and removable trays for fast low-oil meals.",
      category: HOME_CATEGORY,
      subcategory: "Appliances",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 2, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 6, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(125000),
      stock: 29,
      ...buildImagePayload([
        "photo-1586208958839-06c17cacdf08",
        "photo-1574269909862-7e1d70bb8078",
        "photo-1556911220-e15b29be8c8f",
      ]),
    },
    {
      name: "Airtight Modular Pantry Storage Containers",
      description:
        "Stackable clear pantry containers with airtight lids and reusable labels to organize grains, snacks, baking supplies, and dry ingredients.",
      category: HOME_CATEGORY,
      subcategory: "Storage",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "set" },
          { packageType: "Carton", quantity: 18, measurementUnit: "set" },
        ],
      ),
      price: toKobo(22500),
      stock: 88,
      ...buildImagePayload([
        "photo-1584464491033-06628f3a6b7b",
        "photo-1556909114-f6e7ad7d3136",
        "photo-1513694203232-719a280e022f",
      ]),
    },
    {
      name: "Multi-Surface Cleaning Supplies Starter Kit",
      description:
        "Household cleaning supplies kit with multi-surface cleaner, microfiber cloths, scrub sponges, and a spray bottle for routine home care.",
      category: HOME_CATEGORY,
      subcategory: "Cleaning Supplies",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Pack", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "set" },
          { packageType: "Carton", quantity: 24, measurementUnit: "set" },
        ],
      ),
      price: toKobo(14500),
      stock: 110,
      ...buildImagePayload([
        "photo-1563453392212-326f5e854473",
        "photo-1585421514284-efb74c2b69ba",
        "photo-1584464491033-06628f3a6b7b",
      ]),
    },
  ];
}

function buildBeautyProductBlueprints(brand) {
  return [
    {
      name: "Hydrating Glow Facial Skincare Serum",
      description:
        "Lightweight hydrating serum with a smooth fast-absorbing texture to support a fresh-looking glow and a comfortable daily skincare routine.",
      category: BEAUTY_CATEGORY,
      subcategory: "Skincare",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Bottle", quantity: 30, measurementUnit: "ml" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "bottle" },
          { packageType: "Carton", quantity: 24, measurementUnit: "bottle" },
        ],
      ),
      price: toKobo(18500),
      stock: 92,
      ...buildImagePayload([
        "photo-1570194065650-d99fb4bedf0a",
        "photo-1620916566398-39f1143ab7be",
        "photo-1556228578-8c89e6adf883",
      ]),
    },
    {
      name: "Velvet Matte Lipstick Makeup Trio",
      description:
        "Three-shade matte lipstick set with rich pigment, smooth glide, and wearable neutral tones for everyday and occasion makeup looks.",
      category: BEAUTY_CATEGORY,
      subcategory: "Makeup",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 3, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 12, measurementUnit: "set" },
          { packageType: "Carton", quantity: 36, measurementUnit: "set" },
        ],
      ),
      price: toKobo(16500),
      stock: 86,
      ...buildImagePayload([
        "photo-1586495777744-4413f21062fa",
        "photo-1596462502278-27bfdc403348",
        "photo-1522335789203-aabd1fc54bc9",
      ]),
    },
    {
      name: "Argan Repair Haircare Shampoo and Conditioner",
      description:
        "Nourishing shampoo and conditioner pair infused with argan oil to soften hair, reduce dryness, and improve manageability after wash day.",
      category: BEAUTY_CATEGORY,
      subcategory: "Haircare",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 2, measurementUnit: "bottle" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "set" },
          { packageType: "Carton", quantity: 18, measurementUnit: "set" },
        ],
      ),
      price: toKobo(24500),
      stock: 74,
      ...buildImagePayload([
        "photo-1522338242992-e1a54906a8da",
        "photo-1571781926291-c477ebfd024b",
        "photo-1556228578-0d85b1a4d571",
      ]),
    },
    {
      name: "Signature Amber Oud Eau de Parfum",
      description:
        "Warm amber oud fragrance with layered woody and soft floral notes, presented in a polished bottle for long-lasting daily or evening wear.",
      category: BEAUTY_CATEGORY,
      subcategory: "Fragrances",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Bottle", quantity: 100, measurementUnit: "ml" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "bottle" },
          { packageType: "Carton", quantity: 24, measurementUnit: "bottle" },
        ],
      ),
      price: toKobo(38500),
      stock: 61,
      ...buildImagePayload([
        "photo-1541643600914-78b084683601",
        "photo-1594035910387-fea47794261f",
        "photo-1615634260167-c8cdede054de",
      ]),
    },
    {
      name: "Precision Beard Grooming Trimmer Kit",
      description:
        "Rechargeable beard grooming kit with guide combs, detail trimming attachments, and a travel pouch for clean edge-ups and routine maintenance.",
      category: BEAUTY_CATEGORY,
      subcategory: "Grooming",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Kit", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 4, measurementUnit: "set" },
          { packageType: "Carton", quantity: 12, measurementUnit: "set" },
        ],
      ),
      price: toKobo(32500),
      stock: 55,
      ...buildImagePayload([
        "photo-1503951914875-452162b0f3f1",
        "photo-1622296089863-eb7fc530daa8",
        "photo-1621605815971-fbc98d665033",
      ]),
    },
    {
      name: "Daily Wellness Herbal Tea Gift Box",
      description:
        "Curated herbal wellness tea box with calming and refreshing blends packed in sachets for simple morning, focus, and evening routines.",
      category: BEAUTY_CATEGORY,
      subcategory: "Wellness",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Box", quantity: 20, measurementUnit: "sachet" },
        [
          { packageType: "Pack", quantity: 40, measurementUnit: "sachet" },
          { packageType: "Carton", quantity: 120, measurementUnit: "sachet" },
        ],
      ),
      price: toKobo(14500),
      stock: 90,
      ...buildImagePayload([
        "photo-1544787219-7f47ccb76574",
        "photo-1571934811356-5cc061b6821f",
        "photo-1499638673689-79a0b5115d87",
      ]),
    },
  ];
}

function buildSportsProductBlueprints(brand) {
  return [
    {
      name: "FlexDry Performance Gym Wear Set",
      description:
        "Breathable stretch gym top and shorts set with quick-dry fabric, smooth seams, and flexible comfort for lifting, studio workouts, and training.",
      category: SPORTS_CATEGORY,
      subcategory: "Gym Wear",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Pack", quantity: 3, measurementUnit: "set" },
          { packageType: "Carton", quantity: 12, measurementUnit: "set" },
        ],
      ),
      price: toKobo(28500),
      stock: 79,
      ...buildImagePayload([
        "photo-1517836357463-d25dfeac3438",
        "photo-1538805060514-97d9cc17730c",
        "photo-1517963879433-6ad2b056d712",
      ]),
    },
    {
      name: "Lightweight Marathon Running Hydration Vest",
      description:
        "Lightweight running vest with breathable mesh panels, front flask pockets, and adjustable straps for comfortable long-distance training.",
      category: SPORTS_CATEGORY,
      subcategory: "Running Gear",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Pack", quantity: 4, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 12, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(36500),
      stock: 46,
      ...buildImagePayload([
        "photo-1552674605-db6ffd4facb5",
        "photo-1461896836934-ffe607ba8211",
        "photo-1526401485004-2fda9f4e2562",
      ]),
    },
    {
      name: "All-Season Waterproof Camping Tent",
      description:
        "Three-person waterproof camping tent with a ventilated canopy, reinforced groundsheet, and a compact carry bag for outdoor weekend trips.",
      category: SPORTS_CATEGORY,
      subcategory: "Camping Gear",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 2, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 6, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(89500),
      stock: 27,
      ...buildImagePayload([
        "photo-1504851149312-7a075b496cc7",
        "photo-1504280390367-361c6d9f38f4",
        "photo-1523987355523-c7b5b0dd90a7",
      ]),
    },
    {
      name: "UrbanTrail 21-Speed Mountain Bike",
      description:
        "Durable mountain bike with a lightweight frame, front suspension, and responsive disc brakes for city commutes and recreational trail rides.",
      category: SPORTS_CATEGORY,
      subcategory: "Bikes",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 1, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 4, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(245000),
      stock: 20,
      ...buildImagePayload([
        "photo-1485965120184-e220f721d03e",
        "photo-1507035895480-2b3156c31fc8",
        "photo-1571068316344-75bc76f77890",
      ]),
    },
    {
      name: "ProMatch PU Leather Football",
      description:
        "Training and match football with textured PU panels, balanced bounce, and durable stitching for school play, club sessions, and casual games.",
      category: SPORTS_CATEGORY,
      subcategory: "Balls",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Pack", quantity: 5, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 20, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(12500),
      stock: 120,
      ...buildImagePayload([
        "photo-1579952363873-27f3bade9f55",
        "photo-1517927033932-b3d18e61fb3a",
        "photo-1431324155629-1a6deb1dec8d",
      ]),
    },
    {
      name: "Impact Shield Knee and Elbow Protective Pads",
      description:
        "Protective pad set with impact-absorbing foam, adjustable straps, and a breathable fit for skating, biking, and high-movement training.",
      category: SPORTS_CATEGORY,
      subcategory: "Protective Gear",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Pack", quantity: 6, measurementUnit: "set" },
          { packageType: "Carton", quantity: 18, measurementUnit: "set" },
        ],
      ),
      price: toKobo(22500),
      stock: 64,
      ...buildImagePayload([
        "photo-1571019613454-1cb2f99b2d8b",
        "photo-1546519638-68e109498ffc",
        "photo-1517963879433-6ad2b056d712",
      ]),
    },
  ];
}

function buildKidsProductBlueprints(brand) {
  return [
    {
      name: "Soft Cotton Baby Romper Bodysuit Set",
      description:
        "Gentle cotton baby rompers with envelope necklines, snap closures, and breathable comfort for newborn layering and everyday naps.",
      category: KIDS_CATEGORY,
      subcategory: "Baby Clothing",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 3, measurementUnit: "piece" },
        [
          { packageType: "Pack", quantity: 6, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 24, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(18500),
      stock: 85,
      ...buildImagePayload([
        "photo-1515488042361-ee00e0ddd4e4",
        "photo-1519689680058-324335c77eba",
        "photo-1522771930-78848d9293e8",
      ]),
    },
    {
      name: "Everyday Printed Kids T-Shirt and Shorts Set",
      description:
        "Play-friendly kids clothing set with a soft printed tee, easy-fit shorts, and breathable fabric made for school breaks and weekend outings.",
      category: KIDS_CATEGORY,
      subcategory: "Kids Clothing",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Pack", quantity: 4, measurementUnit: "set" },
          { packageType: "Carton", quantity: 16, measurementUnit: "set" },
        ],
      ),
      price: toKobo(22500),
      stock: 91,
      ...buildImagePayload([
        "photo-1519457431-44ccd64a579b",
        "photo-1471286174890-9c112ffca5b4",
        "photo-1503919005314-30d93d07d823",
      ]),
    },
    {
      name: "Cushioned Hook-and-Loop Kids Sneakers",
      description:
        "Supportive kids shoes with a cushioned sole, hook-and-loop fastening, and a flexible outsole for active school days and playground use.",
      category: KIDS_CATEGORY,
      subcategory: "Shoes",
      brand,
      sellingOptions: buildFootwearSellingOptions(8, 24),
      price: toKobo(19500),
      stock: 77,
      ...buildImagePayload([
        "photo-1542291026-7eec264c27ff",
        "photo-1549298916-b41d501d3772",
        "photo-1560769629-975ec94e6a86",
      ]),
    },
    {
      name: "Montessori Wooden Learning Toy Set",
      description:
        "Colorful wooden learning toys designed for stacking, shape sorting, and hands-on play to support early motor skills and curiosity.",
      category: KIDS_CATEGORY,
      subcategory: "Toys",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 6, measurementUnit: "set" },
          { packageType: "Carton", quantity: 18, measurementUnit: "set" },
        ],
      ),
      price: toKobo(24500),
      stock: 69,
      ...buildImagePayload([
        "photo-1515488042361-ee00e0ddd4e4",
        "photo-1560859251-d563a49cce73",
        "photo-1519340241574-2cec6aef0c01",
      ]),
    },
    {
      name: "Ultra-Dry Baby Diapers Mega Pack",
      description:
        "Absorbent baby diapers with a soft breathable top layer, flexible waistband, and reliable leak protection for day and night comfort.",
      category: KIDS_CATEGORY,
      subcategory: "Diapers",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Pack", quantity: 40, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 80, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 240, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(28500),
      stock: 105,
      ...buildImagePayload([
        "photo-1515488042361-ee00e0ddd4e4",
        "photo-1519689680058-324335c77eba",
        "photo-1492725764893-90b379c2b6e7",
      ]),
    },
    {
      name: "BPA-Free Baby Feeding Bottles Starter Kit",
      description:
        "Baby feeding essentials kit with BPA-free bottles, silicone nipples, a cleaning brush, and travel caps for a practical daily feeding setup.",
      category: KIDS_CATEGORY,
      subcategory: "Feeding Essentials",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Kit", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 4, measurementUnit: "set" },
          { packageType: "Carton", quantity: 12, measurementUnit: "set" },
        ],
      ),
      price: toKobo(21500),
      stock: 72,
      ...buildImagePayload([
        "photo-1578662996442-48f60103fc96",
        "photo-1515488042361-ee00e0ddd4e4",
        "photo-1519689680058-324335c77eba",
      ]),
    },
  ];
}

function buildBooksOfficeProductBlueprints(brand) {
  return [
    {
      name: "Modern Business Strategy Paperback Book",
      description:
        "Readable paperback business book packed with practical frameworks for strategy, operations, and team execution for founders and managers.",
      category: BOOKS_CATEGORY,
      subcategory: "Books",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Pack", quantity: 5, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 20, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(12500),
      stock: 96,
      ...buildImagePayload([
        "photo-1544947950-fa07a98d237f",
        "photo-1495446815901-a7297e633e8d",
        "photo-1512820790803-83ca734da794",
      ]),
    },
    {
      name: "Executive Stationery Notebook and Pen Set",
      description:
        "Premium stationery set with lined notebooks, smooth-writing pens, sticky tabs, and a neat desk-friendly finish for planning and meetings.",
      category: BOOKS_CATEGORY,
      subcategory: "Stationery",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 10, measurementUnit: "set" },
          { packageType: "Carton", quantity: 40, measurementUnit: "set" },
        ],
      ),
      price: toKobo(14500),
      stock: 120,
      ...buildImagePayload([
        "photo-1517842645767-c639042777db",
        "photo-1455390582262-044cdead277a",
        "photo-1515378791036-0648a3ef77b2",
      ]),
    },
    {
      name: "Wireless Color Inkjet Office Printer",
      description:
        "Compact wireless color printer with mobile printing support, sharp document output, and efficient all-in-one handling for home and small office use.",
      category: BOOKS_CATEGORY,
      subcategory: "Printers",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 2, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 6, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(155000),
      stock: 28,
      ...buildImagePayload([
        "photo-1612815154858-60aa4c59eaa6",
        "photo-1586953208448-b95a79798f07",
        "photo-1593642632823-8f785ba67e45",
      ]),
    },
    {
      name: "Ergonomic Mesh Swivel Office Chair",
      description:
        "Adjustable office chair with breathable mesh support, tilt control, cushioned seating, and smooth-rolling casters for long desk sessions.",
      category: BOOKS_CATEGORY,
      subcategory: "Office Chairs",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Piece", quantity: 1, measurementUnit: "piece" },
        [
          { packageType: "Box", quantity: 1, measurementUnit: "piece" },
          { packageType: "Carton", quantity: 4, measurementUnit: "piece" },
        ],
      ),
      price: toKobo(98500),
      stock: 34,
      ...buildImagePayload([
        "photo-1586023492125-27b2c045efd7",
        "photo-1505843490538-5133c6c7d0e1",
        "photo-1518455027359-f3f8164ba6bd",
      ]),
    },
    {
      name: "Minimal Desk Accessories Organizer Kit",
      description:
        "Workspace desk accessories kit with a pen cup, cable holder, memo tray, and storage compartments to keep office tools organized and easy to reach.",
      category: BOOKS_CATEGORY,
      subcategory: "Desk Accessories",
      brand,
      sellingOptions: buildCatalogSellingOptions(
        { packageType: "Set", quantity: 1, measurementUnit: "set" },
        [
          { packageType: "Box", quantity: 8, measurementUnit: "set" },
          { packageType: "Carton", quantity: 24, measurementUnit: "set" },
        ],
      ),
      price: toKobo(18500),
      stock: 98,
      ...buildImagePayload([
        "photo-1497032628192-86f99bcd76bc",
        "photo-1455390582262-044cdead277a",
        "photo-1493809842364-78817add7ffb",
      ]),
    },
  ];
}

async function resolveOwnerByEmail(ownerEmail) {
  const normalizedEmail = (ownerEmail || "").trim().toLowerCase();

  debug(SCRIPT_TAG, {
    step: "DB_QUERY_START",
    layer: "script",
    operation: "ResolveFashionSeedOwner",
    intent: "find business owner or staff account for product seeding",
    ownerEmail: normalizedEmail,
  });

  const owner = await User.findOne({ email: normalizedEmail });
  if (!owner) {
    throw new Error(`User not found for ${normalizedEmail}`);
  }

  const businessId = resolveBusinessScope(owner);
  if (!businessId) {
    throw new Error(
      `User ${normalizedEmail} does not have a business scope configured`,
    );
  }

  debug(SCRIPT_TAG, {
    step: "DB_QUERY_OK",
    layer: "script",
    operation: "ResolveFashionSeedOwner",
    intent: "business owner resolved for product seeding",
    ownerId: owner._id.toString(),
    businessId: businessId.toString(),
    ownerRole: owner.role,
  });

  return {
    owner,
    businessId,
  };
}

function buildProductKey(product) {
  return [
    product.name.trim().toLowerCase(),
    product.category.trim().toLowerCase(),
    product.subcategory.trim().toLowerCase(),
  ].join("|");
}

async function loadExistingProductKeys({ businessId, products }) {
  const categories = [...new Set(products.map((product) => product.category))];
  const names = products.map((product) => product.name);
  const subcategories = products.map((product) => product.subcategory);

  // WHY: Prefetch existing products in one query to avoid N+1 lookups.
  const existingProducts = await Product.find({
    businessId,
    category: { $in: categories },
    name: { $in: names },
    subcategory: { $in: subcategories },
    deletedAt: null,
  })
    .select("name category subcategory")
    .lean();

  return new Set(existingProducts.map((product) => buildProductKey(product)));
}

async function seedBusinessCatalogProducts() {
  const ownerEmail = readArg("--owner-email") || DEFAULT_OWNER_EMAIL;
  const dryRun = hasFlag("--dry-run");

  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is missing in apps/backend/.env");
  }

  debug(SCRIPT_TAG, {
    step: "SCRIPT_START",
    layer: "script",
    operation: "SeedBusinessCatalogProducts",
    intent: "seed catalog products for a business account",
    ownerEmail,
    dryRun,
  });

  await connectDB();

  const { owner, businessId } = await resolveOwnerByEmail(ownerEmail);
  const brand = resolveOwnerBrand(owner);
  const products = [
    ...buildFashionProductBlueprints(brand),
    ...buildFootwearProductBlueprints(brand),
    ...buildFarmProductBlueprints(brand),
    ...buildElectronicsProductBlueprints(brand),
    ...buildHomeKitchenProductBlueprints(brand),
    ...buildBeautyProductBlueprints(brand),
    ...buildSportsProductBlueprints(brand),
    ...buildKidsProductBlueprints(brand),
    ...buildBooksOfficeProductBlueprints(brand),
  ];
  const existingKeys = await loadExistingProductKeys({
    businessId,
    products,
  });

  const createdProducts = [];
  const skippedProducts = [];

  for (const productData of products) {
    const productKey = buildProductKey(productData);

    if (existingKeys.has(productKey)) {
      skippedProducts.push({
        name: productData.name,
        category: productData.category,
        subcategory: productData.subcategory,
      });
      continue;
    }

    if (dryRun) {
      createdProducts.push({
        name: productData.name,
        category: productData.category,
        subcategory: productData.subcategory,
        imageCount: productData.imageUrls.length,
      });
      continue;
    }

    const createdProduct = await createProduct({
      data: productData,
      actor: owner,
      businessId,
    });

    createdProducts.push({
      id: createdProduct._id.toString(),
      name: createdProduct.name,
      category: createdProduct.category,
      subcategory: createdProduct.subcategory,
      imageCount: createdProduct.imageUrls?.length || 0,
    });
  }

  console.log(
    JSON.stringify(
      {
        ownerEmail,
        businessId: businessId.toString(),
        brand,
        dryRun,
        requestedCount: products.length,
        createdCount: createdProducts.length,
        skippedCount: skippedProducts.length,
        createdProducts,
        skippedProducts,
      },
      null,
      2,
    ),
  );

  await mongoose.disconnect();
}

seedBusinessCatalogProducts().catch(async (error) => {
  console.error(error.message);
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
