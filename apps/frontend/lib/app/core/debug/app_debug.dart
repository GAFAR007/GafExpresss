/// lib/app/core/debug/app_debug.dart
/// --------------------------------
/// WHAT THIS FILE IS:
/// - A tiny debug logger wrapper around `debugPrint`.
///
/// WHY IT'S IMPORTANT:
/// - You said you want to ALWAYS know where the app breaks.
/// - Using one logger means every file prints the same way.
/// - Works on Android / iOS / Web.
///
/// HOW IT WORKS:
/// - Call: AppDebug.log("TAG", "message", extra: {...});
/// - It prints a timestamp + tag + message.
///
/// NOTE:
/// - We NEVER log passwords or tokens here.
library;

import 'package:flutter/foundation.dart';

class AppDebug {
  static void log(String tag, String message, {Map<String, Object?>? extra}) {
    final time = DateTime.now().toIso8601String();
    final extraText = (extra == null || extra.isEmpty) ? "" : " | extra=$extra";
    debugPrint("[$time] $tag: $message$extraText");
  }
}
