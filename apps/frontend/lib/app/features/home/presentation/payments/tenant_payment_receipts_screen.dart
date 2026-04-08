/// lib/app/features/home/presentation/payments/tenant_payment_receipts_screen.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Tenant-facing payment receipts screen.
///
/// WHY:
/// - Lets tenants review rent receipts without opening verification flows.
///
/// HOW:
/// - Uses tenantPaymentHistoryProvider to fetch receipts.
/// - Renders summary + payment list with clear states.
/// - Logs build, refresh, and receipt taps.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_model.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_providers.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_widgets.dart';

// WHY: Centralize UI strings to avoid inline magic values.
const String _screenTitle = "Payment receipts";
const String _logTag = "TENANT_RECEIPTS";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_action";
const String _refreshPull = "refresh_pull";
const String _backTap = "back_tap";
const String _receiptTap = "receipt_tap";
const String _homeRoute = "/home";
const String _summaryTitle = "Your payment summary";
const String _refreshTooltip = "Refresh";
const String _refreshErrorAction = "Retry loading receipts";
const String _extraPaymentIdKey = "paymentId";
const String _extraHasReceiptKey = "hasReceiptUrl";

// WHY: Keep spacing consistent across screen sections.
const double _pagePadding = 16;
const double _sectionSpacing = 16;

class TenantPaymentReceiptsScreen extends ConsumerWidget {
  const TenantPaymentReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage);
    final paymentsAsync = ref.watch(tenantPaymentHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log(_logTag, _backTap);
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(_homeRoute);
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              AppDebug.log(_logTag, _refreshAction);
              // WHY: Force a refresh when the user taps the toolbar action.
              ref.invalidate(tenantPaymentHistoryProvider);
            },
            icon: const Icon(Icons.refresh),
            tooltip: _refreshTooltip,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(_logTag, _refreshPull);
          // WHY: Allow pull-to-refresh without leaving the screen.
          final _ = await ref.refresh(tenantPaymentHistoryProvider.future);
        },
        child: paymentsAsync.when(
          data: (response) => _TenantReceiptBody(
            response: response,
            onReceiptTap: (item) {
              AppDebug.log(
                _logTag,
                _receiptTap,
                extra: {
                  _extraPaymentIdKey: item.id,
                  _extraHasReceiptKey: item.receiptUrl != null,
                },
              );
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => PaymentHistoryErrorState(
            error: err,
            onRetry: () {
              AppDebug.log(_logTag, _refreshErrorAction);
              // WHY: Invalidate to trigger a clean refetch after errors.
              ref.invalidate(tenantPaymentHistoryProvider);
            },
          ),
        ),
      ),
    );
  }
}

class _TenantReceiptBody extends StatelessWidget {
  final PaymentHistoryResponse response;
  final ValueChanged<PaymentHistoryItem> onReceiptTap;

  const _TenantReceiptBody({
    required this.response,
    required this.onReceiptTap,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Scrollable layout keeps summary and history accessible on small screens.
    return ListView(
      padding: const EdgeInsets.all(_pagePadding),
      children: [
        // WHY: Summary helps tenants understand yearly limits at a glance.
        PaymentSummaryCard(summary: response.summary, title: _summaryTitle),
        const SizedBox(height: _sectionSpacing),
        // WHY: Show full payment history so tenants can confirm coverage.
        PaymentHistoryList(
          items: response.payments,
          onViewReceipt: onReceiptTap,
        ),
      ],
    );
  }
}
