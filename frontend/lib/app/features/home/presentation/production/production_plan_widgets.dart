/// lib/app/features/home/presentation/production/production_plan_widgets.dart
/// -----------------------------------------------------------------------
/// WHAT:
/// - Reusable widgets for production plan screens (status, KPI, sections).
///
/// WHY:
/// - Keeps screens under size limits by extracting repeated UI.
/// - Ensures consistent styling across production screens.
///
/// HOW:
/// - Small stateless widgets with theme-driven styling.
/// - Accepts labels/values as parameters for flexibility.
library;

import 'package:flutter/material.dart';

// WHY: Consistent spacing keeps card layouts readable.
const double _kpiCardPadding = 12;
const double _kpiCardRadius = 14;
const double _kpiValueSpacing = 6;
const double _statusPillRadius = 999;
const double _statusPillPaddingHorizontal = 10;
const double _statusPillPaddingVertical = 4;
const double _emptyStatePadding = 24;
const double _emptyIconSize = 42;
const double _emptyTitleSpacing = 12;
const double _emptyMessageSpacing = 6;

class ProductionSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const ProductionSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class ProductionKpiCard extends StatelessWidget {
  final String label;
  final String value;

  const ProductionKpiCard({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(_kpiCardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kpiCardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Label uses subdued color to keep focus on the KPI value.
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: _kpiValueSpacing),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ProductionStatusPill extends StatelessWidget {
  final String label;

  const ProductionStatusPill({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _statusPillPaddingHorizontal,
        vertical: _statusPillPaddingVertical,
      ),
      decoration: BoxDecoration(
        // WHY: Pill background stays consistent across light/dark themes.
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(_statusPillRadius),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class ProductionEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const ProductionEmptyState({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_emptyStatePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_outlined, color: colorScheme.primary, size: _emptyIconSize),
            const SizedBox(height: _emptyTitleSpacing),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: _emptyMessageSpacing),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
