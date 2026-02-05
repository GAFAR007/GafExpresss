/// lib/app/features/home/presentation/staff_attendance_state.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Filter state for staff attendance screens.
///
/// WHY:
/// - Keeps filter selections out of widgets.
/// - Allows list + KPI sections to share a single source of truth.
///
/// HOW:
/// - StateProvider stores the current attendance filter selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// WHY: Sentinel allows copyWith to explicitly clear nullable filters.
const Object _unset = Object();

const String attendanceScopeSelf = "self";
const String attendanceScopeAll = "all";

class StaffAttendanceFilters {
  final String scope;
  final DateTimeRange? dateRange;
  final String? estateAssetId;

  const StaffAttendanceFilters({
    this.scope = attendanceScopeAll,
    this.dateRange,
    this.estateAssetId,
  });

  StaffAttendanceFilters copyWith({
    Object? scope = _unset,
    Object? dateRange = _unset,
    Object? estateAssetId = _unset,
  }) {
    return StaffAttendanceFilters(
      scope: scope == _unset ? this.scope : scope as String,
      dateRange: dateRange == _unset
          ? this.dateRange
          : dateRange as DateTimeRange?,
      estateAssetId: estateAssetId == _unset
          ? this.estateAssetId
          : estateAssetId as String?,
    );
  }
}

final staffAttendanceFiltersProvider =
    StateProvider<StaffAttendanceFilters>((ref) {
  // WHY: Default to "all" so managers see the full list.
  return const StaffAttendanceFilters();
});

final staffAttendanceSelectedStaffProvider = StateProvider<String?>((ref) {
  // WHY: Default to null so managers can decide before clocking.
  return null;
});
