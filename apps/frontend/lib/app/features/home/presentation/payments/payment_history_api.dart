/// lib/app/features/home/presentation/payments/payment_history_api.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - API client for tenant payment history endpoints.
///
/// WHY:
/// - Keeps HTTP logic out of UI widgets.
/// - Ensures business + tenant flows share one response parser.
///
/// HOW:
/// - Uses Dio with auth headers.
/// - Fetches payment history and maps to models.
/// - Logs request boundaries and failure reasons.
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/payments/payment_history_model.dart';

// WHY: Centralize endpoint paths to avoid inline magic strings.
const String _tenantPaymentsPath = "/business/tenant/payments";
const String _businessTenantPaymentsBase =
    "/business/tenant";

// WHY: Centralize log metadata for consistent diagnostics.
const String _logTag = "PAYMENTS_API";
const String _serviceName = "tenant_payments_api";
const String _intentTenant = "load tenant receipts";
const String _intentBusiness = "load tenant payment history for owner";
const String _nextActionRetry = "Retry the request or contact support.";
const String _missingTokenMessage = "Missing auth token";
const String _nextActionAuth = "Sign in and retry.";
const String _authOperation = "authOptions";
const String _authIntent = "ensure auth headers";
const String _tenantOperation = "fetchTenantPayments";
const String _businessOperation = "fetchBusinessTenantPayments";
const String _tenantStartMessage = "fetchTenantPayments() start";
const String _tenantSuccessMessage = "fetchTenantPayments() success";
const String _tenantFailureMessage = "fetchTenantPayments() failed";
const String _businessStartMessage = "fetchBusinessTenantPayments() start";
const String _businessSuccessMessage = "fetchBusinessTenantPayments() success";
const String _businessFailureMessage = "fetchBusinessTenantPayments() failed";
const String _authMissingMessage = "auth token missing";
const String _fallbackErrorReason = "unknown_error";
const int _fallbackStatusCode = 0;
const String _extraServiceKey = "service";
const String _extraOperationKey = "operation";
const String _extraIntentKey = "intent";
const String _extraNextActionKey = "next_action";
const String _extraStatusKey = "status";
const String _extraReasonKey = "reason";
const String _extraCountKey = "count";
const String _extraTenantIdKey = "tenantId";

class PaymentHistoryApi {
  final Dio _dio;

  PaymentHistoryApi({required Dio dio}) : _dio = dio;

  // WHY: All payment history endpoints require an auth token.
  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log(
        _logTag,
        _authMissingMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _authOperation,
          _extraIntentKey: _authIntent,
          _extraNextActionKey: _nextActionAuth,
        },
      );
      throw Exception(_missingTokenMessage);
    }

    return Options(headers: {"Authorization": "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// TENANT RECEIPTS
  /// ------------------------------------------------------
  Future<PaymentHistoryResponse> fetchTenantPayments({
    required String? token,
  }) async {
    AppDebug.log(
      _logTag,
      _tenantStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _tenantOperation,
        _extraIntentKey: _intentTenant,
      },
    );

    try {
      final resp = await _dio.get(
        _tenantPaymentsPath,
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final parsed = PaymentHistoryResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _tenantSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _tenantOperation,
          _extraIntentKey: _intentTenant,
          _extraCountKey: parsed.payments.length,
        },
      );

      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _tenantFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _tenantOperation,
          _extraIntentKey: _intentTenant,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }

  /// ------------------------------------------------------
  /// BUSINESS OWNER PAYMENT HISTORY
  /// ------------------------------------------------------
  Future<PaymentHistoryResponse> fetchBusinessTenantPayments({
    required String? token,
    required String tenantId,
  }) async {
    AppDebug.log(
      _logTag,
      _businessStartMessage,
      extra: {
        _extraServiceKey: _serviceName,
        _extraOperationKey: _businessOperation,
        _extraIntentKey: _intentBusiness,
        _extraTenantIdKey: tenantId,
      },
    );

    try {
      final resp = await _dio.get(
        "$_businessTenantPaymentsBase/$tenantId/payments",
        options: _authOptions(token),
      );

      final data = resp.data as Map<String, dynamic>;
      final parsed = PaymentHistoryResponse.fromJson(data);

      AppDebug.log(
        _logTag,
        _businessSuccessMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _businessOperation,
          _extraIntentKey: _intentBusiness,
          _extraTenantIdKey: tenantId,
          _extraCountKey: parsed.payments.length,
        },
      );

      return parsed;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? _fallbackStatusCode;
      final reason =
          error.response?.data?.toString() ??
          error.message ??
          _fallbackErrorReason;
      AppDebug.log(
        _logTag,
        _businessFailureMessage,
        extra: {
          _extraServiceKey: _serviceName,
          _extraOperationKey: _businessOperation,
          _extraIntentKey: _intentBusiness,
          _extraTenantIdKey: tenantId,
          _extraStatusKey: status,
          _extraReasonKey: reason,
          _extraNextActionKey: _nextActionRetry,
        },
      );
      rethrow;
    }
  }
}
