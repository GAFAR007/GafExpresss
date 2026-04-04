///
///
/// /// lib/app/core/platform/platform_info.dart
/// ----------------------------------------
/// WHAT:
/// - A safe "platform detector" that works on Web + iOS + Android.
///
/// WHY:
/// - `dart:io` (Platform.isAndroid) breaks Web.
/// - So we use conditional imports: web uses a web file, mobile uses an io file.
///
/// HOW:
/// - When compiling for Web -> it imports platform_info_web.dart
/// - When compiling for Mobile/Desktop -> it imports platform_info_io.dart
///
/// DEBUGGING:
/// - We print what platform we think we are on (safe info only).
library;

import 'platform_info_stub.dart'
    if (dart.library.html) 'platform_info_web.dart'
    if (dart.library.io) 'platform_info_io.dart';

abstract class PlatformInfo {
  static bool get isWeb => platformIsWeb;
  static bool get isAndroid => platformIsAndroid;
  static bool get isIOS => platformIsIOS;

  static String get name => platformName;
}
