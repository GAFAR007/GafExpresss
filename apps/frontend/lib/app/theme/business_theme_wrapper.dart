/// lib/app/theme/business_theme_wrapper.dart
/// ----------------------------------------
/// WHAT:
/// - Wraps business pages with the business theme when enabled.
///
/// WHY:
/// - Business theme should apply only to business routes.
/// - Keeps classic/dark UI for the rest of the app.
///
/// HOW:
/// - Reads appThemeModeProvider and conditionally applies AppTheme.business().
/// ----------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/theme/app_theme.dart';
import 'package:frontend/app/theme/app_theme_mode.dart';

class BusinessThemeWrapper extends ConsumerWidget {
  final Widget child;

  const BusinessThemeWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    AppDebug.log("THEME", "Business wrapper build", extra: {"mode": mode.name});

    // WHY: Only apply the business palette when the user picked that mode.
    if (mode == AppThemeMode.business) {
      return Theme(
        data: AppTheme.business(),
        child: child,
      );
    }

    return child;
  }
}
