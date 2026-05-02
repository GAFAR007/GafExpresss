/// lib/app/features/home/presentation/production/production_api.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - API client for production plan endpoints (plans, tasks, staff).
///
/// WHY:
/// - Keeps Dio networking out of widgets.
/// - Centralizes parsing + error logging for production flows.
///
/// HOW:
/// - Uses auth headers from session token.
/// - Maps responses into production models.
/// - Logs start/success/failure for each operation.
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_assistant_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_calendar_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';

// WHY: Centralize endpoint paths to avoid inline magic strings.
const String _plansPath = "/business/production/plans";
const String _calendarPath = "/business/production/calendar";
const String _assistantTurnPath = "/business/production/plans/assistant-turn";
const String _assistantCropSearchPath =
    "/business/production/plans/crop-search";
const String _assistantCropLifecyclePath =
    "/business/production/plans/crop-lifecycle";
const String _planDraftPath = "/business/production/plans/ai-draft";
const String _schedulePolicyPath = "/business/production/schedule-policy";
const String _tasksPath = "/business/production/tasks";
const String _taskProgressPath = "/business/production/task-progress";
const String _portfolioConfidencePath =
    "/business/production/confidence/portfolio";
const String _progressReportSuffix = "/progress-report";
const String _progressReportEmailSuffix = "/progress-report/email";
const String _proofDownloadAuditSuffix = "/proof-download-audit";
const String _preorderReconcilePath =
    "/business/preorder/reservations/reconcile-expired";
const String _preorderReservationsPath = "/business/preorder/reservations";
const String _staffPath = "/business/staff";
const String _staffCapacityPath = "/business/staff/capacity";

// WHY: Keep logs consistent across production endpoints.
const String _logTag = "PRODUCTION_API";
const String _serviceName = "production_api";
const String _intentPlans = "load production plans";
const String _intentCalendar = "load production calendar";
const String _intentAssistantTurn = "run production assistant turn";
const String _intentAssistantCropSearch =
    "search planner-backed production crops";
const String _intentAssistantCropLifecycle =
    "resolve selected crop lifecycle through planner backend";
const String _intentPlanDetail = "load production plan detail";
const String _intentPlanProgressReport = "load production progress report";
const String _intentPlanProgressReportEmail =
    "email production progress report";
const String _intentProofDownloadAudit =
    "audit production proof media download";
const String _intentPlanUnits = "load production plan units";
const String _intentPortfolioConfidence =
    "load production confidence portfolio";
const String _intentPlanCreate = "create production plan";
const String _intentPlanDraftUpdate = "update production draft";
const String _intentPlanStatusUpdate = "update production plan status";
const String _intentPlanDelete = "delete production plan draft";
const String _intentPlanDraft = "generate production plan draft";
const String _intentSchedulePolicy = "load production schedule policy";
const String _intentSchedulePolicyUpdate = "update production schedule policy";
const String _intentStaffCapacity = "load production staff capacity";
const String _intentPlanPreorder = "update production preorder state";
const String _intentPreorderReservations = "list preorder reservations";
const String _intentPreorderReconcile =
    "reconcile expired preorder reservations";
const String _intentTaskCreate = "create production task";
const String _intentTaskDelete = "delete production task";
const String _intentTaskStatus = "update production task status";
const String _intentTaskAssign = "assign production task staff profiles";
const String _intentTaskResetHistory = "reset production task history";
const String _intentTaskProgress = "log production task progress";
const String _intentTaskProgressBatch = "batch log production task progress";
const String _intentTaskProgressApprove = "approve production task progress";
const String _intentTaskProgressReject = "reject production task progress";
const String _intentTaskApprove = "approve production task";
const String _intentTaskReject = "reject production task";
const String _intentDeviationVariance = "accept deviation variance";
const String _intentDeviationReplan = "replan deviation-locked unit";
const String _intentStaff = "load staff directory";
const String _operationAuth = "authOptions";
const String _operationPlans = "fetchPlans";
const String _operationCalendar = "fetchCalendar";
const String _operationAssistantTurn = "assistantTurn";
const String _operationAssistantCropSearch = "searchAssistantCrops";
const String _operationAssistantCropLifecycle = "previewAssistantCropLifecycle";
const String _operationPlanDetail = "fetchPlanDetail";
const String _operationPlanProgressReport = "fetchPlanProgressReport";
const String _operationPlanProgressReportEmail = "emailPlanProgressReport";
const String _operationProofDownloadAudit = "auditProofDownload";
const String _operationPlanUnits = "fetchPlanUnits";
const String _operationPortfolioConfidence = "fetchPortfolioConfidence";
const String _operationPlanCreate = "createPlan";
const String _operationPlanDraftUpdate = "updateDraft";
const String _operationPlanStatusUpdate = "updatePlanStatus";
const String _operationPlanDelete = "deletePlan";
const String _operationPlanDraft = "generatePlanDraft";
const String _operationSchedulePolicy = "fetchSchedulePolicy";
const String _operationSchedulePolicyUpdate = "updateSchedulePolicy";
const String _operationStaffCapacity = "fetchStaffCapacity";
const String _operationPlanPreorder = "updatePlanPreorder";
const String _operationPreorderReservations = "listPreorderReservations";
const String _operationPreorderReconcile = "reconcileExpiredPreorders";
const String _operationTaskCreate = "createTask";
const String _operationTaskDelete = "deleteTask";
const String _operationTaskStatus = "updateTaskStatus";
const String _operationTaskAssign = "assignTaskStaffProfiles";
const String _operationTaskResetHistory = "resetTaskHistory";
const String _operationTaskProgress = "logTaskProgress";
const String _operationTaskProgressBatch = "logTaskProgressBatch";
const String _operationTaskProgressApprove = "approveTaskProgress";
const String _operationTaskProgressReject = "rejectTaskProgress";
const String _operationTaskApprove = "approveTask";
const String _operationTaskReject = "rejectTask";
const String _operationDeviationVariance = "acceptDeviationVariance";
const String _operationDeviationReplan = "replanDeviationUnit";
const String _operationStaff = "fetchStaffProfiles";
const String _nextActionRetry = "Retry the request or contact support.";
const String _missingTokenMessage = "Missing auth token";
const String _missingTokenLog = "auth token missing";
const String _authIntent = "ensure auth headers";
const String _fallbackErrorReason = "unknown_error";
const int _fallbackStatusCode = 0;
const String _authHeaderKey = "Authorization";
const String _keyFrom = "from";
const String _keyTo = "to";
const String _keyTask = "task";
const String _keyToEmail = "toEmail";
const String _keyRoutePath = "routePath";
const String _keyStaff = "staff";
const String _keyTaskId = "taskId";
const String _keyStatus = "status";
const String _keyReason = "reason";
const String _keyPreorderSummary = "preorderSummary";
const String _keyWorkDate = "workDate";
const String _keyEstateAssetId = "estateAssetId";
const String _keyStaffId = "staffId";
const String _keyUnitId = "unitId";
const String _keyAssignedStaffProfileIds = "assignedStaffProfileIds";
const String _keyActualPlots = "actualPlots";
const String _keyActualPlotUnits = "actualPlotUnits";
const String _keyUnitContribution = "unitContribution";
const String _keyUnitContributionPlotUnits = "unitContributionPlotUnits";
const String _keyCreateNewEntry = "createNewEntry";
const String _keyProofs = "proofs";
const String _keyQuantityActivityType = "quantityActivityType";
const String _keyQuantityAmount = "quantityAmount";
const String _keyQuantityUnit = "quantityUnit";
const String _keyActivityQuantityUnit = "activityQuantityUnit";
const String _keyActivityType = "activityType";
const String _keyActivityQuantity = "activityQuantity";
const String _keyDelayReason = "delayReason";
const String _keyNotes = "notes";
const String _keyNote = "note";
const String _keyEntries = "entries";
const String _keyTaskAdjustments = "taskAdjustments";
const String _keySummary = "summary";
const String _keyMessage = "message";
const String _keyPlan = "plan";
const String _keyPhaseId = "phaseId";
const String _keyTitle = "title";
const String _keyProductId = "productId";
const String _keyStartDate = "startDate";
const String _keyEndDate = "endDate";
const String _keyWorkloadContext = "workloadContext";
const String _keyTurn = "turn";
const String _keyPayload = "payload";
const String _keySuggestions = "suggestions";

// WHY: Keep log messages consistent and reusable.
const String _plansStartMessage = "fetchPlans() start";
const String _plansSuccessMessage = "fetchPlans() success";
const String _plansFailureMessage = "fetchPlans() failed";
const String _calendarStartMessage = "fetchCalendar() start";
const String _calendarSuccessMessage = "fetchCalendar() success";
const String _calendarFailureMessage = "fetchCalendar() failed";
const String _assistantTurnStartMessage = "assistantTurn() start";
const String _assistantTurnSuccessMessage = "assistantTurn() success";
const String _assistantTurnFailureMessage = "assistantTurn() failed";
const String _assistantTurnRecoveredMessage = "assistantTurn() recovered";
const String _assistantCropSearchStartMessage = "searchAssistantCrops() start";
const String _assistantCropSearchSuccessMessage =
    "searchAssistantCrops() success";
