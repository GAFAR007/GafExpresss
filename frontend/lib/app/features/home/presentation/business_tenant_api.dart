/// lib/app/features/home/presentation/business_tenant_api.dart
/// ------------------------------------------------------------
/// WHAT:
/// - BusinessTenantApi for /business/tenant/applications endpoints.
///
/// WHY:
/// - Keeps tenant application fetching isolated from UI widgets.
/// - Centralizes auth handling + JSON parsing for list/detail flows.
///
/// HOW:
/// - Uses Dio with Authorization header.
/// - Parses responses into BusinessTenantApplication models.
///
/// DEBUGGING:
/// - Logs request start/end (safe only).
/// - Never logs tokens or sensitive user data.
/// ------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart';

class BusinessTenantApplicationsResult {
  final List<BusinessTenantApplication> applications;
  final int total;
  final int page;
  final int limit;

  const BusinessTenantApplicationsResult({
    required this.applications,
    required this.total,
    required this.page,
    required this.limit,
  });
}

class BusinessTenantApi {
  final Dio _dio;

  BusinessTenantApi({required Dio dio}) : _dio = dio;

  /// WHY: All /business/tenant routes require auth.
  Options _authOptions(String? token) {
    if (token == null || token.isEmpty) {
      AppDebug.log("BUSINESS_TENANT_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(
      headers: {
        "Authorization": "Bearer $token",
      },
    );
  }

  /// ------------------------------------------------------
  /// LIST TENANT APPLICATIONS
  /// ------------------------------------------------------
  Future<BusinessTenantApplicationsResult> fetchTenantApplications({
    required String? token,
    int page = 1,
    int limit = 10,
    String? status,
    String? estateAssetId,
  }) async {
    AppDebug.log(
      "BUSINESS_TENANT_API",
      "fetchTenantApplications() start",
      extra: {
        "page": page,
        "limit": limit,
        "status": status ?? "all",
        "hasEstate": estateAssetId != null && estateAssetId.isNotEmpty,
      },
    );

    final resp = await _dio.get(
      "/business/tenant/applications",
      queryParameters: {
        "page": page,
        "limit": limit,
        if (status != null && status.isNotEmpty) "status": status,
        if (estateAssetId != null && estateAssetId.isNotEmpty)
          "estateAssetId": estateAssetId,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final rawApps = (data["applications"] ?? []) as List<dynamic>;
    final applications = rawApps
        .map((item) => BusinessTenantApplication.fromJson(
              item as Map<String, dynamic>,
            ))
        .toList();

    final result = BusinessTenantApplicationsResult(
      applications: applications,
      total: _parseInt(data["total"], fallback: 0),
      page: _parseInt(data["page"], fallback: page),
      limit: _parseInt(data["limit"], fallback: limit),
    );

    AppDebug.log(
      "BUSINESS_TENANT_API",
      "fetchTenantApplications() success",
      extra: {"count": applications.length, "total": result.total},
    );

    return result;
  }

  /// ------------------------------------------------------
  /// FETCH TENANT APPLICATION DETAIL
  /// ------------------------------------------------------
  Future<BusinessTenantApplication> fetchTenantApplicationDetail({
    required String? token,
    required String applicationId,
  }) async {
    AppDebug.log(
      "BUSINESS_TENANT_API",
      "fetchTenantApplicationDetail() start",
      extra: {"applicationId": applicationId},
    );

    final resp = await _dio.get(
      "/business/tenant/applications/$applicationId",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final appMap = (data["application"] ?? {}) as Map<String, dynamic>;
    final application = BusinessTenantApplication.fromJson(appMap);

    AppDebug.log(
      "BUSINESS_TENANT_API",
      "fetchTenantApplicationDetail() success",
      extra: {"applicationId": application.id},
    );

    return application;
  }

  /// ------------------------------------------------------
  /// VERIFY CONTACT (REFERENCE/GUARANTOR)
  /// ------------------------------------------------------
  Future<BusinessTenantApplication> verifyTenantContact({
    required String? token,
    required String applicationId,
    required String type,
    required int index,
    required String status,
    String? note,
  }) async {
    AppDebug.log(
      "BUSINESS_TENANT_API",
      "verifyTenantContact() start",
      extra: {
        "applicationId": applicationId,
        "type": type,
        "index": index,
        "status": status,
        "hasNote": note != null && note.trim().isNotEmpty,
      },
    );

    final resp = await _dio.post(
      "/business/tenant/applications/$applicationId/verify-contact",
      data: {
        "type": type,
        "index": index,
        "status": status,
        if (note != null && note.trim().isNotEmpty) "note": note.trim(),
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final appMap = (data["application"] ?? {}) as Map<String, dynamic>;
    final application = BusinessTenantApplication.fromJson(appMap);

    AppDebug.log(
      "BUSINESS_TENANT_API",
      "verifyTenantContact() success",
      extra: {"applicationId": application.id},
    );

    return application;
  }

  /// ------------------------------------------------------
  /// APPROVE TENANT APPLICATION
  /// ------------------------------------------------------
  Future<BusinessTenantApplication> approveTenantApplication({
    required String? token,
    required String applicationId,
  }) async {
    AppDebug.log(
      "BUSINESS_TENANT_API",
      "approveTenantApplication() start",
      extra: {"applicationId": applicationId},
    );

    final resp = await _dio.post(
      "/business/tenant/applications/$applicationId/approve",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final appMap = (data["application"] ?? {}) as Map<String, dynamic>;
    final application = BusinessTenantApplication.fromJson(appMap);

    AppDebug.log(
      "BUSINESS_TENANT_API",
      "approveTenantApplication() success",
      extra: {"applicationId": application.id},
    );

    return application;
  }

  int _parseInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }
}
