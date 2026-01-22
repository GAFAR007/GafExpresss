/// lib/app/features/home/presentation/business_verified_screen.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Confirmation screen shown after successful business verification.
///
/// WHY:
/// - Gives users clear feedback that verification is complete.
/// - Serves as a destination after the Dojah verification step.
///
/// HOW:
/// - Displays the account type and a verified state summary.
/// - Includes a back button to return to Settings.
/// -------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class BusinessVerifiedScreen extends StatelessWidget {
  final String accountType;

  const BusinessVerifiedScreen({super.key, required this.accountType});

  @override
  Widget build(BuildContext context) {
    final label = _labelForType(accountType);
    AppDebug.log(
      "BUSINESS_VERIFIED",
      "build()",
      extra: {"type": accountType, "label": label},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business verified"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_VERIFIED", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            AppDebug.log("BUSINESS_VERIFIED", "Navigate -> /settings");
            context.go('/settings');
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Text(
                  "Verified",
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              "Your business verification is complete. We’ll display the full "
              "verified profile here when the Dojah integration is live.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Account type: $accountType",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // WHY: Keep labels consistent with account type values.
  String _labelForType(String value) {
    switch (value) {
      case 'sole_proprietorship':
        return 'Business Name';
      case 'partnership':
        return 'Partnership';
      case 'limited_liability_company':
        return 'Limited Liability Company (Ltd)';
      case 'public_limited_company':
        return 'Public Limited Company (Plc)';
      case 'incorporated_trustees':
        return 'Incorporated Trustees / NGO';
      default:
        return 'Business account';
    }
  }
}
