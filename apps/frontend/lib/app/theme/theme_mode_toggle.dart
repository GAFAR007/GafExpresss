/// lib/app/theme/theme_mode_toggle.dart
/// -----------------------------------
/// WHAT:
/// - UI toggle for Classic / Dark / Business theme modes.
///
/// WHY:
/// - Lets users switch themes without leaving the screen.
/// - Centralized control keeps UI behavior consistent.
///
/// HOW:
/// - Reads appThemeModeProvider and updates it on tap.
/// - Emits debug logs so the flow is traceable.
/// -----------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/theme/app_theme_mode.dart';

class ThemeModeToggle extends ConsumerWidget {
  final String source;

  const ThemeModeToggle({super.key, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    AppDebug.log(
      "THEME",
      "Toggle build",
      extra: {"mode": mode.name, "source": source},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Theme mode",
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          "Choose how the app should look. Business mode affects business pages only.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            _ThemeChip(
              label: "Classic",
              isActive: mode == AppThemeMode.classic,
              onTap: () => _setMode(
                ref,
                AppThemeMode.classic,
              ),
            ),
            _ThemeChip(
              label: "Dark",
              isActive: mode == AppThemeMode.dark,
              onTap: () => _setMode(
                ref,
                AppThemeMode.dark,
              ),
            ),
            _ThemeChip(
              label: "Business",
              isActive: mode == AppThemeMode.business,
              onTap: () => _setMode(
                ref,
                AppThemeMode.business,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setMode(WidgetRef ref, AppThemeMode mode) {
    AppDebug.log(
      "THEME",
      "Mode tap",
      extra: {"mode": mode.name, "source": source},
    );
    ref.read(appThemeModeProvider.notifier).setMode(mode, source: source);
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) => onTap(),
    );
  }
}
