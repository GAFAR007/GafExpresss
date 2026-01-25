/// lib/app/features/home/presentation/tenant_verification_api.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - API client for tenant verification endpoints.
///
/// WHY:
/// - Tenant verification requires authenticated business tenant calls.
/// - Keeps tenant-specific requests out of the UI layer.
///
/// HOW:
/// - GET /business/tenant/estate to load assigned estate data.
/// - GET /business/tenant/application to load the latest tenant application.
/// - PATCH /business/tenant/application to update a pending application.
/// - POST /business/tenant/verify to submit tenant application.
///
/// DEBUGGING:
/// - Logs request start/end without leaking secrets.
/// ----------------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/tenant_verification_model.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart'
    as business_tenant;

class TenantVerificationApi {
  final Dio _dio;

  TenantVerificationApi({required Dio dio}) : _dio = dio;

  // WHY: All tenant endpoints require an auth token.
  Options _authOptions(String? token) {
    if (token == null || token.isEmpty) {
      AppDebug.log("TENANT_API", "Missing auth token");
      throw Exception("Missing auth token");
    }

    return Options(headers: {"Authorization": "Bearer $token"});
  }

  /// ------------------------------------------------------
  /// FETCH TENANT ESTATE
  /// ------------------------------------------------------
  Future<TenantEstate> fetchTenantEstate({required String? token}) async {
    AppDebug.log("TENANT_API", "fetchTenantEstate() start");

    final resp = await _dio.get(
      "/business/tenant/estate",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final estateMap = (data["estate"] ?? {}) as Map<String, dynamic>;
    final estate = TenantEstate.fromJson(estateMap);

    AppDebug.log(
      "TENANT_API",
      "fetchTenantEstate() success",
      extra: {"estateId": estate.id},
    );

    return estate;
  }

  /// ------------------------------------------------------
  /// FETCH TENANT APPLICATION
  /// ------------------------------------------------------
  Future<business_tenant.BusinessTenantApplication?> fetchTenantApplication({
    required String? token,
  }) async {
    AppDebug.log("TENANT_API", "fetchTenantApplication() start");

    final resp = await _dio.get(
      "/business/tenant/application",
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final applicationMap = data["application"];

    if (applicationMap is Map<String, dynamic>) {
      final application = business_tenant.BusinessTenantApplication.fromJson(
        applicationMap,
      );
      AppDebug.log(
        "TENANT_API",
        "fetchTenantApplication() success",
        extra: {"applicationId": application.id, "status": application.status},
      );
      return application;
    }

    AppDebug.log("TENANT_API", "fetchTenantApplication() none");
    return null;
  }

  /// ------------------------------------------------------
  /// UPDATE TENANT APPLICATION
  /// ------------------------------------------------------
  Future<business_tenant.BusinessTenantApplication> updateTenantApplication({
    required String? token,
    required String unitType,
    required String rentPeriod,
    required String moveInDate,
    required List<TenantContact> references,
    required List<TenantContact> guarantors,
    required bool agreementSigned,
  }) async {
    AppDebug.log(
      "TENANT_API",
      "updateTenantApplication() start",
      extra: {
        "unitType": unitType,
        "rentPeriod": rentPeriod,
        "hasMoveInDate": moveInDate.isNotEmpty,
        "references": references.length,
        "guarantors": guarantors.length,
        "agreementSigned": agreementSigned,
      },
    );

    final resp = await _dio.patch(
      "/business/tenant/application",
      data: {
        "unitType": unitType,
        "rentPeriod": rentPeriod,
        "moveInDate": moveInDate,
        "references": references.map((item) => item.toJson()).toList(),
        "guarantors": guarantors.map((item) => item.toJson()).toList(),
        "agreementSigned": agreementSigned,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;
    final applicationMap = data["application"];
    if (applicationMap is! Map<String, dynamic>) {
      AppDebug.log("TENANT_API", "updateTenantApplication() missing payload");
      throw Exception("Missing updated application data");
    }

    final application = business_tenant.BusinessTenantApplication.fromJson(
      applicationMap,
    );

    AppDebug.log(
      "TENANT_API",
      "updateTenantApplication() success",
      extra: {"applicationId": application.id, "status": application.status},
    );

    return application;
  }

  /// ------------------------------------------------------
  /// SUBMIT TENANT VERIFICATION
  /// ------------------------------------------------------
  Future<Map<String, dynamic>> submitTenantVerification({
    required String? token,
    required String unitType,
    required String rentPeriod,
    required String moveInDate,
    required List<TenantContact> references,
    required List<TenantContact> guarantors,
    required bool agreementSigned,
  }) async {
    AppDebug.log(
      "TENANT_API",
      "submitTenantVerification() start",
      extra: {
        "unitType": unitType,
        "rentPeriod": rentPeriod,
        "hasMoveInDate": moveInDate.isNotEmpty,
        "references": references.length,
        "guarantors": guarantors.length,
        "agreementSigned": agreementSigned,
      },
    );

    final resp = await _dio.post(
      "/business/tenant/verify",
      data: {
        "unitType": unitType,
        "rentPeriod": rentPeriod,
        "moveInDate": moveInDate,
        "references": references.map((item) => item.toJson()).toList(),
        "guarantors": guarantors.map((item) => item.toJson()).toList(),
        "agreementSigned": agreementSigned,
      },
      options: _authOptions(token),
    );

    final data = resp.data as Map<String, dynamic>;

    AppDebug.log(
      "TENANT_API",
      "submitTenantVerification() success",
      extra: {"hasApplication": data["application"] != null},
    );

    return data;
  }
}
