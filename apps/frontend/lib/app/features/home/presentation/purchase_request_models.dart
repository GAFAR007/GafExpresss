/// lib/app/features/home/presentation/purchase_request_models.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Typed models for temporary seller-direct purchase requests.
///
/// WHY:
/// - Keeps request, invoice, and proof parsing out of widgets.
/// - Lets chat and checkout screens share one request shape.
///
/// HOW:
/// - Maps backend JSON into small immutable models.
library;

import 'package:frontend/app/features/home/presentation/order_model.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse((value ?? 0).toString()) ?? 0;
}

String _parseString(dynamic value) {
  return (value ?? "").toString();
}

double _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse((value ?? 0).toString()) ?? 0;
}

class PurchaseRequestItem {
  final String productId;
  final String businessId;
  final String name;
  final String imageUrl;
  final int quantity;
  final int unitPriceCents;
  final int subtotalCents;

  const PurchaseRequestItem({
    required this.productId,
    required this.businessId,
    required this.name,
    required this.imageUrl,
    required this.quantity,
    required this.unitPriceCents,
    required this.subtotalCents,
  });

  factory PurchaseRequestItem.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestItem(
      productId: _parseString(json["product"]),
      businessId: _parseString(json["businessId"]),
      name: _parseString(json["name"]),
      imageUrl: _parseString(json["imageUrl"]),
      quantity: _parseInt(json["quantity"]),
      unitPriceCents: _parseInt(json["unitPrice"]),
      subtotalCents: _parseInt(json["subtotal"]),
    );
  }
}

class PurchaseRequestCharges {
  final int baseLogisticsFeeCents;
  final double sellerMarkupPercent;
  final int sellerMarkupAmountCents;
  final int logisticsFeeCents;
  final int serviceChargeCents;

  const PurchaseRequestCharges({
    required this.baseLogisticsFeeCents,
    required this.sellerMarkupPercent,
    required this.sellerMarkupAmountCents,
    required this.logisticsFeeCents,
    required this.serviceChargeCents,
  });

  int get totalChargesCents => logisticsFeeCents + serviceChargeCents;

  factory PurchaseRequestCharges.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestCharges(
      baseLogisticsFeeCents: _parseInt(json["baseLogisticsFee"]),
      sellerMarkupPercent: _parseDouble(json["sellerMarkupPercent"]),
      sellerMarkupAmountCents: _parseInt(json["sellerMarkupAmount"]),
      logisticsFeeCents: _parseInt(json["logisticsFee"]),
      serviceChargeCents: _parseInt(json["serviceCharge"]),
    );
  }
}

class PurchaseRequestPaymentAccount {
  final String id;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String transferInstruction;
  final bool isDefault;

  const PurchaseRequestPaymentAccount({
    required this.id,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    required this.transferInstruction,
    required this.isDefault,
  });

  bool get isComplete =>
      bankName.trim().isNotEmpty &&
      accountName.trim().isNotEmpty &&
      accountNumber.trim().isNotEmpty &&
      transferInstruction.trim().isNotEmpty;

  String get maskedAccountLabel {
    final digits = accountNumber.replaceAll(RegExp(r"\D+"), "");
    final tail = digits.length >= 4
        ? digits.substring(digits.length - 4)
        : digits;
    return tail.isEmpty ? bankName : "$bankName •••• $tail";
  }

  factory PurchaseRequestPaymentAccount.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestPaymentAccount(
      id: _parseString(json["id"] ?? json["_id"] ?? json["accountId"]),
      bankName: _parseString(json["bankName"]),
      accountName: _parseString(json["accountName"]),
      accountNumber: _parseString(json["accountNumber"]),
      transferInstruction: _parseString(json["transferInstruction"]),
      isDefault: json["isDefault"] == true,
    );
  }
}

class PurchaseRequestInvoice {
  final String invoiceNumber;
  final int totalAmountCents;
  final String paymentInstructions;
  final PurchaseRequestPaymentAccount paymentAccount;
  final String note;
  final DateTime? estimatedDeliveryDate;
  final DateTime? sentAt;
  final String sentByUserId;
  final String sentByRole;

