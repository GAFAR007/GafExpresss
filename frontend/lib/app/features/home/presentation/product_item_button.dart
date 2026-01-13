/// lib/app/features/home/presentation/product_item_button.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Clickable product item component (button-style card).
///
/// WHY:
/// - Makes each product item fully tappable for navigation.
/// - Keeps item UI consistent across lists/grids.
///
/// HOW:
/// - Wraps a Card in an InkWell and calls onTap when pressed.
/// - Renders image, name, price, stock, and description.
///
/// DEBUGGING:
/// - Logs build and tap with product id (safe only).
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:frontend/app/core/debug/app_debug.dart';

/// View model for product UI rendering.
class ProductItemData {
  final String id;
  final String name;
  final String description;
  final int priceCents;
  final int stock;
  final String imageUrl;

  const ProductItemData({
    required this.id,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.stock,
    required this.imageUrl,
  });
}

class ProductItemButton extends StatelessWidget {
  final ProductItemData item;
  final VoidCallback onTap;

  const ProductItemButton({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log("PRODUCT_ITEM", "build()", extra: {"id": item.id});

    final priceText = _formatPrice(item.priceCents);
    final inStock = item.stock > 0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AppDebug.log("PRODUCT_ITEM", "tap", extra: {"id": item.id});
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WHY: Image placeholder keeps layout stable if image fails.
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  item.imageUrl,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          priceText,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: inStock
                                ? Colors.green.shade50
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            inStock ? "In stock" : "Out of stock",
                            style: TextStyle(
                              color: inStock
                                  ? Colors.green.shade700
                                  : Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// WHY: Centralizes price formatting for consistent display.
  String _formatPrice(int priceCents) {
    final value = (priceCents / 100).toStringAsFixed(2);
    return "₦$value";
  }
}
