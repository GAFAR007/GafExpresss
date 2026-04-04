/// lib/app/features/home/presentation/business_staff_directory_filters_section.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Filter controls for the staff directory (role, status, estate).
///
/// WHY:
/// - Lets owners/staff quickly narrow the staff list.
/// - Keeps filter UI reusable and separate from the screen scaffold.
///
/// HOW:
/// - Renders dropdowns inside a section card.
/// - Handles loading/error states for estate data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/features/home/presentation/business_asset_api.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_filter_widgets.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_sections.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_state.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _filtersTitle = "Filters";
const String _filtersHelper = "Use role, status, or estate to narrow results.";
const String _roleLabel = "Role";
const String _statusLabel = "Status";
const String _estateLabel = "Estate";
const String _allRolesLabel = "All roles";
const String _allStatusesLabel = "All statuses";
const String _allEstatesLabel = "All estates";
const String _clearFiltersLabel = "Clear filters";
const String _estateLoadingLabel = "Loading estates...";
const String _estateErrorTitle = "Unable to load estates";
const String _estateErrorHint = "Retry to fetch estate options.";
const String _retryLabel = "Try again";
const String _assetTypeEstate = "estate";

class StaffDirectoryFiltersSection extends StatelessWidget {
  final StaffDirectoryFilters filters;
  final AsyncValue<BusinessAssetsResult> assetsAsync;
  final ValueChanged<StaffDirectoryFilters> onFiltersChanged;
  final VoidCallback onRetryAssets;
  final VoidCallback onClearFilters;

  const StaffDirectoryFiltersSection({
    super.key,
    required this.filters,
    required this.assetsAsync,
    required this.onFiltersChanged,
    required this.onRetryAssets,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep all filters grouped in a single module card.
    return StaffDirectorySectionCard(
      title: _filtersTitle,
      helper: _filtersHelper,
      placeholderText: _allRolesLabel,
      child: Column(
        children: [
          StaffRoleDropdown(
            label: _roleLabel,
            selected: filters.role,
            roles: staffRoleValues,
            allRolesLabel: _allRolesLabel,
            formatLabel: (value) =>
                formatStaffRoleLabel(value, fallback: _allRolesLabel),
            onChanged: (value) => onFiltersChanged(
              filters.copyWith(role: value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StaffStatusDropdown(
            label: _statusLabel,
            selected: filters.status,
            statuses: staffStatusValues,
            allStatusesLabel: _allStatusesLabel,
            formatLabel: (value) =>
                formatStaffRoleLabel(value, fallback: _allStatusesLabel),
            onChanged: (value) => onFiltersChanged(
              filters.copyWith(status: value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          assetsAsync.when(
            loading: () => StaffEstateLoadingDropdown(
              label: _estateLabel,
              valueLabel: _estateLoadingLabel,
            ),
            error: (_, __) => StaffEstateErrorState(
              message: _estateErrorTitle,
              hint: _estateErrorHint,
              retryLabel: _retryLabel,
              onRetry: onRetryAssets,
            ),
            data: (result) => StaffEstateDropdown(
              label: _estateLabel,
              assets: result.assets
                  .where((asset) => asset.assetType == _assetTypeEstate)
                  .toList(),
              selected: filters.estateAssetId,
              allEstatesLabel: _allEstatesLabel,
              onChanged: (value) => onFiltersChanged(
                filters.copyWith(estateAssetId: value),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onClearFilters,
              child: const Text(_clearFiltersLabel),
            ),
          ),
        ],
      ),
    );
  }
}
