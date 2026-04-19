/// lib/app/app.dart
/// ------------------------------------------------------------
/// WHAT THIS FILE IS:
/// - The root widget of the entire app.
///
/// WHY IT'S IMPORTANT:
/// - This is where MaterialApp.router lives.
/// - Router is plugged here, so navigation works everywhere.
///
/// HOW IT WORKS:
/// - Restores session on boot, then builds router-aware MaterialApp.
///
/// DEBUGGING:
/// - Logs AppRoot build + session restore.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import '../app/theme/app_theme.dart';
import 'package:frontend/app/theme/app_theme_mode.dart';
import 'router.dart';
import 'features/home/presentation/chat_call_overlay.dart';
import 'features/home/presentation/presentation/providers/auth_providers.dart';

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  @override
  void initState() {
    super.initState();

    // WHY: restore session once on app boot.
    Future.microtask(() async {
      AppDebug.log("BOOT", "Restoring session");
      await ref.read(authSessionProvider.notifier).restoreSession();
    });

    // WHY: Load persisted theme mode once on app boot.
    Future.microtask(() async {
      AppDebug.log("THEME", "Boot load requested");
      await ref.read(appThemeModeProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BOOT", "AppRoot build()");

    final router = ref.watch(routerProvider);
    final mode = ref.watch(appThemeModeProvider);
    final themeMode = mode == AppThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    AppDebug.log("THEME", "AppRoot theme", extra: {"mode": mode.name});

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const ChatCallOverlayHost(),
          ],
        );
      },
    );
  }
}