  const PurchaseRequestInvoice({
    required this.invoiceNumber,
    required this.totalAmountCents,
    required this.paymentInstructions,
    required this.paymentAccount,
    required this.note,
    required this.estimatedDeliveryDate,
    required this.sentAt,
    required this.sentByUserId,
    required this.sentByRole,
  });

  bool get isSent => sentAt != null || paymentInstructions.trim().isNotEmpty;

  factory PurchaseRequestInvoice.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestInvoice(
      invoiceNumber: _parseString(json["invoiceNumber"]),
      totalAmountCents: _parseInt(json["totalAmount"]),
      paymentInstructions: _parseString(json["paymentInstructions"]),
      paymentAccount: PurchaseRequestPaymentAccount.fromJson(
        (json["paymentAccount"] is Map<String, dynamic>)
            ? json["paymentAccount"] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      note: _parseString(json["note"]),
      estimatedDeliveryDate: _parseDate(json["estimatedDeliveryDate"]),
      sentAt: _parseDate(json["sentAt"]),
      sentByUserId: _parseString(json["sentByUserId"]),
      sentByRole: _parseString(json["sentByRole"]),
    );
  }
}

class PurchaseRequestFulfillment {
  final String linkedOrderId;
  final String orderStatus;
  final String carrierName;
  final String trackingReference;
  final String dispatchNote;
  final DateTime? estimatedDeliveryDate;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final DateTime? orderCreatedAt;
  final DateTime? orderUpdatedAt;

  const PurchaseRequestFulfillment({
    required this.linkedOrderId,
    required this.orderStatus,
    required this.carrierName,
    required this.trackingReference,
    required this.dispatchNote,
    required this.estimatedDeliveryDate,
    required this.shippedAt,
    required this.deliveredAt,
    required this.orderCreatedAt,
    required this.orderUpdatedAt,
  });

  bool get isShipped => orderStatus.trim().toLowerCase() == "shipped";
  bool get isDelivered => orderStatus.trim().toLowerCase() == "delivered";

  factory PurchaseRequestFulfillment.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestFulfillment(
      linkedOrderId: _parseString(json["linkedOrderId"]),
      orderStatus: _parseString(json["orderStatus"]),
      carrierName: _parseString(json["carrierName"]),
      trackingReference: _parseString(json["trackingReference"]),
      dispatchNote: _parseString(json["dispatchNote"]),
      estimatedDeliveryDate: _parseDate(json["estimatedDeliveryDate"]),
      shippedAt: _parseDate(json["shippedAt"]),
      deliveredAt: _parseDate(json["deliveredAt"]),
      orderCreatedAt: _parseDate(json["orderCreatedAt"]),
      orderUpdatedAt: _parseDate(json["orderUpdatedAt"]),
    );
  }
}

class PurchaseRequestProof {
  final String attachmentId;
  final String url;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String note;
  final DateTime? submittedAt;
  final String submittedByUserId;
  final DateTime? reviewedAt;
  final String reviewedByUserId;
  final String reviewedByRole;
  final String reviewDecision;
  final String reviewNote;

  const PurchaseRequestProof({
    required this.attachmentId,
    required this.url,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.note,
    required this.submittedAt,
    required this.submittedByUserId,
    required this.reviewedAt,
    required this.reviewedByUserId,
    required this.reviewedByRole,
    required this.reviewDecision,
    required this.reviewNote,
  });

  bool get isSubmitted => submittedAt != null && attachmentId.isNotEmpty;

  factory PurchaseRequestProof.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestProof(
      attachmentId: _parseString(json["attachmentId"]),
      url: _parseString(json["url"]),
      filename: _parseString(json["filename"]),
      mimeType: _parseString(json["mimeType"]),
      sizeBytes: _parseInt(json["sizeBytes"]),
      note: _parseString(json["note"]),
      submittedAt: _parseDate(json["submittedAt"]),
      submittedByUserId: _parseString(json["submittedByUserId"]),
      reviewedAt: _parseDate(json["reviewedAt"]),
      reviewedByUserId: _parseString(json["reviewedByUserId"]),
      reviewedByRole: _parseString(json["reviewedByRole"]),
      reviewDecision: _parseString(json["reviewDecision"]),
      reviewNote: _parseString(json["reviewNote"]),
    );
  }
}

