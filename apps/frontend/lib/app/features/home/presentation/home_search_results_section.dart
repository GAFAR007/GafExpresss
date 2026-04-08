library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/storefront_product_card.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomeSearchResultsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Product> results;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product>? onPrimaryAction;
  final ValueChanged<Product>? onFavoriteToggle;
  final Set<String> favoriteIds;
  final String? actionLabel;

  const HomeSearchResultsSection({
    super.key,
    this.title = "Search results",
    this.subtitle =
        "Browse filtered products with cleaner pricing and variant detail.",
    required this.results,
    required this.onProductTap,
    this.onPrimaryAction,
    this.onFavoriteToggle,
    this.favoriteIds = const {},
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title: title, subtitle: subtitle, actionLabel: ""),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = AppLayout.columnsForWidth(
              constraints.maxWidth,
              compact: 1,
              medium: 2,
              large: 3,
              xlarge: 4,
            );
            final spacing = AppSpacing.lg;
            final width =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final product in results)
                  SizedBox(
                    width: width,
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
