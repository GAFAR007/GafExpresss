/// lib/app/features/home/presentation/payments/payment_history_widgets.dart
/// ----------------------------------------------------------------------
/// WHAT:
/// - Shared UI widgets for tenant payment history screens.
///
/// WHY:
/// - Avoids duplicated UI logic between business and tenant views.
/// - Keeps each screen widget small and focused.
///
/// HOW:
/// - Provides summary cards, payment list items, and error/empty states.
/// - Uses theme tokens for all colors and typography.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_model.dart';
import 'package:frontend/app/theme/app_theme.dart';

// WHY: Keep UI copy centralized to avoid inline magic strings.
const String _summaryTitleDefault = "Payment summary";
const String _summaryOverdueLabel = "OVERDUE";
const String _summaryPaymentsThisYearLabel = "Payments this year";
const String _summaryPaidPeriodsLabel = "Paid periods YTD";
const String _summaryRemainingLabel = "Remaining periods YTD";
const String _summaryTotalPeriodsLabel = "Total periods / year";
const String _summaryPaidTotalYtdLabel = "Total paid YTD";
const String _summaryPaidTotalAllTimeLabel = "Total paid (all time)";
const String _summaryTotalAmountLabel = "Rent per year (all units)";
const String _summaryPerUnitAmountLabel = "Rent per year (per unit)";
const String _listTitle = "Payment history";
const String _emptyStateMessage = "No rent payments have been recorded yet.";
const String _receiptUnavailableLabel = "Receipt unavailable";
const String _viewReceiptLabel = "View receipt";
const String _amountLabel = "Amount";
const String _periodLabel = "Period";
const String _paidFromLabel = "Paid from";
const String _paidThroughLabel = "Paid through";
const String _paidAtLabel = "Paid at";
const String _statusSuccess = "SUCCESS";
const String _statusFailed = "FAILED";
const String _statusPending = "PENDING";
const String _errorTitle = "Unable to load payments";
const String _errorActionLabel = "Try again";
const String _errorGenericHint = "Please refresh to check again.";
const String _errorSupportHint = "If this persists, contact support.";
const String _logTag = "PAYMENT_WIDGETS";
const String _errorLogMessage = "payment history load failed";
const String _errorReasonDio = "dio_error";
const String _errorReasonUnknown = "unknown_error";
const String _emptyValue = "-";
const String _errorKey = "error";
const String _extraReasonKey = "reason";
const String _extraStatusKey = "status";
const String _extraNextActionKey = "next_action";
const int _zeroValue = 0;
const int _fallbackStatusCode = 0;
const int _maxPeriodsClamp = 9999;

// WHY: Keep spacing consistent and theme-friendly.
const double _cardSpacing = 12;
const double _chipSpacing = 10;
const double _chipRunSpacing = 8;
const double _cardRadius = 16;
const double _cardPadding = 16;
const double _iconSize = 18;
const double _pillHorizontalPadding = 10;
const double _pillVerticalPadding = 4;
const double _chipHorizontalPadding = 10;
const double _chipVerticalPadding = 6;
const double _pillRadius = 999;
const double _emptyIconSize = 32;

class PaymentSummaryCard extends StatelessWidget {
  final PaymentHistorySummary summary;
  final String? title;

  const PaymentSummaryCard({super.key, required this.summary, this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WHY: Overdue states should use a warning tone for clarity.
    final statusTone = summary.isOverdue
        ? AppStatusTone.warning
        : AppStatusTone.success;
    // WHY: Derive total periods from paid + remaining to avoid extra API fields.
    final totalPeriods = (summary.paidPeriodsYtd + summary.remainingPeriodsYtd)
        .clamp(_zeroValue, _maxPeriodsClamp);
    // WHY: Show yearly total only when backend supplies a value.
    final yearlyAmountLabel = summary.yearlyRentTotalKobo == null
        ? _emptyValue
        : formatNgnFromCents(summary.yearlyRentTotalKobo!);
    final yearlyPerUnitLabel = summary.yearlyRentPerUnitKobo == null
        ? _emptyValue
        : formatNgnFromCents(summary.yearlyRentPerUnitKobo!);
    // WHY: Paid totals help explain how much rent has been collected.
    final paidTotalYtdLabel = summary.totalPaidKoboYtd == null
        ? _emptyValue
        : formatNgnFromCents(summary.totalPaidKoboYtd!);
    final paidTotalAllTimeLabel = summary.totalPaidKoboAllTime == null
        ? _emptyValue
        : formatNgnFromCents(summary.totalPaidKoboAllTime!);
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: statusTone,
    );

    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title ?? _summaryTitleDefault,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (summary.isOverdue)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _pillHorizontalPadding,
                    vertical: _pillVerticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColors.background,
                    borderRadius: BorderRadius.circular(_pillRadius),
                  ),
                  child: Text(
                    _summaryOverdueLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: badgeColors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: _cardSpacing),
          Wrap(
            spacing: _chipSpacing,
            runSpacing: _chipRunSpacing,
            children: [
              _SummaryChip(
                label: _summaryPaymentsThisYearLabel,
                value: summary.paymentsThisYear.toString(),
              ),
              _SummaryChip(
                label: _summaryPaidPeriodsLabel,
                value: summary.paidPeriodsYtd.toString(),
              ),
              _SummaryChip(
                label: _summaryRemainingLabel,
                value: summary.remainingPeriodsYtd.toString(),
              ),
              _SummaryChip(
                label: _summaryTotalPeriodsLabel,
                value: totalPeriods.toString(),
              ),
              _SummaryChip(
                label: _summaryPaidTotalYtdLabel,
                value: paidTotalYtdLabel,
              ),
              _SummaryChip(
                label: _summaryPaidTotalAllTimeLabel,
                value: paidTotalAllTimeLabel,
              ),
              _SummaryChip(
                label: _summaryPerUnitAmountLabel,
                value: yearlyPerUnitLabel,
              ),
              _SummaryChip(
                label: _summaryTotalAmountLabel,
                value: yearlyAmountLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PaymentHistoryList extends StatelessWidget {
  final List<PaymentHistoryItem> items;
  final ValueChanged<PaymentHistoryItem>? onViewReceipt;

  const PaymentHistoryList({
    super.key,
    required this.items,
    this.onViewReceipt,
  });

  @override
  Widget build(BuildContext context) {
    // WHY: Show a friendly empty state when no payments exist.
    if (items.isEmpty) {
      return _EmptyState(message: _emptyStateMessage);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _listTitle,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: _cardSpacing),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: _cardSpacing),
            child: PaymentHistoryCard(item: item, onViewReceipt: onViewReceipt),
          ),
        ),
      ],
    );
  }
}

