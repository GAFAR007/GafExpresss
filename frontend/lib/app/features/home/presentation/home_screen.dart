// ignore: dangling_library_doc_comments
/// lib/features/home/presentation/home_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Home screen (post-login landing).
///
/// WHY:
/// - Matches the upgraded layout while keeping core flows intact.
/// - Surfaces promos, categories, and popular items for quick discovery.
///
/// HOW:
/// - Fetches products via productsProvider / productsQueryProvider.
/// - Composes Home section widgets for layout clarity.
///
/// DEBUGGING:
/// - Logs build, navigation taps, and product list errors.
/// ------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/home_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/home_categories_section.dart';
import 'package:frontend/app/features/home/presentation/home_filter_sheet.dart';
import 'package:frontend/app/features/home/presentation/home_header_section.dart';
import 'package:frontend/app/features/home/presentation/home_popular_section.dart';
import 'package:frontend/app/features/home/presentation/home_promo_section.dart';
import 'package:frontend/app/features/home/presentation/home_search_section.dart';
import 'package:frontend/app/features/home/presentation/home_search_results_section.dart';
import 'package:frontend/app/features/home/presentation/cart_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';

const String _homeLogTag = "HOME";
const String _homeRefreshLog = "pull_to_refresh";
const String _homeRefreshSource = "home_pull";

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _pendingQuery = "";
  String _activeQuery = "";
  bool _inStockOnly = false;
  ProductSort _sort = ProductSort.none;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // WHY: Controller keeps search text stable across async rebuilds.
    _searchController = TextEditingController(text: _pendingQuery);
  }

  @override
  void dispose() {
    // WHY: Dispose controller to avoid leaks in long sessions.
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters {
    // WHY: Keep filter state checks consistent across the screen.
    return _inStockOnly || _sort != ProductSort.none;
  }

  String? _mapSortToQuery(ProductSort sort) {
    // WHY: Backend expects sort in the form field:direction.
    switch (sort) {
      case ProductSort.priceLowHigh:
        return "price:asc";
      case ProductSort.priceHighLow:
        return "price:desc";
      case ProductSort.newest:
        return "createdAt:desc";
      case ProductSort.nameAZ:
        return "name:asc";
      case ProductSort.nameZA:
        return "name:desc";
      case ProductSort.none:
        return null;
    }
  }

  void _updateQuery(String value) {
    // WHY: Track raw input and debounce backend requests.
    AppDebug.log("HOME", "Search input changed", extra: {"raw": value});
    setState(() => _pendingQuery = value);

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final trimmed = _pendingQuery.trim();
      AppDebug.log("HOME", "Search debounce fired", extra: {"q": trimmed});
      setState(() => _activeQuery = trimmed);
    });
  }

  Future<void> _openFilterSheet() async {
    // WHY: Bottom sheet keeps user in context without a new route.
    AppDebug.log("HOME", "Open filter sheet");
    final result = await showModalBottomSheet<HomeFilterOptions>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        // WHY: Pass current selections so users can tweak filters.
        return HomeFilterSheet(
          initial: HomeFilterOptions(inStockOnly: _inStockOnly, sort: _sort),
        );
      },
    );

    if (!mounted) {
      // WHY: Avoid setState if the screen unmounted while sheet was open.
      AppDebug.log("HOME", "Filter sheet closed after dispose");
      return;
    }

    if (result == null) {
      // WHY: Distinguish dismiss vs. apply for debug clarity.
      AppDebug.log("HOME", "Filter sheet dismissed");
      return;
    }

    AppDebug.log(
      "HOME",
      "Filters applied",
      extra: {"inStockOnly": result.inStockOnly, "sort": result.sort.name},
    );
    setState(() {
      _inStockOnly = result.inStockOnly;
      _sort = result.sort;
    });
  }

  Future<void> _handleRefresh() async {
    // WHY: Central refresh keeps Home aligned with other sections.
    AppDebug.log(_homeLogTag, _homeRefreshLog);
    await AppRefresh.refreshApp(ref: ref, source: _homeRefreshSource);
  }

  List<Product> _applyFilters(List<Product> products) {
    // WHY: Backend handles search + sort + stock filtering now.
    return products;
  }

  List<Product> _buildFilteredProducts(List<Product> products) {
    // WHY: Backend handles search; only apply local filters/sort.
    final filtered = _applyFilters(products);

    if (_activeQuery.isNotEmpty || _hasActiveFilters) {
      AppDebug.log(
        "HOME",
        "Filter summary",
        extra: {
          "query": _activeQuery,
          "inStockOnly": _inStockOnly,
          "sort": _sort.name,
          "before": products.length,
          "after": filtered.length,
        },
      );
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME", "build()");

    // WHY: Use backend search/sort when filters are active.
    final pendingQuery = _pendingQuery.trim();
    final activeQuery = _activeQuery.trim();
    final hasRemoteQuery =
        activeQuery.isNotEmpty || _sort != ProductSort.none || _inStockOnly;
    final productsQuery = ProductsQuery(
      search: activeQuery.isEmpty ? null : activeQuery,
      sort: _mapSortToQuery(_sort),
      inStockOnly: _inStockOnly,
    );
    final productsAsync = hasRemoteQuery
        ? ref.watch(productsQueryProvider(productsQuery))
        : ref.watch(productsProvider);
    final isAdminAsync = ref.watch(isAdminProvider);
    final cart = ref.watch(cartProvider);
    final cartBadgeCount = cart.hasUnseenChanges ? cart.totalItems : 0;
    final hasFilters = _hasActiveFilters;
    final isTyping = pendingQuery.isNotEmpty && pendingQuery != activeQuery;

    final colorScheme = Theme.of(context).colorScheme;
    final header = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          HomeHeaderSection(
            locationLabel: "Current location",
            notificationCount: cartBadgeCount,
            onNotificationTap: () {
              AppDebug.log("HOME", "Notifications tapped");
              // WHY: Cart notifications should take user to cart.
              if (cartBadgeCount > 0) {
                context.go('/cart');
                return;
              }

              // WHY: Use snackbar to confirm the tap without extra screens.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("No new notifications yet")),
              );
            },
          ),
          const SizedBox(height: 16),
          HomeSearchSection(
            onFilterTap: () {
              // WHY: Launch filter sheet in-place.
              _openFilterSheet();
            },
            hasActiveFilters: hasFilters,
            controller: _searchController,
            onSearchChanged: _updateQuery,
            onSearchSubmitted: (query) {
              AppDebug.log("HOME", "Search submitted", extra: {"q": query});
              _updateQuery(query);
            },
          ),
        ],
      ),
    );

    final session = ref.watch(authSessionProvider);
    final isTenant = session?.user.role == 'tenant';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      bottomNavigationBar: HomeBottomNav(
        currentIndex: 0,
        cartBadgeCount: cartBadgeCount,
        showTenantTab: isTenant,
        onTap: (index) {
          // WHY: Keep navigation centralized in one handler.
          if (index == 0) {
            AppDebug.log("HOME", "Nav -> Home");
            context.go('/home');
            return;
          }
          if (index == 1) {
            AppDebug.log("HOME", "Nav -> Cart");
            context.go('/cart');
            return;
          }
          if (index == 2) {
            AppDebug.log("HOME", "Nav -> Orders");
            context.go('/orders');
            return;
          }
          if (index == 3) {
            AppDebug.log("HOME", "Nav -> Chat");
            context.go('/chat');
            return;
          }
          if (isTenant && index == 4) {
            AppDebug.log("HOME", "Nav -> Tenant");
            context.go('/tenant-verification');
            return;
          }
          if (index == (isTenant ? 5 : 4)) {
            AppDebug.log("HOME", "Nav -> Settings");
            context.go('/settings');
          }
        },
      ),
      body: SafeArea(
        // WHY: Refresh indicator lets Home trigger the central app refresh.
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: productsAsync.when(
            data: (products) {
              return _buildHomeBody(
                header: header,
                products: products,
                pendingQuery: pendingQuery,
                activeQuery: activeQuery,
                isTyping: isTyping,
                hasFilters: hasFilters,
                isAdminAsync: isAdminAsync,
              );
            },
            loading: () {
              // WHY: Keep header visible while fetching new search results.
              return SingleChildScrollView(
                // WHY: Allow pull-to-refresh even when content is short.
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
            error: (error, _) {
              AppDebug.log(
                "HOME",
                "Products load failed",
                extra: {"error": error.toString()},
              );
              return SingleChildScrollView(
                // WHY: Allow pull-to-refresh even when content is short.
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 24),
                    const Center(child: Text("Failed to load products")),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHomeBody({
    required Widget header,
    required List<Product> products,
    required String pendingQuery,
    required String activeQuery,
    required bool isTyping,
    required bool hasFilters,
    required AsyncValue<bool> isAdminAsync,
  }) {
    final filteredProducts = _buildFilteredProducts(products);
    final hasQuery = pendingQuery.isNotEmpty;
    final showResults = hasQuery || hasFilters;

    if (products.isEmpty && !showResults) {
      // WHY: Avoid rendering empty sections when no products exist.
      return const Center(child: Text("No products yet"));
    }

    return SingleChildScrollView(
      // WHY: Allow pull-to-refresh even when content is short.
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showResults && filteredProducts.isEmpty) ...[
                  // WHY: Message changes depending on query vs. filters.
                  Text(
                    hasQuery
                        ? (isTyping
                              ? "Searching..."
                              : "No results for \"$pendingQuery\"")
                        : "No items match your filters",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                if (showResults && filteredProducts.isNotEmpty) ...[
                  HomeSearchResultsSection(
                    title: hasQuery ? "Search results" : "Filtered results",
                    results: filteredProducts,
                    onProductTap: (product) {
                      AppDebug.log(
                        "HOME",
                        "Search product tapped",
                        extra: {"id": product.id},
                      );
                      context.go('/product/${product.id}');
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (!showResults) ...[
                  HomePromoSection(
                    products: products,
                    onSeeAllTap: () {
                      AppDebug.log("HOME", "Promo see all tapped");
                    },
                    onPromoTap: (product) {
                      AppDebug.log(
                        "HOME",
                        "Promo product tapped",
                        extra: {"id": product.id},
                      );
                      context.go('/product/${product.id}');
                    },
                  ),
                  const SizedBox(height: 20),
                  // WHY: Categories are admin-only; verify via backend.
                  isAdminAsync.when(
                    data: (isAdmin) {
                      if (!isAdmin) {
                        AppDebug.log("HOME", "Categories hidden (not admin)");
                        return const SizedBox.shrink();
                      }

                      return Column(
                        children: [
                          HomeCategoriesSection(
                            onSeeAllTap: () {
                              AppDebug.log("HOME", "Categories see all tapped");
                            },
                            onCategoryTap: (label) {
                              AppDebug.log(
                                "HOME",
                                "Category selected",
                                extra: {"label": label},
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      );
                    },
                    loading: () {
                      // WHY: Hide until admin check completes.
                      return const SizedBox.shrink();
                    },
                    error: (error, _) {
                      AppDebug.log(
                        "HOME",
                        "Admin check failed",
                        extra: {"error": error.toString()},
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                  HomePopularSection(
                    products: products,
                    onSeeAllTap: () {
                      AppDebug.log("HOME", "Popular see all tapped");
                    },
                    onProductTap: (product) {
                      AppDebug.log(
                        "HOME",
                        "Popular product tapped",
                        extra: {"id": product.id},
                      );
                      context.go('/product/${product.id}');
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
