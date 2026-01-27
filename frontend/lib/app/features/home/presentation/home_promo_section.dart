/// lib/app/features/home/presentation/home_promo_section.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Promotional carousel for the Home screen.
///
/// WHY:
/// - Creates a hero moment similar to the reference layout.
/// - Highlights a few products without changing business logic.
///
/// HOW:
/// - Uses a PageView to render promo cards from product data.
/// - Displays a simple dot indicator for page position.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';

class HomePromoSection extends StatefulWidget {
  final List<Product> products;
  final VoidCallback onSeeAllTap;
  final ValueChanged<Product> onPromoTap;

  const HomePromoSection({
    super.key,
    required this.products,
    required this.onSeeAllTap,
    required this.onPromoTap,
  });

  @override
  State<HomePromoSection> createState() => _HomePromoSectionState();
}

class _HomePromoSectionState extends State<HomePromoSection> {
  final PageController _controller = PageController(viewportFraction: 0.92);
  int _activeIndex = 0;

  @override
  void dispose() {
    // WHY: Dispose controller to avoid leaks in long sessions.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_PROMO", "build()");

    final promoItems = widget.products.take(3).toList();

    if (promoItems.isEmpty) {
      // WHY: Avoid empty PageView when no data is available.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeader(
            title: "#SpecialForYou",
            onActionTap: () {
              AppDebug.log("HOME_PROMO", "See all tapped");
              widget.onSeeAllTap();
            },
          ),
          const SizedBox(height: 12),
          const Text("No promotions available yet."),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: "#SpecialForYou",
          onActionTap: () {
            AppDebug.log("HOME_PROMO", "See all tapped");
            widget.onSeeAllTap();
          },
        ),
        const SizedBox(height: 8),
        // WHY: Fixed height ensures consistent hero size across devices.
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _controller,
            itemCount: promoItems.length,
            onPageChanged: (index) {
              AppDebug.log(
                "HOME_PROMO",
                "Page changed",
                extra: {"index": index},
              );
              setState(() => _activeIndex = index);
            },
            itemBuilder: (context, index) {
              final product = promoItems[index];
              return _PromoCard(
                product: product,
                onTap: () {
                  AppDebug.log(
                    "HOME_PROMO",
                    "Promo tapped",
                    extra: {"id": product.id},
                  );
                  widget.onPromoTap(product);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // WHY: Dot indicators show position without heavy UI.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            promoItems.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _activeIndex == index ? 14 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _activeIndex == index
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _PromoCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colorScheme.surfaceContainerHighest,
            image: DecorationImage(
              image: NetworkImage(product.imageUrl),
              fit: BoxFit.cover,
              onError: (_, __) {},
            ),
          ),
          child: Container(
            // WHY: Gradient overlay improves text contrast on images.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  colorScheme.scrim.withOpacity(0.55),
                  colorScheme.surface.withOpacity(0),
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.center,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WHY: Tag reinforces the promo style.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.scrim.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "Limited offer",
                      style: TextStyle(
                        color: colorScheme.surface,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.surface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
