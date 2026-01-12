/// lib/app/features/home/presentation/presentation/providers/auth_providers.dart
/// ---------------------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - Riverpod providers that “wire up” networking + AuthApi for the whole app.
///
/// WHY IT'S IMPORTANT:
/// - Keeps creation of Dio/AuthApi in ONE place.
/// - Prevents “import madness” across screens.
/// - Makes it easy to swap baseUrl per platform (Web / Android / iOS).
///
/// HOW IT WORKS:
/// - dioProvider -> creates a single Dio configured with correct baseUrl.
/// - authApiProvider -> builds AuthApi using the Dio from dioProvider.
///
/// DEBUGGING:
/// - Logs when providers are created so we know the app is wired correctly.
///
/// PLATFORM SAFETY:
/// - Works on Web, Android, iOS (no dart:io used here).
/// ---------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/network/dio_client.dart';
import 'package:frontend/app/features/auth/data/auth_api.dart';

/// Provides ONE Dio instance for the app.
///
/// WHY:
/// - Dio holds interceptors, baseUrl, timeouts.
/// - We want ONE consistent networking setup everywhere.
final dioProvider = Provider((ref) {
  AppDebug.log("PROVIDERS", "dioProvider created -> building Dio");
  final dio = buildDio(); // from lib/app/core/network/dio_client.dart
  AppDebug.log("PROVIDERS", "dioProvider ready");
  return dio;
});

/// Provides AuthApi using the shared Dio.
///
/// WHY:
/// - Screens should never create Dio/AuthApi manually.
/// - They just do: ref.read(authApiProvider).login(...)
final authApiProvider = Provider((ref) {
  AppDebug.log("PROVIDERS", "authApiProvider created -> building AuthApi");
  final dio = ref.read(dioProvider);
  final api = AuthApi(dio: dio);
  AppDebug.log("PROVIDERS", "authApiProvider ready");
  return api;
});
