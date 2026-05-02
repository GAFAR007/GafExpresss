/// lib/app/features/home/presentation/production/production_calendar_visuals.dart
/// -----------------------------------------------------------------------------
/// WHAT:
/// - Shared visual helpers for production calendar widgets.
///
/// WHY:
/// - Keeps calendar surfaces consistent across month/day/year views.
/// - Replaces repetitive text labels with compact color + icon driven affordances.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_theme.dart';

class ProductionCalendarPalette {
  final Color accent;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color badgeBackground;
  final Color badgeForeground;
  final Color shadow;

  const ProductionCalendarPalette({
    required this.accent,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.shadow,
  });
}

class ProductionCalendarVisuals {
  static ProductionCalendarPalette palette({
    required ThemeData theme,
    required int taskCount,
    int completedCount = 0,
    bool warning = false,
    bool selected = false,
    bool today = false,
  }) {
    final accent = _accentForDay(
      theme: theme,
      taskCount: taskCount,
      completedCount: completedCount,
      warning: warning,
      selected: selected,
      today: today,
    );
    final isDark = theme.brightness == Brightness.dark;
    final primaryTint = theme.colorScheme.primary;
    final baseSurface = isDark
        ? theme.colorScheme.surfaceContainerLow
        : Color.alphaBlend(
            const Color(0xFF0F172A).withValues(alpha: 0.02),
            theme.colorScheme.surface,
          );
    final elevatedSurface = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : Color.alphaBlend(
            const Color(0xFF0F172A).withValues(alpha: 0.035),
            theme.colorScheme.surfaceContainerLow,
          );
    final surface = Color.alphaBlend(
      primaryTint.withValues(alpha: isDark ? 0.08 : 0.07),
      baseSurface,
    );
    final surfaceAlt = Color.alphaBlend(
      primaryTint.withValues(alpha: isDark ? 0.14 : 0.12),
      elevatedSurface,
    );
    final badgeBackground = _emphasisFill(
      theme: theme,
      accent: primaryTint,
      emphasized: selected || today || taskCount > 0 || warning,
    );
    final badgeForeground = _onFillColor(badgeBackground);
    final border = selected || today
        ? primaryTint.withValues(alpha: isDark ? 0.9 : 0.72)
        : taskCount > 0 || warning
        ? primaryTint.withValues(alpha: isDark ? 0.44 : 0.3)
        : theme.colorScheme.outlineVariant;
    final shadow = const Color(
      0xFF0B1220,
    ).withValues(alpha: isDark ? 0.32 : 0.08);

    return ProductionCalendarPalette(
      accent: accent,
      surface: surface,
      surfaceAlt: surfaceAlt,
      border: border,
      badgeBackground: badgeBackground,
      badgeForeground: badgeForeground,
      shadow: shadow,
    );
  }

