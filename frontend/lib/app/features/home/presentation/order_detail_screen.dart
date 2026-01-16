/// lib/app/features/home/presentation/order_detail_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Shows details for a single order.
///
/// WHY:
/// - Users need to see status + items after checkout.
///
/// HOW:
/// - Receives Order via navigation args.
/// - Allows cancel if status is pending.
///
/// DEBUGGING:
/// - Logs build and cancel actions.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final Order order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  late Order _order;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _cancelOrder() async {
    if (_isCancelling) {
      AppDebug.log("ORDER_DETAIL", "Cancel ignored (_isCancelling=true)");
      return;
    }

    AppDebug.log("ORDER_DETAIL", "Cancel tapped", extra: {"id": _order.id});
    setState(() => _isCancelling = true);

    try {
      final session = ref.read(authSessionProvider);
      if (session == null) {
        throw Exception("Not logged in");
      }

      final api = ref.read(orderApiProvider);
      final updated =
          await api.cancelOrder(token: session.token, orderId: _order.id);

      setState(() {
        _order = updated;
        _isCancelling = false;
      });

      // WHY: Refresh the orders list so status stays in sync.
      ref.invalidate(myOrdersProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Order cancelled")),
      );
    } catch (e) {
      AppDebug.log("ORDER_DETAIL", "Cancel failed", extra: {"error": "$e"});
      if (mounted) setState(() => _isCancelling = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cancel failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("ORDER_DETAIL", "build()", extra: {"id": _order.id});

    final totalText = _formatPrice(_order.totalPriceCents);
    final isPending = _order.status == "pending";

    return Scaffold(
      appBar: AppBar(title: const Text("Order Details")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Order ID: ${_order.id}"),
            const SizedBox(height: 8),
            Text("Status: ${_order.status}"),
            const SizedBox(height: 8),
            Text("Total: $totalText"),
            const SizedBox(height: 16),
            Text(
              "Items",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: _order.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _order.items[index];
                  final lineTotal = _formatPrice(item.lineTotalCents);
                  return ListTile(
                    leading: Image.network(
                      item.imageUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported),
                    ),
                    title: Text(item.name.isEmpty ? "Product" : item.name),
                    subtitle: Text("Qty: ${item.quantity}"),
                    trailing: Text(lineTotal),
                  );
                },
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isCancelling ? null : _cancelOrder,
                child: Text(
                  _isCancelling ? "Cancelling..." : "Cancel Order",
                ),
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
