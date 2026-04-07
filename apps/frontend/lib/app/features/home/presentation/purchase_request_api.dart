/// lib/app/features/home/presentation/purchase_request_api.dart
/// -------------------------------------------------------------
/// WHAT:
/// - REST client for temporary seller-direct purchase requests.
///
/// WHY:
/// - Keeps manual request/invoice/proof networking out of widgets.
/// - Centralizes auth headers and response parsing.
///
/// HOW:
/// - Uses Dio with Bearer auth.
/// - Maps backend purchase-request payloads into typed models.
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/cart_model.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_models.dart';

class PurchaseRequestApi {
  final Dio _dio;

  PurchaseRequestApi({required Dio dio}) : _dio = dio;

  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log("PURCHASE_REQUEST_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(headers: {"Authorization": "Bearer $token"});
  }

  Future<PurchaseRequestCreateResult> createPurchaseRequest({
    required String? token,
    required List<CartItem> items,
    required Map<String, dynamic> deliveryAddress,
    String? reservationId,
  }) async {
    final payload = <String, dynamic>{
      "items": items.map((item) => item.toOrderItemJson()).toList(),
      "deliveryAddress": deliveryAddress,
      if (reservationId != null && reservationId.trim().isNotEmpty)
        "reservationId": reservationId.trim(),
    };

    final resp = await _dio.post(
      "/purchase-requests",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final requestMap =
        (data["purchaseRequest"] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    final conversationMap =
        (data["conversation"] ?? const <String, dynamic>{})
            as Map<String, dynamic>;

    return PurchaseRequestCreateResult(
      purchaseRequest: PurchaseRequest.fromJson(requestMap),
      conversationId: (conversationMap["_id"] ?? conversationMap["id"] ?? "")
          .toString(),
    );
  }

  Future<PurchaseRequestBatchResult> createBatchPurchaseRequests({
    required String? token,
    required List<CartItem> items,
    required Map<String, dynamic> deliveryAddress,
  }) async {
    final resp = await _dio.post(
      "/purchase-requests/batch",
      data: {
        "items": items.map((item) => item.toOrderItemJson()).toList(),
        "deliveryAddress": deliveryAddress,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final rawRequests =
        (data["purchaseRequests"] ?? const <dynamic>[]) as List<dynamic>;
    final rawConversations =
        (data["conversations"] ?? const <dynamic>[]) as List<dynamic>;

    final results = <PurchaseRequestCreateResult>[];
    for (var index = 0; index < rawRequests.length; index++) {
      final requestMap = rawRequests[index] is Map<String, dynamic>
          ? rawRequests[index] as Map<String, dynamic>
          : const <String, dynamic>{};
      final conversationMap =
          index < rawConversations.length &&
              rawConversations[index] is Map<String, dynamic>
          ? rawConversations[index] as Map<String, dynamic>
          : const <String, dynamic>{};
      results.add(
        PurchaseRequestCreateResult(
          purchaseRequest: PurchaseRequest.fromJson(requestMap),
          conversationId:
              (conversationMap["_id"] ?? conversationMap["id"] ?? "")
                  .toString(),
        ),
      );
    }

    return PurchaseRequestBatchResult(requests: results);
  }

  Future<PurchaseRequest> sendInvoice({
    required String? token,
    required String requestId,
    required int baseLogisticsFeeCents,
    required double sellerMarkupPercent,
    required DateTime estimatedDeliveryDate,
    required Map<String, dynamic> paymentAccount,
    bool savePaymentAccount = false,
    String note = "",
  }) async {
    final resp = await _dio.post(
      "/purchase-requests/$requestId/invoice",
      data: {
        "baseLogisticsFee": baseLogisticsFeeCents,
        "sellerMarkupPercent": sellerMarkupPercent,
        "estimatedDeliveryDate": estimatedDeliveryDate.toIso8601String(),
        "paymentAccount": paymentAccount,
        "savePaymentAccount": savePaymentAccount,
        "note": note.trim(),
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    return PurchaseRequest.fromJson(
      (data["purchaseRequest"] ?? const <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  Future<PurchaseRequest> attendChat({
    required String? token,
    required String requestId,
  }) async {
    final resp = await _dio.post(
      "/purchase-requests/$requestId/attend",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    return PurchaseRequest.fromJson(
      (data["purchaseRequest"] ?? const <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  Future<PurchaseRequest> exitChat({
    required String? token,
    required String requestId,
  }) async {
    final resp = await _dio.post(
      "/purchase-requests/$requestId/exit",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    return PurchaseRequest.fromJson(
      (data["purchaseRequest"] ?? const <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  Future<PurchaseRequest> updateAiControl({
    required String? token,
    required String requestId,
    required bool enabled,
  }) async {
    final resp = await _dio.patch(
      "/purchase-requests/$requestId/ai-control",
      data: {"enabled": enabled},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    return PurchaseRequest.fromJson(
      (data["purchaseRequest"] ?? const <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  Future<PurchaseRequest> submitPaymentProof({
    required String? token,
    required String requestId,
    required String attachmentId,
    String note = "",
  }) async {
    final resp = await _dio.post(
      "/purchase-requests/$requestId/proof",
      data: {"attachmentId": attachmentId, "note": note.trim()},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    return PurchaseRequest.fromJson(
      (data["purchaseRequest"] ?? const <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  Future<PurchaseRequestReviewResult> reviewPaymentProof({
    required String? token,
    required String requestId,
    required String decision,
    String reviewNote = "",
    String approvalPassword = "",
  }) async {
    final resp = await _dio.post(
      "/purchase-requests/$requestId/proof-review",
      data: {
        "decision": decision.trim(),
        "reviewNote": reviewNote.trim(),
        if (approvalPassword.trim().isNotEmpty)
          "approvalPassword": approvalPassword,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final orderMap = data["order"] is Map<String, dynamic>
        ? data["order"] as Map<String, dynamic>
        : const <String, dynamic>{};

    return PurchaseRequestReviewResult(
      purchaseRequest: PurchaseRequest.fromJson(
        (data["purchaseRequest"] ?? const <String, dynamic>{})
            as Map<String, dynamic>,
      ),
      orderId: (orderMap["_id"] ?? orderMap["id"] ?? "").toString(),
    );
  }

  Future<PurchaseRequest> cancelPurchaseRequest({
    required String? token,
    required String requestId,
    String reason = "",
  }) async {
    final resp = await _dio.patch(
      "/purchase-requests/$requestId/cancel",
      data: {"reason": reason.trim()},
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    return PurchaseRequest.fromJson(
      (data["purchaseRequest"] ?? const <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }
}
