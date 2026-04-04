/// lib/app/features/home/presentation/settings/settings_verification_actions.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Verification actions for email, phone, and NIN.
///
/// WHY:
/// - Keeps SettingsScreen smaller by moving async verification flows out.
///
/// HOW:
/// - Accepts dependencies (controllers, callbacks, formatters) as parameters.
/// - Logs each step and returns control to the caller for UI updates.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

typedef VerificationDialog = Future<String?> Function({
  required String title,
  required String message,
});

typedef ErrorMessageResolver = String Function(Object error);

class SettingsVerificationActions {
  const SettingsVerificationActions();

  Future<void> verifyEmail({
    required BuildContext context,
    required WidgetRef ref,
    required TextEditingController emailCtrl,
    required VerificationDialog openDialog,
    required ErrorMessageResolver errorMessage,
    required void Function(String step, String message, {Map<String, dynamic>? extra})
        logFlow,
  }) async {
    final emailInput = emailCtrl.text.trim();
    logFlow(
      "EMAIL_VERIFY_TAP",
      "Verify email tapped",
      extra: {"email": emailInput},
    );

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Verify email blocked (missing session)");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    if (emailInput.isEmpty) {
      AppDebug.log("SETTINGS", "Verify email blocked (missing email)");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter an email address")),
      );
      return;
    }

    try {
      final api = ref.read(profileApiProvider);
      logFlow("EMAIL_VERIFY_REQUEST", "Requesting email OTP");
      final response = await api.requestEmailVerification(
        token: session.token,
        email: emailInput,
      );
      final recipient =
          response["email"]?.toString().trim() ?? emailCtrl.text.trim();
      logFlow(
        "EMAIL_VERIFY_SENT",
        "Email OTP sent",
        extra: {"email": recipient},
      );

      AppDebug.log(
        "SETTINGS",
        "Email verification sent",
        extra: {"email": recipient},
      );

      if (!context.mounted) return;
      if (recipient.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Code sent to $recipient")),
        );
      }

      if (!context.mounted) return;
      final code = await openDialog(
        title: "Email verification",
        message: "Enter the code sent to your email address.",
      );
      if (code == null) {
        logFlow("EMAIL_VERIFY_CANCEL", "User cancelled email code input");
        return;
      }

      logFlow("EMAIL_VERIFY_CONFIRM", "Confirming email OTP");
      await api.confirmEmailVerification(token: session.token, code: code);

      ref.invalidate(userProfileProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email verified successfully")),
      );
    } catch (e) {
      logFlow(
        "EMAIL_VERIFY_FAIL",
        "Email verification failed",
        extra: {"error": e.toString()},
      );
      if (!context.mounted) return;
      // WHY: Surface backend-provided message so the UI stays dumb.
      final message = errorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> verifyPhone({
    required BuildContext context,
    required WidgetRef ref,
    required TextEditingController phoneCtrl,
    required String ngPhonePrefix,
    required String? Function(String input) normalizePhone,
    required VerificationDialog openDialog,
    required ErrorMessageResolver errorMessage,
    required void Function(String? code) onDebugOtp,
    required void Function(String step, String message, {Map<String, dynamic>? extra})
        logFlow,
  }) async {
    logFlow("PHONE_VERIFY_TAP", "Verify phone tapped");

    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log("SETTINGS", "Verify phone blocked (missing session)");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    final phoneDigits = phoneCtrl.text.trim();
    final normalizedPhone = normalizePhone(phoneDigits);

    if (phoneDigits.isEmpty) {
      logFlow("PHONE_VERIFY_BLOCK", "Missing phone number");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a phone number first")),
      );
      return;
    }

    if (normalizedPhone == null) {
      logFlow("PHONE_VERIFY_BLOCK", "Invalid phone number");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter 10 digits after +234 (e.g. 8012345678)"),
        ),
      );
      return;
    }

    try {
      final api = ref.read(profileApiProvider);
      logFlow("PHONE_VERIFY_REQUEST", "Requesting phone OTP");
      final response = await api.requestPhoneVerification(
        token: session.token,
        phone: normalizedPhone,
      );

      final debugCode = response["code"]?.toString().trim();
      if (debugCode != null && debugCode.isNotEmpty) {
        AppDebug.log(
          "SETTINGS",
          "Phone OTP debug code received",
          extra: {"length": debugCode.length},
        );
        onDebugOtp(debugCode);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("DEV OTP: $debugCode")),
          );
        }
      }

      if (!context.mounted) return;
      final code = await openDialog(
        title: "Phone verification",
        message: "Enter the OTP sent to your phone number.",
      );
      if (code == null) {
        logFlow("PHONE_VERIFY_CANCEL", "User cancelled phone code input");
        return;
      }

      logFlow("PHONE_VERIFY_CONFIRM", "Confirming phone OTP");
      await api.confirmPhoneVerification(token: session.token, code: code);

      ref.invalidate(userProfileProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone verified successfully")),
      );
    } catch (e) {
      logFlow(
        "PHONE_VERIFY_FAIL",
        "Phone verification failed",
        extra: {"error": e.toString()},
      );
      if (!context.mounted) return;
      // WHY: Surface backend-provided message so the UI stays dumb.
      final message = errorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> verifyNin({
    required BuildContext context,
    required WidgetRef ref,
    required TextEditingController ninCtrl,
    required int ninDigits,
    required ErrorMessageResolver errorMessage,
    required void Function(String step, String message, {Map<String, dynamic>? extra})
        logFlow,
  }) async {
    final ninValue = ninCtrl.text.trim();
    logFlow(
      "NIN_VERIFY_TAP",
      "Verify NIN tapped",
      extra: {"length": ninValue.length},
    );

    final session = ref.read(authSessionProvider);
    if (session == null) {
      logFlow("NIN_VERIFY_BLOCK", "Missing session");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    if (ninValue.length != ninDigits) {
      logFlow("NIN_VERIFY_BLOCK", "Invalid NIN length");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("NIN must be 11 digits")),
      );
      return;
    }

    try {
      final api = ref.read(profileApiProvider);
      logFlow("NIN_VERIFY_REQUEST", "Requesting NIN verification");
      await api.verifyNin(token: session.token, nin: ninValue);

      ref.invalidate(userProfileProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("NIN verified successfully")),
      );
    } catch (e) {
      logFlow(
        "NIN_VERIFY_FAIL",
        "NIN verification failed",
        extra: {"error": e.toString()},
      );
      if (!context.mounted) return;
      // WHY: Surface backend-provided message so the UI stays dumb.
      final message = errorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}
