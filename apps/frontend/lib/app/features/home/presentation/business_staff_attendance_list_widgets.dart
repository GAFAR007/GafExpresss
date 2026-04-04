/// lib/app/features/home/presentation/business_staff_attendance_list_widgets.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Attendance list item widgets.
///
/// WHY:
/// - Keeps card layout small and reusable.
/// - Prevents list sections from growing too large.
///
/// HOW:
/// - Renders staff name, role, and clock-in/out timestamps.
/// - Displays status chips for open/closed sessions.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _statusOpen = "OPEN";
const String _statusClosed = "CLOSED";
const String _labelClockIn = "Clock in";
const String _labelClockOut = "Clock out";
const String _labelDuration = "Duration";
const String _minutesSuffix = " mins";

class StaffAttendanceListItem extends StatelessWidget {
  final StaffAttendanceRecord record;
  final String staffName;
  final String? staffRole;

  const StaffAttendanceListItem({
    super.key,
    required this.record,
    required this.staffName,
    required this.staffRole,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    // WHY: Precompute derived values to keep widgets simple.
    final durationMinutes = record.effectiveDurationMinutes;
    final statusLabel = record.isOpen ? _statusOpen : _statusClosed;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Header row shows identity + status at a glance.
          Row(
            children: [
              Expanded(
                child: Text(
                  staffName,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusChip(label: statusLabel, isOpen: record.isOpen),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // WHY: Role label provides context for the attendance entry.
          if (staffRole != null && staffRole!.trim().isNotEmpty)
            Text(
              staffRole!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          // WHY: Show timestamps for audit clarity.
          Text(
            "$_labelClockIn: ${formatDateTimeLabel(record.clockInAt)}",
            style: textTheme.bodySmall,
          ),
          Text(
            "$_labelClockOut: ${formatDateTimeLabel(record.clockOutAt)}",
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          // WHY: Duration summarises session length for quick scanning.
          Text(
            "$_labelDuration: ${durationMinutes ?? 0}$_minutesSuffix",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isOpen;

  const _StatusChip({required this.label, required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // WHY: Use color coding to separate open vs closed sessions.
    final background = isOpen ? colorScheme.error : colorScheme.primary;
    final textColor = colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
