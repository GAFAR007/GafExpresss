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
import 'package:frontend/app/theme/app_theme.dart';

// WHY: Production dashboards already sit inside framed panels, so KPI cards
// need a quieter footprint instead of competing with the surrounding surface.
const double _kpiCardPaddingHorizontal = 10;
const double _kpiCardPaddingVertical = 9;
const double _kpiCardRadius = 12;
const double _kpiCardMinWidth = 104;
const double _kpiCardMaxWidth = 176;
const double _kpiIconBoxSize = 24;
const double _kpiIconSize = 14;
const double _kpiValueSpacing = 5;
const double _statusPillRadius = 999;
const double _statusPillPaddingHorizontal = 10;
const double _statusPillPaddingVertical = 4;
const double _emptyStatePadding = 24;
const double _emptyIconSize = 42;
const double _emptyTitleSpacing = 12;
const double _emptyMessageSpacing = 6;
const double _loadingStatePadding = 24;
const double _loadingStateTopPadding = 180;
const double _loadingStateIndicatorSize = 28;
const double _refreshIndicatorTop = 12;
const double _refreshIndicatorRight = 16;
const double _refreshIndicatorWidth = 118;
const double _refreshIndicatorHeight = 32;
const Duration _refreshIndicatorFadeDuration = Duration(milliseconds: 160);
const Duration _refreshIndicatorCycleDuration = Duration(milliseconds: 1000);

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
  final String? helper;
  final IconData? icon;
  final AppStatusTone tone;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? labelColor;
  final Color? valueColor;
  final Color? helperColor;

  const ProductionKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.helper,
    this.icon,
    this.tone = AppStatusTone.neutral,
    this.backgroundColor,
    this.borderColor,
    this.labelColor,
    this.valueColor,
    this.helperColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: tone,
    );
    final usesTone = tone != AppStatusTone.neutral;
    final isDark = theme.brightness == Brightness.dark;
    final resolvedBackground =
        backgroundColor ??
        (isDark ? colorScheme.surfaceContainerLow : colorScheme.surface);
    final resolvedBorder =
        borderColor ??
        (usesTone
            ? badgeColors.foreground.withValues(alpha: isDark ? 0.26 : 0.18)
            : colorScheme.outlineVariant);
    final resolvedIconBackground = usesTone
        ? badgeColors.background.withValues(alpha: isDark ? 0.78 : 0.52)
        : colorScheme.surfaceContainerHighest;
    final resolvedIconColor = usesTone
        ? badgeColors.foreground.withValues(alpha: isDark ? 0.96 : 0.88)
        : colorScheme.onSurfaceVariant;
    final resolvedLabelColor = labelColor ?? colorScheme.onSurfaceVariant;
    final resolvedValueColor =
        valueColor ??
        (usesTone
            ? badgeColors.foreground.withValues(alpha: isDark ? 0.96 : 0.88)
            : colorScheme.onSurface);
    final resolvedHelperColor = helperColor ?? colorScheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(
        minWidth: _kpiCardMinWidth,
        maxWidth: _kpiCardMaxWidth,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: _kpiCardPaddingHorizontal,
        vertical: _kpiCardPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(_kpiCardRadius),
        border: Border.all(color: resolvedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  width: _kpiIconBoxSize,
                  height: _kpiIconBoxSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: resolvedIconBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: _kpiIconSize,
                    color: resolvedIconColor,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: resolvedLabelColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: _kpiValueSpacing),
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(
              color: resolvedValueColor,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (helper != null && helper!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              helper!,
              style: textTheme.bodySmall?.copyWith(color: resolvedHelperColor),
            ),
          ],
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
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: Theme.of(context),
      tone: productionStatusTone(label),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _statusPillPaddingHorizontal,
        vertical: _statusPillPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: badgeColors.background,
        borderRadius: BorderRadius.circular(_statusPillRadius),
        border: Border.all(
          color: badgeColors.foreground.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        formatProductionStatusLabel(label),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: badgeColors.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

AppStatusTone productionStatusTone(String rawLabel) {
  switch (rawLabel.trim().toLowerCase()) {
    case "completed":
    case "done":
    case "approved":
      return AppStatusTone.success;
    case "active":
    case "in_progress":
    case "in_production":
    case "on_track":
      return AppStatusTone.warning;
    case "pending":
    case "pending_approval":
    case "needs_review":
    case "paused":
      return AppStatusTone.warning;
    case "blocked":
    case "rejected":
    case "delayed":
    case "overdue":
    case "archived":
      return AppStatusTone.danger;
    default:
      return AppStatusTone.neutral;
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

class ProductionLoadingState extends StatelessWidget {
  final String title;
  final String message;

  const ProductionLoadingState({
    super.key,
    this.title = "Loading production plan",
    this.message = "Restoring the latest production data after refresh.",
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        _loadingStatePadding,
        _loadingStateTopPadding,
        _loadingStatePadding,
        _loadingStatePadding,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _loadingStateIndicatorSize,
                  height: _loadingStateIndicatorSize,
                  child: const CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(height: _emptyTitleSpacing),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
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
        ),
      ],
    );
  }
}

class ProductionRefreshOverlay extends StatelessWidget {
  final bool isRefreshing;
  final Widget child;

  const ProductionRefreshOverlay({
    super.key,
    required this.isRefreshing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: _refreshIndicatorTop,
          right: _refreshIndicatorRight,
          child: ProductionSubtleRefreshIndicator(visible: isRefreshing),
        ),
      ],
    );
  }
}

class ProductionSubtleRefreshIndicator extends StatefulWidget {
  final bool visible;
  final String label;

  const ProductionSubtleRefreshIndicator({
    super.key,
    required this.visible,
    this.label = "Updating",
  });

  @override
  State<ProductionSubtleRefreshIndicator> createState() =>
      _ProductionSubtleRefreshIndicatorState();
}

class _ProductionSubtleRefreshIndicatorState
    extends State<ProductionSubtleRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _refreshIndicatorCycleDuration,
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ProductionSubtleRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    // WHY: The dots only animate while a refresh is actually visible.
    if (widget.visible) {
      _controller.repeat();
      return;
    }
    _controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: _refreshIndicatorFadeDuration,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: Semantics(
            liveRegion: true,
            label: "${widget.label} plan data",
            child: Container(
              width: _refreshIndicatorWidth,
              height: _refreshIndicatorHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.86 : 0.92,
                ),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final dotCount = (1 + (_controller.value * 5).floor())
                      .clamp(1, 5)
                      .toInt();
                  final dots = List.filled(dotCount, ".").join(" ");
                  return Text(
                    "${widget.label} $dots",
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
