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
import 'package:frontend/app/theme/app_radius.dart';

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

String formatProductionStatusLabel(String rawLabel) {
  final trimmed = rawLabel.trim();
  if (trimmed.isEmpty) {
    return "Unknown";
  }

  final words = trimmed.split("_").where((word) => word.trim().isNotEmpty).map((
    word,
  ) {
    final lower = word.toLowerCase();
    return "${lower[0].toUpperCase()}${lower.substring(1)}";
  }).toList();
  return words.join(" ");
}

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
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class ProductionStatusPill extends StatelessWidget {
  final String label;

  const ProductionStatusPill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalized = label.trim().toLowerCase();
    final backgroundColor = switch (normalized) {
      "active" => colorScheme.primaryContainer,
      "paused" => colorScheme.tertiaryContainer,
      "completed" => colorScheme.secondaryContainer,
      "archived" => colorScheme.surfaceContainerHighest,
      "done" => colorScheme.secondaryContainer,
      "in_progress" => colorScheme.primaryContainer,
      "rejected" => colorScheme.errorContainer,
      "pending_approval" => colorScheme.tertiaryContainer,
      _ => colorScheme.secondaryContainer,
    };
    final foregroundColor = switch (normalized) {
      "active" => colorScheme.onPrimaryContainer,
      "paused" => colorScheme.onTertiaryContainer,
      "completed" => colorScheme.onSecondaryContainer,
      "archived" => colorScheme.onSurfaceVariant,
      "done" => colorScheme.onSecondaryContainer,
      "in_progress" => colorScheme.onPrimaryContainer,
      "rejected" => colorScheme.onErrorContainer,
      "pending_approval" => colorScheme.onTertiaryContainer,
      _ => colorScheme.onSecondaryContainer,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _statusPillPaddingHorizontal,
        vertical: _statusPillPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(_statusPillRadius),
      ),
      child: Text(
        formatProductionStatusLabel(label),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ProductionEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ProductionEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 640;
    final hasAction =
        actionLabel?.trim().isNotEmpty == true && onAction != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_emptyStatePadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isCompact ? 380 : 460),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 22 : 28,
              vertical: isCompact ? 24 : 32,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.eco_outlined,
                    color: colorScheme.primary,
                    size: _emptyIconSize,
                  ),
                ),
                const SizedBox(height: _emptyTitleSpacing),
                Text(
                  title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: _emptyMessageSpacing),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (hasAction) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.add),
                      label: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
