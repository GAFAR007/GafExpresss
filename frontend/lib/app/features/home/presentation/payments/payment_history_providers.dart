/// lib/app/features/home/presentation/payments/payment_history_providers.dart
/// -----------------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for tenant payment history screens.
///
/// WHY:
/// - Keeps auth/session wiring in one place.
/// - Lets UI widgets stay focused on rendering.
///
/// HOW:
/// - Builds PaymentHistoryApi from shared Dio.
/// - Fetches tenant receipts and business tenant history.
/// - Logs provider lifecycle events.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_api.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_model.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

// WHY: Keep logs consistent across providers.
const String _logTag = "PAYMENT_PROVIDERS";
const String _apiProviderMessage = "paymentHistoryApiProvider created";
const String _tenantFetchStart = "tenantPaymentHistoryProvider fetch start";
const String _businessFetchStart = "businessPaymentHistoryProvider fetch start";
const String _missingSessionMessage = "session missing";
const String _sessionExpiredMessage =
    "Session expired. Please sign in again.";
const String _signInAction = "Sign in and retry.";
const String _tenantSessionReason = "tenant_session_missing";
const String _businessSessionReason = "business_session_missing";
const String _extraReasonKey = "reason";
const String _extraNextActionKey = "next_action";
const String _extraTenantIdKey = "tenantId";

final paymentHistoryApiProvider = Provider<PaymentHistoryApi>((ref) {
  AppDebug.log(_logTag, _apiProviderMessage);
  final dio = ref.read(dioProvider);
  return PaymentHistoryApi(dio: dio);
});

final tenantPaymentHistoryProvider =
    FutureProvider<PaymentHistoryResponse>((ref) async {
  AppDebug.log(_logTag, _tenantFetchStart);

  // WHY: Payment history requires an active authenticated session.
  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log(
      _logTag,
      _missingSessionMessage,
      extra: {
        _extraReasonKey: _tenantSessionReason,
        _extraNextActionKey: _signInAction,
      },
    );
    // WHY: Block requests when the session is missing to avoid 401 loops.
    throw Exception(_sessionExpiredMessage);
  }

  // WHY: Keep API fetch logic in one place for consistent parsing.
  final api = ref.read(paymentHistoryApiProvider);
  return api.fetchTenantPayments(token: session.token);
});

final businessTenantPaymentHistoryProvider =
    FutureProvider.family<PaymentHistoryResponse, String>((ref, tenantId) async {
  AppDebug.log(
    _logTag,
    _businessFetchStart,
    extra: {_extraTenantIdKey: tenantId},
  );

  // WHY: Business payment history requires an authenticated business session.
  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log(
      _logTag,
      _missingSessionMessage,
      extra: {
        _extraReasonKey: _businessSessionReason,
        _extraTenantIdKey: tenantId,
        _extraNextActionKey: _signInAction,
      },
    );
    // WHY: Prevent unauthorized calls when the session is missing.
    throw Exception(_sessionExpiredMessage);
  }

  // WHY: Keep API fetch logic centralized for consistent parsing.
  final api = ref.read(paymentHistoryApiProvider);
  return api.fetchBusinessTenantPayments(
    token: session.token,
    tenantId: tenantId,
  );
});
