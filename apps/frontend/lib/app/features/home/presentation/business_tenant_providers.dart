/// lib/app/features/home/presentation/business_tenant_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for tenant applications (business).
///
/// WHY:
/// - Keeps API wiring + filters in one place.
/// - Lets tenant list/review screens stay focused on rendering.
///
/// HOW:
/// - businessTenantApiProvider builds BusinessTenantApi from shared Dio.
/// - businessTenantApplicationsProvider fetches list with a query object.
/// - businessTenantByIdProvider fetches a single application.
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// ------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_api.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart';

/// ------------------------------------------------------------
/// QUERY MODEL
/// ------------------------------------------------------------
/// WHY:
/// - Provides a stable key for caching list results per filter.
class BusinessTenantQuery {
  final String? status;
  final String? estateAssetId;
  final int page;
  final int limit;

  const BusinessTenantQuery({
    this.status,
    this.estateAssetId,
    this.page = 1,
    this.limit = 10,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessTenantQuery &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          estateAssetId == other.estateAssetId &&
          page == other.page &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(status, estateAssetId, page, limit);
}

final businessTenantApiProvider = Provider<BusinessTenantApi>((ref) {
  AppDebug.log("PROVIDERS", "businessTenantApiProvider created");
  final dio = ref.read(dioProvider);
  return BusinessTenantApi(dio: dio);
});

final businessTenantApplicationsProvider = FutureProvider.family<
    BusinessTenantApplicationsResult, BusinessTenantQuery>((ref, query) async {
  AppDebug.log(
    "PROVIDERS",
    "businessTenantApplicationsProvider fetch start",
    extra: {
      "status": query.status ?? "all",
      "hasEstate": query.estateAssetId != null && query.estateAssetId!.isNotEmpty,
      "page": query.page,
      "limit": query.limit,
    },
  );

  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "businessTenantApplicationsProvider no session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessTenantApiProvider);
  return api.fetchTenantApplications(
    token: session.token,
    page: query.page,
    limit: query.limit,
    status: query.status,
    estateAssetId: query.estateAssetId,
  );
});

/// Estate analytics (owner/staff) for a specific estate asset.
final estateAnalyticsProvider =
    FutureProvider.family<EstateAnalytics, String>((ref, estateAssetId) async {
  AppDebug.log(
    "PROVIDERS",
    "estateAnalyticsProvider fetch start",
    extra: {"estateAssetId": estateAssetId},
  );

  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "estateAnalyticsProvider no session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessTenantApiProvider);
  return api.fetchEstateAnalytics(
    token: session.token,
    estateAssetId: estateAssetId,
  );
});

final businessTenantByIdProvider =
    FutureProvider.family<BusinessTenantApplication, String>((ref, id) async {
  AppDebug.log(
    "PROVIDERS",
    "businessTenantByIdProvider fetch start",
    extra: {"id": id},
  );

  final session = ref.watch(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "businessTenantByIdProvider no session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessTenantApiProvider);
  return api.fetchTenantApplicationDetail(
    token: session.token,
    applicationId: id,
  );
});
