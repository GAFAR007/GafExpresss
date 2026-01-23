/// lib/app/features/home/presentation/business_account_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Generic business account screen that adapts by account type.
///
/// WHY:
/// - Users need a single entry point for business setup while keeping
///   Settings focused on verification and core profile data.
///
/// HOW:
/// - Accepts an account type string and renders a tailored header.
/// - Provides a back button to return to Settings.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/settings/settings_helpers.dart';
import 'package:frontend/app/features/home/presentation/settings/widgets/nin_id_card.dart';

class BusinessAccountScreen extends ConsumerWidget {
  final String accountType;

  const BusinessAccountScreen({super.key, required this.accountType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // WHY: Translate the stored value into a user-friendly label.
    final label = _labelForType(accountType);
    // WHY: Pull the latest profile so we can show the verified NIN card.
    final profileAsync = ref.watch(userProfileProvider);

    // WHY: Keep phone formatting consistent with Settings.
    const ngPhonePrefix = "+234";
    const ngPhoneDigits = 10;

    // WHY: Log builds to trace navigation issues and UI rendering.
    AppDebug.log(
      "BUSINESS_ACCOUNT",
      "build()",
      extra: {"type": accountType, "label": label},
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // WHY: Track back taps and ensure a safe fallback route.
            AppDebug.log(
              "BUSINESS_ACCOUNT",
              "Back tapped",
              extra: {"type": accountType},
            );
            if (context.canPop()) {
              context.pop();
              return;
            }
            AppDebug.log("BUSINESS_ACCOUNT", "Navigate -> /settings");
            context.go('/settings');
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WHY: Clarify that this screen is tied to the chosen account type.
            Text(
              label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            // WHY: Provide a short placeholder note until the form is designed.
            Text(
              "We’ll design this page next. This screen confirms your "
              "account type and will hold the business setup form.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            // WHY: Show verified identity summary for business users.
            profileAsync.when(
              data: (profile) {
                if (profile == null) {
                  AppDebug.log("BUSINESS_ACCOUNT", "Profile is null");
                  return const Text("Profile not available.");
                }

                if (!profile.isNinVerified) {
                  AppDebug.log(
                    "BUSINESS_ACCOUNT",
                    "NIN not verified",
                    extra: {"userId": profile.id},
                  );
                  return const Text(
                    "Complete NIN verification in Settings to unlock the ID card.",
                  );
                }

                return NinIdCard(
                  firstName: profile.firstName?.trim() ?? '',
                  middleName: profile.middleName?.trim() ?? '',
                  lastName: profile.lastName?.trim() ?? '',
                  dob: profile.dob?.trim() ?? '',
                  email: profile.email.trim(),
                  isEmailVerified: profile.isEmailVerified,
                  phone: formatPhoneDisplay(
                    profile.phone,
                    prefix: ngPhonePrefix,
                    maxDigits: ngPhoneDigits,
                  ),
                  isPhoneVerified: profile.isPhoneVerified,
                  ninLast4: profile.ninLast4,
                  profileImageUrl: profile.profileImageUrl,
                );
              },
              loading: () {
                AppDebug.log("BUSINESS_ACCOUNT", "Profile loading");
                return const Center(child: CircularProgressIndicator());
              },
              error: (error, _) {
                AppDebug.log(
                  "BUSINESS_ACCOUNT",
                  "Profile load failed",
                  extra: {"error": error.toString()},
                );
                return const Text("Unable to load profile right now.");
              },
            ),
            const SizedBox(height: 16),
            // WHY: Give users clear next-step actions.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  AppDebug.log(
                    "BUSINESS_ACCOUNT",
                    "Navigate -> /business-verify",
                    extra: {"type": accountType},
                  );
                  context.go('/business-verify?type=$accountType');
                },
                icon: const Icon(Icons.verified),
                label: const Text("Verify with registration number"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  AppDebug.log(
                    "BUSINESS_ACCOUNT",
                    "Navigate -> /business-register-help",
                    extra: {"type": accountType},
                  );
                  context.go('/business-register-help?type=$accountType');
                },
                icon: const Icon(Icons.support_agent),
                label: const Text("Help me register with CAC"),
              ),
            ),
            const SizedBox(height: 16),
            // WHY: Surface the raw account type for easy debugging.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // WHY: Use surface tokens so info blocks adapt to theme.
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge, color: colorScheme.onSurfaceVariant),
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

  // WHY: Keep a consistent label mapping for business account types.
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
