/// lib/app/features/home/presentation/business_staff_directory_kpi_section.dart
/// -----------------------------------------------------------------------
/// WHAT:
/// - KPI section for the staff directory (placeholder until backend KPIs).
///
/// WHY:
/// - Reserves layout space for upcoming staff analytics.
/// - Shows clear loading/error/empty states in the KPI module.
///
/// HOW:
/// - Renders a section card with state-driven child content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/features/home/presentation/business_staff_directory_sections.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/theme/app_spacing.dart';

const String _kpiTitle = "Staff overview";
const String _kpiHelper = "KPIs coming soon.";
const String _kpiComingSoon = "KPIs are not available yet.";
const String _kpiErrorTitle = "Unable to load staff KPIs";
const String _kpiErrorHint = "If this persists, contact support.";
const String _retryLabel = "Try again";

class StaffDirectoryKpiSection extends StatelessWidget {
  final AsyncValue<List<BusinessStaffProfileSummary>> staffAsync;
  final VoidCallback onRetry;

  const StaffDirectoryKpiSection({
    super.key,
    required this.staffAsync,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // WHY: Show a placeholder until backend summary endpoints are available.
    return StaffDirectorySectionCard(
      title: _kpiTitle,
      helper: _kpiHelper,
      placeholderText: _kpiComingSoon,
      child: staffAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _kpiErrorTitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _kpiErrorHint,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: onRetry,
              child: const Text(_retryLabel),
            ),
          ],
        ),
        data: (_) => Text(
          _kpiComingSoon,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
