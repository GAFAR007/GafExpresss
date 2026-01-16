/// lib/app/router.dart
/// -------------------
/// WHAT THIS FILE IS:
/// - Central routing config using go_router.
///
/// WHY IT'S IMPORTANT:
/// - If routes/imports are wrong, the app won't compile.
/// - This is the #1 place where "constructor not found" happens.
///
/// HOW IT WORKS:
/// - initialLocation: /login
/// - routes: /login, /register, /home, /product/:id
///
/// DEBUGGING:
/// - Logs whenever router builds.
/// - Logs every route builder call so you can trace navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/app/features/home/presentation/presentation/login_screen.dart';
import 'package:frontend/app/features/home/presentation/presentation/register_screen.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

import 'package:frontend/app/features/home/presentation/cart_screen.dart';
import 'package:frontend/app/features/home/presentation/home_screen.dart';
import 'package:frontend/app/features/home/presentation/my_orders_screen.dart';
import 'package:frontend/app/features/home/presentation/order_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/features/home/presentation/payment_success_screen.dart';
import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/product_detail_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  final bool isAuthed = session != null && session.isTokenValid;

  AppDebug.log(
    "ROUTER",
    "buildRouter()",
    extra: {"isAuthed": isAuthed},
  );

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final String path = state.matchedLocation;
      final bool isAuthRoute = path == '/login' || path == '/register';
      final bool isPublicProduct = path.startsWith('/product/');
      final bool isPaymentSuccess = path == '/payment-success';
      final bool isPublicRoute =
          isAuthRoute || isPublicProduct || isPaymentSuccess;

      // WHY: If not logged in, block protected routes.
      if (!isAuthed && !isPublicRoute) {
        AppDebug.log("ROUTER", "redirect -> /login", extra: {"from": path});
        return '/login';
      }

      // WHY: If logged in, keep user out of auth screens.
      if (isAuthed && isAuthRoute) {
        AppDebug.log("ROUTER", "redirect -> /home", extra: {"from": path});
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /login");
          return const LoginScreen();
        },
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /register");
          return const RegisterScreen();
        },
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /home");
          return const HomeScreen();
        },
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /cart");
          return const CartScreen();
        },
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /orders");
          return const MyOrdersScreen();
        },
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;

          AppDebug.log("ROUTER", "-> /orders/:id", extra: {"id": id});

          if (extra is! Order) {
            AppDebug.log(
              "ROUTER",
              "OrderDetail missing extra",
              extra: {"id": id},
            );
            return const Scaffold(
              body: Center(child: Text('Order data missing')),
            );
          }

          return OrderDetailScreen(order: extra);
        },
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log("ROUTER", "-> /product/:id", extra: {"id": id});
          return ProductDetailScreen(productId: id);
        },
      ),
      GoRoute(
        path: '/payment-success',
        builder: (context, state) {
          final reference = state.uri.queryParameters['reference'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /payment-success",
            extra: {"reference": reference},
          );
          return PaymentSuccessScreen(reference: reference);
        },
      ),
      GoRoute(
        path: '/paystack',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /paystack");
          final extra = state.extra;

          if (extra is! PaystackCheckoutArgs) {
            AppDebug.log("ROUTER", "Paystack args missing");
            return const Scaffold(
              body: Center(child: Text('Paystack args missing')),
            );
          }

          return PaystackCheckoutScreen(args: extra);
        },
      ),
    ],
    errorBuilder: (context, state) {
      AppDebug.log(
        "ROUTER",
        "errorBuilder()",
        extra: {"error": state.error.toString()},
      );

      return Scaffold(body: Center(child: Text('Route error: ${state.error}')));
    },
  );
});
