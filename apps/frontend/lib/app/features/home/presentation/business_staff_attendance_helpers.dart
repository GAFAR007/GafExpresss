/// lib/app/features/home/presentation/business_staff_attendance_helpers.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Helper utilities for attendance filtering + display mapping.
///
/// WHY:
/// - Keeps list filtering logic out of widgets.
/// - Centralizes fallbacks for staff labels and estate scoping.
///
/// HOW:
/// - Builds staff lookup maps.
/// - Filters attendance by scope/date/estate.
/// - Resolves self staff profile by email.
library;

import 'package:frontend/app/features/home/presentation/business_staff_directory_list_helpers.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_state.dart';

const String _unknownStaff = staffDirectoryUnknownStaffLabel;
const String _roleOwner = "business_owner";
const String _roleStaff = "staff";
const String _roleEstateManager = "estate_manager";
const String _roleAccountant = "accountant";

Map<String, BusinessStaffProfileSummary> buildStaffMap(
  List<BusinessStaffProfileSummary> staff,
) {
  // WHY: Map by id so lookups stay O(1) in list rendering.
  return {for (final profile in staff) profile.id: profile};
}

String resolveStaffName(
  Map<String, BusinessStaffProfileSummary> staffMap,
  String staffProfileId,
) {
  // WHY: Always return a readable label even if data is missing.
  final profile = staffMap[staffProfileId];
  return profile?.userName ??
      profile?.userEmail ??
      _unknownStaff;
}

String? resolveStaffRole(
  Map<String, BusinessStaffProfileSummary> staffMap,
  String staffProfileId,
) {
  // WHY: Role is optional, so keep nullable.
  return staffMap[staffProfileId]?.staffRole;
}

String? resolveEstateId(
  Map<String, BusinessStaffProfileSummary> staffMap,
  String staffProfileId,
) {
  // WHY: Estate scope is used for filtering and grouping.
  return staffMap[staffProfileId]?.estateAssetId;
}

String? resolveSelfStaffProfileId({
  required List<BusinessStaffProfileSummary> staff,
  required String? userEmail,
}) {
  // WHY: Email match is the safest fallback when staffProfileId is missing.
  if (userEmail == null || userEmail.trim().isEmpty) return null;
  // WHY: Use a safe fallback object to avoid throwing from firstWhere.
  final match = staff.firstWhere(
    (profile) => (profile.userEmail ?? '')
        .toLowerCase()
        .trim() ==
        userEmail.toLowerCase().trim(),
    orElse: () => const BusinessStaffProfileSummary(
      id: '',
      userId: '',
      staffRole: '',
      status: '',
      estateAssetId: null,
      userName: null,
      userEmail: null,
      userPhone: null,
    ),
  );
  return match.id.isEmpty ? null : match.id;
}

List<StaffAttendanceRecord> filterAttendanceRecords({
  required List<StaffAttendanceRecord> records,
  required StaffAttendanceFilters filters,
  required Map<String, BusinessStaffProfileSummary> staffMap,
}) {
  // WHY: Apply filters locally to keep UI responsive without extra calls.
  return records.where((record) {
    if (filters.dateRange != null) {
      final range = filters.dateRange!;
      // WHY: Skip records outside the selected date window.
      if (record.clockInAt.isBefore(range.start) ||
          record.clockInAt.isAfter(range.end)) {
        return false;
      }
    }

    if (filters.estateAssetId != null &&
        filters.estateAssetId!.trim().isNotEmpty) {
      // WHY: Estate filter uses staff metadata rather than record data.
      final estateId = resolveEstateId(
        staffMap,
        record.staffProfileId,
      );
      if (estateId != filters.estateAssetId) {
        return false;
      }
    }

    return true;
  }).toList();
}

bool canViewAllAttendance({
  required String? actorRole,
  required String? staffRole,
}) {
  // WHY: Only owners and specific manager roles can view all staff.
  if (actorRole == null) return false;
  if (actorRole == _roleOwner) return true;
  return actorRole == _roleStaff &&
      (staffRole == _roleEstateManager ||
          staffRole == _roleAccountant);
}

bool canManageAttendance({
  required String? actorRole,
  required String? staffRole,
}) {
  // WHY: Only owners and estate managers can clock staff in/out.
  if (actorRole == null) return false;
  if (actorRole == _roleOwner) return true;
  return actorRole == _roleStaff && staffRole == _roleEstateManager;
}

String resolveScopeLabel(String scope) {
  // WHY: Keep labels consistent across filter UI and chips.
  return scope == attendanceScopeSelf
      ? attendanceScopeSelf
      : attendanceScopeAll;
}
