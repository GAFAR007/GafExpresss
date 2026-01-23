/// lib/app/features/home/presentation/business_order_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for business orders.
///
/// WHY:
/// - Keeps API wiring + filters in one place.
/// - Lets the UI stay focused on rendering.
///
/// HOW:
/// - businessOrderApiProvider builds BusinessOrderApi with shared Dio.
/// - businessOrderStatusFilterProvider stores current filter.
/// - businessOrdersProvider fetches orders using the filter.
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// ------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/business_order_api.dart';

final businessOrderApiProvider = Provider<BusinessOrderApi>((ref) {
  AppDebug.log("PROVIDERS", "businessOrderApiProvider created");
  final dio = ref.read(dioProvider);
  return BusinessOrderApi(dio: dio);
});

// WHY: Tracks the selected status filter (null = all).
final businessOrderStatusFilterProvider = StateProvider<String?>((ref) => null);

final businessOrdersProvider = FutureProvider<BusinessOrdersResult>((ref) async {
  AppDebug.log("PROVIDERS", "businessOrdersProvider fetch start");

  final session = ref.watch(authSessionProvider);
  if (session == null) {
    AppDebug.log("PROVIDERS", "businessOrdersProvider missing session");
    throw Exception("Not logged in");
  }

  final status = ref.watch(businessOrderStatusFilterProvider);
  final api = ref.read(businessOrderApiProvider);
  return api.fetchBusinessOrders(token: session.token, status: status);
});
