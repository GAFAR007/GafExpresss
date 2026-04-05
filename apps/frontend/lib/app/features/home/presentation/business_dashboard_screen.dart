/// lib/app/features/home/presentation/business_dashboard_screen.dart
/// ---------------------------------------------------------------
/// WHAT:
/// - Business dashboard landing screen for owners/staff.
///
/// WHY:
/// - Frames the business area as an operational command surface instead of a
///   placeholder analytics stub.
/// - Uses real catalog summary data and structured quick actions.
/// ---------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/app_ui.dart';
import 'package:frontend/app/features/home/presentation/business_analytics_models.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/business_profile_action.dart';
import 'package:frontend/app/features/home/presentation/business_staff_routes.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';
import 'package:frontend/app/theme/theme_mode_toggle.dart';

const String _productionActionTap = "production_quick";
const String _staffActionTap = "staff_directory_quick";
const String _preorderOpsActionTap = "preorder_ops_quick";

class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

  void _logTap(String action) {
    AppDebug.log("BUSINESS_DASH", "action_tap", extra: {"action": action});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("BUSINESS_DASH", "build()");
    final role = ref.read(authSessionProvider)?.user.role ?? "";
    final showOwnerPreorderOps = role == "business_owner";
    final summaryAsync = ref.watch(businessAnalyticsSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business dashboard"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_DASH", "back_tap");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/settings');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh",
            onPressed: () async {
              _logTap("refresh");
              await AppRefresh.refreshApp(
                ref: ref,
                source: "business_dashboard_refresh",
              );
            },
          ),
          const BusinessProfileAction(logTag: "BUSINESS_DASH"),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            AppRefresh.refreshApp(ref: ref, source: "business_dashboard_pull"),
        child: ListView(
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
                  _buildHero(context, summaryAsync),
                  const SizedBox(height: AppSpacing.section),
                  _buildPipelineSection(context, summaryAsync),
                  const SizedBox(height: AppSpacing.section),
                  const ThemeModeToggle(source: "business_dashboard"),
                  const SizedBox(height: AppSpacing.section),
                  _buildActionGrid(
                    context,
                    showOwnerPreorderOps: showOwnerPreorderOps,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 2,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  Widget _buildHero(
    BuildContext context,
    AsyncValue<BusinessAnalyticsSummary> summaryAsync,
  ) {
    final summary = summaryAsync.valueOrNull ?? _emptySummary();
    final metrics = [
      (
        label: "Products",
        value: summary.totalProducts.toString(),
        helper: "Total catalog records",
        icon: Icons.inventory_2_outlined,
        accent: AppColors.analyticsAccent,
      ),
      (
        label: "Orders",
        value: summary.totalOrders.toString(),
        helper: "Tracked across the business",
        icon: Icons.receipt_long_outlined,
        accent: AppColors.commerceAccent,
      ),
      (
        label: "Revenue",
        value: formatNgnFromCents(summary.revenueTotal),
        helper: "Captured value across orders",
        icon: Icons.payments_outlined,
        accent: AppColors.tenantAccent,
      ),
      (
        label: "Stock",
        value: summary.totalStock.toString(),
        helper: "Units recorded right now",
        icon: Icons.stacked_line_chart_rounded,
        accent: AppColors.productionAccent,
      ),
    ];

    return AppSectionCard(
      tone: AppPanelTone.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Operations cockpit",
            subtitle:
                "Use this dashboard to review inventory, order flow, revenue, and next actions from one place.",
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: const [
              AppStatusChip(
                label: "Live records",
                tone: AppStatusTone.info,
                icon: Icons.dataset_outlined,
              ),
              AppStatusChip(
                label: "Operational intelligence",
                tone: AppStatusTone.success,
                icon: Icons.auto_graph_rounded,
              ),
              AppStatusChip(
                label: "Action-ready workflows",
                tone: AppStatusTone.warning,
                icon: Icons.playlist_add_check_circle_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = AppLayout.columnsForWidth(
                constraints.maxWidth,
                compact: 1,
                medium: 2,
                large: 4,
                xlarge: 4,
              );
              final spacing = AppSpacing.lg;
              final width =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: metrics.map((metric) {
                  return SizedBox(
                    width: width,
                    child: AppMetricCard(
                      label: metric.label,
                      value: metric.value,
                      helper: metric.helper,
                      icon: metric.icon,
                      accentColor: metric.accent,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          if (summaryAsync.isLoading) ...[
            const SizedBox(height: AppSpacing.lg),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }

  Widget _buildPipelineSection(
    BuildContext context,
    AsyncValue<BusinessAnalyticsSummary> summaryAsync,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = summaryAsync.valueOrNull ?? _emptySummary();
    final statuses = summary.ordersByStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;

        final orderFlow = AppSectionCard(
          tone: AppPanelTone.base,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                title: "Order flow snapshot",
                subtitle:
                    "Read current order statuses without leaving the dashboard.",
              ),
              const SizedBox(height: AppSpacing.lg),
              if (statuses.isEmpty)
                Text(
                  "No order status data available yet.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: statuses.map((entry) {
                    return AppStatusChip(
                      label: "${entry.key}: ${entry.value}",
                      tone: _toneForStatus(entry.key),
                      icon: Icons.insights_outlined,
                    );
                  }).toList(),
                ),
            ],
          ),
        );

        final focus = AppSectionCard(
          tone: AppPanelTone.base,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                title: "Recommended focus",
                subtitle:
                    "Areas that usually need attention when managing daily operations.",
              ),
              const SizedBox(height: AppSpacing.lg),
              _FocusRow(
                icon: Icons.inventory_2_outlined,
                title: "Catalog quality",
                helper:
                    "${summary.activeProducts} active products are visible and ready for review.",
              ),
              const SizedBox(height: AppSpacing.lg),
              _FocusRow(
                icon: Icons.receipt_long_outlined,
                title: "Fulfillment rhythm",
                helper:
                    "${summary.totalOrders} orders are contributing to the current pipeline.",
              ),
              const SizedBox(height: AppSpacing.lg),
              _FocusRow(
                icon: Icons.bar_chart_rounded,
                title: "Revenue visibility",
                helper:
                    "Use product, order, and production modules together to understand performance from record to action.",
              ),
            ],
          ),
        );

        if (!isWide) {
          return Column(
            children: [
              orderFlow,
              const SizedBox(height: AppSpacing.lg),
              focus,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: orderFlow),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: focus),
          ],
        );
      },
    );
  }

  Widget _buildActionGrid(
    BuildContext context, {
    required bool showOwnerPreorderOps,
  }) {
    final actions = <_DashboardAction>[
      _DashboardAction(
        icon: Icons.inventory_2_outlined,
        title: "Products",
        subtitle: "Manage catalog records, stock, and product metadata.",
        accent: AppColors.analyticsAccent,
        onTap: () {
          _logTap("products_quick");
          context.go('/business-products');
        },
      ),
      _DashboardAction(
        icon: Icons.receipt_long_outlined,
        title: "Orders",
        subtitle: "Track fulfillment, payment, and delivery activity.",
        accent: AppColors.commerceAccent,
        onTap: () {
          _logTap("orders_quick");
          context.go('/business-orders');
        },
      ),
      _DashboardAction(
        icon: Icons.warehouse_outlined,
        title: "Assets",
        subtitle: "Review equipment, inventory assets, and owned records.",
        accent: AppColors.recordsAccent,
        onTap: () {
          _logTap("assets_quick");
          context.go('/business-assets');
        },
      ),
      _DashboardAction(
        icon: Icons.agriculture_outlined,
        title: "Farm audit",
        subtitle:
            "Track tools, machinery, and quarterly or yearly equipment reviews.",
        accent: AppColors.productionAccent,
        onTap: () {
          _logTap("farm_audit_quick");
          context.go('/business-assets/farm-audit');
        },
      ),
      _DashboardAction(
        icon: Icons.home_work_outlined,
        title: "Tenants",
        subtitle:
            "Review applications, occupancy signals, and payment context.",
        accent: AppColors.tenantAccent,
        onTap: () {
          _logTap("tenants_quick");
          context.go('/business-tenants');
        },
      ),
      _DashboardAction(
        icon: Icons.eco_outlined,
        title: "Production",
        subtitle: "Plan cycles and move through the production workspace.",
        accent: AppColors.productionAccent,
        onTap: () {
          _logTap(_productionActionTap);
          context.go(productionPlansRoute);
        },
      ),
      _DashboardAction(
        icon: Icons.groups_outlined,
        title: "Staff",
        subtitle: "Open the staff directory and attendance tooling.",
        accent: AppColors.analyticsAccent,
        onTap: () {
          _logTap(_staffActionTap);
          context.go(businessStaffDirectoryRoute);
        },
      ),
      if (showOwnerPreorderOps)
        _DashboardAction(
          icon: Icons.fact_check_outlined,
          title: "Pre-order ops",
          subtitle: "Monitor reserved capacity and active preorder demand.",
          accent: AppColors.commerceAccent,
          onTap: () {
            _logTap(_preorderOpsActionTap);
            context.go(productionPreorderReservationsRoute);
          },
        ),
    ];

    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Action modules",
            subtitle:
                "Jump into the part of the platform you need without losing dashboard context.",
          ),
          const SizedBox(height: AppSpacing.lg),
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
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: actions.map((action) {
                  return SizedBox(
                    width: width,
                    child: AppActionCard(
                      icon: action.icon,
                      title: action.title,
                      subtitle: action.subtitle,
                      onTap: action.onTap,
                      accentColor: action.accent,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  AppStatusTone _toneForStatus(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains("paid") || normalized.contains("delivered")) {
      return AppStatusTone.success;
    }
    if (normalized.contains("pending")) {
      return AppStatusTone.warning;
    }
    if (normalized.contains("cancel")) {
      return AppStatusTone.danger;
    }
    return AppStatusTone.info;
  }

  BusinessAnalyticsSummary _emptySummary() {
    return const BusinessAnalyticsSummary(
      totalProducts: 0,
      activeProducts: 0,
      totalStock: 0,
      totalOrders: 0,
      ordersByStatus: {},
      revenueTotal: 0,
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_DASH", "bottom_nav_tap", extra: {"index": index});
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

class _FocusRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String helper;

  const _FocusRow({
    required this.icon,
    required this.title,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconBadge(icon: icon),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                helper,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _DashboardAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });
}
