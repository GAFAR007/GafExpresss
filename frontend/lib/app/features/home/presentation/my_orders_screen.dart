/// lib/app/features/home/presentation/my_orders_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - My Orders list screen.
///
/// WHY:
/// - Users need a history of their orders.
///
/// HOW:
/// - Uses myOrdersProvider to fetch /orders.
/// - Navigates to OrderDetailScreen on tap.
///
/// DEBUGGING:
/// - Logs build, refresh, and item taps.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("MY_ORDERS", "build()");

    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Orders"),
        leading: IconButton(
          onPressed: () {
            AppDebug.log("MY_ORDERS", "Back tapped");
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
              AppDebug.log("MY_ORDERS", "Refresh tapped");
              ref.invalidate(myOrdersProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F6F7),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text("No orders yet"));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              return _OrderTile(
                order: order,
                onTap: () {
                  AppDebug.log(
                    "MY_ORDERS",
                    "Order tapped",
                    extra: {"id": order.id},
                  );
                  context.push("/orders/${order.id}", extra: order);
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          AppDebug.log(
            "MY_ORDERS",
            "Load failed",
            extra: {"error": error.toString()},
          );
          return const Center(child: Text("Failed to load orders"));
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  const _OrderTile({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final totalText = _formatPrice(order.totalPriceCents);
    final createdText = _formatDate(order.createdAt);
    final itemCount = order.items.length;
    final firstItemName =
        order.items.isEmpty ? "Items pending" : order.items.first.name;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "Order #${_shortId(order.id)}",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Placed: $createdText",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              firstItemName.isEmpty ? "Items pending" : firstItemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  "$itemCount item${itemCount == 1 ? '' : 's'}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  totalText,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // WHY: Subtle affordance that the card is tappable.
            Row(
              children: [
                Text(
                  "View receipt",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green.shade700,
                      ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: Colors.green.shade700, size: 18),
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

  String _formatDate(DateTime? date) {
    if (date == null) return "N/A";

    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, "0");
    final day = local.day.toString().padLeft(2, "0");
    return "${local.year}-$month-$day";
  }

  String _shortId(String id) {
    if (id.length <= 6) return id;
    return id.substring(id.length - 6).toUpperCase();
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final Color bg;
    final Color fg;

    // WHY: Color-coded status improves quick scanning.
    switch (normalized) {
      case "paid":
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case "cancelled":
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
        break;
      case "pending":
      default:
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
