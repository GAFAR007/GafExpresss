/// lib/app/features/home/presentation/order_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for orders + payments.
///
/// WHY:
/// - Keeps API wiring in one place.
/// - UI widgets stay clean and focused.
///
/// HOW:
/// - orderApiProvider builds OrderApi with shared Dio.
/// - myOrdersProvider fetches the current user's orders.
///
/// DEBUGGING:
/// - Logs provider creation and fetch execution.
/// ------------------------------------------------------------
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'order_api.dart';
import 'order_model.dart';

final orderApiProvider = Provider<OrderApi>((ref) {
  AppDebug.log("PROVIDERS", "orderApiProvider created");
  final dio = ref.read(dioProvider);
  return OrderApi(dio: dio);
});

final myOrdersProvider = FutureProvider<List<Order>>((ref) async {
  AppDebug.log("PROVIDERS", "myOrdersProvider fetch start");

  final session = ref.watch(authSessionProvider);
  if (session == null) {
    AppDebug.log("PROVIDERS", "myOrdersProvider missing session");
    throw Exception("Not logged in");
  }

  final api = ref.read(orderApiProvider);
  return api.fetchMyOrders(token: session.token);
});
