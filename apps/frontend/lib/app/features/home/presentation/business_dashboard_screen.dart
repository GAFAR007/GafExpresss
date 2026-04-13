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
import 'package:frontend/app/features/home/presentation/role_access.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/theme/app_theme.dart';
import 'package:frontend/app/theme/theme_mode_toggle.dart';

const String _productionActionTap = "production_quick";
const String _staffActionTap = "staff_directory_quick";
const String _preorderOpsActionTap = "preorder_ops_quick";
const String _requestQueueActionTap = "request_queue_quick";

class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

  void _logTap(String action) {
    AppDebug.log("BUSINESS_DASH", "action_tap", extra: {"action": action});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("BUSINESS_DASH", "build()");
    final session = ref.watch(authSessionProvider);
    final role = session?.user.role ?? "";
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.valueOrNull;
    final staffRole = profileAsync.valueOrNull?.staffRole ?? "";
    final showOwnerPreorderOps = canUseBusinessOwnerEquivalentAccess(
      role: role,
      staffRole: staffRole,
    );
    final showRequestQueueAction = canManageSellerRequests(
      role: role,
      staffRole: staffRole,
    );
    final summaryAsync = ref.watch(businessAnalyticsSummaryProvider);
    final displayName = (profile?.name ?? session?.user.name ?? "").trim();
    final displayEmail = (profile?.email ?? session?.user.email ?? "").trim();
    final workspaceLabel = (profile?.companyName ?? "").trim();
    final accountLabel = _resolveAccountLabel(role);
    final roleLabel = _resolveDashboardRoleLabel(
      role: role,
      staffRole: staffRole,
    );
    final identitySummary = _resolveIdentitySummary(
      role: role,
      roleLabel: roleLabel,
      workspaceLabel: workspaceLabel,
    );
    final profileImageUrl = (profile?.profileImageUrl ?? "").trim();

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
                  _ProfileSnapshotCard(
                    displayName: displayName,
                    displayEmail: displayEmail,
                    accountLabel: accountLabel,
                    roleLabel: roleLabel,
                    workspaceLabel: workspaceLabel,
                    identitySummary: identitySummary,
                    profileImageUrl: profileImageUrl,
                    isLoadingProfile: profileAsync.isLoading,
                  ),
                  const SizedBox(height: AppSpacing.section),
                  _buildHero(context, summaryAsync),
                  const SizedBox(height: AppSpacing.section),
                  _buildPipelineSection(context, summaryAsync),
                  const SizedBox(height: AppSpacing.section),
                  const ThemeModeToggle(source: "business_dashboard"),
                  const SizedBox(height: AppSpacing.section),
                  _buildActionGrid(
                    context,
                    showOwnerPreorderOps: showOwnerPreorderOps,
                    showRequestQueueAction: showRequestQueueAction,
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
    required bool showRequestQueueAction,
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
      if (showRequestQueueAction)
        _DashboardAction(
          icon: Icons.forum_outlined,
          title: "Request queue",
          subtitle:
              "Review buyer purchase requests and step in from customer care.",
          accent: AppColors.commerceAccent,
          onTap: () {
            _logTap(_requestQueueActionTap);
            context.go('/chat');
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

class _ProfileSnapshotCard extends StatelessWidget {
  final String displayName;
  final String displayEmail;
  final String accountLabel;
  final String roleLabel;
  final String workspaceLabel;
  final String identitySummary;
  final String profileImageUrl;
  final bool isLoadingProfile;

  const _ProfileSnapshotCard({
    required this.displayName,
    required this.displayEmail,
    required this.accountLabel,
    required this.roleLabel,
    required this.workspaceLabel,
    required this.identitySummary,
    required this.profileImageUrl,
    required this.isLoadingProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedName = displayName.isNotEmpty ? displayName : "Business user";
    final resolvedEmail = displayEmail.isNotEmpty
        ? displayEmail
        : "Email not available";
    final resolvedWorkspace = workspaceLabel.isNotEmpty
        ? workspaceLabel
        : "Workspace not assigned";
    final initials = _buildInitials(resolvedName);

    return AppSectionCard(
      tone: AppPanelTone.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: "Current profile",
            subtitle:
                "This dashboard is showing the workspace and permissions for the account signed in right now.",
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              final identity = _IdentityPanel(
                resolvedName: resolvedName,
                resolvedEmail: resolvedEmail,
                identitySummary: identitySummary,
                initials: initials,
                profileImageUrl: profileImageUrl,
                isLoadingProfile: isLoadingProfile,
              );
              final detail = _ProfileRoleSummary(
                accountLabel: accountLabel,
                roleLabel: roleLabel,
                workspaceLabel: resolvedWorkspace,
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: AppSpacing.lg),
                    detail,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: identity),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 5, child: detail),
                ],
              );
            },
          ),
          if (isLoadingProfile) ...[
            const SizedBox(height: AppSpacing.lg),
            LinearProgressIndicator(minHeight: 3, color: colorScheme.primary),
          ],
        ],
      ),
    );
  }
}

