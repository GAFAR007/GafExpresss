/// lib/app/core/network/dio_client.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Creates and configures ONE Dio HTTP client.
///
/// WHY:
/// - All API calls must share:
///   - same baseUrl
///   - same timeouts
///   - same debug logging
///
/// HOW:
/// - buildDio() returns a configured Dio instance.
/// - Every feature (auth/products/etc) receives this Dio instance.
///
/// DEBUGGING:
/// - Logs every request method/url and response status.
/// - DOES NOT log passwords or tokens.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frontend/app/core/constants/app_constants.dart';

Dio buildDio() {
  final baseUrl = AppConstants.apiBaseUrl;

  debugPrint("NET: buildDio() baseUrl = $baseUrl");

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(milliseconds: AppConstants.connectTimeoutMs),
      receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeoutMs),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    ),
  );

  // ✅ Simple interceptor for debugging
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint(
          "NET: REQUEST → ${options.method} ${options.baseUrl}${options.path}",
        );

        // Avoid printing sensitive bodies. Print keys only.
        if (options.data is Map) {
          final keys = (options.data as Map).keys.toList();
          debugPrint("NET: REQUEST BODY keys → $keys");
        }

        return handler.next(options);
      },
      onResponse: (response, handler) {
        debugPrint(
          "NET: RESPONSE ← ${response.statusCode} ${response.requestOptions.path}",
        );
        return handler.next(response);
      },
      onError: (e, handler) {
        debugPrint("NET: ERROR ✗ ${e.message}");
        debugPrint("NET: ERROR url = ${e.requestOptions.uri}");
        if (e.response != null) {
          debugPrint("NET: ERROR status = ${e.response?.statusCode}");
          debugPrint("NET: ERROR data = ${e.response?.data}");
        }
        return handler.next(e);
      },
    ),
  );

  return dio;
}
