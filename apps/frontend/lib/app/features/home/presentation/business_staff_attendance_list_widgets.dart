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
const String _statusPendingProof = "PENDING PROOF";
const String _statusCompleted = "COMPLETED";
const String _labelClockIn = "Clock in";
const String _labelClockOut = "Clock out";
const String _labelDuration = "Duration";
const String _labelProof = "Proof";
const String _minutesSuffix = " mins";
const String _proofMissingLabel = "Missing proof";
const String _proofCompleteLabel = "Proof complete";
const String _proofNotRequiredLabel = "Proof not required";
const String _uploadProofLabel = "Upload proof";
const String _replaceProofLabel = "Replace proof";

class StaffAttendanceListItem extends StatelessWidget {
  final StaffAttendanceRecord record;
  final String staffName;
  final String? staffRole;
  final VoidCallback? onUploadProof;

  const StaffAttendanceListItem({
    super.key,
    required this.record,
    required this.staffName,
    required this.staffRole,
    this.onUploadProof,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    // WHY: Precompute derived values to keep widgets simple.
    final durationMinutes = record.effectiveDurationMinutes;
    final statusLabel = record.isOpen
        ? _statusOpen
        : record.isPendingProof
        ? _statusPendingProof
        : _statusCompleted;
    final proofLabel = record.needsProof
        ? _proofMissingLabel
        : record.effectiveProofs.isNotEmpty
        ? _proofCompleteLabel
        : _proofNotRequiredLabel;
    final statusBackground = record.isOpen
        ? colorScheme.errorContainer
        : record.isPendingProof
        ? colorScheme.tertiaryContainer
        : colorScheme.primaryContainer;
    final statusForeground = record.isOpen
        ? colorScheme.onErrorContainer
        : record.isPendingProof
        ? colorScheme.onTertiaryContainer
        : colorScheme.onPrimaryContainer;
    final proofBackground = record.needsProof
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final proofForeground = record.needsProof
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;
    final proofActionLabel = record.effectiveProofs.isEmpty
        ? _uploadProofLabel
        : _replaceProofLabel;
    final canUploadProof = !record.isOpen && onUploadProof != null;

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
              _StatusChip(
                label: statusLabel,
                background: statusBackground,
                foreground: statusForeground,
              ),
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
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusChip(
                label: proofLabel,
                background: proofBackground,
                foreground: proofForeground,
              ),
              Text(
                "$_labelProof: ${record.effectiveProofs.length}/${record.effectiveRequiredProofs}",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (canUploadProof)
                TextButton(
                  onPressed: onUploadProof,
                  child: Text(proofActionLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _StatusChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
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
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
