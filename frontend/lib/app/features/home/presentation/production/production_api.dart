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
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';

// WHY: Centralize endpoint paths to avoid inline magic strings.
const String _plansPath = "/business/production/plans";
const String _planDraftPath = "/business/production/plans/ai-draft";
const String _tasksPath = "/business/production/tasks";
const String _staffPath = "/business/staff";

// WHY: Keep logs consistent across production endpoints.
const String _logTag = "PRODUCTION_API";
const String _serviceName = "production_api";
const String _intentPlans = "load production plans";
const String _intentPlanDetail = "load production plan detail";
const String _intentPlanCreate = "create production plan";
const String _intentPlanDraft = "generate production plan draft";
const String _intentTaskStatus = "update production task status";
const String _intentTaskApprove = "approve production task";
const String _intentTaskReject = "reject production task";
const String _intentStaff = "load staff directory";
const String _operationAuth = "authOptions";
const String _operationPlans = "fetchPlans";
const String _operationPlanDetail = "fetchPlanDetail";
const String _operationPlanCreate = "createPlan";
const String _operationPlanDraft = "generatePlanDraft";
const String _operationTaskStatus = "updateTaskStatus";
const String _operationTaskApprove = "approveTask";
const String _operationTaskReject = "rejectTask";
const String _operationStaff = "fetchStaffProfiles";
const String _nextActionRetry = "Retry the request or contact support.";
const String _missingTokenMessage = "Missing auth token";
const String _missingTokenLog = "auth token missing";
const String _authIntent = "ensure auth headers";
const String _fallbackErrorReason = "unknown_error";
const int _fallbackStatusCode = 0;
const String _authHeaderKey = "Authorization";
const String _keyTask = "task";
const String _keyStaff = "staff";
const String _keyStatus = "status";
const String _keyReason = "reason";

// WHY: Keep log messages consistent and reusable.
const String _plansStartMessage = "fetchPlans() start";
const String _plansSuccessMessage = "fetchPlans() success";
const String _plansFailureMessage = "fetchPlans() failed";
const String _planDetailStartMessage = "fetchPlanDetail() start";
const String _planDetailSuccessMessage = "fetchPlanDetail() success";
const String _planDetailFailureMessage = "fetchPlanDetail() failed";
const String _planCreateStartMessage = "createPlan() start";
const String _planCreateSuccessMessage = "createPlan() success";
const String _planCreateFailureMessage = "createPlan() failed";
const String _planDraftStartMessage = "generatePlanDraft() start";
const String _planDraftSuccessMessage = "generatePlanDraft() success";
const String _planDraftFailureMessage = "generatePlanDraft() failed";
const String _taskStatusStartMessage = "updateTaskStatus() start";
const String _taskStatusSuccessMessage = "updateTaskStatus() success";
const String _taskStatusFailureMessage = "updateTaskStatus() failed";
const String _taskApproveStartMessage = "approveTask() start";
const String _taskApproveSuccessMessage = "approveTask() success";
const String _taskApproveFailureMessage = "approveTask() failed";
const String _taskRejectStartMessage = "rejectTask() start";
const String _taskRejectSuccessMessage = "rejectTask() success";
const String _taskRejectFailureMessage = "rejectTask() failed";
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
const String _extraStaffCountKey = "staffCount";
const String _extraPhaseCountKey = "phaseCount";

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
      final resp = await _dio.get(
        _plansPath,
        options: _authOptions(token),
      );

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
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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

  /// ------------------------------------------------------
  /// PLAN AI DRAFT
  /// ------------------------------------------------------
  Future<ProductionPlanDraftState> generatePlanDraft({
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
      final draftState = parseProductionPlanDraftResponse(data);

      // WHY: Log phase counts to validate draft completeness.
      AppDebug.log(
        _logTag,
        _planDraftSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDraft,
          _extraIntentKey: _intentPlanDraft,
          _extraPhaseCountKey: draftState.phases.length,
        },
      );

      return draftState;
    } on DioException catch (error) {
      // WHY: Capture status + response for debugging AI failures.
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _planDraftFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationPlanDraft,
          _extraIntentKey: _intentPlanDraft,
          _extraStatusKey: status,
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
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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
      final resp = await _dio.get(
        _staffPath,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final staffList = (data[_keyStaff] ?? []) as List<dynamic>;
      final staff = staffList
          .map((item) =>
              BusinessStaffProfileSummary.fromJson(item as Map<String, dynamic>))
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
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
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
