/// lib/app/features/home/presentation/business_register_help_screen.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Assistance screen for users who need help registering with CAC.
///
/// WHY:
/// - Provides a clear path for customers who are not yet registered.
/// - Keeps the business setup flow explicit and easy to follow.
///
/// HOW:
/// - Renders a short overview and a placeholder CTA area.
/// - Includes a back button to return to the business setup screen.
/// -------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class BusinessRegisterHelpScreen extends StatelessWidget {
  final String accountType;

  const BusinessRegisterHelpScreen({super.key, required this.accountType});

  @override
  Widget build(BuildContext context) {
    final label = _labelForType(accountType);
    final colorScheme = Theme.of(context).colorScheme;
    AppDebug.log(
      "BUSINESS_REGISTER_HELP",
      "build()",
      extra: {"type": accountType, "label": label},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Register with CAC"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_REGISTER_HELP", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            AppDebug.log(
              "BUSINESS_REGISTER_HELP",
              "Navigate -> /business-account",
            );
            context.go('/business-account?type=$accountType');
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              "We can help you register with CAC. We’ll design the assistance "
              "flow next (documents, fees, and timelines).",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // WHY: Use surface tokens to keep CAC help block on-theme.
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.support_agent, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Assistance flow placeholder — we’ll add a CAC request form here.",
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
