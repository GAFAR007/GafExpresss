/// lib/app/features/home/presentation/business_orders_screen.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Business orders list + status update screen.
///
/// WHY:
/// - Business owners/staff must track fulfillment and update status.
/// - Keeps business orders separate from customer order history.
///
/// HOW:
/// - Uses businessOrdersProvider for /business/orders.
/// - Status updates call BusinessOrderApi and refresh providers.
///
/// DEBUGGING:
/// - Logs screen build, filter changes, and status updates.
/// ----------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_order_model.dart';
import 'package:frontend/app/features/home/presentation/business_order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/business_analytics_models.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessOrdersScreen extends ConsumerStatefulWidget {
  const BusinessOrdersScreen({super.key});

  @override
  ConsumerState<BusinessOrdersScreen> createState() =>
      _BusinessOrdersScreenState();
}

class _BusinessOrdersScreenState extends ConsumerState<BusinessOrdersScreen> {
  String? _updatingOrderId;

  static const Map<String, List<String>> _statusTransitions = {
    "pending": ["paid", "cancelled"],
    "paid": ["shipped", "cancelled"],
    "shipped": ["delivered"],
    "delivered": [],
    "cancelled": [],
  };

  void _logTap(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log("BUSINESS_ORDERS", "Tap", extra: {"action": action, ...?extra});
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_ORDERS", "build()");

    final statusFilter = ref.watch(businessOrderStatusFilterProvider);
    final ordersAsync = ref.watch(businessOrdersProvider);
    final summaryAsync = ref.watch(businessAnalyticsSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business orders"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_ORDERS", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-dashboard');
          },
        ),
        actions: [
          IconButton(
            onPressed: () async {
              _logTap("refresh");
              // WHY: Central refresh keeps business data in sync across screens.
              await AppRefresh.refreshApp(
                ref: ref,
                source: "business_orders_refresh",
              );
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _logTap("pull_to_refresh");
          // WHY: Central refresh keeps business data in sync across screens.
          await AppRefresh.refreshApp(
            ref: ref,
            source: "business_orders_pull",
          );
        },
        child: ordersAsync.when(
          data: (result) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // WHY: Present analytics first so teams see the big picture.
                _AnalyticsHeader(summaryAsync: summaryAsync),
                const SizedBox(height: 16),
                // WHY: Status badges double as filters and quick health checks.
                _StatusBadgesRow(
                  summaryAsync: summaryAsync,
                  selected: statusFilter ?? "all",
                  onTap: (value) {
                    _logTap("filter_change", extra: {"status": value});
                    final next = value == "all" ? null : value;
                    ref
                        .read(businessOrderStatusFilterProvider.notifier)
                        .state = next;
                    ref.invalidate(businessOrdersProvider);
                  },
                ),
                const SizedBox(height: 16),
                // WHY: Keep list context visible when filtering.
                _OrdersMeta(
                  count: result.orders.length,
                  total: result.total,
                ),
                const SizedBox(height: 12),
                if (result.orders.isEmpty)
                  const _EmptyState(text: "No orders yet")
                else
                  ...result.orders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _BusinessOrderCard(
                        order: order,
                        isUpdating: _updatingOrderId == order.id,
                        nextStatuses: _nextStatusOptions(order.status),
                        onUpdateTapped: () =>
                            _handleUpdateStatus(context, order),
                        onOpenDetail: () {
                          _logTap("open_detail", extra: {"orderId": order.id});
                          context.push(
                            '/business-orders/${order.id}',
                            extra: order,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            AppDebug.log(
              "BUSINESS_ORDERS",
              "Load failed",
              extra: {"error": error.toString()},
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                Center(child: Text("Failed to load business orders")),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 3,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  List<String> _nextStatusOptions(String currentStatus) {
    final normalized = currentStatus.toLowerCase();
    return _statusTransitions[normalized] ?? const [];
  }

  Future<void> _handleUpdateStatus(
    BuildContext context,
    BusinessOrder order,
  ) async {
    _logTap("update_status", extra: {"orderId": order.id});

    // WHY: Only allow transitions that backend will accept to reduce errors.
    final options = _nextStatusOptions(order.status);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Order is already in a final status")),
      );
      return;
    }

    final selected = await _openStatusSheet(context, options);
    if (selected == null) {
      _logTap("update_status_cancelled", extra: {"orderId": order.id});
      return;
    }

    try {
      setState(() => _updatingOrderId = order.id);
      final api = ref.read(businessOrderApiProvider);
      _logTap("update_status_submit", extra: {"status": selected});
      await api.updateOrderStatus(
        token: ref.read(authSessionProvider)?.token,
        orderId: order.id,
        status: selected,
      );
      ref.invalidate(businessOrdersProvider);
      if (!mounted) return;
      // WHY: Refresh shared data so order changes propagate globally.
      await AppRefresh.refreshApp(
        ref: ref,
        source: "business_order_update_success",
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Order updated to $selected")),
      );
    } catch (e) {
      AppDebug.log(
        "BUSINESS_ORDERS",
        "Update status failed",
        extra: {"error": e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Status update failed: ${e.toString()}")),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingOrderId = null);
      }
    }
  }

  Future<String?> _openStatusSheet(
    BuildContext context,
    List<String> options,
  ) async {
    _logTap("status_sheet_open", extra: {"options": options.length});

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 6),
            Center(
              child: Text(
                "Update status",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            ...options.map(
              (status) => ListTile(
                title: Text(status.toUpperCase()),
                onTap: () {
                  _logTap("status_selected", extra: {"status": status});
                  Navigator.of(context).pop(status);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_ORDERS", "Bottom nav tapped", extra: {"index": index});
    switch (index) {
      case 0:
        context.go('/home');
        return;
      case 1:
        context.go('/business-products');
        return;
      case 2:
        context.go('/business-dashboard');
        return;
      case 3:
        context.go('/business-orders');
        return;
      case 4:
        context.go('/chat');
        return;
      case 5:
        context.go('/settings');
        return;
    }
  }
}

class _BusinessOrderCard extends StatelessWidget {
  final BusinessOrder order;
  final bool isUpdating;
  final List<String> nextStatuses;
  final VoidCallback onUpdateTapped;
  final VoidCallback onOpenDetail;

  const _BusinessOrderCard({
    required this.order,
    required this.isUpdating,
    required this.nextStatuses,
    required this.onUpdateTapped,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.length;
    final buyerName = order.user?.name ?? "Customer";
    final buyerEmail = order.user?.email ?? "—";
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onOpenDetail,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _OrderAccent(status: order.status),
                const SizedBox(width: 8),
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
              "$buyerName • $buyerEmail",
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetaChip(
                  label: "Items",
                  value: "$itemCount",
                ),
                const SizedBox(width: 8),
                _MetaChip(
                  label: "Total",
                  value: formatNgnFromCents(order.totalPriceCents),
                ),
                const Spacer(),
                Text(
                  "View details",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: scheme.primary,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _formatAddress(order),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isUpdating || nextStatuses.isEmpty
                        ? null
                        : onUpdateTapped,
                    child: isUpdating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            nextStatuses.isEmpty
                                ? "Final status"
                                : "Update status",
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatAddress(BusinessOrder order) {
    final address = order.deliveryAddress?.address;
    if (address == null) return "Delivery address unavailable";
    final city = address.city?.trim() ?? '';
    final state = address.state?.trim() ?? '';
    final parts = [city, state].where((value) => value.isNotEmpty).toList();
    if (parts.isEmpty) return "Delivery address unavailable";
    return "Delivery: ${parts.join(', ')}";
  }

  String _shortId(String id) {
    if (id.length <= 6) return id;
    return id.substring(id.length - 6).toUpperCase();
  }
}

class _OrderAccent extends StatelessWidget {
  final String status;

  const _OrderAccent({required this.status});

  @override
  Widget build(BuildContext context) {
    final palette = _statusPalette(context, status);

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: palette.foreground,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label: $value",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  final AsyncValue<BusinessAnalyticsSummary> summaryAsync;

  const _AnalyticsHeader({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    return summaryAsync.when(
      data: (summary) {
        final revenue = formatNgnFromCents(summary.revenueTotal);
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [
                scheme.surface,
                scheme.surfaceContainerHighest,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Fulfillment analytics",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                "Monitor order health, revenue, and delivery pace.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _AnalyticsTile(
                    label: "Orders",
                    value: "${summary.totalOrders}",
                  ),
                  const SizedBox(width: 12),
                  _AnalyticsTile(
                    label: "Revenue",
                    value: revenue,
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () {
        return Container(
          height: 140,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
          ),
        );
      },
      error: (error, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            "Analytics unavailable",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }

}

class _AnalyticsTile extends StatelessWidget {
  final String label;
  final String value;

  const _AnalyticsTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadgesRow extends StatelessWidget {
  final AsyncValue<BusinessAnalyticsSummary> summaryAsync;
  final String selected;
  final ValueChanged<String> onTap;

  const _StatusBadgesRow({
    required this.summaryAsync,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return summaryAsync.when(
      data: (summary) {
        final entries = <Map<String, dynamic>>[
          {"status": "all", "count": summary.totalOrders},
          {"status": "pending", "count": summary.ordersByStatus["pending"] ?? 0},
          {"status": "paid", "count": summary.ordersByStatus["paid"] ?? 0},
          {
            "status": "shipped",
            "count": summary.ordersByStatus["shipped"] ?? 0,
          },
          {
            "status": "delivered",
            "count": summary.ordersByStatus["delivered"] ?? 0,
          },
          {
            "status": "cancelled",
            "count": summary.ordersByStatus["cancelled"] ?? 0,
          },
        ];

        return SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final status = entry["status"] as String;
              final count = entry["count"] as int;
              final isActive = selected == status;
              final scheme = Theme.of(context).colorScheme;
              final accent = scheme.primary;
              final textColor =
                  isActive ? scheme.onPrimary : scheme.onSurfaceVariant;

              return InkWell(
                onTap: () => onTap(status),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? accent : scheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      if (isActive)
                        BoxShadow(
                          color: accent.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                    ],
                    border: Border.all(
                      color: isActive ? accent : scheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        status.toUpperCase(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? scheme.onPrimary.withOpacity(0.2)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "$count",
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: textColor,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () {
        return Container(
          height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      },
      error: (error, _) {
        return const SizedBox.shrink();
      },
    );
  }
}

class _OrdersMeta extends StatelessWidget {
  final int count;
  final int total;

  const _OrdersMeta({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          "Showing $count of $total",
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final palette = _statusPalette(context, normalized);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          color: palette.foreground,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

AppStatusBadgeColors _statusPalette(BuildContext context, String status) {
  final normalized = status.toLowerCase();
  final tone = switch (normalized) {
    "paid" => AppStatusTone.success,
    "shipped" => AppStatusTone.info,
    "delivered" => AppStatusTone.success,
    "cancelled" => AppStatusTone.neutral,
    "pending" => AppStatusTone.warning,
    _ => AppStatusTone.neutral,
  };

  return AppStatusBadgeColors.fromTheme(
    theme: Theme.of(context),
    tone: tone,
  );
}
