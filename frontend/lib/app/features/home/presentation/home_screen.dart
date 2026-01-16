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
/// - Fetches products via productsProvider.
/// - Composes Home section widgets for layout clarity.
///
/// DEBUGGING:
/// - Logs build, navigation taps, and product list errors.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _query = "";
  bool _inStockOnly = false;
  ProductSort _sort = ProductSort.none;

  bool get _hasActiveFilters {
    // WHY: Keep filter state checks consistent across the screen.
    return _inStockOnly || _sort != ProductSort.none;
  }

  void _updateQuery(String value) {
    // WHY: Normalize whitespace so filtering is predictable.
    final next = value.trim();
    AppDebug.log("HOME", "Search query updated", extra: {"q": next});
    setState(() => _query = next);
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
          initial: HomeFilterOptions(
            inStockOnly: _inStockOnly,
            sort: _sort,
          ),
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
      extra: {
        "inStockOnly": result.inStockOnly,
        "sort": result.sort.name,
      },
    );
    setState(() {
      _inStockOnly = result.inStockOnly;
      _sort = result.sort;
    });
  }

  List<Product> _applySearch(List<Product> products) {
    // WHY: Keep search logic isolated for easy reuse with filters.
    if (_query.isEmpty) return products;

    final needle = _query.toLowerCase();

    return products.where((product) {
      final name = product.name.toLowerCase();
      final desc = product.description.toLowerCase();
      return name.contains(needle) || desc.contains(needle);
    }).toList();
  }

  List<Product> _applyFilters(List<Product> products) {
    // WHY: Filter in a dedicated step so search and sorting stay readable.
    var working = products;

    if (_inStockOnly) {
      // WHY: Stock filter should hide unavailable items.
      working = working.where((product) => product.stock > 0).toList();
    }

    if (_sort == ProductSort.none) return working;

    // WHY: Sort a copy to avoid mutating the source list from providers.
    final sorted = List<Product>.from(working);

    // WHY: Map nullable dates to a fallback for consistent ordering.
    DateTime _safeDate(DateTime? value) =>
        value ?? DateTime.fromMillisecondsSinceEpoch(0);

    switch (_sort) {
      case ProductSort.priceLowHigh:
        sorted.sort((a, b) => a.priceCents.compareTo(b.priceCents));
        break;
      case ProductSort.priceHighLow:
        sorted.sort((a, b) => b.priceCents.compareTo(a.priceCents));
        break;
      case ProductSort.newest:
        sorted.sort(
          (a, b) => _safeDate(b.createdAt).compareTo(_safeDate(a.createdAt)),
        );
        break;
      case ProductSort.nameAZ:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case ProductSort.nameZA:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case ProductSort.none:
        break;
    }
    return sorted;
  }

  List<Product> _buildFilteredProducts(List<Product> products) {
    // WHY: Apply search first, then filters/sort for predictable results.
    final searched = _applySearch(products);
    final filtered = _applyFilters(searched);

    if (_query.isNotEmpty || _hasActiveFilters) {
      AppDebug.log(
        "HOME",
        "Filter summary",
        extra: {
          "query": _query,
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

    final productsAsync = ref.watch(productsProvider);
    final isAdminAsync = ref.watch(isAdminProvider);
    final cart = ref.watch(cartProvider);
    final cartBadgeCount = cart.hasUnseenChanges ? cart.totalItems : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F7),
      bottomNavigationBar: HomeBottomNav(
        currentIndex: 0,
        cartBadgeCount: cartBadgeCount,
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
            AppDebug.log("HOME", "Nav -> Settings");
            context.go('/settings');
          }
        },
      ),
      body: SafeArea(
        child: productsAsync.when(
          data: (products) {
            if (products.isEmpty) {
              // WHY: Avoid rendering empty sections when no products exist.
              return const Center(child: Text("No products yet"));
            }

            final filteredProducts = _buildFilteredProducts(products);
            final hasQuery = _query.isNotEmpty;
            final hasFilters = _hasActiveFilters;
            final showResults = hasQuery || hasFilters;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WHY: Green header block mirrors the reference layout.
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
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
                              const SnackBar(
                                content: Text("No new notifications yet"),
                              ),
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
                          onSearchChanged: _updateQuery,
                          onSearchSubmitted: (query) {
                            AppDebug.log(
                              "HOME",
                              "Search submitted",
                              extra: {"q": query},
                            );
                            _updateQuery(query);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showResults && filteredProducts.isEmpty) ...[
                          // WHY: Message changes depending on query vs. filters.
                          Text(
                            hasQuery
                                ? "No results for \"$_query\""
                                : "No items match your filters",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (showResults && filteredProducts.isNotEmpty) ...[
                          HomeSearchResultsSection(
                            title:
                                hasQuery ? "Search results" : "Filtered results",
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
                                AppDebug.log(
                                  "HOME",
                                  "Categories hidden (not admin)",
                                );
                                return const SizedBox.shrink();
                              }

                              return Column(
                                children: [
                                  HomeCategoriesSection(
                                    onSeeAllTap: () {
                                      AppDebug.log(
                                        "HOME",
                                        "Categories see all tapped",
                                      );
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
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            AppDebug.log(
              "HOME",
              "Products load failed",
              extra: {"error": error.toString()},
            );
            return const Center(child: Text("Failed to load products"));
          },
        ),
      ),
    );
  }
}
