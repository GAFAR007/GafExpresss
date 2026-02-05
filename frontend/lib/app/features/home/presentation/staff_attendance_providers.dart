/// lib/app/features/home/presentation/staff_attendance_providers.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Riverpod providers + actions for staff attendance.
///
/// WHY:
/// - Keeps auth/session wiring out of widgets.
/// - Centralizes refresh/invalidation for attendance updates.
///
/// HOW:
/// - Builds StaffAttendanceApi from shared Dio.
/// - Exposes list provider and clock-in/out helpers.
/// - Logs provider lifecycle for diagnostics.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_api.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';

// WHY: Centralize provider logging labels for consistency.
const String _logTag = "STAFF_ATTENDANCE_PROVIDERS";
const String _apiProviderCreated = "staffAttendanceApiProvider created";
const String _fetchStartMessage = "staffAttendanceProvider fetch start";
const String _sessionMissingMessage = "session missing";
const String _sessionExpiredMessage = "Session expired. Please sign in again.";
const String _nextActionSignIn = "Sign in and retry.";
const String _reasonFetchMissing = "staff_attendance_session_missing";
const String _reasonClockMissing = "staff_attendance_clock_session_missing";
const String _extraReasonKey = "reason";
const String _extraNextActionKey = "next_action";
const String _extraStaffKey = "staffProfileId";

final staffAttendanceApiProvider = Provider<StaffAttendanceApi>((ref) {
  // WHY: Log provider creation to troubleshoot DI wiring.
  AppDebug.log(_logTag, _apiProviderCreated);
  // WHY: Reuse the shared Dio instance for auth + interceptors.
  final dio = ref.read(dioProvider);
  return StaffAttendanceApi(dio: dio);
});

final staffAttendanceProvider =
    FutureProvider.family<List<StaffAttendanceRecord>, String?>(
        (ref, staffProfileId) async {
  AppDebug.log(
    _logTag,
    _fetchStartMessage,
    extra: {_extraStaffKey: staffProfileId},
  );

  // WHY: Block fetch when session is missing to avoid stale UI states.
  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log(
      _logTag,
      _sessionMissingMessage,
      extra: {
        _extraReasonKey: _reasonFetchMissing,
        _extraStaffKey: staffProfileId,
        _extraNextActionKey: _nextActionSignIn,
      },
    );
    throw Exception(_sessionExpiredMessage);
  }

  // WHY: Keep networking logic in the API client.
  final api = ref.read(staffAttendanceApiProvider);
  return api.fetchAttendance(
    token: session.token,
    staffProfileId: staffProfileId,
  );
});

class StaffAttendanceActions {
  final WidgetRef _ref;

  StaffAttendanceActions(this._ref);

  Future<StaffAttendanceRecord> clockIn({
    String? staffProfileId,
  }) async {
    // WHY: Ensure auth is valid before attempting a clock-in.
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonClockMissing,
          _extraStaffKey: staffProfileId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    // WHY: Delegate to API client so side effects stay centralized.
    final api = _ref.read(staffAttendanceApiProvider);
    final record = await api.clockIn(
      token: session.token,
      staffProfileId: staffProfileId,
    );

    // WHY: Ensure the list refreshes after a clock-in.
    _ref.invalidate(staffAttendanceProvider(staffProfileId));
    _ref.invalidate(staffAttendanceProvider(null));

    return record;
  }

  Future<StaffAttendanceRecord> clockOut({
    String? staffProfileId,
  }) async {
    // WHY: Ensure auth is valid before attempting a clock-out.
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonClockMissing,
          _extraStaffKey: staffProfileId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    // WHY: Delegate to API client so side effects stay centralized.
    final api = _ref.read(staffAttendanceApiProvider);
    final record = await api.clockOut(
      token: session.token,
      staffProfileId: staffProfileId,
    );

    // WHY: Ensure the list refreshes after a clock-out.
    _ref.invalidate(staffAttendanceProvider(staffProfileId));
    _ref.invalidate(staffAttendanceProvider(null));

    return record;
  }
}
