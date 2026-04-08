/// lib/app/features/home/presentation/production/production_crop_fallback_catalog.dart
/// -------------------------------------------------------------------------------
/// WHAT:
/// - Local offline crop catalog for production planner crop search.
///
/// WHY:
/// - Crop selection should keep working when the live backend search is stale
///   or temporarily unavailable.
/// - The production planner already knows the core crop lifecycle patterns, so
///   we can safely surface a small curated fallback set.
///
/// HOW:
/// - Builds `ProductionAssistantCatalogItem` objects from compact seed records.
/// - Scores queries against names and aliases.
/// - Returns the most relevant local matches when live search fails.
library;

import 'package:frontend/app/features/home/presentation/production/production_assistant_models.dart';

const String _plannerCropFallbackSource = "planner_catalog";
const String _plannerCropFallbackVerificationStatus = "manual_verified";

class _PlannerCropFallbackSeed {
  final String name;
  final List<String> aliases;
  final int minDays;
  final int maxDays;
  final List<String> phases;
  final String profileKind;
  final String category;
  final String variety;
  final String plantType;
  final String summary;
  final String scientificName;
  final String family;

  const _PlannerCropFallbackSeed({
    required this.name,
    required this.aliases,
    required this.minDays,
    required this.maxDays,
    required this.phases,
    required this.profileKind,
    required this.category,
    required this.variety,
    required this.plantType,
    required this.summary,
    required this.scientificName,
    required this.family,
  });

  Map<String, dynamic> toJson() {
    return {
      "id": _normalizeCropKey(name),
      "cropKey": _normalizeCropKey(name),
      "name": name,
      "aliases": aliases,
      "source": _plannerCropFallbackSource,
      "minDays": minDays,
      "maxDays": maxDays,
      "phases": phases,
      "profileKind": profileKind,
      "category": category,
      "variety": variety,
      "plantType": plantType,
      "summary": summary,
      "scientificName": scientificName,
      "family": family,
      "verificationStatus": _plannerCropFallbackVerificationStatus,
    };
  }
}

