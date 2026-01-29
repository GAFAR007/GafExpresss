/// lib/app/features/home/presentation/payment_success_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Payment success landing screen.
///
/// WHY:
/// - Paystack redirects here after payment.
/// - Tells user that backend will confirm via webhook.
///
/// HOW:
/// - Reads reference from route query params.
/// - Offers navigation to Home and Orders.
///
/// DEBUGGING:
/// - Logs build and button taps.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class PaymentSuccessScreen extends StatefulWidget {
  final String reference;
  final String? nextRoute;

  const PaymentSuccessScreen({
    super.key,
    required this.reference,
    this.nextRoute,
  });

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  bool _redirectHandled = false;

  @override
  void initState() {
    super.initState();

    final next = widget.nextRoute?.trim() ?? "";
    if (next.isEmpty) return;

    // WHY: Auto-redirect tenants to their dashboard after successful payment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _redirectHandled) return;
      _redirectHandled = true;
      AppDebug.log(
        "PAYMENT_SUCCESS",
        "Auto-redirect to next route",
        extra: {"next": next},
      );
      context.go(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "PAYMENT_SUCCESS",
      "build()",
      extra: {"hasReference": widget.reference.isNotEmpty},
    );

    final next = widget.nextRoute?.trim() ?? "";

    return Scaffold(
      appBar: AppBar(title: const Text("Payment Received")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Thanks! Your payment is processing.",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              "We will confirm your order once the Paystack webhook arrives.",
            ),
            const SizedBox(height: 12),
            if (widget.reference.isNotEmpty)
              Text(
                "Reference: ${widget.reference}",
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    AppDebug.log("PAYMENT_SUCCESS", "Go Home tapped");
                    context.go("/home");
                  },
                  child: const Text("Go Home"),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    AppDebug.log(
                      "PAYMENT_SUCCESS",
                      "View next tapped",
                      extra: {"next": next.isEmpty ? "/orders" : next},
                    );
                    context.go(next.isEmpty ? "/orders" : next);
                  },
                  child: Text(next.isEmpty ? "View Orders" : "Continue"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
