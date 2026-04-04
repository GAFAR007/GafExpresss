/// lib/app/features/home/presentation/business_product_selling_fields.dart
/// ---------------------------------------------------------------------
/// WHAT:
/// - Shared structured selling-option inputs for business product flows.
///
/// WHY:
/// - Products can be sold as specific package + quantity + measurement combos.
/// - Keeps create/edit flows aligned with catalog and checkout labels.
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/home/presentation/product_selling_option.dart';

class BusinessProductSellingFields extends StatelessWidget {
  final List<ProductSellingOption> sellingOptions;
  final List<String> suggestedPackageTypes;
  final List<String> suggestedMeasurementUnits;
  final TextEditingController packageTypeCtrl;
  final TextEditingController quantityCtrl;
  final TextEditingController measurementUnitCtrl;
  final ValueChanged<String> onPackageTypeSuggestion;
  final ValueChanged<String> onMeasurementUnitSuggestion;
  final VoidCallback onAddOption;
  final ValueChanged<ProductSellingOption> onSetDefault;
  final ValueChanged<ProductSellingOption> onRemoveOption;

  const BusinessProductSellingFields({
    super.key,
    required this.sellingOptions,
    required this.suggestedPackageTypes,
    required this.suggestedMeasurementUnits,
    required this.packageTypeCtrl,
    required this.quantityCtrl,
    required this.measurementUnitCtrl,
    required this.onPackageTypeSuggestion,
    required this.onMeasurementUnitSuggestion,
    required this.onAddOption,
    required this.onSetDefault,
    required this.onRemoveOption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Selling options", style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          "Define exactly how this product is sold, for example Bag of 20 kg, Basket of 5 kg, or Bundle of 3 pieces. One option must be the default.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: packageTypeCtrl,
          decoration: const InputDecoration(
            labelText: "Package type",
            hintText: "Bag, Piece, Bundle, Carton",
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in suggestedPackageTypes.take(16))
              ActionChip(
                label: Text(suggestion),
                onPressed: () => onPackageTypeSuggestion(suggestion),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: quantityCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "Quantity",
                  hintText: "20",
                ),
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: measurementUnitCtrl,
                decoration: const InputDecoration(
                  labelText: "Measurement unit",
                  hintText: "kg, piece, pair, ml",
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAddOption(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in suggestedMeasurementUnits.take(16))
              ActionChip(
                label: Text(suggestion),
                onPressed: () => onMeasurementUnitSuggestion(suggestion),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAddOption,
            icon: const Icon(Icons.add),
            label: const Text("Add selling option"),
          ),
        ),
        if (sellingOptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            "Current options",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in sellingOptions)
                InputChip(
                  label: Text(option.displayLabel),
                  selected: option.isDefault,
                  avatar: option.isDefault
                      ? const Icon(Icons.check_circle_outline, size: 18)
                      : const Icon(Icons.inventory_2_outlined, size: 18),
                  onPressed: () => onSetDefault(option),
                  onDeleted: () => onRemoveOption(option),
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