const String _assistantCropSearchFailureMessage =
    "searchAssistantCrops() failed";
const String _assistantCropLifecycleStartMessage =
    "previewAssistantCropLifecycle() start";
const String _assistantCropLifecycleSuccessMessage =
    "previewAssistantCropLifecycle() success";
const String _assistantCropLifecycleFailureMessage =
    "previewAssistantCropLifecycle() failed";
const String _planDetailStartMessage = "fetchPlanDetail() start";
const String _planDetailSuccessMessage = "fetchPlanDetail() success";
const String _planDetailFailureMessage = "fetchPlanDetail() failed";
const String _planProgressReportStartMessage =
    "fetchPlanProgressReport() start";
const String _planProgressReportSuccessMessage =
    "fetchPlanProgressReport() success";
const String _planProgressReportFailureMessage =
    "fetchPlanProgressReport() failed";
const String _planProgressReportEmailStartMessage =
    "emailPlanProgressReport() start";
const String _planProgressReportEmailSuccessMessage =
    "emailPlanProgressReport() success";
const String _planProgressReportEmailFailureMessage =
    "emailPlanProgressReport() failed";
const String _proofDownloadAuditStartMessage = "auditProofDownload() start";
const String _proofDownloadAuditSuccessMessage = "auditProofDownload() success";
const String _proofDownloadAuditFailureMessage = "auditProofDownload() failed";
const String _portfolioConfidenceStartMessage =
    "fetchPortfolioConfidence() start";
const String _portfolioConfidenceSuccessMessage =
    "fetchPortfolioConfidence() success";
const String _portfolioConfidenceFailureMessage =
    "fetchPortfolioConfidence() failed";
const String _planUnitsStartMessage = "fetchPlanUnits() start";
const String _planUnitsSuccessMessage = "fetchPlanUnits() success";
const String _planUnitsFailureMessage = "fetchPlanUnits() failed";
const String _planCreateStartMessage = "createPlan() start";
const String _planCreateSuccessMessage = "createPlan() success";
const String _planCreateFailureMessage = "createPlan() failed";
const String _planDraftUpdateStartMessage = "updateDraft() start";
const String _planDraftUpdateSuccessMessage = "updateDraft() success";
const String _planDraftUpdateFailureMessage = "updateDraft() failed";
const String _planStatusUpdateStartMessage = "updatePlanStatus() start";
const String _planStatusUpdateSuccessMessage = "updatePlanStatus() success";
const String _planStatusUpdateFailureMessage = "updatePlanStatus() failed";
const String _planDeleteStartMessage = "deletePlan() start";
const String _planDeleteSuccessMessage = "deletePlan() success";
const String _planDeleteFailureMessage = "deletePlan() failed";
const String _planDraftStartMessage = "generatePlanDraft() start";
const String _planDraftSuccessMessage = "generatePlanDraft() success";
const String _planDraftFailureMessage = "generatePlanDraft() failed";
const String _schedulePolicyStartMessage = "fetchSchedulePolicy() start";
const String _schedulePolicySuccessMessage = "fetchSchedulePolicy() success";
const String _schedulePolicyFailureMessage = "fetchSchedulePolicy() failed";
const String _schedulePolicyUpdateStartMessage = "updateSchedulePolicy() start";
const String _schedulePolicyUpdateSuccessMessage =
    "updateSchedulePolicy() success";
const String _schedulePolicyUpdateFailureMessage =
    "updateSchedulePolicy() failed";
const String _staffCapacityStartMessage = "fetchStaffCapacity() start";
const String _staffCapacitySuccessMessage = "fetchStaffCapacity() success";
const String _staffCapacityFailureMessage = "fetchStaffCapacity() failed";
const String _planPreorderStartMessage = "updatePlanPreorder() start";
const String _planPreorderSuccessMessage = "updatePlanPreorder() success";
const String _planPreorderFailureMessage = "updatePlanPreorder() failed";
const String _preorderReservationsStartMessage =
    "listPreorderReservations() start";
const String _preorderReservationsSuccessMessage =
    "listPreorderReservations() success";
const String _preorderReservationsFailureMessage =
    "listPreorderReservations() failed";
const String _preorderReconcileStartMessage =
    "reconcileExpiredPreorders() start";
const String _preorderReconcileSuccessMessage =
    "reconcileExpiredPreorders() success";
const String _preorderReconcileFailureMessage =
    "reconcileExpiredPreorders() failed";
const String _taskCreateStartMessage = "createTask() start";
const String _taskCreateSuccessMessage = "createTask() success";
const String _taskCreateFailureMessage = "createTask() failed";
const String _taskDeleteStartMessage = "deleteTask() start";
const String _taskDeleteSuccessMessage = "deleteTask() success";
const String _taskDeleteFailureMessage = "deleteTask() failed";
const String _taskStatusStartMessage = "updateTaskStatus() start";
const String _taskStatusSuccessMessage = "updateTaskStatus() success";
const String _taskStatusFailureMessage = "updateTaskStatus() failed";
const String _taskAssignStartMessage = "assignTaskStaffProfiles() start";
const String _taskAssignSuccessMessage = "assignTaskStaffProfiles() success";
const String _taskAssignFailureMessage = "assignTaskStaffProfiles() failed";
const String _taskResetHistoryStartMessage = "resetTaskHistory() start";
const String _taskResetHistorySuccessMessage = "resetTaskHistory() success";
const String _taskResetHistoryFailureMessage = "resetTaskHistory() failed";
const String _taskProgressStartMessage = "logTaskProgress() start";
const String _taskProgressSuccessMessage = "logTaskProgress() success";
const String _taskProgressFailureMessage = "logTaskProgress() failed";
const String _taskProgressBatchStartMessage = "logTaskProgressBatch() start";
const String _taskProgressBatchSuccessMessage =
    "logTaskProgressBatch() success";
const String _taskProgressBatchFailureMessage = "logTaskProgressBatch() failed";
const String _taskProgressApproveStartMessage = "approveTaskProgress() start";
const String _taskProgressApproveSuccessMessage =
    "approveTaskProgress() success";
const String _taskProgressApproveFailureMessage =
    "approveTaskProgress() failed";
const String _taskProgressRejectStartMessage = "rejectTaskProgress() start";
const String _taskProgressRejectSuccessMessage = "rejectTaskProgress() success";
const String _taskProgressRejectFailureMessage = "rejectTaskProgress() failed";
const String _taskApproveStartMessage = "approveTask() start";
const String _taskApproveSuccessMessage = "approveTask() success";
const String _taskApproveFailureMessage = "approveTask() failed";
const String _taskRejectStartMessage = "rejectTask() start";
const String _taskRejectSuccessMessage = "rejectTask() success";
const String _taskRejectFailureMessage = "rejectTask() failed";

int _toCanonicalProgressUnits(num value) {
  return (value * 1000).round();
}

const String _deviationVarianceStartMessage = "acceptDeviationVariance() start";
const String _deviationVarianceSuccessMessage =
    "acceptDeviationVariance() success";
const String _deviationVarianceFailureMessage =
    "acceptDeviationVariance() failed";
const String _deviationReplanStartMessage = "replanDeviationUnit() start";
const String _deviationReplanSuccessMessage = "replanDeviationUnit() success";
const String _deviationReplanFailureMessage = "replanDeviationUnit() failed";
const String _staffStartMessage = "fetchStaffProfiles() start";
const String _staffSuccessMessage = "fetchStaffProfiles() success";
const String _staffFailureMessage = "fetchStaffProfiles() failed";

// WHY: Keep extra fields consistent for diagnostics.
const String _extraServiceKey = "service";
const String _extraOperationKey = "operation";
const String _extraIntentKey = "intent";
const String _extraNextActionKey = "next_action";
const String _extraStatusKey = "status";
const String _extraReasonKey = "reason";
const String _extraCountKey = "count";
const String _extraPlanIdKey = "planId";
const String _extraTaskIdKey = "taskId";
const String _extraStaffIdKey = "staffId";
const String _extraProgressIdKey = "progressId";
const String _extraFromKey = "from";
const String _extraToKey = "to";
const String _extraEstateAssetIdKey = "estateAssetId";
const String _extraStaffCountKey = "staffCount";
const String _extraPhaseCountKey = "phaseCount";
const String _extraDraftStatusKey = "draftStatus";
const String _extraIssueTypeKey = "issueType";
const String _extraClassificationKey = "classification";
const String _extraErrorCodeKey = "errorCode";
const String _extraResolutionHintKey = "resolutionHint";
const String _extraRetryAllowedKey = "retryAllowed";
const String _extraRetryReasonKey = "retryReason";
const String _extraDetailsKey = "details";
const String _extraRequestContextKey = "requestContext";
const String _extraHasEstateKey = "hasEstate";
const String _extraHasProductKey = "hasProduct";
const String _extraHasStartDateKey = "hasStartDate";
const String _extraHasEndDateKey = "hasEndDate";
const String _extraHasWorkloadContextKey = "hasWorkloadContext";
const String _extraRecoveryPathKey = "recoveryPath";
const String _responseErrorKey = "error";
const String _responseClassificationKey = "classification";
const String _responseErrorCodeKey = "error_code";
const String _responseResolutionHintKey = "resolution_hint";
const String _responseDetailsKey = "details";
const String _responseRetryAllowedKey = "retry_allowed";
const String _responseRetryReasonKey = "retry_reason";
const int _httpBadRequest = 400;
const int _httpUnprocessable = 422;
const String _aiDraftFallbackClassification = "UNKNOWN_PROVIDER_ERROR";
const String _aiDraftFallbackErrorCode = "PRODUCTION_AI_DRAFT_FAILED";
const String _aiDraftFallbackResolutionHint =
    "Retry the request or adjust your AI prompt.";
