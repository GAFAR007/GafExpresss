/// lib/app/features/home/presentation/business_staff_attendance_list_section.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Attendance list section with loading/empty/error states.
///
/// WHY:
/// - Keeps list rendering small and focused.
/// - Encapsulates state handling for attendance data.
///
/// HOW:
/// - Combines attendance + staff data to render names and roles.
/// - Applies filters before rendering list items.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/features/home/presentation/business_staff_attendance_constants.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_list_widgets.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_state.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StaffAttendanceListSection extends StatelessWidget {
  final AsyncValue<List<StaffAttendanceRecord>> attendanceAsync;
  final AsyncValue<List<BusinessStaffProfileSummary>> staffAsync;
  final StaffAttendanceFilters filters;
  final VoidCallback onRetry;

  const StaffAttendanceListSection({
    super.key,
    required this.attendanceAsync,
    required this.staffAsync,
    required this.filters,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return attendanceAsync.when(
      data: (records) {
        // WHY: Merge staff metadata so the list can show names/roles.
        final staffMap = staffAsync.when(
          data: (staff) => buildStaffMap(staff),
          error: (_, __) => <String, BusinessStaffProfileSummary>{},
          loading: () => <String, BusinessStaffProfileSummary>{},
        );
        // WHY: Apply filters before rendering to keep UI responsive.
        final filtered = filterAttendanceRecords(
          records: records,
          filters: filters,
          staffMap: staffMap,
        );

        if (filtered.isEmpty) {
          // WHY: Provide a friendly empty state when no matches exist.
          return _EmptyState(
            title: staffAttendanceEmptyTitle,
            helper: staffAttendanceEmptyHelper,
          );
        }

        // WHY: Render each record with staff metadata for clarity.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: filtered.map((record) {
            final staffName = resolveStaffName(staffMap, record.staffProfileId);
            final staffRole = resolveStaffRole(staffMap, record.staffProfileId);
            return StaffAttendanceListItem(
              record: record,
              staffName: staffName,
              staffRole: staffRole == null
                  ? null
                  : formatStaffRoleLabel(staffRole),
            );
          }).toList(),
        );
      },
      // WHY: Show loading indicator while fetching attendance.
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      // WHY: Provide retry to recover from transient failures.
      error: (err, _) => _ErrorState(
        title: staffAttendanceErrorTitle,
        helper: staffAttendanceErrorHelper,
        onRetry: onRetry,
        retryLabel: staffAttendanceRetryLabel,
        textTheme: textTheme,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String helper;

  const _EmptyState({
    required this.title,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Title explains why the list is empty.
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            helper,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String title;
  final String helper;
  final VoidCallback onRetry;
  final String retryLabel;
  final TextTheme textTheme;

  const _ErrorState({
    required this.title,
    required this.helper,
    required this.onRetry,
    required this.retryLabel,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Title clarifies the error state.
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            helper,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // WHY: Retry button lets users recover quickly.
          TextButton(
            onPressed: onRetry,
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}
