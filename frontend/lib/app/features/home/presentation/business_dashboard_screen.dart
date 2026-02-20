/// lib/app/features/home/presentation/business_dashboard_screen.dart
/// ---------------------------------------------------------------
/// WHAT:
/// - Business dashboard landing screen for owners/staff.
///
/// WHY:
/// - Gives verified businesses a clear entry point to manage operations.
/// - Keeps business tooling separate from customer settings.
///
/// HOW:
/// - Displays grouped tiles for products, orders, assets, and staff.
/// - Logs build and taps so we can trace access and usage.
/// ---------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_routes.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/theme/theme_mode_toggle.dart';

// WHY: Keep new production action copy consistent in one place.
const String _productionActionLabel = "Production";
const String _productionActionHelper = "Plan cycles";
const String _productionActionTap = "production_quick";
const String _staffActionLabel = "Staff";
const String _staffActionHelper = "Directory";
const String _staffActionTap = "staff_directory_quick";
const String _preorderOpsActionLabel = "Pre-order Ops";
const String _preorderOpsActionHelper = "Monitor holds";
const String _preorderOpsActionTap = "preorder_ops_quick";

class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

  void _logTap(String action) {
    // WHY: Track which business tool the user intended to open.
    AppDebug.log("BUSINESS_DASH", "Tile tapped", extra: {"action": action});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("BUSINESS_DASH", "build()");
    final role = ref.read(authSessionProvider)?.user.role ?? "";
    final showOwnerPreorderOps = role == "business_owner";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Analytics"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // WHY: Always log navigation so route issues are visible.
            AppDebug.log("BUSINESS_DASH", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/settings');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            onPressed: () {
              _logTap("filters");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Filters coming next.")),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              _logTap("notifications");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Notifications coming next.")),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Business analytics",
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _DashboardChip(
                label: "Dashboard",
                isActive: true,
                onTap: () => _logTap("tab_dashboard"),
              ),
              _DashboardChip(
                label: "Growth",
                onTap: () {
                  _logTap("tab_growth");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Growth tab coming next.")),
                  );
                },
              ),
              _DashboardChip(
                label: "Report",
                onTap: () {
                  _logTap("tab_report");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Report tab coming next.")),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          // WHY: Business owners often switch modes while monitoring analytics.
          const ThemeModeToggle(source: "business_dashboard"),
          const SizedBox(height: 20),
          _AnalyticsCard(
            title: "Sales change overtime",
            metric: "110%",
            subtitle: "Growth in 2026",
            onDetailsTap: () {
              _logTap("analytics_details");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Insights coming next.")),
              );
            },
          ),
          const SizedBox(height: 20),
          _ActionStrip(
            onProductsTap: () {
              _logTap("products_quick");
              context.go('/business-products');
            },
            onOrdersTap: () {
              _logTap("orders_quick");
              context.go('/business-orders');
            },
            onAssetsTap: () {
              _logTap("assets_quick");
              context.go('/business-assets');
            },
            onTenantsTap: () {
              _logTap("tenants_quick");
              context.go('/business-tenants');
            },
            onProductionTap: () {
              _logTap(_productionActionTap);
              context.go(productionPlansRoute);
            },
            onStaffTap: () {
              _logTap(_staffActionTap);
              context.go(businessStaffDirectoryRoute);
            },
            showPreorderMonitoring: showOwnerPreorderOps,
            onPreorderMonitoringTap: () {
              _logTap(_preorderOpsActionTap);
              context.go(productionPreorderReservationsRoute);
            },
          ),
        ],
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 2,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_DASH", "Bottom nav tapped", extra: {"index": index});
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

class _DashboardChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DashboardChip({
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) => onTap(),
      // WHY: Theme tokens keep chips readable in classic/dark/business modes.
      selectedColor: colorScheme.secondaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: isActive
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String metric;
  final String subtitle;
  final VoidCallback onDetailsTap;

  const _AnalyticsCard({
    required this.title,
    required this.metric,
    required this.subtitle,
    required this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // WHY: Use surface tokens so analytics cards adapt per theme.
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            metric,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Center(
              child: Text(
                "Chart data coming soon",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onDetailsTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: const Text("See more insight"),
          ),
        ],
      ),
    );
  }
}

class _ActionStrip extends StatelessWidget {
  final VoidCallback onProductsTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onAssetsTap;
  final VoidCallback onTenantsTap;
  final VoidCallback onProductionTap;
  final VoidCallback onStaffTap;
  final bool showPreorderMonitoring;
  final VoidCallback onPreorderMonitoringTap;

  const _ActionStrip({
    required this.onProductsTap,
    required this.onOrdersTap,
    required this.onAssetsTap,
    required this.onTenantsTap,
    required this.onProductionTap,
    required this.onStaffTap,
    required this.showPreorderMonitoring,
    required this.onPreorderMonitoringTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // WHY: Keep actions in a single list so we can render a scrollable loop.
    final actions = <_ActionItem>[
      _ActionItem(
        icon: Icons.groups_outlined,
        label: _staffActionLabel,
        helper: _staffActionHelper,
        onTap: onStaffTap,
      ),
      _ActionItem(
        icon: Icons.inventory_2_outlined,
        label: "Products",
        helper: "Create and edit",
        onTap: onProductsTap,
      ),
      _ActionItem(
        icon: Icons.receipt_long_outlined,
        label: "Orders",
        helper: "Track fulfillment",
        onTap: onOrdersTap,
      ),
      _ActionItem(
        icon: Icons.warehouse_outlined,
        label: "Assets",
        helper: "Manage equipment",
        onTap: onAssetsTap,
      ),
      _ActionItem(
        icon: Icons.home_work_outlined,
        label: "Tenants",
        helper: "Review requests",
        onTap: onTenantsTap,
      ),
      _ActionItem(
        icon: Icons.eco_outlined,
        label: _productionActionLabel,
        helper: _productionActionHelper,
        onTap: onProductionTap,
      ),
    ];
    if (showPreorderMonitoring) {
      actions.add(
        _ActionItem(
          icon: Icons.fact_check_outlined,
          label: _preorderOpsActionLabel,
          helper: _preorderOpsActionHelper,
          onTap: onPreorderMonitoringTap,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      // WHY: Horizontal scrolling keeps the dashboard compact on small screens.
      child: SizedBox(
        height: 124,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          physics: const BouncingScrollPhysics(),
          itemCount: actions.length,
          separatorBuilder: (context, index) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            return _ActionCircle(action: actions[index]);
          },
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
  });
}

class _ActionCircle extends StatelessWidget {
  final _ActionItem action;

  const _ActionCircle({required this.action});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 110,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // WHY: Circular button makes the strip feel like a quick action wheel.
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    // WHY: Theme shadow keeps contrast consistent in dark mode.
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(action.icon, color: colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              action.helper,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
