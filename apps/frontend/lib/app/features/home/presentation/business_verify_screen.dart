/// lib/app/features/home/presentation/business_verify_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Business registration verification screen (Dojah flow placeholder).
///
/// WHY:
/// - Lets users enter a registration number before we wire Dojah.
/// - Provides a clear path to "verified business" after validation.
///
/// HOW:
/// - Renders a form with a single registration input and Verify button.
/// - On verify, logs intent and navigates to /business-verified.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class BusinessVerifyScreen extends StatefulWidget {
  final String accountType;

  const BusinessVerifyScreen({super.key, required this.accountType});

  @override
  State<BusinessVerifyScreen> createState() => _BusinessVerifyScreenState();
}

class _BusinessVerifyScreenState extends State<BusinessVerifyScreen> {
  // WHY: Keep the input stable while the user edits.
  final _regNumberCtrl = TextEditingController();
  bool _isVerifying = false;

  @override
  void dispose() {
    // WHY: Prevent memory leaks from controllers.
    _regNumberCtrl.dispose();
    super.dispose();
  }

  void _onVerifyTap() {
    final regNumber = _regNumberCtrl.text.trim();
    AppDebug.log(
      "BUSINESS_VERIFY",
      "Verify tapped",
      extra: {
        "type": widget.accountType,
        "length": regNumber.length,
      },
    );

    // WHY: Block empty input until Dojah integration is wired.
    if (regNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a registration number to verify")),
      );
      return;
    }

    setState(() => _isVerifying = true);

    // WHY: Placeholder flow until Dojah API is integrated.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      AppDebug.log(
        "BUSINESS_VERIFY",
        "Navigate -> /business-verified",
        extra: {"type": widget.accountType},
      );
      context.go('/business-verified?type=${widget.accountType}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _labelForType(widget.accountType);
    AppDebug.log(
      "BUSINESS_VERIFY",
      "build()",
      extra: {"type": widget.accountType, "label": label},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify business"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_VERIFY", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            AppDebug.log("BUSINESS_VERIFY", "Navigate -> /business-account");
            context.go('/business-account?type=${widget.accountType}');
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              "Enter your CAC registration number to verify your business.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _regNumberCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: "Registration number",
                hintText: "e.g. BN 1234567 or RC 1234567",
              ),
              onChanged: (value) {
                // WHY: Log changes without storing sensitive values.
                AppDebug.log(
                  "BUSINESS_VERIFY",
                  "Registration input changed",
                  extra: {"length": value.trim().length},
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _onVerifyTap,
                child: Text(_isVerifying ? "Verifying..." : "Verify"),
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
