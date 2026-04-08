/// lib/app/features/home/presentation/app_refresh.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Central refresh helper for consumer + tenant + business data.
///
/// WHY:
/// - Keeps refresh behavior consistent across screens.
/// - Avoids duplicate refresh logic and missed providers.
///
/// HOW:
/// - Invalidates all fetch providers so active screens refetch.
/// - Leaves filter/state providers untouched.
///
/// DEBUGGING:
/// - Logs refresh start/end with source for traceability.
/// ------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_order_providers.dart';
import 'package:frontend/app/features/home/presentation/business_product_providers.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_providers.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/product_providers.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_providers.dart';

class AppRefresh {
  static const String _logTag = "APP_REFRESH";
  static const String _logStart = "refresh_start";
  static const String _logEnd = "refresh_end";

  static Future<void> refreshApp({
    required WidgetRef ref,
    required String source,
  }) async {
    // WHY: Log entry so we can trace refresh flows across screens.
    AppDebug.log(_logTag, _logStart, extra: {"source": source});

    // WHY: Consumer data should stay fresh across Home, Cart, Orders, Settings.
    ref.invalidate(productsProvider);
    ref.invalidate(productsSearchProvider);
    ref.invalidate(productsQueryProvider);
    ref.invalidate(productByIdProvider);
    ref.invalidate(productRepositoryProvider);
    ref.invalidate(myOrdersProvider);
    ref.invalidate(userProfileProvider);
    ref.invalidate(isAdminProvider);

    // WHY: Tenant views depend on these APIs (verification + dashboard).
    ref.invalidate(tenantEstateProvider);
    ref.invalidate(tenantApplicationProvider);
    ref.invalidate(tenantSummaryProvider);

    // WHY: Business dashboards and analytics need up-to-date fetches.
    ref.invalidate(businessAssetsProvider);
    ref.invalidate(businessAssetSummaryProvider);
    ref.invalidate(businessProductsProvider);
    ref.invalidate(businessAnalyticsSummaryProvider);
    ref.invalidate(businessProductByIdProvider);
    ref.invalidate(businessOrdersProvider);
    ref.invalidate(businessTenantApplicationsProvider);
    ref.invalidate(businessTenantByIdProvider);
    ref.invalidate(estateAnalyticsProvider);

    // WHY: Role can change after invite acceptance; sync session from profile.
    final session = ref.read(authSessionProvider);
    if (session != null) {
      try {
        // WHY: Fetch the latest profile to compare role with session role.
        final profile = await ref.refresh(userProfileProvider.future);
        final profileRole = profile?.role.trim() ?? "";
        final profileStaffRole = profile?.staffRole?.trim() ?? "";
        final shouldSyncRole =
            profileRole.isNotEmpty && profileRole != session.user.role;
        final shouldSyncStaffRole =
            profileStaffRole.isNotEmpty &&
            profileStaffRole != session.user.staffRole;
        if (shouldSyncRole || shouldSyncStaffRole) {
          // WHY: Update session role so UI (tenant tab) reflects changes.
          await ref
              .read(authSessionProvider.notifier)
              .updateUserRole(
                role: profileRole.isNotEmpty ? profileRole : session.user.role,
                staffRole: profileStaffRole.isNotEmpty
                    ? profileStaffRole
                    : null,
                source: "app_refresh_profile_sync",
              );
        }
      } catch (e) {
        // WHY: Refresh should not crash if profile sync fails.
        AppDebug.log(
          _logTag,
          "profile_role_sync_failed",
          extra: {"source": source, "error": e.toString()},
        );
      }
    }

    // WHY: Log exit so we can confirm completion per refresh source.
    AppDebug.log(_logTag, _logEnd, extra: {"source": source});
  }
}
