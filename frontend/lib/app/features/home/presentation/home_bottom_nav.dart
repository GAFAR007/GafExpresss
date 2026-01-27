/// lib/app/features/home/presentation/home_bottom_nav.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Bottom navigation bar for the Home screen.
///
/// WHY:
/// - Matches the reference layout and improves navigation.
/// - Keeps HomeScreen layout clean by extracting the widget.
///
/// HOW:
/// - Renders a BottomNavigationBar with existing app routes.
/// - Parent handles actual navigation to keep routing centralized.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class HomeBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int cartBadgeCount;
  final bool showTenantTab;

  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.cartBadgeCount,
    required this.showTenantTab,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_NAV", "build()", extra: {"index": currentIndex});
    final colorScheme = Theme.of(context).colorScheme;

    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.home),
        label: "Home",
      ),
      BottomNavigationBarItem(
        icon: Stack(
          children: [
            const Icon(Icons.shopping_cart),
            if (cartBadgeCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  // WHY: Count signals unseen cart items.
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    cartBadgeCount > 99 ? "99+" : "$cartBadgeCount",
                    style: TextStyle(
                      color: colorScheme.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        label: "Cart",
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.receipt_long),
        label: "Orders",
      ),
    ];

    if (showTenantTab) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.apartment),
          label: "Tenant",
        ),
      );
    }

    items.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: "Settings",
      ),
    );

    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        AppDebug.log("HOME_NAV", "Nav tapped", extra: {"index": index});
        // WHY: Delegate navigation to the parent so routing stays centralized.
        onTap(index);
      },
      items: items,
    );
  }
}
