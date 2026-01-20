/// lib/app/features/home/presentation/product_detail_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Product detail screen with cart + Paystack checkout.
///
/// WHY:
/// - Lets users add to cart or pay for a single product.
///
/// HOW:
/// - Uses productByIdProvider to fetch /products/:id.
/// - Creates an order and initializes Paystack checkout.
///
/// DEBUGGING:
/// - Logs build, taps, API start/end, and navigation.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend/app/core/constants/app_constants.dart';
import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/platform/platform_info.dart';
import 'package:frontend/app/features/home/presentation/cart_model.dart';
import 'package:frontend/app/features/home/presentation/cart_providers.dart';
import 'package:frontend/app/features/home/presentation/delivery_address_sheet.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/product_model.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  bool _isPaying = false;
  int _quantity = 1;

  void _addToCart(Product product) {
    final safeQty = _quantity.clamp(1, product.stock);

    AppDebug.log(
      "PRODUCT_DETAIL",
      "Add to cart tapped",
      extra: {"id": product.id, "qty": safeQty},
    );
    // WHY: Use the current quantity so cart matches user intent.
    ref.read(cartProvider.notifier).addProduct(product, quantity: safeQty);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Added to cart")),
    );
  }

  Future<DeliveryAddressSelection?> _selectDeliveryAddress() async {
    AppDebug.log("PRODUCT_DETAIL", "Delivery address selection start");

    try {
      final profile = await ref.read(userProfileProvider.future);
      if (profile == null) {
        AppDebug.log("PRODUCT_DETAIL", "Delivery address blocked (no profile)");
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Load your profile first")),
        );
        return null;
      }

      return await DeliveryAddressSheet.open(
        context: context,
        profile: profile,
      );
    } catch (e) {
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Delivery address selection failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to load delivery address options")),
      );
      return null;
    }
  }

  Future<void> _startPaystackCheckout(Product product) async {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "Pay with Paystack tapped",
      extra: {"id": product.id, "qty": _quantity},
    );

    if (_isPaying) {
      AppDebug.log("PRODUCT_DETAIL", "Ignored tap (_isPaying=true)");
      return;
    }

    if (product.stock <= 0) {
      AppDebug.log("PRODUCT_DETAIL", "Checkout blocked (out of stock)");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product is out of stock")),
      );
      return;
    }

    setState(() => _isPaying = true);

    try {
      // WHY: Clamp quantity to available stock before creating the order.
      final safeQty = _quantity.clamp(1, product.stock);

      final session = ref.read(authSessionProvider);
      if (session == null) {
        throw Exception("Not logged in");
      }

      final selection = await _selectDeliveryAddress();
      if (selection == null) {
        AppDebug.log("PRODUCT_DETAIL", "Checkout cancelled (no address selected)");
        if (mounted) setState(() => _isPaying = false);
        return;
      }

      final api = ref.read(orderApiProvider);

      AppDebug.log(
        "PRODUCT_DETAIL",
        "initPaystackCheckout() start",
        extra: {"productId": product.id},
      );

      final order = await api.createOrder(
        token: session.token,
        items: [CartItem.fromProduct(product, quantity: safeQty)],
        deliveryAddress: selection.toPayload(),
      );

      final callbackUrl = _buildCallbackUrl();
      if (callbackUrl == null || callbackUrl.isEmpty) {
        AppDebug.log("PRODUCT_DETAIL", "Missing callbackUrl for Paystack");
      }

      final init = await api.initPaystackCheckout(
        token: session.token,
        orderId: order.id,
        email: session.user.email,
        amountKobo: order.totalPriceCents,
        callbackUrl: callbackUrl,
      );

      await _openPaystack(
        authorizationUrl: init.authorizationUrl,
        callbackUrl: callbackUrl ?? "",
      );

      AppDebug.log(
        "PRODUCT_DETAIL",
        "Paystack opened; awaiting callback",
        extra: {"orderId": order.id},
      );
    } catch (e) {
      AppDebug.log("PRODUCT_DETAIL", "Checkout failed", extra: {"error": "$e"});
      if (mounted) setState(() => _isPaying = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Checkout failed: $e")),
      );
    }
  }

  Future<void> _openPaystack({
    required String authorizationUrl,
    required String callbackUrl,
  }) async {
    // WHY: Web should stay in same tab; mobile uses in-app WebView.
    if (PlatformInfo.isWeb) {
      final uri = Uri.parse(authorizationUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: "_self",
      );

      if (!launched) {
        throw Exception("Failed to open Paystack");
      }

      return;
    }

    AppDebug.log("PRODUCT_DETAIL", "Navigate -> /paystack");

    if (!mounted) return;
    await context.push(
      "/paystack",
      extra: PaystackCheckoutArgs(
        authorizationUrl: authorizationUrl,
        callbackUrl: callbackUrl,
      ),
    );
  }

  String? _buildCallbackUrl() {
    // WHY: Web can use same-origin callback; mobile needs public URL.
    if (PlatformInfo.isWeb) {
      return "${Uri.base.origin}/payment-success";
    }

    if (AppConstants.paystackCallbackBaseUrl.isEmpty) {
      return null;
    }

    return "${AppConstants.paystackCallbackBaseUrl}/payment-success";
  }

  void _cancelProcessing() {
    AppDebug.log("PRODUCT_DETAIL", "Cancel tapped");
    setState(() => _isPaying = false);
  }

  void _increaseQuantity(Product product) {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "Quantity + tapped",
      extra: {"id": product.id, "qty": _quantity},
    );

    // WHY: Prevent increasing when stock is unavailable.
    if (product.stock <= 0) return;

    final nextQty = _quantity + 1;
    if (nextQty > product.stock) {
      // WHY: Avoid exceeding available stock.
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Quantity max reached",
        extra: {"qty": _quantity, "stock": product.stock},
      );
      return;
    }

    setState(() => _quantity = nextQty);
  }

  void _decreaseQuantity(Product product) {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "Quantity - tapped",
      extra: {"id": product.id, "qty": _quantity},
    );

    // WHY: Minimum quantity is 1 for checkout/cart.
    if (_quantity <= 1) {
      AppDebug.log("PRODUCT_DETAIL", "Quantity min reached", extra: {"qty": _quantity});
      return;
    }

    setState(() => _quantity -= 1);
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "build()",
      extra: {"id": widget.productId, "isPaying": _isPaying, "qty": _quantity},
    );

    final productAsync = ref.watch(productByIdProvider(widget.productId));
    final cart = ref.watch(cartProvider);
    final cartBadgeCount =
        cart.hasUnseenChanges ? cart.totalItems : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Product Details"),
        leading: IconButton(
          onPressed: () {
            AppDebug.log("PRODUCT_DETAIL", "Back tapped");
            // WHY: If no back stack (e.g., from go()), return home.
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go("/home");
            }
          },
          icon: const Icon(Icons.arrow_back),
          tooltip: "Back",
        ),
        actions: [
          IconButton(
            onPressed: () {
              AppDebug.log("PRODUCT_DETAIL", "Go Cart tapped");
              context.go("/cart");
            },
            icon: Stack(
              children: [
                const Icon(Icons.shopping_cart),
                if (cartBadgeCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      // WHY: Count signals unseen cart items.
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        cartBadgeCount > 99 ? "99+" : "$cartBadgeCount",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: productAsync.when(
        data: (product) => _ProductDetailBody(
          product: product,
          isPaying: _isPaying,
          quantity: _quantity,
          onAddToCart: () => _addToCart(product),
          onGoToCart: () {
            AppDebug.log("PRODUCT_DETAIL", "View cart tapped");
            context.go("/cart");
          },
          onPayWithPaystack: () => _startPaystackCheckout(product),
          onCancelPay: _cancelProcessing,
          onIncreaseQty: () => _increaseQuantity(product),
          onDecreaseQty: () => _decreaseQuantity(product),
        ),
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
  final bool isPaying;
  final int quantity;
  final VoidCallback onAddToCart;
  final VoidCallback onGoToCart;
  final VoidCallback onPayWithPaystack;
  final VoidCallback onCancelPay;
  final VoidCallback onIncreaseQty;
  final VoidCallback onDecreaseQty;

  const _ProductDetailBody({
    required this.product,
    required this.isPaying,
    required this.quantity,
    required this.onAddToCart,
    required this.onGoToCart,
    required this.onPayWithPaystack,
    required this.onCancelPay,
    required this.onIncreaseQty,
    required this.onDecreaseQty,
  });

  @override
  Widget build(BuildContext context) {
    final priceText = _formatPrice(product.priceCents);
    final stockText = product.stock > 0 ? "In stock" : "Out of stock";
    final canBuy = product.stock > 0;
    final canDecrease = quantity > 1;
    final canIncrease = quantity < product.stock;
    final totalText = _formatPrice(product.priceCents * quantity);

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
          Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
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
          const SizedBox(height: 16),
          // WHY: Let users pick quantity before adding to cart or paying.
          Row(
            children: [
              Text(
                "Quantity",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              // WHY: Show live total beside quantity for quick price clarity.
              Text(
                "Total: $totalText",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: canBuy && canDecrease ? onDecreaseQty : null,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: "Decrease quantity",
              ),
              Text(
                quantity.toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                onPressed: canBuy && canIncrease ? onIncreaseQty : null,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: "Increase quantity",
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: canBuy ? onAddToCart : null,
                  child: const Text("Add to cart"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onGoToCart,
                  child: const Text("View cart"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: canBuy && !isPaying ? onPayWithPaystack : null,
            child: Text(
              isPaying ? "Processing payment..." : "Pay with Paystack",
            ),
          ),
          if (isPaying) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onCancelPay,
              child: const Text("Cancel"),
            ),
          ],
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
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
            flex: 2,
          ),
        ],
      ),
    );
  }
}
