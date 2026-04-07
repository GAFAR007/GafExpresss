/// lib/app/features/home/presentation/purchase_request_providers.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Riverpod provider wiring for purchase-request APIs.
///
/// WHY:
/// - Keeps the request-to-buy API setup consistent with other feature APIs.
///
/// HOW:
/// - Builds PurchaseRequestApi from the shared Dio provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_api.dart';

final purchaseRequestApiProvider = Provider<PurchaseRequestApi>((ref) {
  AppDebug.log("PROVIDERS", "purchaseRequestApiProvider created");
  final dio = ref.read(dioProvider);
  return PurchaseRequestApi(dio: dio);
});
