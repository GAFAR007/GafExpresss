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

  /// Base URLs you may need depending on where the app runs
  static const String _webOrIosBaseUrl = "http://localhost:4000";
  static const String _androidEmulatorBaseUrl = "http://10.0.2.2:4000";

  /// Paystack callback base URL (public HTTPS).
  ///
  /// WHY:
  /// - Mobile WebView needs a public URL to intercept redirects.
  /// - Update this when your ngrok domain changes.
  static const String paystackCallbackBaseUrl =
      "https://your-ngrok-domain.ngrok-free.dev";

  /// ✅ This is the single source of truth for the API base URL.
  ///
  /// HOW it decides:
  /// - If running on Android emulator => 10.0.2.2
  /// - Otherwise => localhost
  ///
  /// NOTE:
  /// - If you later test on real phone, change this to your laptop IP.
  static String get apiBaseUrl {
    // PlatformInfo.isAndroid is true only on Android.
    // PlatformInfo.isWeb is true only on web.
    // Android emulator "localhost" points to the emulator itself, NOT your laptop.
    if (PlatformInfo.isAndroid && !PlatformInfo.isWeb) {
      return _androidEmulatorBaseUrl;
    }
    return _webOrIosBaseUrl;
  }

  /// Timeouts (safe defaults)
  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 20000;
}
