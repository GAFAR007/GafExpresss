/// lib/app/features/home/presentation/business_staff_directory_list_helpers.dart
/// ------------------------------------------------------------------------
/// WHAT:
/// - Helper functions for staff directory list grouping + filtering.
///
/// WHY:
/// - Keeps list widgets small and readable.
/// - Centralizes filtering and grouping logic.
///
/// HOW:
/// - Applies filters, builds estate name map, and groups staff.
library;

import 'package:frontend/app/core/formatters/phone_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_state.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';

const String staffDirectoryBusinessWideLabel = "Business-wide";
const String staffDirectoryUnknownEstateLabel = "Unknown estate";
const String staffDirectoryUnknownStaffLabel = staffLabelFallback;
const String _ngPhonePrefix = "+234";
const int _ngPhoneDigits = 10;

class StaffDirectoryGroup {
  final String label;
  final List<BusinessStaffProfileSummary> staff;

  const StaffDirectoryGroup({
    required this.label,
    required this.staff,
  });
}

Map<String, String> buildStaffDirectoryEstateMap(List<BusinessAsset> assets) {
  // WHY: Map estate ids to names for group headers.
  final map = <String, String>{};
  for (final asset in assets) {
    if (asset.id.trim().isEmpty) continue;
    map[asset.id] = asset.name;
  }
  return map;
}

List<StaffDirectoryGroup> buildStaffDirectoryGroups(
  List<BusinessStaffProfileSummary> staff,
  Map<String, String> estateMap,
) {
  // WHY: Group by estate scope so business-wide staff are separated.
  final groups = <String, List<BusinessStaffProfileSummary>>{};
  for (final profile in staff) {
    final key = profile.estateAssetId ?? staffDirectoryBusinessWideLabel;
    groups.putIfAbsent(key, () => []);
    groups[key]!.add(profile);
  }

  final entries = groups.entries.map((entry) {
    final label = entry.key == staffDirectoryBusinessWideLabel
        ? staffDirectoryBusinessWideLabel
        : estateMap[entry.key] ?? staffDirectoryUnknownEstateLabel;
    final sorted = [...entry.value]
      ..sort((a, b) => _buildSortKey(a).compareTo(_buildSortKey(b)));
    return StaffDirectoryGroup(label: label, staff: sorted);
  }).toList();

  entries.sort((a, b) {
    if (a.label == staffDirectoryBusinessWideLabel) return -1;
    if (b.label == staffDirectoryBusinessWideLabel) return 1;
    return a.label.compareTo(b.label);
  });
  return entries;
}

List<BusinessStaffProfileSummary> applyStaffDirectoryFilters(
  List<BusinessStaffProfileSummary> staff,
  StaffDirectoryFilters filters,
) {
  // WHY: Keep filtering centralized to avoid duplicated conditions.
  return staff.where((profile) {
    final matchesRole =
        filters.role == null || profile.staffRole == filters.role;
    final matchesStatus =
        filters.status == null || profile.status == filters.status;
    final matchesEstate = filters.estateAssetId == null ||
        profile.estateAssetId == filters.estateAssetId;
    return matchesRole && matchesStatus && matchesEstate;
  }).toList();
}

String buildStaffDisplayName(BusinessStaffProfileSummary profile) {
  // WHY: Always show a readable label even when name is missing.
  final phone = profile.userPhone == null
      ? null
      : formatPhoneDisplay(
          profile.userPhone,
          prefix: _ngPhonePrefix,
          maxDigits: _ngPhoneDigits,
        );
  return profile.userName ??
      profile.userEmail ??
      phone ??
      staffDirectoryUnknownStaffLabel;
}

String _buildSortKey(BusinessStaffProfileSummary profile) {
  return buildStaffDisplayName(profile).toLowerCase();
}
