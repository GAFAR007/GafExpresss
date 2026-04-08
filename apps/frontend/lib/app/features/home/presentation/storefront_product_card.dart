/// lib/app/features/home/presentation/storefront_product_card.dart
/// --------------------------------------------------------------
/// WHAT:
/// - Displays a storefront product card with image, badges, pricing, and a CTA.
///
/// WHY:
/// - Gives home/search/product sections one responsive card implementation that
///   avoids layout overflow on narrow grids.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/storefront_color_swatch_row.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StorefrontProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onPrimaryAction;
  final bool isFavorite;
  final String? primaryActionLabel;
  final bool featured;

  const StorefrontProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onFavoriteToggle,
    this.onPrimaryAction,
    this.isFavorite = false,
    this.primaryActionLabel,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final priceText = formatNgnFromCents(product.priceCents);
    final oldPriceText = product.hasDiscount
        ? formatNgnFromCents(product.oldPriceCents!)
        : null;
    final badgeLabel = product.badges.isNotEmpty
        ? product.badges.first
        : product.preorderEnabled
        ? "Pre-order"
        : _isRecentlyAdded(product)
        ? "New"
        : product.stock > 0 && product.stock <= 5
        ? "Limited"
        : null;
    final accent = _accentFor(product, scheme);
    final hasRatingData = product.rating > 0 || product.reviewCount > 0;
    final availabilityLabel = product.preorderEnabled
        ? "Pre-order"
        : product.stock <= 0
        ? "Sold out"
        : product.stock <= 5
        ? "Only ${product.stock} left"
        : "In stock";
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.08),
                blurRadius: featured ? 28 : 18,
                offset: Offset(0, featured ? 14 : 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: featured ? 6 : 5,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        product.primaryImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  accent.withValues(alpha: 0.92),
                                  scheme.primaryContainer,
                                ],
                              ),
                            ),
                            child: Icon(
                              _iconFor(product),
                              size: 42,
                              color: scheme.onPrimaryContainer,
                            ),
                          );
                        },
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.24),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.md,
                        top: AppSpacing.md,
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (badgeLabel != null)
                              _Pill(
                                label: badgeLabel,
                                background: accent,
                                foreground: Colors.white,
                              ),
                            if (product.hasDiscount &&
                                product.discountPercent != null)
                              _Pill(
                                label: "-${product.discountPercent}%",
                                background: scheme.surface.withValues(
                                  alpha: 0.9,
                                ),
                                foreground: scheme.onSurface,
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: AppSpacing.md,
                        top: AppSpacing.md,
                        child: Material(
                          color: scheme.surface.withValues(alpha: 0.88),
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: onFavoriteToggle,
                            tooltip: isFavorite
                                ? "Remove favorite"
                                : "Favorite",
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: isFavorite
                                  ? scheme.error
                                  : scheme.onSurface,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: Row(
                          children: [
                            Expanded(
                              child: _Pill(
                                label: product.primaryCategoryLabel,
                                background: scheme.surface.withValues(
                                  alpha: 0.88,
                                ),
                                foreground: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _Pill(
                              label: availabilityLabel,
                              background:
                                  product.preorderEnabled || product.stock > 0
                                  ? accent.withValues(alpha: 0.94)
                                  : scheme.surfaceContainerHighest,
                              foreground:
                                  product.preorderEnabled || product.stock > 0
                                  ? Colors.white
                                  : scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: featured ? 5 : 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useCondensedBody =
                        !featured || constraints.maxWidth < 320;
                    final showBrand =
                        !useCondensedBody && product.brand.trim().isNotEmpty;
                    final showUnitLabel =
                        !useCondensedBody &&
                        (product.unitLabel ?? "").trim().isNotEmpty;
                    final descriptionLines = constraints.maxWidth < 320 ? 2 : 3;
                    final priceStyle =
                        (useCondensedBody
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleLarge)
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w900,
                            );

                    return Padding(
                      padding: EdgeInsets.all(
                        useCondensedBody ? AppSpacing.md : AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showBrand) ...[
                            Text(
                              product.brand,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (useCondensedBody
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                          ),
                          if (!useCondensedBody ||
                              constraints.maxWidth >= 280) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              product.shortDescription,
                              maxLines: descriptionLines,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (!useCondensedBody || hasRatingData) ...[
                            Row(
                              children: [
                                if (hasRatingData) ...[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: const Color(0xFFF3B23A),
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    product.rating.toStringAsFixed(1),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    "(${product.reviewCount})",
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ] else ...[
                                  Icon(
                                    _iconFor(product),
                                    size: 16,
                                    color: accent,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      product.subcategory.trim().isNotEmpty
                                          ? product.subcategory
                                          : product.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                if (showUnitLabel)
                                  Text(
                                    product.unitLabel!,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                              ],
                            ),
                          ],
                          if (!useCondensedBody &&
                              product.colorVariants.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            StorefrontColorSwatchRow(
                              colors: product.colorVariants,
                            ),
                          ] else if (!useCondensedBody &&
                              product.sizeVariants.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              product.sizeVariants.take(4).join("  •  "),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      priceText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: priceStyle,
                                    ),
                                    if (oldPriceText != null)
                                      Text(
                                        oldPriceText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              SizedBox.square(
                                dimension: useCondensedBody ? 40 : 48,
                                child: FilledButton.tonal(
                                  onPressed: onPrimaryAction ?? onTap,
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: useCondensedBody
                                      ? const Icon(Icons.add_rounded, size: 22)
                                      : const Icon(
                                          Icons.add_shopping_cart_rounded,
                                          size: 22,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentFor(Product product, ColorScheme scheme) {
    final normalized = "${product.category} ${product.subcategory}"
        .toLowerCase();
    if (normalized.contains("farm") ||
        normalized.contains("agro") ||
        normalized.contains("vegetable") ||
        normalized.contains("grain")) {
      return scheme.secondary;
    }
    if (normalized.contains("home") || normalized.contains("kitchen")) {
      return scheme.tertiary;
    }
    return scheme.primary;
  }

  IconData _iconFor(Product product) {
    final categoryText = "${product.category} ${product.subcategory}"
        .toLowerCase();
    if (categoryText.contains("farm") || categoryText.contains("agro")) {
      return Icons.agriculture_rounded;
    }
    if (categoryText.contains("foot") ||
        categoryText.contains("shoe") ||
        categoryText.contains("sneaker")) {
      return Icons.hiking_rounded;
    }
    if (categoryText.contains("kitchen")) {
      return Icons.kitchen_rounded;
    }
    if (categoryText.contains("grain") || categoryText.contains("cereal")) {
      return Icons.rice_bowl_rounded;
    }
    final subcategory = product.subcategory.toLowerCase();
    if (subcategory.contains("shirt") || subcategory.contains("top")) {
      return Icons.checkroom_rounded;
    }
    if (subcategory.contains("hoodie")) {
      return Icons.dry_cleaning_rounded;
    }
    if (subcategory.contains("trouser")) {
      return Icons.accessibility_new_rounded;
    }
    if (subcategory.contains("sneaker") || subcategory.contains("shoe")) {
      return Icons.hiking_rounded;
    }
    if (subcategory.contains("fruit")) {
      return Icons.apple_rounded;
    }
    if (subcategory.contains("vegetable")) {
      return Icons.eco_rounded;
    }
    return Icons.inventory_2_rounded;
  }

  bool _isRecentlyAdded(Product product) {
    final createdAt = product.createdAt;
    if (createdAt == null) {
      return false;
    }
    final age = DateTime.now().difference(createdAt).inDays;
    return age <= 14;
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
