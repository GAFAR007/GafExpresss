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
import 'package:frontend/app/features/home/presentation/tenant_rent_constants.dart';
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

/// ==============================
/// TENANT VERIFICATION CONTROLLER
/// ==============================
/// WHAT:
/// - Tracks transient UI intent for rent period + coverage selection.
/// WHY:
/// - Prevents rentPeriod from jumping when backend data arrives.
/// - Lets the selector keep defaults while still honoring manual tweaks.
/// HOW:
/// - Exposes a StateNotifierProvider that updates rentPeriod + periodCount.
final tenantVerificationProvider =
    StateNotifierProvider<TenantVerificationNotifier, TenantVerificationState>(
  (ref) => TenantVerificationNotifier(),
);

class TenantVerificationNotifier
    extends StateNotifier<TenantVerificationState> {
  TenantVerificationNotifier() : super(_initialState()) {
    AppDebug.log(
      "PROVIDERS",
      "tenantVerificationProvider initialized",
      extra: {
        "rentPeriod": state.rentPeriod,
        "periodCount": state.periodCount,
      },
    );
  }

  static const String _fallbackRentPeriod = "monthly";

  /// WHY: Provide a default rent period that always exists.
  static String get _defaultRentPeriod {
    final keys = defaultPeriodCountByRentPeriod.keys;
    if (keys.isNotEmpty && keys.first.isNotEmpty) {
      return keys.first;
    }
    return _fallbackRentPeriod;
  }

  /// WHY: Keep the UI initialized to a safe period count before data arrives.
  static int get _defaultPeriodCount =>
      defaultPeriodCountByRentPeriod[_defaultRentPeriod] ?? 1;

  static TenantVerificationState _initialState() {
    return TenantVerificationState(
      rentPeriod: _defaultRentPeriod,
      periodCount: _defaultPeriodCount,
      hasUserManuallyChangedPeriodCount: false,
    );
  }

  /// WHY: Resume backend intent without clobbering a user-selected period count.
  void setRentPeriod(String rentPeriod) {
    final normalized = rentPeriod.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final defaultCount =
        defaultPeriodCountByRentPeriod[normalized] ?? _defaultPeriodCount;
    final periodCount = state.hasUserManuallyChangedPeriodCount
        ? state.periodCount
        : defaultCount;

    state = state.copyWith(
      rentPeriod: normalized,
      periodCount: periodCount,
    );

    AppDebug.log(
      "PROVIDERS",
      "tenantVerificationProvider rentPeriodUpdated",
      extra: {
        "rentPeriod": normalized,
        "periodCount": periodCount,
        "manualOverride": state.hasUserManuallyChangedPeriodCount,
      },
    );
  }

  /// WHY: Record the tenant's manual period selection to avoid resets.
  void setPeriodCount(int periodCount) {
    final limit = getRentPeriodLimit(state.rentPeriod);
    final safeCount = limit == null
        ? periodCount
        : periodCount.clamp(1, limit.maxPeriods);

    state = state.copyWith(
      periodCount: safeCount,
      hasUserManuallyChangedPeriodCount: true,
    );

    AppDebug.log(
      "PROVIDERS",
      "tenantVerificationProvider periodCountUpdated",
      extra: {
        "rentPeriod": state.rentPeriod,
        "periodCount": safeCount,
      },
    );
  }
}
