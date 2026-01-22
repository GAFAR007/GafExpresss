/// lib/app/features/home/presentation/business_assets_screen.dart
/// --------------------------------------------------------------
/// WHAT:
/// - Business assets landing screen (placeholder for now).
///
/// WHY:
/// - Keeps the assets route reachable from the dashboard.
/// - Lets us wire navigation before the full assets UI is built.
///
/// HOW:
/// - Shows a simple message and logs build + taps.
/// - Includes the business bottom nav for quick switching.
/// --------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';

class BusinessAssetsScreen extends StatelessWidget {
  const BusinessAssetsScreen({super.key});

  void _logTap(String action) {
    AppDebug.log("BUSINESS_ASSETS", "Tap", extra: {"action": action});
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_ASSETS", "build()");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business assets"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_ASSETS", "Back tapped");
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
            Icon(Icons.warehouse_outlined, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text("Assets dashboard is coming next."),
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
        currentIndex: 2,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_ASSETS", "Bottom nav tapped", extra: {"index": index});
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
