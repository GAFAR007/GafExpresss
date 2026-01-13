/// lib/app/features/home/presentation/product_detail_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Product detail screen (by id).
///
/// WHY:
/// - Shows full product info when user taps a product.
///
/// HOW:
/// - Uses productByIdProvider to fetch /products/:id.
/// - Renders all product fields (id, name, description, price, stock, etc).
///
/// DEBUGGING:
/// - Logs build and fetch errors (safe only).
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("PRODUCT_DETAIL", "build()", extra: {"id": productId});

    final productAsync = ref.watch(productByIdProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Product Details"),
      ),
      body: productAsync.when(
        data: (product) => _ProductDetailBody(product: product),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          AppDebug.log(
            "PRODUCT_DETAIL",
            "fetch failed",
            extra: {"error": error.toString()},
          );
          return const Center(child: Text("Failed to load product"));
        },
      ),
    );
  }
}

class _ProductDetailBody extends StatelessWidget {
  final Product product;

  const _ProductDetailBody({required this.product});

  @override
  Widget build(BuildContext context) {
    final priceText = _formatPrice(product.priceCents);
    final stockText = product.stock > 0 ? "In stock" : "Out of stock";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WHY: Keep image visible at top for quick context.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              product.imageUrl,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 220,
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.image_not_supported)),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            product.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            product.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _InfoRow(label: "ID", value: product.id),
          _InfoRow(label: "Price", value: priceText),
          _InfoRow(label: "Stock", value: "${product.stock} ($stockText)"),
          _InfoRow(label: "Active", value: product.isActive ? "Yes" : "No"),
          _InfoRow(
            label: "Created",
            value: product.createdAt?.toIso8601String() ?? "N/A",
          ),
          _InfoRow(
            label: "Updated",
            value: product.updatedAt?.toIso8601String() ?? "N/A",
          ),
        ],
      ),
    );
  }

  String _formatPrice(int priceCents) {
    final value = (priceCents / 100).toStringAsFixed(2);
    return "₦$value";
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              "$label:",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
