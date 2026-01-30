/// lib/app/features/home/presentation/tenant_dashboard_screen.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Tenant-facing dashboard showing tenancy status, coverage, and quick actions.
///
/// WHY:
/// - Gives tenants a one-look view (status, paid through, next due) without
///   digging into the verification form.
///
/// HOW:
/// - Pulls tenancy summary via tenantSummaryProvider.
/// - Uses theme tokens for all colors/typography.
/// - Provides quick links to manage verification / view receipt.
///
/// DEBUGGING:
/// - Logs build + tap events via AppDebug.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_providers.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart'
    as tenant_model;

const String _summaryMissingMessage =
    "No tenant summary yet. Complete verification to activate your dashboard.";
const String _summaryEstateMissingMessage =
    "Tenant estate is not assigned yet. Please contact support.";
const String _summaryAuthMessage =
    "Your session needs a refresh. Please sign out and sign in again.";
const String _summaryGenericMessage =
    "Unable to load tenant summary right now.";
const String _summaryRefreshLabel = "Refresh";
const String _summaryRefreshHint = "Kindly refresh to check again.";
const String _summaryMissingResolutionHint =
    "Refresh the dashboard to retry loading the summary.";
const String _summaryRefreshSource = "tenant_dashboard_empty_refresh";
// WHY: Centralize tenant verification navigation target.
const String _tenantVerificationRoute = "/tenant-verification";

class TenantDashboardScreen extends ConsumerWidget {
  const TenantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("TENANT_DASH", "build()");
    final summaryAsync = ref.watch(tenantSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tenant dashboard"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("TENANT_DASH", "back_tap");
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          IconButton(
            onPressed: () async {
              AppDebug.log("TENANT_DASH", "refresh_action");
              // WHY: Central refresh keeps tenant data in sync across screens.
              await AppRefresh.refreshApp(
                ref: ref,
                source: "tenant_dashboard_refresh",
              );
            },
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log("TENANT_DASH", "refresh");
          // WHY: Central refresh keeps tenant data in sync across screens.
          await AppRefresh.refreshApp(
            ref: ref,
            source: "tenant_dashboard_pull",
          );
        },
        child: summaryAsync.when(
          data: (summary) => _DashboardBody(summary: summary),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _SummaryErrorState(error: err),
        ),
      ),
    );
  }
}

class _SummaryErrorState extends ConsumerWidget {
  final Object error;

