/// lib/app/features/home/presentation/production/production_preorder_reservations_screen.dart
/// ----------------------------------------------------------------------------------------
/// WHAT:
/// - Owner monitoring screen for pre-order reservations.
///
/// WHY:
/// - Gives operations a single place to track reservation lifecycle and drift signals.
///
/// HOW:
/// - Calls GET /business/preorder/reservations with status/plan filters.
/// - Shows summary counters, paginated rows, and quick refresh controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/production/production_models.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';

const String _logTag = "PREORDER_MONITORING_SCREEN";
const String _screenTitle = "Pre-order reservations";
const String _routeBackFallback = "/business-production";
const String _refreshAction = "refresh";
const String _applyFilterAction = "apply_filters";
const String _clearFilterAction = "clear_filters";
const String _pagePrevAction = "page_prev";
const String _pageNextAction = "page_next";

const List<String> _statusFilterValues = [
  "",
  "reserved",
  "confirmed",
  "released",
  "expired",
];

class ProductionPreorderReservationsScreen extends ConsumerStatefulWidget {
  const ProductionPreorderReservationsScreen({super.key});

  @override
  ConsumerState<ProductionPreorderReservationsScreen> createState() =>
      _ProductionPreorderReservationsScreenState();
}

class _ProductionPreorderReservationsScreenState
    extends ConsumerState<ProductionPreorderReservationsScreen> {
  final TextEditingController _planIdController = TextEditingController();

  ProductionPreorderReservationListResponse? _result;
  String _error = "";
  String _statusFilter = "";
  int _page = 1;
  bool _loading = true;

  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _planIdController.dispose();
    super.dispose();
  }

  Future<void> _reload({int? page, String? status, String? planId}) async {
    final targetPage = page ?? _page;
    final targetStatus = status ?? _statusFilter;
    final targetPlanId = planId ?? _planIdController.text.trim();

    setState(() {
      _loading = true;
      _error = "";
    });

    try {
      final actions = ref.read(productionPlanActionsProvider);
      final response = await actions.listPreorderReservations(
        status: targetStatus.trim().isEmpty ? null : targetStatus.trim(),
        planId: targetPlanId.isEmpty ? null : targetPlanId,
        page: targetPage,
        limit: _limit,
      );
      if (!mounted) return;

      setState(() {
        _result = response;
        _statusFilter = response.filters.status;
        _page = response.pagination.page;
        _loading = false;
      });
    } catch (error) {
      AppDebug.log(_logTag, "load failed", extra: {"error": error.toString()});
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    AppDebug.log(
      _logTag,
      _applyFilterAction,
      extra: {"status": _statusFilter, "planId": _planIdController.text.trim()},
    );
    _reload(page: 1);
  }

  void _clearFilters() {
    AppDebug.log(_logTag, _clearFilterAction);
    _planIdController.clear();
    setState(() {
      _statusFilter = "";
      _page = 1;
    });
    _reload(page: 1, status: "", planId: "");
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(_logTag, "build()");

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(_routeBackFallback);
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              AppDebug.log(_logTag, _refreshAction);
              _reload(page: _page);
            },
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _reload(page: _page),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildFiltersCard(context),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error.isNotEmpty)
              _buildErrorCard(context)
            else if (_result == null)
              const SizedBox.shrink()
            else ...[
              _buildSummaryCard(context, _result!.summary),
              const SizedBox(height: 16),
              _buildReservationList(context, _result!),
              const SizedBox(height: 16),
              _buildPaginationRow(context, _result!.pagination),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Filters",
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _statusFilter,
            decoration: const InputDecoration(
              labelText: "Status",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _statusFilterValues
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value.isEmpty ? "all" : value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _statusFilter = value ?? "";
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _planIdController,
            decoration: const InputDecoration(
              labelText: "Plan id (optional)",
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _applyFilters,
                  child: const Text("Apply"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearFilters,
                  child: const Text("Clear"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ProductionPreorderReservationSummary summary,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    Widget metric(String label, int value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                "$value",
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            metric("Total", summary.total),
            const SizedBox(width: 8),
            metric("Reserved", summary.reserved),
            const SizedBox(width: 8),
            metric("Confirmed", summary.confirmed),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            metric("Released", summary.released),
            const SizedBox(width: 8),
            metric("Expired", summary.expired),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildReservationList(
    BuildContext context,
    ProductionPreorderReservationListResponse result,
  ) {
    final reservations = result.reservations;
    if (reservations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text("No reservations found."),
      );
    }

    return Column(
      children: reservations
          .map(
            (reservation) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReservationCard(reservation: reservation),
            ),
          )
          .toList(),
    );
  }

  Widget _buildPaginationRow(
    BuildContext context,
    ProductionPreorderReservationPagination pagination,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: pagination.hasPrev
                ? () {
                    AppDebug.log(_logTag, _pagePrevAction);
                    _reload(page: pagination.page - 1);
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text("Prev"),
          ),
        ),
        Expanded(
          child: Center(
            child: Text("Page ${pagination.page} / ${pagination.totalPages}"),
          ),
        ),
        Expanded(
          child: FilledButton.icon(
            onPressed: pagination.hasNext
                ? () {
                    AppDebug.log(_logTag, _pageNextAction);
                    _reload(page: pagination.page + 1);
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text("Next"),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Unable to load reservations",
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(_error),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => _reload(page: _page),
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final ProductionPreorderReservationRecord reservation;

  const _ReservationCard({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chipColor = _statusColor(reservation.status, colorScheme);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reservation.plan.title.isEmpty
                      ? "Plan ${reservation.planId}"
                      : reservation.plan.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reservation.status,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text("Qty: ${reservation.quantity}"),
          const SizedBox(height: 4),
          Text(
            "Customer: ${reservation.user.name.isNotEmpty ? reservation.user.name : reservation.user.email}",
          ),
          const SizedBox(height: 4),
          Text("Created: ${formatDateLabel(reservation.createdAt)}"),
          const SizedBox(height: 4),
          Text("Expires: ${formatDateLabel(reservation.expiresAt)}"),
          if (reservation.expiredAt != null) ...[
            const SizedBox(height: 4),
            Text("Expired at: ${formatDateLabel(reservation.expiredAt)}"),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case "confirmed":
        return Colors.green.shade700;
      case "released":
        return Colors.blueGrey.shade700;
      case "expired":
        return Colors.orange.shade700;
      case "reserved":
      default:
        return scheme.primary;
    }
  }
}
