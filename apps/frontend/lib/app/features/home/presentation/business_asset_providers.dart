/// lib/app/features/home/presentation/business_asset_providers.dart
/// --------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for business asset management.
///
/// WHY:
/// - Keeps business asset fetching + caching out of widgets.
/// - Allows status filters and analytics summaries to share data.
///
/// HOW:
/// - businessAssetApiProvider builds the API from shared Dio.
/// - businessAssetsProvider fetches assets by query.
/// - businessAssetSummaryProvider returns counts per status.
///
/// DEBUGGING:
/// - Logs provider creation and fetch lifecycle events.
/// --------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'business_asset_api.dart';

/// WHY: Stable query object keeps provider cache predictable.
class BusinessAssetsQuery {
  final String? status;
  final String? assetType;
  final String? domainContext;
  final String? farmCategory;
  final String? auditFrequency;
  final int page;
  final int limit;

  const BusinessAssetsQuery({
    this.status,
    this.assetType,
    this.domainContext,
    this.farmCategory,
    this.auditFrequency,
    this.page = 1,
    this.limit = 10,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessAssetsQuery &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          assetType == other.assetType &&
          domainContext == other.domainContext &&
          farmCategory == other.farmCategory &&
          auditFrequency == other.auditFrequency &&
          page == other.page &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(
    status,
    assetType,
    domainContext,
    farmCategory,
    auditFrequency,
    page,
    limit,
  );
}

class BusinessAssetSummary {
  final int total;
  final int active;
  final int maintenance;
  final int inactive;

  const BusinessAssetSummary({
    required this.total,
    required this.active,
    required this.maintenance,
    required this.inactive,
  });
}

class FarmAssetAuditQuery {
  final String? farmCategory;
  final String? auditFrequency;
  final int year;

  const FarmAssetAuditQuery({
    this.farmCategory,
    this.auditFrequency,
    required this.year,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FarmAssetAuditQuery &&
          runtimeType == other.runtimeType &&
          farmCategory == other.farmCategory &&
          auditFrequency == other.auditFrequency &&
          year == other.year;

  @override
  int get hashCode => Object.hash(farmCategory, auditFrequency, year);
}

final businessAssetStatusFilterProvider = StateProvider<String?>((ref) => null);

final businessAssetApiProvider = Provider<BusinessAssetApi>((ref) {
  AppDebug.log("PROVIDERS", "businessAssetApiProvider created");
  final dio = ref.read(dioProvider);
  return BusinessAssetApi(dio: dio);
});

final businessAssetsProvider =
    FutureProvider.family<BusinessAssetsResult, BusinessAssetsQuery>((
      ref,
      query,
    ) async {
      AppDebug.log(
        "PROVIDERS",
        "businessAssetsProvider fetch start",
        extra: {
          "status": query.status ?? "all",
          "assetType": query.assetType ?? "all",
          "domainContext": query.domainContext ?? "all",
          "farmCategory": query.farmCategory ?? "all",
          "auditFrequency": query.auditFrequency ?? "all",
          "page": query.page,
          "limit": query.limit,
        },
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log("PROVIDERS", "businessAssetsProvider missing session");
        throw Exception("Session expired. Please sign in again.");
      }

      final api = ref.read(businessAssetApiProvider);
      return api.fetchAssets(
        token: session.token,
        page: query.page,
        limit: query.limit,
        status: query.status,
        assetType: query.assetType,
        domainContext: query.domainContext,
        farmCategory: query.farmCategory,
        auditFrequency: query.auditFrequency,
      );
    });

final businessFarmAssetAuditProvider =
    FutureProvider.family<FarmAssetAuditAnalytics, FarmAssetAuditQuery>((
      ref,
      query,
    ) async {
      AppDebug.log(
        "PROVIDERS",
        "businessFarmAssetAuditProvider fetch start",
        extra: {
          "farmCategory": query.farmCategory ?? "all",
          "auditFrequency": query.auditFrequency ?? "all",
          "year": query.year,
        },
      );

      final session = ref.read(authSessionProvider);
      if (session == null || !session.isTokenValid) {
        AppDebug.log(
          "PROVIDERS",
          "businessFarmAssetAuditProvider missing session",
        );
        throw Exception("Session expired. Please sign in again.");
      }

      final api = ref.read(businessAssetApiProvider);
      return api.fetchFarmAssetAuditAnalytics(
        token: session.token,
        farmCategory: query.farmCategory,
        auditFrequency: query.auditFrequency,
        year: query.year,
      );
    });

final businessAssetSummaryProvider = FutureProvider<BusinessAssetSummary>((
  ref,
) async {
  AppDebug.log("PROVIDERS", "businessAssetSummaryProvider fetch start");

  final session = ref.read(authSessionProvider);
  if (session == null || !session.isTokenValid) {
    AppDebug.log("PROVIDERS", "businessAssetSummaryProvider missing session");
    throw Exception("Session expired. Please sign in again.");
  }

  final api = ref.read(businessAssetApiProvider);

  // WHY: Fetch totals per status with light payloads for analytics cards.
  final results = await Future.wait([
    api.fetchAssets(token: session.token, page: 1, limit: 1),
    api.fetchAssets(token: session.token, page: 1, limit: 1, status: "active"),
    api.fetchAssets(
      token: session.token,
      page: 1,
      limit: 1,
      status: "maintenance",
    ),
    api.fetchAssets(
      token: session.token,
      page: 1,
      limit: 1,
      status: "inactive",
    ),
  ]);

  final summary = BusinessAssetSummary(
    total: results[0].total,
    active: results[1].total,
    maintenance: results[2].total,
    inactive: results[3].total,
  );

  AppDebug.log(
    "PROVIDERS",
    "businessAssetSummaryProvider fetch success",
    extra: {
      "total": summary.total,
      "active": summary.active,
      "maintenance": summary.maintenance,
      "inactive": summary.inactive,
    },
  );

  return summary;
});
