/// lib/app/features/home/presentation/settings/settings_address_actions.dart
/// -------------------------------------------------------------------------
/// WHAT:
/// - Address verification actions for Settings (home/company).
///
/// WHY:
/// - Keeps SettingsScreen smaller and reusable across address sections.
/// - Centralizes backend calls + error handling for address verification.
///
/// HOW:
/// - Validates session.
/// - Calls ProfileApi.verifyAddress().
/// - Refreshes userProfileProvider and shows feedback.
/// -------------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

typedef ErrorMessageResolver = String Function(Object error);

class SettingsAddressActions {
  const SettingsAddressActions();

  Future<void> verifyAddress({
    required BuildContext context,
    required WidgetRef ref,
    required String type,
    required UserAddress address,
    String? placeId,
    required ErrorMessageResolver errorMessage,
    required void Function(String step, String message,
            {Map<String, dynamic>? extra})
        logFlow,
  }) async {
    logFlow(
      "ADDRESS_VERIFY_TAP",
      "Verify address tapped",
      extra: {"type": type},
    );

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Address verify blocked (missing session)");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    try {
      final api = ref.read(profileApiProvider);
      logFlow("ADDRESS_VERIFY_REQUEST", "Requesting address verification");

      await api.verifyAddress(
        token: session.token,
        type: type,
        address: address,
        placeId: placeId,
      );

      ref.invalidate(userProfileProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${type.toUpperCase()} address verified")),
      );
    } catch (e) {
      logFlow(
        "ADDRESS_VERIFY_FAIL",
        "Address verification failed",
        extra: {"error": e.toString(), "type": type},
      );
      if (!context.mounted) return;
      final message = errorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}
