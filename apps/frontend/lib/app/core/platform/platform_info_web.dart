/// lib/app/core/platform/platform_info_web.dart
/// --------------------------------------------
/// WHAT:
/// - Web implementation.
///
/// WHY:
/// - Web cannot import `dart:io`.
///
/// HOW:
/// - Hardcode web=true and others false.
const bool platformIsWeb = true;
const bool platformIsAndroid = false;
const bool platformIsIOS = false;
const String platformName = "web";
