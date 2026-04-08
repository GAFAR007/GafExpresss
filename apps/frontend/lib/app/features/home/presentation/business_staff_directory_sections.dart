/// lib/app/features/home/presentation/business_staff_directory_sections.dart
/// ---------------------------------------------------------------------
/// WHAT:
/// - Reusable section cards for the staff directory screen.
///
/// WHY:
/// - Keeps the main screen file small and readable.
/// - Provides a consistent module layout for KPI, filter, and list sections.
///
/// HOW:
/// - Renders a titled card with helper text and a placeholder or custom child.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const double _placeholderHeight = 64;

class StaffDirectorySectionCard extends StatelessWidget {
  final String title;
  final String helper;
  final String placeholderText;
  final Widget? child;

  const StaffDirectorySectionCard({
    super.key,
    required this.title,
    required this.helper,
    required this.placeholderText,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Use theme tokens to keep the card consistent across modes.
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final sectionBody = child ??
        Container(
          height: _placeholderHeight,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Center(
            // WHY: Placeholder communicates pending content without blank space.
            child: Text(
              placeholderText,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Title anchors the module for quick scanning.
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // WHY: Helper text sets expectation before data is wired.
          Text(
            helper,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          sectionBody,
        ],
      ),
    );
  }
}
