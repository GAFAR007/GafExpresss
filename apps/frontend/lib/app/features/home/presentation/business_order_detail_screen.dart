/// lib/app/features/home/presentation/business_order_detail_screen.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Business order detail screen with audit timeline + address card.
///
/// WHY:
/// - Business owners need a read-only audit view of fulfillment history.
/// - Keeps update actions elsewhere while showing verified delivery data.
///
/// HOW:
/// - Accepts a BusinessOrder via route extra.
/// - Renders summary, items, delivery address, and status history.
///
/// DEBUGGING:
/// - Logs build + back navigation taps.
/// ----------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_order_model.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessOrderDetailScreen extends StatelessWidget {
  final BusinessOrder order;

  const BusinessOrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_ORDER_DETAIL", "build()", extra: {"id": order.id});

    final items = order.items;
    final history = order.statusHistory;
    final address = order.deliveryAddress?.address;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Order details"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_ORDER_DETAIL", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-orders');
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WHY: The summary card gives instant context for this order.
            _SummaryCard(order: order),
            const SizedBox(height: 16),
            // WHY: Items list helps confirm what needs fulfillment.
            _SectionHeader(
              title: "Items",
              subtitle: "Products tied to this order.",
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const _EmptyState(text: "No items recorded yet.")
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ItemCard(item: item),
                ),
              ),
            const SizedBox(height: 16),
            // WHY: Delivery address card shows verified shipping details.
            _SectionHeader(
              title: "Delivery address",
              subtitle: "Verified address details used for fulfillment.",
            ),
            const SizedBox(height: 10),
            if (address == null)
              const _EmptyState(text: "No delivery address recorded.")
            else
              _AddressCard(order: order),
            const SizedBox(height: 16),
            // WHY: Timeline provides an audit trail for compliance.
            _SectionHeader(
              title: "Audit timeline",
              subtitle: "Status changes recorded by the system.",
            ),
            const SizedBox(height: 10),
            if (history.isEmpty)
              const _EmptyState(text: "No status changes recorded yet.")
            else
              _Timeline(history: history),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final BusinessOrder order;

  const _SummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final buyerName = order.user?.name ?? "Customer";
    final buyerEmail = order.user?.email ?? "—";
    final status = order.status.toUpperCase();
    final amount = formatNgnFromCents(order.totalPriceCents);
    final itemCount = order.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final statusCounts = _buildStatusCounts(order.status, itemCount);
    // WHY: Gradient colors should adapt to each theme (classic/dark/business).
    final gradientColors = theme.brightness == Brightness.dark
        ? <Color>[colorScheme.primaryContainer, colorScheme.primary]
        : <Color>[colorScheme.primary, colorScheme.primaryContainer];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: gradientColors),
        boxShadow: [
          BoxShadow(
            // WHY: Use theme shadow to avoid hardcoded contrast issues.
            color: colorScheme.shadow.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 10),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _StatusPill(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            buyerName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            buyerEmail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricTile(label: "Total", value: amount),
              const SizedBox(width: 12),
              _MetricTile(
                label: "Updated",
                value: _formatDate(order.updatedAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusCountPill(
                label: "Paid",
                count: statusCounts["paid"] ?? 0,
                tone: AppStatusTone.success,
              ),
              _StatusCountPill(
                label: "Shipped",
                count: statusCounts["shipped"] ?? 0,
                tone: AppStatusTone.info,
              ),
              _StatusCountPill(
                label: "Delivered",
                count: statusCounts["delivered"] ?? 0,
                tone: AppStatusTone.success,
              ),
              _StatusCountPill(
                label: "Cancelled",
                count: statusCounts["cancelled"] ?? 0,
                tone: AppStatusTone.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, int> _buildStatusCounts(String status, int itemCount) {
    final normalized = status.toLowerCase();
    return {
      "paid": normalized == "paid" ? itemCount : 0,
      "shipped": normalized == "shipped" ? itemCount : 0,
      "delivered": normalized == "delivered" ? itemCount : 0,
      "cancelled": normalized == "cancelled" ? itemCount : 0,
    };
  }

  String _formatDate(DateTime? date) {
    // WHY: Keep order dates consistent with shared formatting helpers.
    return formatDateLabel(date, fallback: kDateFallbackDash);
  }

  String _shortId(String id) {
    if (id.length <= 6) return id;
    return id.substring(id.length - 6).toUpperCase();
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Map status to theme-aware tones for consistent contrast.
    final tone = _toneForStatus(status);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  AppStatusTone _toneForStatus(String value) {
    switch (value.toLowerCase()) {
      case "paid":
        return AppStatusTone.success;
      case "shipped":
        return AppStatusTone.info;
      case "delivered":
        return AppStatusTone.success;
      case "cancelled":
      case "canceled":
        return AppStatusTone.danger;
      default:
        return AppStatusTone.neutral;
    }
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // WHY: Use theme onPrimary for readable contrast inside gradient.
          color: colorScheme.onPrimary.withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCountPill extends StatelessWidget {
  final String label;
  final int count;
  final AppStatusTone tone;

  const _StatusCountPill({
    required this.label,
    required this.count,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppStatusBadgeColors.fromTheme(theme: theme, tone: tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label: $count",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final OrderItem item;

  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            // WHY: Use theme shadow to adapt to dark/business surfaces.
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              image: imageUrl.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
            ),
            child: imageUrl.isEmpty
                ? Icon(Icons.inventory_2, color: colorScheme.onSurfaceVariant)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  "Qty ${item.quantity} • ${formatNgnFromCents(item.unitPriceCents)}",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatNgnFromCents(item.lineTotalCents),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final BusinessOrder order;

  const _AddressCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final address = order.deliveryAddress?.address;
    if (address == null) {
      return const _EmptyState(text: "No delivery address recorded.");
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            // WHY: Theme shadow keeps contrast consistent in all modes.
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                "Verified address",
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            address.formattedAddress?.isNotEmpty == true
                ? address.formattedAddress!
                : _joinAddress(address),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _AddressChip(
                label: "Source",
                value: order.deliveryAddress?.source,
              ),
              _AddressChip(label: "City", value: address.city),
              _AddressChip(label: "State", value: address.state),
              if (address.postalCode != null && address.postalCode!.isNotEmpty)
                _AddressChip(label: "Postal", value: address.postalCode),
            ],
          ),
        ],
      ),
    );
  }

  String _joinAddress(UserAddress address) {
    final parts = [
      address.houseNumber,
      address.street,
      address.city,
      address.state,
      address.postalCode,
    ].where((value) => value != null && value.trim().isNotEmpty).toList();
    return parts.map((value) => value!.trim()).join(', ');
  }
}

class _AddressChip extends StatelessWidget {
  final String label;
  final String? value;

  const _AddressChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value == null || value!.isEmpty ? "—" : value!;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label: $text",
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<BusinessOrderStatusEntry> history;

  const _Timeline({required this.history});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: history.map((entry) {
        final date = entry.changedAt == null
            ? "—"
            : _formatDate(entry.changedAt!);
        final role = entry.changedByRole?.isNotEmpty == true
            ? entry.changedByRole!.replaceAll('_', ' ')
            : "system";
        final note = entry.note?.isNotEmpty == true ? entry.note! : "update";

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.status.toUpperCase(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$date • $role",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatDate(DateTime date) {
    // WHY: Use shared date-time formatting for timeline entries.
    return formatDateTimeLabel(date);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
