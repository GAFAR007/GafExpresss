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

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text("Order ${order.id}"),
        subtitle: Text("Status: ${order.status}"),
        trailing: Text(totalText),
      ),
    );
  }

  String _formatPrice(int priceCents) {
    final value = (priceCents / 100).toStringAsFixed(2);
    return "NGN $value";
  }
}
