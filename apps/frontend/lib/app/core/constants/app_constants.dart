/// lib/app/core/constants/app_constants.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Central place for constants used across the app.
///
/// WHY:
/// - Prevents duplicated strings everywhere.
/// - Lets you control base URLs/timeouts in ONE place.
///
/// IMPORTANT (MULTI-PLATFORM):
/// - Web + iOS simulator can use http://localhost:4000
/// - Android emulator CANNOT use localhost for your machine backend.
///   Android emulator must use: http://10.0.2.2:4000
/// - Real device must use your machine IP (same WiFi), e.g. http://192.168.0.24:4000
///
/// DEBUGGING:
/// - We will print the chosen baseUrl on app boot so you ALWAYS know what it is.
library;

import 'package:frontend/app/core/platform/platform_info.dart';

class AppConstants {
  AppConstants._();

  static const String _apiBaseUrlFromEnvironment = String.fromEnvironment(
    "API_BASE_URL",
  );
  static const String _paystackCallbackBaseUrlFromEnvironment =
      String.fromEnvironment("PAYSTACK_CALLBACK_BASE_URL");

  /// Base URLs you may need depending on where the app runs
  static const String _webOrIosBaseUrl = "http://localhost:4000";
  static const String _androidEmulatorBaseUrl = "http://10.0.2.2:4000";

  /// ✅ This is the single source of truth for the API base URL.
  ///
  /// HOW it decides:
  /// - If API_BASE_URL is provided at build time => use it
  /// - Otherwise if running on Android emulator => 10.0.2.2
  /// - Otherwise => localhost
  ///
  /// NOTE:
  /// - For production web builds, pass:
  ///   --dart-define=API_BASE_URL=https://api.gafarsexpress.gafarstechnologies.com
  /// - If you later test on real phone, change this to your laptop IP.
  static String get apiBaseUrl {
    final configuredBaseUrl = _normalizeBaseUrl(_apiBaseUrlFromEnvironment);
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    // PlatformInfo.isAndroid is true only on Android.
    // PlatformInfo.isWeb is true only on web.
    // Android emulator "localhost" points to the emulator itself, NOT your laptop.
    if (PlatformInfo.isAndroid && !PlatformInfo.isWeb) {
      return _androidEmulatorBaseUrl;
    }
    return _webOrIosBaseUrl;
  }

  /// Paystack callback base URL (public HTTPS).
  ///
  /// WHY:
  /// - Mobile WebView needs a public URL to intercept redirects.
  /// - Web already uses the current origin.
  ///
  /// NOTE:
  /// - For production builds, pass:
  ///   --dart-define=PAYSTACK_CALLBACK_BASE_URL=https://gafarsexpress.gafarstechnologies.com
  static String get paystackCallbackBaseUrl {
    return _normalizeBaseUrl(_paystackCallbackBaseUrlFromEnvironment);
  }

  /// Timeouts (safe defaults)
  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 20000;

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return "";
    return normalized.replaceFirst(RegExp(r"/+$"), "");
  }
}
