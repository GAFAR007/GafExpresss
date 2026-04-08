library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/storefront_product_card.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomePopularSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product>? onPrimaryAction;
  final ValueChanged<Product>? onFavoriteToggle;
  final Set<String> favoriteIds;
  final String? actionLabel;
  final VoidCallback? onSeeAllTap;

  const HomePopularSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.products,
    required this.onProductTap,
    this.onPrimaryAction,
    this.onFavoriteToggle,
    this.favoriteIds = const {},
    this.actionLabel,
    this.onSeeAllTap,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleItems = products.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: title,
          subtitle: subtitle,
          actionLabel: onSeeAllTap == null ? "" : "See all",
          onActionTap: onSeeAllTap,
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return SizedBox(
                height: 430,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: visibleItems.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: AppSpacing.lg),
                  itemBuilder: (context, index) {
                    final product = visibleItems[index];
                    return SizedBox(
                      width: 286,
                      child: StorefrontProductCard(
                        product: product,
                        isFavorite: favoriteIds.contains(product.id),
                        primaryActionLabel: actionLabel,
                        onTap: () => onProductTap(product),
                        onPrimaryAction: onPrimaryAction == null
                            ? null
                            : () => onPrimaryAction!(product),
                        onFavoriteToggle: onFavoriteToggle == null
                            ? null
                            : () => onFavoriteToggle!(product),
                      ),
                    );
                  },
                ),
              );
            }

            final columns = AppLayout.columnsForWidth(
              constraints.maxWidth,
              compact: 1,
              medium: 2,
              large: 3,
              xlarge: 3,
            );
            final spacing = AppSpacing.lg;
            final cardWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final product in visibleItems)
                  SizedBox(
                    width: cardWidth,
                    height: 430,
                    child: StorefrontProductCard(
                      product: product,
                      isFavorite: favoriteIds.contains(product.id),
                      primaryActionLabel: actionLabel,
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
          },
        ),
      ],
    );
  }
}
