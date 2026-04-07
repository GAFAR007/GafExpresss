/// lib/app/features/home/presentation/business_order_model.dart
/// ------------------------------------------------------------
/// WHAT:
/// - BusinessOrder models for the business orders screens.
///
/// WHY:
/// - Business orders include extra audit data (user + status history).
/// - Keeps parsing logic isolated from UI widgets.
///
/// HOW:
/// - Maps JSON from /business/orders into typed objects.
/// - Reuses OrderItem + OrderDeliveryAddress from order_model.dart.
///
/// DEBUGGING:
/// - Logs parsing with order id (safe only).
/// ------------------------------------------------------------
library;

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';

class BusinessOrderUser {
  final String id;
  final String name;
  final String email;
  final String role;

  const BusinessOrderUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory BusinessOrderUser.fromJson(Map<String, dynamic> json) {
    return BusinessOrderUser(
      id: (json["_id"] ?? json["id"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
      email: (json["email"] ?? "").toString(),
      role: (json["role"] ?? "").toString(),
    );
  }
}

class BusinessOrderStatusEntry {
  final String status;
  final DateTime? changedAt;
  final String? changedBy;
  final String? changedByRole;
  final String? note;

  const BusinessOrderStatusEntry({
    required this.status,
    required this.changedAt,
    required this.changedBy,
    required this.changedByRole,
    required this.note,
  });

  factory BusinessOrderStatusEntry.fromJson(Map<String, dynamic> json) {
    return BusinessOrderStatusEntry(
      status: (json["status"] ?? "").toString(),
      changedAt: _parseDate(json["changedAt"]),
      changedBy: (json["changedBy"] ?? "").toString(),
      changedByRole: (json["changedByRole"] ?? "").toString(),
      note: (json["note"] ?? "").toString(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

class BusinessOrderFulfillment {
  final String carrierName;
  final String trackingReference;
  final String dispatchNote;
  final DateTime? estimatedDeliveryDate;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;

  const BusinessOrderFulfillment({
    required this.carrierName,
    required this.trackingReference,
    required this.dispatchNote,
    required this.estimatedDeliveryDate,
    required this.shippedAt,
    required this.deliveredAt,
  });

  factory BusinessOrderFulfillment.fromJson(Map<String, dynamic> json) {
    return BusinessOrderFulfillment(
      carrierName: (json["carrierName"] ?? "").toString(),
      trackingReference: (json["trackingReference"] ?? "").toString(),
      dispatchNote: (json["dispatchNote"] ?? "").toString(),
      estimatedDeliveryDate: BusinessOrderStatusEntry._parseDate(
        json["estimatedDeliveryDate"],
      ),
      shippedAt: BusinessOrderStatusEntry._parseDate(json["shippedAt"]),
      deliveredAt: BusinessOrderStatusEntry._parseDate(json["deliveredAt"]),
    );
  }
}

class BusinessOrder {
  final String id;
  final String status;
  final String paymentSource;
  final int totalPriceCents;
  final int logisticsFeeCents;
  final int serviceChargeCents;
  final List<OrderItem> items;
  final OrderDeliveryAddress? deliveryAddress;
  final BusinessOrderUser? user;
  final List<String> businessIds;
  final List<BusinessOrderStatusEntry> statusHistory;
  final BusinessOrderFulfillment? fulfillment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BusinessOrder({
    required this.id,
    required this.status,
    required this.paymentSource,
    required this.totalPriceCents,
    required this.logisticsFeeCents,
    required this.serviceChargeCents,
    required this.items,
    required this.deliveryAddress,
    required this.user,
    required this.businessIds,
    required this.statusHistory,
    required this.fulfillment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessOrder.fromJson(Map<String, dynamic> json) {
    final id = (json["_id"] ?? json["id"] ?? "").toString();

    AppDebug.log("BUSINESS_ORDER_MODEL", "fromJson()", extra: {"id": id});

    final rawItems = (json["items"] ?? []) as List<dynamic>;
    final items = rawItems
        .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
        .toList();

    final deliveryMap = json["deliveryAddress"];
    final deliveryAddress = deliveryMap is Map<String, dynamic>
        ? OrderDeliveryAddress.fromJson(deliveryMap)
        : null;

    final userMap = json["user"];
    final user = userMap is Map<String, dynamic>
        ? BusinessOrderUser.fromJson(userMap)
        : null;

    final rawBusinessIds = (json["businessIds"] ?? []) as List<dynamic>;
    final businessIds = rawBusinessIds.map((id) => id.toString()).toList();

    final rawHistory = (json["statusHistory"] ?? []) as List<dynamic>;
    final statusHistory = rawHistory
        .map(
          (entry) =>
              BusinessOrderStatusEntry.fromJson(entry as Map<String, dynamic>),
        )
        .toList();
    final fulfillmentMap = json["fulfillment"];
    final fulfillment = fulfillmentMap is Map<String, dynamic>
        ? BusinessOrderFulfillment.fromJson(fulfillmentMap)
        : null;

    return BusinessOrder(
      id: id,
      status: (json["status"] ?? "").toString(),
      paymentSource: (json["paymentSource"] ?? "paystack").toString(),
      totalPriceCents: (json["totalPrice"] ?? 0) is int
          ? (json["totalPrice"] ?? 0) as int
          : int.tryParse((json["totalPrice"] ?? 0).toString()) ?? 0,
      logisticsFeeCents: _parseFee(json["charges"], "logisticsFee"),
      serviceChargeCents: _parseFee(json["charges"], "serviceCharge"),
      items: items,
      deliveryAddress: deliveryAddress,
      user: user,
      businessIds: businessIds,
      statusHistory: statusHistory,
      fulfillment: fulfillment,
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static int _parseFee(dynamic charges, String key) {
    if (charges is! Map<String, dynamic>) {
      return 0;
    }
    final value = charges[key];
    if (value is int) return value;
    return int.tryParse((value ?? 0).toString()) ?? 0;
  }
}
