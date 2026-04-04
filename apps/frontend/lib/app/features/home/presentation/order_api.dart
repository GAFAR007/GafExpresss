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
library;

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

class PaystackVerifyResult {
  final String reference;
  final String status;
  final bool applied;
  final bool idempotent;
  final bool processed;
  final String? orderId;
  final String? orderStatus;
  final String? reservationId;
  final String? reservationStatus;

  const PaystackVerifyResult({
    required this.reference,
    required this.status,
    required this.applied,
    required this.idempotent,
    required this.processed,
    this.orderId,
    this.orderStatus,
    this.reservationId,
    this.reservationStatus,
  });

  static const List<String> _terminalOrderStatuses = [
    "paid",
    "shipped",
    "delivered",
  ];

  bool get isOrderConfirmed =>
      _terminalOrderStatuses.contains((orderStatus ?? "").toLowerCase());

  bool get isReservationConfirmed {
    final id = reservationId?.trim() ?? "";
    if (id.isEmpty) {
      return true;
    }
    return (reservationStatus ?? "").toLowerCase() == "confirmed";
  }

  bool get isFullyConfirmed => isOrderConfirmed && isReservationConfirmed;
}

class PreorderConfirmResult {
  final String reservationId;
  final String status;
  final bool idempotent;
  final int cap;
  final int reserved;
  final int remaining;

  const PreorderConfirmResult({
    required this.reservationId,
    required this.status,
    required this.idempotent,
    required this.cap,
    required this.reserved,
    required this.remaining,
  });

  factory PreorderConfirmResult.fromJson(Map<String, dynamic> json) {
    final reservation = (json["reservation"] is Map<String, dynamic>)
        ? json["reservation"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final summary = (json["preorderSummary"] is Map<String, dynamic>)
        ? json["preorderSummary"] as Map<String, dynamic>
        : const <String, dynamic>{};

    return PreorderConfirmResult(
      reservationId: (reservation["_id"] ?? reservation["id"] ?? "").toString(),
      status: (reservation["status"] ?? "").toString(),
      idempotent: json["idempotent"] == true,
      cap: _parseInt(summary["cap"]),
      reserved: _parseInt(summary["reserved"]),
      remaining: _parseInt(summary["remaining"]),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse((value ?? 0).toString()) ?? 0;
  }
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

    return Options(headers: {"Authorization": "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// CREATE ORDER
  /// ------------------------------------------------------
  Future<Order> createOrder({
    required String? token,
    required List<CartItem> items,
    required Map<String, dynamic> deliveryAddress,
    String? reservationId,
  }) async {
    final normalizedReservationId = reservationId?.trim();
    AppDebug.log(
      "ORDER_API",
      "createOrder() start",
      extra: {
        "items": items.length,
        "source": deliveryAddress["source"],
        "hasReservationId":
            normalizedReservationId != null &&
            normalizedReservationId.isNotEmpty,
      },
    );

    final payloadItems = items.map((item) => item.toOrderItemJson()).toList();
    final payload = <String, dynamic>{
      "items": payloadItems,
      "deliveryAddress": deliveryAddress,
    };
    if (normalizedReservationId != null && normalizedReservationId.isNotEmpty) {
      payload["reservationId"] = normalizedReservationId;
    }

    final resp = await _dio.post(
      "/orders",
      data: payload,
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

  /// ------------------------------------------------------
  /// PAYSTACK VERIFY
  /// ------------------------------------------------------
  Future<PaystackVerifyResult> verifyPaystackCheckout({
    required String? token,
    required String reference,
  }) async {
    final normalizedReference = reference.trim();
    if (normalizedReference.isEmpty) {
      throw Exception("reference is required");
    }

    AppDebug.log(
      "ORDER_API",
      "verifyPaystackCheckout() start",
      extra: {
        "referenceSuffix": normalizedReference.substring(
          normalizedReference.length > 6 ? normalizedReference.length - 6 : 0,
        ),
      },
    );

    final resp = await _dio.get(
      "/payments/paystack/verify",
      queryParameters: {"reference": normalizedReference},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final order = (data["order"] is Map<String, dynamic>)
        ? data["order"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final reservation = (data["reservation"] is Map<String, dynamic>)
        ? data["reservation"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final result = PaystackVerifyResult(
      reference: (data["reference"] ?? normalizedReference).toString(),
      status: (data["status"] ?? "unknown").toString(),
      applied: data["applied"] == true,
      idempotent: data["idempotent"] == true,
      processed: data["processed"] == true,
      orderId: _parseNullableString(order["id"]),
      orderStatus: _parseNullableString(order["status"]),
      reservationId: _parseNullableString(reservation["id"]),
      reservationStatus: _parseNullableString(reservation["status"]),
    );

    AppDebug.log(
      "ORDER_API",
      "verifyPaystackCheckout() success",
      extra: {
        "status": result.status,
        "applied": result.applied,
        "idempotent": result.idempotent,
      },
    );

    return result;
  }

  /// ------------------------------------------------------
  /// PREORDER CONFIRM (MANUAL FALLBACK)
  /// ------------------------------------------------------
  Future<PreorderConfirmResult> confirmPreorderReservation({
    required String? token,
    required String reservationId,
  }) async {
    final normalizedReservationId = reservationId.trim();
    if (normalizedReservationId.isEmpty) {
      throw Exception("reservationId is required");
    }

    AppDebug.log(
      "ORDER_API",
      "confirmPreorderReservation() start",
      extra: {"reservationId": normalizedReservationId},
    );

    final resp = await _dio.post(
      "/business/preorder/reservations/$normalizedReservationId/confirm",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final result = PreorderConfirmResult.fromJson(data);

    AppDebug.log(
      "ORDER_API",
      "confirmPreorderReservation() success",
      extra: {
        "reservationId": result.reservationId,
        "status": result.status,
        "idempotent": result.idempotent,
      },
    );

    return result;
  }

  static String? _parseNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return text;
  }
}
