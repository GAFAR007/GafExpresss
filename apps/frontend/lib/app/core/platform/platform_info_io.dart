/// lib/app/core/platform/platform_info_io.dart
/// -------------------------------------------
/// WHAT:
/// - Mobile/Desktop implementation using `dart:io`.
///
/// WHY:
/// - Only non-web platforms can use `dart:io`.
///
/// HOW:
/// - Uses Platform.isAndroid / Platform.isIOS.
library;
import 'dart:io' show Platform;

const bool platformIsWeb = false;
final bool platformIsAndroid = Platform.isAndroid;
final bool platformIsIOS = Platform.isIOS;
final String platformName = Platform.isAndroid
    ? "android"
    : Platform.isIOS
    ? "ios"
    : "io";