const List<_PlannerCropFallbackSeed> _plannerCropFallbackSeeds = [
  _PlannerCropFallbackSeed(
    name: "Tomato",
    aliases: ["tomato", "tomatoes", "solanum lycopersicum"],
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
    profileKind: "crop",
    category: "vegetable",
    variety: "",
    plantType: "vine",
    summary:
        "Warm-season tomato profile for open-field or protected cultivation with nursery, fruiting, and repeat-harvest phases.",
    scientificName: "Solanum lycopersicum",
    family: "Solanaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Bell Pepper",
    aliases: ["bell pepper", "sweet pepper"],
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
    profileKind: "crop",
    category: "vegetable",
    variety: "Bell",
    plantType: "shrub",
    summary:
        "Sweet pepper profile optimized for fresh-market bell production and repeated pick harvests.",
    scientificName: "Capsicum annuum",
    family: "Solanaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Pepper",
    aliases: ["pepper", "capsicum", "peppers"],
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
    profileKind: "crop",
    category: "vegetable",
    variety: "",
    plantType: "shrub",
    summary:
        "Warm-season capsicum profile spanning sweet and mildly hot fresh-market pepper systems.",
    scientificName: "Capsicum annuum",
    family: "Solanaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Beans",
    aliases: ["beans", "bean", "common bean", "phaseolus vulgaris"],
    minDays: 50,
    maxDays: 70,
    phases: [
      "germination",
      "vegetative_growth",
      "flowering",
      "pod_set",
      "harvest",
    ],
    profileKind: "crop",
    category: "legume",
    variety: "",
    plantType: "vine",
    summary:
        "Common bean profile covering bush and climbing snap or shell bean systems with a short to medium crop cycle.",
    scientificName: "Phaseolus vulgaris",
    family: "Fabaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Green Beans",
    aliases: ["green beans", "snap beans", "string beans"],
    minDays: 50,
    maxDays: 55,
    phases: [
      "germination",
      "vegetative_growth",
      "flowering",
      "pod_set",
      "harvest",
    ],
    profileKind: "crop",
    category: "legume",
    variety: "Green",
    plantType: "vine",
    summary:
        "Snap bean profile for tender pod production with an early, compressed harvest window.",
    scientificName: "Phaseolus vulgaris",
    family: "Fabaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Soybean",
    aliases: ["soybean", "soybeans", "soya", "glycine max"],
    minDays: 85,
    maxDays: 120,
    phases: [
      "germination",
      "vegetative_growth",
      "flowering",
      "pod_fill",
      "harvest",
    ],
    profileKind: "crop",
    category: "legume",
    variety: "",
    plantType: "herb",
    summary:
        "Soybean profile for warm-season grain and oilseed planning with a compact reproductive window.",
    scientificName: "Glycine max",
    family: "Fabaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Corn",
    aliases: ["corn", "maize", "zea mays"],
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
    profileKind: "crop",
    category: "grain",
    variety: "",
    plantType: "grass",
    summary:
        "Direct-seeded maize profile for warm-season production with pollination-sensitive tasseling and silking stages.",
    scientificName: "Zea mays",
    family: "Poaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Sweet Corn",
    aliases: ["sweet corn", "fresh corn"],
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
    profileKind: "crop",
    category: "grain",
    variety: "Sweet",
    plantType: "grass",
    summary:
        "Fresh-market sweet corn profile with a short harvest window after silking.",
    scientificName: "Zea mays",
    family: "Poaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Rice",
    aliases: ["rice", "paddy", "oryza sativa"],
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
    profileKind: "crop",
    category: "grain",
    variety: "",
    plantType: "grass",
    summary:
        "Lowland or managed-water rice profile with short to medium duration cultivars and clear reproductive timing.",
    scientificName: "Oryza sativa",
    family: "Poaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Cassava",
    aliases: ["cassava", "manioc", "yuca", "manihot esculenta"],
    minDays: 270,
    maxDays: 360,
    phases: [
      "stem_cutting_establishment",
      "canopy_development",
      "root_initiation",
      "root_bulking",
      "harvest",
    ],
    profileKind: "crop",
    category: "tuber",
    variety: "",
    plantType: "shrub",
    summary:
        "Cassava root crop profile for stem-cutting establishment and long in-field bulking to starch maturity.",
    scientificName: "Manihot esculenta",
    family: "Euphorbiaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Onion",
    aliases: ["onion", "onions", "allium cepa"],
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
    profileKind: "crop",
    category: "vegetable",
    variety: "",
    plantType: "herb",
    summary:
        "Bulb onion profile covering seed, transplant, or set-based production with curing at the end of the harvest window.",
    scientificName: "Allium cepa",
    family: "Amaryllidaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Cocoa",
    aliases: ["cocoa", "cacao", "theobroma cacao"],
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
    profileKind: "crop",
    category: "cash crop",
    variety: "",
    plantType: "tree",
    summary:
        "Perennial cocoa profile for shaded tropical production with multi-year establishment before commercial pod harvest.",
    scientificName: "Theobroma cacao",
    family: "Malvaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Mango",
    aliases: ["mango", "mangoes", "mangifera indica"],
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
    profileKind: "fruit",
    category: "tropical fruit",
    variety: "",
    plantType: "tree",
    summary:
        "Tropical mango tree profile for orchard planning, with first bearing after establishment and fruit development after bloom.",
    scientificName: "Mangifera indica",
    family: "Anacardiaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Pineapple",
    aliases: ["pineapple", "pineapples", "ananas comosus"],
    minDays: 540,
    maxDays: 730,
    phases: [
      "vegetative_growth",
      "flower_induction",
      "flowering",
      "fruit_development",
      "harvest",
    ],
    profileKind: "fruit",
    category: "tropical fruit",
    variety: "",
    plantType: "herb",
    summary:
        "Pineapple profile for tropical field or garden systems with a long vegetative phase and a single primary fruit per plant.",
    scientificName: "Ananas comosus",
    family: "Bromeliaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Lettuce",
    aliases: ["lettuce"],
    minDays: 45,
    maxDays: 60,
    phases: ["germination", "vegetative_growth", "head_development", "harvest"],
    profileKind: "crop",
    category: "leafy vegetable",
    variety: "",
    plantType: "herb",
    summary:
        "Fast leafy vegetable profile for nursery or direct-seeded production with a short, cool-season harvest window.",
    scientificName: "Lactuca sativa",
    family: "Asteraceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Okra",
    aliases: ["okra", "lady's finger", "ladies finger"],
    minDays: 50,
    maxDays: 70,
    phases: [
      "germination",
      "vegetative_growth",
      "flowering",
      "pod_development",
      "harvest",
    ],
    profileKind: "crop",
    category: "vegetable",
    variety: "",
    plantType: "herb",
    summary:
        "Warm-season okra profile for repeated pod picking after flowering begins.",
    scientificName: "Abelmoschus esculentus",
    family: "Malvaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Cucumber",
    aliases: ["cucumber", "cucumbers"],
    minDays: 50,
    maxDays: 70,
    phases: [
      "germination",
      "vegetative_growth",
      "flowering",
      "fruit_set",
      "harvest",
    ],
    profileKind: "crop",
    category: "vegetable",
    variety: "",
    plantType: "vine",
    summary:
        "Fast cucurbit profile for fresh-market cucumber production with an early harvest window.",
    scientificName: "Cucumis sativus",
    family: "Cucurbitaceae",
  ),
  _PlannerCropFallbackSeed(
    name: "Watermelon",
    aliases: ["watermelon", "watermelons"],
    minDays: 75,
    maxDays: 95,
    phases: [
      "germination",
      "vegetative_growth",
      "flowering",
      "fruit_set",
      "fruit_development",
      "harvest",
    ],
    profileKind: "crop",
    category: "cucurbit",
    variety: "",
    plantType: "vine",
    summary:
        "Warm-season watermelon profile for vining field production and large-fruit development.",
    scientificName: "Citrullus lanatus",
    family: "Cucurbitaceae",
  ),
];

