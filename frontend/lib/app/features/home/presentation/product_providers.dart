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
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// ------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'product_api.dart';
import 'product_model.dart';

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

/// Fetch single product by id (detail page).
final productByIdProvider =
    FutureProvider.family<Product, String>((ref, id) async {
      AppDebug.log("PROVIDERS", "productByIdProvider fetch start", extra: {"id": id});
      final api = ref.read(productApiProvider);
      return api.fetchProductById(id);
    });
