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

import 'package:frontend/app/features/home/presentation/home_screen.dart';
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
      final bool isPublicRoute = isAuthRoute || isPublicProduct;

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
        path: '/product/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log("ROUTER", "-> /product/:id", extra: {"id": id});
          return ProductDetailScreen(productId: id);
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
