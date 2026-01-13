/// lib/app/features/home/presentation/product_model.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Product model for frontend rendering.
///
/// WHY:
/// - Maps backend /products payload into a typed Dart object.
///
/// HOW:
/// - fromJson parses Product fields from API response.
///
/// DEBUGGING:
/// - Logs parsing with product id (safe only).
/// ------------------------------------------------------------

import 'package:frontend/app/core/debug/app_debug.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final int priceCents;
  final int stock;
  final String imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.stock,
    required this.imageUrl,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final id = (json["_id"] ?? json["id"] ?? "").toString();
    AppDebug.log("PRODUCT_MODEL", "fromJson()", extra: {"id": id});

    return Product(
      id: id,
      name: (json["name"] ?? "").toString(),
      description: (json["description"] ?? "").toString(),
      priceCents: (json["price"] ?? 0) is int
          ? (json["price"] ?? 0) as int
          : int.tryParse((json["price"] ?? 0).toString()) ?? 0,
      stock: (json["stock"] ?? 0) is int
          ? (json["stock"] ?? 0) as int
          : int.tryParse((json["stock"] ?? 0).toString()) ?? 0,
      imageUrl: (json["imageUrl"] ?? "").toString(),
      isActive: (json["isActive"] ?? true) == true,
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
