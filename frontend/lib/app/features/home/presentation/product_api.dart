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

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'product_model.dart';

class ProductApi {
  final Dio _dio;

  ProductApi({required Dio dio}) : _dio = dio;

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
    final queryParameters = <String, dynamic>{
      "page": page,
      "limit": limit,
    };
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      queryParameters["q"] = trimmedQuery;
    }
    if (trimmedSort != null && trimmedSort.isNotEmpty) {
      queryParameters["sort"] = trimmedSort;
    }
    if (inStockOnly == true) {
      queryParameters["inStock"] = true;
    }

    final resp = await _dio.get(
      "/products",
      queryParameters: queryParameters,
    );

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
}
