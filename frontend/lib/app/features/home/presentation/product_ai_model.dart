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

const String _logTag = "PRODUCT_AI_MODEL";

class ProductDraft {
  final String name;
  final String description;
  final int priceNgn;
  final int stock;
  final String imageUrl;

  const ProductDraft({
    required this.name,
    required this.description,
    required this.priceNgn,
    required this.stock,
    required this.imageUrl,
  });

  factory ProductDraft.fromJson(Map<String, dynamic> json) {
    // WHY: Keep model parsing explicit for reliable UI autofill.
    AppDebug.log(
      _logTag,
      "fromJson()",
      extra: {"hasName": (json["name"] ?? "").toString().isNotEmpty},
    );

    final priceValue = json["priceNgn"];
    final stockValue = json["stock"];

    return ProductDraft(
      name: (json["name"] ?? "").toString(),
      description: (json["description"] ?? "").toString(),
      priceNgn: priceValue is int
          ? priceValue
          : int.tryParse(priceValue?.toString() ?? "") ?? 0,
      stock: stockValue is int
          ? stockValue
          : int.tryParse(stockValue?.toString() ?? "") ?? 0,
      imageUrl: (json["imageUrl"] ?? "").toString(),
    );
  }
}
