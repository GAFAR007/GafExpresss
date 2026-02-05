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
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_api.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_draft.dart';

// WHY: Consistent logs for production providers.
const String _logTag = "PRODUCTION_PROVIDERS";
const String _apiProviderCreated = "productionApiProvider created";
const String _plansFetchStart = "productionPlansProvider fetch start";
const String _planDetailFetchStart = "productionPlanDetailProvider fetch start";
const String _staffFetchStart = "productionStaffProvider fetch start";
const String _sessionMissingMessage = "session missing";
const String _sessionExpiredMessage = "Session expired. Please sign in again.";
const String _nextActionSignIn = "Sign in and retry.";
const String _extraReasonKey = "reason";
const String _extraNextActionKey = "next_action";
const String _extraPlanIdKey = "planId";
const String _reasonPlansMissing = "production_plans_session_missing";
const String _reasonDetailMissing = "production_detail_session_missing";
const String _reasonStaffMissing = "production_staff_session_missing";
const String _reasonCreateMissing = "production_create_session_missing";
const String _reasonDraftMissing = "production_draft_session_missing";
const String _reasonTaskStatusMissing = "production_task_status_session_missing";
const String _reasonTaskApproveMissing = "production_task_approve_session_missing";
const String _reasonTaskRejectMissing = "production_task_reject_session_missing";

final productionApiProvider = Provider<ProductionApi>((ref) {
  AppDebug.log(_logTag, _apiProviderCreated);
  final dio = ref.read(dioProvider);
  return ProductionApi(dio: dio);
});

final productionPlansProvider = FutureProvider<List<ProductionPlan>>((ref) async {
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
    final detail = await api.createPlan(
      token: session.token,
      payload: payload,
    );

    // WHY: Refresh list + detail caches after plan creation.
    _ref.invalidate(productionPlansProvider);
    _ref.invalidate(productionPlanDetailProvider(detail.plan.id));

    return detail;
  }

  Future<ProductionPlanDraftState> generateAiDraft({
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
    return api.generatePlanDraft(
      token: session.token,
      payload: payload,
    );
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
    final task = await api.approveTask(
      token: session.token,
      taskId: taskId,
    );

    _ref.invalidate(productionPlanDetailProvider(planId));
    return task;
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
    return task;
  }
}

final productionPlanActionsProvider =
    Provider<ProductionPlanActions>((ref) {
  return ProductionPlanActions(ref);
});
