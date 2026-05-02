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
  bool _bootReady = false;

  @override
  void initState() {
    super.initState();
    _bootstrapApp();
  }

  Future<void> _bootstrapApp() async {
    AppDebug.log("BOOT", "bootstrap() start");
    try {
      await Future.wait([
        ref.read(authSessionProvider.notifier).restoreSession(),
        ref.read(appThemeModeProvider.notifier).load(),
      ]);
    } catch (error) {
      AppDebug.log("BOOT", "bootstrap() failed", extra: {"error": "$error"});
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _bootReady = true;
    });
    AppDebug.log("BOOT", "bootstrap() complete");
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BOOT", "AppRoot build()", extra: {"bootReady": _bootReady});
    final mode = ref.watch(appThemeModeProvider);
    final themeMode = mode == AppThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    AppDebug.log("THEME", "AppRoot theme", extra: {"mode": mode.name});

    if (!_bootReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          // WHY: Route pages must receive tight screen constraints; otherwise
          // nested Scaffolds can shrink and pull footer actions under system UI.
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            const ChatCallOverlayHost(),
          ],
        );
      },
    );
  }
}
