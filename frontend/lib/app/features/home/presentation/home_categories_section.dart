/// lib/app/features/home/presentation/home_categories_section.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Categories strip for the Home screen.
///
/// WHY:
/// - Mirrors the reference layout and aids quick discovery.
/// - Keeps HomeScreen clean by extracting the grid layout.
///
/// HOW:
/// - Uses a horizontal list of category pills with icons.
/// - Parent provides tap handling for logging/navigation.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/home_section_header.dart';

class HomeCategoriesSection extends StatelessWidget {
  final VoidCallback onSeeAllTap;
  final ValueChanged<String> onCategoryTap;

  const HomeCategoriesSection({
    super.key,
    required this.onSeeAllTap,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_CATEGORIES", "build()");

    final categories = [
      _CategoryItem("Stationery", Icons.edit),
      _CategoryItem("Tech", Icons.devices),
      _CategoryItem("Furniture", Icons.chair),
      _CategoryItem("Logistics", Icons.local_shipping),
      _CategoryItem("Supplies", Icons.inventory_2),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: "Categories",
          onActionTap: () {
            AppDebug.log("HOME_CATEGORIES", "See all tapped");
            onSeeAllTap();
          },
        ),
        const SizedBox(height: 8),
        // WHY: Horizontal list fits small screens without wrapping.
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategoryCard(
                item: category,
                onTap: () {
                  AppDebug.log(
                    "HOME_CATEGORIES",
                    "Category tapped",
                    extra: {"label": category.label},
                  );
                  onCategoryTap(category.label);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryItem {
  final String label;
  final IconData icon;

  const _CategoryItem(this.label, this.icon);
}

class _CategoryCard extends StatelessWidget {
  final _CategoryItem item;
  final VoidCallback onTap;

  const _CategoryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 92,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // WHY: Icon in a circle matches the reference style.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, size: 22, color: colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
