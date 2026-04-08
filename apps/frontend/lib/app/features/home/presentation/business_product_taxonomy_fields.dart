/// lib/app/features/home/presentation/business_product_taxonomy_fields.dart
/// ----------------------------------------------------------------------
/// WHAT:
/// - Shared taxonomy fields for business product create/edit flows.
///
/// WHY:
/// - Keeps category, subcategory, and brand inputs consistent everywhere.
/// - Supports structured catalog picks plus custom fallback text.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/product_taxonomy.dart';

class BusinessProductTaxonomyFields extends StatelessWidget {
  final TextEditingController categoryCtrl;
  final TextEditingController subcategoryCtrl;
  final TextEditingController brandCtrl;
  final List<String> extraBrandSuggestions;
  final bool useCustomCategory;
  final bool useCustomSubcategory;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<String?> onSubcategorySelected;

  const BusinessProductTaxonomyFields({
    super.key,
    required this.categoryCtrl,
    required this.subcategoryCtrl,
    required this.brandCtrl,
    this.extraBrandSuggestions = const [],
    required this.useCustomCategory,
    required this.useCustomSubcategory,
    required this.onCategorySelected,
    required this.onSubcategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final categoryText = categoryCtrl.text.trim();
    final subcategoryText = subcategoryCtrl.text.trim();
    final selectedCategory = useCustomCategory
        ? null
        : findProductTaxonomyCategory(categoryText);
    final selectedSubcategory = useCustomSubcategory
        ? null
        : findProductTaxonomySubcategory(
            categoryLabel: categoryText,
            subcategoryLabel: subcategoryText,
          );
    final brandSuggestions = productBrandSuggestions(
      categoryLabel: categoryText,
      subcategoryLabel: subcategoryText,
      extraSuggestions: extraBrandSuggestions,
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            "category-${useCustomCategory ? productTaxonomyCustomValue : selectedCategory?.label ?? "empty"}",
          ),
          initialValue: useCustomCategory
              ? productTaxonomyCustomValue
              : selectedCategory?.label,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "Category",
            hintText: "Select a main category",
          ),
          items: [
            for (final category in productTaxonomyCatalog)
              DropdownMenuItem(
                value: category.label,
                child: Text(category.label),
              ),
            const DropdownMenuItem(
              value: productTaxonomyCustomValue,
              child: Text("Custom category"),
            ),
          ],
          onChanged: onCategorySelected,
        ),
        if (selectedCategory != null) ...[
          const SizedBox(height: 8),
          Text(
            selectedCategory.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (useCustomCategory) ...[
          const SizedBox(height: 12),
          TextField(
            controller: categoryCtrl,
            decoration: const InputDecoration(
              labelText: "Custom category",
              hintText: "Fashion & Apparel",
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (selectedCategory != null)
          DropdownButtonFormField<String>(
            key: ValueKey(
              "subcategory-${useCustomSubcategory ? productTaxonomyCustomValue : selectedSubcategory?.label ?? "empty"}",
            ),
            initialValue: useCustomSubcategory
                ? productTaxonomyCustomValue
                : selectedSubcategory?.label,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: "Subcategory",
              hintText: "Select a subcategory",
            ),
            items: [
              for (final subcategory in selectedCategory.subcategories)
                DropdownMenuItem(
                  value: subcategory.label,
                  child: Text(subcategory.label),
                ),
              const DropdownMenuItem(
                value: productTaxonomyCustomValue,
                child: Text("Custom subcategory"),
              ),
            ],
            onChanged: onSubcategorySelected,
          )
        else
          TextField(
            controller: subcategoryCtrl,
            decoration: const InputDecoration(
              labelText: "Subcategory",
              hintText: "T-Shirts, Phones, Grains & Cereals",
            ),
          ),
        if (useCustomSubcategory) ...[
          const SizedBox(height: 12),
          TextField(
            controller: subcategoryCtrl,
            decoration: const InputDecoration(
              labelText: "Custom subcategory",
              hintText: "Hoodies",
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: brandCtrl,
          decoration: const InputDecoration(
            labelText: "Brand",
            hintText: "Nike, Apple, Levi's",
          ),
        ),
        if (brandSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in brandSuggestions.take(8))
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    brandCtrl.text = suggestion;
                    brandCtrl.selection = TextSelection.collapsed(
                      offset: brandCtrl.text.length,
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
