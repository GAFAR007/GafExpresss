/// lib/app/features/home/presentation/business_bottom_nav.dart
/// ----------------------------------------------------------
/// WHAT:
/// - Bottom navigation bar for business tools.
///
/// WHY:
/// - Matches the requested analytics-style layout.
/// - Keeps business pages reachable while preserving Home/Profile buttons.
///
/// HOW:
/// - Renders a custom row of icons with a highlighted center action.
/// - Parent screens handle navigation via callbacks.
///
/// DEBUGGING:
/// - Logs build and nav taps for traceability.
/// ----------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class BusinessBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BusinessBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _BusinessNavItem(
      icon: Icons.home,
      label: "Home",
      helper: "Browse",
    ),
    _BusinessNavItem(
      icon: Icons.inventory_2_outlined,
      label: "Products",
      helper: "Inventory",
    ),
    _BusinessNavItem(
      icon: Icons.bar_chart_rounded,
      label: "Dashboard",
      helper: "Insights",
    ),
    _BusinessNavItem(
      icon: Icons.receipt_long_outlined,
      label: "Orders",
      helper: "Fulfill",
    ),
    _BusinessNavItem(
      icon: Icons.chat_bubble_outline,
      label: "Chat",
      helper: "Talk",
    ),
    _BusinessNavItem(
      icon: Icons.person_outline,
      label: "Profile",
      helper: "Settings",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_NAV", "build()", extra: {"index": currentIndex});
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        // WHY: Use surface tokens so the nav adapts to each theme mode.
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            // WHY: Theme shadow keeps elevation subtle in dark mode.
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (index) {
          final item = _items[index];
          final isActive = index == currentIndex;
          final isCenter = index == 2;

          return _BusinessNavButton(
            item: item,
            isActive: isActive,
            isCenter: isCenter,
            onTap: () {
              AppDebug.log(
                "BUSINESS_NAV",
                "Nav tapped",
                extra: {"index": index, "label": item.label},
              );
              onTap(index);
            },
          );
        }),
      ),
    );
  }
}

class _BusinessNavButton extends StatelessWidget {
  final _BusinessNavItem item;
  final bool isActive;
  final bool isCenter;
  final VoidCallback onTap;

  const _BusinessNavButton({
    required this.item,
    required this.isActive,
    required this.isCenter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(isCenter ? 14 : 8),
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor
                  : isCenter
                      ? colorScheme.primaryContainer
                      // WHY: Keep transparent but tied to theme tokens.
                      : colorScheme.surface.withOpacity(0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              size: isCenter ? 22 : 20,
              color: isActive ? colorScheme.onPrimary : inactiveColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isActive ? activeColor : inactiveColor,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            item.helper,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 9,
                ),
          ),
        ],
      ),
    );
  }
}

class _BusinessNavItem {
  final IconData icon;
  final String label;
  final String helper;

  const _BusinessNavItem({
    required this.icon,
    required this.label,
    required this.helper,
  });
}
