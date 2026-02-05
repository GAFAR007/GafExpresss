/// lib/app/features/home/presentation/business_staff_attendance_filters_section.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Filter controls for staff attendance lists.
///
/// WHY:
/// - Lets managers switch between self/all, date range, and estate scope.
/// - Keeps filter rendering out of the main screen widget.
///
/// HOW:
/// - Uses dropdowns + date range picker to update filter state.
/// - Emits new filter selections via callback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_asset_api.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_constants.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_state.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _scopeAllValue = attendanceScopeAll;
const String _scopeSelfValue = attendanceScopeSelf;

class StaffAttendanceFiltersSection extends ConsumerWidget {
  final StaffAttendanceFilters filters;
  final AsyncValue<BusinessAssetsResult> assetsAsync;
  final bool canViewAll;
  final ValueChanged<StaffAttendanceFilters> onFiltersChanged;

  const StaffAttendanceFiltersSection({
    super.key,
    required this.filters,
    required this.assetsAsync,
    required this.canViewAll,
    required this.onFiltersChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: Scope switch lets managers toggle between self/all views.
        Text(
          staffAttendanceScopeLabel,
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          value: canViewAll ? filters.scope : _scopeSelfValue,
          decoration: const InputDecoration(),
          items: [
            DropdownMenuItem(
              value: _scopeSelfValue,
              child: Text(staffAttendanceScopeSelf),
            ),
            if (canViewAll)
              DropdownMenuItem(
                value: _scopeAllValue,
                child: Text(staffAttendanceScopeAll),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            onFiltersChanged(filters.copyWith(scope: value));
          },
        ),
        const SizedBox(height: AppSpacing.md),
        // WHY: Date range filter helps slice attendance windows.
        Text(
          staffAttendanceDateLabel,
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: () async {
            // WHY: Use the date picker for consistent date selection UX.
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(kDatePickerFirstYear),
              lastDate: DateTime(kDatePickerLastYear),
              initialDateRange: filters.dateRange,
            );
            onFiltersChanged(filters.copyWith(dateRange: range));
          },
          icon: const Icon(Icons.date_range),
          label: Text(
            filters.dateRange == null
                ? staffAttendanceDateLabel
                : "${formatDateLabel(filters.dateRange?.start)} → ${formatDateLabel(filters.dateRange?.end)}",
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // WHY: Estate filter groups attendance by asset ownership.
        Text(
          staffAttendanceEstateLabel,
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        assetsAsync.when(
          data: (assets) {
            // WHY: Show estate dropdown once assets are available.
            return DropdownButtonFormField<String>(
              value: filters.estateAssetId,
              decoration: const InputDecoration(),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text(staffAttendanceEstateAll),
                ),
                ...assets.assets.map(
                  (asset) => DropdownMenuItem(
                    value: asset.id,
                    child: Text(asset.name),
                  ),
                ),
              ],
              onChanged: (value) {
                onFiltersChanged(filters.copyWith(estateAssetId: value));
              },
            );
          },
          // WHY: Provide quick feedback while estates load.
          loading: () => LinearProgressIndicator(
            color: colorScheme.primary,
          ),
          // WHY: Explain failures so managers can retry later.
          error: (err, _) => Text(
            staffAttendanceErrorHelper,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
