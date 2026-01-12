/// lib/app/app.dart
/// ------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - The root widget of the entire app.
///
/// WHY IT'S IMPORTANT:
/// - This is where MaterialApp.router lives.
/// - Router is plugged here, so navigation works everywhere.
///
/// DEBUGGING:
/// - debugPrint("BOOT: AppRoot build") tells you UI is building.

import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import 'router.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("BOOT: AppRoot build()");

    final router = buildRouter();

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
