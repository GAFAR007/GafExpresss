/// lib/app/features/home/presentation/business_order_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - BusinessOrderApi for /business/orders endpoints.
///
/// WHY:
/// - Business orders require different responses than customer orders.
/// - Keeps role-gated business calls out of UI widgets.
///
/// HOW:
/// - Uses Dio with Authorization header.
/// - Parses orders into BusinessOrder models.
///
/// DEBUGGING:
/// - Logs request start/end (safe only).
/// - Never logs tokens.
/// ------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_order_model.dart';

class BusinessOrdersResult {
  final List<BusinessOrder> orders;
  final int total;
  final int page;
  final int limit;

  const BusinessOrdersResult({
    required this.orders,
    required this.total,
    required this.page,
    required this.limit,
  });
}

class BusinessOrderApi {
  final Dio _dio;

  BusinessOrderApi({required Dio dio}) : _dio = dio;

  /// WHY: All /business/orders endpoints require auth.
  Options _authOptions(String? token) {
    if (token == null || token.isEmpty) {
      AppDebug.log("BUSINESS_ORDER_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(headers: {"Authorization": "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// FETCH BUSINESS ORDERS
  /// ------------------------------------------------------
  Future<BusinessOrdersResult> fetchBusinessOrders({
    required String? token,
    int page = 1,
    int limit = 10,
    String? status,
  }) async {
    AppDebug.log(
      "BUSINESS_ORDER_API",
      "fetchBusinessOrders() start",
      extra: {"page": page, "limit": limit, "status": status ?? "all"},
    );

    final resp = await _dio.get(
      "/business/orders",
      queryParameters: {
        "page": page,
        "limit": limit,
        if (status != null && status.isNotEmpty) "status": status,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final rawOrders = (data["orders"] ?? []) as List<dynamic>;
    final orders = rawOrders
        .map((item) => BusinessOrder.fromJson(item as Map<String, dynamic>))
        .toList();

    final result = BusinessOrdersResult(
      orders: orders,
      total: (data["total"] ?? 0) is int
          ? (data["total"] ?? 0) as int
          : int.tryParse((data["total"] ?? 0).toString()) ?? 0,
      page: (data["page"] ?? page) is int
          ? (data["page"] ?? page) as int
          : int.tryParse((data["page"] ?? page).toString()) ?? page,
      limit: (data["limit"] ?? limit) is int
          ? (data["limit"] ?? limit) as int
          : int.tryParse((data["limit"] ?? limit).toString()) ?? limit,
    );

    AppDebug.log(
      "BUSINESS_ORDER_API",
      "fetchBusinessOrders() success",
      extra: {"count": orders.length, "total": result.total},
    );

    return result;
  }

  /// ------------------------------------------------------
  /// UPDATE ORDER STATUS
  /// ------------------------------------------------------
  Future<BusinessOrder> updateOrderStatus({
    required String? token,
    required String orderId,
    required String status,
    String carrierName = "",
    String trackingReference = "",
    String dispatchNote = "",
    DateTime? estimatedDeliveryDate,
  }) async {
    AppDebug.log(
      "BUSINESS_ORDER_API",
      "updateOrderStatus() start",
      extra: {"orderId": orderId, "status": status},
    );

    final resp = await _dio.patch(
      "/business/orders/$orderId/status",
      data: {
        "status": status,
        if (carrierName.trim().isNotEmpty) "carrierName": carrierName.trim(),
        if (trackingReference.trim().isNotEmpty)
          "trackingReference": trackingReference.trim(),
        if (dispatchNote.trim().isNotEmpty) "dispatchNote": dispatchNote.trim(),
        if (estimatedDeliveryDate != null)
          "estimatedDeliveryDate": estimatedDeliveryDate.toIso8601String(),
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final orderMap = (data["order"] ?? {}) as Map<String, dynamic>;
    final order = BusinessOrder.fromJson(orderMap);

    AppDebug.log(
      "BUSINESS_ORDER_API",
      "updateOrderStatus() success",
      extra: {"orderId": order.id, "status": order.status},
    );

    return order;
  }
}
