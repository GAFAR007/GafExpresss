library;

import 'package:flutter/material.dart';

import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';

class HomeSearchSection extends StatelessWidget {
  final VoidCallback onFilterTap;
  final ValueChanged<String>? onSearchSubmitted;
  final ValueChanged<String>? onSearchChanged;
  final bool hasActiveFilters;
  final TextEditingController? controller;
  final List<String> quickCategories;
  final String? selectedCategory;
  final ValueChanged<String>? onCategorySelected;

  const HomeSearchSection({
    super.key,
    required this.onFilterTap,
    this.onSearchSubmitted,
    this.onSearchChanged,
    this.hasActiveFilters = false,
    this.controller,
    this.quickCategories = const [],
    this.selectedCategory,
    this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: "Search products, categories, or brands",
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: colorScheme.primary,
                    ),
                    suffixIcon:
                        controller != null && controller!.text.trim().isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              controller!.clear();
                              onSearchChanged?.call("");
                              onSearchSubmitted?.call("");
                            },
                            icon: const Icon(Icons.close_rounded),
                            tooltip: "Clear search",
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchSubmitted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonalIcon(
                onPressed: onFilterTap,
                icon: Icon(
                  hasActiveFilters ? Icons.tune_rounded : Icons.tune_outlined,
                ),
                label: Text(hasActiveFilters ? "Filtered" : "Filter"),
              ),
            ],
          ),
          if (quickCategories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final category in quickCategories)
                    ChoiceChip(
                      selected:
                          (selectedCategory ?? "").trim().toLowerCase() ==
                          category.toLowerCase(),
                      label: Text(category),
                      onSelected: (_) => onCategorySelected?.call(category),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
