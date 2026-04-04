/// lib/app/features/home/presentation/tenant_verification_providers.dart
/// --------------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for tenant verification flows.
///
/// WHY:
/// - Keeps API wiring and tenant estate fetching centralized.
/// - Allows UI widgets to stay focused on rendering.
///
/// HOW:
/// - tenantVerificationApiProvider builds the API client with Dio.
/// - tenantEstateProvider loads the tenant's assigned estate asset.
/// - tenantApplicationProvider loads the tenant's latest application (if any).
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// --------------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart'
    as business_tenant;
import 'package:frontend/app/features/home/presentation/tenant_verification_api.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_model.dart';

/// =========================
/// RENT PERIOD DEFAULTS
/// =========================
/// WHY:
/// - Ensures safe default coverage per rent period.
/// - Prevents tenants accidentally paying for too little rent coverage
///   (e.g. 1 month × 3 payments).
/// - Works with backend rule: max 3 payments per calendar year.
///
/// NOTE:
/// - These are UI defaults only.
/// - Backend still enforces all limits and validations.
const Map<String, int> defaultPeriodCountByRentPeriod = {
  'monthly': 12, // 12 months = 1 year
  'quarterly': 4, // 4 quarters = 1 year
  'yearly': 1, // 1 year
};

final tenantVerificationApiProvider = Provider<TenantVerificationApi>((ref) {
  AppDebug.log("PROVIDERS", "tenantVerificationApiProvider created");
  final dio = ref.read(dioProvider);
  return TenantVerificationApi(dio: dio);
});

final tenantEstateProvider = FutureProvider<TenantEstate>((ref) async {
  AppDebug.log("PROVIDERS", "tenantEstateProvider fetch start");

  final session = ref.watch(authSessionProvider);
  if (session == null) {
    AppDebug.log("PROVIDERS", "tenantEstateProvider missing session");
    throw Exception("Not logged in");
  }

  final api = ref.read(tenantVerificationApiProvider);
  return api.fetchTenantEstate(token: session.token);
});

final tenantApplicationProvider =
    FutureProvider<business_tenant.BusinessTenantApplication?>((ref) async {
      AppDebug.log("PROVIDERS", "tenantApplicationProvider fetch start");

      final session = ref.watch(authSessionProvider);
      if (session == null) {
        AppDebug.log("PROVIDERS", "tenantApplicationProvider missing session");
        throw Exception("Not logged in");
      }

      final api = ref.read(tenantVerificationApiProvider);
      return api.fetchTenantApplication(token: session.token);
    });

final tenantSummaryProvider = FutureProvider<business_tenant.TenantSummary>((
  ref,
) async {
  AppDebug.log("PROVIDERS", "tenantSummaryProvider fetch start");

  final session = ref.watch(authSessionProvider);
  if (session == null) {
    AppDebug.log("PROVIDERS", "tenantSummaryProvider missing session");
    throw Exception("Not logged in");
  }

  final api = ref.read(tenantVerificationApiProvider);
  return api.fetchTenantSummary(token: session.token);
});

/// =========================
/// TENANT VERIFICATION NOTIFIER
/// =========================
/// WHY:
/// - Central brain for rent period + payment span.
/// - Applies safe defaults (1 year coverage).
/// - Respects user choice once they manually edit period count.
class TenantVerificationNotifier
    extends StateNotifier<TenantVerificationState> {
  TenantVerificationNotifier()
    : super(
        const TenantVerificationState(
          rentPeriod: 'monthly',
          periodCount: 12, // SAFE DEFAULT = 1 year
          hasUserManuallyChangedPeriodCount: false,
        ),
      );

  /// WHY:
  /// - When rent period changes, auto-set a safe default
  ///   UNLESS the user already changed it manually.
  void setRentPeriod(String rentPeriod) {
    AppDebug.log(
      "TENANT_VERIFY",
      "set_rent_period",
      extra: {"rentPeriod": rentPeriod},
    );

    state = state.copyWith(
      rentPeriod: rentPeriod,
      periodCount: state.hasUserManuallyChangedPeriodCount
          ? state.periodCount
          : defaultPeriodCountByRentPeriod[rentPeriod] ?? 1,
    );
  }

  /// WHY:
  /// - Explicit user action must override defaults.
  void setPeriodCount(int count) {
    AppDebug.log(
      "TENANT_VERIFY",
      "set_period_count",
      extra: {"periodCount": count},
    );

    state = state.copyWith(
      periodCount: count,
      hasUserManuallyChangedPeriodCount: true,
    );
  }
}

/// WHY:
/// - Exposes verification rent state to UI.
/// - Prevents widgets from owning payment logic.
final tenantVerificationProvider =
    StateNotifierProvider<TenantVerificationNotifier, TenantVerificationState>(
      (ref) => TenantVerificationNotifier(),
    );
