/// lib/app/features/home/presentation/cart_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Cart screen with Paystack checkout.
///
/// WHY:
/// - Lets users review items and pay once.
///
/// HOW:
/// - Reads cartProvider for items + totals.
/// - Creates order, initializes Paystack, and opens checkout.
///
/// DEBUGGING:
/// - Logs build, button taps, API start/end, and navigation.
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
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _isPaying = false;

  Future<void> _startPaystackCheckout(CartState cart) async {
    if (_isPaying) {
      AppDebug.log("CART", "Ignored tap (_isPaying=true)");
      return;
    }

    if (cart.items.isEmpty) {
      AppDebug.log("CART", "Checkout blocked (empty cart)");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Your cart is empty")),
      );
      return;
    }

    setState(() => _isPaying = true);

    try {
      final session = ref.read(authSessionProvider);
      if (session == null) {
        throw Exception("Not logged in");
      }

      final api = ref.read(orderApiProvider);

      AppDebug.log(
        "CART",
        "initPaystackCheckout() start",
        extra: {"items": cart.items.length},
      );

      final order =
          await api.createOrder(token: session.token, items: cart.items);

      final callbackUrl = _buildCallbackUrl();
      if (callbackUrl == null || callbackUrl.isEmpty) {
        AppDebug.log("CART", "Missing callbackUrl for Paystack");
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
        "CART",
        "Paystack opened; awaiting callback",
        extra: {"orderId": order.id},
      );
    } catch (e) {
      AppDebug.log("CART", "Checkout failed", extra: {"error": "$e"});
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

    AppDebug.log("CART", "Navigate -> /paystack");

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
    AppDebug.log("CART", "Cancel tapped");
    setState(() => _isPaying = false);
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("CART", "build()", extra: {"isPaying": _isPaying});

    final cart = ref.watch(cartProvider);
    final totalText = _formatPrice(cart.totalCents);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cart"),
        actions: [
          IconButton(
            onPressed: () {
              AppDebug.log("CART", "Go Orders tapped");
              context.go("/orders");
            },
            icon: const Icon(Icons.receipt_long),
          ),
          IconButton(
            onPressed: () {
              AppDebug.log("CART", "Go Home tapped");
              context.go("/home");
            },
            icon: const Icon(Icons.home),
          ),
        ],
      ),
      body: cart.isEmpty
          ? _EmptyCart(
              onGoHome: () {
                AppDebug.log("CART", "Go Home tapped (empty cart)");
                context.go("/home");
              },
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: cart.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = cart.items[index];
                        return _CartItemTile(
                          item: item,
                          onIncrease: () {
                            AppDebug.log(
                              "CART",
                              "Increase qty tapped",
                              extra: {"productId": item.productId},
                            );
                            ref
                                .read(cartProvider.notifier)
                                .updateQuantity(
                                  item.productId,
                                  item.quantity + 1,
                                );
                          },
                          onDecrease: () {
                            AppDebug.log(
                              "CART",
                              "Decrease qty tapped",
                              extra: {"productId": item.productId},
                            );
                            ref
                                .read(cartProvider.notifier)
                                .updateQuantity(
                                  item.productId,
                                  item.quantity - 1,
                                );
                          },
                          onRemove: () {
                            AppDebug.log(
                              "CART",
                              "Remove tapped",
                              extra: {"productId": item.productId},
                            );
                            ref
                                .read(cartProvider.notifier)
                                .removeProduct(item.productId);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Items: ${cart.totalItems}"),
                      Text("Total: $totalText"),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isPaying
                        ? null
                        : () {
                            AppDebug.log("CART", "Pay with Paystack tapped");
                            _startPaystackCheckout(cart);
                          },
                    child: Text(
                      _isPaying ? "Processing payment..." : "Pay with Paystack",
                    ),
                  ),
                  if (_isPaying) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cancelProcessing,
                      child: const Text("Cancel"),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _formatPrice(int priceCents) {
    final value = (priceCents / 100).toStringAsFixed(2);
    return "NGN $value";
  }
}

class _EmptyCart extends StatelessWidget {
  final VoidCallback onGoHome;

  const _EmptyCart({required this.onGoHome});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Your cart is empty"),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onGoHome,
            child: const Text("Go Home"),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lineTotal = _formatPrice(item.lineTotalCents);

    return Card(
      child: ListTile(
        leading: Image.network(
          item.imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.image_not_supported),
        ),
        title: Text(item.name),
        subtitle: Text("Qty: ${item.quantity}"),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(lineTotal),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove),
                  tooltip: "Decrease",
                ),
                IconButton(
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add),
                  tooltip: "Increase",
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete),
                  tooltip: "Remove",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(int priceCents) {
    final value = (priceCents / 100).toStringAsFixed(2);
    return "NGN $value";
  }
}
