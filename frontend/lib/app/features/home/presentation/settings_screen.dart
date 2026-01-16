/// lib/app/features/home/presentation/settings_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Simple Settings screen placeholder.
///
/// WHY:
/// - Replaces the "Profile" slot from the reference layout.
/// - Provides a stable route target for bottom navigation.
///
/// HOW:
/// - Renders a list of tappable setting tiles.
/// - Logs taps for debugging and future wiring.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppDebug.log("SETTINGS", "build()");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("SETTINGS", "Back tapped");
            // WHY: Prefer popping if possible, otherwise return home.
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/home');
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // WHY: Group common actions to make the screen feel complete.
          _SettingsTile(
            icon: Icons.person,
            label: "Account",
            onTap: () {
              AppDebug.log("SETTINGS", "Account tapped");
            },
          ),
          _SettingsTile(
            icon: Icons.lock,
            label: "Privacy",
            onTap: () {
              AppDebug.log("SETTINGS", "Privacy tapped");
            },
          ),
          _SettingsTile(
            icon: Icons.notifications,
            label: "Notifications",
            onTap: () {
              AppDebug.log("SETTINGS", "Notifications tapped");
            },
          ),
          _SettingsTile(
            icon: Icons.help_outline,
            label: "Help & Support",
            onTap: () {
              AppDebug.log("SETTINGS", "Help tapped");
            },
          ),
          const SizedBox(height: 12),
          // WHY: Keep logout in settings so Home layout stays clean.
          _SettingsTile(
            icon: Icons.logout,
            label: "Logout",
            onTap: () async {
              AppDebug.log("SETTINGS", "Logout tapped");
              await ref.read(authSessionProvider.notifier).logout();

              if (!context.mounted) return;
              context.go("/login");
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      // WHY: Leading icon helps users scan the list quickly.
      leading: Icon(icon),
      // WHY: Label describes the destination clearly.
      title: Text(label),
      // WHY: Chevron reinforces that this is navigable.
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
