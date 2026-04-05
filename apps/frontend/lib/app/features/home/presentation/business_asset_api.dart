/// lib/app/features/home/presentation/business_asset_api.dart
/// ---------------------------------------------------------
/// WHAT:
/// - BusinessAssetApi for /business/assets CRUD endpoints.
///
/// WHY:
/// - Keeps asset networking out of UI widgets.
/// - Centralizes auth headers + parsing so UI stays simple.
///
/// HOW:
/// - GET /business/assets (list + filters)
/// - POST /business/assets (create)
/// - PATCH /business/assets/:id (update)
/// - DELETE /business/assets/:id (soft delete)
///
/// DEBUGGING:
/// - Logs request start/end (safe fields only).
/// ---------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'business_asset_model.dart';

class BusinessAssetsResult {
  final List<BusinessAsset> assets;
  final int total;
  final int page;
  final int limit;

  const BusinessAssetsResult({
    required this.assets,
    required this.total,
    required this.page,
    required this.limit,
  });
}

class FarmAssetAuditSummary {
  final int totalAssets;
  final int totalQuantity;
  final double totalEstimatedValue;
  final int dueThisQuarter;
  final int dueThisYear;
  final int overdueCount;

  const FarmAssetAuditSummary({
    required this.totalAssets,
    required this.totalQuantity,
    required this.totalEstimatedValue,
    required this.dueThisQuarter,
    required this.dueThisYear,
    required this.overdueCount,
  });

  factory FarmAssetAuditSummary.fromJson(Map<String, dynamic>? json) {
    final safe = json ?? const <String, dynamic>{};
    return FarmAssetAuditSummary(
      totalAssets: _asInt(safe["totalAssets"]),
      totalQuantity: _asInt(safe["totalQuantity"]),
      totalEstimatedValue: _asDouble(safe["totalEstimatedValue"]),
      dueThisQuarter: _asInt(safe["dueThisQuarter"]),
      dueThisYear: _asInt(safe["dueThisYear"]),
      overdueCount: _asInt(safe["overdueCount"]),
    );
  }
}

class FarmAssetAuditCategoryBreakdown {
  final String label;
  final int assetCount;
  final int quantity;
  final double estimatedValue;

  const FarmAssetAuditCategoryBreakdown({
    required this.label,
    required this.assetCount,
    required this.quantity,
    required this.estimatedValue,
  });

  factory FarmAssetAuditCategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return FarmAssetAuditCategoryBreakdown(
      label: json["label"]?.toString() ?? "uncategorized",
      assetCount: _asInt(json["assetCount"]),
      quantity: _asInt(json["quantity"]),
      estimatedValue: _asDouble(json["estimatedValue"]),
    );
  }
}

class FarmAssetAuditCountBucket {
  final String label;
  final int count;

  const FarmAssetAuditCountBucket({required this.label, required this.count});

  factory FarmAssetAuditCountBucket.fromJson(Map<String, dynamic> json) {
    return FarmAssetAuditCountBucket(
      label: json["label"]?.toString() ?? "",
      count: _asInt(json["count"]),
    );
  }
}

class FarmAssetAuditQuarterBucket {
  final String label;
  final int dueCount;

  const FarmAssetAuditQuarterBucket({
    required this.label,
    required this.dueCount,
  });

  factory FarmAssetAuditQuarterBucket.fromJson(Map<String, dynamic> json) {
    return FarmAssetAuditQuarterBucket(
      label: json["label"]?.toString() ?? "",
      dueCount: _asInt(json["dueCount"]),
    );
  }
}

class FarmAssetAuditAttentionAsset {
  final String id;
  final String name;
  final String category;
  final String status;
  final int quantity;
  final DateTime? nextAuditDate;
  final double estimatedCurrentValue;

  const FarmAssetAuditAttentionAsset({
    required this.id,
    required this.name,
    required this.category,
    required this.status,
    required this.quantity,
    required this.nextAuditDate,
    required this.estimatedCurrentValue,
  });

  factory FarmAssetAuditAttentionAsset.fromJson(Map<String, dynamic> json) {
    return FarmAssetAuditAttentionAsset(
      id: json["id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      category: json["category"]?.toString() ?? "uncategorized",
      status: json["status"]?.toString() ?? "inactive",
      quantity: _asInt(json["quantity"]),
      nextAuditDate: _asDateTime(json["nextAuditDate"]),
      estimatedCurrentValue: _asDouble(json["estimatedCurrentValue"]),
    );
  }
}

class FarmAssetAuditAnalytics {
  final int selectedYear;
  final FarmAssetAuditSummary summary;
  final List<FarmAssetAuditCategoryBreakdown> categoryBreakdown;
  final List<FarmAssetAuditCountBucket> statusBreakdown;
  final List<FarmAssetAuditCountBucket> cadenceBreakdown;
  final List<FarmAssetAuditQuarterBucket> quarterBreakdown;
  final List<FarmAssetAuditAttentionAsset> attentionAssets;

