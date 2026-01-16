/// lib/app/features/home/presentation/home_popular_section.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Popular products list for the Home screen.
///
/// WHY:
/// - Highlights items while keeping HomeScreen concise.
/// - Uses existing product data without new backend calls.
///
/// HOW:
/// - Renders a horizontal list of product cards.
/// - Parent provides tap handler for navigation.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';

class HomePopularSection extends StatelessWidget {
  final List<Product> products;
  final VoidCallback onSeeAllTap;
  final ValueChanged<Product> onProductTap;

  const HomePopularSection({
    super.key,
    required this.products,
    required this.onSeeAllTap,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_POPULAR", "build()");

    final items = products.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: "Popular items",
          onActionTap: () {
            AppDebug.log("HOME_POPULAR", "See all tapped");
            onSeeAllTap();
          },
        ),
        const SizedBox(height: 8),
        // WHY: Horizontal cards create a compact browse section.
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final product = items[index];
              return _PopularCard(
                product: product,
                onTap: () {
                  AppDebug.log(
                    "HOME_POPULAR",
                    "Product tapped",
                    extra: {"id": product.id},
                  );
                  onProductTap(product);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PopularCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _PopularCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final priceText = _formatPrice(product.priceCents);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WHY: Image at top provides quick visual context.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Image.network(
                product.imageUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                priceText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(int priceCents) {
    final value = (priceCents / 100).toStringAsFixed(2);
    return "NGN $value";
  }
}
