/// lib/app/features/home/presentation/home_search_results_section.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Search results section for the Home screen.
///
/// WHY:
/// - Keeps HomeScreen clean by extracting result rendering.
/// - Reuses existing product card UI for consistency.
///
/// HOW:
/// - Renders a header + vertical list of ProductItemButton cards.
/// - Parent handles navigation via onProductTap.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/features/home/presentation/product_item_button.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';

class HomeSearchResultsSection extends StatelessWidget {
  // WHY: Allow HomeScreen to rename the section for filters vs. search.
  final String title;
  final List<Product> results;
  final ValueChanged<Product> onProductTap;

  const HomeSearchResultsSection({
    super.key,
    this.title = "Search results",
    required this.results,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "HOME_SEARCH_RESULTS",
      "build()",
      extra: {"count": results.length, "title": title},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHY: Header text should reflect whether filters or search are active.
        HomeSectionHeader(title: title, actionLabel: ""),
        const SizedBox(height: 8),
        // WHY: Vertical list keeps product cards easy to scan.
        for (final product in results) ...[
          ProductItemButton(
            item: ProductItemData(
              id: product.id,
              name: product.name,
              description: product.description,
              priceCents: product.priceCents,
              stock: product.stock,
              imageUrl: product.imageUrl,
            ),
            onTap: () {
              AppDebug.log(
                "HOME_SEARCH_RESULTS",
                "Result tapped",
                extra: {"id": product.id},
              );
              onProductTap(product);
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
