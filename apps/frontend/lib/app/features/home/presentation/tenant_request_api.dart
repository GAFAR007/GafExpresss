/// lib/app/features/home/presentation/tenant_request_api.dart
/// -----------------------------------------------------------
/// WHAT:
/// - API client for the public tenant-request link flow.
///
/// WHY:
/// - Keeps unauthenticated link loading and submission out of the widget.
/// - Centralizes payload shaping for the public intake form.
///
/// HOW:
/// - GET /tenant-request-links/:token to load estate + unit context.
/// - POST /tenant-request-links/:token/submit to store a public request.
/// -----------------------------------------------------------
library;

import 'package:dio/dio.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_tenant_model.dart';
import 'package:frontend/app/features/home/presentation/tenant_document_picker.dart';
import 'tenant_request_model.dart';

class TenantRequestApi {
  final Dio _dio;

  TenantRequestApi({required Dio dio}) : _dio = dio;

  Future<TenantRequestLinkContext> fetchContext({required String token}) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw Exception('Tenant request token is required');
    }

    AppDebug.log(
      'TENANT_REQUEST_API',
      'fetchContext() start',
      extra: {'hasToken': true},
    );

    final resp = await _dio.get('/tenant-request-links/$trimmedToken');
    final data = resp.data as Map<String, dynamic>;
    final context = TenantRequestLinkContext.fromJson(data);

    AppDebug.log(
      'TENANT_REQUEST_API',
      'fetchContext() success',
      extra: {
        'estateAssetId': context.estateAssetId,
        'unitCount': context.unitMix.length,
      },
    );

    return context;
  }

  Future<BusinessTenantApplication> submitRequest({
    required String token,
    required String firstName,
    String? middleName,
    required String lastName,
    required DateTime dob,
    required String nin,
    required String unitType,
    required PickedDocumentData document,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw Exception('Tenant request token is required');
    }

    AppDebug.log(
      'TENANT_REQUEST_API',
      'submitRequest() start',
      extra: {'hasToken': true, 'hasDocument': document.bytes.isNotEmpty},
    );

    final formData = FormData.fromMap({
      'firstName': firstName.trim(),
      if (middleName != null && middleName.trim().isNotEmpty)
        'middleName': middleName.trim(),
      'lastName': lastName.trim(),
      'dob': DateTime(dob.year, dob.month, dob.day).toIso8601String(),
      'nin': nin.trim(),
      'unitType': unitType.trim(),
      'document': MultipartFile.fromBytes(
        document.bytes,
        filename: document.filename,
      ),
    });

    final resp = await _dio.post(
      '/tenant-request-links/$trimmedToken/submit',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = resp.data as Map<String, dynamic>;
    final appMap = (data['application'] ?? {}) as Map<String, dynamic>;
    final application = BusinessTenantApplication.fromJson(appMap);

    AppDebug.log(
      'TENANT_REQUEST_API',
      'submitRequest() success',
      extra: {'applicationId': application.id},
    );

    return application;
  }
}