const String _assistantFallbackClassification = "UNKNOWN_PROVIDER_ERROR";
const String _assistantFallbackErrorCode = "PRODUCTION_ASSISTANT_TURN_FAILED";
const String _assistantFallbackResolutionHint =
    "Retry with the selected estate and product context.";
const String _assistantRetryFallbackEnvelopeMessage =
    "Production assistant recovered from a retryable backend response.";
const String _assistantRetryFallbackTurnMessage =
    "Assistant provider is temporarily unavailable. I kept your context, so retry now.";
const String _assistantRetryFallbackSuggestionRetry =
    "Retry draft generation with current estate and product context.";
const String _assistantRetryFallbackSuggestionDates =
    "Add or adjust start/end dates, then retry.";
const String _assistantRetryFallbackSuggestionSupport =
    "If this keeps happening, check backend assistant logs.";
const Set<String> _assistantRetryableClassifications = <String>{
  "UNKNOWN_PROVIDER_ERROR",
  "PROVIDER_OUTAGE",
  "RATE_LIMITED",
  "AUTHENTICATION_ERROR",
  "PROVIDER_REJECTED_FORMAT",
};

String _sanitizeAssistantFailureMessage({
  required String message,
  required String errorCode,
  required String classification,
}) {
  final normalizedMessage = message.trim().toLowerCase();
  final normalizedErrorCode = errorCode.trim().toUpperCase();
  final normalizedClassification = classification.trim().toUpperCase();

  if (normalizedMessage.contains("cannot create a new collection") ||
      normalizedMessage.contains("too many collections") ||
      normalizedMessage.contains("already using")) {
    return "Planning storage is busy right now. Your context is still available, so retry draft generation.";
  }

  if (normalizedErrorCode ==
          "PRODUCTION_AI_PLANNER_V2_LIFECYCLE_AI_PARSE_FAILED" ||
      normalizedMessage.contains("did not return valid json")) {
    return "I could not structure the product lifecycle on the first try. Retry draft generation and I will regenerate it.";
  }

  if (normalizedClassification == "PROVIDER_REJECTED_FORMAT") {
    return "The planning assistant returned an invalid format. Retry draft generation with the same context.";
  }

  return message.trim().isNotEmpty
      ? message.trim()
      : _assistantRetryFallbackTurnMessage;
}

class ProductionApi {
  final Dio _dio;

  ProductionApi({required Dio dio}) : _dio = dio;

