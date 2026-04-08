/// lib/app/features/home/presentation/product_ai_model.dart
/// -------------------------------------------------------
/// WHAT:
/// - ProductDraft model for AI-assisted product creation.
///
/// WHY:
/// - Keeps AI draft parsing consistent and typed for UI autofill.
/// - Prevents UI widgets from handling raw JSON maps directly.
///
/// HOW:
/// - fromJson normalizes fields from /business/products/ai-draft.
/// - Provides safe defaults for missing or invalid fields.
///
/// DEBUGGING:
/// - Logs parsing with a lightweight flag (no sensitive data).
/// -------------------------------------------------------
library;

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/product_selling_option.dart';

const String _logTag = "PRODUCT_AI_MODEL";

class ProductDraft {
  final String name;
  final String description;
  final String category;
  final String subcategory;
  final String brand;
  final List<ProductSellingOption> sellingOptions;
  final List<String> sellingUnits;
  final String defaultSellingUnit;
  final int priceNgn;
  final int stock;

  const ProductDraft({
    required this.name,
    required this.description,
    required this.category,
    required this.subcategory,
    required this.brand,
    required this.sellingOptions,
    required this.sellingUnits,
    required this.defaultSellingUnit,
    required this.priceNgn,
    required this.stock,
  });

  ProductSellingOption? get defaultSellingOption {
    if (sellingOptions.isEmpty) {
      return null;
    }
    for (final option in sellingOptions) {
      if (option.isDefault) {
        return option;
      }
    }
    return sellingOptions.first;
  }

  factory ProductDraft.fromJson(Map<String, dynamic> json) {
    // WHY: Keep model parsing explicit for reliable UI autofill.
    AppDebug.log(
      _logTag,
      "fromJson()",
      extra: {"hasName": (json["name"] ?? "").toString().isNotEmpty},
    );

    final priceValue = json["priceNgn"];
    final stockValue = json["stock"];
    final sellingOptions = parseProductSellingOptions(
      rawSellingOptions: json["sellingOptions"],
      rawSellingUnits: json["sellingUnits"],
      rawDefaultSellingUnit: json["defaultSellingUnit"],
    );

    return ProductDraft(
      name: (json["name"] ?? "").toString().trim(),
      description: (json["description"] ?? "").toString().trim(),
      category: (json["category"] ?? "").toString().trim(),
      subcategory: (json["subcategory"] ?? "").toString().trim(),
      brand: (json["brand"] ?? "").toString().trim(),
      sellingOptions: sellingOptions,
      sellingUnits: deriveSellingUnitsFromOptions(sellingOptions),
      defaultSellingUnit: deriveDefaultSellingUnitFromOptions(sellingOptions),
      priceNgn: priceValue is int
          ? priceValue
          : int.tryParse(priceValue?.toString() ?? "") ?? 0,
      stock: stockValue is int
          ? stockValue
          : int.tryParse(stockValue?.toString() ?? "") ?? 0,
    );
  }
}
