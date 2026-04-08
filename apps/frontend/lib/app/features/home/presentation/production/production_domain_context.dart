/// lib/app/features/home/presentation/production/production_domain_context.dart
/// --------------------------------------------------------------------------
/// WHAT:
/// - Shared production domain-context constants + labels for UI and payloads.
///
/// WHY:
/// - Keeps domain context values consistent between draft state, API payloads,
///   and list/detail parsing.
///
/// HOW:
/// - Exposes canonical domain context values used by backend.
/// - Maps UI-friendly labels (for example "Generic") to stored values.
library;

const String productionDomainFarm = "farm";
const String productionDomainFashion = "fashion";
const String productionDomainManufacturing = "manufacturing";
const String productionDomainConstruction = "construction";
const String productionDomainMedia = "media";
const String productionDomainFood = "food";
const String productionDomainCosmetics = "cosmetics";
const String productionDomainCustom = "custom";

// WHY: Keep one list for dropdown options and payload validation checks.
const List<String> productionDomainValues = [
  productionDomainFarm,
  productionDomainFashion,
  productionDomainManufacturing,
  productionDomainConstruction,
  productionDomainMedia,
  productionDomainFood,
  productionDomainCosmetics,
  productionDomainCustom,
];

// WHY: Generic is the default experience; it maps to the custom engine domain.
const String productionDomainDefault = productionDomainCustom;

String normalizeProductionDomainContext(String? raw) {
  final value = (raw ?? "").trim().toLowerCase();
  if (value.isEmpty || value == "generic") {
    return productionDomainDefault;
  }
  if (productionDomainValues.contains(value)) {
    return value;
  }
  return productionDomainDefault;
}

String formatProductionDomainLabel(String value) {
  switch (normalizeProductionDomainContext(value)) {
    case productionDomainFarm:
      return "Farm";
    case productionDomainFashion:
      return "Fashion";
    case productionDomainManufacturing:
      return "Manufacturing";
    case productionDomainConstruction:
      return "Construction";
    case productionDomainMedia:
      return "Media";
    case productionDomainFood:
      return "Food";
    case productionDomainCosmetics:
      return "Cosmetics";
    case productionDomainCustom:
    default:
      return "Generic";
  }
}