  const FarmAssetAuditAnalytics({
    required this.selectedYear,
    required this.summary,
    required this.categoryBreakdown,
    required this.statusBreakdown,
    required this.cadenceBreakdown,
    required this.quarterBreakdown,
    required this.attentionAssets,
  });

  factory FarmAssetAuditAnalytics.fromJson(Map<String, dynamic> json) {
    return FarmAssetAuditAnalytics(
      selectedYear: _asInt(json["selectedYear"]),
      summary: FarmAssetAuditSummary.fromJson(
        json["summary"] as Map<String, dynamic>?,
      ),
      categoryBreakdown: _asList(
        json["categoryBreakdown"],
      ).map((item) => FarmAssetAuditCategoryBreakdown.fromJson(item)).toList(),
      statusBreakdown: _asList(
        json["statusBreakdown"],
      ).map((item) => FarmAssetAuditCountBucket.fromJson(item)).toList(),
      cadenceBreakdown: _asList(
        json["cadenceBreakdown"],
      ).map((item) => FarmAssetAuditCountBucket.fromJson(item)).toList(),
      quarterBreakdown: _asList(
        json["quarterBreakdown"],
      ).map((item) => FarmAssetAuditQuarterBucket.fromJson(item)).toList(),
      attentionAssets: _asList(
        json["attentionAssets"],
      ).map((item) => FarmAssetAuditAttentionAsset.fromJson(item)).toList(),
    );
  }
}

class BusinessAssetApi {
  final Dio _dio;

  BusinessAssetApi({required Dio dio}) : _dio = dio;

