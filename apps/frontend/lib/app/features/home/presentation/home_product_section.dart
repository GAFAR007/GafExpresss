/// lib/app/features/home/presentation/home_product_section.dart
/// -----------------------------------------------------------
/// WHAT:
/// - Renders reusable product sections on the home screen.
///
/// WHY:
/// - Keeps featured, category, and discovery rows visually consistent while
///   reserving enough card height for responsive product tiles.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/storefront_horizontal_product_list.dart';
import 'package:frontend/app/features/home/presentation/storefront_product_card.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomeProductSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product>? onPrimaryAction;
  final ValueChanged<Product>? onFavoriteToggle;
  final Set<String> favoriteIds;
  final String actionLabel;
  final bool featuredCards;
  final int maxItems;
  final VoidCallback? onSeeAllTap;

  const HomeProductSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.products,
    required this.onProductTap,
    this.onPrimaryAction,
    this.onFavoriteToggle,
    this.favoriteIds = const {},
    this.actionLabel = "",
    this.featuredCards = false,
    this.maxItems = 8,
    this.onSeeAllTap,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleProducts = products.take(maxItems).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        // WHY: Product cards include fixed-size image, title, price, and an
        // action button. These heights leave enough room to avoid overflow on
        // narrow mobile cards and featured desktop cards.
        final cardHeight = featuredCards
            ? (isCompact ? 420.0 : 520.0)
            : (isCompact ? 344.0 : 380.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeader(
              title: title,
              subtitle: isCompact ? null : subtitle,
              actionLabel: onSeeAllTap == null ? "" : "View All",
              onActionTap: onSeeAllTap,
            ),
            const SizedBox(height: AppSpacing.md),
            if (featuredCards && isCompact)
              StorefrontHorizontalProductList(
                products: visibleProducts,
                favoriteIds: favoriteIds,
                actionLabel: actionLabel.isEmpty ? null : actionLabel,
                featuredCards: featuredCards,
                onProductTap: onProductTap,
                onPrimaryAction: onPrimaryAction,
                onFavoriteToggle: onFavoriteToggle,
                cardWidth: 252,
              )
            else
              _buildResponsiveGrid(
                constraints: constraints,
                products: visibleProducts,
                cardHeight: cardHeight,
              ),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveGrid({
    required BoxConstraints constraints,
    required List<Product> products,
    required double cardHeight,
  }) {
    final columns = constraints.maxWidth < 760
        ? 2
        : AppLayout.columnsForWidth(
            constraints.maxWidth,
            compact: 2,
            medium: 3,
            large: 4,
            xlarge: 4,
          );
    final spacing = constraints.maxWidth < 760 ? AppSpacing.md : AppSpacing.lg;
    final width = (constraints.maxWidth - (spacing * (columns - 1))) / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final product in products)
          SizedBox(
            width: width,
            height: cardHeight,
            child: StorefrontProductCard(
              product: product,
              featured: featuredCards,
              isFavorite: favoriteIds.contains(product.id),
              primaryActionLabel: actionLabel.isEmpty ? null : actionLabel,
              onTap: () => onProductTap(product),
              onPrimaryAction: onPrimaryAction == null
                  ? null
                  : () => onPrimaryAction!(product),
              onFavoriteToggle: onFavoriteToggle == null
                  ? null
                  : () => onFavoriteToggle!(product),
            ),
          ),
      ],
    );
  }
}
