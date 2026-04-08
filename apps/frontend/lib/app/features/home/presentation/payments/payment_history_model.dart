/// lib/app/features/home/presentation/payments/payment_history_model.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Typed models for tenant payment history responses.
///
/// WHY:
/// - Keeps JSON parsing out of UI widgets.
/// - Ensures business + tenant payment screens share one shape.
///
/// HOW:
/// - Maps API response keys into strongly typed models.
/// - Uses defensive parsing and safe fallbacks.
library;

import 'package:frontend/app/core/debug/app_debug.dart';

// WHY: Centralize JSON keys to avoid inline magic strings.
const String _paymentsKey = "payments";
const String _summaryKey = "summary";
const String _idKey = "id";
const String _amountKey = "amountKobo";
const String _currencyKey = "currency";
const String _statusKey = "status";
const String _periodCountKey = "periodCount";
const String _rentCadenceKey = "rentCadence";
const String _createdAtKey = "createdAt";
const String _paidFromKey = "paidFrom";
const String _paidThroughKey = "paidThrough";
const String _receiptUrlKey = "receiptUrl";
const String _paymentsThisYearKey = "paymentsThisYear";
const String _paidPeriodsYtdKey = "paidPeriodsYtd";
const String _remainingPeriodsYtdKey = "remainingPeriodsYtd";
const String _isOverdueKey = "isOverdue";
const String _totalPaidKoboYtdKey = "totalPaidKoboYtd";
const String _totalPaidKoboAllTimeKey = "totalPaidKoboAllTime";
const String _yearlyRentTotalKey = "yearlyRentTotalKobo";
const String _yearlyRentPerUnitKey = "yearlyRentPerUnitKobo";

// WHY: Provide consistent defaults without inline magic values.
const String _defaultCurrency = "NGN";
const String _defaultStatus = "UNKNOWN";
const int _defaultInt = 0;
const String _emptyString = "";
const String _trueString = "true";
const String _logTag = "PAYMENT_MODEL";
const String _logParsedMessage = "parsed payment history";
const String _extraCountKey = "count";

class PaymentHistoryItem {
  final String id;
  final int amountKobo;
  final String currency;
  final String status;
  final int? periodCount;
  final String rentCadence;
  final DateTime? createdAt;
  final DateTime? paidFrom;
  final DateTime? paidThrough;
  final String? receiptUrl;

  const PaymentHistoryItem({
    required this.id,
    required this.amountKobo,
    required this.currency,
    required this.status,
    required this.periodCount,
    required this.rentCadence,
    required this.createdAt,
    required this.paidFrom,
    required this.paidThrough,
    required this.receiptUrl,
  });

  factory PaymentHistoryItem.fromJson(Map<String, dynamic> json) {
    // WHY: Parse dynamic payloads safely to avoid runtime crashes in UI.
    return PaymentHistoryItem(
      id: _asString(json[_idKey]),
      amountKobo: _asInt(json[_amountKey]),
      currency: _asString(json[_currencyKey], fallback: _defaultCurrency),
      status: _asString(json[_statusKey], fallback: _defaultStatus),
      periodCount: _asNullableInt(json[_periodCountKey]),
      rentCadence: _asString(json[_rentCadenceKey]),
      createdAt: _asDate(json[_createdAtKey]),
      paidFrom: _asDate(json[_paidFromKey]),
      paidThrough: _asDate(json[_paidThroughKey]),
      receiptUrl: _asNullableString(json[_receiptUrlKey]),
    );
  }
}

class PaymentHistorySummary {
  final int paymentsThisYear;
  final int paidPeriodsYtd;
  final int remainingPeriodsYtd;
  final bool isOverdue;
  final int? totalPaidKoboYtd;
  final int? totalPaidKoboAllTime;
  final int? yearlyRentTotalKobo;
  final int? yearlyRentPerUnitKobo;

  const PaymentHistorySummary({
    required this.paymentsThisYear,
    required this.paidPeriodsYtd,
    required this.remainingPeriodsYtd,
    required this.isOverdue,
    required this.totalPaidKoboYtd,
    required this.totalPaidKoboAllTime,
    required this.yearlyRentTotalKobo,
    required this.yearlyRentPerUnitKobo,
  });

  factory PaymentHistorySummary.fromJson(Map<String, dynamic> json) {
    // WHY: Summary chips should always render even if fields are missing.
    return PaymentHistorySummary(
      paymentsThisYear: _asInt(json[_paymentsThisYearKey]),
      paidPeriodsYtd: _asInt(json[_paidPeriodsYtdKey]),
      remainingPeriodsYtd: _asInt(json[_remainingPeriodsYtdKey]),
      isOverdue: _asBool(json[_isOverdueKey]),
      totalPaidKoboYtd: _asNullableInt(json[_totalPaidKoboYtdKey]),
      totalPaidKoboAllTime:
          _asNullableInt(json[_totalPaidKoboAllTimeKey]),
      yearlyRentTotalKobo: _asNullableInt(json[_yearlyRentTotalKey]),
      yearlyRentPerUnitKobo: _asNullableInt(json[_yearlyRentPerUnitKey]),
    );
  }
}

class PaymentHistoryResponse {
  final List<PaymentHistoryItem> payments;
  final PaymentHistorySummary summary;

  const PaymentHistoryResponse({
    required this.payments,
    required this.summary,
  });

  factory PaymentHistoryResponse.fromJson(Map<String, dynamic> json) {
    // WHY: Backend payloads may omit arrays; guard before mapping.
    final rawPayments = json[_paymentsKey];
    final rawSummary = json[_summaryKey];
    final items = rawPayments is List
        ? rawPayments
            .whereType<Map<String, dynamic>>()
            .map(PaymentHistoryItem.fromJson)
            .toList()
        : <PaymentHistoryItem>[];

    final summary = rawSummary is Map<String, dynamic>
        ? PaymentHistorySummary.fromJson(rawSummary)
        : const PaymentHistorySummary(
            paymentsThisYear: _defaultInt,
            paidPeriodsYtd: _defaultInt,
            remainingPeriodsYtd: _defaultInt,
            isOverdue: false,
            totalPaidKoboYtd: null,
            totalPaidKoboAllTime: null,
            yearlyRentTotalKobo: null,
            yearlyRentPerUnitKobo: null,
          );

    // WHY: Log safe counts to confirm API payloads without exposing PII.
    AppDebug.log(
      _logTag,
      _logParsedMessage,
      extra: {_extraCountKey: items.length},
    );

    return PaymentHistoryResponse(
      payments: items,
      summary: summary,
    );
  }
}

int _asInt(dynamic value, {int fallback = _defaultInt}) {
  // WHY: Normalize integer parsing for API payloads.
  if (value is int) return value;
  if (value is num) return value.round();
  if (value == null) return fallback;
  return int.tryParse(value.toString()) ?? fallback;
}

int? _asNullableInt(dynamic value) {
  // WHY: Preserve optional fields without forcing zero.
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

String _asString(dynamic value, {String fallback = _emptyString}) {
  // WHY: Keep string conversions consistent across models.
  if (value == null) return fallback;
  return value.toString();
}

String? _asNullableString(dynamic value) {
  // WHY: Represent empty strings as null for cleaner UI logic.
  if (value == null) return null;
  final trimmed = value.toString().trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _asDate(dynamic value) {
  // WHY: Normalize date parsing for API payloads.
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

bool _asBool(dynamic value) {
  // WHY: Treat missing values as false to keep UI consistent.
  if (value is bool) return value;
  if (value == null) return false;
  return value.toString().toLowerCase() == _trueString;
}
