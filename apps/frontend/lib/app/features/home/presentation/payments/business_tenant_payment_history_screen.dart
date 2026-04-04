/// lib/app/features/home/presentation/payments/business_tenant_payment_history_screen.dart
/// ---------------------------------------------------------------------------------
/// WHAT:
/// - Business-facing tenant payment history screen.
///
/// WHY:
/// - Lets owners/staff review tenant receipts without overloading review screens.
///
/// HOW:
/// - Uses businessTenantPaymentHistoryProvider with tenant id.
/// - Renders summary + payment list and logs key actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_model.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_providers.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_widgets.dart';

// WHY: Centralize UI copy and log tags to avoid inline magic strings.
const String _screenTitle = "Tenant payments";
const String _summaryTitle = "Tenant payment summary";
const String _logTag = "BUSINESS_PAYMENTS";
const String _buildMessage = "build()";
const String _refreshAction = "refresh_action";
const String _refreshPull = "refresh_pull";
const String _backTap = "back_tap";
const String _receiptTap = "receipt_tap";
const String _refreshTooltip = "Refresh";
const String _fallbackRoute = "/business-tenants";
const String _refreshErrorAction = "Retry loading payments";
const String _emptyString = "";
const String _titleSeparator = " - ";
const String _extraTenantIdKey = "tenantId";
const String _extraPaymentIdKey = "paymentId";
const String _extraHasReceiptKey = "hasReceiptUrl";

// WHY: Keep spacing consistent across screen sections.
const double _pagePadding = 16;
const double _sectionSpacing = 16;

class BusinessTenantPaymentHistoryScreen extends ConsumerWidget {
  final String tenantId;
  final String? tenantName;

  const BusinessTenantPaymentHistoryScreen({
    super.key,
    required this.tenantId,
    this.tenantName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log(_logTag, _buildMessage, extra: {_extraTenantIdKey: tenantId});
    final paymentsAsync = ref.watch(
      businessTenantPaymentHistoryProvider(tenantId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleText()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log(
              _logTag,
              _backTap,
              extra: {_extraTenantIdKey: tenantId},
            );
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(_fallbackRoute);
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              AppDebug.log(
                _logTag,
                _refreshAction,
                extra: {_extraTenantIdKey: tenantId},
              );
              // WHY: Allow manual refresh without leaving the screen.
              ref.invalidate(businessTenantPaymentHistoryProvider(tenantId));
            },
            icon: const Icon(Icons.refresh),
            tooltip: _refreshTooltip,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(
            _logTag,
            _refreshPull,
            extra: {_extraTenantIdKey: tenantId},
          );
          // WHY: Allow pull-to-refresh for quick updates.
          final _ = await ref.refresh(
            businessTenantPaymentHistoryProvider(tenantId).future,
          );
        },
        child: paymentsAsync.when(
          data: (response) => _BusinessPaymentBody(
            response: response,
            onReceiptTap: (item) {
              AppDebug.log(
                _logTag,
                _receiptTap,
                extra: {
                  _extraTenantIdKey: tenantId,
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
              AppDebug.log(
                _logTag,
                _refreshErrorAction,
                extra: {_extraTenantIdKey: tenantId},
              );
              // WHY: Invalidate to trigger a clean refetch after errors.
              ref.invalidate(businessTenantPaymentHistoryProvider(tenantId));
            },
          ),
        ),
      ),
    );
  }

  String _titleText() {
    // WHY: Prefer showing tenant name when available.
    final safeName = tenantName?.trim() ?? _emptyString;
    if (safeName.isEmpty) {
      return _screenTitle;
    }
    return "$_screenTitle$_titleSeparator$safeName";
  }
}

class _BusinessPaymentBody extends StatelessWidget {
  final PaymentHistoryResponse response;
  final ValueChanged<PaymentHistoryItem> onReceiptTap;

  const _BusinessPaymentBody({
    required this.response,
    required this.onReceiptTap,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Scrollable layout keeps summary and history visible on small screens.
    return ListView(
      padding: const EdgeInsets.all(_pagePadding),
      children: [
        // WHY: Summary shows yearly payment progress for owner review.
        PaymentSummaryCard(summary: response.summary, title: _summaryTitle),
        const SizedBox(height: _sectionSpacing),
        // WHY: History list shows each successful rent payment.
        PaymentHistoryList(
          items: response.payments,
          onViewReceipt: onReceiptTap,
        ),
      ],
    );
  }
}
