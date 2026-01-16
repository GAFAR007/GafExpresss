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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class PaymentSuccessScreen extends StatelessWidget {
  final String reference;

  const PaymentSuccessScreen({super.key, required this.reference});

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "PAYMENT_SUCCESS",
      "build()",
      extra: {"reference": reference},
    );

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
            if (reference.isNotEmpty)
              Text(
                "Reference: $reference",
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
                    AppDebug.log("PAYMENT_SUCCESS", "View Orders tapped");
                    context.go("/orders");
                  },
                  child: const Text("View Orders"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
