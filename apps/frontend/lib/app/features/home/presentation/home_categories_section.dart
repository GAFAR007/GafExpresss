/// lib/app/features/home/presentation/home_categories_section.dart
/// --------------------------------------------------------------
/// WHAT:
/// - Renders category and subcategory shortcut chips for storefront discovery.
///
/// WHY:
/// - Lets shoppers jump into either a broad category or a specific
///   subcategory without relying on text search.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/home_section_header.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class StorefrontCategorySummary {
  final String label;
  final String helper;
  final int itemCount;
  final IconData icon;
  final Color accent;
  final String? parentCategory;

  const StorefrontCategorySummary({
    required this.label,
    required this.helper,
    required this.itemCount,
    required this.icon,
    required this.accent,
    this.parentCategory,
  });
}

class HomeCategoriesSection extends StatelessWidget {
  final List<StorefrontCategorySummary> categories;
  final List<StorefrontCategorySummary> subcategories;
  final ValueChanged<String> onCategoryTap;
  final ValueChanged<StorefrontCategorySummary> onSubcategoryTap;
  final String? selectedCategory;
  final String? selectedSubcategory;

  const HomeCategoriesSection({
    super.key,
    required this.categories,
    required this.subcategories,
    required this.onCategoryTap,
    required this.onSubcategoryTap,
    this.selectedCategory,
    this.selectedSubcategory,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final allCategory = StorefrontCategorySummary(
      label: "All",
      helper: "All products",
      itemCount: categories.fold<int>(
        0,
        (total, item) => total + item.itemCount,
      ),
      icon: Icons.grid_view_rounded,
      accent: scheme.primary,
    );
    final visibleCategories = [allCategory, ...categories];
    final visibleSubcategories = _visibleSubcategories();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionHeader(
          title: "Shop by category",
          subtitle: "",
          actionLabel: "",
        ),
        const SizedBox(height: AppSpacing.md),
        _StorefrontShortcutList(
          items: visibleCategories,
          selectedLabel: selectedCategory,
          isAllSelected: selectedCategory == null,
          onTap: (item) => onCategoryTap(item.label == "All" ? "" : item.label),
        ),
        if (visibleSubcategories.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            selectedCategory == null
                ? "Shop by subcategory"
                : "Shop ${selectedCategory!} styles",
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.md),
          _StorefrontShortcutList(
            items: visibleSubcategories,
            selectedLabel: selectedSubcategory,
            isAllSelected: selectedSubcategory == null,
            onTap: onSubcategoryTap,
          ),
        ],
      ],
    );
  }

  List<StorefrontCategorySummary> _visibleSubcategories() {
    final normalizedCategory = (selectedCategory ?? "").trim().toLowerCase();
    if (normalizedCategory.isEmpty) {
      return subcategories;
    }

    return subcategories
        .where(
          (item) =>
              (item.parentCategory ?? "").trim().toLowerCase() ==
              normalizedCategory,
        )
        .toList();
  }
}

class _StorefrontShortcutList extends StatelessWidget {
  final List<StorefrontCategorySummary> items;
  final String? selectedLabel;
  final bool isAllSelected;
  final ValueChanged<StorefrontCategorySummary> onTap;

  const _StorefrontShortcutList({
    required this.items,
    required this.selectedLabel,
    required this.isAllSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final item = items[index];
                return StorefrontCategoryCard(
                  item: item,
                  selected: item.label == "All"
                      ? isAllSelected
                      : _isSelected(item.label),
                  onTap: () => onTap(item),
                );
              },
            ),
          );
        }

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final item in items)
              StorefrontCategoryCard(
                item: item,
                selected: item.label == "All"
                    ? isAllSelected
                    : _isSelected(item.label),
                onTap: () => onTap(item),
              ),
          ],
        );
      },
    );
  }

  bool _isSelected(String label) =>
      (selectedLabel ?? "").trim().toLowerCase() == label.toLowerCase();
}

class StorefrontCategoryCard extends StatelessWidget {
  final StorefrontCategorySummary item;
  final VoidCallback onTap;
  final bool selected;

  const StorefrontCategoryCard({
    super.key,
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? item.accent.withValues(alpha: 0.14)
                : scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? item.accent : scheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(item.icon, color: item.accent, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? item.accent : scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
