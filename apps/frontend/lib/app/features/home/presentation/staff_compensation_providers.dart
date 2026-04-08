/// lib/app/features/home/presentation/staff_compensation_providers.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Riverpod providers + actions for staff compensation data.
///
/// WHY:
/// - Keeps auth/session wiring out of UI widgets.
/// - Centralizes refresh/invalidation for compensation updates.
///
/// HOW:
/// - Builds StaffCompensationApi from shared Dio.
/// - Exposes fetch provider and upsert action helper.
/// - Logs provider lifecycle for diagnostics.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_compensation_api.dart';
import 'package:frontend/app/features/home/presentation/staff_compensation_model.dart';

// WHY: Centralize provider logging labels for consistency.
const String _logTag = "STAFF_COMP_PROVIDERS";
const String _apiProviderCreated = "staffCompensationApiProvider created";
const String _fetchStartMessage = "staffCompensationProvider fetch start";
const String _sessionMissingMessage = "session missing";
const String _sessionExpiredMessage = "Session expired. Please sign in again.";
const String _nextActionSignIn = "Sign in and retry.";
const String _reasonFetchMissing = "staff_comp_session_missing";
const String _reasonUpdateMissing = "staff_comp_update_session_missing";
const String _extraReasonKey = "reason";
const String _extraNextActionKey = "next_action";
const String _extraStaffKey = "staffProfileId";

final staffCompensationApiProvider = Provider<StaffCompensationApi>((ref) {
  AppDebug.log(_logTag, _apiProviderCreated);
  final dio = ref.read(dioProvider);
  return StaffCompensationApi(dio: dio);
});

final staffCompensationProvider =
    FutureProvider.family<StaffCompensation?, String>((ref, staffProfileId) async {
  AppDebug.log(
    _logTag,
    _fetchStartMessage,
    extra: {_extraStaffKey: staffProfileId},
  );

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

  final api = ref.read(staffCompensationApiProvider);
  return api.fetchCompensation(
    token: session.token,
    staffProfileId: staffProfileId,
  );
});

class StaffCompensationActions {
  final Ref _ref;

  StaffCompensationActions(this._ref);

  Future<StaffCompensation> upsertCompensation({
    required String staffProfileId,
    int? salaryAmountKobo,
    String? salaryCadence,
    String? payDay,
    String? notes,
  }) async {
    final session = _ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      AppDebug.log(
        _logTag,
        _sessionMissingMessage,
        extra: {
          _extraReasonKey: _reasonUpdateMissing,
          _extraStaffKey: staffProfileId,
          _extraNextActionKey: _nextActionSignIn,
        },
      );
      throw Exception(_sessionExpiredMessage);
    }

    final api = _ref.read(staffCompensationApiProvider);
    final compensation = await api.upsertCompensation(
      token: session.token,
      staffProfileId: staffProfileId,
      salaryAmountKobo: salaryAmountKobo,
      salaryCadence: salaryCadence,
      payDay: payDay,
      notes: notes,
    );

    // WHY: Ensure UI reflects the latest compensation after save.
    _ref.invalidate(staffCompensationProvider(staffProfileId));

    return compensation;
  }
}
