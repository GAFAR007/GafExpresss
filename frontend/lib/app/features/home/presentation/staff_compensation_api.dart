/// lib/app/features/home/presentation/staff_compensation_api.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - API client for staff compensation endpoints.
///
/// WHY:
/// - Keeps payroll networking out of widgets.
/// - Centralizes auth headers + error logging.
///
/// HOW:
/// - GET /business/staff/:id/compensation
/// - PATCH /business/staff/:id/compensation
/// - Logs start/success/failure with safe context.
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/staff_compensation_model.dart';

const String _logTag = "STAFF_COMP_API";
const String _serviceName = "staff_compensation_api";
const String _authHeaderKey = "Authorization";
const String _missingTokenMessage = "Missing auth token";
const String _missingTokenLog = "auth token missing";
const String _authOperation = "authOptions";
const String _authIntent = "ensure auth headers";
const String _intentFetch = "fetch staff compensation";
const String _intentUpsert = "update staff compensation";
const String _operationFetch = "fetchCompensation";
const String _operationUpsert = "upsertCompensation";
const String _nextActionRetry = "Retry the request or contact support.";
const String _fallbackErrorReason = "unknown_error";
const int _fallbackStatusCode = 0;
const String _keyCompensation = "compensation";
const String _keySalaryAmount = "salaryAmountKobo";
const String _keySalaryCadence = "salaryCadence";
const String _keyPayDay = "payDay";
const String _keyNotes = "notes";

const String _extraServiceKey = "service";
const String _extraOperationKey = "operation";
const String _extraIntentKey = "intent";
const String _extraNextActionKey = "next_action";
const String _extraStatusKey = "status";
const String _extraReasonKey = "reason";
const String _extraStaffIdKey = "staffProfileId";
const String _extraHasAmountKey = "hasAmount";
const String _extraHasCadenceKey = "hasCadence";

class StaffCompensationApi {
  final Dio _dio;

  StaffCompensationApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log(
        _logTag,
        _missingTokenLog,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _authOperation,
          _extraIntentKey: _authIntent,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      throw Exception(_missingTokenMessage);
    }
    return Options(headers: {_authHeaderKey: "Bearer $token"});
  }

  Future<StaffCompensation?> fetchCompensation({
    required String? token,
    required String staffProfileId,
  }) async {
    AppDebug.log(
      _logTag,
      "fetchCompensation() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationFetch,
        _extraIntentKey: _intentFetch,
        _extraStaffIdKey: staffProfileId,
      },
    );

    try {
      final resp = await _dio.get(
        "/business/staff/$staffProfileId/compensation",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final compMap = data[_keyCompensation];
      final comp = compMap is Map<String, dynamic>
          ? StaffCompensation.fromJson(compMap)
          : null;

      AppDebug.log(
        _logTag,
        "fetchCompensation() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationFetch,
          _extraIntentKey: _intentFetch,
          _extraStaffIdKey: staffProfileId,
        },
      );

      return comp;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchCompensation() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationFetch,
          _extraIntentKey: _intentFetch,
          _extraStaffIdKey: staffProfileId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<StaffCompensation> upsertCompensation({
    required String? token,
    required String staffProfileId,
    int? salaryAmountKobo,
    String? salaryCadence,
    String? payDay,
    String? notes,
  }) async {
    AppDebug.log(
      _logTag,
      "upsertCompensation() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationUpsert,
        _extraIntentKey: _intentUpsert,
        _extraStaffIdKey: staffProfileId,
        _extraHasAmountKey: salaryAmountKobo != null,
        _extraHasCadenceKey: salaryCadence != null && salaryCadence.trim().isNotEmpty,
      },
    );

    try {
      final payload = <String, dynamic>{
        if (salaryAmountKobo != null) _keySalaryAmount: salaryAmountKobo,
        if (salaryCadence != null && salaryCadence.trim().isNotEmpty)
          _keySalaryCadence: salaryCadence.trim(),
        if (payDay != null) _keyPayDay: payDay.trim(),
        if (notes != null) _keyNotes: notes.trim(),
      };

      final resp = await _dio.patch(
        "/business/staff/$staffProfileId/compensation",
        data: payload,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final compMap = (data[_keyCompensation] ?? {}) as Map<String, dynamic>;
      final comp = StaffCompensation.fromJson(compMap);

      AppDebug.log(
        _logTag,
        "upsertCompensation() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationUpsert,
          _extraIntentKey: _intentUpsert,
          _extraStaffIdKey: staffProfileId,
        },
      );

      return comp;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "upsertCompensation() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationUpsert,
          _extraIntentKey: _intentUpsert,
          _extraStaffIdKey: staffProfileId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }
}
