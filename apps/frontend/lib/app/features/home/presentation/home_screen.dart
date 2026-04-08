/// lib/app/features/home/presentation/home_screen.dart
/// --------------------------------------------------
/// WHAT:
/// - Renders the storefront home screen with hero, search, category shortcuts,
///   product sections, and cart interactions.
///
/// WHY:
/// - Centralizes storefront discovery state so shoppers can filter by category,
///   subcategory, stock, search query, and sort order in one place.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/cart_providers.dart';
import 'package:frontend/app/features/home/presentation/home_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/home_categories_section.dart';
import 'package:frontend/app/features/home/presentation/home_filter_sheet.dart';
import 'package:frontend/app/features/home/presentation/home_hero_section.dart';
import 'package:frontend/app/features/home/presentation/home_product_section.dart';
import 'package:frontend/app/features/home/presentation/home_promo_section.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/features/home/presentation/home_search_results_section.dart';
import 'package:frontend/app/features/home/presentation/home_search_section.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _featuredKey = GlobalKey();
  final GlobalKey _categoriesKey = GlobalKey();

  String _pendingQuery = "";
  String _activeQuery = "";
  String? _selectedCategory;
  String? _selectedSubcategory;
  bool _inStockOnly = false;
  ProductSort _sort = ProductSort.none;
  Set<String> _favoriteIds = <String>{};
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _inStockOnly ||
      _sort != ProductSort.none ||
      _selectedCategory != null ||
      _selectedSubcategory != null;

  Future<void> _handleRefresh() {
    return AppRefresh.refreshApp(ref: ref, source: "customer_home_pull");
  }

  void _updateQuery(String value) {
    setState(() => _pendingQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() => _activeQuery = value.trim());
    });
  }

  void _toggleCategory(String label) {
    if (label.trim().isEmpty) {
      setState(() {
        _selectedCategory = null;
        _selectedSubcategory = null;
      });
      return;
    }

    setState(() {
      final isSameCategory =
          (_selectedCategory ?? "").toLowerCase() == label.toLowerCase();
      _selectedCategory = isSameCategory ? null : label;
      _selectedSubcategory = null;
    });
  }

  void _toggleSubcategory(StorefrontCategorySummary summary) {
    setState(() {
      final isSameSubcategory =
          (_selectedSubcategory ?? "").trim().toLowerCase() ==
          summary.label.trim().toLowerCase();
      _selectedSubcategory = isSameSubcategory ? null : summary.label;
      if (!isSameSubcategory &&
          (summary.parentCategory ?? "").trim().isNotEmpty) {
        _selectedCategory = summary.parentCategory!.trim();
      }
    });
  }

  void _toggleFavorite(Product product) {
    setState(() {
      if (_favoriteIds.contains(product.id)) {
        _favoriteIds = {..._favoriteIds}..remove(product.id);
      } else {
        _favoriteIds = {..._favoriteIds, product.id};
      }
    });
  }

  void _clearDiscovery() {
    setState(() {
      _pendingQuery = "";
      _activeQuery = "";
      _selectedCategory = null;
      _selectedSubcategory = null;
      _inStockOnly = false;
      _sort = ProductSort.none;
      _searchController.clear();
    });
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<HomeFilterOptions>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => HomeFilterSheet(
        initial: HomeFilterOptions(inStockOnly: _inStockOnly, sort: _sort),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _inStockOnly = result.inStockOnly;
      _sort = result.sort;
    });
  }

  Future<void> _scrollToKey(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) {
      return;
    }

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  void _handleCardAction(Product product) {
    if (!product.isPurchasable ||
        (product.stock <= 0 && !product.preorderEnabled)) {
      context.go("/product/${product.id}");
      return;
    }

    final session = ref.read(authSessionProvider);
    if (!isBuyerRole(session?.user.role)) {
      AppDebug.log(
        "HOME",
        "Quick add blocked for non-buyer role",
        extra: {"role": session?.user.role ?? "", "productId": product.id},
      );
      context.go("/product/${product.id}");
      return;
    }

    ref.read(cartProvider.notifier).addProduct(product);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("${product.name} added to cart")));
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final session = ref.watch(authSessionProvider);
    final role = session?.user.role;
    final isTenant = role == "tenant";
    final canAccessBuyerFlows = isBuyerRole(role);
    final cartBadgeCount = canAccessBuyerFlows && cart.hasUnseenChanges
        ? cart.totalItems
        : 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: HomeBottomNav(
        currentIndex: 0,
        cartBadgeCount: cartBadgeCount,
        showTenantTab: isTenant,
        showBuyerTabs: canAccessBuyerFlows,
        onTap: (index) {
          if (index == 0) {
            context.go("/home");
            return;
          }
          var nextIndex = 1;
          if (canAccessBuyerFlows && index == nextIndex) {
            context.go("/cart");
            return;
          }
          if (canAccessBuyerFlows) {
            nextIndex += 1;
          }
          if (canAccessBuyerFlows && index == nextIndex) {
            context.go("/orders");
            return;
          }
          if (canAccessBuyerFlows) {
            nextIndex += 1;
          }
          if (index == nextIndex) {
            context.go("/chat");
            return;
          }
          nextIndex += 1;
          if (isTenant && index == nextIndex) {
            context.go("/tenant-verification");
            return;
          }
          context.go("/settings");
        },
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: productsAsync.when(
            data: (products) => _buildLoadedState(
              context: context,
              products: products,
              cartBadgeCount: cartBadgeCount,
              canAccessBuyerFlows: canAccessBuyerFlows,
            ),
            loading: _buildLoadingState,
            error: (error, _) {
              AppDebug.log(
                "HOME",
                "customer_home_load_failed",
                extra: {"error": error.toString()},
              );
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.section,
                    AppSpacing.page,
                    AppSpacing.section,
                  ),
                  child: AppEmptyState(
                    icon: Icons.storefront_outlined,
                    title: "Storefront unavailable",
                    message:
                        "We could not load the latest products right now. Pull to refresh and try again.",
                    action: OutlinedButton(
                      onPressed: _handleRefresh,
                      child: const Text("Refresh"),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadedState({
    required BuildContext context,
    required List<Product> products,
    required int cartBadgeCount,
    required bool canAccessBuyerFlows,
  }) {
    if (products.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.section,
            AppSpacing.page,
            AppSpacing.section,
          ),
          child: AppEmptyState(
            icon: Icons.shopping_bag_outlined,
            title: "No products available yet",
            message:
                "The storefront is ready, but there are no active products in the store right now.",
            action: OutlinedButton(
              onPressed: _handleRefresh,
              child: const Text("Refresh"),
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final categorySummaries = _buildCategorySummaries(
      products: products,
      colorScheme: colorScheme,
    );
    final subcategorySummaries = _buildSubcategorySummaries(
      products: products,
      colorScheme: colorScheme,
      categoryLabel: _selectedCategory,
    );
    final filteredProducts = _applyFilters(products);
    final hasSearchIntent = _activeQuery.isNotEmpty || _hasFilters;

    final featuredProducts = [...products]..sort(_compareFeaturedProducts);
    final newArrivals = [...products]..sort(_sortNewest);
    final popularProducts = [...products]..sort(_scoreByDemand);
    final deals = products.where((product) => product.hasDiscount).toList()
      ..sort(_compareFeaturedProducts);
    final categorySections = [
      for (final summary in categorySummaries.take(4))
        _CategoryProductSection(
          summary: summary,
          products:
              products
                  .where(
                    (product) =>
                        product.category.trim().toLowerCase() ==
                        summary.label.toLowerCase(),
                  )
                  .toList()
                ..sort(_compareFeaturedProducts),
        ),
    ];
    final highlightedCategory = categorySummaries.isNotEmpty
        ? categorySummaries.first.label
        : null;
    final heroMetrics = _buildHeroMetrics(
      products: products,
      categories: categorySummaries,
    );

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeHeroSection(
            catalogLabel: _buildCatalogLabel(categorySummaries),
            headline: "Discover products you'll love",
            subtitle: _buildHeroSubtitle(
              products: products,
              categories: categorySummaries,
            ),
            promoEyebrow: highlightedCategory ?? "Browse our collection",
            promoTitle: _buildHeroPromoTitle(
              highlightedCategory: highlightedCategory,
            ),
            promoBody: _buildPromoSubtitle(categorySummaries),
            primaryLabel: "Shop now",
            secondaryLabel: "Browse categories",
            promoLabel: highlightedCategory == null
                ? "See all categories"
                : "Shop $highlightedCategory",
            cartBadgeCount: cartBadgeCount,
            metrics: heroMetrics,
            onCartTap: canAccessBuyerFlows ? () => context.go("/cart") : null,
            onPrimaryTap: () => _scrollToKey(_featuredKey),
            onSecondaryTap: () => _scrollToKey(_categoriesKey),
            onPromoTap: highlightedCategory == null
                ? () => _scrollToKey(_categoriesKey)
                : () => _toggleCategory(highlightedCategory),
          ),
          AppResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeSearchSection(
                  controller: _searchController,
                  onFilterTap: _openFilterSheet,
                  onSearchChanged: _updateQuery,
                  onSearchSubmitted: _updateQuery,
                  hasActiveFilters: _hasFilters,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: _toggleCategory,
                ),
                if (_pendingQuery.trim().isNotEmpty &&
                    _pendingQuery.trim() != _activeQuery) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Searching products...",
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (hasSearchIntent) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (_activeQuery.isNotEmpty)
                        AppStatusChip(
                          label: 'Search: "$_activeQuery"',
                          tone: AppStatusTone.info,
                          icon: Icons.search_rounded,
                        ),
                      if (_selectedCategory != null)
                        AppStatusChip(
                          label: _selectedCategory!,
                          tone: AppStatusTone.warning,
                          icon: Icons.category_rounded,
                        ),
                      if (_selectedSubcategory != null)
                        AppStatusChip(
                          label: _selectedSubcategory!,
                          tone: AppStatusTone.info,
                          icon: Icons.sell_rounded,
                        ),
                      if (_inStockOnly)
                        const AppStatusChip(
                          label: "In stock only",
                          tone: AppStatusTone.success,
                          icon: Icons.inventory_2_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _clearDiscovery,
                    child: const Text("Clear search and filters"),
                  ),
                ],
                const SizedBox(height: AppSpacing.section),
                KeyedSubtree(
                  key: _categoriesKey,
                  child: HomeCategoriesSection(
                    categories: categorySummaries,
                    subcategories: subcategorySummaries,
                    selectedCategory: _selectedCategory,
                    selectedSubcategory: _selectedSubcategory,
                    onCategoryTap: _toggleCategory,
                    onSubcategoryTap: _toggleSubcategory,
                  ),
                ),
                const SizedBox(height: AppSpacing.section),
                if (hasSearchIntent) ...[
                  if (filteredProducts.isEmpty)
                    AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: "No products matched",
                      message:
                          "Try a different search term, switch category, or reset your filters.",
                      action: OutlinedButton(
                        onPressed: _clearDiscovery,
                        child: const Text("Reset filters"),
                      ),
                    )
                  else
                    HomeSearchResultsSection(
                      title: _activeQuery.isNotEmpty
                          ? 'Results for "$_activeQuery"'
                          : _selectedSubcategory != null
                          ? "${_selectedSubcategory!} products"
                          : _selectedCategory != null
                          ? "${_selectedCategory!} products"
                          : "Filtered products",
                      subtitle:
                          "Browse matching products available in the store right now.",
                      results: filteredProducts,
                      onProductTap: (product) =>
                          context.go("/product/${product.id}"),
                      onPrimaryAction: _handleCardAction,
                      onFavoriteToggle: _toggleFavorite,
                      favoriteIds: _favoriteIds,
                    ),
                ] else ...[
                  KeyedSubtree(
                    key: _featuredKey,
                    child: HomeProductSection(
                      title: "Featured products",
                      subtitle:
                          "Start with standout picks chosen for availability, imagery, and freshness.",
                      products: featuredProducts,
                      featuredCards: true,
                      favoriteIds: _favoriteIds,
                      onProductTap: (product) =>
                          context.go("/product/${product.id}"),
                      onPrimaryAction: _handleCardAction,
                      onFavoriteToggle: _toggleFavorite,
                      onSeeAllTap: () => _scrollToKey(_categoriesKey),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  HomePromoSection(
                    eyebrow: highlightedCategory ?? "Browse our collection",
                    title: "Discover products you'll love",
                    subtitle: _buildPromoSubtitle(categorySummaries),
                    primaryLabel: highlightedCategory == null
                        ? "Browse categories"
                        : "Shop $highlightedCategory",
                    onPrimaryTap: highlightedCategory == null
                        ? () => _scrollToKey(_categoriesKey)
                        : () => _toggleCategory(highlightedCategory),
                    highlights: _buildPromoHighlights(
                      products,
                      categorySummaries,
                    ),
                  ),
                  if (newArrivals.length > 1) ...[
                    const SizedBox(height: AppSpacing.section),
                    HomeProductSection(
                      title: "New arrivals",
                      subtitle:
                          "Recently added products, ordered by the latest arrivals in the store.",
                      products: newArrivals,
                      favoriteIds: _favoriteIds,
                      onProductTap: (product) =>
                          context.go("/product/${product.id}"),
                      onPrimaryAction: _handleCardAction,
                      onFavoriteToggle: _toggleFavorite,
                      onSeeAllTap: () {
                        setState(() => _sort = ProductSort.newest);
                      },
                    ),
                  ],
                  if (popularProducts.length > 1) ...[
                    const SizedBox(height: AppSpacing.section),
                    HomeProductSection(
                      title: "Popular right now",
                      subtitle:
                          "Popular picks based on availability, freshness, and complete product details.",
                      products: popularProducts,
                      favoriteIds: _favoriteIds,
                      onProductTap: (product) =>
                          context.go("/product/${product.id}"),
                      onPrimaryAction: _handleCardAction,
                      onFavoriteToggle: _toggleFavorite,
                    ),
                  ],
                  if (deals.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    HomeProductSection(
                      title: "Deals",
                      subtitle:
                          "Products with discount pricing or comparison pricing available right now.",
                      products: deals,
                      favoriteIds: _favoriteIds,
                      onProductTap: (product) =>
                          context.go("/product/${product.id}"),
                      onPrimaryAction: _handleCardAction,
                      onFavoriteToggle: _toggleFavorite,
                    ),
                  ],
                  for (final section in categorySections) ...[
                    if (section.products.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.section),
                      HomeProductSection(
                        title: section.summary.label,
                        subtitle: section.summary.helper,
                        products: section.products,
                        favoriteIds: _favoriteIds,
                        onProductTap: (product) =>
                            context.go("/product/${product.id}"),
                        onPrimaryAction: _handleCardAction,
                        onFavoriteToggle: _toggleFavorite,
                        onSeeAllTap: () {
                          setState(() {
                            _selectedCategory = section.summary.label;
                            _selectedSubcategory = null;
                          });
                        },
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Product> _applyFilters(List<Product> products) {
    final query = _activeQuery.trim().toLowerCase();
    final selectedCategory = (_selectedCategory ?? "").trim().toLowerCase();
    final selectedSubcategory = (_selectedSubcategory ?? "")
        .trim()
        .toLowerCase();

    final filtered = products.where((product) {
      if (_inStockOnly && product.stock <= 0) {
        return false;
      }

      if (selectedCategory.isNotEmpty &&
          product.category.trim().toLowerCase() != selectedCategory) {
        return false;
      }

      if (selectedSubcategory.isNotEmpty &&
          product.subcategory.trim().toLowerCase() != selectedSubcategory) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = [
        product.name,
        product.description,
        product.longDescription,
        product.category,
        product.subcategory,
        product.brand,
      ].join(" ").toLowerCase();

      return haystack.contains(query);
    }).toList();

    filtered.sort(_compareBySort);
    return filtered;
  }

  int _compareBySort(Product left, Product right) {
    switch (_sort) {
      case ProductSort.newest:
        return _sortNewest(left, right);
      case ProductSort.priceLowHigh:
        return left.priceCents.compareTo(right.priceCents);
      case ProductSort.priceHighLow:
        return right.priceCents.compareTo(left.priceCents);
      case ProductSort.nameAZ:
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      case ProductSort.nameZA:
        return right.name.toLowerCase().compareTo(left.name.toLowerCase());
      case ProductSort.none:
        return _compareFeaturedProducts(left, right);
    }
  }

  int _compareFeaturedProducts(Product left, Product right) {
    final leftScore = _featuredScore(left);
    final rightScore = _featuredScore(right);
    if (leftScore != rightScore) {
      return rightScore.compareTo(leftScore);
    }
    return _sortNewest(left, right);
  }

  int _featuredScore(Product product) {
    var score = 0;
    if (product.primaryImageUrl.trim().isNotEmpty) score += 10;
    if (product.stock > 0) score += 8;
    if (product.preorderEnabled) score += 3;
    if (product.hasDiscount) score += 2;
    score += product.stock.clamp(0, 50);
    final createdAt = product.createdAt;
    if (createdAt != null) {
      final freshness = 30 - DateTime.now().difference(createdAt).inDays;
      score += freshness.clamp(0, 30);
    }
    return score;
  }

  int _sortNewest(Product left, Product right) {
    final leftDate =
        left.updatedAt ??
        left.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate =
        right.updatedAt ??
        right.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return rightDate.compareTo(leftDate);
  }

  int _scoreByDemand(Product left, Product right) {
    final leftScore = _demandScore(left);
    final rightScore = _demandScore(right);
    if (leftScore != rightScore) {
      return rightScore.compareTo(leftScore);
    }
    return _sortNewest(left, right);
  }

  int _demandScore(Product product) {
    var score = 0;
    if (product.stock > 0) score += 6;
    if (product.primaryImageUrl.trim().isNotEmpty) score += 4;
    if (product.preorderEnabled) score += 2;
    score += product.stock.clamp(0, 40);
    final updatedAt =
        product.updatedAt ??
        product.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    score += (30 - DateTime.now().difference(updatedAt).inDays).clamp(0, 30);
    return score;
  }

  List<StorefrontCategorySummary> _buildCategorySummaries({
    required List<Product> products,
    required ColorScheme colorScheme,
  }) {
    final grouped = <String, List<Product>>{};

    for (final product in products) {
      final label = product.category.trim();
      if (label.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(label, () => []).add(product);
    }

    final summaries = <StorefrontCategorySummary>[];
    for (final entry in grouped.entries) {
      final label = entry.key;
      final items = entry.value;
      final helper = _buildCategoryHelper(items);
      summaries.add(
        StorefrontCategorySummary(
          label: label,
          helper: helper,
          itemCount: items.length,
          icon: _iconForCategory(label, helper),
          accent: _accentForCategory(label, colorScheme),
        ),
      );
    }

    summaries.sort((left, right) => right.itemCount.compareTo(left.itemCount));
    return summaries;
  }

  List<StorefrontCategorySummary> _buildSubcategorySummaries({
    required List<Product> products,
    required ColorScheme colorScheme,
    required String? categoryLabel,
  }) {
    final grouped = <String, List<Product>>{};
    final parentBySubcategory = <String, String>{};
    final normalizedCategory = (categoryLabel ?? "").trim().toLowerCase();

    for (final product in products) {
      final parentCategory = product.category.trim();
      final subcategory = product.subcategory.trim();
      if (subcategory.isEmpty) {
        continue;
      }
      if (normalizedCategory.isNotEmpty &&
          parentCategory.toLowerCase() != normalizedCategory) {
        continue;
      }

      grouped.putIfAbsent(subcategory, () => []).add(product);
      parentBySubcategory.putIfAbsent(subcategory, () => parentCategory);
    }

    final summaries = <StorefrontCategorySummary>[];
    for (final entry in grouped.entries) {
      final label = entry.key;
      final items = entry.value;
      final parentCategory = parentBySubcategory[label];
      summaries.add(
        StorefrontCategorySummary(
          label: label,
          helper: parentCategory ?? "",
          itemCount: items.length,
          icon: _iconForCategory(parentCategory ?? label, label),
          accent: _accentForCategory(parentCategory ?? label, colorScheme),
          parentCategory: parentCategory,
        ),
      );
    }

    summaries.sort((left, right) {
      final countCompare = right.itemCount.compareTo(left.itemCount);
      if (countCompare != 0) {
        return countCompare;
      }
      return left.label.toLowerCase().compareTo(right.label.toLowerCase());
    });
    return summaries;
  }

  String _buildCategoryHelper(List<Product> products) {
    final subcategoryCounts = <String, int>{};
    final brandCounts = <String, int>{};

    for (final product in products) {
      final subcategory = product.subcategory.trim();
      final brand = product.brand.trim();
      if (subcategory.isNotEmpty) {
        subcategoryCounts.update(
          subcategory,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      if (brand.isNotEmpty) {
        brandCounts.update(brand, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    if (subcategoryCounts.isNotEmpty) {
      final topSubcategories = subcategoryCounts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      return topSubcategories.take(2).map((entry) => entry.key).join(" • ");
    }

    if (brandCounts.isNotEmpty) {
      final topBrands = brandCounts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      return topBrands.take(2).map((entry) => entry.key).join(" • ");
    }

    return products.length == 1
        ? "1 active product"
        : "${products.length} active products";
  }

  String _buildCatalogLabel(List<StorefrontCategorySummary> categories) {
    if (categories.isEmpty) {
      return "In store";
    }
    return categories.take(2).map((item) => item.label).join(" • ");
  }

  List<HomeHeroMetric> _buildHeroMetrics({
    required List<Product> products,
    required List<StorefrontCategorySummary> categories,
  }) {
    final inStockCount = products.where((product) => product.stock > 0).length;
    final brandCount = products
        .map((product) => product.brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .length;

    final metrics = <HomeHeroMetric>[
      HomeHeroMetric(
        label: "products",
        value: "${products.length}",
        icon: Icons.inventory_2_rounded,
      ),
      HomeHeroMetric(
        label: "categories",
        value: "${categories.length}",
        icon: Icons.category_rounded,
      ),
      HomeHeroMetric(
        label: "available now",
        value: "$inStockCount",
        icon: Icons.local_shipping_rounded,
      ),
    ];

    if (brandCount > 0) {
      metrics.insert(
        2,
        HomeHeroMetric(
          label: brandCount == 1 ? "brand" : "brands",
          value: "$brandCount",
          icon: Icons.sell_rounded,
        ),
      );
    }

    return metrics;
  }

  String _buildHeroSubtitle({
    required List<Product> products,
    required List<StorefrontCategorySummary> categories,
  }) {
    if (categories.isEmpty) {
      return "Browse the latest products, search quickly, and jump straight into product details from the store.";
    }

    final topBrands = products
        .map((product) => product.brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .take(2)
        .toList();
    final brandText = topBrands.isEmpty ? "the store" : topBrands.join(" and ");

    if (categories.length == 1 && topBrands.isNotEmpty) {
      return "Browse ${categories.first.label} products, explore $brandText, and move quickly from discovery into product details.";
    }

    if (categories.length == 1) {
      return "Browse ${categories.first.label} products, compare what is available, and jump straight into product details.";
    }

    return "Browse ${categories.first.label} and ${categories[1].label}, discover products from $brandText, and shop the latest items in the store.";
  }

  String _buildHeroPromoTitle({required String? highlightedCategory}) {
    if (highlightedCategory == null) {
      return "Start with the latest collection";
    }
    return "Start with $highlightedCategory";
  }

  String _buildPromoSubtitle(List<StorefrontCategorySummary> categories) {
    if (categories.isEmpty) {
      return "Explore the latest products available in the storefront.";
    }

    final visibleCategories = categories
        .take(3)
        .map((item) => item.label)
        .toList();
    return "Browse ${visibleCategories.join(", ")} and move quickly from category shortcuts into product details.";
  }

  List<String> _buildPromoHighlights(
    List<Product> products,
    List<StorefrontCategorySummary> categories,
  ) {
    final highlights = <String>[];

    if (categories.isNotEmpty) {
      highlights.add(
        "${categories.length} categories ready for quick browsing",
      );
    }

    final brands = products
        .map((product) => product.brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .toList();
    if (brands.isNotEmpty) {
      highlights.add(
        brands.length == 1
            ? "Browse products from ${brands.first}"
            : "Shop across ${brands.length} active brands",
      );
    }

    final inStockCount = products.where((product) => product.stock > 0).length;
    highlights.add(
      inStockCount == 1
          ? "1 product currently in stock"
          : "$inStockCount products currently in stock",
    );

    return highlights.take(3).toList();
  }

  IconData _iconForCategory(String label, String helper) {
    final normalized = "$label $helper".toLowerCase();
    if (normalized.contains("foot") ||
        normalized.contains("shoe") ||
        normalized.contains("sneaker")) {
      return Icons.hiking_rounded;
    }
    if (normalized.contains("farm") || normalized.contains("agro")) {
      return Icons.agriculture_rounded;
    }
    if (normalized.contains("kitchen") || normalized.contains("home")) {
      return Icons.kitchen_rounded;
    }
    if (normalized.contains("grain") || normalized.contains("cereal")) {
      return Icons.rice_bowl_rounded;
    }
    if (normalized.contains("vegetable")) {
      return Icons.eco_rounded;
    }
    return Icons.category_rounded;
  }

  Color _accentForCategory(String label, ColorScheme colorScheme) {
    final normalized = label.toLowerCase();
    if (normalized.contains("farm") || normalized.contains("agro")) {
      return colorScheme.secondary;
    }
    if (normalized.contains("home") || normalized.contains("kitchen")) {
      return colorScheme.tertiary;
    }
    return colorScheme.primary;
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: AppResponsiveContent(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.section,
          AppSpacing.page,
          AppSpacing.section,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LoadingBlock(height: 260, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.section),
            _LoadingBlock(height: 108, radius: AppRadius.xl),
            const SizedBox(height: AppSpacing.section),
            SizedBox(
              height: 152,
              child: Row(
                children: const [
                  Expanded(
                    child: _LoadingBlock(height: 152, radius: AppRadius.xl),
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _LoadingBlock(height: 152, radius: AppRadius.xl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            SizedBox(
              height: 430,
              child: Row(
                children: const [
                  Expanded(
                    child: _LoadingBlock(height: 430, radius: AppRadius.xl),
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _LoadingBlock(height: 430, radius: AppRadius.xl),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryProductSection {
  final StorefrontCategorySummary summary;
  final List<Product> products;

  const _CategoryProductSection({
    required this.summary,
    required this.products,
  });
}

class _LoadingBlock extends StatelessWidget {
  final double height;
  final double radius;

  const _LoadingBlock({required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
