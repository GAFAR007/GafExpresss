library;

import 'package:frontend/app/features/home/presentation/home_filter_sheet.dart';
import 'package:frontend/app/features/home/presentation/product_api.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';

class ProductRepository {
  final ProductApi _api;

  List<Product>? _catalogCache;

  ProductRepository({required ProductApi api}) : _api = api;

  Future<List<Product>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _catalogCache != null) {
      return _catalogCache!;
    }

    final remoteProducts = await _api.fetchProducts(limit: 100);
    remoteProducts.sort((left, right) {
      final priorityCompare = _priorityFor(right).compareTo(_priorityFor(left));
      if (priorityCompare != 0) {
        return priorityCompare;
      }

      final updatedLeft =
          left.updatedAt ??
          left.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final updatedRight =
          right.updatedAt ??
          right.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return updatedRight.compareTo(updatedLeft);
    });
    _catalogCache = remoteProducts;
    return remoteProducts;
  }

  Future<List<Product>> fetchProducts({
    int page = 1,
    int limit = 120,
    String? searchQuery,
    String? sort,
    bool inStockOnly = false,
    String? category,
  }) async {
    final catalog = await fetchCatalog();
    final filtered = _applyQuery(
      catalog,
      searchQuery: searchQuery,
      sort: sort,
      inStockOnly: inStockOnly,
      category: category,
    );

    final safePage = page <= 0 ? 1 : page;
    final safeLimit = limit <= 0 ? filtered.length : limit;
    final start = (safePage - 1) * safeLimit;
    if (start >= filtered.length) {
      return const [];
    }
    return filtered.skip(start).take(safeLimit).toList();
  }

  Future<Product> fetchProductById(String id) async {
    final catalog = await fetchCatalog();
    for (final product in catalog) {
      if (product.id == id) {
        return product;
      }
    }

    return _api.fetchProductById(id);
  }

  Future<PreorderAvailability> fetchPreorderAvailability(String id) async {
    return _api.fetchPreorderAvailability(id);
  }

  List<Product> _applyQuery(
    List<Product> catalog, {
    String? searchQuery,
    String? sort,
    bool inStockOnly = false,
    String? category,
  }) {
    final normalizedSearch = (searchQuery ?? "").trim().toLowerCase();
    final normalizedCategory = (category ?? "").trim().toLowerCase();

    final filtered = catalog.where((product) {
      if (inStockOnly && product.stock <= 0) {
        return false;
      }

      if (normalizedCategory.isNotEmpty) {
        final categoryMatch =
            product.category.toLowerCase() == normalizedCategory ||
            product.subcategory.toLowerCase() == normalizedCategory;
        if (!categoryMatch) {
          return false;
        }
      }

      if (normalizedSearch.isEmpty) {
        return true;
      }

      final haystack = [
        product.name,
        product.description,
        product.category,
        product.subcategory,
        product.brand,
        ...product.badges,
      ].join(" ").toLowerCase();

      return haystack.contains(normalizedSearch);
    }).toList();

    filtered.sort((left, right) => _compareProducts(left, right, sort));
    return filtered;
  }

  int _compareProducts(Product left, Product right, String? sort) {
    switch (_sortFromQuery(sort)) {
      case ProductSort.newest:
        final leftDate =
            left.updatedAt ??
            left.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.updatedAt ??
            right.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      case ProductSort.priceLowHigh:
        return left.priceCents.compareTo(right.priceCents);
      case ProductSort.priceHighLow:
        return right.priceCents.compareTo(left.priceCents);
      case ProductSort.nameAZ:
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      case ProductSort.nameZA:
        return right.name.toLowerCase().compareTo(left.name.toLowerCase());
      case ProductSort.none:
        final priorityCompare = _priorityFor(
          right,
        ).compareTo(_priorityFor(left));
        if (priorityCompare != 0) {
          return priorityCompare;
        }
        return right.reviewCount.compareTo(left.reviewCount);
    }
  }

  ProductSort _sortFromQuery(String? sort) {
    switch ((sort ?? "").trim()) {
      case "createdAt:desc":
        return ProductSort.newest;
      case "price:asc":
        return ProductSort.priceLowHigh;
      case "price:desc":
        return ProductSort.priceHighLow;
      case "name:asc":
        return ProductSort.nameAZ;
      case "name:desc":
        return ProductSort.nameZA;
      default:
        return ProductSort.none;
    }
  }

  int _priorityFor(Product product) {
    var score = 0;
    if (product.isPurchasable) score += 12;
    if (product.preorderEnabled) score += 4;
    if (product.hasDiscount) score += 2;
    if (product.stock > 0) {
      score += 4;
    }
    score += product.rating.round();
    return score;
  }
}
