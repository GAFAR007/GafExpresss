/// lib/app/features/home/presentation/production/production_providers.dart
/// ---------------------------------------------------------------------
/// WHAT:
/// - Riverpod providers + action helpers for production plan flows.
///
/// WHY:
/// - Keeps auth/session wiring out of widgets.
/// - Centralizes API calls and cache invalidation.
///
/// HOW:
/// - Builds ProductionApi from shared Dio.
/// - Exposes list/detail providers and action helpers.
/// - Logs provider lifecycle for diagnostics.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_assistant_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_calendar_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_api.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';

// WHY: Consistent logs for production providers.
const String _logTag = "PRODUCTION_PROVIDERS";
const String _apiProviderCreated = "productionApiProvider created";
const String _plansFetchStart = "productionPlansProvider fetch start";
const String _calendarFetchStart = "productionCalendarProvider fetch start";
const String _planDetailFetchStart = "productionPlanDetailProvider fetch start";
const String _planUnitsFetchStart = "productionPlanUnitsProvider fetch start";
const String _staffFetchStart = "productionStaffProvider fetch start";
const String _sessionMissingMessage = "session missing";
const String _sessionExpiredMessage = "Session expired. Please sign in again.";
const String _nextActionSignIn = "Sign in and retry.";
const String _extraReasonKey = "reason";
const String _extraNextActionKey = "next_action";
const String _extraPlanIdKey = "planId";
const String _extraCountKey = "count";
const String _extraFromKey = "from";
const String _extraToKey = "to";
const String _reasonPlansMissing = "production_plans_session_missing";
const String _reasonCalendarMissing = "production_calendar_session_missing";
const String _reasonDetailMissing = "production_detail_session_missing";
const String _reasonPlanUnitsMissing = "production_plan_units_session_missing";
const String _reasonStaffMissing = "production_staff_session_missing";
const String _reasonCreateMissing = "production_create_session_missing";
const String _reasonDraftMissing = "production_draft_session_missing";
const String _reasonPlanStatusMissing =
    "production_plan_status_session_missing";
const String _reasonPlanDeleteMissing =
    "production_plan_delete_session_missing";
const String _reasonSchedulePolicyMissing =
    "production_schedule_policy_session_missing";
const String _reasonSchedulePolicyUpdateMissing =
    "production_schedule_policy_update_session_missing";
const String _reasonPortfolioConfidenceMissing =
    "production_portfolio_confidence_session_missing";
const String _reasonStaffCapacityMissing =
    "production_staff_capacity_session_missing";
const String _reasonTaskStatusMissing =
    "production_task_status_session_missing";
const String _reasonTaskProgressMissing =
    "production_task_progress_session_missing";
const String _reasonTaskProgressBatchMissing =
    "production_task_progress_batch_session_missing";
const String _reasonTaskProgressApproveMissing =
    "production_task_progress_approve_session_missing";
const String _reasonTaskProgressRejectMissing =
    "production_task_progress_reject_session_missing";
const String _reasonTaskApproveMissing =
    "production_task_approve_session_missing";
const String _reasonTaskRejectMissing =
    "production_task_reject_session_missing";
const String _reasonDeviationVarianceMissing =
    "production_deviation_variance_session_missing";
const String _reasonDeviationReplanMissing =
    "production_deviation_replan_session_missing";
const String _reasonAssistantTurnMissing =
    "production_assistant_turn_session_missing";
const String _reasonPreorderMissing = "production_preorder_session_missing";
const String _reasonPreorderMonitoringMissing =
    "production_preorder_monitoring_session_missing";
const String _reasonPreorderReconcileMissing =
    "production_preorder_reconcile_session_missing";

final productionApiProvider = Provider<ProductionApi>((ref) {
  AppDebug.log(_logTag, _apiProviderCreated);
  final dio = ref.read(dioProvider);
  return ProductionApi(dio: dio);
});

