// ignore: dangling_library_doc_comments
/// lib/features/home/presentation/home_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Home screen (post-login landing).
///
/// WHY:
/// - Confirms protected routes work.
/// - Provides logout action to clear session.
///
/// HOW:
/// - Reads auth session provider and triggers logout on button tap.
///
/// DEBUGGING:
/// - Logs build and logout tap.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("HOME", "build()");

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Home ✅"),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                AppDebug.log("HOME", "Logout tapped");
                await ref.read(authSessionProvider.notifier).logout();

                if (!context.mounted) return;
                context.go('/login');
              },
              child: const Text("Logout"),
            ),
          ],
        ),
      ),
    );
  }
}
