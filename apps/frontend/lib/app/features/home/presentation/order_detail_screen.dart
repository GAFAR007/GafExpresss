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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

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
      final updated = await api.cancelOrder(
        token: session.token,
        orderId: _order.id,
      );

      setState(() {
        _order = updated;
        _isCancelling = false;
      });

      // WHY: Refresh the orders list so status stays in sync.
      ref.invalidate(myOrdersProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Order cancelled")));
    } catch (e) {
      AppDebug.log("ORDER_DETAIL", "Cancel failed", extra: {"error": "$e"});
      if (mounted) setState(() => _isCancelling = false);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Cancel failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("ORDER_DETAIL", "build()", extra: {"id": _order.id});

    final totalText = formatNgnFromCents(_order.totalPriceCents);
    final isPending = _order.status == "pending";
    final createdText = _formatDate(_order.createdAt);
    final itemCount = _order.items.length;
    final colorScheme = Theme.of(context).colorScheme;
    final paymentNote = _order.paymentSource == "manual_direct"
        ? "Payment was confirmed by the seller after proof review."
        : "Payments are confirmed by webhook.";

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text("Receipt")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WHY: Receipt card groups all order info in one visual block.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.08),
                    blurRadius: 16,
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
                        "Receipt",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      _StatusChip(status: _order.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text("Order #${_shortId(_order.id)}"),
                  const SizedBox(height: 4),
                  Text("Placed: $createdText"),
                  const SizedBox(height: 4),
                  Text("Items: $itemCount"),
                  const SizedBox(height: 12),
                  const _DashedDivider(),
                  const SizedBox(height: 12),
                  Text("Items", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  // WHY: Use a non-scrollable list to keep a single receipt scroll.
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _order.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _order.items[index];
                      final lineTotal = formatNgnFromCents(item.lineTotalCents);
                      final unitText =
                          "${item.quantity} x ${formatNgnFromCents(item.unitPriceCents)}";

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              item.imageUrl,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.image_not_supported),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name.isEmpty ? "Product" : item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  unitText,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            lineTotal,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const _DashedDivider(),
                  const SizedBox(height: 12),
                  // WHY: Summary row clarifies the final payable amount.
                  _SummaryRow(
                    label: "Subtotal",
                    value: formatNgnFromCents(_order.subtotalPriceCents),
                  ),
                  if (_order.logisticsFeeCents > 0)
                    _SummaryRow(
                      label: "Logistics",
                      value: formatNgnFromCents(_order.logisticsFeeCents),
                    ),
                  if (_order.serviceChargeCents > 0)
                    _SummaryRow(
                      label: "Service charge",
                      value: formatNgnFromCents(_order.serviceChargeCents),
                    ),
                  _SummaryRow(label: "Tax", value: formatNgnFromCents(0)),
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: "Total",
                    value: totalText,
                    isEmphasis: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Payment method: ${_order.paymentSource == "manual_direct" ? "Seller direct invoice" : "Paystack"}",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    paymentNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 16),
              // WHY: Keep cancel visible outside the receipt for emphasis.
              ElevatedButton(
                onPressed: _isCancelling ? null : _cancelOrder,
                child: Text(_isCancelling ? "Cancelling..." : "Cancel Order"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    // WHY: Keep order timestamps consistent across screens.
    return formatDateLabel(date);
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
    final theme = Theme.of(context);
    final badge = AppStatusBadgeColors.fromStatus(
      theme: theme,
      status: switch (normalized) {
        "paid" => AppStatusKind.paid,
        "shipped" => AppStatusKind.shipped,
        "delivered" => AppStatusKind.delivered,
        "cancelled" => AppStatusKind.cancelled,
        "pending" => AppStatusKind.pending,
        _ => AppStatusKind.neutral,
      },
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          color: badge.foreground,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmphasis;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isEmphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = isEmphasis
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;

    return Row(
      children: [
        Text(label, style: style),
        const Spacer(),
        Text(value, style: style),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // WHY: Dashed line gives a receipt-like feel without images.
        final dashCount = (constraints.maxWidth / 8).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            dashCount,
            (_) => SizedBox(
              width: 4,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: scheme.outlineVariant),
              ),
            ),
          ),
        );
      },
    );
  }
}
