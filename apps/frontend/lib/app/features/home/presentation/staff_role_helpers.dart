/// lib/app/features/home/presentation/staff_role_helpers.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Shared staff role/status constants + label helpers.
///
/// WHY:
/// - Keeps role values consistent across staff screens and filters.
/// - Avoids duplicated role lists and formatting logic.
///
/// HOW:
/// - Exposes role/status enums as const lists.
/// - Formats snake_case values for display.
library;

// WHY: Backend staff role values must stay consistent everywhere.
const String staffRoleAssetManager = "asset_manager";
const String staffRoleFarmManager = "farm_manager";
const String staffRoleEstateManager = "estate_manager";
const String staffRoleQualityControlManager = "quality_control_manager";
const String staffRoleCustomerCare = "customer_care";
const String staffRoleAccountant = "accountant";
const String staffRoleLawyer = "lawyer";
const String staffRoleShareholder = "shareholder";
const String staffRoleFieldAgent = "field_agent";
const String staffRoleCleaner = "cleaner";
const String staffRoleFarmer = "farmer";
const String staffRoleInventoryKeeper = "inventory_keeper";
const String staffRoleAuditor = "auditor";
const String staffRoleSecurity = "security";
const String staffRoleMaintenanceTechnician = "maintenance_technician";
const String staffRoleLogisticsDriver = "logistics_driver";

const List<String> staffRoleValues = [
  staffRoleAssetManager,
  staffRoleFarmManager,
  staffRoleEstateManager,
  staffRoleQualityControlManager,
  staffRoleCustomerCare,
  staffRoleAccountant,
  staffRoleLawyer,
  staffRoleShareholder,
  staffRoleFieldAgent,
  staffRoleCleaner,
  staffRoleFarmer,
  staffRoleInventoryKeeper,
  staffRoleAuditor,
  staffRoleSecurity,
  staffRoleMaintenanceTechnician,
  staffRoleLogisticsDriver,
];

// WHY: Staff status values power directory filters.
const List<String> staffStatusValues = ["active", "suspended", "terminated"];

const String staffLabelFallback = "Staff member";

String formatStaffRoleLabel(
  String raw, {
  String fallback = staffLabelFallback,
}) {
  if (raw.trim().isEmpty) return fallback;
  return raw.replaceAll("_", " ");
}
