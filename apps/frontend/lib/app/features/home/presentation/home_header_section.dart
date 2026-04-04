library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomeHeaderSection extends StatelessWidget {
  final String locationLabel;
  final String helperLabel;
  final VoidCallback onActionTap;
  final int badgeCount;
  final IconData actionIcon;
  final String actionTooltip;

  const HomeHeaderSection({
    super.key,
    required this.locationLabel,
    required this.helperLabel,
    required this.onActionTap,
    required this.badgeCount,
    this.actionIcon = Icons.shopping_bag_outlined,
    this.actionTooltip = "Cart",
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: colorScheme.surface.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const AppIconBadge(icon: Icons.pin_drop_outlined, size: 18),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        helperLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimary.withValues(alpha: 0.76),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: colorScheme.surface.withValues(alpha: 0.2),
            ),
          ),
          child: IconButton(
            tooltip: actionTooltip,
            onPressed: onActionTap,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(actionIcon, color: colorScheme.onPrimary),
                if (badgeCount > 0)
                  Positioned(
                    right: -7,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        badgeCount > 99 ? "99+" : "$badgeCount",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onError,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
