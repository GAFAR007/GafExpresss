/// lib/app/features/home/presentation/tenant_dashboard_screen.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Tenant-facing dashboard showing tenancy status, coverage, and quick actions.
///
/// WHY:
/// - Gives tenants a clearer status-first view with stronger hierarchy and
///   richer data blocks while keeping the current routes and logic intact.
/// ----------------------------------------------------------------
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart'
    as tenant_model;
import 'package:frontend/app/features/home/presentation/tenant_verification_providers.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';

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
const String _tenantVerificationRoute = "/tenant-verification";
const String _tenantPaymentsRoute = "/tenant-payments";
const String _logCtaReceipts = "cta_receipts";

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
          await AppRefresh.refreshApp(
            ref: ref,
            source: "tenant_dashboard_pull",
          );
        },
        child: summaryAsync.when(
          data: (summary) => _DashboardBody(summary: summary),
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 180),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (err, stackTrace) => _SummaryErrorState(error: err),
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

    AppDebug.log(
      "TENANT_DASH",
      "summary_load_failed",
      extra: {
        "reason": resolved.reason,
        "status": resolved.statusCode,
        "next_action": resolved.resolutionHint,
      },
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        AppResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            120,
            AppSpacing.page,
            AppSpacing.section,
          ),
          child: AppEmptyState(
            icon: Icons.apartment_rounded,
            title: resolved.message,
            message: resolved.uiHint == null
                ? resolved.resolutionHint
                : "${resolved.uiHint}\n${resolved.resolutionHint}",
            action: resolved.showRefreshAction
                ? TextButton(
                    onPressed: () async {
                      AppDebug.log("TENANT_DASH", "summary_refresh_tap");
                      await AppRefresh.refreshApp(
                        ref: ref,
                        source: _summaryRefreshSource,
                      );
                    },
                    child: const Text(_summaryRefreshLabel),
                  )
                : null,
          ),
        ),
      ],
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
      resolutionHint: "Try again or contact support if the issue persists.",
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
    final status = summary.status.toLowerCase();
    final paymentStatus = summary.paymentStatus.toLowerCase();
    final bool isApprovedOrActive = status == 'approved' || status == 'active';
    final bool isActive = status == 'active';
    final bool isPaid = paymentStatus == 'paid';
    final payments = summary.paymentsSummary;

    final metricCards = <Widget>[
      if (payments != null)
        AppMetricCard(
          label: "Paid YTD",
          value: formatNgnFromCents(payments.totalPaidKoboYtd),
          helper: "Payments captured this year",
          icon: Icons.calendar_month_outlined,
          accentColor: AppColors.analyticsAccent,
        ),
      if (payments != null)
        AppMetricCard(
          label: "All-time paid",
          value: formatNgnFromCents(payments.totalPaidKoboAllTime),
          helper: "Cumulative confirmed payments",
          icon: Icons.account_balance_wallet_outlined,
          accentColor: AppColors.productionAccent,
        ),
      if (payments != null)
        AppMetricCard(
          label: "Payments this year",
          value: payments.paymentsThisYear.toString(),
          helper: "Confirmed receipt count",
          icon: Icons.receipt_long_outlined,
          accentColor: AppColors.tenantAccent,
        ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        AppResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.page,
            AppSpacing.page,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroCard(
                title: isActive ? "Tenancy active" : "Tenancy overview",
                subtitle: isActive
                    ? "Your rent payment is confirmed and your tenant record is active."
                    : status == 'approved'
                    ? "Your application is approved. Complete payment to activate the tenancy."
                    : "Your application is still moving through review.",
                statusLabel: isPaid ? "PAID" : status.toUpperCase(),
                statusTone: isPaid
                    ? AppStatusTone.success
                    : isApprovedOrActive
                    ? AppStatusTone.info
                    : AppStatusTone.warning,
                agreementLabel: summary.agreementStatus.isEmpty
                    ? null
                    : "Agreement ${summary.agreementStatus.toUpperCase()}",
                agreementTone: summary.agreementStatus.toLowerCase() == 'signed'
                    ? AppStatusTone.success
                    : AppStatusTone.info,
                paidThrough: summary.paidThroughDate,
                nextDue: summary.nextDueDate,
                showReceipt: isPaid,
                onViewReceipt: () {
                  AppDebug.log("TENANT_DASH", "view_receipt_tap");
                  context.go(_tenantPaymentsRoute);
                },
              ),
              if (metricCards.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = AppLayout.columnsForWidth(
                      constraints.maxWidth,
                      compact: 1,
                      medium: 2,
                      large: 3,
                      xlarge: 3,
                    );
                    final spacing = AppSpacing.lg;
                    final width =
                        (constraints.maxWidth - (spacing * (columns - 1))) /
                        columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: metricCards
                          .map((card) => SizedBox(width: width, child: card))
                          .toList(),
                    );
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.section),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 920;

                  final left = Column(
                    children: [
                      _InfoCard(
                        title: "Plan",
                        rows: [
                          ("Unit", summary.unitType, Icons.apartment_outlined),
                          (
                            "Rent",
                            "${formatNgnFromCents(summary.rentAmount.round())} / ${summary.rentPeriod}",
                            Icons.payments_outlined,
                          ),
                          (
                            "Move-in",
                            _fmtDate(summary.moveInDate),
                            Icons.login_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ActionRow(
                        isApprovedOrActive: isApprovedOrActive,
                        isActive: isActive,
                      ),
                    ],
                  );

                  final right = Column(
                    children: [
                      _InfoCard(
                        title: "Important dates",
                        rows: [
                          (
                            "Paid through",
                            _fmtDate(summary.paidThroughDate),
                            Icons.event_available_outlined,
                          ),
                          (
                            "Next due",
                            _fmtDate(summary.nextDueDate),
                            Icons.event_note_outlined,
                          ),
                          (
                            "Last payment",
                            _fmtDate(summary.lastRentPaymentAt),
                            Icons.history_toggle_off_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _MiniTimeline(
                        steps: [
                          const _TimelineStep(label: "Submitted", done: true),
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

                  if (!wide) {
                    return Column(
                      children: [
                        left,
                        const SizedBox(height: AppSpacing.lg),
                        right,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: right),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.section),
              AppSectionCard(
                tone: AppPanelTone.base,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    AppSectionHeader(
                      title: "Need help?",
                      subtitle:
                          "Review your verification details if something looks off, or contact support for tenancy changes.",
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime? dt) {
    return formatDateLabel(dt, fallback: "Not set");
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String statusLabel;
  final AppStatusTone statusTone;
  final String? agreementLabel;
  final AppStatusTone agreementTone;
  final DateTime? paidThrough;
  final DateTime? nextDue;
  final bool showReceipt;
  final VoidCallback? onViewReceipt;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusTone,
    required this.paidThrough,
    required this.nextDue,
    this.agreementLabel,
    this.agreementTone = AppStatusTone.info,
    this.showReceipt = false,
    this.onViewReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppSectionCard(
      tone: AppPanelTone.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatusChip(
                label: statusLabel,
                tone: statusTone,
                icon: Icons.verified_user_outlined,
              ),
              if (agreementLabel != null)
                AppStatusChip(
                  label: agreementLabel!,
                  tone: agreementTone,
                  icon: Icons.description_outlined,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              _StatusValue(
                label: "Paid through",
                value: formatDateLabel(paidThrough, fallback: "Not set"),
              ),
              _StatusValue(
                label: "Next due",
                value: formatDateLabel(nextDue, fallback: "Not set"),
              ),
            ],
          ),
          if (showReceipt) ...[
            const SizedBox(height: AppSpacing.xl),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
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
}

class _ActionRow extends StatelessWidget {
  final bool isApprovedOrActive;
  final bool isActive;

  const _ActionRow({required this.isApprovedOrActive, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Row(
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
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isApprovedOrActive
                ? () {
                    if (isActive) {
                      AppDebug.log("TENANT_DASH", _logCtaReceipts);
                      context.go(_tenantPaymentsRoute);
                      return;
                    }
                    AppDebug.log("TENANT_DASH", "cta_pay");
                    context.go(_tenantVerificationRoute);
                  }
                : null,
            icon: const Icon(Icons.payments),
            label: Text(isActive ? "View receipts" : "Pay rent"),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String, IconData)> rows;

  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIconBadge(icon: rows[index].$3),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[index].$1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        rows[index].$2,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
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

    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Application timeline",
            subtitle:
                "Track where your tenant record is in the approval and activation flow.",
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: List.generate(steps.length, (index) {
              final step = steps[index];
              final badge = AppStatusBadgeColors.fromTheme(
                theme: theme,
                tone: step.done ? AppStatusTone.success : AppStatusTone.neutral,
              );

              return Expanded(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: badge.background,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            step.done
                                ? Icons.check_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: badge.foreground,
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          step.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (index < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(bottom: 26),
                          color: step.done
                              ? AppColors.productionAccent.withValues(
                                  alpha: 0.42,
                                )
                              : colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
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

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
