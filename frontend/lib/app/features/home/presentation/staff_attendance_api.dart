/// lib/app/features/home/presentation/staff_attendance_api.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - API client for staff attendance endpoints.
///
/// WHY:
/// - Keeps attendance networking out of widgets.
/// - Centralizes auth headers + failure logging.
///
/// HOW:
/// - POST /business/staff/attendance/clock-in
/// - POST /business/staff/attendance/clock-out
/// - GET /business/staff/attendance?staffProfileId=...
/// - Logs start/success/failure with safe context.
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';

const String _logTag = "STAFF_ATTENDANCE_API";
const String _serviceName = "staff_attendance_api";
const String _authHeaderKey = "Authorization";
const String _missingTokenMessage = "Missing auth token";
const String _missingTokenLog = "auth token missing";
const String _authOperation = "authOptions";
const String _authIntent = "ensure auth headers";
const String _intentClockIn = "clock in staff";
const String _intentClockOut = "clock out staff";
const String _intentList = "list attendance";
const String _operationClockIn = "clockIn";
const String _operationClockOut = "clockOut";
const String _operationList = "listAttendance";
const String _nextActionRetry = "Retry the request or contact support.";
const String _fallbackErrorReason = "unknown_error";
const int _fallbackStatusCode = 0;
const String _keyAttendance = "attendance";
const String _keyStaffProfileId = "staffProfileId";

const String _attendancePath = "/business/staff/attendance";
const String _clockInPath = "/business/staff/attendance/clock-in";
const String _clockOutPath = "/business/staff/attendance/clock-out";

const String _extraServiceKey = "service";
const String _extraOperationKey = "operation";
const String _extraIntentKey = "intent";
const String _extraNextActionKey = "next_action";
const String _extraStatusKey = "status";
const String _extraReasonKey = "reason";
const String _extraStaffIdKey = "staffProfileId";
const String _extraCountKey = "count";

class StaffAttendanceApi {
  final Dio _dio;

  StaffAttendanceApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    // WHY: Block requests early when auth is missing to avoid noisy 401s.
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
    // WHY: Centralize Bearer header formatting to prevent drift.
    return Options(headers: {_authHeaderKey: "Bearer $token"});
  }

  Future<List<StaffAttendanceRecord>> fetchAttendance({
    required String? token,
    String? staffProfileId,
  }) async {
    // WHY: Log intent so we can trace list requests in logs.
    AppDebug.log(
      _logTag,
      "fetchAttendance() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationList,
        _extraIntentKey: _intentList,
        _extraStaffIdKey: staffProfileId,
      },
    );

    try {
      // WHY: Include staffProfileId only when querying a specific staff member.
      final resp = await _dio.get(
        _attendancePath,
        queryParameters: staffProfileId == null
            ? null
            : {_keyStaffProfileId: staffProfileId},
        options: _authOptions(token),
      );

      // WHY: Map backend payload into typed records for the UI.
      final data = resp.data as Map<String, dynamic>;
      final list = (data[_keyAttendance] ?? []) as List<dynamic>;
      final attendance = list
          .map((item) =>
              StaffAttendanceRecord.fromJson(item as Map<String, dynamic>))
          .toList();

      // WHY: Log success with counts for quick sanity checks.
      AppDebug.log(
        _logTag,
        "fetchAttendance() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationList,
          _extraIntentKey: _intentList,
          _extraStaffIdKey: staffProfileId,
          _extraCountKey: attendance.length,
        },
      );

      return attendance;
    } on DioException catch (error) {
      // WHY: Capture HTTP status + response text for debugging.
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "fetchAttendance() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationList,
          _extraIntentKey: _intentList,
          _extraStaffIdKey: staffProfileId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<StaffAttendanceRecord> clockIn({
    required String? token,
    String? staffProfileId,
  }) async {
    // WHY: Log intent so clock-in actions are traceable.
    AppDebug.log(
      _logTag,
      "clockIn() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationClockIn,
        _extraIntentKey: _intentClockIn,
        _extraStaffIdKey: staffProfileId,
      },
    );

    try {
      // WHY: Only send staffProfileId when clocking in as a manager.
      final payload = staffProfileId == null
          ? <String, dynamic>{}
          : {_keyStaffProfileId: staffProfileId};
      final resp = await _dio.post(
        _clockInPath,
        data: payload,
        options: _authOptions(token),
      );

      // WHY: Normalize response into our record model.
      final data = resp.data as Map<String, dynamic>;
      final attendanceMap = data[_keyAttendance] as Map<String, dynamic>;
      final record = StaffAttendanceRecord.fromJson(attendanceMap);

      // WHY: Log success so we can confirm time tracking actions.
      AppDebug.log(
        _logTag,
        "clockIn() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationClockIn,
          _extraIntentKey: _intentClockIn,
          _extraStaffIdKey: staffProfileId,
        },
      );

      return record;
    } on DioException catch (error) {
      // WHY: Keep error logging consistent across attendance calls.
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "clockIn() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationClockIn,
          _extraIntentKey: _intentClockIn,
          _extraStaffIdKey: staffProfileId,
          _extraStatusKey: statusCode,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  Future<StaffAttendanceRecord> clockOut({
    required String? token,
    String? staffProfileId,
  }) async {
    // WHY: Log intent so clock-out actions are traceable.
    AppDebug.log(
      _logTag,
      "clockOut() start",
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _operationClockOut,
        _extraIntentKey: _intentClockOut,
        _extraStaffIdKey: staffProfileId,
      },
    );

    try {
      // WHY: Only send staffProfileId when clocking out as a manager.
      final payload = staffProfileId == null
          ? <String, dynamic>{}
          : {_keyStaffProfileId: staffProfileId};
      final resp = await _dio.post(
        _clockOutPath,
        data: payload,
        options: _authOptions(token),
      );

      // WHY: Normalize response into our record model.
      final data = resp.data as Map<String, dynamic>;
      final attendanceMap = data[_keyAttendance] as Map<String, dynamic>;
      final record = StaffAttendanceRecord.fromJson(attendanceMap);

      // WHY: Log success so we can confirm time tracking actions.
      AppDebug.log(
        _logTag,
        "clockOut() success",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationClockOut,
          _extraIntentKey: _intentClockOut,
          _extraStaffIdKey: staffProfileId,
        },
      );

      return record;
    } on DioException catch (error) {
      // WHY: Keep error logging consistent across attendance calls.
      final statusCode = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ?? error.message ?? _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        "clockOut() failed",
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _operationClockOut,
          _extraIntentKey: _intentClockOut,
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
