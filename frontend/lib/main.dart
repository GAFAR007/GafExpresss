/// lib/main.dart
/// ------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - The app entry point (first code Flutter runs).
///
/// WHY IT'S IMPORTANT:
/// - If this file fails, nothing boots.
/// - Riverpod NEEDS ProviderScope at the top, otherwise ref.read/ref.watch crashes.
///
/// DEBUGGING STRATEGY:
/// - Logs confirm:
///   1) main() started
///   2) Correct apiBaseUrl selected (Web / Android / iOS)
///   3) ProviderScope is actually wrapping the app
///   4) runApp() executed
///
/// MULTI-PLATFORM SAFETY:
/// - Works on Web, Android, iOS.
/// - No `dart:io` usage here.
/// ------------------------------------------------------------

// ignore_for_file: dangling_library_doc_comments

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // ✅ REQUIRED for ProviderScope

import 'app/app.dart';
import 'app/core/constants/app_constants.dart';

void main() {
  // ------------------------------------------------------------
  // BOOT CONFIRMATION
  // ------------------------------------------------------------
  debugPrint("BOOT: main() started");

  // ------------------------------------------------------------
  // ENVIRONMENT CONFIRMATION
  // ------------------------------------------------------------

  //   // This tells us WHICH backend URL is being used.
  //   // - Web            -> http://localhost:4000
  //   // - Android emu    -> http://10.0.2.2:4000
  //   // - iOS simulator  -> http://localhost:4000
  debugPrint("BOOT: apiBaseUrl = ${AppConstants.apiBaseUrl}");

  // ------------------------------------------------------------
  // START THE APP (WITH RIVERPOD)
  // ------------------------------------------------------------
  // ✅ This is the fix:
  // Riverpod providers (ref.read/ref.watch) ONLY work if the app
  // is wrapped in ProviderScope at the top level.
  debugPrint("BOOT: Wrapping AppRoot with ProviderScope()");

  runApp(const ProviderScope(child: AppRoot()));

  debugPrint("BOOT: runApp() called");
}
