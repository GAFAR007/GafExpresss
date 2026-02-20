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
library;

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
import 'package:frontend/app/features/home/presentation/business_tenant_applications_screen.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_review_screen.dart';
import 'package:frontend/app/features/home/presentation/payments/business_tenant_payment_history_screen.dart';
import 'package:frontend/app/features/home/presentation/payments/tenant_payment_receipts_screen.dart';
import 'package:frontend/app/features/home/presentation/business_invite_screen.dart';
import 'package:frontend/app/features/home/presentation/business_staff_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_screen.dart';
import 'package:frontend/app/features/home/presentation/business_staff_routes.dart';
import 'package:frontend/app/features/home/presentation/business_verified_screen.dart';
import 'package:frontend/app/features/home/presentation/business_verify_screen.dart';
import 'package:frontend/app/features/home/presentation/home_screen.dart';
import 'package:frontend/app/features/home/presentation/tenant_dashboard_screen.dart';
import 'package:frontend/app/features/home/presentation/my_orders_screen.dart';
import 'package:frontend/app/features/home/presentation/order_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/chat_inbox_screen.dart';
import 'package:frontend/app/features/home/presentation/chat_thread_screen.dart';
import 'package:frontend/app/features/home/presentation/chat_routes.dart';
import 'package:frontend/app/features/home/presentation/chat_models.dart';
import 'package:frontend/app/features/home/presentation/order_model.dart';
import 'package:frontend/app/features/home/presentation/payment_success_screen.dart';
import 'package:frontend/app/features/home/presentation/paystack_checkout_screen.dart';
import 'package:frontend/app/features/home/presentation/product_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/settings_screen.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_list_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_calendar_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_assistant_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_create_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_plan_detail_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_preorder_reservations_screen.dart';
import 'package:frontend/app/features/home/presentation/production/production_routes.dart';
import 'package:frontend/app/theme/business_theme_wrapper.dart';

// WHY: Keep route keys centralized for payment history navigation extras.
const String _tenantNameExtraKey = "tenantName";
const String _productionPlanIdParam = "id";
const String _staffProfileIdParam = "id";
const String _routeProductionListLog = "-> /business-production";
const String _routeProductionCalendarLog = "-> /business-production/calendar";
const String _routeProductionAssistantLog =
    "-> /business-production/create-assistant";
const String _routeProductionCreateLog = "-> /business-production/create";
const String _routeProductionPreorderReservationsLog =
    "-> /business-production/preorder-reservations";
