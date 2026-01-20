/// lib/app/features/home/presentation/order_model.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Order and OrderItem models for UI rendering.
///
/// WHY:
/// - Keeps /orders parsing in one place.
/// - Allows detail screen to show structured data.
///
/// HOW:
/// - fromJson handles both populated product objects and raw ids.
///
/// DEBUGGING:
/// - Logs parsing with order id (safe only).
/// ------------------------------------------------------------

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';

class OrderItem {
  final String productId;
  final String name;
  final String imageUrl;
  final int quantity;
  final int unitPriceCents;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.quantity,
    required this.unitPriceCents,
  });

  /// WHY: Keep line totals consistent everywhere.
  int get lineTotalCents => unitPriceCents * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final product = json["product"];

    // WHY: Backend may return populated product or just id.
    final Map<String, dynamic> productMap =
        product is Map<String, dynamic> ? product : const {};

    final productId = (productMap["_id"] ??
            productMap["id"] ??
            product ??
            "")
        .toString();

    return OrderItem(
      productId: productId,
      name: (productMap["name"] ?? "").toString(),
      imageUrl: (productMap["imageUrl"] ?? "").toString(),
      quantity: (json["quantity"] ?? 0) is int
          ? (json["quantity"] ?? 0) as int
          : int.tryParse((json["quantity"] ?? 0).toString()) ?? 0,
      unitPriceCents: (json["price"] ?? 0) is int
          ? (json["price"] ?? 0) as int
          : int.tryParse((json["price"] ?? 0).toString()) ?? 0,
    );
  }
}

class OrderDeliveryAddress {
  final String source;
  final UserAddress address;

  const OrderDeliveryAddress({
    required this.source,
    required this.address,
  });

  factory OrderDeliveryAddress.fromJson(Map<String, dynamic> json) {
    return OrderDeliveryAddress(
      source: (json["source"] ?? "").toString(),
      address: UserAddress.fromJson(json),
    );
  }
}

class Order {
  final String id;
  final String status;
  final int totalPriceCents;
  final List<OrderItem> items;
  final OrderDeliveryAddress? deliveryAddress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Order({
    required this.id,
    required this.status,
    required this.totalPriceCents,
    required this.items,
    required this.deliveryAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final id = (json["_id"] ?? json["id"] ?? "").toString();

    AppDebug.log("ORDER_MODEL", "fromJson()", extra: {"id": id});

    final rawItems = (json["items"] ?? []) as List<dynamic>;
    final items = rawItems
        .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
        .toList();

    final deliveryMap = json["deliveryAddress"];
    final deliveryAddress = deliveryMap is Map<String, dynamic>
        ? OrderDeliveryAddress.fromJson(deliveryMap)
        : null;

    return Order(
      id: id,
      status: (json["status"] ?? "").toString(),
      totalPriceCents: (json["totalPrice"] ?? 0) is int
          ? (json["totalPrice"] ?? 0) as int
          : int.tryParse((json["totalPrice"] ?? 0).toString()) ?? 0,
      items: items,
      deliveryAddress: deliveryAddress,
      createdAt: _parseDate(json["createdAt"]),
      updatedAt: _parseDate(json["updatedAt"]),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
