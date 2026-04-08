/// lib/app/features/home/presentation/product_taxonomy.dart
/// -------------------------------------------------------
/// WHAT:
/// - Shared product category, subcategory, and brand suggestions.
///
/// WHY:
/// - Keeps product creation structured without hard-limiting the catalog.
/// - Drives dependent dropdowns for category -> subcategory selection.
library;

const String productTaxonomyCustomValue = "__custom__";
const String productTaxonomyDefaultCategoryLabel = "Fashion & Apparel";
const String productTaxonomyDefaultSubcategoryLabel = "Tops";
const List<String> productPackageTypeCatalog = [
  "Piece",
  "Pack",
  "Bag",
  "Sack",
  "Carton",
  "Box",
  "Bundle",
  "Pair",
  "Bottle",
  "Can",
  "Jar",
  "Tube",
  "Crate",
  "Tray",
  "Set",
  "Dozen",
  "Roll",
  "Bale",
  "Bunch",
  "Basket",
  "Sachet",
  "Tin",
  "Packet",
  "Pallet",
];
const List<String> productMeasurementUnitCatalog = [
  "piece",
  "pair",
  "kg",
  "g",
  "lb",
  "ton",
  "ml",
  "L",
  "cl",
  "m",
  "box",
  "carton",
  "bag",
  "pack",
  "bottle",
  "crate",
  "tray",
  "set",
  "roll",
  "bundle",
  "dozen",
  "bunch",
  "basket",
  "sachet",
  "jar",
  "tube",
  "can",
  "unit",
];

class ProductTaxonomyCategory {
  final String label;
  final String description;
  final List<String> brandSuggestions;
  final List<ProductTaxonomySubcategory> subcategories;

  const ProductTaxonomyCategory({
    required this.label,
    required this.description,
    this.brandSuggestions = const [],
    this.subcategories = const [],
  });
}

class ProductTaxonomySubcategory {
  final String label;
  final List<String> brandSuggestions;

  const ProductTaxonomySubcategory({
    required this.label,
    this.brandSuggestions = const [],
  });
}

