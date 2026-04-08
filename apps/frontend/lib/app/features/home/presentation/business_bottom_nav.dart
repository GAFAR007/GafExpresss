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
    _BusinessNavItem(icon: Icons.home, label: "Home"),
    _BusinessNavItem(
      icon: Icons.inventory_2_outlined,
      label: "Products",
    ),
    _BusinessNavItem(
      icon: Icons.bar_chart_rounded,
      label: "Dashboard",
    ),
    _BusinessNavItem(
      icon: Icons.receipt_long_outlined,
      label: "Orders",
    ),
    _BusinessNavItem(
      icon: Icons.chat_bubble_outline,
      label: "Chat",
    ),
  ];

  static const _profileItem = _BusinessNavItem(
    icon: Icons.person_outline,
    label: "Profile",
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final isActive = index == currentIndex;

              return Expanded(
                child: _BusinessNavButton(
                  item: item,
                  isActive: isActive,
                  onTap: () {
                    AppDebug.log(
                      "BUSINESS_NAV",
                      "Nav tapped",
                      extra: {"index": index, "label": item.label},
                    );
                    onTap(index);
                  },
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _BusinessNavButton extends StatelessWidget {
  final _BusinessNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _BusinessNavButton({
    required this.item,
    required this.isActive,
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
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer.withValues(alpha: 0.82)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.035),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: isActive
                      ? activeColor.withValues(alpha: 0.22)
                      : colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: 18,
                color: isActive ? colorScheme.onPrimary : inactiveColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isActive ? activeColor : colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: -0.08,
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

  const _BusinessNavItem({
    required this.icon,
    required this.label,
  });
}
