/// lib/app/features/home/presentation/business_staff_directory_list_widgets.dart
/// --------------------------------------------------------------------------
/// WHAT:
/// - UI widgets for the staff directory list section.
///
/// WHY:
/// - Keeps the list section file small and readable.
/// - Encapsulates row + group rendering.
///
/// HOW:
/// - Renders group headers and staff rows with action buttons.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_list_helpers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/staff_role_helpers.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _logTag = "STAFF_DIRECTORY_LIST";
const String _logViewProfile = "view_profile";
const String _extraStaffIdKey = "staffProfileId";
const String _roleLabel = "Role";
const String _statusLabel = "Status";
const String _viewProfileLabel = "View profile";

class StaffDirectoryGroupSection extends StatelessWidget {
  final StaffDirectoryGroup group;

  const StaffDirectoryGroupSection({
    super.key,
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        // WHY: Group headers make estate scope visible at a glance.
        Text(
          group.label,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...group.staff.map(
          (profile) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: StaffDirectoryListRow(profile: profile),
          ),
        ),
      ],
    );
  }
}

class StaffDirectoryListRow extends StatelessWidget {
  final BusinessStaffProfileSummary profile;

  const StaffDirectoryListRow({
    super.key,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final displayName = buildStaffDisplayName(profile);
    final roleLabel = formatStaffRoleLabel(
      profile.staffRole,
      fallback: staffDirectoryUnknownStaffLabel,
    );
    final statusLabel = formatStaffRoleLabel(
      profile.status,
      fallback: staffDirectoryUnknownStaffLabel,
    );

    // WHY: Card styling keeps list rows readable across themes.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "$_roleLabel: $roleLabel",
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "$_statusLabel: $statusLabel",
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // WHY: Log navigation to keep staff detail access traceable.
              AppDebug.log(
                _logTag,
                _logViewProfile,
                extra: {_extraStaffIdKey: profile.id},
              );
              context.go(
                businessStaffDetailPath(profile.id),
              );
            },
            child: const Text(_viewProfileLabel),
          ),
        ],
      ),
    );
  }
}

class StaffDirectoryEmptyState extends StatelessWidget {
  final String message;
  final String hint;

  const StaffDirectoryEmptyState({
    super.key,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class StaffDirectoryErrorState extends StatelessWidget {
  final String message;
  final String hint;
  final String retryLabel;
  final VoidCallback onRetry;

  const StaffDirectoryErrorState({
    super.key,
    required this.message,
    required this.hint,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: onRetry,
          child: Text(retryLabel),
        ),
      ],
    );
  }
}
