/// lib/app/features/home/presentation/business_staff_attendance_actions_section.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Action controls for clock-in/out in attendance screens.
///
/// WHY:
/// - Keeps action wiring small and reusable.
/// - Allows managers to clock in/out on behalf of staff.
///
/// HOW:
/// - Optional staff selector for managers.
/// - Two action buttons that trigger clock-in/out callbacks.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/business_staff_attendance_constants.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StaffAttendanceActionsSection extends StatelessWidget {
  final bool canManage;
  final List<BusinessStaffProfileSummary> staffOptions;
  final String? selectedStaffId;
  final ValueChanged<String?> onStaffChanged;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;

  const StaffAttendanceActionsSection({
    super.key,
    required this.canManage,
    required this.staffOptions,
    required this.selectedStaffId,
    required this.onStaffChanged,
    required this.onClockIn,
    required this.onClockOut,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canManage) ...[
          // WHY: Managers need to choose which staff member to clock in/out.
          Text(staffAttendanceStaffLabel, style: textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: selectedStaffId,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text(staffAttendanceStaffPlaceholder),
              ),
              ...staffOptions.map(
                (staff) => DropdownMenuItem(
                  value: staff.id,
                  child: Text(staff.userName ?? staff.userEmail ?? staff.id),
                ),
              ),
            ],
            onChanged: onStaffChanged,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        // WHY: Keep actions side-by-side for quick time tracking.
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onClockIn,
                child: const Text(staffAttendanceClockInLabel),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: onClockOut,
                child: const Text(staffAttendanceClockOutLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