class PaymentHistoryCard extends StatelessWidget {
  final PaymentHistoryItem item;
  final ValueChanged<PaymentHistoryItem>? onViewReceipt;

  const PaymentHistoryCard({super.key, required this.item, this.onViewReceipt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusTone = _toneForStatus(item.status);
    final badgeColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: statusTone,
    );
    final periodLabel = _buildPeriodLabel(item);
    final paidAt = _formatDate(item.createdAt);
    final paidFrom = _formatDate(item.paidFrom);
    final paidThrough = _formatDate(item.paidThrough);
    // WHY: Disable the receipt button when no receipt URL exists.
    final canViewReceipt = onViewReceipt != null && item.receiptUrl != null;

    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "$_amountLabel: ${_formatMoney(item.amountKobo)}",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _pillHorizontalPadding,
                  vertical: _pillVerticalPadding,
                ),
                decoration: BoxDecoration(
                  color: badgeColors.background,
                  borderRadius: BorderRadius.circular(_pillRadius),
                ),
                child: Text(
                  item.status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: badgeColors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _cardSpacing),
          Wrap(
            spacing: _chipSpacing,
            runSpacing: _chipRunSpacing,
            children: [
              _MetaChip(label: _periodLabel, value: periodLabel),
              _MetaChip(label: _paidFromLabel, value: paidFrom),
              _MetaChip(label: _paidThroughLabel, value: paidThrough),
              _MetaChip(label: _paidAtLabel, value: paidAt),
            ],
          ),
          const SizedBox(height: _cardSpacing),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: canViewReceipt
                  ? () => onViewReceipt?.call(item)
                  : null,
              icon: const Icon(Icons.receipt_long, size: _iconSize),
              label: Text(
                canViewReceipt ? _viewReceiptLabel : _receiptUnavailableLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppStatusTone _toneForStatus(String status) {
    // WHY: Map payment status labels to theme-safe tones.
    switch (status.toUpperCase()) {
      case _statusSuccess:
        return AppStatusTone.success;
      case _statusFailed:
        return AppStatusTone.danger;
      case _statusPending:
        return AppStatusTone.warning;
      default:
        return AppStatusTone.neutral;
    }
  }

  String _buildPeriodLabel(PaymentHistoryItem item) {
    // WHY: Provide a safe fallback when period count is missing.
    final count = item.periodCount ?? _zeroValue;
    final cadence = item.rentCadence.toLowerCase();
    if (count <= 0 || cadence.isEmpty) {
      return _emptyValue;
    }
    return "$count ${cadence.toLowerCase()}";
  }

  String _formatMoney(int kobo) {
    // WHY: Keep money formatting consistent across screens.
    return formatNgnFromCents(kobo);
  }

  String _formatDate(DateTime? date) {
    // WHY: Ensure date formatting stays consistent with tenant dashboards.
    return formatDateLabel(date, fallback: "-");
  }
}

class PaymentHistoryErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const PaymentHistoryErrorState({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveError(error);

    AppDebug.log(
      _logTag,
      _errorLogMessage,
      extra: {
        _extraReasonKey: resolved.reason,
        _extraStatusKey: resolved.statusCode,
        _extraNextActionKey: resolved.nextAction,
      },
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: _cardSpacing),
            Text(resolved.message, textAlign: TextAlign.center),
            const SizedBox(height: _cardSpacing),
            Text(
              resolved.nextAction,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: _cardSpacing),
              TextButton(
                onPressed: onRetry,
                child: const Text(_errorActionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorResolution {
  final String message;
  final String reason;
  final int statusCode;
  final String nextAction;

  const _ErrorResolution({
    required this.message,
    required this.reason,
    required this.statusCode,
    required this.nextAction,
  });
}

_ErrorResolution _resolveError(Object error) {
  // WHY: Translate network errors into actionable messages.
  if (error is DioException) {
    final status = error.response?.statusCode ?? _fallbackStatusCode;
    final body = error.response?.data;
    final providerMessage = body is Map<String, dynamic>
        ? body[_errorKey]?.toString()
        : null;

    return _ErrorResolution(
      message: providerMessage ?? _errorGenericHint,
      reason: _errorReasonDio,
      statusCode: status,
      nextAction: _errorSupportHint,
    );
  }

  return const _ErrorResolution(
    message: _errorGenericHint,
    reason: _errorReasonUnknown,
    statusCode: _fallbackStatusCode,
    nextAction: _errorSupportHint,
  );
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _chipHorizontalPadding,
        vertical: _chipVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_pillRadius),
      ),
      child: Text(
        "$label: $value",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _chipHorizontalPadding,
        vertical: _chipVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_pillRadius),
      ),
      child: Text(
        "$label: $value",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: _emptyIconSize,
          ),
          const SizedBox(height: _cardSpacing),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
