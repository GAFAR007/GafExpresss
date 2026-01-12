/// lib/app/core/network/network_providers.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Riverpod providers for networking (Dio).
///
/// WHY:
/// - Keeps dependencies injectable and testable.
/// - Any feature can `ref.read(dioProvider)` and get the same Dio.
///
/// DEBUGGING:
/// - Provider creation is logged so you can see it in console.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dio_client.dart';

final dioProvider = Provider<Dio>((ref) {
  debugPrint("PROVIDER: dioProvider created");
  return buildDio();
});
