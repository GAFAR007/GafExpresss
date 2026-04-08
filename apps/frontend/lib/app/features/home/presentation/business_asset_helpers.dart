/// lib/app/features/home/presentation/business_asset_helpers.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Shared helpers + select options for business asset flows.
///
/// WHY:
/// - Keeps asset enums in one place to avoid mismatches with backend.
/// - Centralizes conditional rules for required fields.
///
/// HOW:
/// - Provides option lists used by asset create/edit screens.
/// - Exposes helper guards for ownership + asset class requirements.
/// ------------------------------------------------------------------
library;

// WHY: Asset types must match backend enums exactly.
const List<Map<String, String>> assetTypeOptions = [
  {"value": "estate", "label": "Estate / Property"},
  {"value": "intangible", "label": "Intangible (Software/Licenses)"},
  {"value": "vehicle", "label": "Vehicle"},
  {"value": "equipment", "label": "Equipment"},
  {"value": "warehouse", "label": "Warehouse"},
  {"value": "inventory_asset", "label": "Inventory asset"},
  {"value": "other", "label": "Other"},
];

// WHY: Ownership type drives which financial fields are required.
const List<Map<String, String>> ownershipTypeOptions = [
  {"value": "owned", "label": "Owned"},
  {"value": "leased", "label": "Leased"},
  {"value": "rented_out", "label": "Rented out"},
  {"value": "managed_for_client", "label": "Managed for client"},
];

// WHY: Asset class impacts depreciation + reporting.
const List<Map<String, String>> assetClassOptions = [
  {"value": "fixed", "label": "Fixed asset"},
  {"value": "current", "label": "Current asset"},
];

// WHY: Rent periods match backend rent schedule enums.
const List<Map<String, String>> rentPeriodOptions = [
  {"value": "monthly", "label": "Monthly"},
  {"value": "quarterly", "label": "Quarterly"},
  {"value": "yearly", "label": "Yearly"},
];

// WHY: Fee periods align with backend lease/management enums.
const List<Map<String, String>> feePeriodOptions = [
  {"value": "monthly", "label": "Monthly"},
  {"value": "quarterly", "label": "Quarterly"},
  {"value": "yearly", "label": "Yearly"},
];

// WHY: Provide a stable default for users unsure about classification.
String assetClassForType(String assetType) {
  switch (assetType) {
    case 'inventory_asset':
      return 'current';
    default:
      return 'fixed';
  }
}

// WHY: Simple helper to keep conditional logic readable in UI.
bool requiresPurchaseFields(String assetClass, String ownershipType) {
  return assetClass == 'fixed' &&
      (ownershipType == 'owned' || ownershipType == 'rented_out');
}

// WHY: Lease fields only apply for leased assets.
bool requiresLeaseFields(String ownershipType) => ownershipType == 'leased';

// WHY: Management fee is required only for managed assets.
bool requiresManagementFields(String ownershipType) =>
    ownershipType == 'managed_for_client';

// WHY: Estate-specific fields are only relevant for properties.
bool isEstateType(String assetType) => assetType == 'estate';

// WHY: Inventory fields are only relevant for inventory assets.
bool isInventoryType(String assetType) => assetType == 'inventory_asset';
