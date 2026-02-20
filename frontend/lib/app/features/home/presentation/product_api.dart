/// lib/app/features/home/presentation/product_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - ProductApi fetches public product listings from backend.
///
/// WHY:
/// - Keeps networking logic out of UI widgets.
/// - Central place for /products contract parsing.
///
/// HOW:
/// - Calls GET /products and maps response to Product models.
///
/// DEBUGGING:
/// - Logs request start/end and count (safe only).
/// ------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'product_model.dart';

class ProductApi {
  final Dio _dio;

  ProductApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    if (token == null || token.isEmpty) {
      AppDebug.log("PRODUCT_API", "Missing auth token");
      throw Exception("Missing auth token");
    }
    return Options(headers: {"Authorization": "Bearer $token"});
  }

  Future<List<Product>> fetchProducts({
    int page = 1,
    int limit = 10,
    String? searchQuery,
    String? sort,
    bool? inStockOnly,
  }) async {
    final trimmedQuery = searchQuery?.trim();
    final trimmedSort = sort?.trim();

    AppDebug.log(
      "PRODUCT_API",
      "fetchProducts() start",
      extra: {
        "page": page,
        "limit": limit,
        "q": trimmedQuery,
        "sort": trimmedSort,
        "inStockOnly": inStockOnly,
      },
    );

    // WHY: Only send params that the backend understands.
    final queryParameters = <String, dynamic>{"page": page, "limit": limit};
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      queryParameters["q"] = trimmedQuery;
    }
    if (trimmedSort != null && trimmedSort.isNotEmpty) {
      queryParameters["sort"] = trimmedSort;
    }
    if (inStockOnly == true) {
      queryParameters["inStock"] = true;
    }

    final resp = await _dio.get("/products", queryParameters: queryParameters);

    final data = resp.data as Map<String, dynamic>;
    final rawList = (data["products"] ?? []) as List<dynamic>;

    final products = rawList
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();

    AppDebug.log(
      "PRODUCT_API",
      "fetchProducts() success",
      extra: {"count": products.length},
    );

    return products;
  }

  /// ------------------------------------------------------
  /// FETCH PRODUCT BY ID
  /// ------------------------------------------------------
  /// WHY:
  /// - Product detail page needs full data for a single item.
  Future<Product> fetchProductById(String id) async {
    AppDebug.log("PRODUCT_API", "fetchProductById() start", extra: {"id": id});

    final resp = await _dio.get("/products/$id");
    final data = resp.data as Map<String, dynamic>;
    final productMap = data["product"] as Map<String, dynamic>;

    final product = Product.fromJson(productMap);

    AppDebug.log(
      "PRODUCT_API",
      "fetchProductById() success",
      extra: {"id": product.id},
    );

    return product;
  }

  /// ------------------------------------------------------
  /// FETCH PREORDER AVAILABILITY
  /// ------------------------------------------------------
  Future<PreorderAvailability> fetchPreorderAvailability(
    String productId,
  ) async {
    AppDebug.log(
      "PRODUCT_API",
      "fetchPreorderAvailability() start",
      extra: {"id": productId},
    );

    final resp = await _dio.get("/products/$productId/preorder-availability");
    final data = resp.data as Map<String, dynamic>;
    final availabilityMap =
        (data["availability"] ?? {}) as Map<String, dynamic>;
    final availability = PreorderAvailability.fromJson(availabilityMap);

    AppDebug.log(
      "PRODUCT_API",
      "fetchPreorderAvailability() success",
      extra: {
        "id": productId,
        "enabled": availability.preorderEnabled,
        "remaining": availability.preorderRemainingQuantity,
        "effectiveCap": availability.effectiveCap,
      },
    );

    return availability;
  }

  /// ------------------------------------------------------
  /// RESERVE PREORDER QUANTITY
  /// ------------------------------------------------------
  Future<PreorderReserveResult> reservePreorder({
    required String? token,
    required String planId,
    required int quantity,
  }) async {
    AppDebug.log(
      "PRODUCT_API",
      "reservePreorder() start",
      extra: {"planId": planId, "quantity": quantity},
    );

    final resp = await _dio.post(
      "/business/production/plans/$planId/preorder/reserve",
      data: {"quantity": quantity},
      options: _authOptions(token),
    );
    final data = resp.data as Map<String, dynamic>;
    final result = PreorderReserveResult.fromJson(data);

    AppDebug.log(
      "PRODUCT_API",
      "reservePreorder() success",
      extra: {
        "planId": planId,
        "reservationId": result.reservationId,
        "remaining": result.remaining,
        "effectiveCap": result.effectiveCap,
      },
    );

    return result;
  }

  /// ------------------------------------------------------
  /// RELEASE PREORDER RESERVATION
  /// ------------------------------------------------------
  Future<PreorderReleaseResult> releasePreorderReservation({
    required String? token,
    required String reservationId,
  }) async {
    AppDebug.log(
      "PRODUCT_API",
      "releasePreorderReservation() start",
      extra: {"reservationId": reservationId},
    );

    final resp = await _dio.post(
      "/business/preorder/reservations/$reservationId/release",
      options: _authOptions(token),
    );
    final data = resp.data as Map<String, dynamic>;
    final result = PreorderReleaseResult.fromJson(data);

    AppDebug.log(
      "PRODUCT_API",
      "releasePreorderReservation() success",
      extra: {
        "reservationId": result.reservationId,
        "status": result.status,
        "idempotent": result.idempotent,
        "remaining": result.remaining,
      },
    );

    return result;
  }
}