const List<ProductTaxonomyCategory> productTaxonomyCatalog = [
  ProductTaxonomyCategory(
    label: "Fashion & Apparel",
    description: "Clothing, styled collections, and everyday wear.",
    brandSuggestions: ["Nike", "Adidas", "Zara", "H&M", "Uniqlo", "Levi's"],
    subcategories: [
      ProductTaxonomySubcategory(
        label: "Tops",
        brandSuggestions: ["Nike", "Adidas", "Zara", "Uniqlo"],
      ),
      ProductTaxonomySubcategory(
        label: "T-Shirts",
        brandSuggestions: ["Nike", "Adidas", "Uniqlo", "H&M"],
      ),
      ProductTaxonomySubcategory(
        label: "Hoodies",
        brandSuggestions: ["Nike", "Adidas", "Puma", "Champion"],
      ),
      ProductTaxonomySubcategory(
        label: "Shirts",
        brandSuggestions: ["Zara", "H&M", "Tommy Hilfiger", "Mango"],
      ),
      ProductTaxonomySubcategory(
        label: "Polos",
        brandSuggestions: ["Lacoste", "Polo Ralph Lauren", "Hugo Boss"],
      ),
      ProductTaxonomySubcategory(
        label: "Jeans",
        brandSuggestions: ["Levi's", "Wrangler", "Diesel", "Calvin Klein"],
      ),
      ProductTaxonomySubcategory(
        label: "Trousers",
        brandSuggestions: ["Zara", "Mango", "Next", "Massimo Dutti"],
      ),
      ProductTaxonomySubcategory(
        label: "Shorts",
        brandSuggestions: ["Nike", "Adidas", "H&M", "Zara"],
      ),
      ProductTaxonomySubcategory(
        label: "Outerwear",
        brandSuggestions: ["North Face", "Columbia", "Zara", "Uniqlo"],
      ),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Footwear",
    description: "Sneakers, boots, sandals, and performance shoes.",
    brandSuggestions: [
      "Nike",
      "Adidas",
      "New Balance",
      "Puma",
      "Converse",
      "Vans",
      "Timberland",
      "Crocs",
    ],
    subcategories: [
      ProductTaxonomySubcategory(label: "Sneakers"),
      ProductTaxonomySubcategory(label: "Running Shoes"),
      ProductTaxonomySubcategory(label: "Boots"),
      ProductTaxonomySubcategory(label: "Loafers"),
      ProductTaxonomySubcategory(label: "Sandals"),
      ProductTaxonomySubcategory(label: "Heels"),
      ProductTaxonomySubcategory(label: "Slippers"),
      ProductTaxonomySubcategory(label: "School Shoes"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Farm & Agro",
    description: "Produce, farm inputs, and agricultural supplies.",
    brandSuggestions: [
      "Golden Penny",
      "Honeywell",
      "Yara",
      "Notore",
      "John Deere",
      "Syngenta",
    ],
    subcategories: [
      ProductTaxonomySubcategory(label: "Grains & Cereals"),
      ProductTaxonomySubcategory(label: "Legumes"),
      ProductTaxonomySubcategory(label: "Tubers"),
      ProductTaxonomySubcategory(label: "Fruits"),
      ProductTaxonomySubcategory(label: "Vegetables"),
      ProductTaxonomySubcategory(label: "Herbs & Spices"),
      ProductTaxonomySubcategory(label: "Seeds & Seedlings"),
      ProductTaxonomySubcategory(label: "Fertilizers"),
      ProductTaxonomySubcategory(label: "Farm Tools"),
      ProductTaxonomySubcategory(label: "Animal Feed"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Electronics & Tech",
    description: "Consumer electronics, computers, and accessories.",
    brandSuggestions: [
      "Apple",
      "Samsung",
      "Dell",
      "HP",
      "Lenovo",
      "Asus",
      "Xiaomi",
      "Tecno",
      "Infinix",
      "Sony",
    ],
    subcategories: [
      ProductTaxonomySubcategory(
        label: "Phones",
        brandSuggestions: [
          "Apple",
          "Samsung",
          "Tecno",
          "Infinix",
          "Google",
          "Xiaomi",
        ],
      ),
      ProductTaxonomySubcategory(
        label: "Laptops",
        brandSuggestions: ["Apple", "Dell", "HP", "Lenovo", "Asus", "Acer"],
      ),
      ProductTaxonomySubcategory(
        label: "Tablets",
        brandSuggestions: ["Apple", "Samsung", "Xiaomi", "Lenovo"],
      ),
      ProductTaxonomySubcategory(label: "Headphones"),
      ProductTaxonomySubcategory(label: "Smart Watches"),
      ProductTaxonomySubcategory(label: "Gaming"),
      ProductTaxonomySubcategory(label: "Cameras"),
      ProductTaxonomySubcategory(label: "Accessories"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Home & Kitchen",
    description: "Furniture, decor, kitchenware, and home essentials.",
    brandSuggestions: ["Ikea", "Binatone", "Scanfrost", "Hisense"],
    subcategories: [
      ProductTaxonomySubcategory(label: "Furniture"),
      ProductTaxonomySubcategory(label: "Decor"),
      ProductTaxonomySubcategory(label: "Bedding"),
      ProductTaxonomySubcategory(label: "Cookware"),
      ProductTaxonomySubcategory(label: "Appliances"),
      ProductTaxonomySubcategory(label: "Storage"),
      ProductTaxonomySubcategory(label: "Cleaning Supplies"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Beauty & Personal Care",
    description: "Skincare, makeup, fragrances, and grooming.",
    brandSuggestions: ["Nivea", "Maybelline", "L'Oreal", "Dove", "MAC"],
    subcategories: [
      ProductTaxonomySubcategory(label: "Skincare"),
      ProductTaxonomySubcategory(label: "Makeup"),
      ProductTaxonomySubcategory(label: "Haircare"),
      ProductTaxonomySubcategory(label: "Fragrances"),
      ProductTaxonomySubcategory(label: "Grooming"),
      ProductTaxonomySubcategory(label: "Wellness"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Sports & Outdoor",
    description: "Fitness, sportswear, and outdoor activity gear.",
    brandSuggestions: ["Nike", "Adidas", "Under Armour", "Puma", "Decathlon"],
    subcategories: [
      ProductTaxonomySubcategory(label: "Gym Wear"),
      ProductTaxonomySubcategory(label: "Running Gear"),
      ProductTaxonomySubcategory(label: "Camping Gear"),
      ProductTaxonomySubcategory(label: "Bikes"),
      ProductTaxonomySubcategory(label: "Balls"),
      ProductTaxonomySubcategory(label: "Protective Gear"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Kids & Baby",
    description: "Kids fashion, toys, and baby essentials.",
    brandSuggestions: ["Carter's", "Mothercare", "Fisher-Price", "Huggies"],
    subcategories: [
      ProductTaxonomySubcategory(label: "Baby Clothing"),
      ProductTaxonomySubcategory(label: "Kids Clothing"),
      ProductTaxonomySubcategory(label: "Shoes"),
      ProductTaxonomySubcategory(label: "Toys"),
      ProductTaxonomySubcategory(label: "Diapers"),
      ProductTaxonomySubcategory(label: "Feeding Essentials"),
    ],
  ),
  ProductTaxonomyCategory(
    label: "Books & Office",
    description: "Books, stationery, and office equipment.",
    brandSuggestions: ["Casio", "HP", "Canon", "Bic"],
    subcategories: [
      ProductTaxonomySubcategory(label: "Books"),
      ProductTaxonomySubcategory(label: "Stationery"),
      ProductTaxonomySubcategory(label: "Printers"),
      ProductTaxonomySubcategory(label: "Office Chairs"),
      ProductTaxonomySubcategory(label: "Desk Accessories"),
    ],
  ),
];

ProductTaxonomyCategory? findProductTaxonomyCategory(String? label) {
  final normalized = label?.trim().toLowerCase() ?? "";
  if (normalized.isEmpty) return null;

  for (final category in productTaxonomyCatalog) {
    if (category.label.toLowerCase() == normalized) {
      return category;
    }
  }
  return null;
}

ProductTaxonomySubcategory? findProductTaxonomySubcategory({
  required String? categoryLabel,
  required String? subcategoryLabel,
}) {
  final category = findProductTaxonomyCategory(categoryLabel);
  final normalized = subcategoryLabel?.trim().toLowerCase() ?? "";
  if (category == null || normalized.isEmpty) return null;

  for (final subcategory in category.subcategories) {
    if (subcategory.label.toLowerCase() == normalized) {
      return subcategory;
    }
  }
  return null;
}

List<String> productBrandSuggestions({
  String? categoryLabel,
  String? subcategoryLabel,
  Iterable<String> extraSuggestions = const [],
}) {
  final category = findProductTaxonomyCategory(categoryLabel);
  final subcategory = findProductTaxonomySubcategory(
    categoryLabel: categoryLabel,
    subcategoryLabel: subcategoryLabel,
  );

  final suggestions = <String>[];
  final seen = <String>{};

  void addAll(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        suggestions.add(trimmed);
      }
    }
  }

  addAll(extraSuggestions.toList());
  if (subcategory != null) {
    addAll(subcategory.brandSuggestions);
  }
  if (category != null) {
    addAll(category.brandSuggestions);
  }

  return suggestions;
}

List<String> productPackageTypeSuggestions({
  String? categoryLabel,
  String? subcategoryLabel,
  Iterable<String> extraSuggestions = const [],
}) {
  final normalizedCategory = (categoryLabel ?? "").trim().toLowerCase();
  final normalizedSubcategory = (subcategoryLabel ?? "").trim().toLowerCase();
  final suggestions = <String>[];
  final seen = <String>{};

  void addAll(Iterable<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        suggestions.add(trimmed);
      }
    }
  }

  addAll(extraSuggestions);

  switch (normalizedSubcategory) {
    case "sandals":
    case "sneakers":
    case "boots":
    case "loafers":
    case "heels":
    case "slippers":
    case "running shoes":
    case "school shoes":
      addAll(["Pair", "Box", "Carton"]);
      break;
    case "tops":
    case "t-shirts":
    case "hoodies":
    case "shirts":
    case "polos":
    case "jeans":
    case "trousers":
    case "shorts":
    case "outerwear":
      addAll(["Piece", "Pack", "Bale", "Bundle"]);
      break;
    case "phones":
    case "laptops":
    case "tablets":
    case "headphones":
    case "smart watches":
    case "cameras":
      addAll(["Piece", "Box", "Carton"]);
      break;
    case "grains & cereals":
    case "legumes":
    case "tubers":
    case "seeds & seedlings":
    case "fertilizers":
    case "animal feed":
      addAll(["Bag", "Sack", "Carton", "Crate"]);
      break;
    case "farm tools":
      addAll(["Piece", "Set", "Pack", "Box"]);
      break;
    case "fruits":
      addAll(["Piece", "Pack", "Crate", "Basket"]);
      break;
    case "vegetables":
    case "herbs & spices":
      addAll(["Bunch", "Pack", "Bag", "Crate"]);
      break;
    case "skincare":
    case "makeup":
    case "haircare":
    case "fragrances":
    case "grooming":
      addAll(["Piece", "Pack", "Bottle", "Jar", "Tube"]);
      break;
  }

  switch (normalizedCategory) {
    case "fashion & apparel":
      addAll(["Piece", "Pack", "Bale", "Bundle"]);
      break;
    case "footwear":
      addAll(["Pair", "Box", "Carton"]);
      break;
    case "farm & agro":
      addAll(["Bag", "Sack", "Crate", "Basket", "Pack"]);
      break;
    case "electronics & tech":
      addAll(["Piece", "Box", "Carton"]);
      break;
    case "home & kitchen":
      addAll(["Piece", "Set", "Box", "Carton"]);
      break;
    case "beauty & personal care":
      addAll(["Piece", "Pack", "Bottle", "Jar"]);
      break;
    case "sports & outdoor":
      addAll(["Piece", "Set", "Pack", "Box"]);
      break;
    case "kids & baby":
      addAll(["Piece", "Pack", "Set", "Carton"]);
      break;
    case "books & office":
      addAll(["Piece", "Pack", "Box", "Carton"]);
      break;
  }

  addAll(productPackageTypeCatalog);
  return suggestions;
}

List<String> productMeasurementUnitSuggestions({
  String? categoryLabel,
  String? subcategoryLabel,
  String? packageType,
  Iterable<String> extraSuggestions = const [],
}) {
  final normalizedCategory = (categoryLabel ?? "").trim().toLowerCase();
  final normalizedSubcategory = (subcategoryLabel ?? "").trim().toLowerCase();
  final normalizedPackageType = (packageType ?? "").trim().toLowerCase();
  final suggestions = <String>[];
  final seen = <String>{};

  void addAll(Iterable<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        suggestions.add(trimmed);
      }
    }
  }

  addAll(extraSuggestions);

  switch (normalizedPackageType) {
    case "piece":
      addAll(["piece"]);
      break;
    case "pair":
      addAll(["pair"]);
      break;
    case "bag":
    case "sack":
      addAll(["kg", "g", "lb", "bag"]);
      break;
    case "basket":
      addAll(["kg", "piece", "basket"]);
      break;
    case "bundle":
      addAll(["piece", "bundle"]);
      break;
    case "pack":
      addAll(["piece", "pack", "g", "ml"]);
      break;
    case "bottle":
      addAll(["ml", "L", "bottle"]);
      break;
    case "jar":
      addAll(["g", "ml", "jar"]);
      break;
    case "tube":
      addAll(["g", "ml", "tube"]);
      break;
    case "box":
      addAll(["piece", "box"]);
      break;
    case "carton":
      addAll(["piece", "carton", "pack"]);
      break;
    case "crate":
      addAll(["kg", "piece", "crate"]);
      break;
    case "tray":
      addAll(["piece", "tray"]);
      break;
    case "dozen":
      addAll(["piece", "dozen"]);
      break;
    case "roll":
      addAll(["roll", "m"]);
      break;
    case "can":
      addAll(["ml", "g", "can"]);
      break;
    case "sachet":
      addAll(["g", "ml", "sachet"]);
      break;
  }

  switch (normalizedSubcategory) {
    case "sandals":
    case "sneakers":
    case "boots":
    case "loafers":
    case "heels":
    case "slippers":
    case "running shoes":
    case "school shoes":
      addAll(["pair", "piece"]);
      break;
    case "tops":
    case "t-shirts":
    case "hoodies":
    case "shirts":
    case "polos":
    case "jeans":
    case "trousers":
    case "shorts":
    case "outerwear":
      addAll(["piece", "pack"]);
      break;
    case "grains & cereals":
    case "legumes":
    case "tubers":
    case "seeds & seedlings":
    case "fertilizers":
    case "animal feed":
      addAll(["kg", "g", "bag", "sack"]);
      break;
    case "farm tools":
      addAll(["piece", "set", "pack", "box"]);
      break;
    case "fruits":
    case "vegetables":
    case "herbs & spices":
      addAll(["kg", "piece", "bunch", "basket", "crate"]);
      break;
    case "phones":
    case "laptops":
    case "tablets":
    case "headphones":
    case "smart watches":
    case "cameras":
      addAll(["piece", "box"]);
      break;
    case "skincare":
    case "makeup":
    case "haircare":
    case "fragrances":
    case "grooming":
      addAll(["ml", "g", "piece", "bottle", "jar", "tube"]);
      break;
  }

  switch (normalizedCategory) {
    case "fashion & apparel":
      addAll(["piece", "pack"]);
      break;
    case "footwear":
      addAll(["pair", "piece"]);
      break;
    case "farm & agro":
      addAll(["kg", "g", "piece", "bunch", "bag", "basket", "crate"]);
      break;
    case "electronics & tech":
      addAll(["piece", "box", "carton"]);
      break;
    case "home & kitchen":
      addAll(["piece", "set", "box"]);
      break;
    case "beauty & personal care":
      addAll(["ml", "g", "piece", "bottle", "jar", "tube"]);
      break;
    case "sports & outdoor":
      addAll(["piece", "set", "pack"]);
      break;
    case "kids & baby":
      addAll(["piece", "pack", "set"]);
      break;
    case "books & office":
      addAll(["piece", "pack", "box"]);
      break;
  }

  addAll(productMeasurementUnitCatalog);
  return suggestions;
}

List<String> productSellingUnitSuggestions({
  String? categoryLabel,
  String? subcategoryLabel,
  Iterable<String> extraSuggestions = const [],
}) {
  return productPackageTypeSuggestions(
    categoryLabel: categoryLabel,
    subcategoryLabel: subcategoryLabel,
    extraSuggestions: extraSuggestions,
  );
}