String _normalizeCropKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), "_")
      .replaceAll(RegExp(r"_+"), "_")
      .replaceAll(RegExp(r"^_|_$"), "");
}

List<ProductionAssistantCatalogItem> buildPlannerCropFallbackCatalog() {
  return _plannerCropFallbackSeeds
      .map((seed) => ProductionAssistantCatalogItem.fromJson(seed.toJson()))
      .toList(growable: false);
}

ProductionAssistantCatalogItem? findPlannerCropFallbackByName(
  String productName,
) {
  final normalizedTarget = _normalizeCropKey(productName);
  if (normalizedTarget.isEmpty) {
    return null;
  }

  final items = buildPlannerCropFallbackCatalog();
  for (final item in items) {
    final normalizedCandidates =
        <String>[item.name, item.cropKey, ...item.aliases]
            .map(_normalizeCropKey)
            .where((entry) => entry.isNotEmpty)
            .toList(growable: false);
    if (normalizedCandidates.any(
      (candidate) =>
          candidate == normalizedTarget ||
          candidate.contains(normalizedTarget) ||
          normalizedTarget.contains(candidate),
    )) {
      return item;
    }
  }
  return null;
}

int _scorePlannerCropFallbackItem({
  required ProductionAssistantCatalogItem item,
  required String normalizedQuery,
  required List<String> queryTokens,
}) {
  final normalizedCandidates =
      <String>[item.name, item.cropKey, ...item.aliases]
          .map(_normalizeCropKey)
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);

  if (normalizedCandidates.any((candidate) => candidate == normalizedQuery)) {
    return 100;
  }

  var score = 0;
  for (final candidate in normalizedCandidates) {
    if (candidate.contains(normalizedQuery)) {
      score += 10;
    }
  }
  for (final token in queryTokens) {
    if (token.length < 2) {
      continue;
    }
    for (final candidate in normalizedCandidates) {
      if (candidate.contains(token)) {
        score += 3;
        break;
      }
    }
  }

  if (score == 0) {
    return normalizedCandidates.any(
          (candidate) => candidate.startsWith(normalizedQuery),
        )
        ? 4
        : 0;
  }
  return score;
}

List<ProductionAssistantCatalogItem> searchPlannerCropFallbackCatalog({
  required String query,
  int limit = 8,
}) {
  final safeLimit = limit < 1 ? 1 : limit;
  final normalizedQuery = query.trim().toLowerCase();
  final items = buildPlannerCropFallbackCatalog();

  if (normalizedQuery.isEmpty) {
    return items.take(safeLimit).toList(growable: false);
  }

  final queryTokens = normalizedQuery
      .split(RegExp(r"[^a-z0-9]+"))
      .where((token) => token.length >= 2)
      .toList(growable: false);

  final scoredItems = <MapEntry<ProductionAssistantCatalogItem, int>>[];
  for (final item in items) {
    final score = _scorePlannerCropFallbackItem(
      item: item,
      normalizedQuery: normalizedQuery,
      queryTokens: queryTokens,
    );
    if (score > 0) {
      scoredItems.add(MapEntry(item, score));
    }
  }

  scoredItems.sort((left, right) {
    final scoreComparison = right.value.compareTo(left.value);
    if (scoreComparison != 0) {
      return scoreComparison;
    }
    return left.key.name.toLowerCase().compareTo(right.key.name.toLowerCase());
  });

  if (scoredItems.isEmpty) {
    return const <ProductionAssistantCatalogItem>[];
  }

  return scoredItems
      .take(safeLimit)
      .map((entry) => entry.key)
      .toList(growable: false);
}
