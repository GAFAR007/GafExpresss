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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend/app/core/constants/app_constants.dart';
import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/core/platform/platform_info.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
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
  bool _isReserving = false;
  bool _isReleasing = false;
  String? _reservedReservationId;
  int? _reservedQuantity;
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Added to cart")));
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

      if (!mounted) return null;
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
        const SnackBar(
          content: Text("Failed to load delivery address options"),
        ),
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

    final hasReservedHold = (_reservedReservationId ?? "").trim().isNotEmpty;
    if (product.stock <= 0 && !hasReservedHold) {
      AppDebug.log("PRODUCT_DETAIL", "Checkout blocked (out of stock)");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Product is out of stock")));
      return;
    }

    setState(() => _isPaying = true);

    try {
      // WHY: Clamp quantity to available stock before creating the order.
      final safeQty = product.stock > 0
          ? _quantity.clamp(1, product.stock).toInt()
          : _quantity;
      final normalizedReservationId = (_reservedReservationId ?? "").trim();
      final hasReservationId = normalizedReservationId.isNotEmpty;
      final checkoutQuantity = hasReservationId
          ? (_reservedQuantity ?? safeQty)
          : safeQty;

      final session = ref.read(authSessionProvider);
      if (session == null) {
        throw Exception("Not logged in");
      }

      final selection = await _selectDeliveryAddress();
      if (selection == null) {
        AppDebug.log(
          "PRODUCT_DETAIL",
          "Checkout cancelled (no address selected)",
        );
        if (mounted) setState(() => _isPaying = false);
        return;
      }

      final api = ref.read(orderApiProvider);

      AppDebug.log(
        "PRODUCT_DETAIL",
        "initPaystackCheckout() start",
        extra: {
          "productId": product.id,
          "hasReservationId": hasReservationId,
          "quantity": checkoutQuantity,
        },
      );

      final order = await api.createOrder(
        token: session.token,
        items: [CartItem.fromProduct(product, quantity: checkoutQuantity)],
        deliveryAddress: selection.toPayload(),
        reservationId: hasReservationId ? normalizedReservationId : null,
      );

      // WHY: Refresh shared data so order lists update after creation.
      await AppRefresh.refreshApp(
        ref: ref,
        source: "order_create_success_product_detail",
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Checkout failed: $e")));
    }
  }

  Future<void> _releasePreorderReservation({
    String? reservationId,
    bool showFeedback = true,
  }) async {
    final targetReservationId = (reservationId ?? _reservedReservationId ?? "")
        .trim();
    if (targetReservationId.isEmpty || _isReleasing) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please sign in to release pre-order hold"),
        ),
      );
      return;
    }

    setState(() => _isReleasing = true);
    try {
      final api = ref.read(productApiProvider);
      final result = await api.releasePreorderReservation(
        token: session.token,
        reservationId: targetReservationId,
      );
      if (!mounted) return;

      setState(() {
        _reservedReservationId = null;
        _reservedQuantity = null;
      });
      ref.invalidate(productPreorderAvailabilityProvider(widget.productId));

      if (!showFeedback) {
        return;
      }
      final message = result.idempotent
          ? "Reservation already released"
          : "Reservation released. Remaining: ${result.remaining}";
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Release preorder failed",
        extra: {
          "error": error.toString(),
          "reservationId": targetReservationId,
        },
      );
      if (!mounted || !showFeedback) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Release failed: $error")));
    } finally {
      if (mounted) {
        setState(() => _isReleasing = false);
      }
    }
  }

  Future<void> _reservePreorder(Product product) async {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "Reserve preorder tapped",
      extra: {"id": product.id, "qty": _quantity},
    );

    if (_isReserving) {
      AppDebug.log("PRODUCT_DETAIL", "Ignored reserve tap (_isReserving=true)");
      return;
    }

    final availability = ref
        .read(productPreorderAvailabilityProvider(widget.productId))
        .valueOrNull;
    if (availability == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Pre-order availability is still loading"),
        ),
      );
      return;
    }
    if (!availability.preorderEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Pre-order is not enabled for this product"),
        ),
      );
      return;
    }

    final planId = (product.productionPlanId ?? "").trim();
    if (planId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This product is not linked to a production plan"),
        ),
      );
      return;
    }

    final effectiveRemaining = availability.effectiveRemainingQuantity;
    if (effectiveRemaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pre-order capacity available")),
      );
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please sign in to reserve pre-order quantity"),
        ),
      );
      return;
    }

    final safeQuantity = _quantity.clamp(1, effectiveRemaining);
    setState(() => _isReserving = true);
    try {
      final api = ref.read(productApiProvider);
      final result = await api.reservePreorder(
        token: session.token,
        planId: planId,
        quantity: safeQuantity,
      );
      if (!mounted) return;
      setState(() {
        _reservedReservationId = result.reservationId;
        _reservedQuantity = result.quantity;
        _quantity = result.quantity;
      });
      ref.invalidate(productPreorderAvailabilityProvider(widget.productId));

      final remaining = result.remaining;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Reserved ${result.quantity}. Remaining: $remaining"),
        ),
      );
    } catch (error) {
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Reserve preorder failed",
        extra: {"error": error.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Reserve failed: $error")));
    } finally {
      if (mounted) {
        setState(() => _isReserving = false);
      }
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
    final reservationId = (_reservedReservationId ?? "").trim();
    setState(() => _isPaying = false);
    if (reservationId.isNotEmpty) {
      _releasePreorderReservation(reservationId: reservationId);
    }
  }

  void _increaseQuantity(Product product) {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "Quantity + tapped",
      extra: {"id": product.id, "qty": _quantity},
    );

    if ((_reservedReservationId ?? "").trim().isNotEmpty) {
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Quantity change blocked (active reserved hold)",
        extra: {"reservationId": _reservedReservationId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Release reserved hold before changing quantity"),
        ),
      );
      return;
    }

    final maxSelectable = _resolveMaxSelectableQuantity(product);
    final nextQty = _quantity + 1;
    if (nextQty > maxSelectable) {
      // WHY: Avoid exceeding the current stock/preorder selectable limit.
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Quantity max reached",
        extra: {"qty": _quantity, "maxSelectable": maxSelectable},
      );
      return;
    }

    setState(() {
      _quantity = nextQty;
    });
  }

  int _resolveMaxSelectableQuantity(Product product) {
    final stockLimit = product.stock > 0 ? product.stock : 0;
    final availability = ref
        .read(productPreorderAvailabilityProvider(widget.productId))
        .valueOrNull;
    final preorderLimit = availability?.preorderEnabled == true
        ? availability!.effectiveRemainingQuantity
        : 0;
    final maxSelectable = stockLimit > preorderLimit
        ? stockLimit
        : preorderLimit;
    return maxSelectable > 0 ? maxSelectable : 1;
  }

  void _decreaseQuantity(Product product) {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "Quantity - tapped",
      extra: {"id": product.id, "qty": _quantity},
    );

    if ((_reservedReservationId ?? "").trim().isNotEmpty) {
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Quantity change blocked (active reserved hold)",
        extra: {"reservationId": _reservedReservationId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Release reserved hold before changing quantity"),
        ),
      );
      return;
    }

    // WHY: Minimum quantity is 1 for checkout/cart.
    if (_quantity <= 1) {
      AppDebug.log(
        "PRODUCT_DETAIL",
        "Quantity min reached",
        extra: {"qty": _quantity},
      );
      return;
    }

    setState(() {
      _quantity -= 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "PRODUCT_DETAIL",
      "build()",
      extra: {"id": widget.productId, "isPaying": _isPaying, "qty": _quantity},
    );

    final productAsync = ref.watch(productByIdProvider(widget.productId));
    final preorderAvailabilityAsync = ref.watch(
      productPreorderAvailabilityProvider(widget.productId),
    );
    final cart = ref.watch(cartProvider);
    final cartBadgeCount = cart.hasUnseenChanges ? cart.totalItems : 0;
    final scheme = Theme.of(context).colorScheme;

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
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        cartBadgeCount > 99 ? "99+" : "$cartBadgeCount",
                        style: TextStyle(
                          color: scheme.onError,
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
        data: (product) {
          final maxSelectableQuantity = _resolveMaxSelectableQuantity(product);
          return _ProductDetailBody(
            product: product,
            preorderAvailabilityAsync: preorderAvailabilityAsync,
            isPaying: _isPaying,
            isReserving: _isReserving,
            isReleasing: _isReleasing,
            reservedReservationId: _reservedReservationId,
            quantity: _quantity,
            maxSelectableQuantity: maxSelectableQuantity,
            onAddToCart: () => _addToCart(product),
            onGoToCart: () {
              AppDebug.log("PRODUCT_DETAIL", "View cart tapped");
              context.go("/cart");
            },
            onPayWithPaystack: () => _startPaystackCheckout(product),
            onReservePreorder: () => _reservePreorder(product),
            onReleasePreorder: _releasePreorderReservation,
            onCancelPay: _cancelProcessing,
            onIncreaseQty: () => _increaseQuantity(product),
            onDecreaseQty: () => _decreaseQuantity(product),
          );
        },
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
  final AsyncValue<PreorderAvailability> preorderAvailabilityAsync;
  final bool isPaying;
  final bool isReserving;
  final bool isReleasing;
  final String? reservedReservationId;
  final int quantity;
  final int maxSelectableQuantity;
  final VoidCallback onAddToCart;
  final VoidCallback onGoToCart;
  final VoidCallback onPayWithPaystack;
  final VoidCallback onReservePreorder;
  final Future<void> Function() onReleasePreorder;
  final VoidCallback onCancelPay;
  final VoidCallback onIncreaseQty;
  final VoidCallback onDecreaseQty;

  const _ProductDetailBody({
    required this.product,
    required this.preorderAvailabilityAsync,
    required this.isPaying,
    required this.isReserving,
    required this.isReleasing,
    required this.reservedReservationId,
    required this.quantity,
    required this.maxSelectableQuantity,
    required this.onAddToCart,
    required this.onGoToCart,
    required this.onPayWithPaystack,
    required this.onReservePreorder,
    required this.onReleasePreorder,
    required this.onCancelPay,
    required this.onIncreaseQty,
    required this.onDecreaseQty,
  });

  @override
  Widget build(BuildContext context) {
    final priceText = formatNgnFromCents(product.priceCents);
    final stockText = product.stock > 0 ? "In stock" : "Out of stock";
    final canBuy = product.stock > 0;
    final canDecrease = quantity > 1;
    final canIncrease = quantity < maxSelectableQuantity;
    final totalText = formatNgnFromCents(product.priceCents * quantity);
    final scheme = Theme.of(context).colorScheme;
    final hasReservedHold =
        reservedReservationId != null && reservedReservationId!.isNotEmpty;
    final preorderAvailability = preorderAvailabilityAsync.valueOrNull;
    final effectiveRemaining =
        preorderAvailability?.effectiveRemainingQuantity ?? 0;
    final canReserve =
        preorderAvailability?.preorderEnabled == true &&
        effectiveRemaining > 0 &&
        !isReserving;
    final canAdjustQuantity =
        !hasReservedHold &&
        (canBuy ||
            (preorderAvailability?.preorderEnabled == true &&
                effectiveRemaining > 0));
    final canCheckout = (canBuy || hasReservedHold) && !isPaying;
    final canReleaseReservedHold = hasReservedHold && !isReleasing;

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
                  color: scheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
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
            label: "Production",
            value: product.productionState.isEmpty
                ? "-"
                : product.productionState,
          ),
          _InfoRow(
            label: "Created",
            // WHY: Keep product audit dates consistent with shared helpers.
            value: formatDateLabel(product.createdAt),
          ),
          _InfoRow(
            label: "Updated",
            // WHY: Use the same formatter for updated timestamps.
            value: formatDateLabel(product.updatedAt),
          ),
          const SizedBox(height: 16),
          Text(
            "Pre-order availability",
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          preorderAvailabilityAsync.when(
            data: (availability) {
              final confidencePercent = (availability.confidenceScore * 100)
                  .toStringAsFixed(0);
              final coveragePercent =
                  (availability.approvedProgressCoverage * 100).toStringAsFixed(
                    0,
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: "Enabled",
                    value: availability.preorderEnabled ? "Yes" : "No",
                  ),
                  _InfoRow(
                    label: "Cap",
                    value: availability.preorderCapQuantity.toString(),
                  ),
                  _InfoRow(
                    label: "Reserved",
                    value: availability.preorderReservedQuantity.toString(),
                  ),
                  _InfoRow(
                    label: "Remaining",
                    value: availability.preorderRemainingQuantity.toString(),
                  ),
                  _InfoRow(
                    label: "Effective cap",
                    value: availability.effectiveCap.toString(),
                  ),
                  _InfoRow(
                    label: "Effective remaining",
                    value: availability.effectiveRemainingQuantity.toString(),
                  ),
                  _InfoRow(
                    label: "Confidence",
                    value: "$confidencePercent% (coverage $coveragePercent%)",
                  ),
                ],
              );
            },
            loading: () => const Text("Loading pre-order availability..."),
            error: (error, _) => Text(
              "Failed to load pre-order availability: $error",
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: canReserve ? onReservePreorder : null,
            child: Text(
              isReserving
                  ? "Reserving pre-order..."
                  : "Reserve pre-order quantity",
            ),
          ),
          if (reservedReservationId != null &&
              reservedReservationId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "Reserved hold: $reservedReservationId",
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: canReleaseReservedHold
                  ? () {
                      onReleasePreorder();
                    }
                  : null,
              child: Text(
                isReleasing ? "Releasing hold..." : "Release reserved hold",
              ),
            ),
          ],
          const SizedBox(height: 16),
          // WHY: Let users pick quantity before adding to cart or paying.
          Row(
            children: [
              Text("Quantity", style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              // WHY: Show live total beside quantity for quick price clarity.
              Text(
                "Total: $totalText",
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                onPressed: canAdjustQuantity && canDecrease
                    ? onDecreaseQty
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: "Decrease quantity",
              ),
              Text(
                quantity.toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                onPressed: canAdjustQuantity && canIncrease
                    ? onIncreaseQty
                    : null,
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
            onPressed: canCheckout ? onPayWithPaystack : null,
            child: Text(
              isPaying ? "Processing payment..." : "Pay with Paystack",
            ),
          ),
          if (isPaying) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onCancelPay, child: const Text("Cancel")),
          ],
        ],
      ),
    );
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
            flex: 2,
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