  // WHY: Production endpoints all require auth headers.
  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log(
        _logTag,
        _missingTokenLog,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAuth,
          _extraIntentKey: _authIntent,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      throw Exception(_missingTokenMessage);
    }
    return Options(headers: {_authHeaderKey: "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// LIST PRODUCTION PLANS
  /// ------------------------------------------------------
  Future<ProductionPlanListResponse> fetchPlans({
    required String? token,
  }) async {
    AppDebug.log(
      _logTag,
      _plansStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlans,
        _extraIntentKey: _intentPlans,
      },
    );

    try {
      final resp = await _dio.get(_plansPath, options: _authOptions(token));

      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionPlanListResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _plansSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlans,
          _extraIntentKey: _intentPlans,
          _extraCountKey: parsed.plans.length,
        },
      );

      return parsed;
    } on DioException catch (error) {
      // WHY: Assistant failures must expose structured diagnostics and avoid dropping chat UX on retryable backend responses.
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _plansFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlans,
          _extraIntentKey: _intentPlans,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// CALENDAR
  /// ------------------------------------------------------
  Future<ProductionCalendarResponse> fetchCalendar({
    required String? token,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final from = formatDateInput(fromDate);
    final to = formatDateInput(toDate);
    AppDebug.log(
      _logTag,
      _calendarStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationCalendar,
        _extraIntentKey: _intentCalendar,
        _extraFromKey: from,
        _extraToKey: to,
      },
    );

    try {
      final resp = await _dio.get(
        _calendarPath,
        queryParameters: {_keyFrom: from, _keyTo: to},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionCalendarResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _calendarSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationCalendar,
          _extraIntentKey: _intentCalendar,
          _extraFromKey: from,
          _extraToKey: to,
          _extraCountKey: parsed.items.length,
        },
      );

      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _calendarFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationCalendar,
          _extraIntentKey: _intentCalendar,
          _extraFromKey: from,
          _extraToKey: to,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// SCHEDULE POLICY
  /// ------------------------------------------------------
  Future<ProductionSchedulePolicyResponse> fetchSchedulePolicy({
    required String? token,
    String? estateAssetId,
  }) async {
    final scopedEstateId = estateAssetId?.trim() ?? "";
    AppDebug.log(
      _logTag,
      _schedulePolicyStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationSchedulePolicy,
        _extraIntentKey: _intentSchedulePolicy,
        _extraEstateAssetIdKey: scopedEstateId,
      },
    );

    try {
      final resp = await _dio.get(
        _schedulePolicyPath,
        queryParameters: scopedEstateId.isEmpty
            ? null
            : {_keyEstateAssetId: scopedEstateId},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final policy = ProductionSchedulePolicyResponse.fromJson(data);
      AppDebug.log(
        _logTag,
        _schedulePolicySuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationSchedulePolicy,
          _extraIntentKey: _intentSchedulePolicy,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraCountKey: policy.policy.blocks.length,
        },
      );
      return policy;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _schedulePolicyFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationSchedulePolicy,
          _extraIntentKey: _intentSchedulePolicy,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionSchedulePolicyResponse> updateSchedulePolicy({
    required String? token,
    String? estateAssetId,
    required Map<String, dynamic> payload,
  }) async {
    final scopedEstateId = estateAssetId?.trim() ?? "";
    AppDebug.log(
      _logTag,
      _schedulePolicyUpdateStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationSchedulePolicyUpdate,
        _extraIntentKey: _intentSchedulePolicyUpdate,
        _extraEstateAssetIdKey: scopedEstateId,
      },
    );

    try {
      final resp = await _dio.put(
        _schedulePolicyPath,
        queryParameters: scopedEstateId.isEmpty
            ? null
            : {_keyEstateAssetId: scopedEstateId},
        data: payload,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final policy = ProductionSchedulePolicyResponse.fromJson(data);
      AppDebug.log(
        _logTag,
        _schedulePolicyUpdateSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationSchedulePolicyUpdate,
          _extraIntentKey: _intentSchedulePolicyUpdate,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraCountKey: policy.policy.blocks.length,
        },
      );
      return policy;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _schedulePolicyUpdateFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationSchedulePolicyUpdate,
          _extraIntentKey: _intentSchedulePolicyUpdate,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionStaffCapacitySummary> fetchStaffCapacity({
    required String? token,
    String? estateAssetId,
  }) async {
    final scopedEstateId = estateAssetId?.trim() ?? "";
    AppDebug.log(
      _logTag,
      _staffCapacityStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationStaffCapacity,
        _extraIntentKey: _intentStaffCapacity,
        _extraEstateAssetIdKey: scopedEstateId,
      },
    );

    try {
      final resp = await _dio.get(
        _staffCapacityPath,
        queryParameters: scopedEstateId.isEmpty
            ? null
            : {_keyEstateAssetId: scopedEstateId},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final capacity = ProductionStaffCapacitySummary.fromJson(data);
      AppDebug.log(
        _logTag,
        _staffCapacitySuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationStaffCapacity,
          _extraIntentKey: _intentStaffCapacity,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraCountKey: capacity.roles.length,
        },
      );
      return capacity;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _staffCapacityFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationStaffCapacity,
          _extraIntentKey: _intentStaffCapacity,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// PLAN DETAIL
  /// ------------------------------------------------------
  Future<ProductionPlanDetail> fetchPlanDetail({
    required String? token,
    required String planId,
  }) async {
    AppDebug.log(
      _logTag,
      _planDetailStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanDetail,
        _extraIntentKey: _intentPlanDetail,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.get(
        "$_plansPath/$planId",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final detail = ProductionPlanDetail.fromJson(data);

      AppDebug.log(
        _logTag,
        _planDetailSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDetail,
          _extraIntentKey: _intentPlanDetail,
          _extraPlanIdKey: planId,
        },
      );

      return detail;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planDetailFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDetail,
          _extraIntentKey: _intentPlanDetail,
          _extraPlanIdKey: planId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionProgressReportResponse> fetchPlanProgressReport({
    required String? token,
    required String planId,
    required String routePath,
    String? toEmail,
  }) async {
    AppDebug.log(
      _logTag,
      _planProgressReportStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanProgressReport,
        _extraIntentKey: _intentPlanProgressReport,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.get(
        "$_plansPath/$planId$_progressReportSuffix",
        queryParameters: {
          _keyRoutePath: routePath,
          if ((toEmail ?? "").trim().isNotEmpty) _keyToEmail: toEmail!.trim(),
        },
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final report = ProductionProgressReportResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _planProgressReportSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanProgressReport,
          _extraIntentKey: _intentPlanProgressReport,
          _extraPlanIdKey: planId,
        },
      );

      return report;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planProgressReportFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanProgressReport,
          _extraIntentKey: _intentPlanProgressReport,
          _extraPlanIdKey: planId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionProgressReportEmailResponse> emailPlanProgressReport({
    required String? token,
    required String planId,
    required String toEmail,
    required String routePath,
  }) async {
    AppDebug.log(
      _logTag,
      _planProgressReportEmailStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanProgressReportEmail,
        _extraIntentKey: _intentPlanProgressReportEmail,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.post(
        "$_plansPath/$planId$_progressReportEmailSuffix",
        data: {_keyToEmail: toEmail, _keyRoutePath: routePath},
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final result = ProductionProgressReportEmailResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _planProgressReportEmailSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanProgressReportEmail,
          _extraIntentKey: _intentPlanProgressReportEmail,
          _extraPlanIdKey: planId,
        },
      );

      return result;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planProgressReportEmailFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanProgressReportEmail,
          _extraIntentKey: _intentPlanProgressReportEmail,
          _extraPlanIdKey: planId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<void> auditProofDownload({
    required String? token,
    required String planId,
    required String taskId,
    required String staffId,
    required DateTime workDate,
    required List<ProductionTaskProgressProofRecord> proofs,
  }) async {
    AppDebug.log(
      _logTag,
      _proofDownloadAuditStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationProofDownloadAudit,
        _extraIntentKey: _intentProofDownloadAudit,
        _extraPlanIdKey: planId,
        _extraTaskIdKey: taskId,
        _extraStaffIdKey: staffId,
        _extraCountKey: proofs.length,
      },
    );

    try {
      await _dio.post(
        "$_plansPath/$planId$_proofDownloadAuditSuffix",
        data: {
          _keyTaskId: taskId,
          _keyStaffId: staffId,
          _keyWorkDate: formatDateInput(workDate),
          _keyProofs: [
            for (final proof in proofs)
              {
                "url": proof.url,
                "publicId": proof.publicId,
                "filename": proof.filename,
                "mimeType": proof.mimeType,
                "sizeBytes": proof.sizeBytes,
                "uploadedAt": proof.uploadedAt?.toIso8601String(),
                "uploadedBy": proof.uploadedBy,
              },
          ],
        },
        options: _authOptions(token),
      );

      AppDebug.log(
        _logTag,
        _proofDownloadAuditSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationProofDownloadAudit,
          _extraIntentKey: _intentProofDownloadAudit,
          _extraPlanIdKey: planId,
          _extraTaskIdKey: taskId,
          _extraStaffIdKey: staffId,
          _extraCountKey: proofs.length,
        },
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _proofDownloadAuditFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationProofDownloadAudit,
          _extraIntentKey: _intentProofDownloadAudit,
          _extraPlanIdKey: planId,
          _extraTaskIdKey: taskId,
          _extraStaffIdKey: staffId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// PORTFOLIO CONFIDENCE
  /// ------------------------------------------------------
  Future<ProductionPortfolioConfidenceResponse?> fetchPortfolioConfidence({
    required String? token,
    String? estateAssetId,
  }) async {
    final scopedEstateId = estateAssetId?.trim() ?? "";
    AppDebug.log(
      _logTag,
      _portfolioConfidenceStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPortfolioConfidence,
        _extraIntentKey: _intentPortfolioConfidence,
        _extraEstateAssetIdKey: scopedEstateId,
      },
    );

    try {
      final resp = await _dio.get(
        _portfolioConfidencePath,
        queryParameters: scopedEstateId.isEmpty
            ? null
            : {_keyEstateAssetId: scopedEstateId},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionPortfolioConfidenceResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _portfolioConfidenceSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPortfolioConfidence,
          _extraIntentKey: _intentPortfolioConfidence,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraCountKey: parsed.summary.planCount,
        },
      );
      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _portfolioConfidenceFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPortfolioConfidence,
          _extraIntentKey: _intentPortfolioConfidence,
          _extraEstateAssetIdKey: scopedEstateId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      // WHY: Non-manager roles are expected to receive forbidden/disabled responses for portfolio confidence.
      if (status == 403 || status == 400) {
        return null;
      }
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// PLAN UNITS
  /// ------------------------------------------------------
  Future<ProductionPlanUnitsResponse> fetchPlanUnits({
    required String? token,
    required String planId,
  }) async {
    AppDebug.log(
      _logTag,
      _planUnitsStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanUnits,
        _extraIntentKey: _intentPlanUnits,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.get(
        "$_plansPath/$planId/units",
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionPlanUnitsResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _planUnitsSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanUnits,
          _extraIntentKey: _intentPlanUnits,
          _extraPlanIdKey: planId,
          _extraCountKey: parsed.totalUnits,
        },
      );
      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planUnitsFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanUnits,
          _extraIntentKey: _intentPlanUnits,
          _extraPlanIdKey: planId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// CREATE PLAN
  /// ------------------------------------------------------
  Future<ProductionPlanDetail> createPlan({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      _planCreateStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanCreate,
        _extraIntentKey: _intentPlanCreate,
      },
    );

    try {
      final resp = await _dio.post(
        _plansPath,
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final detail = ProductionPlanDetail.fromJson(data);

      AppDebug.log(
        _logTag,
        _planCreateSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanCreate,
          _extraIntentKey: _intentPlanCreate,
          _extraPlanIdKey: detail.plan.id,
        },
      );

      return detail;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planCreateFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanCreate,
          _extraIntentKey: _intentPlanCreate,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionPlanDetail> updateDraft({
    required String? token,
    required String planId,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      _planDraftUpdateStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanDraftUpdate,
        _extraIntentKey: _intentPlanDraftUpdate,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.put(
        "$_plansPath/$planId/draft",
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final detail = ProductionPlanDetail.fromJson(data);
      AppDebug.log(
        _logTag,
        _planDraftUpdateSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDraftUpdate,
          _extraIntentKey: _intentPlanDraftUpdate,
          _extraPlanIdKey: detail.plan.id,
        },
      );
      return detail;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planDraftUpdateFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDraftUpdate,
          _extraIntentKey: _intentPlanDraftUpdate,
          _extraPlanIdKey: planId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionPlan> updatePlanStatus({
    required String? token,
    required String planId,
    required String status,
  }) async {
    AppDebug.log(
      _logTag,
      _planStatusUpdateStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanStatusUpdate,
        _extraIntentKey: _intentPlanStatusUpdate,
        _extraPlanIdKey: planId,
        _extraStatusKey: status,
      },
    );

    try {
      final resp = await _dio.patch(
        "$_plansPath/$planId/status",
        data: {_keyStatus: status},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final planMap =
          (data[_keyPlan] ?? const <String, dynamic>{}) as Map<String, dynamic>;
      final plan = ProductionPlan.fromJson(planMap);

      AppDebug.log(
        _logTag,
        _planStatusUpdateSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanStatusUpdate,
          _extraIntentKey: _intentPlanStatusUpdate,
          _extraPlanIdKey: plan.id,
          _extraStatusKey: plan.status,
        },
      );

      return plan;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planStatusUpdateFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanStatusUpdate,
          _extraIntentKey: _intentPlanStatusUpdate,
          _extraPlanIdKey: planId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<String> deletePlan({
    required String? token,
    required String planId,
  }) async {
    AppDebug.log(
      _logTag,
      _planDeleteStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanDelete,
        _extraIntentKey: _intentPlanDelete,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.delete(
        "$_plansPath/$planId",
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final message = data[_keyMessage]?.toString().trim() ?? "";

      AppDebug.log(
        _logTag,
        _planDeleteSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDelete,
          _extraIntentKey: _intentPlanDelete,
          _extraPlanIdKey: planId,
        },
      );

      return message;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planDeleteFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDelete,
          _extraIntentKey: _intentPlanDelete,
          _extraPlanIdKey: planId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// UPDATE PREORDER STATE
  /// ------------------------------------------------------
  Future<ProductionPreorderSummary> updatePlanPreorder({
    required String? token,
    required String planId,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      _planPreorderStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanPreorder,
        _extraIntentKey: _intentPlanPreorder,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final resp = await _dio.patch(
        "$_plansPath/$planId/preorder",
        data: payload,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final summaryMap =
          (data[_keyPreorderSummary] ?? {}) as Map<String, dynamic>;
      final summary = ProductionPreorderSummary.fromJson(summaryMap);

      AppDebug.log(
        _logTag,
        _planPreorderSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanPreorder,
          _extraIntentKey: _intentPlanPreorder,
          _extraPlanIdKey: planId,
          _extraStatusKey: summary.productionState,
        },
      );

      return summary;
    } on DioException catch (error) {
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      final classification =
          responseMap[_responseClassificationKey]?.toString() ??
          _fallbackErrorReason;
      final errorCode =
          responseMap[_responseErrorCodeKey]?.toString() ??
          _fallbackErrorReason;
      final resolutionHint =
          responseMap[_responseResolutionHintKey]?.toString() ??
          _nextActionRetry;
      AppDebug.log(
        _logTag,
        _planPreorderFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanPreorder,
          _extraIntentKey: _intentPlanPreorder,
          _extraPlanIdKey: planId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraClassificationKey: classification,
          _extraErrorCodeKey: errorCode,
          _extraResolutionHintKey: resolutionHint,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// LIST PREORDER RESERVATIONS
  /// ------------------------------------------------------
  Future<ProductionPreorderReservationListResponse> listPreorderReservations({
    required String? token,
    String? status,
    String? planId,
    int page = 1,
    int limit = 20,
  }) async {
    AppDebug.log(
      _logTag,
      _preorderReservationsStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPreorderReservations,
        _extraIntentKey: _intentPreorderReservations,
        _extraPlanIdKey: (planId ?? "").trim(),
        _extraStatusKey: (status ?? "").trim(),
      },
    );

    try {
      final normalizedStatus = (status ?? "").trim();
      final normalizedPlanId = (planId ?? "").trim();
      final queryParameters = <String, dynamic>{"page": page, "limit": limit};
      if (normalizedStatus.isNotEmpty) {
        queryParameters["status"] = normalizedStatus;
      }
      if (normalizedPlanId.isNotEmpty) {
        queryParameters["planId"] = normalizedPlanId;
      }

      final resp = await _dio.get(
        _preorderReservationsPath,
        queryParameters: queryParameters,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionPreorderReservationListResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _preorderReservationsSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPreorderReservations,
          _extraIntentKey: _intentPreorderReservations,
          _extraCountKey: parsed.reservations.length,
          _extraStatusKey: parsed.filters.status,
        },
      );

      return parsed;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _preorderReservationsFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPreorderReservations,
          _extraIntentKey: _intentPreorderReservations,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// RECONCILE EXPIRED PREORDER HOLDS
  /// ------------------------------------------------------
  Future<ProductionPreorderReconcileSummary> reconcileExpiredPreorders({
    required String? token,
  }) async {
    AppDebug.log(
      _logTag,
      _preorderReconcileStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPreorderReconcile,
        _extraIntentKey: _intentPreorderReconcile,
      },
    );

    try {
      final resp = await _dio.post(
        _preorderReconcilePath,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final summaryMap = (data[_keySummary] ?? {}) as Map<String, dynamic>;
      final summary = ProductionPreorderReconcileSummary.fromJson(summaryMap);

      AppDebug.log(
        _logTag,
        _preorderReconcileSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPreorderReconcile,
          _extraIntentKey: _intentPreorderReconcile,
          _extraCountKey: summary.expiredCount,
        },
      );

      return summary;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _preorderReconcileFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPreorderReconcile,
          _extraIntentKey: _intentPreorderReconcile,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// ASSISTANT CROP SEARCH
  /// ------------------------------------------------------
  Future<ProductionAssistantCatalogSearchResponse> searchAssistantCrops({
    required String? token,
    required String query,
    required String domainContext,
    String? estateAssetId,
    int limit = 8,
  }) async {
    AppDebug.log(
      _logTag,
      _assistantCropSearchStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationAssistantCropSearch,
        _extraIntentKey: _intentAssistantCropSearch,
        "query": query.trim(),
        "domainContext": domainContext.trim(),
        "estateAssetId": (estateAssetId ?? "").trim(),
      },
    );

    try {
      final resp = await _dio.get(
        _assistantCropSearchPath,
        queryParameters: {
          "q": query.trim(),
          "domainContext": domainContext.trim(),
          if ((estateAssetId ?? "").trim().isNotEmpty)
            "estateAssetId": estateAssetId!.trim(),
          "limit": limit,
        },
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionAssistantCatalogSearchResponse.fromJson(data);
      AppDebug.log(
        _logTag,
        _assistantCropSearchSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAssistantCropSearch,
          _extraIntentKey: _intentAssistantCropSearch,
          _extraCountKey: parsed.items.length,
        },
      );
      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _assistantCropSearchFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAssistantCropSearch,
          _extraIntentKey: _intentAssistantCropSearch,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionAssistantCropLifecyclePreviewResponse>
  previewAssistantCropLifecycle({
    required String? token,
    required String productName,
    String? cropSubtype,
    required String domainContext,
    required String? estateAssetId,
  }) async {
    AppDebug.log(
      _logTag,
      _assistantCropLifecycleStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationAssistantCropLifecycle,
        _extraIntentKey: _intentAssistantCropLifecycle,
        "productName": productName.trim(),
        "cropSubtype": (cropSubtype ?? "").trim(),
        "domainContext": domainContext.trim(),
        "estateAssetId": (estateAssetId ?? "").trim(),
      },
    );

    try {
      final resp = await _dio.get(
        _assistantCropLifecyclePath,
        queryParameters: {
          "productName": productName.trim(),
          if ((cropSubtype ?? "").trim().isNotEmpty)
            "cropSubtype": cropSubtype!.trim(),
          "domainContext": domainContext.trim(),
          if ((estateAssetId ?? "").trim().isNotEmpty)
            "estateAssetId": estateAssetId!.trim(),
        },
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionAssistantCropLifecyclePreviewResponse.fromJson(
        data,
      );
      AppDebug.log(
        _logTag,
        _assistantCropLifecycleSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAssistantCropLifecycle,
          _extraIntentKey: _intentAssistantCropLifecycle,
          "lifecycleSource": parsed.lifecycleSource,
          "minDays": parsed.lifecycle.minDays,
          "maxDays": parsed.lifecycle.maxDays,
        },
      );
      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _assistantCropLifecycleFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAssistantCropLifecycle,
          _extraIntentKey: _intentAssistantCropLifecycle,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// PLAN ASSISTANT TURN
  /// ------------------------------------------------------
  Future<ProductionAssistantTurnResponse> assistantTurn({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      _assistantTurnStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationAssistantTurn,
        _extraIntentKey: _intentAssistantTurn,
      },
    );

    try {
      final resp = await _dio.post(
        _assistantTurnPath,
        data: payload,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionAssistantTurnResponse.fromJson(data);
      AppDebug.log(
        _logTag,
        _assistantTurnSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAssistantTurn,
          _extraIntentKey: _intentAssistantTurn,
          "action": parsed.turn.action,
        },
      );
      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final reason =
          rawData?.toString() ?? error.message ?? _fallbackErrorReason;
      final backendErrorMessage = (responseMap[_responseErrorKey] ?? "")
          .toString()
          .trim();
      final classification = (responseMap[_responseClassificationKey] ?? "")
          .toString()
          .trim()
          .toUpperCase();
      final errorCode = (responseMap[_responseErrorCodeKey] ?? "")
          .toString()
          .trim();
      final resolutionHint = (responseMap[_responseResolutionHintKey] ?? "")
          .toString()
          .trim();
      final retryAllowed = responseMap[_responseRetryAllowedKey] == true;
      final retryReason = (responseMap[_responseRetryReasonKey] ?? "")
          .toString()
          .trim();
      final sanitizedBackendErrorMessage = _sanitizeAssistantFailureMessage(
        message: backendErrorMessage,
        errorCode: errorCode,
        classification: classification,
      );
      final details =
          responseMap[_responseDetailsKey] ?? const <String, dynamic>{};
      final hasEstate = (payload[_keyEstateAssetId] ?? "")
          .toString()
          .trim()
          .isNotEmpty;
      final hasProduct = (payload[_keyProductId] ?? "")
          .toString()
          .trim()
          .isNotEmpty;
      final hasStartDate = (payload[_keyStartDate] ?? "")
          .toString()
          .trim()
          .isNotEmpty;
      final hasEndDate = (payload[_keyEndDate] ?? "")
          .toString()
          .trim()
          .isNotEmpty;
      final hasWorkloadContext = payload[_keyWorkloadContext] is Map;
      AppDebug.log(
        _logTag,
        _assistantTurnFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationAssistantTurn,
          _extraIntentKey: _intentAssistantTurn,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraClassificationKey: classification.isNotEmpty
              ? classification
              : _assistantFallbackClassification,
          _extraErrorCodeKey: errorCode.isNotEmpty
              ? errorCode
              : _assistantFallbackErrorCode,
          _extraResolutionHintKey: resolutionHint.isNotEmpty
              ? resolutionHint
              : _assistantFallbackResolutionHint,
          _extraRetryAllowedKey: retryAllowed,
          _extraRetryReasonKey: retryReason.isNotEmpty
              ? retryReason
              : _fallbackErrorReason,
          _extraDetailsKey: details,
          _extraRequestContextKey: {
            _extraHasEstateKey: hasEstate,
            _extraHasProductKey: hasProduct,
            _extraHasStartDateKey: hasStartDate,
            _extraHasEndDateKey: hasEndDate,
            _extraHasWorkloadContextKey: hasWorkloadContext,
          },
          _extraNextActionKey: _nextActionRetry,
        },
      );

      final hasBackendTurnPayload =
          responseMap[_keyTurn] is Map<String, dynamic>;
      final shouldRecoverDirectTurn =
          (status == _httpBadRequest || status == _httpUnprocessable) &&
          hasBackendTurnPayload;
      if (shouldRecoverDirectTurn) {
        // WHY: Some backend flows return a conversational turn on non-2xx; parsing it here avoids UI hard-failure bubbles.
        final recoveredResponse = ProductionAssistantTurnResponse.fromJson({
          _keyMessage:
              (responseMap[_keyMessage] ??
                      _assistantRetryFallbackEnvelopeMessage)
                  .toString()
                  .trim(),
          _keyTurn: responseMap[_keyTurn],
        });
        AppDebug.log(
          _logTag,
          _assistantTurnRecoveredMessage,
          extra: {
            _extraServiceKey: _serviceName,
            _extraOperationKey: _operationAssistantTurn,
            _extraIntentKey: _intentAssistantTurn,
            _extraStatusKey: status,
            _extraRecoveryPathKey: "backend_turn_payload",
            _extraClassificationKey: classification.isNotEmpty
                ? classification
                : _assistantFallbackClassification,
            _extraRetryAllowedKey: retryAllowed,
          },
        );
        return recoveredResponse;
      }

      final shouldRecoverRetryableFailure =
          (status == _httpBadRequest || status == _httpUnprocessable) &&
          (retryAllowed ||
              _assistantRetryableClassifications.contains(classification));
      if (shouldRecoverRetryableFailure) {
        // WHY: Assistant turn should stay conversational for retryable provider failures.
        final fallbackSuggestions = <String>[
          _assistantRetryFallbackSuggestionRetry,
          resolutionHint.isNotEmpty
              ? resolutionHint
              : _assistantRetryFallbackSuggestionDates,
          if (retryReason.isNotEmpty) "Retry reason: $retryReason",
          if (errorCode.isNotEmpty) "Error code: $errorCode",
          _assistantRetryFallbackSuggestionSupport,
        ].where((item) => item.trim().isNotEmpty).toList(growable: false);
        final recoveredResponse = ProductionAssistantTurnResponse.fromJson({
          _keyMessage: _assistantRetryFallbackEnvelopeMessage,
          _keyTurn: {
            "action": productionAssistantActionSuggestions,
            _keyMessage: backendErrorMessage.isNotEmpty
                ? sanitizedBackendErrorMessage
                : _assistantRetryFallbackTurnMessage,
            _keyPayload: {_keySuggestions: fallbackSuggestions},
          },
        });
        AppDebug.log(
          _logTag,
          _assistantTurnRecoveredMessage,
          extra: {
            _extraServiceKey: _serviceName,
            _extraOperationKey: _operationAssistantTurn,
            _extraIntentKey: _intentAssistantTurn,
            _extraStatusKey: status,
            _extraRecoveryPathKey: "synthetic_retry_suggestions",
            _extraClassificationKey: classification.isNotEmpty
                ? classification
                : _assistantFallbackClassification,
            _extraRetryAllowedKey: true,
            _extraRetryReasonKey: retryReason.isNotEmpty
                ? retryReason
                : _fallbackErrorReason,
          },
        );
        return recoveredResponse;
      }

      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// PLAN AI DRAFT
  /// ------------------------------------------------------
  Future<ProductionAiDraftResult> fetchAiDraftPlan({
    required String? token,
    required Map<String, dynamic> payload,
  }) {
    // WHY: Alias keeps naming aligned with create-screen draft preview intent.
    return generatePlanDraft(token: token, payload: payload);
  }

  Future<ProductionAiDraftResult> generatePlanDraft({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    // WHY: Log AI draft intent for observability.
    AppDebug.log(
      _logTag,
      _planDraftStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationPlanDraft,
        _extraIntentKey: _intentPlanDraft,
      },
    );

    try {
      // WHY: Send payload to backend AI draft endpoint.
      final resp = await _dio.post(
        _planDraftPath,
        data: payload,
        options: _authOptions(token),
      );

      // WHY: Parse response into draft state for UI use.
      final data = resp.data as Map<String, dynamic>;
      final draftResult = parseProductionPlanDraftResponse(data);

      // WHY: Log phase counts to validate draft completeness.
      AppDebug.log(
        _logTag,
        _planDraftSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDraft,
          _extraIntentKey: _intentPlanDraft,
          _extraPhaseCountKey: draftResult.draft.phases.length,
          _extraDraftStatusKey: draftResult.status,
          _extraIssueTypeKey:
              draftResult.partialIssue?.issueType ?? _fallbackErrorReason,
        },
      );

      return draftResult;
    } on DioException catch (error) {
      // WHY: Capture status + response for debugging AI failures.
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final reason =
          rawData?.toString() ?? error.message ?? _fallbackErrorReason;
      final classification = responseMap[_responseClassificationKey];
      final errorCode = responseMap[_responseErrorCodeKey];
      final resolutionHint = responseMap[_responseResolutionHintKey];
      final retryAllowed = responseMap[_responseRetryAllowedKey] == true;
      final retryReason =
          responseMap[_responseRetryReasonKey]?.toString() ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planDraftFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDraft,
          _extraIntentKey: _intentPlanDraft,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraClassificationKey:
              classification ?? _aiDraftFallbackClassification,
          _extraErrorCodeKey: errorCode ?? _aiDraftFallbackErrorCode,
          _extraResolutionHintKey:
              resolutionHint ?? _aiDraftFallbackResolutionHint,
          _extraRetryAllowedKey: retryAllowed,
          _extraRetryReasonKey: retryReason,
          _extraDetailsKey: responseMap[_responseDetailsKey] ?? const {},
          _extraNextActionKey: _nextActionRetry,
        },
      );

      final hasStructuredAiError =
          responseMap[_responseClassificationKey] != null ||
          responseMap[_responseErrorCodeKey] != null ||
          responseMap[_responseResolutionHintKey] != null;
      if ((status == _httpUnprocessable || status == _httpBadRequest) &&
          hasStructuredAiError) {
        final errorPayload = responseMap.isEmpty
            ? <String, dynamic>{
                _responseErrorKey: reason,
                _responseClassificationKey: _aiDraftFallbackClassification,
                _responseErrorCodeKey: _aiDraftFallbackErrorCode,
                _responseResolutionHintKey: _aiDraftFallbackResolutionHint,
                _responseRetryAllowedKey: true,
                _responseRetryReasonKey: _fallbackErrorReason,
                _responseDetailsKey: const <String, dynamic>{},
              }
            : responseMap;
        throw ProductionAiDraftError.fromBackend(
          errorPayload,
          statusCode: status,
        );
      }

      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// CREATE TASK
  /// ------------------------------------------------------
  Future<ProductionTask> createTask({
    required String? token,
    required String planId,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      _logTag,
      _taskCreateStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskCreate,
        _extraIntentKey: _intentTaskCreate,
        _extraPlanIdKey: planId,
        _keyPhaseId: payload[_keyPhaseId]?.toString() ?? "",
        _keyTitle: payload[_keyTitle]?.toString() ?? "",
      },
    );

    try {
      final resp = await _dio.post(
        "$_plansPath/$planId/tasks",
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final taskMap = (data[_keyTask] ?? {}) as Map<String, dynamic>;
      final task = ProductionTask.fromJson(taskMap);

      AppDebug.log(
        _logTag,
        _taskCreateSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskCreate,
          _extraIntentKey: _intentTaskCreate,
          _extraPlanIdKey: planId,
          _extraTaskIdKey: task.id,
        },
      );

      return task;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskCreateFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskCreate,
          _extraIntentKey: _intentTaskCreate,
          _extraPlanIdKey: planId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<String> deleteTask({
    required String? token,
    required String taskId,
  }) async {
    AppDebug.log(
      _logTag,
      _taskDeleteStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskDelete,
        _extraIntentKey: _intentTaskDelete,
        _extraTaskIdKey: taskId,
      },
    );

    try {
      final resp = await _dio.delete(
        "$_tasksPath/$taskId",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final message = (data[_keyMessage] ?? "").toString().trim();

      AppDebug.log(
        _logTag,
        _taskDeleteSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskDelete,
          _extraIntentKey: _intentTaskDelete,
          _extraTaskIdKey: taskId,
        },
      );

      return message.isNotEmpty ? message : "Production task deleted.";
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskDeleteFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskDelete,
          _extraIntentKey: _intentTaskDelete,
          _extraTaskIdKey: taskId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// UPDATE TASK STATUS
  /// ------------------------------------------------------
  Future<ProductionTask> updateTaskStatus({
    required String? token,
    required String taskId,
    required String status,
  }) async {
    AppDebug.log(
      _logTag,
      _taskStatusStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskStatus,
        _extraIntentKey: _intentTaskStatus,
        _extraTaskIdKey: taskId,
      },
    );

    try {
      final resp = await _dio.patch(
        "$_tasksPath/$taskId/status",
        data: {_keyStatus: status},
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final taskMap = (data[_keyTask] ?? {}) as Map<String, dynamic>;
      final task = ProductionTask.fromJson(taskMap);

      AppDebug.log(
        _logTag,
        _taskStatusSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskStatus,
          _extraIntentKey: _intentTaskStatus,
          _extraTaskIdKey: taskId,
        },
      );

      return task;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskStatusFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskStatus,
          _extraIntentKey: _intentTaskStatus,
          _extraTaskIdKey: taskId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<ProductionTask> assignTaskStaffProfiles({
    required String? token,
    required String taskId,
    required List<String> assignedStaffProfileIds,
  }) async {
    AppDebug.log(
      _logTag,
      _taskAssignStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskAssign,
        _extraIntentKey: _intentTaskAssign,
        _extraTaskIdKey: taskId,
        _extraCountKey: assignedStaffProfileIds.length,
      },
    );

    try {
      final resp = await _dio.put(
        "$_tasksPath/$taskId/assign",
        data: {_keyAssignedStaffProfileIds: assignedStaffProfileIds},
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final taskMap = (data[_keyTask] ?? {}) as Map<String, dynamic>;
      final task = ProductionTask.fromJson(taskMap);
      AppDebug.log(
        _logTag,
        _taskAssignSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskAssign,
          _extraIntentKey: _intentTaskAssign,
          _extraTaskIdKey: taskId,
        },
      );
      return task;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskAssignFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskAssign,
          _extraIntentKey: _intentTaskAssign,
          _extraTaskIdKey: taskId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<String> resetTaskHistory({
    required String? token,
    required String taskId,
    required DateTime workDate,
    required String staffId,
    String? notes,
  }) async {
    AppDebug.log(
      _logTag,
      _taskResetHistoryStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskResetHistory,
        _extraIntentKey: _intentTaskResetHistory,
        _extraTaskIdKey: taskId,
        _extraStaffIdKey: staffId,
      },
    );

    try {
      final payload = <String, dynamic>{
        _keyWorkDate: workDate.toIso8601String().split("T").first,
        _keyStaffId: staffId.trim(),
      };
      final normalizedNotes = notes?.trim() ?? "";
      if (normalizedNotes.isNotEmpty) {
        payload[_keyNotes] = normalizedNotes;
      }
      final resp = await _dio.post(
        "$_tasksPath/$taskId/reset-history",
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final message = (data[_keyMessage] ?? "").toString().trim();

      AppDebug.log(
        _logTag,
        _taskResetHistorySuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskResetHistory,
          _extraIntentKey: _intentTaskResetHistory,
          _extraTaskIdKey: taskId,
          _extraStaffIdKey: staffId,
        },
      );

      return message.isNotEmpty ? message : "Production history reset.";
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskResetHistoryFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskResetHistory,
          _extraIntentKey: _intentTaskResetHistory,
          _extraTaskIdKey: taskId,
          _extraStaffIdKey: staffId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// LOG TASK PROGRESS
  /// ------------------------------------------------------
  Future<ProductionTaskProgressRecord> logTaskProgress({
    required String? token,
    required String taskId,
    required DateTime workDate,
    String? staffId,
    String? unitId,
    bool createNewEntry = false,
    num? actualPlots,
    num? unitContribution,
    List<ProductionTaskProgressProofInput> proofs = const [],
    String? quantityActivityType,
    String? activityType,
    num? quantityAmount,
    num? activityQuantity,
    String? quantityUnit,
    required String delayReason,
    required String notes,
  }) async {
    AppDebug.log(
      _logTag,
      _taskProgressStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskProgress,
        _extraIntentKey: _intentTaskProgress,
        _extraTaskIdKey: taskId,
      },
    );

    try {
      final normalizedStaffId = staffId?.trim() ?? "";
      final normalizedUnitId = unitId?.trim() ?? "";
      final normalizedQuantityActivityType =
          (activityType ?? quantityActivityType)?.trim() ?? "";
      final normalizedQuantityUnit = quantityUnit?.trim() ?? "";
      final normalizedUnitContribution = unitContribution ?? actualPlots ?? 0;
      final normalizedUnitContributionPlotUnits = _toCanonicalProgressUnits(
        normalizedUnitContribution,
      );
      final normalizedActivityQuantity = activityQuantity ?? quantityAmount;
      final payload = <String, dynamic>{
        _keyWorkDate: workDate.toIso8601String().split("T").first,
        _keyDelayReason: delayReason,
        _keyNotes: notes,
      };
      if (createNewEntry) {
        payload[_keyCreateNewEntry] = true;
      }
      payload[_keyUnitContribution] = normalizedUnitContribution;
      payload[_keyActualPlots] = normalizedUnitContribution;
      payload[_keyUnitContributionPlotUnits] =
          normalizedUnitContributionPlotUnits;
      payload[_keyActualPlotUnits] = normalizedUnitContributionPlotUnits;
      if (normalizedStaffId.isNotEmpty) {
        payload[_keyStaffId] = normalizedStaffId;
      }
      if (normalizedUnitId.isNotEmpty) {
        payload[_keyUnitId] = normalizedUnitId;
      }
      if (normalizedQuantityActivityType.isNotEmpty) {
        payload[_keyActivityType] = normalizedQuantityActivityType;
        payload[_keyQuantityActivityType] = normalizedQuantityActivityType;
      }
      if (normalizedActivityQuantity != null) {
        payload[_keyActivityQuantity] = normalizedActivityQuantity;
        payload[_keyQuantityAmount] = normalizedActivityQuantity;
      }
      if (normalizedQuantityUnit.isNotEmpty) {
        payload[_keyQuantityUnit] = normalizedQuantityUnit;
        payload[_keyActivityQuantityUnit] = normalizedQuantityUnit;
      }
      final resp = proofs.isEmpty
          ? await _dio.post(
              "$_tasksPath/$taskId/progress",
              data: payload,
              options: _authOptions(token),
            )
          : await _dio.post(
              "$_tasksPath/$taskId/progress",
              data: () {
                final formData = FormData();
                for (final entry in payload.entries) {
                  formData.fields.add(
                    MapEntry(entry.key, entry.value.toString()),
                  );
                }
                for (final proof in proofs) {
                  formData.files.add(
                    MapEntry(
                      _keyProofs,
                      MultipartFile.fromBytes(
                        proof.bytes,
                        filename: proof.filename,
                      ),
                    ),
                  );
                }
                return formData;
              }(),
              options: Options(
                headers: _authOptions(token).headers,
                contentType: "multipart/form-data",
              ),
            );

      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionTaskProgressResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _taskProgressSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgress,
          _extraIntentKey: _intentTaskProgress,
          _extraTaskIdKey: taskId,
        },
      );

      return parsed.progress;
    } on DioException catch (error) {
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      final classification =
          responseMap[_responseClassificationKey]?.toString() ??
          _fallbackErrorReason;
      final errorCode =
          responseMap[_responseErrorCodeKey]?.toString() ??
          _fallbackErrorReason;
      final resolutionHint =
          responseMap[_responseResolutionHintKey]?.toString() ??
          _nextActionRetry;
      AppDebug.log(
        _logTag,
        _taskProgressFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgress,
          _extraIntentKey: _intentTaskProgress,
          _extraTaskIdKey: taskId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraClassificationKey: classification,
          _extraErrorCodeKey: errorCode,
          _extraResolutionHintKey: resolutionHint,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// BATCH LOG TASK PROGRESS
  /// ------------------------------------------------------
  Future<ProductionTaskProgressBatchResponse> logTaskProgressBatch({
    required String? token,
    required DateTime workDate,
    required List<ProductionTaskProgressBatchEntryInput> entries,
  }) async {
    AppDebug.log(
      _logTag,
      _taskProgressBatchStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskProgressBatch,
        _extraIntentKey: _intentTaskProgressBatch,
        _extraCountKey: entries.length,
      },
    );

    try {
      final payload = {
        _keyWorkDate: workDate.toIso8601String().split("T").first,
        _keyEntries: entries.map((entry) => entry.toJson()).toList(),
      };
      final resp = await _dio.post(
        "$_tasksPath/progress/batch",
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionTaskProgressBatchResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _taskProgressBatchSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgressBatch,
          _extraIntentKey: _intentTaskProgressBatch,
          _extraCountKey: parsed.summary.successCount,
        },
      );

      return parsed;
    } on DioException catch (error) {
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      final classification =
          responseMap[_responseClassificationKey]?.toString() ??
          _fallbackErrorReason;
      final errorCode =
          responseMap[_responseErrorCodeKey]?.toString() ??
          _fallbackErrorReason;
      final resolutionHint =
          responseMap[_responseResolutionHintKey]?.toString() ??
          _nextActionRetry;
      AppDebug.log(
        _logTag,
        _taskProgressBatchFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgressBatch,
          _extraIntentKey: _intentTaskProgressBatch,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraClassificationKey: classification,
          _extraErrorCodeKey: errorCode,
          _extraResolutionHintKey: resolutionHint,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// APPROVE TASK PROGRESS
  /// ------------------------------------------------------
  Future<ProductionTaskProgressRecord> approveTaskProgress({
    required String? token,
    required String progressId,
  }) async {
    AppDebug.log(
      _logTag,
      _taskProgressApproveStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskProgressApprove,
        _extraIntentKey: _intentTaskProgressApprove,
        _extraProgressIdKey: progressId,
      },
    );

    try {
      final resp = await _dio.post(
        "$_taskProgressPath/$progressId/approve",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionTaskProgressResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _taskProgressApproveSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgressApprove,
          _extraIntentKey: _intentTaskProgressApprove,
          _extraProgressIdKey: progressId,
        },
      );

      return parsed.progress;
    } on DioException catch (error) {
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      final classification =
          responseMap[_responseClassificationKey]?.toString() ??
          _fallbackErrorReason;
      final errorCode =
          responseMap[_responseErrorCodeKey]?.toString() ??
          _fallbackErrorReason;
      final resolutionHint =
          responseMap[_responseResolutionHintKey]?.toString() ??
          _nextActionRetry;
      AppDebug.log(
        _logTag,
        _taskProgressApproveFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgressApprove,
          _extraIntentKey: _intentTaskProgressApprove,
          _extraProgressIdKey: progressId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraClassificationKey: classification,
          _extraErrorCodeKey: errorCode,
          _extraResolutionHintKey: resolutionHint,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// REJECT TASK PROGRESS
  /// ------------------------------------------------------
  Future<ProductionTaskProgressRecord> rejectTaskProgress({
    required String? token,
    required String progressId,
    required String reason,
  }) async {
    AppDebug.log(
      _logTag,
      _taskProgressRejectStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskProgressReject,
        _extraIntentKey: _intentTaskProgressReject,
        _extraProgressIdKey: progressId,
      },
    );

    try {
      final resp = await _dio.post(
        "$_taskProgressPath/$progressId/reject",
        data: {_keyReason: reason},
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final parsed = ProductionTaskProgressResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _taskProgressRejectSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgressReject,
          _extraIntentKey: _intentTaskProgressReject,
          _extraProgressIdKey: progressId,
        },
      );

      return parsed.progress;
    } on DioException catch (error) {
      final rawData = error.response?.data;
      final responseMap = rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{};
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      final classification =
          responseMap[_responseClassificationKey]?.toString() ??
          _fallbackErrorReason;
      final errorCode =
          responseMap[_responseErrorCodeKey]?.toString() ??
          _fallbackErrorReason;
      final resolutionHint =
          responseMap[_responseResolutionHintKey]?.toString() ??
          _nextActionRetry;
      AppDebug.log(
        _logTag,
        _taskProgressRejectFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskProgressReject,
          _extraIntentKey: _intentTaskProgressReject,
          _extraProgressIdKey: progressId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraClassificationKey: classification,
          _extraErrorCodeKey: errorCode,
          _extraResolutionHintKey: resolutionHint,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// APPROVE TASK
  /// ------------------------------------------------------
  Future<ProductionTask> approveTask({
    required String? token,
    required String taskId,
  }) async {
    AppDebug.log(
      _logTag,
      _taskApproveStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskApprove,
        _extraIntentKey: _intentTaskApprove,
        _extraTaskIdKey: taskId,
      },
    );

    try {
      final resp = await _dio.post(
        "$_tasksPath/$taskId/approve",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final taskMap = (data[_keyTask] ?? {}) as Map<String, dynamic>;
      final task = ProductionTask.fromJson(taskMap);

      AppDebug.log(
        _logTag,
        _taskApproveSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskApprove,
          _extraIntentKey: _intentTaskApprove,
          _extraTaskIdKey: taskId,
        },
      );

      return task;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskApproveFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskApprove,
          _extraIntentKey: _intentTaskApprove,
          _extraTaskIdKey: taskId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// REJECT TASK
  /// ------------------------------------------------------
  Future<ProductionTask> rejectTask({
    required String? token,
    required String taskId,
    required String reason,
  }) async {
    AppDebug.log(
      _logTag,
      _taskRejectStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationTaskReject,
        _extraIntentKey: _intentTaskReject,
        _extraTaskIdKey: taskId,
      },
    );

    try {
      final resp = await _dio.post(
        "$_tasksPath/$taskId/reject",
        data: {_keyReason: reason},
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final taskMap = (data[_keyTask] ?? {}) as Map<String, dynamic>;
      final task = ProductionTask.fromJson(taskMap);

      AppDebug.log(
        _logTag,
        _taskRejectSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskReject,
          _extraIntentKey: _intentTaskReject,
          _extraTaskIdKey: taskId,
        },
      );

      return task;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _taskRejectFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationTaskReject,
          _extraIntentKey: _intentTaskReject,
          _extraTaskIdKey: taskId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// DEVIATION GOVERNANCE ACTIONS
  /// ------------------------------------------------------
  Future<String> acceptDeviationVariance({
    required String? token,
    required String planId,
    required String alertId,
    String? note,
  }) async {
    AppDebug.log(
      _logTag,
      _deviationVarianceStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationDeviationVariance,
        _extraIntentKey: _intentDeviationVariance,
        _extraPlanIdKey: planId,
      },
    );

    try {
      final payload = <String, dynamic>{};
      final normalizedNote = (note ?? "").trim();
      if (normalizedNote.isNotEmpty) {
        payload[_keyNote] = normalizedNote;
      }
      final resp = await _dio.post(
        "$_plansPath/$planId/deviation-alerts/$alertId/accept-variance",
        data: payload,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final message = data[_keyMessage]?.toString() ?? "";

      AppDebug.log(
        _logTag,
        _deviationVarianceSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDeviationVariance,
          _extraIntentKey: _intentDeviationVariance,
          _extraPlanIdKey: planId,
        },
      );

      return message;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _deviationVarianceFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDeviationVariance,
          _extraIntentKey: _intentDeviationVariance,
          _extraPlanIdKey: planId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<String> replanDeviationUnit({
    required String? token,
    required String planId,
    required String alertId,
    required List<Map<String, dynamic>> taskAdjustments,
    String? note,
  }) async {
    AppDebug.log(
      _logTag,
      _deviationReplanStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationDeviationReplan,
        _extraIntentKey: _intentDeviationReplan,
        _extraPlanIdKey: planId,
        _extraCountKey: taskAdjustments.length,
      },
    );

    try {
      final payload = <String, dynamic>{_keyTaskAdjustments: taskAdjustments};
      final normalizedNote = (note ?? "").trim();
      if (normalizedNote.isNotEmpty) {
        payload[_keyNote] = normalizedNote;
      }
      final resp = await _dio.post(
        "$_plansPath/$planId/deviation-alerts/$alertId/replan-unit",
        data: payload,
        options: _authOptions(token),
      );
      final data = resp.data as Map<String, dynamic>;
      final message = data[_keyMessage]?.toString() ?? "";

      AppDebug.log(
        _logTag,
        _deviationReplanSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDeviationReplan,
          _extraIntentKey: _intentDeviationReplan,
          _extraPlanIdKey: planId,
          _extraCountKey: taskAdjustments.length,
        },
      );

      return message;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _deviationReplanFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationDeviationReplan,
          _extraIntentKey: _intentDeviationReplan,
          _extraPlanIdKey: planId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// STAFF DIRECTORY
  /// ------------------------------------------------------
  Future<List<BusinessStaffProfileSummary>> fetchStaffProfiles({
    required String? token,
  }) async {
    AppDebug.log(
      _logTag,
      _staffStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationStaff,
        _extraIntentKey: _intentStaff,
      },
    );

    try {
      final resp = await _dio.get(_staffPath, options: _authOptions(token));

      final data = resp.data as Map<String, dynamic>;
      final staffList = (data[_keyStaff] ?? []) as List<dynamic>;
      final staff = staffList
          .map(
            (item) => BusinessStaffProfileSummary.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();

      AppDebug.log(
        _logTag,
        _staffSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationStaff,
          _extraIntentKey: _intentStaff,
          _extraStaffCountKey: staff.length,
        },
      );

      return staff;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _staffFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationStaff,
          _extraIntentKey: _intentStaff,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }
}
