/// lib/app/features/home/presentation/business_staff_routes.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Route constants for business staff directory screens.
///
/// WHY:
/// - Avoids inline route strings across widgets and router.
/// - Keeps staff navigation consistent and reusable.
///
/// HOW:
/// - Exposes a single route path used by GoRouter + UI.
library;

// WHY: Centralize staff directory path to avoid inline route strings.
const String businessStaffDirectoryRoute = "/business-staff-directory";
const String _staffDetailBaseRoute = "/business-staff";
const String _staffDetailIdParam = "id";

// WHY: Staff detail route must be shared between list + router.
const String businessStaffDetailRoute = "$_staffDetailBaseRoute/:$_staffDetailIdParam";
const String businessStaffDetailBaseRoute = _staffDetailBaseRoute;

String businessStaffDetailPath(String staffProfileId) {
  return "$_staffDetailBaseRoute/$staffProfileId";
}
