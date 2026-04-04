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
  }) async {
    AppDebug.log(
      "BUSINESS_ASSET_API",
      "fetchAssets() start",
      extra: {
        "page": page,
        "limit": limit,
        "status": status ?? "all",
      },
    );

    final resp = await _dio.get(
      "/business/assets",
      queryParameters: {
        "page": page,
        "limit": limit,
        if (status != null && status.isNotEmpty) "status": status,
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
      extra: {
        "assetType": payload["assetType"],
        "status": payload["status"],
      },
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
