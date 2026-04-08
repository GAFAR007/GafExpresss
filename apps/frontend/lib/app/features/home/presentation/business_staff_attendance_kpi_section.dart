/// lib/app/features/home/presentation/business_staff_attendance_kpi_section.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - KPI cards for staff attendance metrics.
///
/// WHY:
/// - Gives managers a quick snapshot of attendance health.
/// - Keeps KPI rendering separate from list/filter logic.
///
/// HOW:
/// - Computes KPI summary from filtered attendance records.
/// - Renders compact cards with labels + helper text.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/business_staff_attendance_constants.dart';
import 'package:frontend/app/features/home/presentation/staff_attendance_model.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _percentSuffix = "%";
const String _minutesSuffix = " mins";

class StaffAttendanceKpiSection extends StatelessWidget {
  final List<StaffAttendanceRecord> records;

  const StaffAttendanceKpiSection({
    super.key,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Compute KPIs from the currently filtered records.
    final summary = StaffAttendanceKpiSummary.fromRecords(records);
    // WHY: Display integers for readability on small cards.
    final onTimePercent =
        (summary.onTimeRate * 100).toStringAsFixed(0);
    final avgDuration = summary.avgDurationMinutes.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: Title anchors the KPI group for scanning.
        Text(
          staffAttendanceTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            // WHY: On-time rate summarizes completed vs open sessions.
            _KpiCard(
              label: staffAttendanceKpiOnTime,
              value: "$onTimePercent$_percentSuffix",
              helper: staffAttendanceKpiHelper,
            ),
            // WHY: Open sessions indicate staff currently clocked in.
            _KpiCard(
              label: staffAttendanceKpiLate,
              value: summary.openSessions.toString(),
              helper: staffAttendanceKpiHelper,
            ),
            // WHY: Avg duration helps spot unusually long sessions.
            _KpiCard(
              label: staffAttendanceKpiDelay,
              value: "$avgDuration$_minutesSuffix",
              helper: staffAttendanceKpiHelper,
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String helper;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 160,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Label clarifies what the KPI represents.
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          // WHY: Value is the primary metric emphasis.
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // WHY: Helper text explains the KPI meaning.
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
