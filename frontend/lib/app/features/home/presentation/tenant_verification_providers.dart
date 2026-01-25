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