class PurchaseRequestCustomerCare {
  final String assistantName;
  final bool isEnabled;
  final String currentAttendantUserId;
  final String currentAttendantName;
  final String currentAttendantRole;
  final String currentAttendantStaffRole;
  final DateTime? lastUpdatedAt;

  const PurchaseRequestCustomerCare({
    required this.assistantName,
    required this.isEnabled,
    required this.currentAttendantUserId,
    required this.currentAttendantName,
    required this.currentAttendantRole,
    required this.currentAttendantStaffRole,
    required this.lastUpdatedAt,
  });

  bool get hasHumanAttendant =>
      !isEnabled && currentAttendantUserId.trim().isNotEmpty;

  bool get aiControlEnabled => isEnabled;

  String get attendantLabel {
    final raw = currentAttendantStaffRole.trim().isNotEmpty
        ? currentAttendantStaffRole
        : currentAttendantRole;
    return raw.replaceAll("_", " ").trim();
  }

  factory PurchaseRequestCustomerCare.fromJson(Map<String, dynamic> json) {
    return PurchaseRequestCustomerCare(
      assistantName: _parseString(json["assistantName"]).isEmpty
          ? "Amara"
          : _parseString(json["assistantName"]),
      isEnabled: json["isEnabled"] == false ? false : true,
      currentAttendantUserId: _parseString(json["currentAttendantUserId"]),
      currentAttendantName: _parseString(json["currentAttendantName"]),
      currentAttendantRole: _parseString(json["currentAttendantRole"]),
      currentAttendantStaffRole: _parseString(
        json["currentAttendantStaffRole"],
      ),
      lastUpdatedAt: _parseDate(json["lastUpdatedAt"]),
    );
  }
}

class PurchaseRequest {
  final String id;
  final String customerId;
  final String businessId;
  final String conversationId;
  final String reservationId;
  final String linkedOrderId;
  final String status;
  final String currencyCode;
  final List<PurchaseRequestItem> items;
  final int subtotalAmountCents;
  final PurchaseRequestCharges charges;
  final OrderDeliveryAddress? deliveryAddress;
  final PurchaseRequestInvoice invoice;
  final PurchaseRequestProof proof;
  final PurchaseRequestCustomerCare customerCare;
  final PurchaseRequestFulfillment? fulfillment;
  final List<PurchaseRequestPaymentAccount> availablePaymentAccounts;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;
  final String cancelReason;

  const PurchaseRequest({
    required this.id,
    required this.customerId,
    required this.businessId,
    required this.conversationId,
    required this.reservationId,
    required this.linkedOrderId,
    required this.status,
    required this.currencyCode,
    required this.items,
    required this.subtotalAmountCents,
    required this.charges,
    required this.deliveryAddress,
    required this.invoice,
    required this.proof,
    required this.customerCare,
    required this.fulfillment,
    required this.availablePaymentAccounts,
    required this.createdAt,
    required this.updatedAt,
    required this.cancelledAt,
    required this.cancelReason,
  });

