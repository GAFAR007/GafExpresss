/// lib/app/features/home/presentation/business_product_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for business product management.
///
/// WHY:
/// - Keeps API wiring out of widgets.
/// - Shares a single cacheable list provider for business products.
///
/// HOW:
/// - businessProductApiProvider builds BusinessProductApi from shared Dio.
/// - businessProductsProvider fetches products with auth token + query.
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// ------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'business_analytics_models.dart';
import 'business_product_api.dart';
import 'product_model.dart';

/// ------------------------------------------------------------
/// QUERY MODEL
/// ------------------------------------------------------------
/// WHY:
/// - Provides a stable key for caching per-filter results.
class BusinessProductsQuery {
  final String? search;
  final String? sort;
  final int page;
  final int limit;
  final bool? isActive;

  const BusinessProductsQuery({
    this.search,
    this.sort,
    this.page = 1,
    this.limit = 10,
    this.isActive,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessProductsQuery &&
          runtimeType == other.runtimeType &&
          search == other.search &&
          sort == other.sort &&
          page == other.page &&
          limit == other.limit &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(search, sort, page, limit, isActive);
}

final businessProductApiProvider = Provider<BusinessProductApi>((ref) {
  AppDebug.log("PROVIDERS", "businessProductApiProvider created");
  final dio = ref.read(dioProvider);
  return BusinessProductApi(dio: dio);
});

final businessProductsProvider =
    FutureProvider.family<List<Product>, BusinessProductsQuery>(
        (ref, query) async {
  AppDebug.log(
    "PROVIDERS",
    "businessProductsProvider fetch start",
    extra: {
      "q": query.search,
      "sort": query.sort,
      "page": query.page,
      "limit": query.limit,
      "isActive": query.isActive,
    },
  );

  // WHY: Business endpoints require auth; block if session is missing.
  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "businessProductsProvider missing session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessProductApiProvider);
  return api.fetchProducts(
    token: session.token,
    page: query.page,
    limit: query.limit,
    searchQuery: query.search,
    sort: query.sort,
    isActive: query.isActive,
  );
});

final businessAnalyticsSummaryProvider =
    FutureProvider<BusinessAnalyticsSummary>((ref) async {
  AppDebug.log("PROVIDERS", "businessAnalyticsSummaryProvider fetch start");

  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "businessAnalyticsSummaryProvider missing session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessProductApiProvider);
  return api.fetchAnalyticsSummary(token: session.token);
});

final businessProductByIdProvider =
    FutureProvider.family<Product, String>((ref, id) async {
  AppDebug.log(
    "PROVIDERS",
    "businessProductByIdProvider fetch start",
    extra: {"id": id},
  );

  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "businessProductByIdProvider missing session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessProductApiProvider);
  return api.fetchProductById(token: session.token, id: id);
});
