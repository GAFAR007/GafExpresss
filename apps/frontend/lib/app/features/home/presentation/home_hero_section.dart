library;

import 'package:flutter/material.dart';

import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomeHeroMetric {
  final String label;
  final String value;
  final IconData icon;

  const HomeHeroMetric({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class HomeHeroSection extends StatelessWidget {
  final String topLabel;
  final String catalogLabel;
  final String headline;
  final String subtitle;
  final String promoEyebrow;
  final String promoTitle;
  final String promoBody;
  final String primaryLabel;
  final String secondaryLabel;
  final String promoLabel;
  final int cartBadgeCount;
  final List<HomeHeroMetric> metrics;
  final VoidCallback onCartTap;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;
  final VoidCallback onPromoTap;

  const HomeHeroSection({
    super.key,
    this.topLabel = "Home",
    required this.catalogLabel,
    required this.headline,
    required this.subtitle,
    required this.promoEyebrow,
    required this.promoTitle,
    required this.promoBody,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.promoLabel,
    required this.cartBadgeCount,
    required this.metrics,
    required this.onCartTap,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
    required this.onPromoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _TopIconButton(
                icon: Icons.grid_view_rounded,
                onTap: onSecondaryTap,
              ),
              const Spacer(),
              Text(
                topLabel,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              _CartButton(badgeCount: cartBadgeCount, onTap: onCartTap),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: InkWell(
              onTap: onPromoTap,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      scheme.primary,
                      scheme.tertiary.withValues(alpha: 0.96),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                promoEyebrow,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              promoBody.isNotEmpty ? promoBody : subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onPrimary.withValues(alpha: 0.88),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              primaryLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w900,
                                decoration: TextDecoration.underline,
                                decorationColor: scheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _heroIconFor(catalogLabel),
                          color: scheme.onPrimary,
                          size: 54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "${metrics.first.value} products · $catalogLabel",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _heroIconFor(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains("foot") ||
        normalized.contains("shoe") ||
        normalized.contains("sneaker")) {
      return Icons.hiking_rounded;
    }
    if (normalized.contains("farm") ||
        normalized.contains("agro") ||
        normalized.contains("grain") ||
        normalized.contains("vegetable")) {
      return Icons.agriculture_rounded;
    }
    if (normalized.contains("home") || normalized.contains("kitchen")) {
      return Icons.kitchen_rounded;
    }
    return Icons.shopping_bag_rounded;
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, size: 20, color: scheme.primary),
      ),
    );
  }
}

class _CartButton extends StatelessWidget {
  final int badgeCount;
  final VoidCallback onTap;

  const _CartButton({required this.badgeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 20, color: scheme.primary),
            if (badgeCount > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    badgeCount > 99 ? "99+" : "$badgeCount",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onError,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
