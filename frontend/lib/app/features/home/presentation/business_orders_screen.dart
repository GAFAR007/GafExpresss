/// lib/app/features/home/presentation/business_orders_screen.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Business orders landing screen (placeholder for now).
///
/// WHY:
/// - Gives business users a dedicated route from the bottom nav.
/// - Keeps navigation stable while the full orders UI is built.
///
/// HOW:
/// - Shows a simple message and logs build + taps.
/// - Includes the business bottom nav for quick switching.
/// ----------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';

class BusinessOrdersScreen extends StatelessWidget {
  const BusinessOrdersScreen({super.key});

  void _logTap(String action) {
    AppDebug.log("BUSINESS_ORDERS", "Tap", extra: {"action": action});
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_ORDERS", "build()");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business orders"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_ORDERS", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-dashboard');
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text("Orders dashboard is coming next."),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                _logTap("open_products");
                context.go('/business-products');
              },
              child: const Text("Manage products"),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 3,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_ORDERS", "Bottom nav tapped", extra: {"index": index});
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
