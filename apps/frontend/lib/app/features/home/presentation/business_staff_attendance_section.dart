/// lib/app/features/home/presentation/business_staff_attendance_section.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Full attendance module (KPIs, filters, actions, list).
///
/// WHY:
/// - Provides a complete attendance workflow inside staff detail screens.
/// - Keeps attendance UI logic encapsulated and reusable.
///
/// HOW:
/// - Wires attendance providers + filters.
/// - Renders KPI cards, filter controls, actions, and list states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_actions_container.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_constants.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_filters_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_kpi_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_list_section.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_providers.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_state.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class BusinessStaffAttendanceSection extends ConsumerWidget {
  final String? staffProfileId;

  const BusinessStaffAttendanceSection({
    super.key,
    required this.staffProfileId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // WHY: Log build to trace UI refreshes on filters and provider updates.
    AppDebug.log(
      staffAttendanceLogTag,
      staffAttendanceLogBuild,
      extra: {staffAttendanceLogStaffKey: staffProfileId},
    );

    // WHY: Read session + filters once for consistent rendering.
    final session = ref.watch(authSessionProvider);
    final filters = ref.watch(staffAttendanceFiltersProvider);
    final selectedStaffId = ref.watch(staffAttendanceSelectedStaffProvider);
    final staffAsync = ref.watch(productionStaffProvider);
    final assetsAsync =
        ref.watch(businessAssetsProvider(staffAttendanceAssetsQuery));

    // WHY: Build staff map for quick metadata lookups.
    final staffList = staffAsync.asData?.value ?? const [];
    final staffMap = buildStaffMap(staffList);
    final actorSelfStaffId = resolveSelfStaffProfileId(
      staff: staffList,
      userEmail: session?.user.email,
    );
    // WHY: Resolve "self" staff profile when detail screen id is missing.
    final selfStaffId = staffProfileId ??
        actorSelfStaffId;
    // WHY: Determine permissions based on staff role + user role.
    final selfStaffRole =
        selfStaffId == null ? null : staffMap[selfStaffId]?.staffRole;
    final canViewAll = canViewAllAttendance(
      actorRole: session?.user.role,
      staffRole: selfStaffRole,
    );
    final canManage = canManageAttendance(
      actorRole: session?.user.role,
      staffRole: selfStaffRole,
    );
    final canClockSelf = session?.user.role == "staff" &&
        actorSelfStaffId != null &&
        selfStaffId != null &&
        selfStaffId == actorSelfStaffId;
    // WHY: Clamp scope to self when the actor lacks full access.
    final effectiveScope = canViewAll ? filters.scope : attendanceScopeSelf;
    final staffIdForQuery =
        effectiveScope == attendanceScopeSelf ? selfStaffId : null;

    // WHY: Fetch attendance using scoped staff id when needed.
    final attendanceAsync =
        ref.watch(staffAttendanceProvider(staffIdForQuery));
    // WHY: Pre-filter records for KPI + list consistency.
    final filteredRecords = attendanceAsync.maybeWhen(
      data: (records) => filterAttendanceRecords(
        records: records,
        filters: filters.copyWith(scope: effectiveScope),
        staffMap: staffMap,
      ),
      orElse: () => const <StaffAttendanceRecord>[],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: KPI cards summarize attendance health quickly.
        StaffAttendanceKpiSection(records: filteredRecords),
        const SizedBox(height: AppSpacing.md),
        // WHY: Filters allow managers to adjust view scope and date range.
        StaffAttendanceFiltersSection(
          filters: filters.copyWith(scope: effectiveScope),
          assetsAsync: assetsAsync,
          canViewAll: canViewAll,
          onFiltersChanged: (next) {
            AppDebug.log(
              staffAttendanceLogTag,
              staffAttendanceLogFilterChange,
              extra: {staffAttendanceLogStaffKey: staffProfileId},
            );
            ref.read(staffAttendanceFiltersProvider.notifier).state = next;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        // WHY: Actions allow clock-in/out with optional staff selection.
        StaffAttendanceActionsContainer(
          canManage: canManage,
          canClockSelf: canClockSelf,
          staffOptions: staffList,
          selectedStaffId: selectedStaffId,
          onStaffChanged: (value) {
            ref.read(staffAttendanceSelectedStaffProvider.notifier).state =
                value;
          },
          staffProfileId: staffProfileId,
        ),
        const SizedBox(height: AppSpacing.md),
        // WHY: List section handles loading/empty/error states for attendance.
        StaffAttendanceListSection(
          attendanceAsync: attendanceAsync,
          staffAsync: staffAsync,
          filters: filters.copyWith(scope: effectiveScope),
          onRetry: () {
            AppDebug.log(
              staffAttendanceLogTag,
              staffAttendanceLogRetry,
              extra: {staffAttendanceLogStaffKey: staffProfileId},
            );
            final _ = ref.refresh(staffAttendanceProvider(staffIdForQuery));
          },
        ),
      ],
    );
  }
}
