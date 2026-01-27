/// lib/app/features/home/presentation/product_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for product fetching.
///
/// WHY:
/// - Keeps API wiring in one place.
/// - UI simply watches a FutureProvider.
///
/// HOW:
/// - productApiProvider builds ProductApi using shared Dio.
/// - productsProvider fetches /products list.
/// - productsSearchProvider fetches /products with search param.
/// - productsQueryProvider fetches /products with search + sort params.
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// ------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'product_api.dart';
import 'product_model.dart';

/// ------------------------------------------------------------
/// QUERY MODEL
/// ------------------------------------------------------------
/// WHY:
/// - Encapsulates search/sort inputs for the products list.
/// - Gives Riverpod a stable key for caching per-query results.
class ProductsQuery {
  final String? search;
  final String? sort;
  final int page;
  final int limit;
  final bool inStockOnly;

  const ProductsQuery({
    this.search,
    this.sort,
    this.page = 1,
    this.limit = 10,
    this.inStockOnly = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductsQuery &&
          runtimeType == other.runtimeType &&
          search == other.search &&
          sort == other.sort &&
          page == other.page &&
          limit == other.limit &&
          inStockOnly == other.inStockOnly;

  @override
  int get hashCode => Object.hash(search, sort, page, limit, inStockOnly);

  @override
  String toString() {
    return "ProductsQuery(search: $search, sort: $sort, page: $page, limit: $limit, inStockOnly: $inStockOnly)";
  }
}

final productApiProvider = Provider<ProductApi>((ref) {
  AppDebug.log("PROVIDERS", "productApiProvider created");
  final dio = ref.read(dioProvider);
  return ProductApi(dio: dio);
});

final productsProvider = FutureProvider<List<Product>>((ref) async {
  AppDebug.log("PROVIDERS", "productsProvider fetch start");
  final api = ref.read(productApiProvider);
  return api.fetchProducts();
});

/// Fetch products with a search query.
final productsSearchProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
      // WHY: Normalize query so backend receives clean input.
      final trimmed = query.trim();
      AppDebug.log(
        "PROVIDERS",
        "productsSearchProvider fetch start",
        extra: {"q": trimmed},
      );
      final api = ref.read(productApiProvider);
      return api.fetchProducts(searchQuery: trimmed);
    });

/// Fetch products with search + sort.
final productsQueryProvider =
    FutureProvider.family<List<Product>, ProductsQuery>((ref, query) async {
  AppDebug.log(
    "PROVIDERS",
    "productsQueryProvider fetch start",
    extra: {
      "q": query.search,
      "sort": query.sort,
      "page": query.page,
      "limit": query.limit,
      "inStockOnly": query.inStockOnly,
    },
  );
  final api = ref.read(productApiProvider);
  return api.fetchProducts(
    page: query.page,
    limit: query.limit,
    searchQuery: query.search,
    sort: query.sort,
    inStockOnly: query.inStockOnly,
  );
});

/// Fetch single product by id (detail page).
final productByIdProvider =
    FutureProvider.family<Product, String>((ref, id) async {
      AppDebug.log("PROVIDERS", "productByIdProvider fetch start", extra: {"id": id});
      final api = ref.read(productApiProvider);
      return api.fetchProductById(id);
    });
