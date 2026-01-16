/// lib/app/features/home/presentation/order_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - OrderApi handles /orders and Paystack init calls.
///
/// WHY:
/// - Keeps networking out of UI widgets.
/// - Central place for auth headers + parsing.
///
/// HOW:
/// - Uses Dio with Authorization header.
/// - Maps responses into Order models.
///
/// DEBUGGING:
/// - Logs request start/end (safe only).
/// - Never logs tokens.
/// ------------------------------------------------------------

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'cart_model.dart';
import 'order_model.dart';

class PaystackInitResult {
  final String authorizationUrl;
  final String reference;

  const PaystackInitResult({
    required this.authorizationUrl,
    required this.reference,
  });
}

class OrderApi {
  final Dio _dio;

  OrderApi({required Dio dio}) : _dio = dio;

  /// WHY: All /orders endpoints require auth.
  Options _authOptions(String? token) {
    if (token == null || token.isEmpty) {
      AppDebug.log("ORDER_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(
      headers: {
        "Authorization": "Bearer $token",
      },
    );
  }

  /// ------------------------------------------------------
  /// CREATE ORDER
  /// ------------------------------------------------------
  Future<Order> createOrder({
    required String? token,
    required List<CartItem> items,
  }) async {
    AppDebug.log(
      "ORDER_API",
      "createOrder() start",
      extra: {"items": items.length},
    );

    final payloadItems = items.map((item) => item.toOrderItemJson()).toList();

    final resp = await _dio.post(
      "/orders",
      data: {"items": payloadItems},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final orderMap = (data["order"] ?? {}) as Map<String, dynamic>;

    final order = Order.fromJson(orderMap);

    AppDebug.log(
      "ORDER_API",
      "createOrder() success",
      extra: {"orderId": order.id},
    );

    return order;
  }

  /// ------------------------------------------------------
  /// FETCH MY ORDERS
  /// ------------------------------------------------------
  Future<List<Order>> fetchMyOrders({
    required String? token,
    int page = 1,
    int limit = 10,
  }) async {
    AppDebug.log(
      "ORDER_API",
      "fetchMyOrders() start",
      extra: {"page": page, "limit": limit},
    );

    final resp = await _dio.get(
      "/orders",
      queryParameters: {"page": page, "limit": limit},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final rawOrders = (data["orders"] ?? []) as List<dynamic>;

    final orders = rawOrders
        .map((item) => Order.fromJson(item as Map<String, dynamic>))
        .toList();

    AppDebug.log(
      "ORDER_API",
      "fetchMyOrders() success",
      extra: {"count": orders.length},
    );

    return orders;
  }

  /// ------------------------------------------------------
  /// CANCEL ORDER
  /// ------------------------------------------------------
  Future<Order> cancelOrder({
    required String? token,
    required String orderId,
  }) async {
    AppDebug.log(
      "ORDER_API",
      "cancelOrder() start",
      extra: {"orderId": orderId},
    );

    final resp = await _dio.patch(
      "/orders/$orderId/cancel",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final orderMap = (data["order"] ?? {}) as Map<String, dynamic>;

    final order = Order.fromJson(orderMap);

    AppDebug.log(
      "ORDER_API",
      "cancelOrder() success",
      extra: {"orderId": order.id, "status": order.status},
    );

    return order;
  }

  /// ------------------------------------------------------
  /// PAYSTACK INIT
  /// ------------------------------------------------------
  Future<PaystackInitResult> initPaystackCheckout({
    required String? token,
    required String orderId,
    required String email,
    required int amountKobo,
    String? callbackUrl,
  }) async {
    AppDebug.log(
      "ORDER_API",
      "initPaystackCheckout() start",
      extra: {"orderId": orderId, "amountKobo": amountKobo},
    );

    final payload = <String, dynamic>{
      "orderId": orderId,
      "email": email,
      "amount": amountKobo,
    };

    // WHY: Paystack callback is required for redirect-based confirmation.
    if (callbackUrl != null && callbackUrl.isNotEmpty) {
      payload["callbackUrl"] = callbackUrl;
    }

    final resp = await _dio.post(
      "/payments/paystack/init",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final inner = (data["data"] ?? data) as Map<String, dynamic>;

    final authorizationUrl =
        (inner["authorization_url"] ?? inner["authorizationUrl"] ?? "")
            .toString();
    final reference = (inner["reference"] ?? "").toString();

    if (authorizationUrl.isEmpty) {
      AppDebug.log("ORDER_API", "initPaystackCheckout() missing auth url");
      throw Exception("Paystack init missing authorization_url");
    }

    AppDebug.log(
      "ORDER_API",
      "initPaystackCheckout() success",
      extra: {"reference": reference},
    );

    return PaystackInitResult(
      authorizationUrl: authorizationUrl,
      reference: reference,
    );
  }
}
