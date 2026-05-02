/// lib/app/features/home/presentation/home_bottom_nav.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Bottom navigation bar for the Home screen.
///
/// WHY:
/// - Keeps the customer-facing shell consistent with the new visual system.
/// - Still delegates route changes to the parent screen.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/theme/app_radius.dart';

class HomeBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int cartBadgeCount;
  final bool showTenantTab;
  final bool showBuyerTabs;

  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.cartBadgeCount,
    required this.showTenantTab,
    this.showBuyerTabs = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("HOME_NAV", "build()", extra: {"index": currentIndex});
    final colorScheme = Theme.of(context).colorScheme;
    final chatBadgeCount = ref.watch(chatUnreadCountProvider);

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: "Home",
      ),
      if (showBuyerTabs)
        NavigationDestination(
          icon: _CartIcon(count: cartBadgeCount, selected: false),
          selectedIcon: _CartIcon(count: cartBadgeCount, selected: true),
          label: "Cart",
        ),
      if (showBuyerTabs)
        const NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: "Orders",
        ),
      NavigationDestination(
        icon: _ChatIcon(count: chatBadgeCount, selected: false),
        selectedIcon: _ChatIcon(count: chatBadgeCount, selected: true),
        label: "Chat",
      ),
    ];

    if (showTenantTab) {
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.apartment_outlined),
          selectedIcon: Icon(Icons.apartment_rounded),
          label: "Tenant",
        ),
      );
    }

    destinations.add(
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings_rounded),
        label: "Settings",
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedIndex: currentIndex,
          onDestinationSelected: (index) {
            AppDebug.log("HOME_NAV", "Nav tapped", extra: {"index": index});
            onTap(index);
          },
          destinations: destinations,
        ),
      ),
    );
  }
}

class _ChatIcon extends StatelessWidget {
  final int count;
  final bool selected;

  const _ChatIcon({required this.count, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = selected
        ? Icons.chat_bubble_rounded
        : Icons.chat_bubble_outline_rounded;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: colorScheme.surface, width: 1.2),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
              child: Text(
                count > 99 ? "99+" : "$count",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onError,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _CartIcon extends StatelessWidget {
  final int count;
  final bool selected;

  const _CartIcon({required this.count, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          selected ? Icons.shopping_cart_rounded : Icons.shopping_cart_outlined,
        ),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
              child: Text(
                count > 99 ? "99+" : "$count",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onError,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
