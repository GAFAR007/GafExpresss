/// lib/app/features/home/presentation/cart_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod cart state + controller.
///
/// WHY:
/// - Centralizes cart mutations (add/remove/update).
/// - Keeps UI logic small and predictable.
///
/// HOW:
/// - CartController manages a CartState with a list of CartItem.
/// - UI reads cartProvider to render items and totals.
///
/// DEBUGGING:
/// - Logs provider creation and every cart mutation.
/// ------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'cart_model.dart';
import 'product_model.dart';

class CartState {
  final List<CartItem> items;

  const CartState({required this.items});

  bool get isEmpty => items.isEmpty;

  /// WHY: Used to show the cart badge and summary.
  int get totalItems =>
      items.fold(0, (total, item) => total + item.quantity);

  /// WHY: Used for checkout and display.
  int get totalCents =>
      items.fold(0, (total, item) => total + item.lineTotalCents);
}

class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState(items: []));

  /// WHY: Adds product to cart or increases quantity if already present.
  void addProduct(Product product, {int quantity = 1}) {
    AppDebug.log(
      "CART",
      "addProduct()",
      extra: {"productId": product.id, "qty": quantity},
    );

    final items = [...state.items];
    final index = items.indexWhere((item) => item.productId == product.id);

    if (index == -1) {
      items.add(CartItem.fromProduct(product, quantity: quantity));
    } else {
      final existing = items[index];
      items[index] = existing.copyWith(
        quantity: existing.quantity + (quantity <= 0 ? 1 : quantity),
      );
    }

    state = CartState(items: items);
  }

  /// WHY: Remove a product completely from cart.
  void removeProduct(String productId) {
    AppDebug.log("CART", "removeProduct()", extra: {"productId": productId});

    final items =
        state.items.where((item) => item.productId != productId).toList();
    state = CartState(items: items);
  }

  /// WHY: Update quantity with validation (0 => remove).
  void updateQuantity(String productId, int quantity) {
    AppDebug.log(
      "CART",
      "updateQuantity()",
      extra: {"productId": productId, "qty": quantity},
    );

    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }

    final items = [...state.items];
    final index = items.indexWhere((item) => item.productId == productId);

    if (index == -1) return;

    items[index] = items[index].copyWith(quantity: quantity);
    state = CartState(items: items);
  }

  /// WHY: Clears cart after checkout or user intent.
  void clearCart() {
    AppDebug.log("CART", "clearCart()");
    state = const CartState(items: []);
  }
}

final cartProvider = StateNotifierProvider<CartController, CartState>((ref) {
  AppDebug.log("PROVIDERS", "cartProvider created");
  return CartController();
});
