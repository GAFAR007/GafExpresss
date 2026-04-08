library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/storefront_product_card.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StorefrontHorizontalProductList extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product>? onPrimaryAction;
  final ValueChanged<Product>? onFavoriteToggle;
  final Set<String> favoriteIds;
  final String? actionLabel;
  final bool featuredCards;
  final double cardWidth;

  const StorefrontHorizontalProductList({
    super.key,
    required this.products,
    required this.onProductTap,
    this.onPrimaryAction,
    this.onFavoriteToggle,
    this.favoriteIds = const {},
    this.actionLabel,
    this.featuredCards = false,
    this.cardWidth = 276,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const SizedBox.shrink();
    }

    final height = featuredCards ? 470.0 : 430.0;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.lg),
        itemBuilder: (context, index) {
          final product = products[index];
          return SizedBox(
            width: cardWidth,
            child: StorefrontProductCard(
              product: product,
              featured: featuredCards,
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
}
