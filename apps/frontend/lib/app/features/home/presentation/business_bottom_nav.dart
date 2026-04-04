/// lib/app/features/home/presentation/business_bottom_nav.dart
/// ----------------------------------------------------------
/// WHAT:
/// - Bottom navigation bar for business tools.
///
/// WHY:
/// - Matches the requested analytics-style layout.
/// - Keeps business pages reachable while profile lives in the app bar.
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
import 'package:frontend/app/theme/app_radius.dart';

class BusinessBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool showProfileItem;

  const BusinessBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.showProfileItem = false,
  });

  static const _baseItems = [
    _BusinessNavItem(icon: Icons.home, label: "Home", helper: "Browse"),
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
  ];

  static const _profileItem = _BusinessNavItem(
    icon: Icons.person_outline,
    label: "Profile",
    helper: "Settings",
  );

  List<_BusinessNavItem> get _items => [
    ..._baseItems,
    if (showProfileItem) _profileItem,
  ];

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_NAV", "build()", extra: {"index": currentIndex});
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
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
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isCenter ? 92 : 82,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer
              : isCenter
              ? colorScheme.surfaceContainerLow
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.all(isCenter ? 11 : 8),
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor
                    : isCenter
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Icon(
                item.icon,
                size: isCenter ? 20 : 18,
                color: isActive
                    ? colorScheme.onPrimary
                    : isCenter
                    ? colorScheme.primary
                    : inactiveColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isActive ? activeColor : colorScheme.onSurface,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.helper,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.84),
                fontSize: 9.5,
              ),
            ),
          ],
        ),
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
