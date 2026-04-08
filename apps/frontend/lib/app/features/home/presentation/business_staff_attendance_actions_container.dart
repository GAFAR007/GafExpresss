/// lib/app/features/home/presentation/business_staff_attendance_actions_container.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Attendance action container that wires clock-in/out handlers.
///
/// WHY:
/// - Keeps action logic out of the main attendance section widget.
/// - Centralizes logging + snackbars for clock actions.
///
/// HOW:
/// - Uses StaffAttendanceActions to call backend.
/// - Shows SnackBars for success and validation hints.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_actions_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_attendance_constants.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_proof_flow.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_providers.dart';

class StaffAttendanceActionsContainer extends ConsumerWidget {
  final bool canManage;
  final List<BusinessStaffProfileSummary> staffOptions;
  final String? selectedStaffId;
  final ValueChanged<String?> onStaffChanged;
  final String? staffProfileId;

  const StaffAttendanceActionsContainer({
    super.key,
    required this.canManage,
    required this.staffOptions,
    required this.selectedStaffId,
    required this.onStaffChanged,
    required this.staffProfileId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StaffAttendanceActionsSection(
      canManage: canManage,
      staffOptions: staffOptions,
      selectedStaffId: selectedStaffId,
      onStaffChanged: onStaffChanged,
      onClockIn: () async {
        // WHY: Log taps so clock actions can be audited.
        AppDebug.log(
          staffAttendanceLogTag,
          staffAttendanceLogClockIn,
          extra: {staffAttendanceLogStaffKey: staffProfileId},
        );
        // WHY: Resolve action helper per tap to use current providers.
        final actions = StaffAttendanceActions(ref);
        final targetId = canManage ? selectedStaffId : null;
        if (canManage && targetId == null) {
          // WHY: Prevent manager actions without a chosen staff member.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(staffAttendanceSelectStaffPrompt)),
          );
          return;
        }
        // WHY: Trigger backend clock-in for the selected profile (or self).
        await actions.clockIn(staffProfileId: targetId);
        if (context.mounted) {
          // WHY: Confirm success so users know the action completed.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(staffAttendanceClockInSuccess)),
          );
        }
      },
      onClockOut: () async {
        // WHY: Log taps so clock actions can be audited.
        AppDebug.log(
          staffAttendanceLogTag,
          staffAttendanceLogClockOut,
          extra: {staffAttendanceLogStaffKey: staffProfileId},
        );
        // WHY: Resolve action helper per tap to use current providers.
        final actions = StaffAttendanceActions(ref);
        final targetId = canManage ? selectedStaffId : null;
        if (canManage && targetId == null) {
          // WHY: Prevent manager actions without a chosen staff member.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(staffAttendanceSelectStaffPrompt)),
          );
          return;
        }
        try {
          // WHY: Trigger backend clock-out for the selected profile (or self).
          final attendance = await actions.clockOut(staffProfileId: targetId);
          await requireAttendanceProofUpload(
            context: context,
            ref: ref,
            attendance: attendance,
            subjectLabel: _resolveSelectedStaffLabel(),
          );
          if (context.mounted) {
            // WHY: Confirm the complete clock-out + proof flow succeeded.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(staffAttendanceClockOutSuccess)),
            );
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(staffAttendanceErrorHelper)),
            );
          }
        }
      },
    );
  }

  String _resolveSelectedStaffLabel() {
    final trimmedSelectedId = selectedStaffId?.trim() ?? "";
    if (!canManage || trimmedSelectedId.isEmpty) {
      return staffProfileId?.trim().isNotEmpty == true
          ? staffProfileId!.trim()
          : "Staff member";
    }

    for (final staff in staffOptions) {
      final matchesSelectedId =
          staff.id.trim() == trimmedSelectedId ||
          staff.userId.trim() == trimmedSelectedId;
      if (!matchesSelectedId) {
        continue;
      }

      final name = (staff.userName?.trim().isNotEmpty == true)
          ? staff.userName!.trim()
          : trimmedSelectedId;
      final role = staff.staffRole.trim();
      return role.isEmpty ? name : "$name • $role";
    }

    return trimmedSelectedId;
  }
}
