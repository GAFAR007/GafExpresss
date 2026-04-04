library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_api.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_repository.dart';

class ProductsQuery {
  final String? search;
  final String? sort;
  final int page;
  final int limit;
  final bool inStockOnly;
  final String? category;

  const ProductsQuery({
    this.search,
    this.sort,
    this.page = 1,
    this.limit = 120,
    this.inStockOnly = false,
    this.category,
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
          inStockOnly == other.inStockOnly &&
          category == other.category;

  @override
  int get hashCode =>
      Object.hash(search, sort, page, limit, inStockOnly, category);
}

final productApiProvider = Provider<ProductApi>((ref) {
  AppDebug.log("PROVIDERS", "productApiProvider created");
  final dio = ref.read(dioProvider);
  return ProductApi(dio: dio);
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  AppDebug.log("PROVIDERS", "productRepositoryProvider created");
  final api = ref.read(productApiProvider);
  return ProductRepository(api: api);
});

final productsProvider = FutureProvider<List<Product>>((ref) async {
  AppDebug.log("PROVIDERS", "productsProvider fetch start");
  final repository = ref.read(productRepositoryProvider);
  return repository.fetchProducts(limit: 120);
});

final productsSearchProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) async {
  final trimmed = query.trim();
  AppDebug.log(
    "PROVIDERS",
    "productsSearchProvider fetch start",
    extra: {"q": trimmed},
  );
  final repository = ref.read(productRepositoryProvider);
  return repository.fetchProducts(searchQuery: trimmed, limit: 120);
});

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
          "category": query.category,
        },
      );
      final repository = ref.read(productRepositoryProvider);
      return repository.fetchProducts(
        page: query.page,
        limit: query.limit,
        searchQuery: query.search,
        sort: query.sort,
        inStockOnly: query.inStockOnly,
        category: query.category,
      );
    });

final productByIdProvider = FutureProvider.family<Product, String>((
  ref,
  id,
) async {
  AppDebug.log(
    "PROVIDERS",
    "productByIdProvider fetch start",
    extra: {"id": id},
  );
  final repository = ref.read(productRepositoryProvider);
  return repository.fetchProductById(id);
});

final productPreorderAvailabilityProvider =
    FutureProvider.family<PreorderAvailability, String>((ref, id) async {
      AppDebug.log(
        "PROVIDERS",
        "productPreorderAvailabilityProvider fetch start",
        extra: {"id": id},
      );
      final repository = ref.read(productRepositoryProvider);
      return repository.fetchPreorderAvailability(id);
    });
