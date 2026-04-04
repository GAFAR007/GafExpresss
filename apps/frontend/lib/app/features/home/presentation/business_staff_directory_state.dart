/// lib/app/features/home/presentation/business_staff_directory_state.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Filter state for the staff directory screen.
///
/// WHY:
/// - Keeps filter selections out of widgets.
/// - Lets list + filter sections share the same source of truth.
///
/// HOW:
/// - StateProvider stores the current filter selection.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// WHY: Sentinel allows copyWith to explicitly clear nullable filters.
const Object _unset = Object();

class StaffDirectoryFilters {
  final String? role;
  final String? status;
  final String? estateAssetId;

  const StaffDirectoryFilters({
    this.role,
    this.status,
    this.estateAssetId,
  });

  StaffDirectoryFilters copyWith({
    Object? role = _unset,
    Object? status = _unset,
    Object? estateAssetId = _unset,
  }) {
    return StaffDirectoryFilters(
      role: role == _unset ? this.role : role as String?,
      status: status == _unset ? this.status : status as String?,
      estateAssetId: estateAssetId == _unset
          ? this.estateAssetId
          : estateAssetId as String?,
    );
  }
}

final staffDirectoryFiltersProvider =
    StateProvider<StaffDirectoryFilters>((ref) {
  // WHY: Default to no filters so the full staff list is visible.
  return const StaffDirectoryFilters();
});
