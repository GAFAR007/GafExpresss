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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:frontend/app/core/constants/app_constants.dart';
import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/platform/platform_info.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/cart_model.dart';
import 'package:frontend/app/features/home/presentation/cart_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/delivery_address_sheet.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_providers.dart';
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_radius.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';

bool _isPaystackTemporarilyLocked() {
  return true;
}

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _isPaying = false;
  bool _isRequesting = false;

  bool _ensureBuyerAccess(String action) {
    final role = ref.read(authSessionProvider)?.user.role;
    if (isBuyerRole(role)) {
      return true;
    }

    AppDebug.log(
      "CART",
      "Buyer action blocked for non-buyer role",
      extra: {"action": action, "role": role ?? ""},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Staff accounts cannot use customer cart or checkout"),
        ),
      );
    }
    return false;
  }

  Future<DeliveryAddressSelection?> _selectDeliveryAddress() async {
    AppDebug.log("CART", "Delivery address selection start");

    try {
      final profile = await ref.read(userProfileProvider.future);
      if (profile == null) {
        AppDebug.log("CART", "Delivery address blocked (no profile)");
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
        "CART",
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

  Future<void> _startPaystackCheckout(CartState cart) async {
    if (!_ensureBuyerAccess("paystack_checkout")) {
      return;
    }

    if (_isPaying) {
      AppDebug.log("CART", "Ignored tap (_isPaying=true)");
      return;
    }

    if (cart.items.isEmpty) {
      AppDebug.log("CART", "Checkout blocked (empty cart)");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Your cart is empty")));
      return;
    }

    setState(() => _isPaying = true);

    try {
      final session = ref.read(authSessionProvider);
      if (session == null) {
        throw Exception("Not logged in");
      }

      final selection = await _selectDeliveryAddress();
      if (selection == null) {
        AppDebug.log("CART", "Checkout cancelled (no address selected)");
        if (mounted) setState(() => _isPaying = false);
        return;
      }

      final api = ref.read(orderApiProvider);

      AppDebug.log(
        "CART",
        "initPaystackCheckout() start",
        extra: {"items": cart.items.length},
      );

      final order = await api.createOrder(
        token: session.token,
        items: cart.items,
        deliveryAddress: selection.toPayload(),
      );

      // WHY: Refresh shared data so order lists update after creation.
      await AppRefresh.refreshApp(
        ref: ref,
        source: "order_create_success_cart",
      );

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Checkout failed: $e")));
    }
  }

  Future<void> _startRequestToBuy(CartState cart) async {
    if (!_ensureBuyerAccess("purchase_request")) {
      return;
    }

    if (_isRequesting) {
      AppDebug.log("CART", "Ignored request tap (_isRequesting=true)");
      return;
    }

    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Your cart is empty")));
      return;
    }

    setState(() => _isRequesting = true);

    try {
      final session = ref.read(authSessionProvider);
      if (session == null) {
        throw Exception("Not logged in");
      }

      final selection = await _selectDeliveryAddress();
      if (selection == null) {
        if (mounted) setState(() => _isRequesting = false);
        return;
      }

      final api = ref.read(purchaseRequestApiProvider);
      final result = await api.createBatchPurchaseRequests(
        token: session.token,
        items: cart.items,
        deliveryAddress: selection.toPayload(),
      );

      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(chatInboxProvider);

      if (!mounted) return;
      setState(() => _isRequesting = false);

      if (result.requests.isEmpty) {
        throw Exception("No seller requests were created");
      }

      if (result.requests.length == 1) {
        final conversationId = result.requests.first.conversationId.trim();
        if (conversationId.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Request sent. Continue the payment discussion in chat.",
              ),
            ),
          );
          await context.push("/chat/$conversationId");
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Requests sent to ${result.requests.length} sellers. Continue each payment in chat.",
          ),
        ),
      );
      context.go("/chat");
    } catch (e) {
      AppDebug.log("CART", "Request to buy failed", extra: {"error": "$e"});
      if (mounted) setState(() => _isRequesting = false);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Request failed: $e")));
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
    final totalText = formatNgnFromCents(cart.totalCents);

    // WHY: Viewing cart should clear unseen notification badge.
    if (cart.hasUnseenChanges && cart.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(cartProvider.notifier).markViewed();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cart"),
        leading: IconButton(
          onPressed: () {
            AppDebug.log("CART", "Back tapped");
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
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpacing.section),
                child: AppResponsiveContent(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.xl,
                    AppSpacing.page,
                    AppSpacing.section,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CartOverviewHeader(
                        itemCount: cart.totalItems,
                        totalText: totalText,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final itemsPanel = _CartItemsPanel(
                            items: cart.items,
                            onIncrease: (item) {
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
                            onDecrease: (item) {
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
                            onRemove: (item) {
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
                          final summaryPanel = _CartSummaryPanel(
                            itemCount: cart.totalItems,
                            totalText: totalText,
                            isPaying: _isPaying,
                            isRequesting: _isRequesting,
                            onRequestToBuy: _isRequesting
                                ? null
                                : () {
                                    AppDebug.log(
                                      "CART",
                                      "Request to buy tapped",
                                    );
                                    _startRequestToBuy(cart);
                                  },
                            onLockedPaystackTap: () {
                              AppDebug.log(
                                "CART",
                                "Locked Paystack callback retained",
                              );
                              _startPaystackCheckout(cart);
                            },
                            onCancelProcessing: _isPaying
                                ? _cancelProcessing
                                : null,
                          );

                          if (!isWide) {
                            return Column(
                              children: [
                                itemsPanel,
                                const SizedBox(height: AppSpacing.xl),
                                summaryPanel,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: itemsPanel),
                              const SizedBox(width: AppSpacing.xl),
                              SizedBox(width: 380, child: summaryPanel),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  final VoidCallback onGoHome;

  const _EmptyCart({required this.onGoHome});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppResponsiveContent(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.section,
        AppSpacing.page,
        AppSpacing.section,
      ),
      child: AppSectionCard(
        tone: AppPanelTone.hero,
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconBadge(
              icon: Icons.shopping_bag_outlined,
              color: scheme.primary,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              "Your cart is empty",
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Browse products, add what you like, and come back here to checkout.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onGoHome,
              icon: const Icon(Icons.storefront_rounded),
              label: const Text("Continue shopping"),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartOverviewHeader extends StatelessWidget {
  final int itemCount;
  final String totalText;

  const _CartOverviewHeader({required this.itemCount, required this.totalText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppSectionCard(
      tone: AppPanelTone.hero,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Row(
        children: [
          AppIconBadge(
            icon: Icons.shopping_cart_checkout_rounded,
            color: scheme.primary,
            size: 24,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Review your cart",
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "Check item quantities, remove anything you don't want, then continue to secure payment.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          AppStatusChip(
            label: "$itemCount item${itemCount == 1 ? '' : 's'}",
            tone: AppStatusTone.info,
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(width: AppSpacing.sm),
          AppStatusChip(
            label: totalText,
            tone: AppStatusTone.success,
            icon: Icons.payments_rounded,
          ),
        ],
      ),
    );
  }
}

class _CartItemsPanel extends StatelessWidget {
  final List<CartItem> items;
  final ValueChanged<CartItem> onIncrease;
  final ValueChanged<CartItem> onDecrease;
  final ValueChanged<CartItem> onRemove;

  const _CartItemsPanel({
    required this.items,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: "Cart items",
            subtitle:
                "${items.length} product${items.length == 1 ? '' : 's'} ready for checkout.",
          ),
          const SizedBox(height: AppSpacing.xl),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.lg),
            _CartItemTile(
              item: items[index],
              onIncrease: () => onIncrease(items[index]),
              onDecrease: () => onDecrease(items[index]),
              onRemove: () => onRemove(items[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CartSummaryPanel extends StatelessWidget {
  final int itemCount;
  final String totalText;
  final bool isPaying;
  final bool isRequesting;
  final VoidCallback? onRequestToBuy;
  final VoidCallback? onLockedPaystackTap;
  final VoidCallback? onCancelProcessing;

  const _CartSummaryPanel({
    required this.itemCount,
    required this.totalText,
    required this.isPaying,
    required this.isRequesting,
    required this.onRequestToBuy,
    required this.onLockedPaystackTap,
    required this.onCancelProcessing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPaystackLocked = _isPaystackTemporarilyLocked();

    return AppSectionCard(
      tone: AppPanelTone.hero,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Order summary",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Delivery address is selected first, then the app opens one seller chat per business so each seller can quote separately.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SummaryLine(label: "Items", value: itemCount.toString()),
          const SizedBox(height: AppSpacing.md),
          const _SummaryLine(label: "Delivery", value: "Select at checkout"),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: AppSpacing.lg),
          _SummaryLine(label: "Total", value: totalText, emphasize: true),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRequestToBuy,
              icon: isRequesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(
                isRequesting ? "Starting request..." : "Request to Buy",
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isPaystackLocked ? null : onLockedPaystackTap,
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(
                isPaying ? "Processing payment..." : "Pay with Paystack",
              ),
            ),
          ),
          if (onCancelProcessing != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancelProcessing,
                child: const Text("Cancel payment"),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  "Temporary flow: seller reviews the address, adds logistics and service charge, sends direct payment details, then approves your uploaded proof in chat.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ],
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unitPrice = formatNgnFromCents(item.unitPriceCents);
    final lineTotal = formatNgnFromCents(item.lineTotalCents);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;
          final image = ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Image.network(
              item.imageUrl,
              width: isCompact ? 84 : 96,
              height: isCompact ? 84 : 96,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: isCompact ? 84 : 96,
                height: isCompact ? 84 : 96,
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Unit price: $unitPrice",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Quantity: ${item.quantity}",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final lineSummary = Column(
            crossAxisAlignment: isCompact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                "Subtotal",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                lineTotal,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          );
          final quantityControl = _CartQuantityControl(
            quantity: item.quantity,
            onDecrease: onDecrease,
            onIncrease: onIncrease,
            onRemove: onRemove,
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    image,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Divider(color: scheme.outlineVariant, height: 1),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: lineSummary),
                    const SizedBox(width: AppSpacing.md),
                    quantityControl,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              image,
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: details),
              const SizedBox(width: AppSpacing.lg),
              lineSummary,
              const SizedBox(width: AppSpacing.lg),
              quantityControl,
            ],
          );
        },
      ),
    );
  }
}

class _CartQuantityControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  const _CartQuantityControl({
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CartCircleButton(
            icon: Icons.remove_rounded,
            tooltip: quantity <= 1 ? "Remove item" : "Decrease quantity",
            onPressed: onDecrease,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              quantity.toString(),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          _CartCircleButton(
            icon: Icons.add_rounded,
            tooltip: "Increase quantity",
            onPressed: onIncrease,
          ),
          const SizedBox(width: AppSpacing.xs),
          _CartCircleButton(
            icon: Icons.delete_outline_rounded,
            tooltip: "Remove product",
            onPressed: onRemove,
            foreground: scheme.error,
          ),
        ],
      ),
    );
  }
}

class _CartCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? foreground;

  const _CartCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, size: 20, color: foreground ?? scheme.primary),
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style:
                (emphasize
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                      color: emphasize
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
                    ),
          ),
        ),
        Text(
          value,
          style:
              (emphasize
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
        ),
      ],
    );
  }
}
