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
/// - routes: /login, /register, /home, /cart, /orders, /settings, /product/:id
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
import 'package:frontend/app/features/home/presentation/business_account_screen.dart';
import 'package:frontend/app/features/home/presentation/business_asset_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/business_assets_screen.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_dashboard_screen.dart';
import 'package:frontend/app/features/home/presentation/business_orders_screen.dart';
import 'package:frontend/app/features/home/presentation/business_order_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/business_order_model.dart';
import 'package:frontend/app/features/home/presentation/business_product_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/business_products_screen.dart';
import 'package:frontend/app/features/home/presentation/business_register_help_screen.dart';
import 'package:frontend/app/features/home/presentation/business_team_screen.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_applications_screen.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_review_screen.dart';
import 'package:frontend/app/features/home/presentation/business_invite_screen.dart';
import 'package:frontend/app/features/home/presentation/business_verified_screen.dart';
import 'package:frontend/app/features/home/presentation/business_verify_screen.dart';
import 'package:frontend/app/features/home/presentation/home_screen.dart';
import 'package:frontend/app/features/home/presentation/my_orders_screen.dart';
import 'package:frontend/app/features/home/presentation/order_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/features/home/presentation/payment_success_screen.dart';
import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/product_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/settings_screen.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_screen.dart';
import 'package:frontend/app/theme/business_theme_wrapper.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(authSessionProvider);
  final bool isAuthed = session != null && session.isTokenValid;

  AppDebug.log("ROUTER", "buildRouter()", extra: {"isAuthed": isAuthed});

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final String path = state.matchedLocation;
      final bool isAuthRoute = path == '/login' || path == '/register';
      final bool isPublicProduct = path.startsWith('/product/');
      final bool isPaymentSuccess = path == '/payment-success';
      final bool isBusinessInvite = path.startsWith('/business-invite');
      final bool isTenantVerification = path == '/tenant-verification';
      final bool isPublicRoute =
          isAuthRoute ||
          isPublicProduct ||
          isPaymentSuccess ||
          isBusinessInvite;
      final bool isBusinessProtectedRoute =
          path.startsWith('/business-dashboard') ||
          path.startsWith('/business-products') ||
          path.startsWith('/business-orders') ||
          path.startsWith('/business-assets') ||
          path.startsWith('/business-team') ||
          path.startsWith('/business-tenants') ||
          path.startsWith('/tenant-review');

      // WHY: If not logged in, block protected routes.
      if (!isAuthed && !isPublicRoute) {
        AppDebug.log("ROUTER", "redirect -> /login", extra: {"from": path});
        return '/login';
      }

      // WHY: If logged in, keep user out of auth screens.
      if (isAuthed && isAuthRoute) {
        final nextParam = state.uri.queryParameters['next'];
        final decodedNext = nextParam == null || nextParam.trim().isEmpty
            ? null
            : Uri.decodeComponent(nextParam.trim());
        final nextTarget =
            decodedNext != null && decodedNext.startsWith('/')
                ? decodedNext
                : '/home';

        AppDebug.log(
          "ROUTER",
          "redirect after auth",
          extra: {"from": path, "to": nextTarget},
        );
        return nextTarget;
      }

      // WHY: Only business owners/staff can access the business dashboard.
      if (isAuthed && isBusinessProtectedRoute) {
        final role = session.user.role;
        final isBusinessRole = role == 'business_owner' || role == 'staff';

        if (!isBusinessRole) {
          AppDebug.log(
            "ROUTER",
            "redirect -> /settings (business guard)",
            extra: {"role": role},
          );
          return '/settings';
        }
      }

      // WHY: Tenant verification can be reviewed by tenant/staff/owners.
      if (isAuthed && isTenantVerification) {
        final role = session.user.role;
        final allowedRoles = ['tenant', 'business_owner', 'staff'];
        if (!allowedRoles.contains(role)) {
          AppDebug.log(
            "ROUTER",
            "redirect -> /settings (tenant guard)",
            extra: {"role": role, "allowed": allowedRoles},
          );
          return '/settings';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final redirectTo = state.uri.queryParameters['next'];
          AppDebug.log("ROUTER", "-> /login");
          return LoginScreen(redirectTo: redirectTo);
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
        path: '/settings',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /settings");
          return const SettingsScreen();
        },
      ),
      GoRoute(
        path: '/business-invite',
        builder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /business-invite",
            extra: {"hasToken": token.isNotEmpty},
          );
          // WHY: Allow invite links to open without auth so users see instructions.
          return BusinessInviteScreen(token: token);
        },
      ),
      GoRoute(
        path: '/tenant-verification',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /tenant-verification");
          // WHY: Tenant onboarding should inherit business theme styles.
          return const BusinessThemeWrapper(
            child: TenantVerificationScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-account',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'] ?? 'business';
          AppDebug.log("ROUTER", "-> /business-account", extra: {"type": type});
          // WHY: Keep the business palette scoped to business-only routes.
          return BusinessThemeWrapper(
            child: BusinessAccountScreen(accountType: type),
          );
        },
      ),
      GoRoute(
        path: '/business-dashboard',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-dashboard");
          return const BusinessThemeWrapper(
            child: BusinessDashboardScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-products',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-products");
          return const BusinessThemeWrapper(
            child: BusinessProductsScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-products/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /business-products/:id",
            extra: {"id": id},
          );
          return BusinessThemeWrapper(
            child: BusinessProductDetailScreen(productId: id),
          );
        },
      ),
      GoRoute(
        path: '/business-orders',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-orders");
          return const BusinessThemeWrapper(
            child: BusinessOrdersScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-orders/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /business-orders/:id",
            extra: {"id": id},
          );
          final extra = state.extra;
          if (extra is BusinessOrder) {
            return BusinessThemeWrapper(
              child: BusinessOrderDetailScreen(order: extra),
            );
          }
          return const BusinessThemeWrapper(
            child: BusinessOrdersScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-assets',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-assets");
          return const BusinessThemeWrapper(
            child: BusinessAssetsScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-assets/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /business-assets/:id",
            extra: {"id": id},
          );
          final extra = state.extra;
          if (extra is BusinessAsset) {
            return BusinessThemeWrapper(
              child: BusinessAssetDetailScreen(asset: extra),
            );
          }
          // WHY: Avoid a broken detail screen when no asset was passed.
          AppDebug.log(
            "ROUTER",
            "Asset detail missing extra",
            extra: {"id": id},
          );
          return const BusinessThemeWrapper(
            child: BusinessAssetsScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-team',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-team");
          return const BusinessThemeWrapper(
            child: BusinessTeamScreen(),
          );
        },
      ),
      GoRoute(
        path: '/business-tenants',
        builder: (context, state) {
          final estateAssetId = state.uri.queryParameters['estateAssetId'];
          AppDebug.log(
            "ROUTER",
            "-> /business-tenants",
            extra: {
              "hasEstate": estateAssetId != null && estateAssetId.isNotEmpty,
            },
          );
          return BusinessThemeWrapper(
            child: BusinessTenantApplicationsScreen(
              estateAssetId: estateAssetId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/tenant-review/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /tenant-review/:id",
            extra: {"id": id},
          );
          return BusinessThemeWrapper(
            child: BusinessTenantReviewScreen(applicationId: id),
          );
        },
      ),
      GoRoute(
        path: '/business-verify',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'] ?? 'business';
          AppDebug.log("ROUTER", "-> /business-verify", extra: {"type": type});
          return BusinessThemeWrapper(
            child: BusinessVerifyScreen(accountType: type),
          );
        },
      ),
      GoRoute(
        path: '/business-verified',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'] ?? 'business';
          AppDebug.log(
            "ROUTER",
            "-> /business-verified",
            extra: {"type": type},
          );
          return BusinessThemeWrapper(
            child: BusinessVerifiedScreen(accountType: type),
          );
        },
      ),
      GoRoute(
        path: '/business-register-help',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'] ?? 'business';
          AppDebug.log(
            "ROUTER",
            "-> /business-register-help",
            extra: {"type": type},
          );
          return BusinessThemeWrapper(
            child: BusinessRegisterHelpScreen(accountType: type),
          );
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