  /// WHY: All business asset endpoints require auth.
  Options _authOptions(String? token) {
    if (token == null || token.trim().isEmpty) {
      AppDebug.log("BUSINESS_ASSET_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(headers: {"Authorization": "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// LIST ASSETS
  /// ------------------------------------------------------
  Future<BusinessAssetsResult> fetchAssets({
    required String? token,
    int page = 1,
    int limit = 10,
    String? status,
    String? assetType,
    String? domainContext,
    String? farmCategory,
    String? auditFrequency,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "fetchAssets() start",
      extra: {
        "page": page,
        "limit": limit,
        "status": status ?? "all",
        "assetType": assetType ?? "all",
        "domainContext": domainContext ?? "all",
        "farmCategory": farmCategory ?? "all",
        "auditFrequency": auditFrequency ?? "all",
      },
    );

    final resp = await _dio.get(
      "/business/assets",
      queryParameters: {
        "page": page,
        "limit": limit,
        if (status != null && status.isNotEmpty) "status": status,
        if (assetType != null && assetType.isNotEmpty) "assetType": assetType,
        if (domainContext != null && domainContext.isNotEmpty)
          "domainContext": domainContext,
        if (farmCategory != null && farmCategory.isNotEmpty)
          "farmCategory": farmCategory,
        if (auditFrequency != null && auditFrequency.isNotEmpty)
          "auditFrequency": auditFrequency,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final rawAssets = (data["assets"] ?? []) as List<dynamic>;
    final assets = rawAssets
        .map((item) => BusinessAsset.fromJson(item as Map<String, dynamic>))
        .toList();

    final result = BusinessAssetsResult(
      assets: assets,
      total: (data["total"] ?? 0) is int
          ? (data["total"] ?? 0) as int
          : int.tryParse((data["total"] ?? 0).toString()) ?? 0,
      page: (data["page"] ?? page) is int
          ? (data["page"] ?? page) as int
          : int.tryParse((data["page"] ?? page).toString()) ?? page,
      limit: (data["limit"] ?? limit) is int
          ? (data["limit"] ?? limit) as int
          : int.tryParse((data["limit"] ?? limit).toString()) ?? limit,
    );

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "fetchAssets() success",
      extra: {"count": assets.length, "total": result.total},
    );

    return result;
  }

  Future<FarmAssetAuditAnalytics> fetchFarmAssetAuditAnalytics({
    required String? token,
    String? farmCategory,
    String? auditFrequency,
    int? year,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "fetchFarmAssetAuditAnalytics() start",
      extra: {
        "farmCategory": farmCategory ?? "all",
        "auditFrequency": auditFrequency ?? "all",
        "year": year,
      },
    );

    final resp = await _dio.get(
      "/business/assets/farm-audit",
      queryParameters: {
        if (farmCategory != null && farmCategory.isNotEmpty)
          "farmCategory": farmCategory,
        if (auditFrequency != null && auditFrequency.isNotEmpty)
          "auditFrequency": auditFrequency,
        if (year != null) "year": year,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final analytics = FarmAssetAuditAnalytics.fromJson(data);

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "fetchFarmAssetAuditAnalytics() success",
      extra: {"totalAssets": analytics.summary.totalAssets},
    );

    return analytics;
  }

  /// ------------------------------------------------------
  /// CREATE ASSET
  /// ------------------------------------------------------
  Future<BusinessAsset> createAsset({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "createAsset() start",
      extra: {"assetType": payload["assetType"], "status": payload["status"]},
    );

    final resp = await _dio.post(
      "/business/assets",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final assetMap = (data["asset"] ?? {}) as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(assetMap);

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "createAsset() success",
      extra: {"assetId": asset.id},
    );

    return asset;
  }

  Future<BusinessAsset> submitFarmAsset({
    required String? token,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "submitFarmAsset() start",
      extra: {
        "assetType": payload["assetType"],
        "farmCategory":
            (payload["farmProfile"] as Map<String, dynamic>?)?["farmCategory"],
      },
    );

    final resp = await _dio.post(
      "/business/assets/farm-audit/submissions",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(
      (data["asset"] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    );

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "submitFarmAsset() success",
      extra: {
        "assetId": asset.id,
        "approvalStatus": asset.approvalStatus,
      },
    );

    return asset;
  }

  /// ------------------------------------------------------
  /// UPDATE ASSET
  /// ------------------------------------------------------
  Future<BusinessAsset> updateAsset({
    required String? token,
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "updateAsset() start",
      extra: {"assetId": id, "status": payload["status"]},
    );

    final resp = await _dio.patch(
      "/business/assets/$id",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final assetMap = (data["asset"] ?? {}) as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(assetMap);

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "updateAsset() success",
      extra: {"assetId": asset.id},
    );

    return asset;
  }

  Future<BusinessAsset> submitFarmAssetAudit({
    required String? token,
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "submitFarmAssetAudit() start",
      extra: {"assetId": id, "status": payload["status"]},
    );

    final resp = await _dio.post(
      "/business/assets/$id/farm-audit-requests",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(
      (data["asset"] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    );

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "submitFarmAssetAudit() success",
      extra: {
        "assetId": asset.id,
        "hasPendingAudit":
            asset.farmProfile?.pendingAuditRequest?.status == 'pending_approval',
      },
    );

    return asset;
  }

  Future<BusinessAsset> submitFarmToolUsageRequest({
    required String? token,
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "submitFarmToolUsageRequest() start",
      extra: {
        "assetId": id,
        "productionDate": payload["productionDate"],
        "quantityRequested": payload["quantityRequested"],
      },
    );

    final resp = await _dio.post(
      "/business/assets/$id/farm-usage-requests",
      data: payload,
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(
      (data["asset"] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    );

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "submitFarmToolUsageRequest() success",
      extra: {"assetId": asset.id},
    );

    return asset;
  }

  Future<BusinessAsset> approveFarmAssetRequest({
    required String? token,
    required String id,
    required String requestType,
    String? requestId,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "approveFarmAssetRequest() start",
      extra: {
        "assetId": id,
        "requestType": requestType,
        "requestId": requestId ?? '',
      },
    );

    final resp = await _dio.post(
      "/business/assets/$id/farm-approval",
      data: {
        "requestType": requestType,
        if (requestId != null && requestId.trim().isNotEmpty)
          "requestId": requestId.trim(),
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(
      (data["asset"] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    );

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "approveFarmAssetRequest() success",
      extra: {"assetId": asset.id, "requestType": requestType},
    );

    return asset;
  }

  /// ------------------------------------------------------
  /// SOFT DELETE ASSET
  /// ------------------------------------------------------
  Future<BusinessAsset> deleteAsset({
    required String? token,
    required String id,
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "deleteAsset() start",
      extra: {"assetId": id},
    );

    final resp = await _dio.delete(
      "/business/assets/$id",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final assetMap = (data["asset"] ?? {}) as Map<String, dynamic>;
    final asset = BusinessAsset.fromJson(assetMap);

    AppDebug.log(
      "BUSINESS_ASSET_API",
      "deleteAsset() success",
      extra: {"assetId": asset.id},
    );

    return asset;
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse((value ?? 0).toString()) ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse((value ?? 0).toString()) ?? 0;
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

List<Map<String, dynamic>> _asList(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