  static BoxDecoration shellDecoration({
    required ThemeData theme,
    required ProductionCalendarPalette palette,
    double radius = 24,
    bool emphasized = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: emphasized ? 0.08 : 0.05),
            theme.colorScheme.surfaceContainerLow,
          )
        : Color.alphaBlend(
            const Color(
              0xFF0F172A,
            ).withValues(alpha: emphasized ? 0.03 : 0.015),
            theme.colorScheme.surface,
          );
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: palette.border, width: emphasized ? 1.8 : 1.3),
      boxShadow: [
        BoxShadow(
          color: palette.shadow,
          blurRadius: emphasized ? 24 : 16,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration tileDecoration({
    required ThemeData theme,
    required ProductionCalendarPalette palette,
    double radius = 18,
    bool emphasized = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final background = emphasized
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: isDark ? 0.14 : 0.08),
            palette.surfaceAlt,
          )
        : palette.surface;
    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: palette.border, width: emphasized ? 2 : 1.4),
      boxShadow: [
        BoxShadow(
          color: palette.shadow,
          blurRadius: emphasized ? 18 : 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static Color mutedText(ThemeData theme, {Color? accent}) {
    final seed = accent ?? theme.colorScheme.onSurfaceVariant;
    return Color.alphaBlend(
      seed.withValues(alpha: 0.12),
      theme.colorScheme.onSurfaceVariant,
    );
  }

  static IconData statusIcon(String statusRaw) {
    switch (statusRaw.trim().toLowerCase()) {
      case "done":
      case "approved":
        return Icons.check_circle_rounded;
      case "in_progress":
        return Icons.timelapse_rounded;
      case "pending":
      case "pending_approval":
        return Icons.schedule_rounded;
      case "rejected":
        return Icons.cancel_rounded;
      default:
        return Icons.fiber_manual_record_rounded;
    }
  }

  static String compactStatusLabel(String statusRaw) {
    switch (statusRaw.trim().toLowerCase()) {
      case "in_progress":
        return "Live";
      case "pending_approval":
        return "Review";
      case "done":
        return "Done";
      case "pending":
        return "Queued";
      default:
        final trimmed = statusRaw.trim();
        return trimmed.isEmpty ? "Open" : trimmed.replaceAll("_", " ");
    }
  }

  static AppStatusTone statusTone(String statusRaw) {
    switch (statusRaw.trim().toLowerCase()) {
      case "done":
      case "approved":
        return AppStatusTone.success;
      case "in_progress":
        return AppStatusTone.info;
      case "pending":
      case "pending_approval":
        return AppStatusTone.warning;
      case "rejected":
        return AppStatusTone.danger;
      default:
        return AppStatusTone.neutral;
    }
  }

  static Color _accentForDay({
    required ThemeData theme,
    required int taskCount,
    required int completedCount,
    required bool warning,
    required bool selected,
    required bool today,
  }) {
    if (selected) {
      return theme.colorScheme.primary;
    }
    if (warning) {
      return AppColors.warning;
    }
    if (taskCount > 0 && completedCount >= taskCount) {
      return AppColors.success;
    }
    if (taskCount > 0) {
      return theme.colorScheme.primary;
    }
    if (today) {
      return theme.colorScheme.primary;
    }
    return const Color(0xFF334155);
  }

  static Color _emphasisFill({
    required ThemeData theme,
    required Color accent,
    required bool emphasized,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    if (!emphasized) {
      return isDark
          ? theme.colorScheme.surfaceContainerHigh
          : const Color(0xFFDCE8FA);
    }
    final darkBase = isDark
        ? theme.colorScheme.primaryContainer
        : const Color(0xFF1A3F91);
    return Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.18 : 0.22),
      darkBase,
    );
  }

  static Color _onFillColor(Color fill) {
    return fill.computeLuminance() > 0.42
        ? const Color(0xFF111827)
        : const Color(0xFFF8FAFC);
  }
}

class ProductionCalendarMetricPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color accent;
  final String? tooltip;
  final bool compact;
  final bool filled;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? iconColor;
  final Color? borderColor;

  const ProductionCalendarMetricPill({
    super.key,
    required this.icon,
    required this.value,
    required this.accent,
    this.tooltip,
    this.compact = false,
    this.filled = true,
    this.padding,
    this.backgroundColor,
    this.foregroundColor,
    this.iconColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultBackground = theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.18),
            theme.colorScheme.surfaceContainerHigh,
          )
        : const Color(0xFF1A3F91);
    final background = filled
        ? (backgroundColor ?? defaultBackground)
        : backgroundColor;
    final foreground =
        foregroundColor ??
        ((background ?? defaultBackground).computeLuminance() > 0.42
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC));
    final resolvedIconColor =
        iconColor ??
        (filled && background == null
            ? accent
            : theme.brightness == Brightness.dark
            ? accent.withValues(alpha: 0.96)
            : accent);
    final resolvedBorderColor =
        borderColor ?? (filled ? accent.withValues(alpha: 0.28) : null);
    final child = Container(
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 4 : 6,
          ),
      decoration: background != null || resolvedBorderColor != null
          ? BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: resolvedBorderColor != null
                  ? Border.all(color: resolvedBorderColor, width: 1.2)
                  : null,
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: resolvedIconColor),
          SizedBox(width: compact ? 4 : 6),
          Text(
            value,
            style:
                (compact
                        ? theme.textTheme.labelMedium
                        : theme.textTheme.titleSmall)
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );

    if (tooltip == null || tooltip!.trim().isEmpty) {
      return child;
    }
    return Tooltip(message: tooltip, child: child);
  }
}

class ProductionCalendarActivityDots extends StatelessWidget {
  final int count;
  final Color accent;
  final bool compact;

  const ProductionCalendarActivityDots({
    super.key,
    required this.count,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleCount = math.min(count, compact ? 3 : 4);
    final dotSize = compact ? 6.0 : 7.0;
    final overflow = count - visibleCount;
    final textColor = accent.computeLuminance() > 0.5
        ? const Color(0xFF0F172A)
        : accent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < visibleCount; index += 1)
          Container(
            width: dotSize,
            height: dotSize,
            margin: EdgeInsets.only(right: index == visibleCount - 1 ? 0 : 4),
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: 0.34 + (index / math.max(1, visibleCount)) * 0.42,
              ),
              shape: BoxShape.circle,
            ),
          ),
        if (overflow > 0) ...[
          const SizedBox(width: 6),
          Text(
            "+$overflow",
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor.withValues(alpha: 0.96),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
