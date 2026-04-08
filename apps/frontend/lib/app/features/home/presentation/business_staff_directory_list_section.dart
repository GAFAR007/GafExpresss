/// lib/app/features/home/presentation/business_staff_directory_list_section.dart
/// ------------------------------------------------------------------------
/// WHAT:
/// - Staff list section with grouping + drilldown actions.
///
/// WHY:
/// - Displays staff profiles grouped by estate scope.
/// - Supports filtering, sorting, and detail navigation.
///
/// HOW:
/// - Renders state-aware list content inside a section card.
/// - Groups staff by estate and sorts by display name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/features/home/presentation/business_asset_api.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_list_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_list_widgets.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_sections.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_state.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';

const String _listTitle = "Staff list";
const String _listHelper = "Tap a staff member to open their profile.";
const String _emptyTitle = "No staff found";
const String _emptyHint = "Try clearing filters or inviting more staff.";
const String _errorTitle = "Unable to load staff";
const String _errorHint = "Check your connection and try again.";
const String _retryLabel = "Try again";

class StaffDirectoryListSection extends StatelessWidget {
  final AsyncValue<List<BusinessStaffProfileSummary>> staffAsync;
  final AsyncValue<BusinessAssetsResult> assetsAsync;
  final StaffDirectoryFilters filters;
  final VoidCallback onRetry;

  const StaffDirectoryListSection({
    super.key,
    required this.staffAsync,
    required this.assetsAsync,
    required this.filters,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return StaffDirectorySectionCard(
      title: _listTitle,
      helper: _listHelper,
      placeholderText: _emptyTitle,
      child: staffAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (_, __) => StaffDirectoryErrorState(
          message: _errorTitle,
          hint: _errorHint,
          retryLabel: _retryLabel,
          onRetry: onRetry,
        ),
        data: (staff) {
          final estateMap = buildStaffDirectoryEstateMap(
            assetsAsync.valueOrNull?.assets ?? const [],
          );
          // WHY: Apply filters before grouping to keep list focused.
          final filtered = applyStaffDirectoryFilters(staff, filters);
          if (filtered.isEmpty) {
            return StaffDirectoryEmptyState(
              message: _emptyTitle,
              hint: _emptyHint,
            );
          }

          final groups = buildStaffDirectoryGroups(filtered, estateMap);
          return Column(
            children: groups
                .map((group) => StaffDirectoryGroupSection(
                      group: group,
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
