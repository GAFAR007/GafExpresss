/// lib/app/features/home/presentation/production/production_routes.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Route constants for production plan screens.
///
/// WHY:
/// - Keeps route names centralized to avoid inline magic strings.
///
/// HOW:
/// - Exposes base paths and helpers for detail navigation.
library;

const String productionPlansRoute = "/business-production";
const String productionPlanAssistantRoute =
    "/business-production/create-assistant";
const String productionPlanCreateRoute = "/business-production/create";
const String productionPlanDetailRoute = "/business-production/:id";
const String productionPlanInsightsRoute = "/business-production/:id/insights";
const String productionCalendarRoute = "/business-production/calendar";
const String productionPlanArchiveRoute = "/business-production/archive";
const String productionPreorderReservationsRoute =
    "/business-production/preorder-reservations";

String productionPlanDetailPath(String id) {
  // WHY: Detail routes need to embed the plan id in the path.
  return "/business-production/$id";
}

String productionPlanInsightsPath(String id) {
  // WHY: Insights live on a separate route so the plan workspace can stay calendar-first.
  return "/business-production/$id/insights";
}
