/// lib/app/features/home/presentation/product_model.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Product model for frontend rendering.
///
/// WHY:
/// - Keeps one normalized backend product shape for home, login, cart,
///   and product details.
library;

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/product_selling_option.dart';

class ProductColorVariant {
  final String name;
  final String hexCode;
  final String? imageUrl;

  const ProductColorVariant({
    required this.name,
    required this.hexCode,
    this.imageUrl,
  });

  factory ProductColorVariant.fromJson(Map<String, dynamic> json) {
    return ProductColorVariant(
      name: (json["name"] ?? json["label"] ?? "").toString(),
      hexCode: (json["hexCode"] ?? json["hex"] ?? "#000000").toString(),
      imageUrl: Product._parseString(json["imageUrl"]),
    );
  }
}

class Product {
  final String id;
  final String name;
  final String slug;
  final String description;
  final String longDescription;
  final String category;
  final String subcategory;
  final String brand;
  final List<ProductSellingOption> sellingOptions;
  final List<String> sellingUnits;
  final String defaultSellingUnit;
  final int priceCents;
  final int? oldPriceCents;
  final String currencyCode;
  final int stock;
  final double rating;
  final int reviewCount;
  final String imageUrl;
  final List<String> imageUrls;
  final List<String> badges;
  final List<ProductColorVariant> colorVariants;
  final List<String> sizeVariants;
  final String? unitLabel;
  final bool isFeatured;
  final bool isTrending;
  final bool isNewArrival;
  final bool isActive;
  final bool isPurchasable;
  final bool isLocalSeed;
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
    required this.slug,
    required this.description,
    required this.longDescription,
    required this.category,
    required this.subcategory,
    required this.brand,
    required this.sellingOptions,
    required this.sellingUnits,
    required this.defaultSellingUnit,
    required this.priceCents,
    required this.oldPriceCents,
    required this.currencyCode,
    required this.stock,
    required this.rating,
    required this.reviewCount,
    required this.imageUrl,
    required this.imageUrls,
    required this.badges,
    required this.colorVariants,
    required this.sizeVariants,
    required this.unitLabel,
    required this.isFeatured,
    required this.isTrending,
    required this.isNewArrival,
    required this.isActive,
    required this.isPurchasable,
    required this.isLocalSeed,
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

  String get primaryCategoryLabel =>
      subcategory.trim().isNotEmpty ? subcategory.trim() : category.trim();

  String get shortDescription => description.trim().isNotEmpty
      ? description.trim()
      : longDescription.trim();

  String get primaryImageUrl {
    if (imageUrl.trim().isNotEmpty) {
      return imageUrl.trim();
    }
    for (final candidate in imageUrls) {
      if (candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return "";
  }

  bool get hasDiscount =>
      oldPriceCents != null &&
      oldPriceCents! > 0 &&
      oldPriceCents! > priceCents;

  int? get discountPercent {
    if (!hasDiscount) {
      return null;
    }
    final savings = oldPriceCents! - priceCents;
    return ((savings / oldPriceCents!) * 100).round();
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final id = (json["_id"] ?? json["id"] ?? "").toString();
    final sellingOptions = parseProductSellingOptions(
      rawSellingOptions: json["sellingOptions"],
      rawSellingUnits: json["sellingUnits"],
      rawDefaultSellingUnit: json["defaultSellingUnit"],
    );
    final imageUrl = (json["imageUrl"] ?? json["thumbnail"] ?? "").toString();
    final imageUrls = ((json["imageUrls"] ?? json["images"] ?? []) as List)
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();

    AppDebug.log("PRODUCT_MODEL", "fromJson()", extra: {"id": id});

    return Product(
      id: id,
      name: (json["name"] ?? json["title"] ?? "").toString(),
      slug: (json["slug"] ?? _slugify((json["name"] ?? "").toString()))
          .toString(),
      description: (json["description"] ?? json["shortDescription"] ?? "")
          .toString(),
      longDescription:
          (json["longDescription"] ??
                  json["detailedDescription"] ??
                  json["description"] ??
                  "")
              .toString(),
      category: (json["category"] ?? "").toString(),
      subcategory: (json["subcategory"] ?? "").toString(),
      brand: (json["brand"] ?? "").toString(),
      sellingOptions: sellingOptions,
      sellingUnits: deriveSellingUnitsFromOptions(sellingOptions),
      defaultSellingUnit: deriveDefaultSellingUnitFromOptions(sellingOptions),
      priceCents: _parseInt(json["price"]),
      oldPriceCents: _parseNullableInt(
        json["oldPrice"] ?? json["compareAtPrice"] ?? json["oldPriceCents"],
      ),
      currencyCode: (json["currency"] ?? json["currencyCode"] ?? "NGN")
          .toString(),
      stock: _parseInt(json["stock"]),
      rating: _parseDouble(json["rating"]),
      reviewCount: _parseInt(json["reviewCount"] ?? json["reviews"]),
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      badges: _parseBadges(json),
      colorVariants: _parseColorVariants(json),
      sizeVariants: _parseStringList(
        json["sizeVariants"] ?? json["sizes"] ?? json["availableSizes"],
      ),
      unitLabel: _parseString(
        json["unitLabel"] ?? json["unit"] ?? json["defaultSellingUnit"],
      ),
      isFeatured: json["isFeatured"] == true,
      isTrending: json["isTrending"] == true,
      isNewArrival: json["isNewArrival"] == true,
      isActive: (json["isActive"] ?? true) == true,
      isPurchasable: (json["isPurchasable"] ?? true) == true,
      isLocalSeed: json["isLocalSeed"] == true,
      productionState: (json["productionState"] ?? "").toString(),
      productionPlanId: _parseObjectId(json["productionPlanId"]),
      preorderEnabled: (json["preorderEnabled"] ?? false) == true,
      preorderCapQuantity: _parseInt(json["preorderCapQuantity"]),
      preorderReservedQuantity: _parseInt(json["preorderReservedQuantity"]),
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
      deletedAt: _parseDate(json["deletedAt"]),
      businessId: _parseString(json["businessId"]),
      createdBy: _parseString(json["createdBy"]),
      updatedBy: _parseString(json["updatedBy"]),
      deletedBy: _parseString(json["deletedBy"]),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse((value ?? 0).toString()) ?? 0;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value.toString());
  }

  static double _parseDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse((value ?? 0).toString()) ?? 0;
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

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<ProductColorVariant> _parseColorVariants(
    Map<String, dynamic> json,
  ) {
    final raw = json["colorVariants"] ?? json["colors"];
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map(
          (item) =>
              ProductColorVariant.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static List<String> _parseBadges(Map<String, dynamic> json) {
    final badges = <String>{};

    if (json["badges"] is List) {
      badges.addAll(
        (json["badges"] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      );
    }

    if (json["isNewArrival"] == true) {
      badges.add("New");
    }
    if (json["isTrending"] == true) {
      badges.add("Trending");
    }
    if (json["isFeatured"] == true) {
      badges.add("Featured");
    }

    return badges.toList();
  }

  static String _slugify(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "-")
        .replaceAll(RegExp(r"(^-|-$)"), "");
    return normalized.isEmpty ? "product" : normalized;
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