  const _SummaryErrorState({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolveSummaryError(error);
    final message = resolved.message;
    final shouldShowAction = resolved.showRefreshAction;
    final hint = resolved.uiHint;

    // WHY: Capture error context + next action for support diagnostics.
    AppDebug.log(
      "TENANT_DASH",
      "summary_load_failed",
      extra: {
        "reason": resolved.reason,
        "status": resolved.statusCode,
        "next_action": resolved.resolutionHint,
      },
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
              ),
            ],
            if (shouldShowAction) ...[
              // WHY: Provide a safe retry path using the central refresh flow.
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  AppDebug.log("TENANT_DASH", "summary_refresh_tap");
                  await AppRefresh.refreshApp(
                    ref: ref,
                    source: _summaryRefreshSource,
                  );
                },
                child: const Text(_summaryRefreshLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryErrorResolution {
  final String message;
  final String reason;
  final String resolutionHint;
  final int statusCode;
  final bool showRefreshAction;
  final String? uiHint;

  const _SummaryErrorResolution({
    required this.message,
    required this.reason,
    required this.resolutionHint,
    required this.statusCode,
    required this.showRefreshAction,
    required this.uiHint,
  });
}

_SummaryErrorResolution _resolveSummaryError(Object error) {
  // WHY: Map API errors to tenant-friendly copy + next steps.
  if (error is DioException) {
    final status = error.response?.statusCode ?? 0;
    final data = error.response?.data;
    final providerMessage = data is Map<String, dynamic>
        ? data["error"]?.toString()
        : null;

    if (status == 404) {
      return const _SummaryErrorResolution(
        message: _summaryMissingMessage,
        reason: "tenant_summary_not_found",
        resolutionHint: _summaryMissingResolutionHint,
        statusCode: 404,
        showRefreshAction: true,
        uiHint: _summaryRefreshHint,
      );
    }

    if (status == 400 &&
        providerMessage != null &&
        providerMessage.toLowerCase().contains("estate")) {
      return const _SummaryErrorResolution(
        message: _summaryEstateMissingMessage,
        reason: "tenant_estate_missing",
        resolutionHint: "Assign a tenant estate or contact support.",
        statusCode: 400,
        showRefreshAction: false,
        uiHint: null,
      );
    }

    if (status == 401 || status == 403) {
      return const _SummaryErrorResolution(
        message: _summaryAuthMessage,
        reason: "tenant_auth_error",
        resolutionHint: "Sign out and sign in again to refresh your session.",
        statusCode: 403,
        showRefreshAction: false,
        uiHint: null,
      );
    }

    return _SummaryErrorResolution(
      message: _summaryGenericMessage,
      reason: "tenant_summary_error",
      resolutionHint:
          "Try again or contact support if the issue persists.",
      statusCode: status,
      showRefreshAction: false,
      uiHint: null,
    );
  }

  return const _SummaryErrorResolution(
    message: _summaryGenericMessage,
    reason: "tenant_summary_unknown_error",
    resolutionHint: "Try again or contact support if the issue persists.",
    statusCode: 0,
    showRefreshAction: false,
    uiHint: null,
  );
}

class _DashboardBody extends StatelessWidget {
  final tenant_model.TenantSummary summary;
  const _DashboardBody({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = summary.status.toLowerCase();
    final paymentStatus = summary.paymentStatus.toLowerCase();

    final bool isApprovedOrActive =
        status == 'approved' || status == 'active';
    final bool isActive = status == 'active';
    final bool isPaid = paymentStatus == 'paid';
    final payments = summary.paymentsSummary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroCard(
          title: isActive ? "Tenant active" : "Tenancy status",
          subtitle: isActive
              ? "Your rent payment is confirmed."
              : status == 'approved'
                  ? "Pay rent to activate your tenancy."
                  : "We are processing your application.",
          statusLabel: isPaid ? "PAID" : status.toUpperCase(),
          agreementLabel: summary.agreementStatus.isEmpty
              ? null
              : "Agreement: ${summary.agreementStatus.toUpperCase()}",
          paidThrough: summary.paidThroughDate,
          nextDue: summary.nextDueDate,
          showReceipt: isPaid,
          onViewReceipt: () {
            AppDebug.log("TENANT_DASH", "view_receipt_tap");
            // TODO: Navigate to receipts when available.
          },
        ),
        const SizedBox(height: 16),
        if (payments != null) ...[
          _KpiRow(
            chips: [
              _KpiChip(
                label: "Paid YTD",
                value: _formatMoney(payments.totalPaidKoboYtd),
              ),
              _KpiChip(
                label: "All-time",
                value: _formatMoney(payments.totalPaidKoboAllTime),
              ),
              _KpiChip(
                label: "Payments this year",
                value: payments.paymentsThisYear.toString(),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _InfoCard(
          title: "Plan",
          rows: [
            ("Unit", summary.unitType),
            // WHY: Rent amounts are stored in kobo; format to NGN for display.
            (
              "Rent",
              "${formatNgnFromCents(summary.rentAmount.round())} / ${summary.rentPeriod}",
            ),
            ("Move-in", _fmtDate(summary.moveInDate)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  AppDebug.log("TENANT_DASH", "cta_verify");
                  context.go(_tenantVerificationRoute);
                },
                icon: const Icon(Icons.verified_user),
                label: const Text("View verification"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isApprovedOrActive
                    ? () {
                        AppDebug.log("TENANT_DASH", "cta_pay");
                  context.go(_tenantVerificationRoute);
                      }
                    : null,
                icon: const Icon(Icons.payments),
                label: Text(isActive ? "View receipts" : "Pay rent"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _InfoCard(
          title: "Important dates",
          rows: [
            ("Paid through", _fmtDate(summary.paidThroughDate)),
            ("Next due", _fmtDate(summary.nextDueDate)),
            ("Last payment", _fmtDate(summary.lastRentPaymentAt)),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          "Need help?",
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          "If anything looks off, tap “View verification” to review your details or contact support.",
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _MiniTimeline(
          steps: [
            _TimelineStep(label: "Submitted", done: true),
            _TimelineStep(
              label: "Approved",
              done: isApprovedOrActive || isPaid,
            ),
            _TimelineStep(label: "Paid", done: isPaid),
            _TimelineStep(label: "Active", done: isActive),
          ],
        ),
      ],
    );
  }

  String _fmtDate(DateTime? dt) {
    // WHY: Keep tenant dashboard dates consistent across screens.
    return formatDateLabel(dt, fallback: "Not set");
  }

  String _formatMoney(int kobo) {
    // WHY: Keep money formatting centralized and consistent.
    return formatNgnFromCents(kobo);
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String statusLabel;
  final String? agreementLabel;
  final DateTime? paidThrough;
  final DateTime? nextDue;
  final bool showReceipt;
  final VoidCallback? onViewReceipt;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.paidThrough,
    required this.nextDue,
    this.agreementLabel,
    this.showReceipt = false,
    this.onViewReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (agreementLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    agreementLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _StatusValue(label: "Paid through", value: _fmtDate(paidThrough)),
              _StatusValue(label: "Next due", value: _fmtDate(nextDue)),
            ],
          ),
          if (showReceipt) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewReceipt,
                icon: const Icon(Icons.receipt_long),
                label: const Text("View payment receipt"),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    // WHY: Reuse shared date formatting for dashboard cards.
    return formatDateLabel(dt, fallback: "Not set");
  }
}

class _KpiRow extends StatelessWidget {
  final List<_KpiChip> chips;
  const _KpiRow({required this.chips});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: chips,
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final String value;
  const _KpiChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      row.$1,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      row.$2,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTimeline extends StatelessWidget {
  final List<_TimelineStep> steps;
  const _MiniTimeline({required this.steps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: steps
            .map(
              (s) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    s.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: s.done
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool done;
  const _TimelineStep({required this.label, required this.done});
}

class _StatusValue extends StatelessWidget {
  final String label;
  final String value;
  const _StatusValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
