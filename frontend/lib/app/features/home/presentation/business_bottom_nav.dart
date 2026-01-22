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
      icon: Icons.person_outline,
      label: "Profile",
      helper: "Settings",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_NAV", "build()", extra: {"index": currentIndex});

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
    final activeColor = const Color(0xFF0F9D58);
    final inactiveColor = Colors.grey.shade500;

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
                      ? Colors.green.shade50
                      : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              size: isCenter ? 22 : 20,
              color: isActive ? Colors.white : inactiveColor,
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
                  color: Colors.grey.shade400,
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