final productionPlansProvider = FutureProvider<List<ProductionPlan>>((
  ref,
) async {
  AppDebug.log(_logTag, _plansFetchStart);

  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log(
      _logTag,
      _sessionMissingMessage,
      extra: {
        _extraReasonKey: _reasonPlansMissing,
        _extraNextActionKey: _nextActionSignIn,
      },
    );
    throw Exception(_sessionExpiredMessage);
  }

  final api = ref.read(productionApiProvider);
  final response = await api.fetchPlans(token: session.token);
  return response.plans;
});

class ProductionCalendarQuery {
  final DateTime from;
  final DateTime to;

  const ProductionCalendarQuery({required this.from, required this.to});

  String get fromInput => formatDateInput(from);
  String get toInput => formatDateInput(to);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductionCalendarQuery &&
        other.fromInput == fromInput &&
        other.toInput == toInput;
  }

  @override
  int get hashCode => Object.hash(fromInput, toInput);
}

final productionCalendarProvider =
    FutureProvider.family<ProductionCalendarResponse, ProductionCalendarQuery>((
      ref,
      query,
    ) async {
      AppDebug.log(
        _logTag,
        _calendarFetchStart,
        extra: {_extraFromKey: query.fromInput, _extraToKey: query.toInput},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonCalendarMissing,
            _extraFromKey: query.fromInput,
            _extraToKey: query.toInput,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchCalendar(
        token: session.token,
        fromDate: query.from,
        toDate: query.to,
      );
    });

final productionSchedulePolicyProvider =
    FutureProvider.family<ProductionSchedulePolicyResponse, String?>((
      ref,
      estateAssetId,
    ) async {
      AppDebug.log(
        _logTag,
        "productionSchedulePolicyProvider fetch start",
        extra: {_extraPlanIdKey: estateAssetId ?? ""},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonSchedulePolicyMissing,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchSchedulePolicy(
        token: session.token,
        estateAssetId: estateAssetId,
      );
    });

final productionStaffCapacityProvider =
    FutureProvider.family<ProductionStaffCapacitySummary, String?>((
      ref,
      estateAssetId,
    ) async {
      AppDebug.log(
        _logTag,
        "productionStaffCapacityProvider fetch start",
        extra: {_extraPlanIdKey: estateAssetId ?? ""},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonStaffCapacityMissing,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchStaffCapacity(
        token: session.token,
        estateAssetId: estateAssetId,
      );
    });

final productionPortfolioConfidenceProvider =
    FutureProvider.family<ProductionPortfolioConfidenceResponse?, String?>((
      ref,
      estateAssetId,
    ) async {
      AppDebug.log(
        _logTag,
        "productionPortfolioConfidenceProvider fetch start",
        extra: {_extraPlanIdKey: estateAssetId ?? ""},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonPortfolioConfidenceMissing,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchPortfolioConfidence(
        token: session.token,
        estateAssetId: estateAssetId,
      );
    });

final productionPlanDetailProvider =
    FutureProvider.family<ProductionPlanDetail, String>((ref, planId) async {
      AppDebug.log(
        _logTag,
        _planDetailFetchStart,
        extra: {_extraPlanIdKey: planId},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonDetailMissing,
            _extraPlanIdKey: planId,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchPlanDetail(token: session.token, planId: planId);
    });

final productionPlanUnitsProvider =
    FutureProvider.family<ProductionPlanUnitsResponse, String>((
      ref,
      planId,
    ) async {
      AppDebug.log(
        _logTag,
        _planUnitsFetchStart,
        extra: {_extraPlanIdKey: planId},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonPlanUnitsMissing,
            _extraPlanIdKey: planId,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchPlanUnits(token: session.token, planId: planId);
    });

final productionStaffProvider =
    FutureProvider<List<BusinessStaffProfileSummary>>((ref) async {
      AppDebug.log(_logTag, _staffFetchStart);

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonStaffMissing,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchStaffProfiles(token: session.token);
    });

class ProductionAiDraftRequest {
  final Map<String, dynamic> payload;

  const ProductionAiDraftRequest({required this.payload});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductionAiDraftRequest &&
        other.payload.toString() == payload.toString();
  }

  @override
  int get hashCode => payload.toString().hashCode;
}

final productionAiDraftProvider =
    FutureProvider.family<ProductionAiDraftResult, ProductionAiDraftRequest>((
      ref,
      request,
    ) async {
      AppDebug.log(
        _logTag,
        "productionAiDraftProvider fetch start",
        extra: {_extraCountKey: request.payload.length},
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          _logTag,
          _sessionMissingMessage,
          extra: {
            _extraReasonKey: _reasonDraftMissing,
            _extraNextActionKey: _nextActionSignIn,
          },
        );
        throw Exception(_sessionExpiredMessage);
      }

      final api = ref.read(productionApiProvider);
      return api.fetchAiDraftPlan(
        token: session.token,
        payload: request.payload,
      );
    });

class ProductionPlanActions {
  final Ref _ref;

  ProductionPlanActions(this._ref);

  Future<ProductionPlanDetail> createPlan({
    required Map<String, dynamic> payload,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonCreateMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final detail = await api.createPlan(token: session.token, payload: payload);

    // WHY: Refresh list + detail caches after plan creation.
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPlanDetailProvider(detail.plan.id));
    _ref.invalidate(productionPortfolioConfidenceProvider);

    return detail;
  }

  Future<ProductionAiDraftResult> generateAiDraft({
    required Map<String, dynamic> payload,
  }) async {
    // WHY: AI draft generation requires a valid session token.
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonDraftMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    // WHY: AI drafts are read-only and do not affect caches.
    return api.generatePlanDraft(token: session.token, payload: payload);
  }

  Future<ProductionPlan> updatePlanStatus({
    required String planId,
    required String status,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonPlanStatusMissing,
          _extraPlanIdKey: planId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final plan = await api.updatePlanStatus(
      token: session.token,
      planId: planId,
      status: status,
    );

    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return plan;
  }

  Future<String> deletePlan({required String planId}) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonPlanDeleteMissing,
          _extraPlanIdKey: planId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final message = await api.deletePlan(token: session.token, planId: planId);

    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return message;
  }

  Future<ProductionAssistantCatalogSearchResponse> searchAssistantCrops({
    required String query,
    required String domainContext,
    String? estateAssetId,
    int limit = 8,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonAssistantTurnMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    return api.searchAssistantCrops(
      token: session.token,
      query: query,
      domainContext: domainContext,
      estateAssetId: estateAssetId,
      limit: limit,
    );
  }

  Future<ProductionAssistantCropLifecyclePreviewResponse>
  previewAssistantCropLifecycle({
    required String productName,
    String? cropSubtype,
    required String domainContext,
    required String? estateAssetId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonAssistantTurnMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    return api.previewAssistantCropLifecycle(
      token: session.token,
      productName: productName,
      cropSubtype: cropSubtype,
      domainContext: domainContext,
      estateAssetId: estateAssetId,
    );
  }

  Future<ProductionAssistantTurnResponse> runAssistantTurn({
    required Map<String, dynamic> payload,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonAssistantTurnMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    return api.assistantTurn(token: session.token, payload: payload);
  }

  Future<ProductionSchedulePolicyResponse> updateSchedulePolicy({
    String? estateAssetId,
    required Map<String, dynamic> payload,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonSchedulePolicyUpdateMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final updated = await api.updateSchedulePolicy(
      token: session.token,
      estateAssetId: estateAssetId,
      payload: payload,
    );
    _ref.invalidate(productionSchedulePolicyProvider(estateAssetId));
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return updated;
  }

  Future<ProductionTask> updateTaskStatus({
    required String taskId,
    required String status,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskStatusMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final task = await api.updateTaskStatus(
      token: session.token,
      taskId: taskId,
      status: status,
    );

    // WHY: Keep detail view in sync after updates.
    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return task;
  }

  Future<ProductionTask> assignTaskStaffProfiles({
    required String taskId,
    required String planId,
    required List<String> assignedStaffProfileIds,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskStatusMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final task = await api.assignTaskStaffProfiles(
      token: session.token,
      taskId: taskId,
      assignedStaffProfileIds: assignedStaffProfileIds,
    );
    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return task;
  }

  Future<ProductionTask> approveTask({
    required String taskId,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskApproveMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final task = await api.approveTask(token: session.token, taskId: taskId);

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return task;
  }

  Future<ProductionTaskProgressRecord> logTaskProgress({
    required String taskId,
    required DateTime workDate,
    String? staffId,
    String? unitId,
    required num actualPlots,
    required String delayReason,
    required String notes,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskProgressMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final progress = await api.logTaskProgress(
      token: session.token,
      taskId: taskId,
      workDate: workDate,
      staffId: staffId,
      unitId: unitId,
      actualPlots: actualPlots,
      delayReason: delayReason,
      notes: notes,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return progress;
  }

  Future<ProductionTaskProgressBatchResponse> logTaskProgressBatch({
    required DateTime workDate,
    required List<ProductionTaskProgressBatchEntryInput> entries,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskProgressBatchMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final result = await api.logTaskProgressBatch(
      token: session.token,
      workDate: workDate,
      entries: entries,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return result;
  }

  Future<ProductionTaskProgressRecord> approveTaskProgress({
    required String progressId,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskProgressApproveMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final progress = await api.approveTaskProgress(
      token: session.token,
      progressId: progressId,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return progress;
  }

  Future<ProductionTaskProgressRecord> rejectTaskProgress({
    required String progressId,
    required String reason,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskProgressRejectMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final progress = await api.rejectTaskProgress(
      token: session.token,
      progressId: progressId,
      reason: reason,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return progress;
  }

  Future<ProductionTask> rejectTask({
    required String taskId,
    required String reason,
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonTaskRejectMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final task = await api.rejectTask(
      token: session.token,
      taskId: taskId,
      reason: reason,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return task;
  }

  Future<String> acceptDeviationVariance({
    required String planId,
    required String alertId,
    String? note,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonDeviationVarianceMissing,
          _extraPlanIdKey: planId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final message = await api.acceptDeviationVariance(
      token: session.token,
      planId: planId,
      alertId: alertId,
      note: note,
    );
    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return message;
  }

  Future<String> replanDeviationUnit({
    required String planId,
    required String alertId,
    required List<Map<String, dynamic>> taskAdjustments,
    String? note,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonDeviationReplanMissing,
          _extraPlanIdKey: planId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final message = await api.replanDeviationUnit(
      token: session.token,
      planId: planId,
      alertId: alertId,
      taskAdjustments: taskAdjustments,
      note: note,
    );
    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return message;
  }

  Future<ProductionPreorderSummary> updatePlanPreorder({
    required String planId,
    required Map<String, dynamic> payload,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonPreorderMissing,
          _extraPlanIdKey: planId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final summary = await api.updatePlanPreorder(
      token: session.token,
      planId: planId,
      payload: payload,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return summary;
  }

  Future<ProductionPreorderReservationListResponse> listPreorderReservations({
    String? status,
    String? planId,
    int page = 1,
    int limit = 20,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonPreorderMonitoringMissing,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    return api.listPreorderReservations(
      token: session.token,
      status: status,
      planId: planId,
      page: page,
      limit: limit,
    );
  }

  Future<ProductionPreorderReconcileSummary> reconcileExpiredPreorders({
    required String planId,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonPreorderReconcileMissing,
          _extraPlanIdKey: planId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(productionApiProvider);
    final summary = await api.reconcileExpiredPreorders(token: session.token);

    _ref.invalidate(productionPlanDetailProvider(planId));
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPortfolioConfidenceProvider);
    return summary;
  }
}

final productionPlanActionsProvider = Provider<ProductionPlanActions>((ref) {
  return ProductionPlanActions(ref);
});
