/// lib/app/features/home/presentation/cart_model.dart
/// ------------------------------------------------------------
/// WHAT:
/// - CartItem represents a single product in the cart.
///
/// WHY:
/// - Keeps cart data structured and reusable across screens.
/// - Lets us convert cart items into order payloads safely.
///
/// HOW:
/// - Build CartItem from Product when user adds to cart.
/// - Provide helpers for totals and order payload mapping.
///
/// DEBUGGING:
/// - Logs item creation (safe fields only).
/// ------------------------------------------------------------

import 'package:frontend/app/core/debug/app_debug.dart';
import 'product_model.dart';

class CartItem {
  final String productId;
  final String name;
  final String imageUrl;
  final int unitPriceCents;
  final int quantity;

  const CartItem({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.unitPriceCents,
    required this.quantity,
  });

  /// WHY: Central place to build cart items from Product.
  factory CartItem.fromProduct(Product product, {int quantity = 1}) {
    final safeQty = quantity <= 0 ? 1 : quantity;

    AppDebug.log(
      "CART_MODEL",
      "fromProduct()",
      extra: {"productId": product.id, "qty": safeQty},
    );

    return CartItem(
      productId: product.id,
      name: product.name,
      imageUrl: product.imageUrl,
      unitPriceCents: product.priceCents,
      quantity: safeQty,
    );
  }

  /// WHY: Keep total calculations consistent everywhere.
  int get lineTotalCents => unitPriceCents * quantity;

  /// WHY: Payload for /orders POST.
  Map<String, dynamic> toOrderItemJson() {
    return {
      "productId": productId,
      "quantity": quantity,
    };
  }

  CartItem copyWith({int? quantity}) {
    return CartItem(
      productId: productId,
      name: name,
      imageUrl: imageUrl,
      unitPriceCents: unitPriceCents,
      quantity: quantity ?? this.quantity,
    );
  }
}