class _IdentityPanel extends StatelessWidget {
  final String resolvedName;
  final String resolvedEmail;
  final String identitySummary;
  final String initials;
  final String profileImageUrl;
  final bool isLoadingProfile;

  const _IdentityPanel({
    required this.resolvedName,
    required this.resolvedEmail,
    required this.identitySummary,
    required this.initials,
    required this.profileImageUrl,
    required this.isLoadingProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: colorScheme.primaryContainer,
          backgroundImage: profileImageUrl.isNotEmpty
              ? NetworkImage(profileImageUrl)
              : null,
          child: profileImageUrl.isNotEmpty
              ? null
              : Text(
                  initials,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resolvedName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                resolvedEmail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                identitySummary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (isLoadingProfile) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Refreshing account details...",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileRoleSummary extends StatelessWidget {
  final String accountLabel;
  final String roleLabel;
  final String workspaceLabel;

  const _ProfileRoleSummary({
    required this.accountLabel,
    required this.roleLabel,
    required this.workspaceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppStatusChip(
                label: accountLabel,
                tone: AppStatusTone.info,
                icon: Icons.badge_outlined,
              ),
              AppStatusChip(
                label: roleLabel,
                tone: AppStatusTone.success,
                icon: Icons.verified_user_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ProfileSummaryRow(
            label: "Account type",
            value: accountLabel,
            icon: Icons.person_outline,
          ),
          const SizedBox(height: AppSpacing.md),
          _ProfileSummaryRow(
            label: "Active role",
            value: roleLabel,
            icon: Icons.admin_panel_settings_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          _ProfileSummaryRow(
            label: "Workspace",
            value: workspaceLabel,
            icon: Icons.business_outlined,
          ),
        ],
      ),
    );
  }
}

class _ProfileSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProfileSummaryRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconBadge(icon: icon, color: colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
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
        ),
      ],
    );
  }
}

String _resolveAccountLabel(String role) {
  final normalized = role.trim().toLowerCase();
  if (normalized == "staff") {
    return "Staff account";
  }
  if (normalized == "business_owner") {
    return "Business owner account";
  }
  return "Business account";
}

String _resolveDashboardRoleLabel({
  required String role,
  required String staffRole,
}) {
  final normalizedRole = role.trim().toLowerCase();
  if (normalizedRole == "staff" && staffRole.trim().isNotEmpty) {
    return _titleCaseLabel(staffRole);
  }
  return _titleCaseLabel(role);
}

String _resolveIdentitySummary({
  required String role,
  required String roleLabel,
  required String workspaceLabel,
}) {
  final workspace = workspaceLabel.trim().isNotEmpty
      ? workspaceLabel.trim()
      : "your workspace";
  final normalized = role.trim().toLowerCase();

  if (normalized == "staff") {
    return "You are signed in as a staff user. Your current operational role is $roleLabel and this dashboard should follow that role inside $workspace.";
  }
  if (normalized == "business_owner") {
    return "You are signed in as the business owner. This dashboard is showing the main business workspace for $workspace.";
  }
  return "You are signed in to the business workspace for $workspace.";
}

String _titleCaseLabel(String raw) {
  final normalized = raw.trim().replaceAll("_", " ");
  if (normalized.isEmpty) return "Unknown role";
  return normalized
      .split(RegExp(r"\s+"))
      .where((part) => part.isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        return "${lower[0].toUpperCase()}${lower.substring(1)}";
      })
      .join(" ");
}

String _buildInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r"\s+"))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return "BU";
  return parts.map((part) => part.substring(0, 1).toUpperCase()).join();
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