const String _routeProductionDetailLog = "-> /business-production/:id";
const String _routeStaffDirectoryLog = "-> /business-staff-directory";
const String _routeStaffDetailLog = "-> /business-staff/:id";
const String _routeChatInboxLog = "-> /chat";
const String _routeChatThreadLog = "-> /chat/:id";

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
      final bool isTenantDashboard = path.startsWith('/tenant-dashboard');
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
          path.startsWith('/business-tenants') ||
          path.startsWith('/business-tenant-payments') ||
          path.startsWith('/tenant-review') ||
          path.startsWith(productionPlansRoute) ||
          path.startsWith(businessStaffDirectoryRoute) ||
          path.startsWith(businessStaffDetailBaseRoute);
      // WHY: Tenant receipts should be guarded the same as tenant dashboards.
      final bool isTenantPayments = path.startsWith('/tenant-payments');

      // WHY: If not logged in, block protected routes.
      if (!isAuthed && !isPublicRoute) {
        AppDebug.log("ROUTER", "redirect -> /login", extra: {"from": path});
        return '/login';
      }

      // WHY: If logged in, keep user out of auth screens.
      if (isAuthed && isAuthRoute) {
        final nextParam = state.uri.queryParameters['next'];
        final tokenParam = state.uri.queryParameters['token'];
        final decodedNext = nextParam == null || nextParam.trim().isEmpty
            ? null
            : Uri.decodeComponent(nextParam.trim());
        String? nextTarget = decodedNext != null && decodedNext.startsWith('/')
            ? decodedNext
            : null;
        // WHY: Recover invite token when next params are not encoded properly.
        if ((nextTarget == null || nextTarget.isEmpty) &&
            tokenParam != null &&
            tokenParam.trim().isNotEmpty) {
          nextTarget = '/business-invite?token=${tokenParam.trim()}';
        } else if (nextTarget == '/business-invite' &&
            tokenParam != null &&
            tokenParam.trim().isNotEmpty) {
          nextTarget = '/business-invite?token=${tokenParam.trim()}';
        }
        // WHY: Use pending invite token if present (synchronous router redirect).
        final pendingInvite = ref.read(pendingInviteTokenProvider);
        final resolvedTarget =
            pendingInvite != null && pendingInvite.trim().isNotEmpty
            ? '/business-invite?token=${pendingInvite.trim()}'
            : nextTarget ?? '/home';
        final safeTarget = resolvedTarget.startsWith('/business-invite')
            ? '/business-invite?token=***'
            : resolvedTarget;

        AppDebug.log(
          "ROUTER",
          "redirect after auth",
          extra: {
            "from": path,
            "to": safeTarget,
            "hasPendingInvite":
                pendingInvite != null && pendingInvite.trim().isNotEmpty,
          },
        );
        return resolvedTarget;
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

      // WHY: Tenant dashboard should be tenant-only (staff/owners use admin panels).
      if (isAuthed && (isTenantDashboard || isTenantPayments)) {
        final role = session.user.role;
        final allowedRoles = ['tenant'];
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
          final nextParam = state.uri.queryParameters['next'];
          final tokenParam = state.uri.queryParameters['token'];
          String? redirectTo = nextParam;
          // WHY: Restore invite flow if token leaked into query params.
          if ((redirectTo == null || redirectTo.trim().isEmpty) &&
              tokenParam != null &&
              tokenParam.trim().isNotEmpty) {
            redirectTo = '/business-invite?token=${tokenParam.trim()}';
          } else if (redirectTo == '/business-invite' &&
              tokenParam != null &&
              tokenParam.trim().isNotEmpty) {
            redirectTo = '/business-invite?token=${tokenParam.trim()}';
          }
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
        path: chatInboxRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeChatInboxLog);
          return const ChatInboxScreen();
        },
      ),
      GoRoute(
        path: "$chatThreadRouteBase/:$chatThreadRouteParam",
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeChatThreadLog);
          final conversationId =
              state.pathParameters[chatThreadRouteParam] ?? "";
          final extra = state.extra;
          final args = extra is ChatThreadArgs
              ? extra
              : extra is ChatConversation
              ? ChatThreadArgs(conversation: extra)
              : null;
          return ChatThreadScreen(conversationId: conversationId, args: args);
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
          return const BusinessThemeWrapper(child: TenantVerificationScreen());
        },
      ),
      GoRoute(
        path: '/tenant-dashboard',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /tenant-dashboard");
          return const BusinessThemeWrapper(child: TenantDashboardScreen());
        },
      ),
      GoRoute(
        path: '/tenant-payments',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /tenant-payments");
          // WHY: Keep tenant receipts aligned with tenant dashboard theming.
          return const BusinessThemeWrapper(
            child: TenantPaymentReceiptsScreen(),
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
          return const BusinessThemeWrapper(child: BusinessDashboardScreen());
        },
      ),
      GoRoute(
        path: '/business-products',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-products");
          return const BusinessThemeWrapper(child: BusinessProductsScreen());
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
          return const BusinessThemeWrapper(child: BusinessOrdersScreen());
        },
      ),
      GoRoute(
        path: '/business-orders/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log("ROUTER", "-> /business-orders/:id", extra: {"id": id});
          final extra = state.extra;
          if (extra is BusinessOrder) {
            return BusinessThemeWrapper(
              child: BusinessOrderDetailScreen(order: extra),
            );
          }
          return const BusinessThemeWrapper(child: BusinessOrdersScreen());
        },
      ),
      GoRoute(
        path: '/business-assets',
        builder: (context, state) {
          AppDebug.log("ROUTER", "-> /business-assets");
          return const BusinessThemeWrapper(child: BusinessAssetsScreen());
        },
      ),
      GoRoute(
        path: '/business-assets/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          AppDebug.log("ROUTER", "-> /business-assets/:id", extra: {"id": id});
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
          return const BusinessThemeWrapper(child: BusinessAssetsScreen());
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
          AppDebug.log("ROUTER", "-> /tenant-review/:id", extra: {"id": id});
          return BusinessThemeWrapper(
            child: BusinessTenantReviewScreen(applicationId: id),
          );
        },
      ),
      GoRoute(
        path: '/business-tenant-payments/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId'] ?? '';
          final extra = state.extra;
          // WHY: Tenant name is optional; fall back to id-only display.
          final tenantName = extra is Map<String, dynamic>
              ? extra[_tenantNameExtraKey] as String?
              : null;
          AppDebug.log(
            "ROUTER",
            "-> /business-tenant-payments/:tenantId",
            extra: {
              "tenantId": tenantId,
              "hasName": tenantName != null && tenantName.isNotEmpty,
            },
          );
          return BusinessThemeWrapper(
            child: BusinessTenantPaymentHistoryScreen(
              tenantId: tenantId,
              tenantName: tenantName,
            ),
          );
        },
      ),
      GoRoute(
        path: businessStaffDirectoryRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeStaffDirectoryLog);
          return const BusinessThemeWrapper(
            child: BusinessStaffDirectoryScreen(),
          );
        },
      ),
      GoRoute(
        path: businessStaffDetailRoute,
        builder: (context, state) {
          final staffProfileId =
              state.pathParameters[_staffProfileIdParam] ?? '';
          AppDebug.log(
            "ROUTER",
            _routeStaffDetailLog,
            extra: {_staffProfileIdParam: staffProfileId},
          );
          return BusinessThemeWrapper(
            child: BusinessStaffDetailScreen(staffProfileId: staffProfileId),
          );
        },
      ),
      GoRoute(
        path: productionPlansRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeProductionListLog);
          return const BusinessThemeWrapper(child: ProductionPlanListScreen());
        },
      ),
      GoRoute(
        path: productionCalendarRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeProductionCalendarLog);
          return const BusinessThemeWrapper(child: ProductionCalendarScreen());
        },
      ),
      GoRoute(
        path: productionPlanAssistantRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeProductionAssistantLog);
          return const BusinessThemeWrapper(
            child: ProductionPlanAssistantScreen(),
          );
        },
      ),
      GoRoute(
        path: productionPlanCreateRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeProductionCreateLog);
          return const BusinessThemeWrapper(
            child: ProductionPlanCreateScreen(),
          );
        },
      ),
      GoRoute(
        path: productionPreorderReservationsRoute,
        builder: (context, state) {
          AppDebug.log("ROUTER", _routeProductionPreorderReservationsLog);
          return const BusinessThemeWrapper(
            child: ProductionPreorderReservationsScreen(),
          );
        },
      ),
      GoRoute(
        path: productionPlanDetailRoute,
        builder: (context, state) {
          final planId = state.pathParameters[_productionPlanIdParam] ?? '';
          AppDebug.log(
            "ROUTER",
            _routeProductionDetailLog,
            extra: {_productionPlanIdParam: planId},
          );
          return BusinessThemeWrapper(
            child: ProductionPlanDetailScreen(planId: planId),
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
          final nextRoute = state.uri.queryParameters['next'] ?? '';
          AppDebug.log(
            "ROUTER",
            "-> /payment-success",
            extra: {
              "hasReference": reference.isNotEmpty,
              "hasNext": nextRoute.trim().isNotEmpty,
            },
          );
          return PaymentSuccessScreen(
            reference: reference,
            nextRoute: nextRoute,
          );
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
