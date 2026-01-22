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
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';

class BusinessDashboardScreen extends StatelessWidget {
  const BusinessDashboardScreen({super.key});

  void _logTap(String action) {
    // WHY: Track which business tool the user intended to open.
    AppDebug.log("BUSINESS_DASH", "Tile tapped", extra: {"action": action});
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_DASH", "build()");

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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
            onTeamTap: () {
              _logTap("team_roles_quick");
              context.go('/business-team');
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
    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) => onTap(),
      selectedColor: Colors.green.shade100,
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isActive ? Colors.green.shade700 : Colors.grey.shade700,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F4EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7E0D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            metric,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE7E0D6)),
            ),
            child: Center(
              child: Text(
                "Chart data coming soon",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onDetailsTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green.shade700,
              side: BorderSide(color: Colors.green.shade200),
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
  final VoidCallback onTeamTap;

  const _ActionStrip({
    required this.onProductsTap,
    required this.onOrdersTap,
    required this.onAssetsTap,
    required this.onTeamTap,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Keep actions in a single list so we can render a scrollable loop.
    final actions = [
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
        icon: Icons.badge_outlined,
        label: "Team roles",
        helper: "Staff access",
        onTap: onTeamTap,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
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
          separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green.shade100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(action.icon, color: Colors.green.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              action.helper,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
