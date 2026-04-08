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
/// - Polls verification status and displays payment/order/reservation states.
/// - Offers optional manual reservation confirm fallback for allowed roles.
///
/// DEBUGGING:
/// - Logs build and button taps.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/auth_session.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/order_api.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  final String reference;
  final String? nextRoute;

  const PaymentSuccessScreen({
    super.key,
    required this.reference,
    this.nextRoute,
  });

  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  bool _redirectHandled = false;
  bool _isVerifying = false;
  bool _isManualConfirming = false;
  int _pollAttempt = 0;
  int _pollMaxAttempts = 0;
  String _paymentStatus = "";
  String _orderStatus = "";
  String _orderId = "";
  String _reservationStatus = "";
  String _reservationId = "";
  String _verificationMessage = "";
  bool _verificationFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapPaymentSuccess();
    });
  }

  Future<void> _bootstrapPaymentSuccess() async {
    await _pollPaymentConfirmationStatus();

    final next = widget.nextRoute?.trim() ?? "";
    if (next.isEmpty || !mounted || _redirectHandled) {
      return;
    }

    // WHY: Auto-redirect tenants to their dashboard after successful payment.
    _redirectHandled = true;
    // WHY: Refresh payment-sensitive views before redirecting.
    await AppRefresh.refreshApp(
      ref: ref,
      source: "payment_success_auto_redirect",
    );
    if (!mounted) return;
    AppDebug.log(
      "PAYMENT_SUCCESS",
      "Auto-redirect to next route",
      extra: {"next": next},
    );
    context.go(next);
  }

  Future<void> _pollPaymentConfirmationStatus() async {
    final reference = widget.reference.trim();
    if (reference.isEmpty) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) return;
      setState(() {
        _verificationFailed = true;
        _verificationMessage =
            "Sign in to verify payment status for reference $reference.";
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isVerifying = true;
        _pollAttempt = 0;
        _pollMaxAttempts = 6;
        _verificationFailed = false;
        _verificationMessage = "";
      });
    }

    try {
      final api = ref.read(orderApiProvider);
      PaystackVerifyResult? latestResult;

      for (var attempt = 1; attempt <= 6; attempt += 1) {
        final result = await api.verifyPaystackCheckout(
          token: session.token,
          reference: reference,
        );
        latestResult = result;

        if (!mounted) return;
        setState(() {
          _pollAttempt = attempt;
          _paymentStatus = result.status;
          _orderStatus = result.orderStatus ?? "";
          _orderId = result.orderId ?? "";
          _reservationStatus = result.reservationStatus ?? "";
          _reservationId = result.reservationId ?? "";
          _verificationFailed = false;
          _verificationMessage = _buildPollingMessage(
            result: result,
            attempt: attempt,
            maxAttempts: 6,
          );
        });

        if (result.isFullyConfirmed) {
          break;
        }

        if (attempt < 6) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      await AppRefresh.refreshApp(
        ref: ref,
        source: "payment_success_verify_paystack",
      );

      if (!mounted) return;
      if (latestResult == null) {
        setState(() {
          _verificationFailed = true;
          _verificationMessage =
              "Unable to verify payment status yet. Webhook confirmation is still in progress.";
        });
      }
    } catch (error) {
      AppDebug.log(
        "PAYMENT_SUCCESS",
        "verifyPaystackCheckout failed",
        extra: {
          "error": error.toString(),
          "hasReference": reference.isNotEmpty,
        },
      );
      if (!mounted) return;
      setState(() {
        _verificationFailed = true;
        _verificationMessage =
            "We received your redirect, but verification is still pending. "
            "Webhook confirmation will continue in the background. "
            "You can safely check Orders in a moment.";
      });
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  String _buildPollingMessage({
    required PaystackVerifyResult result,
    required int attempt,
    required int maxAttempts,
  }) {
    final status = result.status.toLowerCase();
    if (result.isFullyConfirmed) {
      return "Payment and order confirmation completed.";
    }
    if (status == "failed") {
      return "Payment is marked failed. If you were debited, contact support.";
    }
    if (status == "success") {
      return "Payment success received. Waiting for final order/reservation sync ($attempt/$maxAttempts).";
    }
    return "Payment status is still pending ($attempt/$maxAttempts).";
  }

  bool _isOrderTerminalConfirmed(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == "paid" ||
        normalized == "shipped" ||
        normalized == "delivered";
  }

  bool _canShowManualConfirm(AuthSession? session) {
    final role = (session?.user.role ?? "").trim().toLowerCase();
    final roleAllowed = role == "customer" || role == "business_owner";
    if (!roleAllowed) {
      return false;
    }
    if (_reservationId.trim().isEmpty) {
      return false;
    }
    if (_reservationStatus.toLowerCase() != "reserved") {
      return false;
    }
    if (_paymentStatus.toLowerCase() != "success") {
      return false;
    }
    if (!_isOrderTerminalConfirmed(_orderStatus)) {
      return false;
    }
    return true;
  }

  Future<void> _manualConfirmReservation() async {
    if (_isManualConfirming) {
      return;
    }
    final reservationId = _reservationId.trim();
    if (reservationId.isEmpty) {
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      if (!mounted) return;
      setState(() {
        _verificationFailed = true;
        _verificationMessage = "Sign in to perform manual reservation confirm.";
      });
      return;
    }

    final role = session.user.role.trim().toLowerCase();
    if (role != "customer" && role != "business_owner") {
      if (!mounted) return;
      setState(() {
        _verificationFailed = true;
        _verificationMessage =
            "Your role cannot run manual reservation confirm.";
      });
      return;
    }

    setState(() => _isManualConfirming = true);
    try {
      final api = ref.read(orderApiProvider);
      final result = await api.confirmPreorderReservation(
        token: session.token,
        reservationId: reservationId,
      );

      await AppRefresh.refreshApp(
        ref: ref,
        source: "payment_success_manual_reservation_confirm",
      );

      if (!mounted) return;
      setState(() {
        _reservationStatus = result.status;
        _verificationFailed = false;
        _verificationMessage = result.idempotent
            ? "Reservation already confirmed."
            : "Reservation confirmed manually.";
      });
    } catch (error) {
      AppDebug.log(
        "PAYMENT_SUCCESS",
        "manual reservation confirm failed",
        extra: {"error": error.toString(), "reservationId": reservationId},
      );
      if (!mounted) return;
      setState(() {
        _verificationFailed = true;
        _verificationMessage = "Manual reservation confirm failed: $error";
      });
    } finally {
      if (mounted) {
        setState(() => _isManualConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "PAYMENT_SUCCESS",
      "build()",
      extra: {"hasReference": widget.reference.isNotEmpty},
    );

    final next = widget.nextRoute?.trim() ?? "";
    final session = ref.watch(authSessionProvider);
    final canShowManualConfirm = _canShowManualConfirm(session);

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
            const SizedBox(height: 12),
            _StatusLine(
              label: "Payment status",
              value: _paymentStatus.isEmpty ? "-" : _paymentStatus,
            ),
            _StatusLine(
              label: "Order status",
              value: _orderStatus.isEmpty ? "-" : _orderStatus,
            ),
            _StatusLine(
              label: "Reservation status",
              value: _reservationStatus.isEmpty ? "-" : _reservationStatus,
            ),
            if (_orderId.isNotEmpty)
              _StatusLine(label: "Order id", value: _orderId),
            if (_reservationId.isNotEmpty)
              _StatusLine(label: "Reservation id", value: _reservationId),
            if (_pollMaxAttempts > 0)
              _StatusLine(
                label: "Sync attempts",
                value: "$_pollAttempt/$_pollMaxAttempts",
              ),
            if (_isVerifying) ...[
              const SizedBox(height: 12),
              const Text("Verifying payment status..."),
            ],
            if (_verificationMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _verificationMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: _verificationFailed
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ],
            if (canShowManualConfirm) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isManualConfirming
                    ? null
                    : _manualConfirmReservation,
                child: Text(
                  _isManualConfirming
                      ? "Confirming reservation..."
                      : "Manual reservation confirm",
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Fallback only: use this if payment is successful but reservation is still reserved.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                  onPressed: () async {
                    AppDebug.log(
                      "PAYMENT_SUCCESS",
                      "View next tapped",
                      extra: {"next": next.isEmpty ? "/orders" : next},
                    );
                    // WHY: Refresh before leaving payment success.
                    await AppRefresh.refreshApp(
                      ref: ref,
                      source: "payment_success_continue",
                    );
                    if (!context.mounted) return;
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

class _StatusLine extends StatelessWidget {
  final String label;
  final String value;

  const _StatusLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text("$label: $value"),
    );
  }
}
