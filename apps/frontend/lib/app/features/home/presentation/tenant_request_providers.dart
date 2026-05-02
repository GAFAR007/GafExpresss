/// lib/app/features/home/presentation/tenant_request_providers.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Providers for the public tenant request link flow.
///
/// WHY:
/// - Keeps API wiring out of the public request screen.
/// - Lets the screen use Riverpod caching for the link context.
/// -----------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

import 'tenant_request_api.dart';
import 'tenant_request_model.dart';

final tenantRequestApiProvider = Provider<TenantRequestApi>((ref) {
  AppDebug.log('PROVIDERS', 'tenantRequestApiProvider created');
  final dio = ref.read(dioProvider);
  return TenantRequestApi(dio: dio);
});

final tenantRequestLinkContextProvider =
    FutureProvider.family<TenantRequestLinkContext, String>((ref, token) async {
      AppDebug.log(
        'PROVIDERS',
        'tenantRequestLinkContextProvider fetch start',
        extra: {'hasToken': token.trim().isNotEmpty},
      );

      final api = ref.read(tenantRequestApiProvider);
      return api.fetchContext(token: token);
    });
