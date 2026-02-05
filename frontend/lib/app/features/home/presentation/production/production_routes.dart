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
const String productionPlanCreateRoute = "/business-production/create";
const String productionPlanDetailRoute = "/business-production/:id";

String productionPlanDetailPath(String id) {
  // WHY: Detail routes need to embed the plan id in the path.
  return "/business-production/$id";
}
