// ignore: dangling_library_doc_comments
/// lib/features/home/presentation/home_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Home screen (post-login landing).
///
/// WHY:
/// - Shows products from /products endpoint.
/// - Provides logout action to clear session.
///
/// HOW:
/// - Fetches products via productsProvider.
/// - Renders ProductItemButton list.
///
/// DEBUGGING:
/// - Logs build, logout tap, and product list errors.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_item_button.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("HOME", "build()");

    final productsAsync = ref.watch(productsProvider);

    ProductItemData toItemData(Product product) {
      return ProductItemData(
        id: product.id,
        name: product.name,
        description: product.description,
        priceCents: product.priceCents,
        stock: product.stock,
        imageUrl: product.imageUrl,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Products",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Row(
                    children: [
                      // WHY: Quick access to cart without leaving home.
                      IconButton(
                        onPressed: () {
                          AppDebug.log("HOME", "Cart tapped");
                          context.go('/cart');
                        },
                        icon: const Icon(Icons.shopping_cart),
                        tooltip: "Cart",
                      ),
                      // WHY: Orders are part of the checkout flow.
                      IconButton(
                        onPressed: () {
                          AppDebug.log("HOME", "Orders tapped");
                          context.go('/orders');
                        },
                        icon: const Icon(Icons.receipt_long),
                        tooltip: "Orders",
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          AppDebug.log("HOME", "Logout tapped");
                          await ref.read(authSessionProvider.notifier).logout();

                          if (!context.mounted) return;
                          context.go('/login');
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text("Logout"),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: productsAsync.when(
                  data: (products) {
                    if (products.isEmpty) {
                      return const Center(child: Text("No products yet"));
                    }

                    return ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ProductItemButton(
                          item: toItemData(product),
                          onTap: () {
                            AppDebug.log(
                              "HOME",
                              "Product tapped",
                              extra: {"id": product.id},
                            );
                            context.go('/product/${product.id}');
                          },
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) {
                    AppDebug.log(
                      "HOME",
                      "Products load failed",
                      extra: {"error": error.toString()},
                    );
                    return const Center(
                      child: Text("Failed to load products"),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