  bool get isCancelled => status == "cancelled";
  bool get isApproved => status == "approved";
  bool get isQuoted => status == "quoted";
  bool get isRejected => status == "rejected";
  bool get isProofSubmitted => status == "proof_submitted";
  bool get isRequested => status == "requested";
  bool get aiControlEnabled => customerCare.aiControlEnabled;
  bool get isAiInControl => customerCare.aiControlEnabled;
  String get assistantName => customerCare.assistantName;
  bool get canBuyerSubmitProof => isQuoted || isRejected;
  bool get canSellerReviewProof => isProofSubmitted;
  bool get canSellerEditInvoice =>
      !isCancelled && !isApproved && !isProofSubmitted;
  String get linkedOrderStatus => fulfillment?.orderStatus.trim() ?? "";
  int get customerVisibleLogisticsFeeCents => charges.logisticsFeeCents;
  DateTime? get activeEstimatedDeliveryDate =>
      fulfillment?.estimatedDeliveryDate ?? invoice.estimatedDeliveryDate;
  int get totalAmountCents => invoice.totalAmountCents > 0
      ? invoice.totalAmountCents
      : subtotalAmountCents + charges.totalChargesCents;
  String get progressStage {
    if (isApproved) {
      switch (linkedOrderStatus.toLowerCase()) {
        case "shipped":
          return "shipped";
        case "delivered":
          return "delivered";
        default:
          return "approved";
      }
    }
    return status;
  }

  factory PurchaseRequest.fromJson(Map<String, dynamic> json) {
    final rawItems = (json["items"] ?? []) as List<dynamic>;
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(PurchaseRequestItem.fromJson)
        .toList();
    final chargesMap = (json["charges"] is Map<String, dynamic>)
        ? json["charges"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final invoiceMap = (json["invoice"] is Map<String, dynamic>)
        ? json["invoice"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final proofMap = (json["proof"] is Map<String, dynamic>)
        ? json["proof"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final customerCareMap = (json["customerCare"] is Map<String, dynamic>)
        ? json["customerCare"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final fulfillmentMap = (json["fulfillment"] is Map<String, dynamic>)
        ? json["fulfillment"] as Map<String, dynamic>
        : null;
    final deliveryMap = (json["deliveryAddress"] is Map<String, dynamic>)
        ? json["deliveryAddress"] as Map<String, dynamic>
        : null;
    final rawPaymentAccounts =
        (json["availablePaymentAccounts"] ?? const <dynamic>[])
            as List<dynamic>;
    final availablePaymentAccounts = rawPaymentAccounts
        .whereType<Map<String, dynamic>>()
        .map(PurchaseRequestPaymentAccount.fromJson)
        .toList();

    return PurchaseRequest(
      id: _parseString(json["_id"] ?? json["id"]),
      customerId: _parseString(json["customerId"]),
      businessId: _parseString(json["businessId"]),
      conversationId: _parseString(json["conversationId"]),
      reservationId: _parseString(json["reservationId"]),
      linkedOrderId: _parseString(json["linkedOrderId"]),
      status: _parseString(json["status"]),
      currencyCode: _parseString(json["currencyCode"]).isEmpty
          ? "NGN"
          : _parseString(json["currencyCode"]),
      items: items,
      subtotalAmountCents: _parseInt(json["subtotalAmount"]),
      charges: PurchaseRequestCharges.fromJson(chargesMap),
      deliveryAddress: deliveryMap == null
          ? null
          : OrderDeliveryAddress.fromJson(deliveryMap),
      invoice: PurchaseRequestInvoice.fromJson(invoiceMap),
      proof: PurchaseRequestProof.fromJson(proofMap),
      customerCare: PurchaseRequestCustomerCare.fromJson(customerCareMap),
      fulfillment: fulfillmentMap == null
          ? null
          : PurchaseRequestFulfillment.fromJson(fulfillmentMap),
      availablePaymentAccounts: availablePaymentAccounts,
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
      cancelledAt: _parseDate(json["cancelledAt"]),
      cancelReason: _parseString(json["cancelReason"]),
    );
  }
}

class PurchaseRequestCreateResult {
  final PurchaseRequest purchaseRequest;
  final String conversationId;

  const PurchaseRequestCreateResult({
    required this.purchaseRequest,
    required this.conversationId,
  });
}

class PurchaseRequestBatchResult {
  final List<PurchaseRequestCreateResult> requests;

  const PurchaseRequestBatchResult({required this.requests});
}

class PurchaseRequestReviewResult {
  final PurchaseRequest purchaseRequest;
  final String orderId;

  const PurchaseRequestReviewResult({
    required this.purchaseRequest,
    required this.orderId,
  });
}
