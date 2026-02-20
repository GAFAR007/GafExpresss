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
library;

import 'package:frontend/app/core/debug/app_debug.dart';

class Product {
  final String id;
  final String name;
  final String description;
  final int priceCents;
  final int stock;
  final String imageUrl;
  final List<String> imageUrls;
  final bool isActive;
  final String productionState;
  final String? productionPlanId;
  final bool preorderEnabled;
  final int preorderCapQuantity;
  final int preorderReservedQuantity;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? businessId;
  final String? createdBy;
  final String? updatedBy;
  final String? deletedBy;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.stock,
    required this.imageUrl,
    required this.imageUrls,
    required this.isActive,
    required this.productionState,
    required this.productionPlanId,
    required this.preorderEnabled,
    required this.preorderCapQuantity,
    required this.preorderReservedQuantity,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.businessId,
    this.createdBy,
    this.updatedBy,
    this.deletedBy,
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
      imageUrls: ((json["imageUrls"] ?? []) as List<dynamic>)
          .map((item) => item.toString())
          .toList(),
      isActive: (json["isActive"] ?? true) == true,
      productionState: (json["productionState"] ?? "").toString(),
      productionPlanId: _parseObjectId(json["productionPlanId"]),
      preorderEnabled: (json["preorderEnabled"] ?? false) == true,
      preorderCapQuantity: (json["preorderCapQuantity"] ?? 0) is int
          ? (json["preorderCapQuantity"] ?? 0) as int
          : int.tryParse((json["preorderCapQuantity"] ?? 0).toString()) ?? 0,
      preorderReservedQuantity: (json["preorderReservedQuantity"] ?? 0) is int
          ? (json["preorderReservedQuantity"] ?? 0) as int
          : int.tryParse((json["preorderReservedQuantity"] ?? 0).toString()) ??
                0,
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
      deletedAt: _parseDate(json["deletedAt"]),
      businessId: _parseString(json["businessId"]),
      createdBy: _parseString(json["createdBy"]),
      updatedBy: _parseString(json["updatedBy"]),
      deletedBy: _parseString(json["deletedBy"]),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.trim().isEmpty) return null;
    return text;
  }

  static String? _parseObjectId(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) {
      return _parseString(value["_id"] ?? value["id"]);
    }
    return _parseString(value);
  }
}

class PreorderAvailability {
  final bool preorderEnabled;
  final int preorderCapQuantity;
  final int preorderReservedQuantity;
  final int preorderRemainingQuantity;
  final int baseCap;
  final int effectiveCap;
  final double confidenceScore;
  final double approvedProgressCoverage;

  const PreorderAvailability({
    required this.preorderEnabled,
    required this.preorderCapQuantity,
    required this.preorderReservedQuantity,
    required this.preorderRemainingQuantity,
    required this.baseCap,
    required this.effectiveCap,
    required this.confidenceScore,
    required this.approvedProgressCoverage,
  });

  int get effectiveRemainingQuantity {
    final remaining = effectiveCap - preorderReservedQuantity;
    if (remaining <= 0) {
      return 0;
    }
    return remaining;
  }

  factory PreorderAvailability.fromJson(Map<String, dynamic> json) {
    return PreorderAvailability(
      preorderEnabled: json["preorderEnabled"] == true,
      preorderCapQuantity: _parseInt(json["preorderCapQuantity"]),
      preorderReservedQuantity: _parseInt(json["preorderReservedQuantity"]),
      preorderRemainingQuantity: _parseInt(json["preorderRemainingQuantity"]),
      baseCap: _parseInt(json["baseCap"]),
      effectiveCap: _parseInt(json["effectiveCap"]),
      confidenceScore: _parseDouble(json["confidenceScore"]),
      approvedProgressCoverage: _parseDouble(json["approvedProgressCoverage"]),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse((value ?? 0).toString()) ?? 0;
  }

  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse((value ?? 0).toString()) ?? 0;
  }
}

class PreorderReserveResult {
  final String reservationId;
  final int quantity;
  final String status;
  final int cap;
  final int reserved;
  final int remaining;
  final int effectiveCap;

  const PreorderReserveResult({
    required this.reservationId,
    required this.quantity,
    required this.status,
    required this.cap,
    required this.reserved,
    required this.remaining,
    required this.effectiveCap,
  });

  factory PreorderReserveResult.fromJson(Map<String, dynamic> json) {
    final reservation = (json["reservation"] is Map<String, dynamic>)
        ? json["reservation"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final summary = (json["preorderSummary"] is Map<String, dynamic>)
        ? json["preorderSummary"] as Map<String, dynamic>
        : const <String, dynamic>{};

    return PreorderReserveResult(
      reservationId: (reservation["_id"] ?? reservation["id"] ?? "").toString(),
      quantity: PreorderAvailability._parseInt(reservation["quantity"]),
      status: (reservation["status"] ?? "").toString(),
      cap: PreorderAvailability._parseInt(summary["cap"]),
      reserved: PreorderAvailability._parseInt(summary["reserved"]),
      remaining: PreorderAvailability._parseInt(summary["remaining"]),
      effectiveCap: PreorderAvailability._parseInt(summary["effectiveCap"]),
    );
  }
}

class PreorderReleaseResult {
  final String reservationId;
  final String status;
  final bool idempotent;
  final int cap;
  final int reserved;
  final int remaining;

  const PreorderReleaseResult({
    required this.reservationId,
    required this.status,
    required this.idempotent,
    required this.cap,
    required this.reserved,
    required this.remaining,
  });

  factory PreorderReleaseResult.fromJson(Map<String, dynamic> json) {
    final reservation = (json["reservation"] is Map<String, dynamic>)
        ? json["reservation"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final summary = (json["preorderSummary"] is Map<String, dynamic>)
        ? json["preorderSummary"] as Map<String, dynamic>
        : const <String, dynamic>{};

    return PreorderReleaseResult(
      reservationId: (reservation["_id"] ?? reservation["id"] ?? "").toString(),
      status: (reservation["status"] ?? "").toString(),
      idempotent: json["idempotent"] == true,
      cap: PreorderAvailability._parseInt(summary["cap"]),
      reserved: PreorderAvailability._parseInt(summary["reserved"]),
      remaining: PreorderAvailability._parseInt(summary["remaining"]),
    );
  }
}
