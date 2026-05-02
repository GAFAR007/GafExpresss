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
const String productionPlanDraftStudioRoute =
    "/business-production/draft-studio";
const String productionPlanDetailRoute = "/business-production/:id";
const String productionPlanTaskDetailRoute =
    "/business-production/:id/task/:taskId";
const String productionPlanInsightsRoute = "/business-production/:id/insights";
const String productionPlanInsightsViewQuery = "view";
const String productionPlanPhaseDetailRoute =
    "/business-production/:id/phase/:phaseId";
const String productionPlanPresenceStatsRoute =
    "/business-production/:id/presence-stats";
const String productionCalendarRoute = "/business-production/calendar";
const String productionPlanArchiveRoute = "/business-production/archive";
const String productionPreorderReservationsRoute =
    "/business-production/preorder-reservations";

String productionPlanDetailPath(String id) {
  // WHY: Detail routes need to embed the plan id in the path.
  return "/business-production/$id";
}

String productionPlanTaskDetailPath({
  required String planId,
  required String taskId,
}) {
  // WHY: Task detail routes need both ids so rows can deep-link into a
  // focused task screen without reopening the whole phase dashboard.
  return "/business-production/$planId/task/$taskId";
}

String productionPlanInsightsPath(String id, {String? view}) {
  // WHY: Insights live on a separate route so the plan workspace can stay calendar-first.
  final trimmedView = (view ?? "").trim();
  return Uri(
    path: "/business-production/$id/insights",
    queryParameters: trimmedView.isEmpty
        ? null
        : <String, String>{productionPlanInsightsViewQuery: trimmedView},
  ).toString();
}

String productionPlanPhaseDetailPath({
  required String planId,
  required String phaseId,
}) {
  // WHY: Phase detail routes need both plan and phase ids to deep-link directly into lifecycle sections.
  return "/business-production/$planId/phase/$phaseId";
}

String productionPlanPresenceStatsPath(String id) {
  // WHY: Presence stats live on a separate route so the draft view stays uncluttered.
  return "/business-production/$id/presence-stats";
}

String productionPlanDraftStudioPath({String? planId}) {
  final trimmedPlanId = (planId ?? "").trim();
  if (trimmedPlanId.isEmpty) {
    return productionPlanDraftStudioRoute;
  }
  return "$productionPlanDraftStudioRoute?planId=$trimmedPlanId";
}
